# robot-aubo-i10h_b0

Robonix deployment for an AUBO i10H_B0 arm on a fixed table, with a Jodell
RG75-300 gripper on its own RS-485 line and a monochrome Hikrobot camera on
the wrist. It picks a fruit it sees on the table.

| Piece | Repository | Knows about |
|---|---|---|
| Primitive `aubo_arm` | [`primitive-aubo-i_series-arm-rbnx`](https://github.com/syswonder/primitive-aubo-i_series-arm-rbnx) | the AUBO SDK; standard arm contracts |
| Primitive `jodell_gripper` | [`primitive-jodell-rg-gripper-rbnx`](https://github.com/syswonder/primitive-jodell-rg-gripper-rbnx) | the gripper's Modbus registers; standard gripper contracts |
| Primitive `mv_camera` | [`primitive-hikrobot-mv-camera-rbnx`](https://github.com/syswonder/primitive-hikrobot-mv-camera-rbnx) | the camera (through the controller's vision service); standard camera contracts |
| Skill `fruit_pick` | [`skill-fruit_pick-rbnx`](https://github.com/syswonder/skill-fruit_pick-rbnx) | only the standard contracts |
| Deployment | this repository | which devices, which calibration, which limits |

```text
rbnx ask "..." -> Pilot -> Executor -> fruit_pick (MCP, async)
   camera/rgb + intrinsics --> find the fruit against the empty-table background
   arm/pos_command, end_pose --> aubo_arm -> AUBO SDK -> controller
   gripper/open, grip, state --> jodell_gripper -> RS-485
```

## Manifests

| File | Arm | Gripper | Camera | Skill | Use |
|---|---|---|---|---|---|
| `robonix_manifest.yaml` | real, motion | real | real | yes | the demo |
| `robonix_manifest.readonly.yaml` | real, no motion | real, nothing calls it | real | no | connection check |
| `robonix_manifest.sim.yaml` | simulator | `tests/fake_rg.py` | real (read only) | yes | whole chain without moving anything |

Apart from the sim's transports, faster arm speed and `sim` block, the fields
they share must stay the same in all three.

## Calibration

The manifests and the URDF carry the camera calibration. After a
recalibration, or when the table surface moves, run

```bash
python3 scripts/calibration.py intrinsics.json handeye.json board.json
```

on the calibration results (see the script for the expected JSON) and paste
what it prints into the
three manifests (`mv_camera.intrinsics`, `fruit_pick.camera_in_tcp`,
`fruit_pick.table_z_m`) and `model/aubo_i10H_B0.urdf` (`camera_fixed`).

## Host setup

Everything runs in the `robonix-aubo:20260922` image (`docker/Dockerfile`; put
AUBO's `pyaubo_sdk-0.26.0rc6-cp310-*.whl` in `vendor/` first) with the Robonix
tree mounted from `ROBONIX_SOURCE`, a checkout with `target/release` built.
Copy `.env.example` to `.env` and set at least `AUBO_HOST` (the controller's
address) and `ROBONIX_SOURCE`. `build.sh`/`start.sh` clone the package
repositories on the host into `rbnx-boot/cache/<repo>` before starting the
container. The gripper's USB-RS485 adapter is
passed in from `GRIPPER_DEVICE`; the readonly and motion modes refuse to start
without it.

## Offline (nothing moves)

```bash
./start.sh sim
scripts/container.sh exec python3 scripts/fruit_pick_client.py background
scripts/container.sh exec python3 scripts/fruit_pick_client.py run
scripts/container.sh exec rbnx ask "把桌上的果实抓起来再放回去"   # i18n-ok: scripted task
./stop.sh
```

The camera is the real one, so with the real arm at its photo pose this
detects whatever is on the real table, while the simulated arm and the fake
gripper carry out the run.

## First run on the arm

Someone stays at the emergency stop throughout. Nothing here powers the arm,
releases brakes, starts the runtime, or changes TCP, payload or safety
settings; do that on the pendant.

1. **Prepare.** Pendant: payload set before power-on (at least 1 kg), collision
   level 6, TCP all zero, arm at the photo pose. Gripper powered; nothing else
   holding the gripper adapter or the camera (no other container or script).
   Camera exposure 5 ms (it returns to 50 ms after a controller restart).
2. **Read-only check.** `./start.sh readonly`; `scripts/container.sh exec rbnx caps -v`
   shows the three primitives ACTIVE. The gripper must already be activated
   (it loses activation on every power cycle; activating sweeps the jaws).
3. **Motion.** `./stop.sh`, `./start.sh motion`, table empty:
   `fruit_pick_client.py background`. Put one fruit (20 to 34 mm) on the table:
   `fruit_pick_client.py run`. It is put back where it was.
4. **Through Pilot.** `rbnx ask` with the same task.
5. **Stop.** `./stop.sh`; the arm primitive stops owned motion and confirms it
   before the container goes.

A failed or canceled run leaves the arm where it stopped. Bring it back to the
photo pose on the pendant before the next run.

## Limits

- `required_runtime: ""`: moveLine over RPC runs with the controller runtime
  Stopped.
- Joint 6 stalls near -1.84 rad on the wrist cabling; `joint_limits` stops at
  -1.80.
- `min_payload_kg` and `min_collision_level` refuse motion while the pendant
  settings are missing: with payload 0 the arm raises false collision stops.
- The workspace box keeps the fingertips at least 10 mm above the table.
- The gripper's closed width is not measured; only the open width (40 mm) is
  used, to reject fruit that does not fit.
- The URDF uses the vendor i10H collision meshes (no visual meshes for the B0)
  and is descriptive only; the controller's kinematics drive every motion.
