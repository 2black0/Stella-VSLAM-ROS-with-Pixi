#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."
ROS_SETUP="$PROJECT_ROOT/ros2_ws/install/setup.bash"

if [ -f "$ROS_SETUP" ]; then
    # shellcheck source=/dev/null
    . "$ROS_SETUP"
fi
