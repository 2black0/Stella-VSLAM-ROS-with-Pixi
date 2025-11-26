#!/bin/bash
set -e

# ==========================================
# KONFIGURASI PATH
# ==========================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
LIB_DIR="$PROJECT_ROOT/lib_rpi"
DATASET_DIR="$PROJECT_ROOT/dataset"
BUILD_DIR="$LIB_DIR/stella_vslam_examples/build"

# Config file asli
ORIGINAL_CONFIG="$LIB_DIR/stella_vslam/example/aist/equirectangular.yaml"
# Config file sementara (akan dimodifikasi otomatis)
TEMP_CONFIG="$LIB_DIR/tmp_config_socket.yaml"

echo "=========================================="
echo "   STELLA VSLAM: RPI (PUBLISHER) -> MAC (VIEWER)"
echo "   Mode: Socket Publisher Client"
echo "=========================================="

# Cek Pixi
if [ -z "$CONDA_PREFIX" ]; then
    echo "❌ ERROR: Harap jalankan 'pixi shell' terlebih dahulu!"
    exit 1
fi

# ==========================================
# 0. AUTO-DISCOVERY VIEWER IP
# ==========================================
echo ""
echo "📡 MENCARI VIEWER DI JARINGAN..."
echo "------------------------------------------"

# 1. Dapatkan Subnet lokal (misal: 192.168.11)
MY_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo "$MY_IP" | cut -d'.' -f1-3)

echo "ℹ️  IP Raspberry Pi : $MY_IP"
echo "ℹ️  Scanning subnet : $SUBNET.x untuk Port 3000..."

FOUND_IP=""

# 2. Parallel Scan (Pure Bash - Cepat)
for i in {1..254}; do
    TARGET="$SUBNET.$i"
    # Lewati IP sendiri
    if [ "$TARGET" == "$MY_IP" ]; then continue; fi

    (
        timeout 0.2 bash -c "</dev/tcp/$TARGET/3000" &>/dev/null && echo "$TARGET"
    ) &
done > .found_ips_list

wait

if [ -s .found_ips_list ]; then
    FOUND_IP=$(head -n 1 .found_ips_list)
    rm .found_ips_list
fi

# 3. Logika Penentuan IP
if [ ! -z "$FOUND_IP" ]; then
    echo "✅ DITEMUKAN VIEWER: $FOUND_IP"
    VIEWER_IP="$FOUND_IP"
else
    echo "⚠️  Tidak ditemukan Viewer otomatis di jaringan $SUBNET.x"
    echo "   Pastikan Mac sudah menjalankan 'node app.js' dan firewall tidak memblokir port 3000."
    echo ""
    read -p "👉 Masukkan IP Address Mac (Viewer) secara manual: " VIEWER_IP
fi

if [ -z "$VIEWER_IP" ]; then
    echo "❌ IP tidak boleh kosong."
    exit 1
fi

echo "✅ Target Viewer Set: http://$VIEWER_IP:3000"

# Membuat Config Sementara
cp "$ORIGINAL_CONFIG" "$TEMP_CONFIG"

echo "" >> "$TEMP_CONFIG"
echo "# --- AUTO GENERATED SOCKET CONFIG ---" >> "$TEMP_CONFIG"
echo "SocketPublisher:" >> "$TEMP_CONFIG"
echo "  server_uri: \"http://$VIEWER_IP:3000\"" >> "$TEMP_CONFIG"


# ==========================================
# 1. DOWNLOAD DATASETS (Cek saja)
# ==========================================
if [ ! -d "$DATASET_DIR" ]; then mkdir -p "$DATASET_DIR"; fi
cd "$DATASET_DIR"

if [ ! -f "orb_vocab.fbow" ]; then
    echo "⬇️  Downloading orb_vocab.fbow..."
    curl -L "https://github.com/stella-cv/FBoW_orb_vocab/raw/main/orb_vocab.fbow" -o orb_vocab.fbow
fi

if [ ! -d "aist_living_lab_1" ]; then
    if [ ! -f "aist_living_lab_1.zip" ]; then
        echo "⬇️  Downloading dataset..."

        # Cek apakah gdown terinstall (sekarang lewat pixi.toml)
        if ! command -v gdown &> /dev/null; then
            echo "❌ Error: 'gdown' tidak ditemukan."
            echo "👉 Harap jalankan 'pixi install' ulang karena gdown baru ditambahkan ke pixi.toml."
            exit 1
        fi

        gdown "1d8kADKWBptEqTF7jEVhKatBEdN7g0ikY" -O "aist_living_lab_1.zip"
    fi
    echo "📦 Extracting..."
    unzip -q -o aist_living_lab_1.zip
fi

# ==========================================
# 2. RUN SLAM
# ==========================================

echo ""
echo "------------------------------------------"
echo "🚀 STARTING STELLA VSLAM (PUBLISHER)"
echo "------------------------------------------"

# Cek Executable
if [ ! -f "$BUILD_DIR/run_video_slam" ]; then
    echo "❌ ERROR: Executable tidak ditemukan. Jalankan build dulu."
    exit 1
fi

cd "$BUILD_DIR"

# Menjalankan SLAM dengan Config SEMENTARA
./run_video_slam \
    -v "$DATASET_DIR/orb_vocab.fbow" \
    -m "$DATASET_DIR/aist_living_lab_1/video.mp4" \
    -c "$TEMP_CONFIG" \
    --viewer socket_publisher \
    --no-sleep