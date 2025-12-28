#!/usr/bin/env bash
set -euo pipefail

rm -rf \
  .pixi \
  pixi.lock \
  lib \
  dataset \
  bin \
  ros2_ws/build \
  ros2_ws/install \
  ros2_ws/log
