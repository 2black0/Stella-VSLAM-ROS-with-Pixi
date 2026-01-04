'use strict';

const EventEmitter = require('events');
const { spawn } = require('child_process');
const path = require('path');

const PYTHON_BIN = process.env.PYMAVLINK_PYTHON || process.env.PYTHON || 'python3';
const BRIDGE_PATH = path.join(__dirname, '..', 'pymavlink_bridge.py');
const BRIDGE_RESTART_DELAY = Number(process.env.PYMAVLINK_BRIDGE_RESTART_MS || 3000);
const MODE_REQUEST_TIMEOUT = Number(process.env.PYMAVLINK_MODE_TIMEOUT_MS || 10000);
const TAKEOFF_REQUEST_TIMEOUT = Number(
  process.env.PYMAVLINK_TAKEOFF_TIMEOUT_MS || 120000
);
const CSV_START_TIMEOUT = Number(process.env.PYMAVLINK_CSV_START_TIMEOUT_MS || 5000);
const CSV_STOP_TIMEOUT = Number(process.env.PYMAVLINK_CSV_STOP_TIMEOUT_MS || 20000);

class MavlinkTelemetry extends EventEmitter {
  constructor(io) {
    super();
    this.io = io;
    this.state = {
      lat: null,
      lon: null,
      alt: null,
      relative_alt: null,
      gps_fix_type: null,
      satellites_visible: null,
      hdop: null,
      baro_alt: null,
      heading: null,
      climb: null,
      armed: false,
      ready: false,
      status: 'Idle',
      system_status: 'Unknown',
      mode: 'Unknown',
      mode_id: null,
      system_id: null,
      component_id: null,
      lastUpdate: null,
      statusTimestamp: null,
    };
    this.bridgeProcess = null;
    this.stdoutBuffer = '';
    this.pendingCommands = new Map();
    this.commandSeq = 0;
    this.lastSlamSample = null;
    this.lastGpsSample = null;
  }

  getCurrentState() {
    return { ...this.state };
  }

  start() {
    this.spawnBridge();
  }

  spawnBridge() {
    if (this.bridgeProcess) {
      return;
    }
    const env = { ...process.env };
    if (!env.PYMAVLINK_CONNECTION) {
      const host = process.env.MAVLINK_TARGET_HOST || '127.0.0.1';
      const port = process.env.MAVLINK_TARGET_PORT || process.env.MAVLINK_PORT || '14551';
      env.PYMAVLINK_CONNECTION = `udp:${host}:${port}`;
    }
    this.bridgeProcess = spawn(PYTHON_BIN, [BRIDGE_PATH], {
      stdio: ['pipe', 'pipe', 'inherit'],
      env,
    });
    this.bridgeProcess.stdout.on('data', (chunk) => this.handleStdout(chunk));
    this.bridgeProcess.on('exit', (code, signal) => {
      console.warn(
        `[PYMAVLINK] bridge exited (code=${code} signal=${signal || 'none'})`
      );
      this.bridgeProcess = null;
      this.rejectAllPending(new Error('Pymavlink bridge stopped'));
      setTimeout(() => this.spawnBridge(), BRIDGE_RESTART_DELAY);
    });
  }

  handleStdout(chunk) {
    this.stdoutBuffer += chunk.toString();
    let newlineIndex = this.stdoutBuffer.indexOf('\n');
    while (newlineIndex >= 0) {
      const line = this.stdoutBuffer.slice(0, newlineIndex).trim();
      this.stdoutBuffer = this.stdoutBuffer.slice(newlineIndex + 1);
      if (line.length > 0) {
        this.processBridgeLine(line);
      }
      newlineIndex = this.stdoutBuffer.indexOf('\n');
    }
  }

  processBridgeLine(line) {
    try {
      const payload = JSON.parse(line);
      this.handleBridgeMessage(payload);
    } catch (error) {
      console.warn('[PYMAVLINK] failed to parse bridge output', line, error.message);
    }
  }

  handleBridgeMessage(message) {
    if (!message || typeof message !== 'object') {
      return;
    }
    if (message.type === 'telemetry' && message.data) {
      const now = Date.now();
      this.state = { ...this.state, ...message.data, lastUpdate: now };
      this.updateLatestSamples(message.data, now);
      this.emitState();
      return;
    }
    if (
      message.type === 'mode_result' ||
      message.type === 'takeoff_result' ||
      message.type === 'csv_start_result' ||
      message.type === 'csv_stop_result'
    ) {
      this.resolvePending(message);
      return;
    }
    if (message.type === 'log') {
      const level = message.level || 'info';
      const text = message.message || '';
      if (level === 'error') {
        console.error(`[PYMAVLINK] ${text}`);
      } else {
        console.log(`[PYMAVLINK] ${text}`);
      }
    }
  }

  updateLatestSamples(payload = {}, now = Date.now()) {
    const lat =
      payload.lat ?? payload.state_lat ?? payload.gps_lat ?? this.lastGpsSample?.lat ?? null;
    const lon =
      payload.lon ?? payload.state_lon ?? payload.gps_lon ?? this.lastGpsSample?.lon ?? null;
    const alt =
      payload.alt ?? payload.state_alt ?? payload.gps_alt ?? this.lastGpsSample?.alt ?? null;
    const rel =
      payload.relative_alt ??
      payload.state_relative_alt ??
      payload.gps_alt_rel ??
      this.lastGpsSample?.rel ??
      null;
    const gpsTimestamp =
      payload.last_gps_host_timestamp ??
      payload.timestamp_mavlink ??
      (this.lastGpsSample ? this.lastGpsSample.timestamp : now);
    const heading =
      payload.heading ?? this.lastGpsSample?.heading ?? null;
    if (lat != null || lon != null || alt != null || rel != null) {
      this.lastGpsSample = {
        timestamp: gpsTimestamp,
        lat,
        lon,
        alt,
        rel,
        heading,
      };
    }
  }

  emitState() {
    const snapshot = { ...this.state };
    this.emit('state', snapshot);
    if (this.io) {
      this.io.emit('telemetry_update', snapshot);
    }
  }

  pushStatus(statusText, extraState = {}) {
    this.state = {
      ...this.state,
      status: statusText,
      statusTimestamp: Date.now(),
      ...extraState,
    };
    this.emitState();
  }

  requestModeChange(modeName) {
    return this.sendCommandWithResponse(
      { type: 'set_mode', mode: modeName },
      'mode_result',
      MODE_REQUEST_TIMEOUT
    );
  }

  requestTakeoff(altitudeMeters = 30) {
    let altitude = Number(altitudeMeters);
    if (!Number.isFinite(altitude) || altitude <= 0) {
      altitude = 30;
    }
    return this.sendCommandWithResponse(
      { type: 'takeoff', altitude },
      'takeoff_result',
      TAKEOFF_REQUEST_TIMEOUT
    );
  }

  startCsvLogging() {
    return this.sendCommandWithResponse(
      { type: 'csv_start' },
      'csv_start_result',
      CSV_START_TIMEOUT
    );
  }

  stopCsvLogging() {
    return this.sendCommandWithResponse(
      { type: 'csv_stop' },
      'csv_stop_result',
      CSV_STOP_TIMEOUT
    );
  }

  sendSlamPose(pose) {
    if (!pose) {
      return;
    }
    if (!this.bridgeProcess || !this.bridgeProcess.stdin.writable) {
      return;
    }
    this.lastSlamSample = {
      timestamp: pose.timestamp || Date.now(),
      x: pose.x ?? null,
      y: pose.y ?? null,
      z: pose.z ?? null,
      qw: pose.qw ?? null,
      qx: pose.qx ?? null,
      qy: pose.qy ?? null,
      qz: pose.qz ?? null,
    };
    const payload = { type: 'slam_pose', data: pose };
    this.sendCommand(payload);
  }

  getLatestOutput() {
    const slam = this.lastSlamSample || null;
    const gps = this.lastGpsSample || null;
    if (!slam && !gps) {
      return null;
    }
    const now = Date.now();
    return {
      timestamp_system: now,
      timestamp_slam: slam ? slam.timestamp : null,
      slam_x: slam ? slam.x : null,
      slam_y: slam ? slam.y : null,
      slam_z: slam ? slam.z : null,
      slam_qw: slam ? slam.qw : null,
      slam_qx: slam ? slam.qx : null,
      slam_qy: slam ? slam.qy : null,
      slam_qz: slam ? slam.qz : null,
      timestamp_mavlink: gps ? gps.timestamp : null,
      gps_lat: gps ? gps.lat : null,
      gps_lon: gps ? gps.lon : null,
      gps_alt: gps ? gps.alt : null,
      alt_rel: gps ? gps.rel : null,
      heading: gps ? gps.heading : null,
    };
  }

  sendCommandWithResponse(command, expectType, timeoutMs) {
    if (!this.bridgeProcess || !this.bridgeProcess.stdin.writable) {
      return Promise.reject(new Error('Pymavlink bridge unavailable'));
    }
    const requestId = ++this.commandSeq;
    const payload = { ...command, request_id: requestId };
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingCommands.delete(requestId);
        reject(new Error(`${expectType} timed out`));
      }, timeoutMs);
      this.pendingCommands.set(requestId, { resolve, reject, timer, expectType });
      this.sendCommand(payload);
    });
  }

  sendCommand(payload) {
    if (!this.bridgeProcess || !this.bridgeProcess.stdin.writable) {
      throw new Error('Pymavlink bridge unavailable');
    }
    try {
      this.bridgeProcess.stdin.write(`${JSON.stringify(payload)}\n`);
    } catch (error) {
      console.warn('[PYMAVLINK] failed to send command', error.message);
    }
  }

  rejectAllPending(error) {
    for (const [, entry] of this.pendingCommands.entries()) {
      clearTimeout(entry.timer);
      entry.reject(error);
    }
    this.pendingCommands.clear();
  }

  resolvePending(message) {
    const requestId = message.request_id;
    if (typeof requestId !== 'number') {
      return;
    }
    const pending = this.pendingCommands.get(requestId);
    if (!pending || (pending.expectType && pending.expectType !== message.type)) {
      return;
    }
    this.pendingCommands.delete(requestId);
    clearTimeout(pending.timer);
    if (message.ok) {
      pending.resolve(message);
    } else {
      pending.reject(new Error(message.error || 'Command failed'));
    }
  }
}

module.exports = { MavlinkTelemetry };
