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

echo ""
echo "=========================================="
echo "✅ DOWNLOAD COMPLETE"
echo "=========================================="
