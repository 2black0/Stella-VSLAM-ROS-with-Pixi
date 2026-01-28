#!/bin/bash
# scripts/clean_env.sh

LIB_DIR="$CONDA_PREFIX/lib"
echo "🧹 Cleaning Conflicting GUI Libraries in: $LIB_DIR"
cd "$LIB_DIR" || exit

# Hapus library sistem versi Conda yang sering bentrok dengan OpenCV System
rm -f libglib-2.0.so* libgio-2.0.so* libgobject-2.0.so* libgmodule-2.0.so*
rm -f libgstreamer* libgst*
rm -f libgtk* libgdk* libpango* libcairo* libharfbuzz* libatk* libxcb* libX11*

echo "✅ Environment Cleaned."