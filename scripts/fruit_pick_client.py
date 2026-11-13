#!/usr/bin/env python3
# SPDX-License-Identifier: MulanPSL-2.0
"""Call the fruit_pick skill directly through Atlas and MCP.

Run inside the deployment container (scripts/container.sh exec python3 ...):

  background               photograph the empty table (clear it first)
  run [DESTINATION]        pick one fruit, release it at DESTINATION or where it
                           was, and poll until the run ends (Ctrl-C cancels)
  status RUN_ID            print state and detail
  cancel RUN_ID            request cancellation

Each action activates the skill first, as the Executor would.
"""

from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "rbnx-boot/cache/skill-fruit_pick-rbnx/rbnx-build/codegen/proto_gen"))

PROVIDER = "fruit_pick"
PICK = "robonix/skill/fruit_pick/pick_fruit"
BACKGROUND = "robonix/skill/fruit_pick/capture_background"
TERMINAL = {"SUCCEEDED", "FAILED", "CANCELED", "TIMEOUT"}


def activate():
    """Send CMD_ACTIVATE to the skill's lifecycle Driver (idempotent)."""
    import grpc
    import lifecycle_pb2
    import robonix_contracts_pb2_grpc as contracts
    from robonix_api import ATLAS

    with ATLAS.connect_capability(consumer_id="fruit_pick_client", provider_id=PROVIDER,
                                  contract_id="robonix/lifecycle/driver", transport="grpc") as ch:
        with grpc.insecure_channel(ch.endpoint) as wire:
            reply = contracts.RobonixLifecycleDriverStub(wire).Driver(
                lifecycle_pb2.Driver_Request(command=1, config_json="{}"), timeout=60)
    if not reply.ok:
        raise RuntimeError(f"activation failed: {reply.error or reply.state}")


async def call(contract, arguments, timeout=15):
    """Call one MCP tool of the skill and return its structured result."""
    from fastmcp import Client
    from robonix_api import ATLAS

    with ATLAS.connect_capability(consumer_id="fruit_pick_client", provider_id=PROVIDER,
                                  contract_id=contract, transport="mcp") as ch:
        async with Client(ch.endpoint, timeout=timeout) as client:
            reply = await client.call_tool(contract.rsplit("/", 1)[-1], arguments)
    if reply.is_error:
        raise RuntimeError(" ".join(getattr(c, "text", str(c)) for c in reply.content))
    result = reply.structured_content
    if isinstance(result, dict) and set(result) == {"result"}:
        result = result["result"]
    return result


def watch(run_id):
    """Poll status until the run ends; Ctrl-C sends cancel and keeps polling."""
    last = None
    while True:
        try:
            status = asyncio.run(call(f"{PICK}/status", {"run_id": run_id}))
            if status != last:
                print(f"{time.strftime('%H:%M:%S')} {status['state']}: {status['detail']}", flush=True)
                last = status
            if status["state"] in TERMINAL:
                sys.exit(0 if status["state"] == "SUCCEEDED" else 1)
            time.sleep(0.5)
        except KeyboardInterrupt:
            print("canceling...", flush=True)
            print(json.dumps(asyncio.run(call(f"{PICK}/cancel", {"run_id": run_id}))))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=("background", "run", "status", "cancel"))
    parser.add_argument("arg", nargs="?", default="")
    ns = parser.parse_args()
    if ns.action in ("status", "cancel") and not ns.arg:
        parser.error(f"{ns.action} takes a run_id")
    try:
        activate()
        if ns.action == "background":
            print(json.dumps(asyncio.run(call(BACKGROUND, {}, timeout=120)), ensure_ascii=False))
        elif ns.action == "run":
            started = asyncio.run(call(PICK, {"destination": ns.arg}))
            print(json.dumps(started, ensure_ascii=False))
            watch(started["run_id"])
        else:
            leaf = "status" if ns.action == "status" else "cancel"
            print(json.dumps(asyncio.run(call(f"{PICK}/{leaf}", {"run_id": ns.arg})), ensure_ascii=False))
    except Exception as exc:
        parser.exit(1, f"error: {exc}\n")


if __name__ == "__main__":
    main()
