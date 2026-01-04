'use strict';
const GLOBAL_SCALE = 50;

let scene, camera, renderer;


/* Color setting*/
const CURRENT_FRAME_COLOR = "rgb(0,192,0)";
const KEYFRAME_COLOR = "rgb(92, 85, 250)";
const EDGE_COLOR = "rgb(192, 223, 255)";
const MARKER_COLOR = "rgb(255, 0, 255)";
const BACKGROUND_COLOR = "rgb(255, 255, 255)";
const REFERENCE_POINT_COLOR = [255, 0, 0];

// timestamp on received for measuring fps;
let receiveTimestamp = 0;

let property = {
    CameraMode: 'Follow',
    FixAngle: true,
    LandmarkSize: 0.0,
    KeyframeSize: 0.0,
    CurrentFrameSize: 0.8,
    DrawGraph: false,
    DrawGrid: true,
    DrawPoints: true,
    LocalizationMode: false,
    ResetSignal: function () { },
    StopSignal: function () { }
};

let graphicStats; // visualize fps of graphic refresh
let trackStats; // visualize fps of tracking update
let clock = new THREE.Clock();

let cameraFrames = new CameraFrames();

let pointUpdateFlag = false;
let pointCloud = new PointCloud();
let markerIndicators = new MarkerIndicators();
let posePanel;
let poseUpdatedLabel;
let poseBody;
let gpsPanel;
let gpsUpdatedLabel;
let gpsBody;
let slam2gpsActive = false;
let calibrateActive = false;
let visualSlamActive = false;
let csvRecording = false;
let telemetryPollTimer = null;

let grid;

let mouseHandler;
let wheelHandler;
let viewControls;


function init() {

    // create a stats for showing graphic update rate
    // place on the left-up corner
    graphicStats = new Stats();
    graphicStats.setMode(0); // 0: fps, 1: ms
    graphicStats.domElement.style.position = "absolute";
    graphicStats.domElement.style.left = "0px";
    graphicStats.domElement.style.top = "0px";
    document.getElementById("Stats-output").appendChild(graphicStats.domElement);

    // create a stats for showing current frame update rate
    // place bellow of graphicStats
    trackStats = new Stats();
    trackStats.setMode(0);
    trackStats.domElement.style.position = "alsolute";
    trackStats.domElement.style.left = "0px";
    trackStats.domElement.style.top = "48px";
    document.getElementById("Stats-output").appendChild(trackStats.domElement);

    // create a camera
    camera = new THREE.PerspectiveCamera(45, window.innerWidth / window.innerHeight, 0.01, 1000);

    initGui();
    initTumbnail();
    initProtobuf();

    // create a scene, that holds all elements such as cameras and points.
    scene = new THREE.Scene();

    // create a render and set the setSize
    renderer = new THREE.WebGLRenderer({ antialias: false });
    renderer.setClearColor(new THREE.Color(BACKGROUND_COLOR));
    renderer.setSize(window.innerWidth, window.innerHeight);

    // create grid plane
    grid = new THREE.GridHelper(500, 50);
    scene.add(grid);

    // position and point the camera to the center of the scene
    camera.position.x = -100;
    camera.position.y = 60;
    camera.position.z = 30;
    camera.rotation.x = 0;
    camera.rotation.y = 0;
    camera.rotation.z = 0;

    let lineGeo = new THREE.Geometry();
    for (let i = 0; i < 16; i++) {
        lineGeo.vertices.push(new THREE.Vector3(0, 0, 0));
    }

    // add the output of the renderer to the html element
    // this line must be before initialization TrackBallControls(othrewise, dat.gui won't be work).
    document.getElementById("WebGL-output").appendChild(renderer.domElement);

    // create a view controller that
    viewControls = new ViewControls(camera);

    // create a mouse action listener
    let mouseListener = function (btn, act, pos, vel) {
        if (btn == 0 && act != 0) {
            viewControls.addRot(vel[0], vel[1]);
        }
        else if (btn == 2 && act != 0) {
            viewControls.addMove(vel[0], vel[1])
        }
    };
    // create a mouse wheel action listener
    let wheelListener = function (rot) {
        viewControls.addZoom(rot);
    };
    mouseHandler = new MouseHandler(renderer.domElement, mouseListener);
    wheelHandler = new WheelHandler(renderer.domElement, wheelListener);
    setCameraMode(property.CameraMode);
    viewControls.update(100);

    // animation render function
    render();
    initTelemetryPanels();
    initControlPanel();
    scheduleTelemetryPoll();

}

// render method that updates each stats, camera frames, view controller, and renderer.
function render() {
    graphicStats.update();

    pointCloud.updatePointInScene(scene);

    cameraFrames.updateFramesInScene(scene);

    markerIndicators.updateMarkersInScene(scene);

    //if(chase_camera == false){
    // 仮　トラックボールコントロール用
    let delta = clock.getDelta();
    //trackballControls.update(delta);
    viewControls.update(delta);


    // render using requestAnimationFrame
    requestAnimationFrame(render);
    // render the Scene
    renderer.render(scene, camera);
}

// initialize gui by dat.gui
function initGui() {
    let gui = new dat.GUI({ width: 300 });
    gui.close();

    gui.add(property, 'CameraMode', ['Above', 'Follow', 'Bird', 'Subjective']).onChange(setCameraMode);
    gui.add(property, 'FixAngle').onChange(toggleFixAngle);
    gui.add(property, 'LandmarkSize', 0, 4, 0.1).onChange(setPointSize);
    gui.add(property, 'KeyframeSize', 0, 4, 0.1).onChange(setKeyframeSize);
    gui.add(property, 'CurrentFrameSize', 0, 4, 0.1).onChange(setCurrentframeSize);
    gui.add(camera, 'far', 1000, 1000000, 1000).onChange(setFar);
    gui.add(property, 'DrawGraph').onChange(setGraphVis);
    gui.add(property, 'DrawGrid').onChange(setGridVis);
    gui.add(property, 'DrawPoints').onChange(setPointsVis);
    gui.add(property, 'LocalizationMode').onChange(setLocalizationMode);
    gui.add(property, 'ResetSignal').domElement.children[0].innerHTML = "<button onclick='onClickReset()'>reset</button>";
    gui.add(property, 'StopSignal').domElement.children[0].innerHTML = "<button onclick='onClickTerminate()'>terminate</button>";
}

function setCameraMode(val) {
    let suffix = "_rot";
    if (property.FixAngle) {
        suffix = "_fix";
    }
    cameraFrames.setCurrentFrameVisibility(val !== "Subjective");
    viewControls.setMode(val + suffix);
}
function toggleFixAngle(val) {
    // If view angle is fixed, camera could not be rotated.
    setCameraMode(property.CameraMode);
}
function setPointSize(val) {
    val = Math.pow(2, val);
    pointCloud.setPointSize(val);
}
function setKeyframeSize(val) {
    val = Math.pow(2, val);
    cameraFrames.setKeyframeSize(val);
}
function setCurrentframeSize(val) {
    val = Math.pow(2, val);
    cameraFrames.setCurrentFrameSize(val);
}
function setFar(val) {
    camera.updateProjectionMatrix();
}
function setGraphVis(val) {
    cameraFrames.setGraphVisibility(val);
}
function setGridVis(val) {
    grid.visible = val;
}
function setPointsVis(val) {
    pointCloud.setPointsVisibility(val);
}
function setLocalizationMode(val) {
    if (val == true) {
        socket.emit("signal", "disable_mapping_mode");
    }
    else {
        socket.emit("signal", "enable_mapping_mode");
    }
}
function onClickReset() {
    socket.emit("signal", "reset");
}
function onClickTerminate() {
    socket.emit("signal", "terminate");
}

// function that converts array that have size of 16 to matrix that shape of 4x4
function array2mat44(mat, array) {
    for (let i = 0; i < 4; i++) {
        let raw = [];
        for (let j = 0; j < 4; j++) {
            let k = i * 4 + j;
            let elm = array[k];
            raw.push(elm);
        }
        mat.push(raw);
    }
}
function loadProtobufData(obj, keyframes, edges, points, referencePointIds, currentFramePose, markers) {
    for (let keyframeObj of obj.keyframes) {
        let keyframe = {};
        keyframe["id"] = keyframeObj.id;
        if (keyframeObj.pose != undefined) {
            keyframe["camera_pose"] = [];
            array2mat44(keyframe["camera_pose"], keyframeObj.pose.pose);
        }
        keyframes.push(keyframe);
    }
    for (let edgeObj of obj.edges) {
        edges.push([edgeObj.id0, edgeObj.id1])
    }
    for (let landmarkObj of obj.landmarks) {
        let landmark = {};
        landmark["id"] = landmarkObj.id;
        if (landmarkObj.coords.length != 0) {
            landmark["point_pos"] = landmarkObj.coords;
            landmark["rgb"] = landmarkObj.color;
        }
        points.push(landmark);
    }
    for (let id of obj.localLandmarks) {
        referencePointIds.push(id);
    }
    for (let markerObj of obj.markers) {
        let marker = {};
        marker["id"] = markerObj.id;
        if (markerObj.coords.length != 0) {
            marker["corners_pos"] = markerObj.coords;
            marker["initialized"] = markerObj.initialized;
        }
        markers.push(marker);
    }
    array2mat44(currentFramePose, obj.currentFrame.pose);

}

let mapSegment = undefined;
let mapMsg = undefined;
function initProtobuf() {

    protobuf.load("map_segment.proto", function (err, root) {
        mapSegment = root.lookupType("map_segment.map");
        mapMsg = root.lookupType("map_segment.map.msg");
    });
}

function receiveProtobuf(msg) {
    if (msg.length == 0 || mapSegment == undefined) {
        return;
    }

    let keyframes = [];
    let edges = [];
    let points = [];
    let referencePointIds = [];
    let currentFramePose = [];
    let markers = [];

    let buffer = base64ToUint8Array(msg);
    let obj = mapSegment.decode(buffer);

    if (obj.messages[0].tag == "RESET_ALL") {
        removeAllElements();
    }
    else {
        loadProtobufData(obj, keyframes, edges, points, referencePointIds, currentFramePose, markers);
        updateMapElements(msg.length, keyframes, edges, points, referencePointIds, currentFramePose, markers);
    }
}
function base64ToUint8Array(base64) {
    let binaryString = window.atob(base64);
    let len = binaryString.length;
    let bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return bytes;
}

function updateMapElements(msgSize, keyframes, edges, points, referencePointIds, currentFramePose, markers) {
    trackStats.update();
    cameraFrames.updateCurrentFrame(currentFramePose);
    viewControls.setCurrentIntrinsic(currentFramePose);
    updatePosePanel(currentFramePose);

    if (cameraFrames.numValidKeyframe == 0 && keyframes.length == 0) {
        return;
    }

    for (let point of points) {
        let id = point["id"];
        if (point["point_pos"] == undefined) {
            pointCloud.removePoint(id);
        }
        else {
            let x = point["point_pos"][0] * GLOBAL_SCALE;
            let y = point["point_pos"][1] * GLOBAL_SCALE;
            let z = point["point_pos"][2] * GLOBAL_SCALE;
            let r = point["rgb"][0];
            let g = point["rgb"][1];
            let b = point["rgb"][2];
            pointCloud.updatePoint(id, x, y, z, r, g, b);
        }
    }
    for (let keyframe of keyframes) {
        let id = keyframe["id"];
        if (keyframe["camera_pose"] == undefined) {
            cameraFrames.removeKeyframe(id);
        }
        else {
            cameraFrames.updateKeyframe(id, keyframe["camera_pose"]);
        }
    }
    cameraFrames.setEdges(edges);


    let currentMillis = new Date().getTime();
    if (receiveTimestamp != 0) {
        let dt = currentMillis - receiveTimestamp;
        if (dt < 2) dt = 2;
        let fps = 1000.0 / dt;
        // adaptive update rate
        //viewControls.updateSmoothness(fps);
        console.log(("         " + parseInt(msgSize / 1000)).substr(-6) + " KB"
            + ("     " + (fps).toFixed(1)).substr(-7) + " fps, "
            + ("         " + pointCloud.nValidPoint).substr(-6) + " pts, "
            + ("         " + cameraFrames.numValidKeyframe).substr(-6) + " kfs");
    }
    receiveTimestamp = currentMillis;

    pointCloud.colorizeReferencePoints(referencePointIds);

    // update markers
    for (let marker of markers) {
        let id = marker["id"];
        let initialized = marker["initialized"];
        if (marker["corners_pos"] == undefined) {
            markerIndicators.removeMarker(id);
        }
        else {
            let x0 = marker["corners_pos"][0] * GLOBAL_SCALE;
            let y0 = marker["corners_pos"][1] * GLOBAL_SCALE;
            let z0 = marker["corners_pos"][2] * GLOBAL_SCALE;

            let x1 = marker["corners_pos"][3] * GLOBAL_SCALE;
            let y1 = marker["corners_pos"][4] * GLOBAL_SCALE;
            let z1 = marker["corners_pos"][5] * GLOBAL_SCALE;

            let x2 = marker["corners_pos"][6] * GLOBAL_SCALE;
            let y2 = marker["corners_pos"][7] * GLOBAL_SCALE;
            let z2 = marker["corners_pos"][8] * GLOBAL_SCALE;

            let x3 = marker["corners_pos"][9] * GLOBAL_SCALE;
            let y3 = marker["corners_pos"][10] * GLOBAL_SCALE;
            let z3 = marker["corners_pos"][11] * GLOBAL_SCALE;

            markerIndicators.updateMarker(id, x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3, initialized);
        }
    }
}

function removeAllElements() {
    for (let id in pointCloud.vertexIds) {
        if (id < 0 || id == undefined) {
            continue;
        }
        pointCloud.removePoint(id);
    }
    for (let id in cameraFrames.keyframeIndices) {
        if (id < 0 || id == undefined) {
            continue;
        }
        cameraFrames.removeKeyframe(id);
    }
    cameraFrames.setEdges([]);

    markerIndicators.scheduleRemoveAll();
}

function initTelemetryPanels() {
    posePanel = document.getElementById("pose-panel");
    poseUpdatedLabel = document.getElementById("pose-updated");
    poseBody = document.getElementById("pose-body");
    gpsPanel = document.getElementById("gps-panel");
    gpsUpdatedLabel = document.getElementById("gps-updated");
    gpsBody = document.getElementById("gps-body");
}

function normalizeNumber(value) {
    if (typeof value === "number") {
        return Number.isFinite(value) ? value : null;
    }
    if (typeof value === "string") {
        const parsed = Number(value.trim());
        return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
}

function formatNumber(value, digits = 3) {
    const num = normalizeNumber(value);
    if (num === null) {
        return "--";
    }
    return num.toFixed(digits);
}

function formatMillis(value) {
    const num = normalizeNumber(value);
    if (num === null) {
        return "--";
    }
    return `${Math.round(num)} ms`;
}

function updatePosePanel(currentFramePose) {
    if (!poseBody || !poseUpdatedLabel) {
        return;
    }
    if (!Array.isArray(currentFramePose) || currentFramePose.length !== 4) {
        poseBody.textContent = "Waiting for pose data...";
        poseUpdatedLabel.textContent = "Updated: --";
        return;
    }
    
    // Extract pose matrix components (following get_slam.py convention)
    const r00 = currentFramePose[0][0], r01 = currentFramePose[0][1], r02 = currentFramePose[0][2], tx = currentFramePose[0][3];
    const r10 = currentFramePose[1][0], r11 = currentFramePose[1][1], r12 = currentFramePose[1][2], ty = currentFramePose[1][3];
    const r20 = currentFramePose[2][0], r21 = currentFramePose[2][1], r22 = currentFramePose[2][2], tz = currentFramePose[2][3];
    
    // Calculate camera position in world frame (same as get_slam.py and app.js)
    // translation = -R^T * t
    const x = -(r00 * tx + r10 * ty + r20 * tz);
    const y = -(r01 * tx + r11 * ty + r21 * tz);
    const z = -(r02 * tx + r12 * ty + r22 * tz);
    
    // Convert rotation matrix to quaternion (same algorithm as get_slam.py and app.js)
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
    
    const now = new Date().toLocaleTimeString();
    poseUpdatedLabel.textContent = `Updated: ${now}`;
    
    poseBody.innerHTML = `
        <div>Position (Camera)</div>
        <div>x: ${formatNumber(x)}</div>
        <div>y: ${formatNumber(y)}</div>
        <div>z: ${formatNumber(z)}</div>
        <div style="margin-top:6px;">Quaternion</div>
        <div>w: ${formatNumber(qw, 4)}</div>
        <div>x: ${formatNumber(qx, 4)}</div>
        <div>y: ${formatNumber(qy, 4)}</div>
        <div>z: ${formatNumber(qz, 4)}</div>
    `;
}

function updateMavlinkPanel(data) {
    if (!gpsBody || !gpsUpdatedLabel) {
        return;
    }
    if (!data) {
        gpsBody.textContent = "Waiting for telemetry...";
        gpsUpdatedLabel.textContent = "Updated: --";
        return;
    }
    const updatedAt =
        typeof data.lastUpdate === "number"
            ? new Date(data.lastUpdate).toLocaleTimeString()
            : new Date().toLocaleTimeString();
    gpsUpdatedLabel.textContent = `Updated: ${updatedAt}`;
    const modeText = data.mode || data.mode_name || data.modeName || "Unknown";
    const lat = formatNumber(data.lat ?? data.state_lat ?? data.stateLat ?? null, 6);
    const lon = formatNumber(data.lon ?? data.state_lon ?? data.stateLon ?? null, 6);
    const alt = formatNumber(data.alt ?? data.state_alt ?? data.stateAlt ?? null, 2);
    const relAlt = formatNumber(
        data.relative_alt ?? data.state_relative_alt ?? data.state_relative_altitude ?? null,
        2
    );
    const baroAlt = formatNumber(
        data.baro_alt ?? data.state_baro_alt ?? data.alt ?? data.state_alt ?? null,
        2
    );
    const heading = formatNumber(data.heading ?? data.state_heading ?? null, 1);
    gpsBody.innerHTML = `
        <div>Mode: ${modeText}</div>
        <div>Lat: ${lat}</div>
        <div>Lon: ${lon}</div>
        <div>Baro/Alt: ${baroAlt} m</div>
        <div>Alt Rel: ${relAlt} m</div>
        <div>Heading: ${heading}°</div>
    `;
}

function initControlPanel() {
    const takeoffBtn = document.getElementById("btn-takeoff");
    const modeButtons = [
        { id: "btn-mode-guided", mode: "GUIDED" },
        { id: "btn-mode-auto", mode: "AUTO" },
        { id: "btn-mode-rtl", mode: "RTL" },
    ];
    const calibrateToggle = document.getElementById("calibrate-toggle");
    const slamToggle = document.getElementById("slam2gps-toggle");
    const saveCsvBtn = document.getElementById("btn-save-csv");
    const visualSlamToggle = document.getElementById("visual-slam-toggle");

    if (takeoffBtn) {
        takeoffBtn.addEventListener("click", () => {
            if (!window.socket) {
                alert("Socket belum siap.");
                return;
            }
            takeoffBtn.disabled = true;
            window.socket.emit("takeoff_request", {}, (response = {}) => {
                takeoffBtn.disabled = false;
                if (response.ok) {
                    alert("Takeoff sequence sent.");
                } else {
                    alert(response.error || "Gagal menjalankan takeoff.");
                }
            });
        });
    }
    modeButtons.forEach(({ id, mode }) => {
        const btn = document.getElementById(id);
        if (!btn) {
            return;
        }
        btn.addEventListener("click", () => {
            if (!window.socket) {
                alert("Socket belum siap.");
                return;
            }
            btn.disabled = true;
            window.socket.emit("mode_change_request", { mode }, (response = {}) => {
                btn.disabled = false;
                if (response.ok) {
                    alert(`Mode set to ${response.mode || mode}`);
                } else {
                    alert(response.error || "Gagal mengganti mode.");
                }
            });
        });
    });
    if (calibrateToggle) {
        calibrateToggle.addEventListener("click", () => {
            calibrateActive = !calibrateActive;
            updateCalibrateButton();
            alert(
                calibrateActive
                    ? "Calibration activated"
                    : "Calibration deactivated"
            );
        });
        updateCalibrateButton();
    }
    if (slamToggle) {
        slamToggle.addEventListener("click", () => {
            slam2gpsActive = !slam2gpsActive;
            updateSlamToggleButton();
            alert(
                slam2gpsActive
                    ? "SLAM2GPS mode activated"
                    : "SLAM2GPS mode deactivated"
            );
        });
        updateSlamToggleButton();
    }
    if (visualSlamToggle) {
        visualSlamToggle.addEventListener("click", () => {
            visualSlamActive = !visualSlamActive;
            updateVisualSlamButton();
            alert(
                visualSlamActive
                    ? "Visual SLAM activated"
                    : "Visual SLAM deactivated"
            );
        });
        updateVisualSlamButton();
    }
    if (saveCsvBtn) {
        saveCsvBtn.addEventListener("click", () => {
            if (!window.socket) {
                alert("Socket belum siap.");
                return;
            }
            saveCsvBtn.disabled = true;
            if (!csvRecording) {
                window.socket.emit("csv_logging", { action: "start" }, (response = {}) => {
                    saveCsvBtn.disabled = false;
                    if (response.ok) {
                        csvRecording = true;
                        saveCsvBtn.textContent = "Stop CSV";
                        saveCsvBtn.classList.add("csv-active");
                    } else {
                        alert(response.error || "Gagal memulai rekam CSV.");
                    }
                });
            } else {
                window.socket.emit("csv_logging", { action: "stop" }, (response = {}) => {
                    saveCsvBtn.disabled = false;
                    if (response.ok && response.csv) {
                        triggerCsvDownload(response.csv, response.fileName || "slam-log.csv");
                        csvRecording = false;
                        saveCsvBtn.textContent = "Save CSV";
                        saveCsvBtn.classList.remove("csv-active");
                    } else {
                        alert(response.error || "Gagal menghentikan rekam CSV.");
                    }
                });
            }
        });
    }
}

function updateSlamToggleButton() {
    const slamToggle = document.getElementById("slam2gps-toggle");
    if (!slamToggle) {
        return;
    }
    if (slam2gpsActive) {
        slamToggle.classList.remove("inactive");
        slamToggle.classList.add("active");
        slamToggle.textContent = "SLAM2GPS";
    } else {
        slamToggle.classList.remove("active");
        slamToggle.classList.add("inactive");
        slamToggle.textContent = "SLAM2GPS";
    }
}

function updateCalibrateButton() {
    const calibrateToggle = document.getElementById("calibrate-toggle");
    if (!calibrateToggle) {
        return;
    }
    if (calibrateActive) {
        calibrateToggle.classList.remove("inactive");
        calibrateToggle.classList.add("active");
    } else {
        calibrateToggle.classList.remove("active");
        calibrateToggle.classList.add("inactive");
    }
}

function updateVisualSlamButton() {
    const visualSlamToggle = document.getElementById("visual-slam-toggle");
    if (!visualSlamToggle) {
        return;
    }
    visualSlamToggle.textContent = "Visual-SLAM";
    if (visualSlamActive) {
        visualSlamToggle.classList.remove("inactive");
        visualSlamToggle.classList.add("active");
    } else {
        visualSlamToggle.classList.remove("active");
        visualSlamToggle.classList.add("inactive");
    }
}

window.updateMavlinkPanel = updateMavlinkPanel;

function triggerCsvDownload(base64Data, fileName) {
    try {
        const byteCharacters = atob(base64Data);
        const byteNumbers = new Array(byteCharacters.length);
        for (let i = 0; i < byteCharacters.length; i++) {
            byteNumbers[i] = byteCharacters.charCodeAt(i);
        }
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: "text/csv;charset=utf-8;" });
        const url = URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = fileName || `slam-log-${Date.now()}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    } catch (error) {
        console.error("Failed to download CSV", error);
        alert("Gagal menyimpan file CSV.");
    }
}

function scheduleTelemetryPoll() {
    if (telemetryPollTimer) {
        return;
    }
    const poll = () => {
        fetch("/api/telemetry")
            .then((res) => {
                if (!res.ok) {
                    throw new Error("Telemetry fetch failed");
                }
                return res.json();
            })
            .then((data) => {
                if (typeof updateMavlinkPanel === "function") {
                    updateMavlinkPanel(data);
                }
            })
            .catch(() => {
                // ignore fetch errors
            });
    };
    poll();
    telemetryPollTimer = setInterval(poll, 1000);
}

// calculate inverse of se3 pose matrix
function inv(pose) {
    let res = new Array();
    for (let i = 0; i < 3; i++) {
        res.push([0, 0, 0, 0]);
    }
    // - R^T * t
    res[0][3] = - pose[0][0] * pose[0][3] - pose[1][0] * pose[1][3] - pose[2][0] * pose[2][3];
    res[1][3] = - pose[0][1] * pose[0][3] - pose[1][1] * pose[1][3] - pose[2][1] * pose[2][3];
    res[2][3] = - pose[0][2] * pose[0][3] - pose[1][2] * pose[1][3] - pose[2][2] * pose[2][3];
    res[0][0] = pose[0][0]; res[0][1] = pose[1][0]; res[0][2] = pose[2][0];
    res[1][0] = pose[0][1]; res[1][1] = pose[1][1]; res[1][2] = pose[2][1];
    res[2][0] = pose[0][2]; res[2][1] = pose[1][2]; res[2][2] = pose[2][2];

    return res;
}

// window resize function
// The function is called in index.ejs
function onResize() {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
}

let thumbEnlarge = false; // if thumbnail is clicked, that is enlarged and this flag is set
const THUMB_SCALING = 3; // thumbnail scaling magnification
const THUMB_HEIGHT = 96; // normally thumbnail height (width is doubled height)
const CANVAS_SIZE = [1024, 500]; // thumbnail image resolution
function initTumbnail() {
    let thumb = document.getElementById("thumb");
    thumb.style.width = THUMB_HEIGHT * 2 + 'px';
    thumb.style.height = THUMB_HEIGHT + 'px';
    thumb.style.transition = 'all 0.5s ease-in-out'; // enable animation when enlarge and shrinking
    thumb.style.zIndex = '10001'; // thumbnail is drawn over two stats
    thumb.setAttribute("width", CANVAS_SIZE[0]);
    thumb.setAttribute("height", CANVAS_SIZE[1]);
    thumb.addEventListener('click', onThumbClick);

}
function onThumbClick() {

    thumbEnlarge = !thumbEnlarge; // inverse flag
    if (!thumbEnlarge) {
        document.getElementById("thumb").style.transform = 'translate(0px, 0px) scale(1)';
    }
    else {
        let x = THUMB_HEIGHT * (THUMB_SCALING - 1);
        let y = THUMB_HEIGHT / 2 * (THUMB_SCALING - 1);
        document.getElementById("thumb").style.transform = 'translate(' + x + 'px, ' + y + 'px) scale(' + THUMB_SCALING + ')';
    }

}
