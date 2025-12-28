#!/bin/bash
set -e

# Mendapatkan lokasi direktori tempat script ini berada
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
DATASET_DIR="$PROJECT_ROOT/dataset"

echo "=========================================="
echo "   DOWNLOAD EXAMPLE DATASET STELLA VSLAM"
echo "=========================================="
echo "📂 Dataset Dir : $DATASET_DIR"

if [ ! -d "$DATASET_DIR" ]; then mkdir -p "$DATASET_DIR"; fi

cd "$DATASET_DIR"

# 1. Download ORB Vocabulary
echo ""
echo "------------------------------------------"
echo "⬇️  Downloading ORB Vocabulary..."
echo "------------------------------------------"
if [ ! -f "orb_vocab.fbow" ]; then
    curl -L "https://github.com/stella-cv/FBoW_orb_vocab/raw/main/orb_vocab.fbow" -o orb_vocab.fbow
    echo "✅ orb_vocab.fbow downloaded."
else
    echo "ℹ️  orb_vocab.fbow already exists."
fi

# 2. Download AIST Living Lab Dataset
echo ""
echo "------------------------------------------"
echo "⬇️  Downloading AIST Living Lab Dataset..."
echo "------------------------------------------"
if [ ! -d "aist_living_lab_1" ]; then
    if [ ! -f "aist_living_lab_1.zip" ]; then
        echo "   Downloading zip file (from Google Drive)..."
        # Use gdown for reliable Google Drive download
        FILEID="1d8kADKWBptEqTF7jEVhKatBEdN7g0ikY"
        FILENAME="aist_living_lab_1.zip"
        
        if command -v gdown &> /dev/null; then
            gdown "${FILEID}" -O "${FILENAME}"
        else
            echo "❌ Error: gdown not found. Please ensure it is installed in your pixi environment."
            exit 1
        fi
        echo "✅ aist_living_lab_1.zip downloaded."
    else
        echo "ℹ️  aist_living_lab_1.zip already exists."
    fi
    
    echo "   Extracting..."
    unzip -q aist_living_lab_1.zip
    echo "✅ Extracted to $DATASET_DIR/aist_living_lab_1"
else
    echo "ℹ️  aist_living_lab_1 directory already exists."
fi

# 3. Download UZH-FPV Dataset (indoor_forward_3_snapdragon_with_gt)
echo ""
echo "------------------------------------------"
echo "⬇️  Downloading UZH-FPV Dataset..."
echo "------------------------------------------"
UZH_DIR="indoor_forward_3_snapdragon_with_gt"
UZH_ZIP="${UZH_DIR}.zip"
UZH_URL="http://rpg.ifi.uzh.ch/datasets/uzh-fpv-newer-versions/v3/${UZH_ZIP}"

if [ ! -d "$UZH_DIR" ]; then
    if [ ! -f "$UZH_ZIP" ]; then
        echo "   Downloading zip file..."
        curl -L "$UZH_URL" -o "$UZH_ZIP"
        echo "✅ $UZH_ZIP downloaded."
    else
        echo "ℹ️  $UZH_ZIP already exists."
    fi

    echo "   Extracting..."
    unzip -q "$UZH_ZIP"
    echo "✅ Extracted to $DATASET_DIR/$UZH_DIR"
else
    echo "ℹ️  $UZH_DIR directory already exists."
fi

# 4. Download UZH-FPV Calibration Data
echo ""
echo "------------------------------------------"
echo "⬇️  Downloading UZH-FPV Calibration Data..."
echo "------------------------------------------"
CALIB_DIR="indoor_forward_calib_snapdragon"
CALIB_ZIP="${CALIB_DIR}.zip"
CALIB_URL="http://rpg.ifi.uzh.ch/datasets/uzh-fpv/calib/${CALIB_ZIP}"

if [ ! -d "$CALIB_DIR" ]; then
    if [ ! -f "$CALIB_ZIP" ]; then
        echo "   Downloading zip file..."
        curl -L "$CALIB_URL" -o "$CALIB_ZIP"
        echo "✅ $CALIB_ZIP downloaded."
    else
        echo "ℹ️  $CALIB_ZIP already exists."
    fi

    echo "   Extracting..."
    unzip -q "$CALIB_ZIP"
    echo "✅ Extracted to $DATASET_DIR/$CALIB_DIR"
else
    echo "ℹ️  $CALIB_DIR directory already exists."
fi

echo ""
echo "=========================================="
echo "✅ DOWNLOAD COMPLETE"
echo "=========================================="
