#!/bin/bash

# Hentikan script jika ada command yang error
set -e

# Mendapatkan lokasi direktori tempat script ini berada
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
# Folder build terpusat
LIB_DIR="$PROJECT_ROOT/lib"
ROS2_WS="$PROJECT_ROOT/ros2_ws"
# Repo fork untuk stella_vslam_ros (override via env jika perlu)
STELLA_VSLAM_ROS_REPO="${STELLA_VSLAM_ROS_REPO:-https://github.com/2black0/stella_vslam_ros.git}"
STELLA_VSLAM_ROS_BRANCH="${STELLA_VSLAM_ROS_BRANCH:-ros2}"

# Build options (set to 1 to enable, 0 to skip)
# Fokus non-ROS: skip ROS build by default
BUILD_ROS="${BUILD_ROS:-0}"  # Set to 1 jika butuh ROS wrapper

echo "=========================================="
echo "   SETUP & BUILD STELLA VSLAM"
echo "=========================================="
echo "📂 Project Root : $PROJECT_ROOT"
echo "📂 Lib Dir      : $LIB_DIR"
echo "📂 ROS2 WS      : $ROS2_WS"
echo "🎯 Build Mode   : Non-ROS (AirSim examples)"
echo "📦 ROS wrapper  : $([ "$BUILD_ROS" = "1" ] && echo "Enabled" || echo "Disabled (set BUILD_ROS=1 to enable)")"

# 1. Cek Environment Pixi
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Script ini harus dijalankan di dalam environment Pixi."
    echo "👉 Silakan jalankan perintah: pixi shell"
    exit 1
fi

echo "✅ Environment Pixi terdeteksi: $CONDA_PREFIX"

echo "✅ Environment Pixi terdeteksi: $CONDA_PREFIX"

if [ ! -d "$LIB_DIR" ]; then mkdir -p "$LIB_DIR"; fi

# ==========================================
# PART 1: BUILD VIEWER DEPENDENCIES
# ==========================================

# --- IridescenceViewer ---
echo ""
echo "------------------------------------------"
echo "📦 Build IridescenceViewer"
echo "------------------------------------------"
cd "$LIB_DIR"
if [ ! -d "iridescence" ]; then
    git clone https://github.com/koide3/iridescence.git
    cd iridescence
    git checkout 085322e0c949f75b67d24d361784e85ad7f197ab
    git submodule update --init --recursive
else
    cd iridescence
    echo "ℹ️  Folder iridescence sudah ada."
fi

mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_SYSTEM_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
    -DCMAKE_SKIP_BUILD_RPATH=TRUE \
    -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
    -DIridescence_INCLUDE_DIRS=$CONDA_PREFIX/include/iridescence \
    -DIridescence_LIBRARY=$CONDA_PREFIX/lib/libiridescence.so \
    -Dgl_imgui_LIBRARY=$CONDA_PREFIX/lib/libgl_imgui.so \
    ..
make -j$(nproc)
make install

# --- PangolinViewer ---
echo ""
echo "------------------------------------------"
echo "📦 Build PangolinViewer"
echo "------------------------------------------"
cd "$LIB_DIR"
if [ ! -d "Pangolin" ]; then
    git clone https://github.com/stevenlovegrove/Pangolin.git
    cd Pangolin
    git checkout ad8b5f83
    # Patch file_utils.cpp as per docs
    sed -i -e "193,198d" ./src/utils/file_utils.cpp
    # Patch packetstream_tags.h to include cstdint (Fix for GCC 13+)
    sed -i '/#pragma once/a #include <cstdint>' ./include/pangolin/log/packetstream_tags.h
else
    cd Pangolin
    echo "ℹ️  Folder Pangolin sudah ada."
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
    -DCMAKE_CXX_FLAGS="-Wno-stringop-truncation -Wno-deprecated-copy -Wno-parentheses -Wno-unused-parameter -Wno-maybe-uninitialized" \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_PANGOLIN_DEPTHSENSE=OFF \
    -DBUILD_PANGOLIN_FFMPEG=OFF \
    -DBUILD_PANGOLIN_LIBDC1394=OFF \
    -DBUILD_PANGOLIN_LIBJPEG=OFF \
    -DBUILD_PANGOLIN_LIBOPENEXR=OFF \
    -DBUILD_PANGOLIN_LIBPNG=OFF \
    -DBUILD_PANGOLIN_LIBREALSENSE=OFF \
    -DBUILD_PANGOLIN_LIBREALSENSE2=OFF \
    -DBUILD_PANGOLIN_LIBTIFF=OFF \
    -DBUILD_PANGOLIN_LIBUVC=OFF \
    -DBUILD_PANGOLIN_LZ4=OFF \
    -DBUILD_PANGOLIN_OPENNI=OFF \
    -DBUILD_PANGOLIN_OPENNI2=OFF \
    -DBUILD_PANGOLIN_PLEORA=OFF \
    -DBUILD_PANGOLIN_PYTHON=OFF \
    -DBUILD_PANGOLIN_TELICAM=OFF \
    -DBUILD_PANGOLIN_TOON=OFF \
    -DBUILD_PANGOLIN_UVC_MEDIAFOUNDATION=OFF \
    -DBUILD_PANGOLIN_V4L=OFF \
    -DBUILD_PANGOLIN_VIDEO=OFF \
    -DBUILD_PANGOLIN_ZSTD=OFF \
    -DBUILD_PYPANGOLIN_MODULE=OFF \
    ..
make -j$(nproc)
make install

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
    # We remove the 'const' from 'const SizeType length;'
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
make -j$(nproc)
make install

# NOTE: Skipping protobuf 3.6.1 build as we use system/pixi protobuf to avoid conflicts.

# ==========================================
# PART 1.5: SETUP AIRSIM (for camera examples)
# ==========================================
echo ""
echo "------------------------------------------"
echo "📦 Setup AirSim Headers & Libraries"
echo "------------------------------------------"

cd "$LIB_DIR"
if [ ! -d "AirSim" ]; then
    echo "🔽 Cloning AirSim repository..."
    git clone --depth 1 https://github.com/microsoft/AirSim.git
fi

cd AirSim

# Download dependencies manually without running setup.sh (to avoid apt-get errors)
echo "📦 Downloading AirSim dependencies manually..."

# 1. Download Eigen if not present
if [ ! -d "AirLib/deps/eigen3/Eigen" ]; then
    echo "  ⬇️  Downloading Eigen..."
    mkdir -p AirLib/deps
    if [ ! -f "AirLib/deps/eigen3.zip" ]; then
        wget -q https://gitlab.com/libeigen/eigen/-/archive/3.3.7/eigen-3.3.7.zip -O AirLib/deps/eigen3.zip
    fi
    unzip -q AirLib/deps/eigen3.zip -d AirLib/deps/
    mv AirLib/deps/eigen-3.3.7 AirLib/deps/eigen3
    echo "  ✅ Eigen downloaded"
else
    echo "  ✅ Eigen already present"
fi

# 2. Download rpclib if not present
if [ ! -d "external/rpclib/rpclib-2.3.0" ]; then
    echo "  ⬇️  Downloading rpclib..."
    mkdir -p external/rpclib
    if [ ! -f "external/rpclib/rpclib-2.3.0.zip" ]; then
        wget -q https://github.com/rpclib/rpclib/archive/v2.3.0.zip -O external/rpclib/rpclib-2.3.0.zip
    fi
    unzip -q external/rpclib/rpclib-2.3.0.zip -d external/rpclib/
    echo "  ✅ rpclib downloaded"
else
    echo "  ✅ rpclib already present"
fi

# 3. Verify AirLib headers exist (should be in git repo)
if [ ! -d "AirLib/include" ]; then
    echo "❌ ERROR: AirLib/include not found. This should exist in the cloned repository."
    exit 1
fi

echo "✅ AirSim setup complete (without apt-get)"

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

# Build & install FBoW as shared lib so it lives in the Pixi env
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
make -j$(nproc)
make install

# Back to stella_vslam core build
cd "$LIB_DIR"

# Install dependencies via rosdep (skipping what we installed via pixi if possible, but safe to run)
# rosdep install -y -i --from-paths . # Pixi handles most, but this might catch extras. 
# However, in a pixi env, we prefer pixi dependencies. 
# We'll assume pixi.toml has covered it.

cd stella_vslam
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-maybe-uninitialized" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DUSE_PANGOLIN_VIEWER=ON \
    -DUSE_IRIDESCENCE_VIEWER=ON \
    -DUSE_SOCKET_PUBLISHER=ON \
    ..
make -j$(nproc)
make install

# Build Viewers Plugins (Integrated in stella_vslam repo instructions but often separate repos in docs)
# The docs say:
# 1. stella_vslam
# 2. iridescence_viewer plugin
# 3. pangolin_viewer plugin
# 4. socket_publisher plugin

# --- iridescence_viewer plugin ---
echo "📦 Build plugin: iridescence_viewer"
cd "$LIB_DIR"
if [ ! -d "iridescence_viewer" ]; then
    git clone --recursive https://github.com/stella-cv/iridescence_viewer.git
fi
cd iridescence_viewer
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_SYSTEM_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
    -DIridescence_INCLUDE_DIRS=$CONDA_PREFIX/include/iridescence \
    -DIridescence_LIBRARY=$CONDA_PREFIX/lib/libiridescence.so \
    -Dgl_imgui_LIBRARY=$CONDA_PREFIX/lib/libgl_imgui.so \
    ..
make -j$(nproc)
make install

# --- pangolin_viewer plugin ---
echo "📦 Build plugin: pangolin_viewer"
cd "$LIB_DIR"
if [ ! -d "pangolin_viewer" ]; then
    git clone --recursive https://github.com/stella-cv/pangolin_viewer.git
fi
cd pangolin_viewer
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    ..
make -j$(nproc)
make install

# --- socket_publisher plugin ---
echo "📦 Build plugin: socket_publisher"
cd "$LIB_DIR"
if [ ! -d "socket_publisher" ]; then
    git clone --recursive https://github.com/stella-cv/socket_publisher.git
    # Patch data_serializer.cc in socket_publisher plugin as well if needed (it seems to be the same code base as socket.io-client-cpp wrapper?)
    # Wait, socket_publisher plugin is different from socket.io-client-cpp lib.
    # The warning came from socket_publisher/src/data_serializer.cc
    # So we need to patch it HERE.
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
make -j$(nproc)
make install

# ==========================================
# PART 2.5: PREPARE STELLA_VSLAM EXAMPLES
# ==========================================
echo ""
echo "------------------------------------------"
echo "📦 Prepare stella_vslam_examples"
echo "------------------------------------------"

cd "$LIB_DIR"
# Clone original examples if not exists
if [ ! -d "stella_vslam_examples" ]; then
    echo "🔽 Cloning stella_vslam_examples..."
    git clone --recursive --depth 1 https://github.com/stella-cv/stella_vslam_examples.git
else
    echo "ℹ️  Folder stella_vslam_examples sudah ada."
fi

cd stella_vslam_examples

# Copy custom AirSim source files from project code
CUSTOM_EXAMPLES_SRC="$PROJECT_ROOT/code/stella-vslam/examples"
if [ -d "$CUSTOM_EXAMPLES_SRC/src" ]; then
    echo "📋 Copying custom AirSim examples..."
    cp -v "$CUSTOM_EXAMPLES_SRC/src/run_camera_airsim_slam.cc" src/
    cp -v "$CUSTOM_EXAMPLES_SRC/src/run_camera_airsim_log_slam.cc" src/
    
    # Backup original CMakeLists.txt
    if [ ! -f "CMakeLists.txt.original" ]; then
        cp CMakeLists.txt CMakeLists.txt.original
    fi
    
    # Copy custom CMakeLists.txt with AirSim support
    cp -v "$CUSTOM_EXAMPLES_SRC/CMakeLists.txt" .
    
    echo "✅ Custom AirSim examples merged"
else
    echo "⚠️  Warning: Custom examples not found at $CUSTOM_EXAMPLES_SRC"
    echo "   Will build original examples only (no AirSim support)"
fi

# ==========================================
# PART 2.6: BUILD STELLA_VSLAM EXAMPLES
# ==========================================
echo ""
echo "------------------------------------------"
echo "📦 Build stella_vslam_examples"
echo "------------------------------------------"

cd "$LIB_DIR/stella_vslam_examples"
mkdir -p build && cd build

# Configure with CMake
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
    -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-deprecated-copy -Wno-deprecated-declarations -Wno-stringop-truncation" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DUSE_STACK_TRACE_LOGGER=OFF \
    -DAIRSIM_ROOT="$LIB_DIR/AirSim" \
    ..


echo "🔨 Building examples..."
make -j$(nproc)

# List built executables
echo ""
echo "✅ Examples built successfully:"
ls -lh run_* 2>/dev/null || echo "   (check build directory for executables)"

# Optional: create symlinks in a known location for easy access
mkdir -p "$PROJECT_ROOT/bin"
for exe in run_camera_airsim_slam run_camera_airsim_log_slam; do
    if [ -f "$exe" ]; then
        ln -sf "$LIB_DIR/stella_vslam_examples/build/$exe" "$PROJECT_ROOT/bin/$exe"
        echo "   Symlinked: bin/$exe"
    fi
done

# ==========================================
# PART 3: BUILD STELLA_VSLAM_ROS (OPTIONAL)
# ==========================================

if [ "$BUILD_ROS" = "1" ]; then
    echo ""
    echo "------------------------------------------"
    echo "📦 Build stella_vslam_ros"
    echo "------------------------------------------"

    if [ ! -d "$ROS2_WS/src" ]; then mkdir -p "$ROS2_WS/src"; fi
    cd "$ROS2_WS/src"

    if [ ! -d "stella_vslam_ros" ] || [ ! -f "stella_vslam_ros/CMakeLists.txt" ]; then
        echo "ℹ️  stella_vslam_ros tidak ditemukan atau tidak valid. Meng-clone ulang..."
        rm -rf stella_vslam_ros  # hapus jika ada tapi rusak/kosong
        git clone --recursive -b "$STELLA_VSLAM_ROS_BRANCH" "$STELLA_VSLAM_ROS_REPO" stella_vslam_ros
        echo "🔧 Patching stella_vslam_ros/CMakeLists.txt..."
        sed -i '1s/^/add_compile_options(-Wno-array-bounds -Wno-stringop-overflow)\n/' stella_vslam_ros/CMakeLists.txt
    else
        echo "ℹ️  stella_vslam_ros sudah ada dan valid."
        if ! grep -q "add_compile_options(-Wno-array-bounds" stella_vslam_ros/CMakeLists.txt; then
            echo "🔧 Patching stella_vslam_ros/CMakeLists.txt..."
            sed -i '1s/^/add_compile_options(-Wno-array-bounds -Wno-stringop-overflow)\n/' stella_vslam_ros/CMakeLists.txt
        fi
    fi

    cd "$ROS2_WS"
    # rosdep install -y -i --from-paths src --skip-keys=stella_vslam # Pixi handles deps

    echo "🔨 Building with colcon..."
    colcon build \
        --symlink-install \
        --cmake-args \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX
else
    echo ""
    echo "------------------------------------------"
    echo "⏭️  Skipping stella_vslam_ros (BUILD_ROS=0)"
    echo "   Set BUILD_ROS=1 to enable ROS wrapper build"
    echo "------------------------------------------"
fi

echo ""
echo "=========================================="
echo "✅ SUKSES! Build stella-vslam Complete."
if [ "$BUILD_ROS" = "1" ]; then
    echo "   Jangan lupa source workspace Anda:"
    echo "   source $ROS2_WS/install/setup.bash"
fi
echo ""
echo "📦 Built executables:"
echo "   Examples: $LIB_DIR/stella_vslam_examples/build/"
echo "     - run_camera_slam, run_video_slam, run_image_slam, etc."
if [ -f "$LIB_DIR/stella_vslam_examples/build/run_camera_airsim_slam" ]; then
    echo "     - run_camera_airsim_slam ✅"
    echo "     - run_camera_airsim_log_slam ✅"
fi
echo ""
echo "   Quick access: $PROJECT_ROOT/bin/"
if [ "$BUILD_ROS" = "0" ]; then
    echo ""
    echo "ℹ️  ROS wrapper was skipped (BUILD_ROS=0)"
    echo "   To build ROS wrapper: BUILD_ROS=1 ./scripts/build-stella.sh"
fi
echo "=========================================="
