#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"

BUILD_JOBS=8
echo "INFO: Building with $BUILD_JOBS jobs"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--all] [--iridescence|--irisdecence] [--pangolin] [--socket]

Examples:
  pixi run build-deps -- --all
  pixi run build-deps -- --pangolin
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
    echo "ERROR: No dependency selected."
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

prepare_build_dir() {
    local src_dir="$1"
    local build_dir="$2"
    local cache_file="$build_dir/CMakeCache.txt"
    local src_dir_abs="$src_dir"

    if [ -d "$src_dir" ]; then
        src_dir_abs="$(cd "$src_dir" && pwd -P)"
    fi

    if [ -f "$cache_file" ]; then
        local cached_src
        cached_src=$(grep -m 1 "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$cache_file" | cut -d= -f2-)
        if [ -n "$cached_src" ] && [ "$cached_src" != "$src_dir_abs" ]; then
            echo "INFO: Removing stale build dir $build_dir (was configured for $cached_src)"
            rm -rf "$build_dir"
        fi
    fi

    mkdir -p "$build_dir"
}

mkdir -p "$LIB_DIR"

# Ensure OpenGL symlinks exist BEFORE building anything
# This is critical for CMake to find libOpenGL.so (unversioned)
echo "Ensuring OpenGL/EGL symlinks in Pixi environment..."
ensure_gl_symlink() {
    local link_path="$1"
    local target_path="$2"
    if [ ! -e "$link_path" ] && [ -e "$target_path" ]; then
        ln -s "$(basename "$target_path")" "$link_path"
        echo "  Created: $(basename "$link_path") -> $(basename "$target_path")"
    elif [ -e "$link_path" ]; then
        echo "  OK: $(basename "$link_path") already exists"
    else
        echo "  WARNING: Target $(basename "$target_path") not found (symlink will be created during Pangolin build)"
    fi
}

ensure_gl_symlink "$CONDA_PREFIX/lib/libOpenGL.so" "$CONDA_PREFIX/lib/libOpenGL.so.0"
ensure_gl_symlink "$CONDA_PREFIX/lib/libEGL.so" "$CONDA_PREFIX/lib/libEGL.so.1"

# Viewer dependencies
if [ "$BUILD_IRIDESCENCE" -eq 1 ]; then
    require_repo "$LIB_DIR/iridescence" "iridescence"

    echo "Building iridescence..."
    cd "$LIB_DIR/iridescence"

    prepare_build_dir "$LIB_DIR/iridescence" "$LIB_DIR/iridescence/build"
    cd "$LIB_DIR/iridescence/build"
    cmake \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_SYSTEM_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
        -DCMAKE_SKIP_BUILD_RPATH=TRUE \
        -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
        -DIridescence_INCLUDE_DIRS="$CONDA_PREFIX/include/iridescence" \
        -DIridescence_LIBRARY="$CONDA_PREFIX/lib/libiridescence.so" \
        -Dgl_imgui_LIBRARY="$CONDA_PREFIX/lib/libgl_imgui.so" \
        ..
    make -j"$BUILD_JOBS"
    make install

    IRIDESCENCE_LIB="$CONDA_PREFIX/lib/libiridescence.so"
    GL_IMGUI_LIB="$CONDA_PREFIX/lib/libgl_imgui.so"
    if [ -f "$IRIDESCENCE_LIB" ] && [ ! -e "$GL_IMGUI_LIB" ]; then
        ln -sf "$(basename "$IRIDESCENCE_LIB")" "$GL_IMGUI_LIB"
        if [ -f "$CONDA_PREFIX/lib/libiridescence.so.1" ] && [ ! -e "$CONDA_PREFIX/lib/libgl_imgui.so.1" ]; then
            ln -sf "$(basename "$CONDA_PREFIX/lib/libiridescence.so.1")" "$CONDA_PREFIX/lib/libgl_imgui.so.1"
        fi
    fi
fi

if [ "$BUILD_PANGOLIN" -eq 1 ]; then
    require_repo "$LIB_DIR/Pangolin" "Pangolin"

    echo "Building Pangolin..."
    PANGOLIN_DIR="$LIB_DIR/Pangolin"
    PANGOLIN_PATCH_MARKER="$PANGOLIN_DIR/.codex_file_utils_patch"
    PANGOLIN_FILE_UTILS="$PANGOLIN_DIR/src/utils/file_utils.cpp"
    PANGOLIN_PACKET_TAGS="$PANGOLIN_DIR/include/pangolin/log/packetstream_tags.h"

    if [ -f "$PANGOLIN_FILE_UTILS" ] && [ ! -f "$PANGOLIN_PATCH_MARKER" ]; then
        sed -i -e "193,198d" "$PANGOLIN_FILE_UTILS"
        touch "$PANGOLIN_PATCH_MARKER"
    fi

    if [ -f "$PANGOLIN_PACKET_TAGS" ] && ! grep -q "#include <cstdint>" "$PANGOLIN_PACKET_TAGS"; then
        sed -i '/#pragma once/a #include <cstdint>' "$PANGOLIN_PACKET_TAGS"
    fi

    cd "$PANGOLIN_DIR"
    prepare_build_dir "$PANGOLIN_DIR" "$PANGOLIN_DIR/build"
    cd "$PANGOLIN_DIR/build"
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX:/usr" \
        -DCMAKE_SYSTEM_PREFIX_PATH="$CONDA_PREFIX:/usr" \
        -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
        -DCMAKE_SKIP_BUILD_RPATH=TRUE \
        -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
        -DOpenGL_GL_PREFERENCE=GLVND \
        -DOPENGL_gl_LIBRARY="$CONDA_PREFIX/lib/libGL.so" \
        -DOPENGL_glx_LIBRARY="$CONDA_PREFIX/lib/libGLX.so" \
        -DOPENGL_opengl_LIBRARY="$CONDA_PREFIX/lib/libOpenGL.so" \
        -DOPENGL_egl_LIBRARY="$CONDA_PREFIX/lib/libEGL.so" \
        -DEGL_LIBRARY="$CONDA_PREFIX/lib/libEGL.so" \
        -DCMAKE_CXX_FLAGS="-Wno-stringop-truncation -Wno-deprecated-copy -Wno-parentheses -Wno-unused-parameter -Wno-maybe-uninitialized" \
        -DBUILD_EXAMPLES=OFF \
        -DBUILD_TOOLS=OFF \
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
    make -j"$BUILD_JOBS"
    make install
fi

if [ "$BUILD_SOCKET" -eq 1 ]; then
    require_repo "$LIB_DIR/socket.io-client-cpp" "socket.io-client-cpp"

    echo "Building socket.io-client-cpp..."
    SOCKET_DIR="$LIB_DIR/socket.io-client-cpp"
    SOCKET_RAPIDJSON="$SOCKET_DIR/lib/rapidjson/include/rapidjson/document.h"

    if [ -f "$SOCKET_RAPIDJSON" ]; then
        sed -i 's/const SizeType length;/SizeType length;/g' "$SOCKET_RAPIDJSON"
    fi

    cd "$SOCKET_DIR"
    prepare_build_dir "$SOCKET_DIR" "$SOCKET_DIR/build"
    cd "$SOCKET_DIR/build"
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$CONDA_PREFIX" \
        -DCMAKE_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_SYSTEM_PREFIX_PATH="$CONDA_PREFIX" \
        -DCMAKE_IGNORE_PREFIX_PATH=/usr/local \
        -DCMAKE_SKIP_BUILD_RPATH=TRUE \
        -DCMAKE_SKIP_INSTALL_RPATH=TRUE \
        -DCMAKE_CXX_FLAGS="-Wno-stringop-truncation -Wno-deprecated-copy" \
        -DBUILD_UNIT_TESTS=OFF \
        ..
    make -j"$BUILD_JOBS"
    make install

    SOCKET_TLS_LINK="$SOCKET_DIR/build/libsioclient_tls.so"
    if [ -f "$SOCKET_TLS_LINK" ]; then
        SOCKET_TLS_REAL="$(readlink -f "$SOCKET_TLS_LINK")"
        if [ -f "$SOCKET_TLS_REAL" ]; then
            echo "Installing libsioclient_tls.so into Pixi env..."
            install -m 755 "$SOCKET_TLS_REAL" "$CONDA_PREFIX/lib/$(basename "$SOCKET_TLS_REAL")"
            ln -sf "$(basename "$SOCKET_TLS_REAL")" "$CONDA_PREFIX/lib/libsioclient_tls.so.1"
            ln -sf "libsioclient_tls.so.1" "$CONDA_PREFIX/lib/libsioclient_tls.so"
        fi
    fi
fi

# AirSim setup (headers + deps used by examples)
require_repo "$LIB_DIR/AirSim" "AirSim"

echo "Setting up AirSim dependencies..."
cd "$LIB_DIR/AirSim"

if [ ! -d "AirLib/deps/eigen3/Eigen" ]; then
    echo "Downloading Eigen..."
    mkdir -p AirLib/deps
    if [ ! -s "AirLib/deps/eigen3.zip" ]; then
        rm -f AirLib/deps/eigen3.zip
        wget -q https://gitlab.com/libeigen/eigen/-/archive/3.3.7/eigen-3.3.7.zip -O AirLib/deps/eigen3.zip
    fi
    unzip -q AirLib/deps/eigen3.zip -d AirLib/deps/
    mv AirLib/deps/eigen-3.3.7 AirLib/deps/eigen3
else
    echo "Eigen already present."
fi

if [ ! -d "external/rpclib/rpclib-2.3.0" ]; then
    echo "Downloading rpclib..."
    mkdir -p external/rpclib
    if [ ! -s "external/rpclib/rpclib-2.3.0.zip" ]; then
        rm -f external/rpclib/rpclib-2.3.0.zip
        wget -q https://github.com/rpclib/rpclib/archive/v2.3.0.zip -O external/rpclib/rpclib-2.3.0.zip
    fi
    unzip -q external/rpclib/rpclib-2.3.0.zip -d external/rpclib/
else
    echo "rpclib already present."
fi

if [ ! -d "AirLib/include" ]; then
    echo "ERROR: AirLib/include not found."
    exit 1
fi

echo "AirSim setup complete."
