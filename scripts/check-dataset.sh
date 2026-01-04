#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
DATASET_DIR="$PROJECT_ROOT/dataset"
UZH_DIR="$DATASET_DIR/indoor_forward_3_snapdragon_with_gt"

MISSING=0

OK_MARK="✅"
FAIL_MARK="❌"

section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

mark_ok() {
    echo "${OK_MARK} $1"
}

mark_fail() {
    echo "${FAIL_MARK} $1"
}

check_dir() {
    local label="$1"
    local path="$2"
    if [ -d "$path" ]; then
        mark_ok "$label: $path"
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

check_file() {
    local label="$1"
    local path="$2"
    if [ -f "$path" ]; then
        mark_ok "$label: $path"
    else
        mark_fail "$label: $path (missing)"
        MISSING=1
    fi
}

section "Dataset Paths"
check_dir "dataset" "$DATASET_DIR"
check_file "orb_vocab.fbow" "$DATASET_DIR/orb_vocab.fbow"
check_dir "aist_living_lab_1" "$DATASET_DIR/aist_living_lab_1"
check_file "aist_living_lab_1/video.mp4" "$DATASET_DIR/aist_living_lab_1/video.mp4"

check_dir "indoor_forward_3_snapdragon_with_gt" "$UZH_DIR"
check_dir "indoor_forward_calib_snapdragon" "$UZH_DIR/indoor_forward_calib_snapdragon"
check_dir "UZH img" "$UZH_DIR/img"
check_file "UZH groundtruth.txt" "$UZH_DIR/groundtruth.txt"
check_file "UZH left_images.txt" "$UZH_DIR/left_images.txt"
check_file "UZH right_images.txt" "$UZH_DIR/right_images.txt"
check_file "UZH imu.txt" "$UZH_DIR/imu.txt"

section "Summary"
if [ "$MISSING" -eq 1 ]; then
    mark_fail "Missing dataset artifacts detected."
    exit 1
fi

mark_ok "All dataset artifacts look good."
