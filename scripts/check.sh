#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
EXAMPLES_BUILD="$EXAMPLES_DIR/build"

MISSING=0

if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Run inside the Pixi environment (pixi shell)."
    exit 1
fi

OK_MARK="✅"
FAIL_MARK="❌"

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

mark_ok() {
    echo "${OK_MARK} $1"
}

mark_fail() {
    echo "${FAIL_MARK} $1"
}

check_dir() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        mark_ok "$label: $path"
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

check_file() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        mark_ok "$label: $path"
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

section "Source Paths + CMakeLists"
check_file "stella_vslam CMakeLists.txt" "$LIB_DIR/stella_vslam/CMakeLists.txt"
check_file "stella_vslam_examples CMakeLists.txt" "$LIB_DIR/stella_vslam_examples/CMakeLists.txt"
check_file "iridescence_viewer CMakeLists.txt" "$LIB_DIR/iridescence_viewer/CMakeLists.txt"
check_file "pangolin_viewer CMakeLists.txt" "$LIB_DIR/pangolin_viewer/CMakeLists.txt"
check_file "socket_publisher CMakeLists.txt" "$LIB_DIR/socket_publisher/CMakeLists.txt"
check_dir "AirSim headers" "$LIB_DIR/AirSim/AirLib/include"

section "Build Directories + Installed Core Libraries (Pixi Env)"
check_dir "stella_vslam build" "$LIB_DIR/stella_vslam/build"
check_dir "stella_vslam_examples build" "$EXAMPLES_BUILD"
check_file "libstella_vslam.so" "$CONDA_PREFIX/lib/libstella_vslam.so"
check_file "libfbow.so" "$CONDA_PREFIX/lib/libfbow.so"

section "Installed Viewer Plugins (Pixi Env)"
check_file "libpangolin_viewer.so" "$CONDA_PREFIX/lib/libpangolin_viewer.so"
check_file "libiridescence_viewer.so" "$CONDA_PREFIX/lib/libiridescence_viewer.so"
check_file "libsocket_publisher.so" "$CONDA_PREFIX/lib/libsocket_publisher.so"

section "Examples (Build Outputs)"
check_file "run_camera_slam" "$EXAMPLES_BUILD/run_camera_slam"
check_file "run_video_slam" "$EXAMPLES_BUILD/run_video_slam"
check_file "run_image_slam" "$EXAMPLES_BUILD/run_image_slam"
if [ -f "$EXAMPLES_DIR/CMakeLists.txt" ] && grep -q "run_camera_airsim_slam" "$EXAMPLES_DIR/CMakeLists.txt"; then
    check_file "run_camera_airsim_slam" "$EXAMPLES_BUILD/run_camera_airsim_slam"
else
    mark_ok "run_camera_airsim_slam: not configured in CMakeLists.txt (skipped)"
fi

if [ -f "$EXAMPLES_DIR/CMakeLists.txt" ] && grep -q "run_camera_airsim_log_slam" "$EXAMPLES_DIR/CMakeLists.txt"; then
    check_file "run_camera_airsim_log_slam" "$EXAMPLES_BUILD/run_camera_airsim_log_slam"
else
    mark_ok "run_camera_airsim_log_slam: not configured in CMakeLists.txt (skipped)"
fi

section "Summary"
if [ "$MISSING" -eq 1 ]; then
    mark_fail "Missing build artifacts detected."
    exit 1
fi

mark_ok "All build artifacts look good."
