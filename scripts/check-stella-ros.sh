#!/bin/bash

# Hentikan script jika ada command yang error
set -e

# Mendapatkan lokasi direktori tempat script ini berada
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
ROS2_WS="$PROJECT_ROOT/ros2_ws"

echo "=========================================="
echo "   CHECK STELLA VSLAM BUILD ARTIFACTS"
echo "=========================================="

# 1. Cek Environment Pixi
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Script ini harus dijalankan di dalam environment Pixi."
    echo "👉 Silakan jalankan perintah: pixi shell"
    exit 1
fi

echo "✅ Environment Pixi: $CONDA_PREFIX"

# 2. Cek Shared Libraries di $CONDA_PREFIX/lib
echo ""
echo "🔍 Checking Shared Libraries..."

check_lib() {
    if [ -f "$CONDA_PREFIX/lib/$1" ]; then
        echo "✅ Found: $1"
    else
        echo "❌ MISSING: $1"
        MISSING_LIBS=1
    fi
}

check_lib "libstella_vslam.so"
check_lib "libpangolin.so"
check_lib "libiridescence.so"
check_lib "libsocket_publisher.so"
check_lib "libfbow.so"

# 3. Cek ROS 2 Package
echo ""
echo "🔍 Checking ROS 2 Package..."

if [ -f "$ROS2_WS/install/setup.bash" ]; then
    echo "✅ Found ROS 2 workspace setup.bash"
    source "$ROS2_WS/install/setup.bash"
    
    if ros2 pkg list | grep -q "stella_vslam_ros"; then
        echo "✅ ROS Package 'stella_vslam_ros' found."
    else
        echo "❌ ROS Package 'stella_vslam_ros' NOT found."
        MISSING_ROS=1
    fi
    
    # Cek Executable
    if [ -f "$ROS2_WS/install/stella_vslam_ros/lib/stella_vslam_ros/run_slam" ]; then
        echo "✅ Executable 'run_slam' found."
    else
        echo "❌ Executable 'run_slam' NOT found."
        MISSING_ROS=1
    fi
else
    echo "❌ ROS 2 workspace setup.bash NOT found. Did the build complete?"
    MISSING_ROS=1
fi

# 4. Check Datasets
echo ""
echo "🔍 Checking Datasets..."
DATASET_DIR="$PROJECT_ROOT/dataset"

if [ -f "$DATASET_DIR/orb_vocab.fbow" ]; then
    echo "✅ Found: orb_vocab.fbow"
else
    echo "❌ MISSING: orb_vocab.fbow (Run scripts/download-stella-example.sh)"
    MISSING_DATA=1
fi

if [ -f "$DATASET_DIR/aist_living_lab_1/video.mp4" ]; then
    echo "✅ Found: aist_living_lab_1/video.mp4"
else
    echo "❌ MISSING: aist_living_lab_1/video.mp4 (Run scripts/download-stella-example.sh)"
    MISSING_DATA=1
fi

echo ""
echo "=========================================="
if [ "$MISSING_LIBS" == "1" ] || [ "$MISSING_ROS" == "1" ] || [ "$MISSING_DATA" == "1" ]; then
    echo "❌ VERIFICATION FAILED. Some artifacts are missing."
    exit 1
else
    echo "✅ VERIFICATION PASSED. All artifacts found."
    echo "   To run SLAM:"
    echo "   source $ROS2_WS/install/setup.bash"
    echo "   ros2 run stella_vslam_ros run_slam ..."
fi
echo "=========================================="
