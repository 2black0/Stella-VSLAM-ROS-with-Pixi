#!/bin/bash
set -e

# Mendapatkan lokasi direktori tempat script ini berada
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
DATASET_DIR="$PROJECT_ROOT/dataset"
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
BUILD_DIR="$EXAMPLES_DIR/build"

echo "=========================================="
echo "   RUN STELLA VSLAM SIMPLE EXAMPLE (NON-ROS)"
echo "=========================================="

# 1. Cek Dataset
if [ ! -f "$DATASET_DIR/orb_vocab.fbow" ] || [ ! -f "$DATASET_DIR/aist_living_lab_1/video.mp4" ]; then
    echo "❌ Dataset missing. Please run scripts/download-stella-example.sh first."
    exit 1
fi

# 2. Cek & Build Examples
if [ ! -d "$EXAMPLES_DIR" ]; then
    echo "⬇️  Cloning stella_vslam_examples..."
    mkdir -p "$LIB_DIR"
    cd "$LIB_DIR"
    git clone --recursive https://github.com/stella-cv/stella_vslam_examples.git
else
    # Ensure submodules are initialized
    cd "$EXAMPLES_DIR"
    if [ ! -f "3rd/filesystem/include/ghc/filesystem.hpp" ]; then
        echo "  📦 Initializing submodules..."
        git submodule update --init --recursive
    fi
fi

if [ ! -f "$BUILD_DIR/run_video_slam" ]; then
    echo "🔨 Building examples..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
    make -j$(nproc)
fi

# 3. Run Example
echo ""
echo "🚀 Running run_video_slam..."
echo "   Vocab: $DATASET_DIR/orb_vocab.fbow"
echo "   Video: $DATASET_DIR/aist_living_lab_1/video.mp4"
echo "   Config: $LIB_DIR/stella_vslam/example/aist/equirectangular.yaml"
echo "------------------------------------------"

cd "$BUILD_DIR"
./run_video_slam \
    -v "$DATASET_DIR/orb_vocab.fbow" \
    -m "$DATASET_DIR/aist_living_lab_1/video.mp4" \
    -c "$LIB_DIR/stella_vslam/example/aist/equirectangular.yaml" \
    --map-db-out map.msg \
    --frame-skip 2 \
    --no-sleep
