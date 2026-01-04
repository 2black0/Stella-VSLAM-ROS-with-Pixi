#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"

MISSING=0
VERSION_MISMATCH=0

if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Run inside the Pixi environment (pixi shell)."
    exit 1
fi

OK_MARK="✅"
FAIL_MARK="❌"

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

mark_ok() {
    echo "${OK_MARK} $1"
}

mark_fail() {
    echo "${FAIL_MARK} $1"
}

get_git_commit() {
    local path="$1"
    if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
        git -C "$path" rev-parse HEAD
    else
        echo ""
    fi
}

get_expected_submodule_commit() {
    local rel_path="$1"
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$PROJECT_ROOT" ls-tree HEAD "$rel_path" 2>/dev/null | awk '$2=="commit"{print $3}'
    else
        echo ""
    fi
}

check_repo() {
    local label="$1"
    local path="$2"
    local expected="$3"

    if [ ! -d "$path" ]; then
        mark_fail "$label repo: $path (missing)"
        MISSING=1
        return
    fi

    local rev
    rev="$(get_git_commit "$path")"
    if [ -z "$rev" ]; then
        if [ -n "$expected" ]; then
            mark_ok "$label repo: $path (vendored, expected $expected)"
        else
            mark_ok "$label repo: $path (vendored)"
        fi
        return
    fi

    if [ -n "$expected" ] && [[ "$rev" != "$expected"* ]]; then
        mark_fail "$label repo: $path (expected $expected, got $rev)"
        VERSION_MISMATCH=1
        return
    fi

    if [ -n "$expected" ]; then
        mark_ok "$label repo: $path (commit $rev, pinned $expected)"
    else
        mark_ok "$label repo: $path (commit $rev)"
    fi
}

format_commit() {
    local path="$1"
    local rev
    rev="$(get_git_commit "$path")"
    if [ -n "$rev" ]; then
        echo "commit $rev"
    else
        echo "vendored"
    fi
}

so_version() {
    local path="$1"
    local target
    target="$(readlink "$path" 2>/dev/null || true)"
    if [ -n "$target" ]; then
        echo "$target"
    else
        echo ""
    fi
}

check_lib() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        local version
        version="$(so_version "$path")"
        if [ -n "$version" ]; then
            mark_ok "$label: $path (version $version)"
        else
            mark_ok "$label: $path"
        fi
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

check_header_dir() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        mark_ok "$label: $path"
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

read_eigen_version() {
    local header="$1"
    if [ -f "$header" ]; then
        local world major minor
        world="$(grep -E "^#define EIGEN_WORLD_VERSION" "$header" | awk '{print $3}')"
        major="$(grep -E "^#define EIGEN_MAJOR_VERSION" "$header" | awk '{print $3}')"
        minor="$(grep -E "^#define EIGEN_MINOR_VERSION" "$header" | awk '{print $3}')"
        if [ -n "$world" ] && [ -n "$major" ] && [ -n "$minor" ]; then
            echo "${world}.${major}.${minor}"
        fi
    fi
}

read_rpclib_version() {
    local header="$1"
    if [ -f "$header" ]; then
        local major minor patch
        major="$(grep -E "^#define RPC_VERSION_MAJOR" "$header" | awk '{print $3}')"
        minor="$(grep -E "^#define RPC_VERSION_MINOR" "$header" | awk '{print $3}')"
        patch="$(grep -E "^#define RPC_VERSION_PATCH" "$header" | awk '{print $3}')"
        if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ]; then
            echo "${major}.${minor}.${patch}"
        fi
    fi
}

read_rpclib_version_fallback() {
    local dir="$1"
    local base
    base="$(basename "$dir")"
    if [[ "$base" == rpclib-* ]]; then
        echo "${base#rpclib-}"
    fi
}

section "Repo Path + Version"
check_repo "iridescence" "$LIB_DIR/iridescence" "$(get_expected_submodule_commit "lib/iridescence")"
check_repo "Pangolin" "$LIB_DIR/Pangolin" "$(get_expected_submodule_commit "lib/Pangolin")"
check_repo "socket.io-client-cpp" "$LIB_DIR/socket.io-client-cpp" ""
check_repo "AirSim" "$LIB_DIR/AirSim" ""

section "Installed Libraries (Path + Version)"
check_lib "libiridescence.so" "$CONDA_PREFIX/lib/libiridescence.so"
check_lib "libpango_core.so" "$CONDA_PREFIX/lib/libpango_core.so"
check_lib "libpango_opengl.so" "$CONDA_PREFIX/lib/libpango_opengl.so"
check_lib "libsioclient.so" "$CONDA_PREFIX/lib/libsioclient.so"

if [ -f "$CONDA_PREFIX/lib/libsioclient_tls.so" ]; then
    check_lib "libsioclient_tls.so" "$CONDA_PREFIX/lib/libsioclient_tls.so"
else
    mark_ok "libsioclient_tls.so: not installed in Pixi env (built artifact checked below)"
fi

section "Build Deps (Path + Version)"
if [ -d "$LIB_DIR/iridescence/build" ]; then
    mark_ok "iridescence build: $LIB_DIR/iridescence/build ($(format_commit "$LIB_DIR/iridescence"))"
else
    mark_fail "iridescence build: $LIB_DIR/iridescence/build (missing)"
    MISSING=1
fi

if [ -d "$LIB_DIR/Pangolin/build" ]; then
    mark_ok "Pangolin build: $LIB_DIR/Pangolin/build ($(format_commit "$LIB_DIR/Pangolin"))"
else
    mark_fail "Pangolin build: $LIB_DIR/Pangolin/build (missing)"
    MISSING=1
fi

SOCKET_BUILD_DIR="$LIB_DIR/socket.io-client-cpp/build"
if [ -d "$SOCKET_BUILD_DIR" ]; then
    SOCKET_SO="$SOCKET_BUILD_DIR/libsioclient.so"
    SOCKET_TLS_SO="$SOCKET_BUILD_DIR/libsioclient_tls.so"
    if [ -f "$SOCKET_SO" ] && [ -f "$SOCKET_TLS_SO" ]; then
        SOCKET_SO_VER="$(so_version "$SOCKET_SO")"
        SOCKET_TLS_VER="$(so_version "$SOCKET_TLS_SO")"
        if [ -n "$SOCKET_SO_VER" ] && [ -n "$SOCKET_TLS_VER" ]; then
            mark_ok "socket.io-client-cpp build: $SOCKET_BUILD_DIR (libsioclient $SOCKET_SO_VER, libsioclient_tls $SOCKET_TLS_VER)"
        else
            mark_ok "socket.io-client-cpp build: $SOCKET_BUILD_DIR (libsioclient + libsioclient_tls present)"
        fi
    else
        mark_fail "socket.io-client-cpp build: $SOCKET_BUILD_DIR (missing libsioclient or libsioclient_tls)"
        MISSING=1
    fi
else
    mark_fail "socket.io-client-cpp build: $SOCKET_BUILD_DIR (missing)"
    MISSING=1
fi

AIRSIM_HEADERS="$LIB_DIR/AirSim/AirLib/include"
EIGEN_DIR="$LIB_DIR/AirSim/AirLib/deps/eigen3/Eigen"
RPCLIB_DIR="$LIB_DIR/AirSim/external/rpclib/rpclib-2.3.0"

if [ -d "$AIRSIM_HEADERS" ]; then
    EIGEN_VERSION="$(read_eigen_version "$EIGEN_DIR/src/Core/util/Macros.h")"
    RPCLIB_VERSION="$(read_rpclib_version "$RPCLIB_DIR/include/rpc/version.h")"
    if [ -z "$RPCLIB_VERSION" ]; then
        RPCLIB_VERSION="$(read_rpclib_version_fallback "$RPCLIB_DIR")"
    fi

    if [ -n "$EIGEN_VERSION" ] && [ -n "$RPCLIB_VERSION" ]; then
        mark_ok "AirSim deps: $LIB_DIR/AirSim (Eigen $EIGEN_VERSION, rpclib $RPCLIB_VERSION)"
    else
        mark_ok "AirSim deps: $LIB_DIR/AirSim"
    fi
else
    mark_fail "AirSim deps: $LIB_DIR/AirSim (missing AirLib/include)"
    MISSING=1
fi

section "Summary"
if [ "$MISSING" -eq 1 ] || [ "$VERSION_MISMATCH" -eq 1 ]; then
    mark_fail "Missing paths or version mismatch detected."
    exit 1
fi

mark_ok "All build-deps artifacts, paths, and versions look good."
