#!/bin/bash

# Ensure script is run inside Pixi environment
if [[ -z "$CONDA_PREFIX" ]]; then
    echo "❌ Error: This script must be run via 'pixi run' or inside 'pixi shell'."
    exit 1
fi

echo "======================================================="
echo "🔗 OPENCV SYSTEM LINKER (Package Mode)"
echo "======================================================="

# 1. Determine target location in Pixi Environment
SITE_PACKAGES="$CONDA_PREFIX/lib/python3.10/site-packages"
PIXI_CV2_DIR="$SITE_PACKAGES/cv2"

# 2. Check for Conflicts (Pip/Conda version)
# Kornia sering menginstall opencv-python-headless, kita harus hapus itu juga
if pip show opencv-python > /dev/null 2>&1 || pip show opencv-contrib-python > /dev/null 2>&1 || pip show opencv-python-headless > /dev/null 2>&1; then
    echo "⚠️  Detected OpenCV installed via Pixi/Pip."
    echo "   Kornia/Torchvision might have pulled standard OpenCV."
    
    # Otomatis uninstall tanpa tanya (biar cepat), atau bisa diubah jadi prompt
    echo "♻️  Uninstalling Pip versions to prevent conflict..."
    pip uninstall -y opencv-python opencv-contrib-python opencv-python-headless
fi

# 3. Search for System OpenCV Package Directory
# Ubuntu biasanya menaruh di dist-packages/cv2
echo "🔍 Searching for System OpenCV Package..."

SYSTEM_CV2_DIR="/usr/local/lib/python3.10/dist-packages/cv2"

if [[ ! -d "$SYSTEM_CV2_DIR" ]]; then
    # Fallback search jika tidak ketemu di lokasi standar
    SYSTEM_CV2_DIR=$(find /usr/local/lib -type d -name "cv2" 2>/dev/null | head -n 1)
fi

if [[ -z "$SYSTEM_CV2_DIR" || ! -d "$SYSTEM_CV2_DIR" ]]; then
    echo "❌ FAILED: Cannot find 'cv2' folder in /usr/local/lib."
    echo "   Please check your 'sudo make install' output."
    exit 1
fi

echo "✅ Found System Package: $SYSTEM_CV2_DIR"

# 4. Create Symlink (Folder to Folder)
# Hapus folder/file cv2 di pixi jika ada (bekas install pip)
rm -rf "$PIXI_CV2_DIR" 

echo "🔗 Linking Directory..."
ln -s "$SYSTEM_CV2_DIR" "$PIXI_CV2_DIR"

# 5. Quick Verification
echo "🧪 Verifying Import & CUDA..."
# Kita cek path-nya juga untuk memastikan dia meload dari link yang benar
python -c "import cv2; import os; print(f'OpenCV Ver : {cv2.__version__}'); print(f'Loaded from: {os.path.dirname(cv2.__file__)}'); print(f'CUDA Device: {cv2.cuda.getCudaEnabledDeviceCount()}')"

if [ $? -eq 0 ]; then
    echo "✅ SUCCESS! Pixi is using System OpenCV (CUDA Enabled)."
else
    echo "❌ Verification Failed."
    exit 1
fi