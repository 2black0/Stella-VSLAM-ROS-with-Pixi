#!/bin/bash

# Hentikan script jika ada command yang error
set -e

# Mendapatkan lokasi direktori tempat script ini berada
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
# Folder build terpusat (gunakan folder terpisah untuk RPi agar tidak campur)
LIB_DIR="$PROJECT_ROOT/lib_rpi"

echo "=========================================="
echo "   SETUP & BUILD STELLA VSLAM (RPi 5)"
echo "=========================================="
echo "📂 Project Root : $PROJECT_ROOT"
echo "📂 Lib Dir      : $LIB_DIR"
echo "🎯 Build Mode   : SocketIO Only (No GUI Viewers, No ROS)"

# Detect RPi or ARM64 and limit jobs to avoid OOM
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    echo "⚠️  ARM64 detected. Limiting make jobs to 2 to avoid OOM on RPi."
    MAKE_JOBS="-j2"
else
    MAKE_JOBS="-j$(nproc)"
fi
echo "⚙️  Make Jobs    : $MAKE_JOBS"

# 1. Cek Environment Pixi
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Script ini harus dijalankan di dalam environment Pixi."
    echo "👉 Silakan jalankan perintah: pixi shell"
    exit 1
fi

echo "✅ Environment Pixi terdeteksi: $CONDA_PREFIX"

if [ ! -d "$LIB_DIR" ]; then mkdir -p "$LIB_DIR"; fi

# ==========================================
# PART 1: BUILD DEPENDENCIES (SocketIO Only)
# ==========================================

# --- SocketViewer ---
echo ""
echo "------------------------------------------"
echo "📦 Build SocketViewer (socket.io-client-cpp)"
echo "------------------------------------------"
cd "$LIB_DIR"
if [ ! -d "socket.io-client-cpp" ]; then
    git clone https://github.com/shinsumicco/socket.io-client-cpp.git
    cd socket.io-client-cpp
    git submodule init
    git submodule update
    
    # Patch rapidjson document.h to fix "assignment of read-only member" error
    echo "🔧 Patching rapidjson/document.h..."
    sed -i 's/const SizeType length;/SizeType length;/g' lib/rapidjson/include/rapidjson/document.h
else
    cd socket.io-client-cpp
    echo "ℹ️  Folder socket.io-client-cpp sudah ada."
fi

mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_SYSTEM_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
    -DCMAKE_SKIP_BUILD_RPATH=TRUE \
    -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
    -DCMAKE_CXX_FLAGS="-Wno-stringop-truncation -Wno-deprecated-copy" \
    -DBUILD_UNIT_TESTS=OFF \
    ..
make $MAKE_JOBS
make install

# ==========================================
# PART 2: BUILD STELLA_VSLAM (CORE)
# ==========================================
echo ""
echo "------------------------------------------"
echo "📦 Build stella_vslam (Core)"
echo "------------------------------------------"

cd "$LIB_DIR"
if [ ! -d "stella_vslam" ]; then
    git clone --recursive --depth 1 https://github.com/stella-cv/stella_vslam.git
else
    echo "ℹ️  Folder stella_vslam sudah ada."
fi

# Patch FBoW to fix class-memaccess warning
echo "🔧 Patching FBoW/src/fbow.cpp..."
sed -i 's/memset(&_params,0,sizeof(_params));/_params = {};/g' stella_vslam/3rd/FBoW/src/fbow.cpp

# Build & install FBoW as shared lib
echo "📦 Build FBoW (shared)"
cd stella_vslam/3rd/FBoW
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DBUILD_SHARED_LIBS=ON \
    ..
make $MAKE_JOBS
make install

# Back to stella_vslam core build
cd "$LIB_DIR"

cd stella_vslam
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-maybe-uninitialized" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DUSE_PANGOLIN_VIEWER=OFF \
    -DUSE_IRIDESCENCE_VIEWER=OFF \
    -DUSE_SOCKET_PUBLISHER=ON \
    ..
make $MAKE_JOBS
make install

# Build Socket Publisher Plugin ONLY
echo "📦 Build plugin: socket_publisher"
cd "$LIB_DIR"
if [ ! -d "socket_publisher" ]; then
    git clone --recursive https://github.com/stella-cv/socket_publisher.git
    echo "🔧 Patching socket_publisher/src/data_serializer.cc..."
    sed -i 's/map.release_current_frame();/(void)map.release_current_frame();/g' socket_publisher/src/data_serializer.cc
fi
cd socket_publisher
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    ..
make $MAKE_JOBS
make install

# ==========================================
# PART 3: BUILD EXAMPLES
# ==========================================
echo ""
echo "------------------------------------------"
echo "📦 Build stella_vslam_examples"
echo "------------------------------------------"

cd "$LIB_DIR"
if [ ! -d "stella_vslam_examples" ]; then
    git clone --recursive --depth 1 https://github.com/stella-cv/stella_vslam_examples.git
else
    echo "ℹ️  Folder stella_vslam_examples sudah ada."
fi

cd stella_vslam_examples
mkdir -p build && cd build

# Configure with CMake (No AirSim, No Stack Trace Logger)
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-deprecated-copy -Wno-deprecated-declarations -Wno-stringop-truncation" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DUSE_STACK_TRACE_LOGGER=OFF \
    ..

echo "🔨 Building examples..."
make $MAKE_JOBS

echo ""
echo "✅ Examples built successfully:"
ls -lh run_* 2>/dev/null || echo "   (check build directory for executables)"

echo ""
echo "=========================================="
echo "✅ SUKSES! Build stella-vslam (RPi/SocketIO) Complete."
echo "=========================================="
