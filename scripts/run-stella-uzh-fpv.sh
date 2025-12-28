#!/bin/bash
set -euo pipefail

# Jalankan contoh monocular dengan dataset UZH-FPV (pilih sequence lewat argumen).
# Gunakan: pixi run bash scripts/run-stella-uzh-fpv.sh --dataset /path/to/uzh-fpv[/img] --config /path/to/UZH_FPV_mono.yaml

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
DATASET_DIR="$PROJECT_ROOT/dataset"
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
BUILD_DIR="$EXAMPLES_DIR/build"

VOCAB="$DATASET_DIR/orb_vocab.fbow"
CONFIG="$PROJECT_ROOT/config/UZH_FPV_mono.yaml"

# Default dataset location (override via SRC_DATASET)
SRC_DATASET="${SRC_DATASET:-$HOME/Downloads/py-vslam/datasets/uzh-fpv}"

# Argumen opsional: --dataset /path/to/uzh-fpv atau /path/to/uzh-fpv/img
# Argumen opsional: --config /path/to/UZH_FPV_mono.yaml
while [ $# -gt 0 ]; do
    case "$1" in
        --dataset)
            if [ $# -lt 2 ]; then
                echo "❌ --dataset membutuhkan path."
                exit 1
            fi
            SRC_DATASET="$2"
            shift 2
            ;;
        --config)
            if [ $# -lt 2 ]; then
                echo "❌ --config membutuhkan path."
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

# Jika path relatif, coba resolve terhadap cwd lalu project root
if [ "${SRC_DATASET:0:1}" != "/" ]; then
    if [ -d "$SRC_DATASET" ]; then
        SRC_DATASET="$(cd "$SRC_DATASET" && pwd)"
    elif [ -d "$PROJECT_ROOT/$SRC_DATASET" ]; then
        SRC_DATASET="$(cd "$PROJECT_ROOT/$SRC_DATASET" && pwd)"
    fi
fi

# Jika config relatif, coba resolve terhadap cwd lalu project root
if [ "${CONFIG:0:1}" != "/" ]; then
    if [ -f "$CONFIG" ]; then
        CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
    elif [ -f "$PROJECT_ROOT/$CONFIG" ]; then
        CONFIG="$(cd "$PROJECT_ROOT" && pwd)/$CONFIG"
    fi
fi

# Jika user menunjuk langsung ke folder img/, naik satu level agar ketemu left_images.txt
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

# 1. Cek vocab + config
if [ ! -f "$VOCAB" ]; then
    echo "❌ orb_vocab.fbow belum ada di $VOCAB. Jalankan scripts/download-stella-example.sh dulu."
    exit 1
fi
if [ ! -f "$CONFIG" ]; then
    echo "❌ Config $CONFIG tidak ditemukan."
    exit 1
fi
if [ ! -d "$IMG_DIR" ]; then
    echo "❌ Folder $IMG_DIR tidak ditemukan. Pastikan dataset sudah diekstrak dan memiliki folder img."
    exit 1
fi
if [ ! -f "$SRC_DATASET/left_images.txt" ]; then
    echo "❌ left_images.txt tidak ditemukan. Script ini hanya memakai cam0/left."
    exit 1
fi
FIRST_REL="$(awk 'NF>=3 && $1 !~ /^#/ {print $3; exit}' "$SRC_DATASET/left_images.txt")"
if [ -n "$FIRST_REL" ] && [ ! -f "$SRC_DATASET/$FIRST_REL" ]; then
    echo "❌ Gambar pertama dari left_images.txt tidak ditemukan: $SRC_DATASET/$FIRST_REL"
    exit 1
fi

# 2. Siapkan urutan cam0/left sesuai left_images.txt (pakai symlink sementara)
PREPARED_IMG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/uzh_fpv_mono.XXXXXX")"
cleanup() {
    if [ -n "${PREPARED_IMG_DIR:-}" ] && [ -d "$PREPARED_IMG_DIR" ]; then
        rm -rf "$PREPARED_IMG_DIR"
    fi
}
trap cleanup EXIT

echo "🔗 Menyiapkan symlink gambar kiri ke $PREPARED_IMG_DIR ..."
pixi run python - "$SRC_DATASET" "$PREPARED_IMG_DIR" <<'PY'
import os
import pathlib
import sys

src_root = pathlib.Path(sys.argv[1])
dst_dir = pathlib.Path(sys.argv[2])
left_list = src_root / "left_images.txt"

if not left_list.exists():
    raise SystemExit(f"left_images.txt tidak ditemukan di {src_root}")

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
    raise SystemExit(f"Tidak ada entri gambar di {left_list}")

for idx, rel_path in enumerate(lines):
    src_img = src_root / rel_path
    if not src_img.exists():
        raise SystemExit(f"Gambar tidak ditemukan: {src_img}")
    dst_img = dst_dir / f"{idx:06d}{src_img.suffix}"
    os.symlink(src_img.resolve(), dst_img)
print(f"Total {len(lines)} gambar kiri disiapkan.")
PY
echo "✅ Urutan gambar siap dari left_images.txt."

# 3. Pastikan contoh sudah ter-clone & ter-build
if [ ! -d "$EXAMPLES_DIR" ]; then
    echo "⬇️  Cloning stella_vslam_examples..."
    mkdir -p "$LIB_DIR"
    cd "$LIB_DIR"
    git clone --recursive https://github.com/stella-cv/stella_vslam_examples.git
else
    cd "$EXAMPLES_DIR"
    if [ ! -f "3rd/filesystem/include/ghc/filesystem.hpp" ]; then
        echo "  📦 Inisialisasi submodule..."
        git submodule update --init --recursive
    fi
fi

if [ ! -x "$BUILD_DIR/run_image_slam" ]; then
    echo "🔨 Build run_image_slam..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
    make -j"$(nproc)"
fi

# 4. Jalankan SLAM
echo ""
echo "🚀 Menjalankan run_image_slam..."
cd "$BUILD_DIR"
./run_image_slam \
    -v "$VOCAB" \
    -d "$PREPARED_IMG_DIR" \
    -c "$CONFIG" \
    --frame-skip 1 \
    --viewer pangolin_viewer \
    --no-sleep
