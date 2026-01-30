#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
ROS2_WS="$PROJECT_ROOT/ros2_ws"

if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Run inside the Pixi environment (pixi shell)."
    exit 1
fi

STELLA_VSLAM_ROS_DIR="$ROS2_WS/src/stella_vslam_ros"
CMAKE_FILE="$STELLA_VSLAM_ROS_DIR/CMakeLists.txt"

if [ ! -d "$STELLA_VSLAM_ROS_DIR" ]; then
    echo "ERROR: Missing stella_vslam_ros at $STELLA_VSLAM_ROS_DIR"
    echo "       Make sure the ROS2 workspace is present under ros2_ws/src."
    exit 1
fi

if [ ! -f "$CMAKE_FILE" ]; then
    echo "ERROR: CMakeLists.txt not found in $STELLA_VSLAM_ROS_DIR"
    exit 1
fi

if ! grep -q "add_compile_options(-Wno-array-bounds" "$CMAKE_FILE"; then
    sed -i '1s/^/add_compile_options(-Wno-array-bounds -Wno-stringop-overflow)\n/' "$CMAKE_FILE"
fi

echo "Building stella_vslam_ros..."
cd "$ROS2_WS"

colcon build \
    --symlink-install \
    --cmake-args \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
    --parallel-workers 8

echo "Done. Source: source $ROS2_WS/install/setup.bash"
