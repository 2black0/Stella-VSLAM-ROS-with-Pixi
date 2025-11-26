#!/bin/bash

# Hentikan script jika ada command yang error
set -e

# Mendapatkan lokasi direktori
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
LIB_DIR="$PROJECT_ROOT/lib_rpi"

echo "=========================================="
echo "   SETUP & BUILD STELLA VSLAM (RPi 5)"
echo "   Hybrid Mode: Pixi Deps + Source Build"
echo "   Feature: Skip built modules & Fix OpenGL & Suppress Warnings"
echo "=========================================="
echo "📂 Lib Dir      : $LIB_DIR"

# Cek Pixi Environment
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Harap jalankan 'pixi shell' terlebih dahulu!"
    exit 1
fi

# Konfigurasi Core untuk RPi 5
export CMAKE_BUILD_PARALLEL_LEVEL=3
MAKE_JOBS="-j3"

if [ ! -d "$LIB_DIR" ]; then mkdir -p "$LIB_DIR"; fi

# Flags untuk menyembunyikan warning C++20 dan library lama
# -Wno-c++20-compat: Sembunyikan warning char8_t
# -Wno-type-limits: Sembunyikan warning json comparison
# -Wno-deprecated: Sembunyikan warning fungsi usang
COMMON_CXX_FLAGS="-Wno-deprecated-declarations -Wno-deprecated-copy -Wno-c++20-compat -Wno-type-limits -Wno-parentheses"

# ==========================================
# 1. SOCKET.IO-CLIENT-CPP (Source)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "socket.io-client-cpp" ]; then
    echo "⬇️  [1/6] Cloning Socket.IO Client..."
    git clone https://github.com/shinsumicco/socket.io-client-cpp.git
    cd socket.io-client-cpp
    git submodule init
    git submodule update
else
    cd socket.io-client-cpp
fi

if [ -f ".build_complete" ]; then
    echo "✅ [1/6] Socket.IO Client already built. Skipping..."
else
    echo "🏗️  [1/6] Building Socket.IO Client..."

    # --- PATCHING SOCKET IO ---
    if grep -q "const SizeType length;" lib/rapidjson/include/rapidjson/document.h; then
        echo "🔧 Patching rapidjson/document.h..."
        sed -i 's/const SizeType length;/SizeType length;/g' lib/rapidjson/include/rapidjson/document.h
    fi

    echo "🔧 Enforcing CMake minimum version 3.5..."
    sed -i 's/cmake_minimum_required(VERSION .*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        -DBUILD_UNIT_TESTS=OFF \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        ..
    make $MAKE_JOBS
    make install

    # Tandai sukses
    cd ..
    touch .build_complete
fi

# ==========================================
# 2. G2O (Source - CRITICAL)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "g2o" ]; then
    echo "⬇️  [2/6] Cloning g2o..."
    git clone https://github.com/RainerKuemmerle/g2o.git
    cd g2o
    git checkout 20230223_git
else
    cd g2o
fi

if [ -f ".build_complete" ]; then
    echo "✅ [2/6] g2o already built. Skipping..."
else
    echo "🏗️  [2/6] Building g2o..."

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_UNITTESTS=OFF \
        -DG2O_USE_CHOLMOD=OFF \
        -DG2O_USE_CSPARSE=ON \
        -DG2O_USE_OPENGL=OFF \
        -DG2O_USE_OPENMP=ON \
        -DG2O_BUILD_APPS=OFF \
        -DG2O_BUILD_EXAMPLES=OFF \
        -DG2O_BUILD_LINKED_APPS=OFF \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        ..
    make $MAKE_JOBS
    make install
    cd ..

    # --- FIX OPENGL DEPENDENCY ERROR ---
    echo "🔧 Patching installed g2oConfig.cmake to remove OpenGL dependency..."
    find "$CONDA_PREFIX" -name "g2oConfig.cmake" -exec sed -i '/find_dependency(OpenGL)/d' {} +

    touch .build_complete
fi

# ==========================================
# 3. FBoW (Source)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "FBoW" ]; then
    echo "⬇️  [3/6] Cloning FBoW..."
    git clone https://github.com/stella-cv/FBoW.git
else
    cd "FBoW"
fi

if [ -f ".build_complete" ]; then
    echo "✅ [3/6] FBoW already built. Skipping..."
else
    echo "🏗️  [3/6] Building FBoW..."

    if [ -f "src/fbow.cpp" ]; then
        echo "🔧 Patching FBoW/src/fbow.cpp..."
        sed -i 's/memset(&_params,0,sizeof(_params));/_params = {};/g' src/fbow.cpp
    fi

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        ..
    make $MAKE_JOBS
    make install
    cd ..
    touch .build_complete
fi

# ==========================================
# 4. STELLA VSLAM CORE (Source)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "stella_vslam" ]; then
    echo "⬇️  [4/6] Cloning Stella VSLAM Core..."
    git clone --recursive https://github.com/stella-cv/stella_vslam.git
fi
cd stella_vslam

if [ -f ".build_complete" ]; then
    echo "✅ [4/6] Stella VSLAM Core already built. Skipping..."
else
    echo "🏗️  [4/6] Building Stella VSLAM Core..."

    # --- FIX: Patch CMake Version for Stella Core ---
    echo "🔧 Enforcing CMake minimum version 3.5 for Stella VSLAM..."
    sed -i 's/cmake_minimum_required(VERSION .*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        -DUSE_PANGOLIN_VIEWER=OFF \
        -DUSE_IRIDESCENCE_VIEWER=OFF \
        -DUSE_SOCKET_PUBLISHER=ON \
        -DCMAKE_DISABLE_FIND_PACKAGE_OpenGL=TRUE \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        ..
    make $MAKE_JOBS
    make install
    cd ..
    touch .build_complete
fi

# ==========================================
# 5. SOCKET PUBLISHER PLUGIN (Source)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "socket_publisher" ]; then
    echo "⬇️  [5/6] Cloning Socket Publisher Plugin..."
    git clone --recursive https://github.com/stella-cv/socket_publisher.git
fi
cd socket_publisher

if [ -f ".build_complete" ]; then
    echo "✅ [5/6] Socket Publisher Plugin already built. Skipping..."
else
    echo "🏗️  [5/6] Building Socket Publisher Plugin..."

    # Patch Code
    if [ -f "src/data_serializer.cc" ]; then
        echo "🔧 Patching socket_publisher/src/data_serializer.cc..."
        sed -i 's/map.release_current_frame();/(void)map.release_current_frame();/g' src/data_serializer.cc
    fi

    # --- FIX: Patch CMake Version for Socket Publisher ---
    echo "🔧 Enforcing CMake minimum version 3.5 for Socket Publisher..."
    sed -i 's/cmake_minimum_required(VERSION .*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        ..
    make $MAKE_JOBS
    make install
    cd ..
    touch .build_complete
fi

# ==========================================
# 6. EXAMPLES (Source)
# ==========================================
echo ""
cd "$LIB_DIR"
if [ ! -d "stella_vslam_examples" ]; then
    echo "⬇️  [6/6] Cloning Examples..."
    git clone --recursive https://github.com/stella-cv/stella_vslam_examples.git
fi
cd stella_vslam_examples

if [ -f ".build_complete" ]; then
    echo "✅ [6/6] Examples already built. Skipping..."
else
    echo "🏗️  [6/6] Building Examples..."

    # --- FIX: Patch CMake Version for Examples ---
    echo "🔧 Enforcing CMake minimum version 3.5 for Examples..."
    sed -i 's/cmake_minimum_required(VERSION .*)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX \
        -DCMAKE_PREFIX_PATH=$CONDA_PREFIX \
        -DUSE_STACK_TRACE_LOGGER=OFF \
        -DCMAKE_CXX_FLAGS="$COMMON_CXX_FLAGS" \
        ..
    make $MAKE_JOBS
    # Contoh tidak perlu make install, cukup build

    cd ..
    touch .build_complete
fi

echo ""
echo "✅ BUILD COMPLETE!"
echo "Executables are in: $LIB_DIR/stella_vslam_examples/build/"