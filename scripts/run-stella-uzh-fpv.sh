#!/bin/bash
set -euo pipefail

# Jalankan contoh monocular dengan dataset UZH-FPV (pilih sequence lewat argumen).
# Gunakan: pixi run bash scripts/run-stella-uzh-fpv.sh --dataset /path/to/uzh-fpv[/img]

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
LIB_DIR="$PROJECT_ROOT/lib"
DATASET_DIR="$PROJECT_ROOT/dataset"
EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples"
BUILD_DIR="$EXAMPLES_DIR/build"

VOCAB="$DATASET_DIR/orb_vocab.fbow"
CONFIG="$LIB_DIR/stella_vslam/example/uzh_fpv/UZH_FPV_mono.yaml"

# Default dataset location (override via SRC_DATASET)
SRC_DATASET="${SRC_DATASET:-$HOME/Downloads/py-vslam/datasets/uzh-fpv}"

# Argumen opsional: --dataset /path/to/uzh-fpv atau /path/to/uzh-fpv/img
if [ $# -ge 2 ] && [ "$1" = "--dataset" ]; then
    SRC_DATASET="$2"
    shift 2
fi

# Jika user menunjuk langsung ke folder img/, naik satu level agar ketemu left_images.txt
if [ -d "$SRC_DATASET" ] && [ -f "$SRC_DATASET/left_images.txt" ]; then
    :
elif [ -d "$SRC_DATASET" ] && [ -d "$SRC_DATASET/img" ]; then
    :
elif [ -d "$SRC_DATASET/.." ] && [ -f "$SRC_DATASET/../left_images.txt" ]; then
    SRC_DATASET="$(cd "$SRC_DATASET/.." && pwd)"
fi
DATASET_NAME="$(basename "$SRC_DATASET")"
PREPARED_DIR="$DATASET_DIR/uzh_fpv_${DATASET_NAME}_mono"
PREPARED_IMG_DIR="$PREPARED_DIR/img"

echo "=========================================="
echo "   RUN STELLA VSLAM - UZH FPV (MONO)"
echo "=========================================="
echo "SRC_DATASET    : $SRC_DATASET"
echo "OUTPUT DATASET : $PREPARED_IMG_DIR"
echo "CONFIG         : $CONFIG"
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
IMG_DIR="$SRC_DATASET/img"
if [ ! -d "$IMG_DIR" ]; then
    echo "❌ Folder $IMG_DIR tidak ditemukan. Pastikan dataset UZH-FPV sudah diekstrak."
    exit 1
fi

# 2. Siapkan dataset: symlink gambar kiri dengan nama terurut 000000.png, 000001.png, ...
if [ ! -d "$PREPARED_IMG_DIR" ] || [ -z "$(ls -A "$PREPARED_IMG_DIR" 2>/dev/null)" ]; then
    echo "🔗 Menyiapkan symlink gambar kiri ke $PREPARED_IMG_DIR ..."
    mkdir -p "$PREPARED_IMG_DIR"
    pixi run python - "$SRC_DATASET" "$PREPARED_IMG_DIR" <<'PY'
import sys, pathlib, os
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
        _, _, rel_path = parts[0], parts[1], parts[2]
        lines.append(rel_path)

for idx, rel_path in enumerate(lines):
    src_img = src_root / rel_path
    if not src_img.exists():
        raise SystemExit(f"Gambar tidak ditemukan: {src_img}")
    dst_img = dst_dir / f"{idx:06d}{src_img.suffix}"
    if dst_img.exists():
        continue
    # symlink supaya cepat & hemat disk
    os.symlink(src_img.resolve(), dst_img)
print(f"Total {len(lines)} gambar kiri disiapkan.")
PY
else
    echo "✅ Dataset siap di $PREPARED_IMG_DIR"
fi

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
