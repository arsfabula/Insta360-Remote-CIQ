#!/usr/bin/env python3
"""Read / write X5 PhotographyOptions (per-mode footage settings) through a running x5_session.py.

  x5_photo.py SOCK dump OUT.json                 read every option for each function mode
  x5_photo.py SOCK get MODE OPT[,OPT...]          e.g. get 7 31,41
  x5_photo.py SOCK set MODE OPT VALUE             varint options only, e.g. set 6 26 3 (self-timer 3 s)

GET_PHOTOGRAPHY_OPTIONS (0x0a)  body {1: repeated option type, 2: function_mode}
SET_PHOTOGRAPHY_OPTIONS (0x09)  body {1: repeated option type, 2: PhotographyOptions{<type>: value}, 3: function_mode}
PhotographyOptions field numbers equal the PhotographyOptionType values.
"""
import asyncio
import json
import sys

from x5_probe import pb_decode, varint
from x5_session import RemoteLink

# FunctionMode values for the X5 modes (community enum)
MODES = {6: "NORMAL_IMAGE (Photo)", 7: "NORMAL_VIDEO (Video)", 3: "INTERVAL_SHOOTING", 5: "BURST",
         18: "STARLAPSE_IMAGE", 2: "MOBILE_TIMELAPSE (Timelapse)", 12: "TIMESHIFT", 27: "PURE_VIDEO",
         17: "LOOP_RECORDING_VIDEO", 63: "DASH_CAM", 64: "PTZ (Gimbal?)", 7 + 100: None}
MODES.pop(107)
ALL_TYPES = list(range(1, 112))


def get_body(types, mode):
    return b"".join(b"\x08" + varint(t) for t in types) + b"\x10" + varint(mode)


def values(reply_body):
    dec = pb_decode(reply_body) or []
    v = next((x[1] for x in dec if x[0] == 2 and isinstance(x[1], list)), [])
    return {k: val for k, val in v}


async def get(L, mode, types, wait=2.5):
    _, rp = await L.send(0x0A, get_body(types, mode), wait=wait)
    if not rp:
        return None, None
    return rp[1], values(rp[4]) if rp[4] else {}


async def main():
    sock, cmd = sys.argv[1], sys.argv[2]
    L = RemoteLink(sock)
    if cmd == "dump":
        # Small requests only: one ~230-byte GET (all 111 types) wedged the camera's BLE command
        # parser until a power cycle. 8 types per request keeps every frame under ~40 bytes.
        out = {}
        for mode, name in MODES.items():
            vals, statuses = {}, set()
            for i in range(0, len(ALL_TYPES), 8):
                st, v = await get(L, mode, ALL_TYPES[i:i + 8], wait=2.0)
                statuses.add(st)
                vals.update(v or {})
            out[mode] = {"name": name, "status": sorted(x for x in statuses if x is not None), "values": vals}
            print(f"mode {mode:3d} {name:30s} status={out[mode]['status']} {len(vals)} values", flush=True)
        json.dump(out, open(sys.argv[3], "w"), indent=1, default=str)
        print("saved", sys.argv[3])
    elif cmd == "get":
        mode, types = int(sys.argv[3]), [int(x) for x in sys.argv[4].split(",")]
        print(json.dumps(await get(L, mode, types), default=str))
    elif cmd == "set":
        mode, opt, val = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
        field = varint(opt << 3) + varint(val)
        body = b"\x08" + varint(opt) + b"\x12" + varint(len(field)) + field + b"\x18" + varint(mode)
        _, rp = await L.send(0x09, body, wait=3.0)
        print("set status", rp[1] if rp else None, json.dumps(pb_decode(rp[4]) if rp and rp[4] else []))
        print("read back", json.dumps(await get(L, mode, [opt]), default=str))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
    else:
        asyncio.run(main())
