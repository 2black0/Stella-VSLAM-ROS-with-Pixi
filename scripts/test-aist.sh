#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
DATASET_DIR="$PROJECT_ROOT/dataset"
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
BUILD_DIR="$EXAMPLES_DIR/build"

if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Run inside the Pixi environment (pixi shell)."
    exit 1
fi

echo "=========================================="
echo "   RUN STELLA VSLAM - AIST (VIDEO)"
echo "=========================================="

# 1. Check dataset
if [ ! -f "$DATASET_DIR/orb_vocab.fbow" ] || [ ! -f "$DATASET_DIR/aist_living_lab_1/video.mp4" ]; then
    echo "❌ Dataset missing. Run scripts/dataset.sh first."
    exit 1
fi

# 2. Check dependencies
if [ ! -d "$LIB_DIR/stella_vslam" ] || [ ! -d "$EXAMPLES_DIR" ]; then
    echo "❌ Missing stella_vslam or stella_vslam_examples under lib/."
    exit 1
fi
if [ ! -f "$EXAMPLES_DIR/3rd/filesystem/include/ghc/filesystem.hpp" ]; then
    echo "❌ Missing filesystem headers in stella_vslam_examples/3rd."
    exit 1
fi

# 3. Build examples if needed
if [ ! -x "$BUILD_DIR/run_video_slam" ]; then
    echo "🔨 Building stella_vslam_examples..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
    make -j"$(nproc)"
fi

# 4. Run example
echo ""
echo "🚀 Running run_video_slam..."
cd "$BUILD_DIR"
./run_video_slam \
    -v "$DATASET_DIR/orb_vocab.fbow" \
    -m "$DATASET_DIR/aist_living_lab_1/video.mp4" \
    -c "$LIB_DIR/stella_vslam/example/aist/equirectangular.yaml" \
    --map-db-out map.msg \
    --frame-skip 2 \
    --viewer pangolin_viewer \
    --no-sleep
