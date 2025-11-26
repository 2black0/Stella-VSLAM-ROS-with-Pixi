#!/usr/bin/env python3
"""Pymavlink bridge for socket_viewer."""

import base64
import csv
import io
import json
import os
import queue
import sys
import threading
import time
from typing import Any, Dict, Optional

from pymavlink import mavutil

DEFAULT_CONNECTION = os.getenv(
    "PYMAVLINK_CONNECTION",
    os.getenv("MAVLINK_CONNECTION", "udp:127.0.0.1:14551"),
)
HEARTBEAT_TIMEOUT = float(os.getenv("PYMAVLINK_HEARTBEAT_TIMEOUT", "10"))
MODE_EXTRA_FLAGS = {
    "GUIDED": mavutil.mavlink.MAV_MODE_FLAG_GUIDED_ENABLED,
    "AUTO": mavutil.mavlink.MAV_MODE_FLAG_AUTO_ENABLED,
    "RTL": mavutil.mavlink.MAV_MODE_FLAG_AUTO_ENABLED,
    "STABILIZE": mavutil.mavlink.MAV_MODE_FLAG_STABILIZE_ENABLED,
}
STATUS_HOLD_SECONDS = float(os.getenv("PYMAVLINK_STATUS_HOLD_SECONDS", "4"))


def emit(payload: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def log(message: str, level: str = "info") -> None:
    emit({"type": "log", "level": level, "message": message})


class PymavlinkBridge:
    def __init__(self, connection_string: str) -> None:
        self.connection_string = connection_string
        self.master: Optional[mavutil.mavfile] = None
        self.command_queue: "queue.Queue[Dict[str, Any]]" = queue.Queue()
        self.state: Dict[str, Any] = {
            "lat": None,
            "lon": None,
            "alt": None,
            "relative_alt": None,
            "gps_fix_type": None,
            "satellites_visible": None,
            "hdop": None,
            "baro_alt": None,
            "heading": None,
            "climb": None,
            "last_slam_timestamp": None,
            "last_slam_host_timestamp": None,
            "last_slam_delta_ms": None,
            "last_gps_host_timestamp": None,
            "last_gps_vehicle_timestamp": None,
            "last_gps_vehicle_skew_ms": None,
            "last_log_delta_ms": None,
            "armed": False,
            "ready": False,
            "status": "Idle",
            "system_status": "Unknown",
            "mode": "Unknown",
            "mode_id": None,
            "system_id": None,
            "component_id": None,
            "statusTimestamp": None,
        }
        self._debug_timing = bool(int(os.getenv("PYMAVLINK_DEBUG_TIMING", "0")))
        self._vehicle_boot_offset = None
        self._last_vehicle_boot_ms = None
        self._status_hold_until = 0.0
        self.master_lock = threading.Lock()
        self.logging_active = False
        self.csv_rows = []
        self.latest_slam = {
            "timestamp": None,
            "x": None,
            "y": None,
            "z": None,
            "qw": None,
            "qx": None,
            "qy": None,
            "qz": None,
        }
        self.latest_mav = {
            "timestamp": None,
            "lat": None,
            "lon": None,
            "alt": None,
            "rel": None,
        }

    def connect(self) -> None:
        while True:
            try:
                log(f"Connecting to {self.connection_string}")
                self.master = mavutil.mavlink_connection(self.connection_string)
                hb = self.master.wait_heartbeat(timeout=HEARTBEAT_TIMEOUT)
                log(
                    f"Connected (sys={self.master.target_system} comp={self.master.target_component})"
                )
                if hb:
                    self.state["mode"] = mavutil.mode_string_v10(hb) or "UNKNOWN"
                    self.state["mode_id"] = getattr(hb, "custom_mode", None)
                    self.state["system_id"] = hb.get_srcSystem()
                    self.state["component_id"] = hb.get_srcComponent()
                    self.emit_state()
                return
            except Exception as exc:  # pylint: disable=broad-except
                log(f"Connection failed: {exc}", level="error")
                time.sleep(2)

    def emit_state(self) -> None:
        emit({"type": "telemetry", "data": {**self.state}})

    def update_status(self, text: str, hold_seconds: float = None) -> None:
        hold = STATUS_HOLD_SECONDS if hold_seconds is None else hold_seconds
        self.state["status"] = text
        self.state["statusTimestamp"] = int(time.time() * 1000)
        self._status_hold_until = time.monotonic() + hold
        self.emit_state()

    def stdin_listener(self) -> None:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
                self.command_queue.put(payload)
            except Exception as exc:  # pylint: disable=broad-except
                log(f"Invalid command payload: {exc}", level="error")

    def process_commands(self) -> None:
        while True:
            try:
                payload = self.command_queue.get_nowait()
            except queue.Empty:
                break
            threading.Thread(
                target=self.execute_command, args=(payload,), daemon=True
            ).start()

    def execute_command(self, payload: Dict[str, Any]) -> None:
        command_type = payload.get("type")
        request_id = payload.get("request_id")
        result_type = {
            "set_mode": "mode_result",
            "takeoff": "takeoff_result",
            "csv_start": "csv_start_result",
            "csv_stop": "csv_stop_result",
        }.get(command_type)
        try:
            result_payload = self.handle_command(payload)
            if result_type:
                response = {"type": result_type, "ok": True, "request_id": request_id}
                if isinstance(result_payload, dict):
                    response.update(result_payload)
                emit(response)
        except Exception as exc:  # pylint: disable=broad-except
            if result_type:
                emit(
                    {
                        "type": result_type,
                        "ok": False,
                        "request_id": request_id,
                        "error": str(exc),
                    }
                )
            log(f"Command {command_type} failed: {exc}", level="error")

    def handle_command(self, payload: Dict[str, Any]) -> None:
        command_type = payload.get("type")
        if command_type == "set_mode":
            mode_name = str(payload.get("mode") or "").strip().upper()
            self.set_mode(mode_name)
        elif command_type == "takeoff":
            altitude = payload.get("altitude")
            try:
                altitude_value = float(altitude)
            except (TypeError, ValueError):
                altitude_value = 30.0
            altitude_value = altitude_value if altitude_value > 0 else 30.0
            self.takeoff_sequence(altitude_value)
        elif command_type == "slam_pose":
            self.store_slam_pose(payload.get("data"))
        elif command_type == "csv_start":
            return self.start_csv_logging()
        elif command_type == "csv_stop":
            return self.stop_csv_logging()

    def set_mode(self, mode_name: str) -> None:
        if not self.master:
            raise RuntimeError("Vehicle connection not ready")
        if not mode_name:
            raise ValueError("Mode name is required")
        mapping = self.master.mode_mapping() or {}
        if mode_name not in mapping:
            raise ValueError(f"Mode '{mode_name}' not supported")
        mode_id = mapping[mode_name]
        base_mode = mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
        extra_flag = MODE_EXTRA_FLAGS.get(mode_name)
        if extra_flag:
            base_mode |= extra_flag
        with self.master_lock:
            self.master.mav.command_long_send(
                self.master.target_system,
                self.master.target_component,
                mavutil.mavlink.MAV_CMD_DO_SET_MODE,
                0,
                base_mode,
                mode_id,
                0,
                0,
                0,
                0,
                0,
            )
            self.master.mav.set_mode_send(
                self.master.target_system,
                base_mode,
                mode_id,
            )

    def takeoff_sequence(self, altitude: float) -> None:
        if not self.master:
            raise RuntimeError("Vehicle connection not ready")
        target_text = f"{altitude:.1f}".rstrip("0").rstrip(".")
        self.update_status("TAKEOFF: switching to GUIDED")
        self.set_mode("GUIDED")
        self.wait_until(
            lambda: (self.state.get("mode") or "").upper() == "GUIDED",
            timeout=15,
            description="mode GUIDED",
        )
        self.update_status("TAKEOFF: waiting for vehicle ready")
        self.wait_until(
            lambda: bool(self.state.get("ready")),
            timeout=15,
            description="vehicle ready",
        )
        self.update_status("TAKEOFF: arming motors")
        self.arm(True)
        self.wait_until(
            lambda: bool(self.state.get("armed")),
            timeout=20,
            description="vehicle arm",
        )
        self.update_status(f"TAKEOFF: climbing to {target_text} m")
        self.send_takeoff_command(altitude)
        self.wait_until(
            lambda: (self.state.get("relative_alt") or 0) >= altitude * 0.95,
            timeout=90,
            description="target altitude",
        )
        self.update_status("TAKEOFF: sequence complete", hold_seconds=6)

    def arm(self, should_arm: bool) -> None:
        if not self.master:
            raise RuntimeError("Vehicle connection not ready")
        with self.master_lock:
            self.master.mav.command_long_send(
                self.master.target_system,
                self.master.target_component,
                mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                0,
                1 if should_arm else 0,
                0,
                0,
                0,
                0,
                0,
                0,
            )

    def send_takeoff_command(self, altitude: float) -> None:
        if not self.master:
            raise RuntimeError("Vehicle connection not ready")
        with self.master_lock:
            self.master.mav.command_long_send(
                self.master.target_system,
                self.master.target_component,
                mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                altitude,
            )

    def wait_until(
        self, predicate, timeout: float, description: str = "condition", interval: float = 0.5
    ) -> None:
        end_time = time.monotonic() + timeout
        while time.monotonic() <= end_time:
            if predicate():
                return
            time.sleep(interval)
        raise TimeoutError(f"Timed out waiting for {description}")

    def store_slam_pose(self, payload: Optional[Dict[str, Any]]) -> None:
        if not payload:
            return
        timestamp = self._safe_float(payload.get("timestamp"))
        if timestamp is None:
            timestamp = int(time.time() * 1000)
        else:
            timestamp = int(timestamp)
            if timestamp < 1e12:  # assume payload in seconds
                timestamp = int(timestamp * 1000)
        x = self._safe_float(payload.get("x"))
        y = self._safe_float(payload.get("y"))
        z = self._safe_float(payload.get("z"))
        qw = self._safe_float(payload.get("qw"))
        qx = self._safe_float(payload.get("qx"))
        qy = self._safe_float(payload.get("qy"))
        qz = self._safe_float(payload.get("qz"))
        if x is None or y is None or z is None:
            return
        host_now = int(time.time() * 1000)
        delta = host_now - timestamp
        self.state["last_slam_timestamp"] = timestamp
        self.state["last_slam_host_timestamp"] = host_now
        self.state["last_slam_delta_ms"] = delta
        if self._debug_timing and abs(delta) > 250:
            log(f"SLAM timestamp skew {delta} ms (payload={timestamp})", level="error")
        self.latest_slam = {
            "timestamp": int(timestamp),
            "x": x,
            "y": y,
            "z": z,
            "qw": qw,
            "qx": qx,
            "qy": qy,
            "qz": qz,
        }
        if self.logging_active:
            self.append_log_row()

    def start_csv_logging(self) -> None:
        self.csv_rows = []
        self.logging_active = True
        self.update_status("CSV: recording", hold_seconds=2)
        return {"status": "started"}

    def stop_csv_logging(self) -> Dict[str, Any]:
        if not self.logging_active:
            raise RuntimeError("CSV belum dimulai")
        self.logging_active = False
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(
            [
                "timestamp_log",
                "timestamp_slam",
                "slam_x",
                "slam_y",
                "slam_z",
                "timestamp_mavlink",
                "gps_lat",
                "gps_lon",
                "gps_alt",
                "gps_alt_rel",
            ]
        )
        writer.writerows(self.csv_rows)
        csv_text = output.getvalue()
        self.csv_rows = []
        file_name = f"slam-log-{int(time.time())}.csv"
        encoded = base64.b64encode(csv_text.encode("utf-8")).decode("ascii")
        return {"csv": encoded, "file_name": file_name}

    def append_log_row(self) -> None:
        slam = self.latest_slam
        mav = self.latest_mav
        if (
            slam.get("timestamp") is None
            or slam.get("x") is None
            or slam.get("y") is None
            or slam.get("z") is None
        ):
            return
        log_time = int(time.time() * 1000)
        log_vs_slam = log_time - slam["timestamp"]
        self.state["last_log_delta_ms"] = log_vs_slam
        if self._debug_timing and abs(log_vs_slam) > 250:
            log(
                f"LOG timestamp vs SLAM skew {log_vs_slam} ms "
                f"(slam={slam['timestamp']} log={log_time})",
                level="error",
            )
        row = [
            log_time,
            slam["timestamp"],
            slam["x"],
            slam["y"],
            slam["z"],
            mav.get("timestamp"),
            mav.get("lat"),
            mav.get("lon"),
            mav.get("alt"),
            mav.get("rel"),
        ]
        self.csv_rows.append(row)

    @staticmethod
    def _safe_float(value: Any) -> Optional[float]:
        try:
            if value is None:
                return None
            return float(value)
        except (TypeError, ValueError):
            return None

    def handle_message(self, msg: mavutil.mavlink.MAVLink_message) -> None:
        mtype = msg.get_type()
        if mtype == "HEARTBEAT":
            base_mode = getattr(msg, "base_mode", 0)
            system_status = getattr(msg, "system_status", None)
            self.state["armed"] = bool(
                base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
            )
            self.state["ready"] = system_status in (
                mavutil.mavlink.MAV_STATE_STANDBY,
                mavutil.mavlink.MAV_STATE_ACTIVE,
            )
            if system_status is not None:
                status_enum = mavutil.mavlink.enums.get("MAV_STATE", {})
                enum_entry = status_enum.get(system_status)
                self.state["system_status"] = getattr(enum_entry, "name", str(system_status))
                if time.monotonic() >= self._status_hold_until:
                    self.state["status"] = self.state["system_status"]
                    self.state["statusTimestamp"] = int(time.time() * 1000)
            self.state["mode"] = mavutil.mode_string_v10(msg) or "UNKNOWN"
            self.state["mode_id"] = getattr(msg, "custom_mode", None)
            self.state["system_id"] = msg.get_srcSystem()
            self.state["component_id"] = msg.get_srcComponent()
            self.emit_state()
            return
        if mtype == "GLOBAL_POSITION_INT":
            lat = getattr(msg, "lat", None)
            lon = getattr(msg, "lon", None)
            alt = getattr(msg, "alt", None)
            rel = getattr(msg, "relative_alt", None)
            self.state["lat"] = lat / 1e7 if lat is not None else None
            self.state["lon"] = lon / 1e7 if lon is not None else None
            self.state["alt"] = alt / 1000 if alt is not None else None
            self.state["relative_alt"] = rel / 1000 if rel is not None else None
            now_ms = int(time.time() * 1000)
            vehicle_boot = getattr(msg, "time_boot_ms", None)
            skew_ms = None
            if isinstance(vehicle_boot, (int, float)):
                vehicle_boot = int(vehicle_boot)
                if (
                    self._vehicle_boot_offset is None
                    or self._last_vehicle_boot_ms is None
                    or vehicle_boot < self._last_vehicle_boot_ms
                ):
                    self._vehicle_boot_offset = now_ms - vehicle_boot
                self._last_vehicle_boot_ms = vehicle_boot
                estimated_host = self._vehicle_boot_offset + vehicle_boot
                skew_ms = now_ms - estimated_host
                if self._debug_timing and abs(skew_ms) > 250:
                    log(
                        f"GPS timestamp skew {skew_ms} ms "
                        f"(vehicle_boot={vehicle_boot} offset={self._vehicle_boot_offset})",
                        level="error",
                    )
            timestamp = now_ms
            self.state["last_gps_host_timestamp"] = now_ms
            self.state["last_gps_vehicle_timestamp"] = (
                (vehicle_boot + (self._vehicle_boot_offset or 0)) if vehicle_boot is not None else None
            )
            self.state["last_gps_vehicle_skew_ms"] = skew_ms
            self.latest_mav = {
                "timestamp": timestamp,
                "lat": self.state["lat"],
                "lon": self.state["lon"],
                "alt": self.state["alt"],
                "rel": self.state["relative_alt"],
            }
            self.emit_state()
            return
        if mtype == "GPS_RAW_INT":
            fix_type = getattr(msg, "fix_type", None)
            self.state["gps_fix_type"] = fix_type
            self.state["satellites_visible"] = getattr(msg, "satellites_visible", None)
            eph = getattr(msg, "eph", None)
            hdop = None
            if eph is not None and eph != 65535:
                try:
                    hdop = float(eph) / 100.0
                except (TypeError, ValueError):
                    hdop = None
            self.state["hdop"] = hdop
            self.emit_state()
            return
        if mtype == "VFR_HUD":
            self.state["heading"] = self._safe_float(getattr(msg, "heading", None))
            self.state["baro_alt"] = self._safe_float(getattr(msg, "alt", None))
            self.state["climb"] = self._safe_float(getattr(msg, "climb", None))
            self.emit_state()
            return

    def run(self) -> None:
        threading.Thread(target=self.stdin_listener, daemon=True).start()
        while True:
            try:
                self.connect()
                while True:
                    if not self.master:
                        break
                    msg = None
                    with self.master_lock:
                        if self.master:
                            msg = self.master.recv_match(blocking=True, timeout=1)
                    if msg:
                        self.handle_message(msg)
                    self.process_commands()
            except Exception as exc:  # pylint: disable=broad-except
                log(f"Bridge loop error: {exc}", level="error")
            except KeyboardInterrupt:
                log("Bridge interrupted", level="error")
                break
            finally:
                if self.master:
                    try:
                        self.master.close()
                    except Exception:  # pylint: disable=broad-except
                        pass
                    self.master = None
                time.sleep(2)


def main() -> None:
    bridge = PymavlinkBridge(DEFAULT_CONNECTION)
    try:
        bridge.run()
    except KeyboardInterrupt:
        log("Bridge terminated by KeyboardInterrupt", level="error")


if __name__ == "__main__":
    main()
