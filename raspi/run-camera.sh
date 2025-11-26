#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_DIR="$SCRIPT_DIR/lib_rpi"
DATASET_DIR="$SCRIPT_DIR/dataset"
BUILD_DIR="$LIB_DIR/stella_vslam_examples/build"

# Config file
CONFIG_FILE="$LIB_DIR/webcam_config.yaml"
# Auto IP discovery (copy logic dari run-demo.sh)
MY_IP=$(hostname -I | awk '{print $1}')
SUBNET=$(echo "$MY_IP" | cut -d'.' -f1-3)
FOUND_IP=""
for i in {1..254}; do
    TARGET="$SUBNET.$i"
    if [ "$TARGET" == "$MY_IP" ]; then continue; fi
    ( timeout 0.2 bash -c "</dev/tcp/$TARGET/3000" &>/dev/null && echo "$TARGET" ) &
done > .found_ips_list
wait
if [ -s .found_ips_list ]; then FOUND_IP=$(head -n 1 .found_ips_list); rm .found_ips_list; fi

if [ ! -z "$FOUND_IP" ]; then
    VIEWER_IP="$FOUND_IP"
    echo "✅ Auto-detected Viewer: $VIEWER_IP"
else
    read -p "👉 Masukkan IP Mac Viewer: " VIEWER_IP
fi

# Inject IP ke Config Sementara
cp "$CONFIG_FILE" "$LIB_DIR/tmp_webcam.yaml"
sed -i "s|http://.*:3000|http://$VIEWER_IP:3000|g" "$LIB_DIR/tmp_webcam.yaml"

echo "🚀 Starting Webcam SLAM..."
cd "$BUILD_DIR"

# Perintah khusus run_camera_slam
# -n 0 : Kamera index 0 (/dev/video0)
# -s 1.0 : Skala gambar (gunakan 0.5 jika RPi berat)
./run_camera_slam \
    -v "$DATASET_DIR/orb_vocab.fbow" \
    -n 0 \
    -c "$LIB_DIR/tmp_webcam.yaml" \
    --viewer socket_publisher