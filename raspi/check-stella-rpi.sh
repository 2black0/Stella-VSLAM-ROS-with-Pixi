#!/bin/bash

# Hentikan script jika ada command yang error
# Kita matikan set -e agar script tetap lanjut meski ada file hilang (untuk reporting)
# set -e

# Mendapatkan lokasi direktori tempat script ini berada (folder 'raspi')
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- FIX PATH ---
# Berdasarkan output tree, folder lib_rpi dan dataset ada DI DALAM folder raspi
LIB_DIR="$SCRIPT_DIR/lib_rpi"
DATASET_DIR="$SCRIPT_DIR/dataset"
BUILD_EXAMPLES_DIR="$LIB_DIR/stella_vslam_examples/build"

# Untuk keperluan display info saja
PROJECT_ROOT="$SCRIPT_DIR/.."

# Counter Error
MISSING_COUNT=0

echo "=========================================="
echo "   CHECK STELLA VSLAM ARTIFACTS (RPi 5)"
echo "   Mode: SocketIO / Non-ROS"
echo "=========================================="
echo "📂 Script Dir   : $SCRIPT_DIR"
echo "📂 Lib Dir      : $LIB_DIR"
echo "📂 Dataset Dir  : $DATASET_DIR"

# 1. Cek Environment Pixi
echo ""
echo "🔍 [1/5] Checking Environment..."
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Script ini harus dijalankan di dalam environment Pixi."
    echo "👉 Silakan jalankan perintah: pixi shell"
    exit 1
fi
echo "✅ Environment Pixi Detected: $CONDA_PREFIX"

# Fungsi helper untuk cek file
check_file() {
    if [ -f "$1" ]; then
        echo "✅ Found: $(basename "$1")"
    else
        echo "❌ MISSING: $1"
        MISSING_COUNT=$((MISSING_COUNT+1))
    fi
}

# Fungsi helper untuk cek library di Conda Prefix
check_lib() {
    if ls "$CONDA_PREFIX/lib/$1"* 1> /dev/null 2>&1; then
        echo "✅ Found Library: $1"
    else
        echo "❌ MISSING Library: $1"
        MISSING_COUNT=$((MISSING_COUNT+1))
    fi
}

# 2. Cek Shared Libraries (Hasil Build Manual & Pixi)
echo ""
echo "🔍 [2/5] Checking Core Libraries ($CONDA_PREFIX/lib)..."

# Cek library kritis yang kita build manual
check_lib "libstella_vslam"      # Core
check_lib "libsocket_publisher"  # Plugin Wajib
check_lib "libg2o_core"          # Solver (Manual Build)
check_lib "libfbow"              # BoW
check_lib "libsioclient"         # Socket Client

# Pastikan Library Viewer GUI TIDAK ADA (Karena kita build headless)
if ls "$CONDA_PREFIX/lib/libpangolin"* 1> /dev/null 2>&1; then
    echo "⚠️  WARNING: libpangolin found (Not used in SocketIO mode, but okay)."
else
    echo "ℹ️  Info: libpangolin not found (Correct for headless build)."
fi

# 3. Cek Executables
echo ""
echo "🔍 [3/5] Checking Executables..."
check_file "$BUILD_EXAMPLES_DIR/run_video_slam"

# 4. Cek Datasets
echo ""
echo "🔍 [4/5] Checking Datasets..."
check_file "$DATASET_DIR/orb_vocab.fbow"
check_file "$DATASET_DIR/aist_living_lab_1/video.mp4"

# 5. Cek Runtime Tools
echo ""
echo "🔍 [5/5] Checking Runtime Tools..."
# Node.js check dihilangkan karena berjalan di Host (Mac)

if command -v gdown &> /dev/null; then
    echo "✅ gdown found (for Dataset Download)"
else
    echo "❌ gdown NOT found (Run 'pixi install')"
    MISSING_COUNT=$((MISSING_COUNT+1))
fi

# ==========================================
# SUMMARY
# ==========================================
echo ""
echo "=========================================="
if [ "$MISSING_COUNT" -eq 0 ]; then
    echo "✅ VERIFICATION PASSED! All systems ready."
    echo ""
    echo "👉 To Start:"
    echo "   1. Ensure Viewer is running on Host (Mac)."
    echo "   2. Run: ./raspi/run-demo.sh"
else
    echo "❌ VERIFICATION FAILED. $MISSING_COUNT artifacts missing."
    echo ""
    echo "👉 If Executables are missing: Run './raspi/build-stella-rpi.sh' again."
    echo "👉 If Datasets are missing   : Run './raspi/run-demo.sh' (it will auto-download them)."
    echo "👉 If Libraries are missing  : Ensure build script completed successfully."
    exit 1
fi
echo "=========================================="