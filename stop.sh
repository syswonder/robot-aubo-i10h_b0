#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
# Shut the deployment down; the arm primitive must confirm owned motion stopped.
set -euo pipefail
exec bash "$(dirname "$0")/scripts/container.sh" stop
