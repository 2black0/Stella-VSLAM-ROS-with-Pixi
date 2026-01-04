#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
ROS2_WS="$PROJECT_ROOT/ros2_ws"
ROS2_SRC="$ROS2_WS/src/stella_vslam_ros"
ROS2_INSTALL="$ROS2_WS/install/stella_vslam_ros"

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

section "ROS 2 Workspace"
check_dir "ros2_ws" "$ROS2_WS"
check_dir "ros2_ws/src" "$ROS2_WS/src"
check_file "stella_vslam_ros CMakeLists.txt" "$ROS2_SRC/CMakeLists.txt"

section "ROS 2 Install Artifacts"
check_file "setup.bash" "$ROS2_WS/install/setup.bash"
check_dir "stella_vslam_ros install" "$ROS2_INSTALL"
check_file "package.xml" "$ROS2_INSTALL/share/stella_vslam_ros/package.xml"
check_file "run_slam" "$ROS2_INSTALL/lib/stella_vslam_ros/run_slam"

section "Summary"
if [ "$MISSING" -eq 1 ]; then
    mark_fail "Missing ROS 2 build artifacts detected."
    exit 1
fi

mark_ok "ROS 2 build artifacts look good."
