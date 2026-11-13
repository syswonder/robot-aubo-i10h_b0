#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
# Entry point expected by the robonix-aubo image: load ROS 2 and register the
# mounted Robonix source tree, then run the given command.
set -eo pipefail
source /opt/ros/humble/setup.bash
set -u
export PYTHONPATH="/opt/robonix/pylib/robonix-api:${PYTHONPATH:-}"
rbnx setup /opt/robonix >/dev/null
exec "$@"
