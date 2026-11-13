#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
# Fetch and build the packages of one deployment variant (default: motion,
# i.e. robonix_manifest.yaml). Usage: ./build.sh [sim|readonly|motion]
set -euo pipefail
exec bash "$(dirname "$0")/scripts/container.sh" build "${1:-motion}"
