#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--all] [--iridescence|--irisdecence] [--pangolin] [--socket]

Examples:
  pixi run build -- --all
  pixi run build -- --pangolin
EOF
}

BUILD_IRIDESCENCE=0
BUILD_PANGOLIN=0
BUILD_SOCKET=0

if [ "${1:-}" = "--" ]; then
    shift
fi

if [ $# -eq 0 ]; then
    BUILD_IRIDESCENCE=1
    BUILD_PANGOLIN=1
    BUILD_SOCKET=1
fi

for arg in "$@"; do
    case "$arg" in
        --all)
            BUILD_IRIDESCENCE=1
            BUILD_PANGOLIN=1
            BUILD_SOCKET=1
            ;;
        --iridescence|--irisdecence)
            BUILD_IRIDESCENCE=1
            ;;
        --pangolin)
            BUILD_PANGOLIN=1
            ;;
        --socket)
            BUILD_SOCKET=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

if [ "$BUILD_IRIDESCENCE" -eq 0 ] && [ "$BUILD_PANGOLIN" -eq 0 ] && [ "$BUILD_SOCKET" -eq 0 ]; then
    echo "ERROR: No viewer plugin selected."
    usage
    exit 1
fi

if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Run inside the Pixi environment (pixi shell)."
    exit 1
fi

require_repo() {
    local path="$1"
    local name="$2"
    if [ ! -d "$path" ]; then
        echo "ERROR: Missing $name at $path"
        echo "       Make sure the dependency exists under lib/."
        exit 1
    fi
}

cmake_bool() {
    if [ "$1" -eq 1 ]; then
        echo "ON"
    else
        echo "OFF"
    fi
}

require_repo "$LIB_DIR/stella_vslam" "stella_vslam"
require_repo "$LIB_DIR/stella_vslam_examples" "stella_vslam_examples"
require_repo "$LIB_DIR/AirSim" "AirSim"

# Patch FBoW to fix class-memaccess warning
FBoW_CPP="$LIB_DIR/stella_vslam/3rd/FBoW/src/fbow.cpp"
if [ -f "$FBoW_CPP" ]; then
    sed -i 's/memset(&_params,0,sizeof(_params));/_params = {};/g' "$FBoW_CPP"
fi

echo "Building FBoW (shared)..."
cd "$LIB_DIR/stella_vslam/3rd/FBoW"
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
    -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DBUILD_SHARED_LIBS=ON \
    ..
make -j"$(nproc)"
make install

echo "Building stella_vslam core..."
cd "$LIB_DIR/stella_vslam"
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
    -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-maybe-uninitialized" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DUSE_PANGOLIN_VIEWER="$(cmake_bool "$BUILD_PANGOLIN")" \
    -DUSE_IRIDESCENCE_VIEWER="$(cmake_bool "$BUILD_IRIDESCENCE")" \
    -DUSE_SOCKET_PUBLISHER="$(cmake_bool "$BUILD_SOCKET")" \
    ..
make -j"$(nproc)"
make install

if [ "$BUILD_IRIDESCENCE" -eq 1 ]; then
    require_repo "$LIB_DIR/iridescence_viewer" "iridescence_viewer"

    echo "Building plugin: iridescence_viewer"
    IRIDESCENCE_LIB="$CONDA_PREFIX/lib/libiridescence.so"
    GL_IMGUI_LIB="$CONDA_PREFIX/lib/libgl_imgui.so"
    if [ -f "$IRIDESCENCE_LIB" ] && [ ! -e "$GL_IMGUI_LIB" ]; then
        ln -sf "$(basename "$IRIDESCENCE_LIB")" "$GL_IMGUI_LIB"
        if [ -f "$CONDA_PREFIX/lib/libiridescence.so.1" ] && [ ! -e "$CONDA_PREFIX/lib/libgl_imgui.so.1" ]; then
            ln -sf "$(basename "$CONDA_PREFIX/lib/libiridescence.so.1")" "$CONDA_PREFIX/lib/libgl_imgui.so.1"
        fi
    fi

    cd "$LIB_DIR/iridescence_viewer"
    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_SYSTEM_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
        -DOpenGL_GL_PREFERENCE=GLVND \
        -DCMAKE_POLICY_DEFAULT_CMP0072=NEW \
        -DIridescence_INCLUDE_DIRS="$CONDA_PREFIX/include/iridescence" \
        -DIridescence_LIBRARY="$CONDA_PREFIX/lib/libiridescence.so" \
        -Dgl_imgui_LIBRARY="$CONDA_PREFIX/lib/libgl_imgui.so" \
        ..
    make -j"$(nproc)"
    make install
fi

if [ "$BUILD_PANGOLIN" -eq 1 ]; then
    require_repo "$LIB_DIR/pangolin_viewer" "pangolin_viewer"

    echo "Building plugin: pangolin_viewer"
    cd "$LIB_DIR/pangolin_viewer"
    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
        -DOpenGL_GL_PREFERENCE=GLVND \
        -DCMAKE_POLICY_DEFAULT_CMP0072=NEW \
        ..
    make -j"$(nproc)"
    make install
fi

if [ "$BUILD_SOCKET" -eq 1 ]; then
    require_repo "$LIB_DIR/socket_publisher" "socket_publisher"

    echo "Building plugin: socket_publisher"
    SOCKET_PUBLISHER_CPP="$LIB_DIR/socket_publisher/src/data_serializer.cc"
    if [ -f "$SOCKET_PUBLISHER_CPP" ]; then
        sed -i 's/map.release_current_frame();/(void)map.release_current_frame();/g' "$SOCKET_PUBLISHER_CPP"
    fi

    cd "$LIB_DIR/socket_publisher"
    mkdir -p build && cd build
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
        -DOpenGL_GL_PREFERENCE=GLVND \
        -DCMAKE_POLICY_DEFAULT_CMP0072=NEW \
        ..
    make -j"$(nproc)"
    make install
fi

# Prepare examples
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
CUSTOM_EXAMPLES_SRC="$PROJECT_ROOT/code/stella-vslam/examples"
cd "$EXAMPLES_DIR"

if [ -d "$CUSTOM_EXAMPLES_SRC/src" ]; then
    cp -v "$CUSTOM_EXAMPLES_SRC/src/run_camera_airsim_slam.cc" src/
    cp -v "$CUSTOM_EXAMPLES_SRC/src/run_camera_airsim_log_slam.cc" src/

    if [ -f "CMakeLists.txt" ] && [ ! -f "CMakeLists.txt.original" ]; then
        cp CMakeLists.txt CMakeLists.txt.original
    fi

    if [ -f "$CUSTOM_EXAMPLES_SRC/CMakeLists.txt" ]; then
        cp -v "$CUSTOM_EXAMPLES_SRC/CMakeLists.txt" .
    fi
else
    echo "INFO: Custom examples not found at $CUSTOM_EXAMPLES_SRC"
    echo "      Building upstream examples only."
fi

# Build examples
cd "$EXAMPLES_DIR"
mkdir -p build && cd build
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
    -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
    -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
    -DCMAKE_CXX_FLAGS="-Wno-class-memaccess -Wno-unused-variable -Wno-unused-parameter -Wno-deprecated-copy -Wno-deprecated-declarations -Wno-stringop-truncation" \
    -DCMAKE_POLICY_DEFAULT_CMP0074=NEW \
    -DOpenGL_GL_PREFERENCE=GLVND \
    -DCMAKE_POLICY_DEFAULT_CMP0072=NEW \
    -DUSE_STACK_TRACE_LOGGER=OFF \
    -DAIRSIM_ROOT="$LIB_DIR/AirSim" \
    ..

make -j"$(nproc)"

echo "Build complete."
