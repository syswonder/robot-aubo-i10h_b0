#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
# Boot one deployment variant in a detached container.
# Usage: ./start.sh sim|readonly|motion   (motion also sets AUBO_ENABLE_MOTION=1)
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 sim|readonly|motion" >&2; exit 2; }
exec bash "$(dirname "$0")/scripts/container.sh" "$1"
