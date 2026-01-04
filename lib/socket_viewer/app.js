let express = require("express");
let path = require("path");
let protobuf = require("protobufjs");
let { MavlinkTelemetry } = require("./telemetry/mavlink-reader");
let { MODE_LABELS, normalizeModeName } = require("./mavlink/modes");
let http_server = require("http").Server(express());
let io_server = require("socket.io")(http_server, {
  maxHttpBufferSize: 15 * 1024 * 1024,
});

let app = express();
let http_publisher = require("http").Server(app);
let io_publisher = require("socket.io")(http_publisher, {
  maxHttpBufferSize: 15 * 1024 * 1024,
});

const SLAM_PROTO_PATH = path.join(__dirname, "public", "map_segment.proto");
let mapSegmentType = null;
let lastSlamDecodeWarning = 0;
try {
  const root = protobuf.loadSync(SLAM_PROTO_PATH);
  mapSegmentType = root.lookupType("map_segment.map");
} catch (error) {
  console.warn(`[SLAM] Failed to load proto: ${error.message}`);
}

// setting express
app.set("views", __dirname + "/views");
app.set("view engine", "ejs");
app.use(express.static(__dirname + "/public"));

// render browser
app.get("/", function (req, res) {
  res.render("index.ejs", {
    initialTelemetry: telemetry.getCurrentState(),
  });
});

app.get("/api/telemetry", function (req, res) {
  res.json(telemetry.getCurrentState());
});

app.get("/api/output", function (req, res) {
  const output = telemetry.getLatestOutput();
  if (!output) {
    res.status(503).json({ error: "Data belum tersedia" });
    return;
  }
  res.json(output);
});

io_server.on("connection", function (socket) {
  console.log(`Connected - ID: ${socket.id}`);

  socket.on("map_publish", function (msg) {
    io_publisher.emit("map_publish", msg);
    processSlamSegment(msg);
  });

  socket.on("frame_publish", function (msg) {
    io_publisher.emit("frame_publish", { image: true, buffer: msg });
  });

  socket.on("disconnect", function () {
    console.log(`Disconnected - ID: ${socket.id}`);
  });
});

io_publisher.on("connection", function (socket) {
  socket.on("signal", function (msg) {
    io_server.emit("signal", msg);
  });

  socket.emit("telemetry_update", telemetry.getCurrentState());

  socket.on("takeoff_request", async function (_payload = {}, callback = () => {}) {
    const altitude =
      typeof _payload.altitude === "number"
        ? _payload.altitude
        : Number(_payload.altitude);
    const targetAltitude = Number.isFinite(altitude) && altitude > 0 ? altitude : 30;
    telemetry.pushStatus(`TAKEOFF: requesting ${targetAltitude} m`);
    try {
      await telemetry.requestTakeoff(targetAltitude);
      telemetry.pushStatus("TAKEOFF: sequence started");
      callback({ ok: true });
    } catch (error) {
      console.warn(`[TAKEOFF] ${error.message || error}`);
      telemetry.pushStatus(`TAKEOFF ERROR: ${error.message || error}`);
      callback({ ok: false, error: error.message || String(error) });
    }
  });

  socket.on("mode_change_request", async function (_payload = {}, callback = () => {}) {
    const normalizedMode = normalizeModeName(_payload.mode || _payload.modeName);
    if (!normalizedMode) {
      callback({
        ok: false,
        error: "Mode tidak dikenal.",
      });
      return;
    }
    const friendlyLabel = MODE_LABELS[normalizedMode] || normalizedMode;
    try {
      telemetry.pushStatus(`MODE: switching to ${friendlyLabel}`);
      await telemetry.requestModeChange(normalizedMode);
      telemetry.pushStatus(`MODE: set to ${friendlyLabel}`);
      callback({ ok: true, mode: friendlyLabel });
    } catch (error) {
      console.warn(`[MODE CHANGE] ${error.message || error}`);
      telemetry.pushStatus(`MODE ERROR: ${error.message || error}`);
      callback({ ok: false, error: error.message || String(error) });
    }
  });
  socket.on("csv_logging", async function (_payload = {}, callback = () => {}) {
    const action = typeof _payload.action === "string" ? _payload.action.toLowerCase() : "";
    if (action === "start") {
      try {
        await telemetry.startCsvLogging();
        telemetry.pushStatus("CSV: recording started");
        callback({ ok: true });
      } catch (error) {
        console.warn(`[CSV START] ${error.message || error}`);
        telemetry.pushStatus(`CSV ERROR: ${error.message || error}`);
        callback({ ok: false, error: error.message || String(error) });
      }
      return;
    }
    if (action === "stop") {
      try {
        const result = await telemetry.stopCsvLogging();
        telemetry.pushStatus("CSV: recording stopped");
        callback({
          ok: true,
          csv: result.csv,
          fileName: result.file_name || result.fileName,
        });
      } catch (error) {
        console.warn(`[CSV STOP] ${error.message || error}`);
        telemetry.pushStatus(`CSV ERROR: ${error.message || error}`);
        callback({ ok: false, error: error.message || String(error) });
      }
      return;
    }
    callback({ ok: false, error: "Aksi CSV tidak dikenal." });
  });
});

const telemetry = new MavlinkTelemetry(io_publisher);
telemetry.start();

http_server.listen(3000, function () {
  console.log("WebSocket: listening on *:3000");
});

http_publisher.listen(3001, function () {
  console.log("HTTP server: listening on *:3001")
});

function processSlamSegment(encodedPayload) {
  if (!mapSegmentType || typeof encodedPayload !== "string") {
    return;
  }
  try {
    const buffer = Buffer.from(encodedPayload, "base64");
    const decoded = mapSegmentType.decode(buffer);
    const poseArray =
      decoded &&
      decoded.currentFrame &&
      Array.isArray(decoded.currentFrame.pose)
        ? decoded.currentFrame.pose
        : null;
    if (!poseArray || poseArray.length < 12) {
      return;
    }
    const slamTimestamp = Date.now();
    
    // Extract pose matrix components (following get_slam.py convention)
    const r00 = poseArray[0], r01 = poseArray[1], r02 = poseArray[2], tx = poseArray[3];
    const r10 = poseArray[4], r11 = poseArray[5], r12 = poseArray[6], ty = poseArray[7];
    const r20 = poseArray[8], r21 = poseArray[9], r22 = poseArray[10], tz = poseArray[11];
    
    // Calculate camera position in world frame (same as get_slam.py)
    // translation = -R^T * t
    const x = -(r00 * tx + r10 * ty + r20 * tz);
    const y = -(r01 * tx + r11 * ty + r21 * tz);
    const z = -(r02 * tx + r12 * ty + r22 * tz);
    
    // Convert rotation matrix to quaternion (column-major order like get_slam.py)
    // rotation = (r00, r10, r20, r01, r11, r21, r02, r12, r22)
    const trace = r00 + r11 + r22;
    let qw, qx, qy, qz;
    
    if (trace > 0) {
      const s = Math.sqrt(trace + 1.0) * 2.0;
      qw = 0.25 * s;
      qx = (r21 - r12) / s;
      qy = (r02 - r20) / s;
      qz = (r10 - r01) / s;
    } else if (r00 > r11 && r00 > r22) {
      const s = Math.sqrt(1.0 + r00 - r11 - r22) * 2.0;
      qw = (r21 - r12) / s;
      qx = 0.25 * s;
      qy = (r01 + r10) / s;
      qz = (r02 + r20) / s;
    } else if (r11 > r22) {
      const s = Math.sqrt(1.0 + r11 - r00 - r22) * 2.0;
      qw = (r02 - r20) / s;
      qx = (r01 + r10) / s;
      qy = 0.25 * s;
      qz = (r12 + r21) / s;
    } else {
      const s = Math.sqrt(1.0 + r22 - r00 - r11) * 2.0;
      qw = (r10 - r01) / s;
      qx = (r02 + r20) / s;
      qy = (r12 + r21) / s;
      qz = 0.25 * s;
    }
    
    const slamPose = {
      timestamp: slamTimestamp,
      x: x,
      y: y,
      z: z,
      qw: qw,
      qx: qx,
      qy: qy,
      qz: qz,
    };
    telemetry.sendSlamPose(slamPose);
  } catch (error) {
    const now = Date.now();
    if (now - lastSlamDecodeWarning > 5000) {
      console.warn('[SLAM] decode error', error.message || error);
      lastSlamDecodeWarning = now;
    }
  }
}
