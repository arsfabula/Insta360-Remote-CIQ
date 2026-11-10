#!/usr/bin/env python3
"""Read-only survey of an Insta360 X5 over BLE (run from the Mac; MTU ~515).

  x5_probe.py OUT.json      runs every phase and writes raw results
  x5_probe.py --report OUT.json   prints a markdown summary of a saved run

Phases
  cmds     every read-only GET-style command with an empty body
  options  GET_OPTIONS for each OptionType 1..180, one at a time
  control  the commands the watch app uses (mode set / capture status / auth)

Excluded on purpose: anything that deletes, formats, shuts down, updates, calibrates or changes
settings; bulk transfers (file lists, thumbnails, packages, gyro); and options/commands that
return secrets (Wi-Fi credentials, authorization id, licences, Find My tokens, USB password).
The camera must not be connected to the watch at the same time. No CHECK_AUTHORIZATION is sent
(it makes the camera show an "allow" prompt; reads and control work without it).
"""
import asyncio
import json
import struct
import sys
import time

BE81 = "0000be81-0000-1000-8000-00805f9b34fb"
BE82 = "0000be82-0000-1000-8000-00805f9b34fb"

# read-only commands (MessageCode values) from the community insta360_messages.proto
CMDS = {
    8: "GET_OPTIONS", 10: "GET_PHOTOGRAPHY_OPTIONS", 11: "GET_FILE_EXTRA", 15: "GET_CURRENT_CAPTURE_STATUS",
    17: "GET_TIMELAPSE_OPTIONS", 21: "GET_TIMELAPSE_PHOTOGRAPHY_OPTIONS", 29: "GET_CONNECTED_BT_PERIPHERALS",
    37: "GET_IPERF_AVERAGE", 43: "GET_SUBMODE_OPTIONS", 55: "GET_SYNC_CAPTURE_MODE",
    64: "GET_FLOWSTATE_ENABLE", 66: "GET_ACTIVE_SENSOR", 68: "GET_MULTI_PHOTOGRAPHY_OPTIONS",
    71: "GET_RECORDING_FILE", 73: "GET_PTZ_OPTION", 104: "GET_BUTTON_PRESS_PARAM", 119: "GET_TIME_REC_CFG",
    121: "GET_PLAYBACK_FILE_NUM", 126: "GET_MILLISECOND_TIME_STAMP", 131: "GET_ABNORMAL_CAPTURE",
    136: "GET_CAMERA_LIVE_INFO", 150: "GET_WIFI_MODE", 153: "PLAYBACK_GET_PHOTO_GROUP_NUM",
    159: "GET_WEBCAM_FACE_DET_FLAG", 166: "GET_STORAGE", 171: "GET_ZOOM", 177: "GET_CUR_FILTER_PHOTO_ALBUM",
    178: "GET_PHOTO_ALBUM_NUM", 182: "QUICKREADER_GET_STATUS", 191: "GET_INTERVALREC_CFG",
    198: "GET_INTERVAL_RECORD_STATUS", 203: "PLAYBACK_GET_HIGHLIGHT_INFO", 205: "GET_INTERVALREC_SCENE_CFG",
    206: "GET_INTERVALREC_FEEDBACK_CFG", 211: "GET_ALBUM_UNFOLD_MAP_INDEX", 216: "GET_CAMERA_PARAMS_JSON",
    223: "GET_WIFI_INTERFERENCE_STATUS", 224: "GET_P3_STATIC_HDR_PARAMS", 227: "GET_REC_RESULT_CACHE",
    228: "GET_PHOTO_RESULT_CACHE", 239: "GET_PTZ_TRACK_STATE", 242: "GET_FIRMWARE_VERSIONS",
}
# OptionType values never queried (secrets)
SECRET_OPTIONS = {15, 16, 36, 38, 56, 61, 62, 131, 142, 143, 144, 163}

CONTROL = [
    ("GET_CURRENT_CAPTURE_STATUS", 0x0F, ""),
    ("SET_OPTIONS video sub-mode 0", 0x07, "08 29 12 00"),
    ("SET_OPTIONS photo sub-mode 0", 0x07, "08 28 12 00"),
    ("SET_OPTIONS video sub-mode 0 (restore)", 0x07, "08 29 12 00"),
]


def frame(payload: bytes) -> bytes:
    return struct.pack("<I", 4 + len(payload)) + payload


def message(code: int, seq: int, body: bytes = b"") -> bytes:
    return frame(bytes([0x04, 0, 0]) + struct.pack("<H", code) + b"\x02" + seq.to_bytes(3, "little") + b"\x80\x00\x00" + body)


def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def pb_decode(b: bytes, depth=0):
    """Generic protobuf decode -> list of (field, value); nested messages decoded when plausible."""
    out, i = [], 0
    try:
        while i < len(b):
            key, i = _rv(b, i)
            f, wt = key >> 3, key & 7
            if f == 0:
                raise ValueError
            if wt == 0:
                v, i = _rv(b, i)
                out.append((f, v))
            elif wt == 2:
                n, i = _rv(b, i)
                chunk = b[i:i + n]
                i += n
                if len(chunk) != n:
                    raise ValueError
                sub = pb_decode(chunk, depth + 1) if depth < 6 and chunk else None
                if sub is not None and not _printable(chunk):
                    out.append((f, sub))
                else:
                    out.append((f, chunk.decode("utf-8", "replace") if _printable(chunk) else chunk.hex()))
            elif wt == 1:
                out.append((f, b[i:i + 8].hex())); i += 8
            elif wt == 5:
                out.append((f, struct.unpack("<f", b[i:i + 4])[0] if len(b) >= i + 4 else None)); i += 4
            else:
                raise ValueError
        return out
    except Exception:  # noqa: BLE001
        return None if depth else [("raw", b.hex())]


def _rv(b, i):
    v = s = 0
    while True:
        x = b[i]; i += 1
        v |= (x & 0x7F) << s
        if not x & 0x80:
            return v, i
        s += 7


def _printable(chunk):
    return len(chunk) >= 3 and all(32 <= c < 127 for c in chunk)


class Link:
    def __init__(self, client):
        self.c = client
        self.buf = bytearray()
        self.frames = []          # (t, code, seq, total_len, body)
        self.seq = 0

    def on_notify(self, _h, data):
        self.buf.extend(data)
        while len(self.buf) >= 4:
            n = struct.unpack("<I", self.buf[:4])[0]
            if n < 7 or n > 1 << 20:
                self.buf.clear(); return
            if len(self.buf) < n:
                return
            f = bytes(self.buf[:n]); del self.buf[:n]
            if f[4] == 0x04 and n >= 16:
                self.frames.append((time.time(), f[7] | f[8] << 8, f[10] | f[11] << 8 | f[12] << 16, n, f[16:]))

    async def send(self, code, body=b"", wait=1.2):
        self.seq += 1
        seq = self.seq
        m = message(code, seq, body)
        for i in range(0, len(m), 20):
            await self.c.write_gatt_char(BE81, m[i:i + 20], response=True)
        t0 = time.time()
        while time.time() - t0 < wait:
            for fr in self.frames:
                if fr[2] == seq and fr[1] < 0x1000:
                    await asyncio.sleep(0.15)
                    return seq, fr
            await asyncio.sleep(0.05)
        return seq, None


def rec(kind, name, code, body, reply):
    r = {"kind": kind, "name": name, "code": code, "body": body.hex()}
    if reply is None:
        r.update(status=None)
    else:
        _, st, _, total, rb = reply
        r.update(status=st, total_len=total, fits_ciq=total <= 20, reply=rb.hex(), decoded=pb_decode(rb) if rb else [])
    return r


async def run(out_path):
    from bleak import BleakClient, BleakScanner
    dev = await BleakScanner.find_device_by_filter(lambda d, ad: (d.name or "").startswith("X5 "), timeout=20)
    if not dev:
        raise SystemExit("no X5 found (wake the camera, close the watch app)")
    results = {"camera": dev.name, "started": time.strftime("%Y-%m-%d %H:%M:%S"), "items": [], "notifications": []}
    async with BleakClient(dev) as c:
        results["mtu"] = c.mtu_size
        L = Link(c)
        await c.start_notify(BE82, L.on_notify)
        await c.write_gatt_char(BE81, frame(b"\x06\x00\x00" + b"syNceNdinS"), response=True)
        await asyncio.sleep(1.0)
        for code, name in CMDS.items():
            _, rp = await L.send(code)
            results["items"].append(rec("cmd", name, code, b"", rp))
            print(f"cmd {code:3d} {name:36s} -> {results['items'][-1].get('status')}", flush=True)
        for opt in range(1, 181):
            if opt in SECRET_OPTIONS:
                continue
            body = b"\x08" + varint(opt)
            _, rp = await L.send(0x08, body, wait=0.9)
            results["items"].append(rec("option", f"option {opt}", 0x08, body, rp))
            r = results["items"][-1]
            print(f"opt {opt:3d} -> {r.get('status')} len={r.get('total_len')} {r.get('reply', '')[:60]}", flush=True)
        for name, code, hx in CONTROL:
            _, rp = await L.send(code, bytes.fromhex(hx), wait=2.0)
            results["items"].append(rec("control", name, code, bytes.fromhex(hx), rp))
            print(f"ctl {name:40s} -> {results['items'][-1].get('status')}", flush=True)
        await asyncio.sleep(2.0)
        for t, code, seq, total, body in L.frames:
            if code >= 0x2000:
                results["notifications"].append({"code": code, "total_len": total, "fits_ciq": total <= 20,
                                                 "body": body.hex(), "decoded": pb_decode(body) if body else []})
    json.dump(results, open(out_path, "w"), indent=1)
    print("saved", out_path)


if __name__ == "__main__":
    if len(sys.argv) == 2:
        asyncio.run(run(sys.argv[1]))
    else:
        print(__doc__)
