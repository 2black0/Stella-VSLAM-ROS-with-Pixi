#!/bin/bash
# Build stella_vslam_ros with colcon inside the Pixi env
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
ROS2_WS="$PROJECT_ROOT/ros2_ws"

if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Jalankan di dalam pixi env (pixi shell)."
    exit 1
fi

echo "🏗️  Building stella_vslam_ros in $ROS2_WS"
cd "$ROS2_WS"

colcon build \
  --symlink-install \
  --cmake-args \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_PREFIX_PATH="$CONDA_PREFIX"

echo "✅ Done. Source: source $ROS2_WS/install/setup.bash"
