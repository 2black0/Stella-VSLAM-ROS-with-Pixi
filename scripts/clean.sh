#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

TARGETS=(
    "$PROJECT_ROOT/.pixi"
    "$PROJECT_ROOT/pixi.lock"
    "$PROJECT_ROOT/lib/iridescence/build"
    "$PROJECT_ROOT/lib/Pangolin/build"
    "$PROJECT_ROOT/lib/socket.io-client-cpp/build"
    "$PROJECT_ROOT/ros2_ws/build"
    "$PROJECT_ROOT/ros2_ws/install"
    "$PROJECT_ROOT/ros2_ws/log"
    "$PROJECT_ROOT/lib/iridescence_viewer/build"
    "$PROJECT_ROOT/lib/pangolin_viewer/build"
    "$PROJECT_ROOT/lib/socket_publisher/build"
    "$PROJECT_ROOT/lib/stella_vslam/build"
    "$PROJECT_ROOT/lib/stella_vslam_examples/build"
)

echo "=========================================="
echo "   CLEAN WORKSPACE ARTIFACTS"
echo "=========================================="

for target in "${TARGETS[@]}"; do
    if [ -e "$target" ]; then
        echo "Removing: $target"
        rm -rf "$target"
    else
        echo "Skipping: $target (not found)"
    fi
done

echo ""
echo "✅ Clean complete."
