#!/usr/bin/env bash
set -euo pipefail

if [ -d .pixi ]; then
  find .pixi -mindepth 1 -maxdepth 1 ! -name config.toml -exec rm -rf {} +
fi

rm -rf \
  pixi.lock \
  lib \
  dataset \
  bin \
  ros2_ws/build \
  ros2_ws/install \
  ros2_ws/log
