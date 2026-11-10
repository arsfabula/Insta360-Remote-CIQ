#!/usr/bin/env python3
"""Functional test of the X5 control commands the watch app uses (run from the Mac).

  x5_test.py OUT.json --session=SOCK [--captures-only]

Sets every sub-mode the watch offers and checks the camera's own confirmation, then runs each
capture type once (writes a few small test files to the SD card) and restores Video mode.
The camera must not be connected to the watch at the same time.
"""
import asyncio
import json
import sys
import time

from x5_probe import pb_decode

VIDEO = [0, 1, 2, 4, 6, 11, 12, 14, 15]
MODES = "--captures-only" not in sys.argv
PHOTO = [0, 2, 3, 7]


def set_sub(video, n):
    opt, tag = (0x29, b"\xc8\x02") if video else (0x28, b"\xc0\x02")
    return bytes([0x08, opt, 0x12, 0x00]) if n == 0 else bytes([0x08, opt, 0x12, 0x03]) + tag + bytes([n])


def last_notif(L, code, since):
    for t, c, _s, _n, body in reversed(L.frames):
        if c == code and t >= since:
            return pb_decode(body) if body else []
    return None


async def read_mode(L):
    _, rp = await L.send(0x08, bytes([0x08, 0x28, 0x08, 0x29]), wait=1.5)
    if not rp:
        return None
    d = dict((k, v) for k, v in (pb_decode(rp[4]) or []) if k == 2)
    vals = dict(d.get(2, [])) if isinstance(d.get(2), list) else {}
    return {"photo": vals.get(40, 0), "video": vals.get(41, 0)}


async def wait_idle(L, log, label, limit=90):
    """Poll GET_CURRENT_CAPTURE_STATUS until CameraCaptureState == 0 (the camera finished saving)."""
    t0 = time.time()
    while time.time() - t0 < limit:
        _, rp = await L.send(0x0F, b"", wait=1.5)
        st = None
        if rp and rp[4]:
            d = pb_decode(rp[4]) or []
            inner = dict(d[0][1]) if d and isinstance(d[0][1], list) else {}
            st = inner.get(1, 0)
        if st == 0:
            log.append({"step": f"idle before {label}", "waited_s": round(time.time() - t0, 1)})
            print(f"    idle after {time.time() - t0:.1f}s", flush=True)
            return True
        await asyncio.sleep(2.0)
    print(f"    still busy after {limit}s", flush=True)
    return False


async def step(L, log, name, code, body, wait=2.5, settle=0.0):
    t0 = time.time()
    seq, rp = await L.send(code, body, wait=wait)
    if settle:
        await asyncio.sleep(settle)
    r = {"step": name, "code": code, "body": body.hex(), "status": rp[1] if rp else None,
         "reply_len": rp[3] if rp else None, "reply": (pb_decode(rp[4]) if rp and rp[4] else [])}
    r["notifications"] = [{"code": f"0x{c:04x}", "body": pb_decode(b) if b else []}
                          for t, c, _s, _n, b in L.frames if t >= t0 and c >= 0x2000]
    log.append(r)
    print(f"{name:44s} -> {r['status']}  {json.dumps(r['reply'])[:110]}", flush=True)
    return r


async def main(out, sock):
    # Uses the long-lived session from x5_session.py: one connection, no repeated "allow" prompts.
    from x5_session import RemoteLink
    log = []
    if True:
        L = RemoteLink(sock)

        # 1. modes
        for video, lst in (((True, VIDEO), (False, PHOTO)) if MODES else ()):
            for n in lst:
                t0 = time.time()
                r = await step(L, log, f"SET {'video' if video else 'photo'} sub-mode {n}", 0x07, set_sub(video, n), settle=1.2)
                r["submode_change"] = last_notif(L, 0x2053, t0)
                r["read_back"] = await read_mode(L)
                print(f"    camera says {r['submode_change']}  read-back {r['read_back']}", flush=True)

        # 2. captures
        await step(L, log, "SET photo sub-mode 0 (single)", 0x07, set_sub(False, 0), settle=1.5)
        await wait_idle(L, log, "TAKE_PICTURE single (20 03 30 03)")
        await step(L, log, "TAKE_PICTURE single (20 03 30 03)", 0x03, bytes.fromhex("20 03 30 03"), wait=15)
        # burst skipped: verified on the watch; the X5 needs minutes to save a 360 burst
        await step(L, log, "SET video sub-mode 0", 0x07, set_sub(True, 0), settle=1.5)
        await wait_idle(L, log, "START_CAPTURE (08 01)")
        await step(L, log, "START_CAPTURE (08 01)", 0x04, bytes.fromhex("0801"), settle=1.5)
        await step(L, log, "GET_CURRENT_CAPTURE_STATUS while recording", 0x0F, b"")
        await step(L, log, "SET_HIGHLIGHT (0x3c) while recording", 0x3C, b"", settle=1.0)
        await step(L, log, "STOP_CAPTURE", 0x05, b"", wait=8, settle=2.0)
        await step(L, log, "SET photo sub-mode 2 (interval)", 0x07, set_sub(False, 2), settle=1.5)
        await wait_idle(L, log, "START_TIMELAPSE interval (08 02)")
        await step(L, log, "START_TIMELAPSE interval (08 02)", 0x16, bytes.fromhex("0802"), wait=5, settle=1.0)
        await step(L, log, "GET_CURRENT_CAPTURE_STATUS interval", 0x0F, b"", settle=5.0)
        await step(L, log, "STOP_TIMELAPSE interval (08 02)", 0x17, bytes.fromhex("0802"), wait=10, settle=2.0)
        await step(L, log, "SET photo sub-mode 7 (starlapse)", 0x07, set_sub(False, 7), settle=1.5)
        await wait_idle(L, log, "START_TIMELAPSE starlapse (08 05)")
        await step(L, log, "START_TIMELAPSE starlapse (08 05)", 0x16, bytes.fromhex("0805"), wait=5, settle=1.0)
        await step(L, log, "GET_CURRENT_CAPTURE_STATUS starlapse", 0x0F, b"", settle=6.0)
        await step(L, log, "STOP_TIMELAPSE starlapse (08 05)", 0x17, bytes.fromhex("0805"), wait=20, settle=3.0)

        # 3. restore
        await step(L, log, "SET video sub-mode 0 (restore)", 0x07, set_sub(True, 0), settle=1.5)
        await asyncio.sleep(1.0)
    json.dump(log, open(out, "w"), indent=1)
    print("saved", out)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
    else:
        sock = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--session=")), None)
        if not sock:
            raise SystemExit("start a session first: x5_session.py serve SOCK, then pass --session=SOCK")
        asyncio.run(main(args[0], sock))
