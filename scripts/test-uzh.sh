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

VOCAB="$DATASET_DIR/orb_vocab.fbow"
CONFIG="$PROJECT_ROOT/lib/stella_vslam/example/uzh_fpv/UZH_FPV_mono.yaml"
SRC_DATASET="$DATASET_DIR/indoor_forward_3_snapdragon_with_gt"

# Args: --dataset /path/to/uzh-fpv[/img], --config /path/to/UZH_FPV_mono.yaml
while [ $# -gt 0 ]; do
    case "$1" in
        --dataset)
            if [ $# -lt 2 ]; then
                echo "❌ --dataset requires a path."
                exit 1
            fi
            SRC_DATASET="$2"
            shift 2
            ;;
        --config)
            if [ $# -lt 2 ]; then
                echo "❌ --config requires a path."
                exit 1
            fi
            CONFIG="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Resolve dataset path
if [ "${SRC_DATASET:0:1}" != "/" ]; then
    if [ -d "$SRC_DATASET" ]; then
        SRC_DATASET="$(cd "$SRC_DATASET" && pwd)"
    elif [ -d "$PROJECT_ROOT/$SRC_DATASET" ]; then
        SRC_DATASET="$(cd "$PROJECT_ROOT/$SRC_DATASET" && pwd)"
    fi
fi

# Resolve config path
if [ "${CONFIG:0:1}" != "/" ]; then
    if [ -f "$CONFIG" ]; then
        CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
    elif [ -f "$PROJECT_ROOT/$CONFIG" ]; then
        CONFIG="$(cd "$PROJECT_ROOT" && pwd)/$CONFIG"
    fi
fi

# If user points to img/, go up to dataset root
if [ -d "$SRC_DATASET" ] && [ -f "$SRC_DATASET/left_images.txt" ]; then
    :
elif [ -d "$SRC_DATASET" ] && [ -d "$SRC_DATASET/img" ]; then
    :
elif [ -d "$SRC_DATASET/.." ] && [ -f "$SRC_DATASET/../left_images.txt" ]; then
    SRC_DATASET="$(cd "$SRC_DATASET/.." && pwd)"
fi
IMG_DIR="$SRC_DATASET/img"

echo "=========================================="
echo "   RUN STELLA VSLAM - UZH FPV (MONO)"
echo "=========================================="
echo "SRC_DATASET    : $SRC_DATASET"
echo "IMAGE DIR      : $IMG_DIR"
echo "CONFIG         : $CONFIG"
echo "IMAGE LIST     : left_images.txt (cam0/left)"
echo ""

# 1. Check dataset + config
if [ ! -f "$VOCAB" ]; then
    echo "❌ orb_vocab.fbow missing at $VOCAB. Run scripts/dataset.sh first."
    exit 1
fi
if [ ! -f "$CONFIG" ]; then
    echo "❌ Config not found: $CONFIG"
    exit 1
fi
if [ ! -d "$IMG_DIR" ]; then
    echo "❌ Image folder not found: $IMG_DIR"
    exit 1
fi
if [ ! -f "$SRC_DATASET/left_images.txt" ]; then
    echo "❌ left_images.txt not found in $SRC_DATASET"
    exit 1
fi
FIRST_REL="$(awk 'NF>=3 && $1 !~ /^#/ {print $3; exit}' "$SRC_DATASET/left_images.txt")"
if [ -n "$FIRST_REL" ] && [ ! -f "$SRC_DATASET/$FIRST_REL" ]; then
    echo "❌ First image from left_images.txt not found: $SRC_DATASET/$FIRST_REL"
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

# 3. Build example if needed
if [ ! -x "$BUILD_DIR/run_image_slam" ]; then
    echo "🔨 Building run_image_slam..."
    prepare_build_dir "$EXAMPLES_DIR" "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
    make -j"$(nproc)"
fi

# 4. Prepare image sequence (symlinks ordered by left_images.txt)
PREPARED_IMG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/uzh_fpv_mono.XXXXXX")"
cleanup() {
    if [ -n "${PREPARED_IMG_DIR:-}" ] && [ -d "$PREPARED_IMG_DIR" ]; then
        rm -rf "$PREPARED_IMG_DIR"
    fi
}
trap cleanup EXIT

echo "🔗 Preparing ordered symlink images in $PREPARED_IMG_DIR ..."
python - "$SRC_DATASET" "$PREPARED_IMG_DIR" <<'PY'
import os
import pathlib
import sys

src_root = pathlib.Path(sys.argv[1])
dst_dir = pathlib.Path(sys.argv[2])
left_list = src_root / "left_images.txt"

if not left_list.exists():
    raise SystemExit(f"left_images.txt not found in {src_root}")

lines = []
with left_list.open() as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        lines.append(parts[2])

if not lines:
    raise SystemExit(f"No image entries found in {left_list}")

for idx, rel_path in enumerate(lines):
    src_img = src_root / rel_path
    if not src_img.exists():
        raise SystemExit(f"Image not found: {src_img}")
    dst_img = dst_dir / f"{idx:06d}{src_img.suffix}"
    os.symlink(src_img.resolve(), dst_img)
print(f"Prepared {len(lines)} images.")
PY

echo ""
echo "🚀 Running run_image_slam..."
cd "$BUILD_DIR"
./run_image_slam \
    -v "$VOCAB" \
    -d "$PREPARED_IMG_DIR" \
    -c "$CONFIG" \
    --frame-skip 1 \
    --viewer pangolin_viewer
