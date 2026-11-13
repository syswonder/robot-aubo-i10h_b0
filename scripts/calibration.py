#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0
"""Print the manifest and URDF values for a calibration of the wrist camera.

Usage: scripts/calibration.py <intrinsics.json> <handeye.json> <board.json>
The inputs are JSON files from a camera calibration (K and dist), an
eye-in-hand calibration (T_cam2flange, a 4x4 camera-to-flange transform) and
a board pose measurement (board2base, a 4x4 transform whose z is the surface
the fruit rests on). Paste the printed values into the
three manifests and model/aubo_i10H_B0.urdf.
"""

import json
import math
import sys

import numpy as np


def rpy(R):
    """Fixed-axis roll/pitch/yaw, the convention of the AUBO pendant and of URDF."""
    return [math.atan2(R[2, 1], R[2, 2]), math.asin(-max(-1.0, min(1.0, R[2, 0]))),
            math.atan2(R[1, 0], R[0, 0])]


def main(intrinsics_json, handeye_json, board_json):
    intr = json.load(open(intrinsics_json))
    K, d = np.array(intr["K"]), [float(v) for v in intr["dist"]]
    T = np.array(json.load(open(handeye_json))["T_cam2flange"])
    table_z = json.load(open(board_json))["board2base"][2][3]
    xyz, angles = [round(float(v), 5) for v in T[:3, 3]], [round(v, 5) for v in rpy(T[:3, :3])]
    print("mv_camera config, intrinsics:")
    print(f"  {{width: 2448, height: 2048, fx: {K[0, 0]:.3f}, fy: {K[1, 1]:.3f}, "
          f"cx: {K[0, 2]:.3f}, cy: {K[1, 2]:.3f}, d: {[round(v, 6) for v in d]}}}")
    print(f"fruit_pick config, camera_in_tcp: {xyz + angles}")
    print(f"fruit_pick config, table_z_m: {table_z:.4f}")
    print(f'URDF camera_fixed: <origin xyz="{" ".join(map(str, xyz))}" rpy="{" ".join(map(str, angles))}" />')


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:4])
