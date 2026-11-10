#!/usr/bin/env python3
"""Keep ONE BLE session to an Insta360 X5 open and accept commands over a unix socket.

Reconnecting from the Mac looks like a new device to the camera every time (macOS rotates its
BLE address), so tools should share one long-lived connection instead of opening their own.

  x5_session.py serve SOCK            connect, sync, keep-alive every 2 s, serve requests;
                                      reconnects automatically when the camera sleeps/wakes
  x5_session.py send SOCK CODE[:BODY] [WAIT]   one request from the shell (hex code/body)

Requests are one JSON line: {"op":"send","code":7,"body":"08 29 12 00","wait":2.0}, {"op":"ping"} or
{"op":"history","since":<unix time>}.
Reply: {"seq":N,"reply":[t,code,seq,total,bodyhex]|null,"notifs":[[t,code,seq,total,bodyhex],...]}
No CHECK_AUTHORIZATION is sent: control commands work without it and it triggers the camera's
"allow" prompt.
"""
import asyncio
import json
import os
import struct
import sys
import time

BE81 = "0000be81-0000-1000-8000-00805f9b34fb"
BE82 = "0000be82-0000-1000-8000-00805f9b34fb"
KEEPALIVE = bytes.fromhex("07 00 00 00 05 00 00")


def frame(payload):
    return struct.pack("<I", 4 + len(payload)) + payload


def message(code, seq, body=b""):
    return frame(bytes([0x04, 0, 0]) + struct.pack("<H", code) + b"\x02" + seq.to_bytes(3, "little") + b"\x80\x00\x00" + body)


async def serve(sock_path):
    """Serve the socket forever; (re)connect to the camera whenever it is reachable."""
    from bleak import BleakClient, BleakScanner
    frames, buf = [], bytearray()
    lock = asyncio.Lock()
    state = {"seq": 0, "client": None}

    def on_notify(_h, data):
        buf.extend(data)
        while len(buf) >= 4:
            n = struct.unpack("<I", buf[:4])[0]
            if n < 7 or n > 1 << 20:
                buf.clear(); return
            if len(buf) < n:
                return
            f = bytes(buf[:n]); del buf[:n]
            if f[4] == 0x04 and n >= 16:
                frames.append([time.time(), f[7] | f[8] << 8, f[10] | f[11] << 8 | f[12] << 16, n, f[16:].hex()])
                del frames[:-2000]

    async def write(data):
        async with lock:
            c = state["client"]
            if c is None:
                raise ConnectionError("camera not connected")
            for i in range(0, len(data), 20):
                await c.write_gatt_char(BE81, data[i:i + 20], response=True)

    async def handle(reader, writer):
        try:
            req = json.loads((await reader.readline()).decode())
            if req.get("op") == "ping":
                out = {"connected": state["client"] is not None}
            elif req.get("op") == "history":
                # every notification since `since` (unix time), e.g. 0x2065 pushes from changes
                # made on the camera's own screen
                out = {"notifs": [f for f in frames if f[0] >= float(req.get("since", 0)) and f[1] >= 0x2000]}
            else:
                t_wait = time.time()
                while state["client"] is None and time.time() - t_wait < 30:
                    await asyncio.sleep(0.5)
                t0 = time.time()
                state["seq"] += 1
                seq = state["seq"]
                try:
                    await write(message(int(req["code"]), seq, bytes.fromhex(req.get("body", ""))))
                except Exception as e:  # noqa: BLE001
                    out = {"seq": seq, "reply": None, "notifs": [], "error": str(e)}
                else:
                    reply = None
                    while time.time() - t0 < float(req.get("wait", 1.5)):
                        reply = next((f for f in frames if f[2] == seq and f[1] < 0x1000 and f[0] >= t0), None)
                        if reply:
                            break
                        await asyncio.sleep(0.05)
                    await asyncio.sleep(float(req.get("settle", 0.2)))
                    out = {"seq": seq, "reply": reply, "notifs": [f for f in frames if f[0] >= t0 and f[1] >= 0x2000]}
            writer.write((json.dumps(out) + "\n").encode())
            await writer.drain()
        finally:
            writer.close()

    async def keepalive():
        while True:
            await asyncio.sleep(2.0)
            if state["client"] is not None:
                try:
                    await write(KEEPALIVE)
                except Exception:  # noqa: BLE001
                    pass

    if os.path.exists(sock_path):
        os.unlink(sock_path)
    await asyncio.start_unix_server(handle, path=sock_path, limit=1 << 22)
    asyncio.create_task(keepalive())
    print(f"serving {sock_path}", flush=True)
    while True:
        dev = await BleakScanner.find_device_by_filter(lambda d, ad: (d.name or "").startswith("X5 "), timeout=15)
        if not dev:
            continue
        gone = asyncio.Event()
        try:
            async with BleakClient(dev, disconnected_callback=lambda _c: gone.set()) as c:
                await c.start_notify(BE82, on_notify)
                await c.write_gatt_char(BE81, frame(b"\x06\x00\x00" + b"syNceNdinS"), response=True)
                state["client"] = c
                print(f"{time.strftime('%H:%M:%S')} connected to {dev.name[:3]}… MTU {c.mtu_size}", flush=True)
                await gone.wait()
        except Exception as e:  # noqa: BLE001
            print(f"{time.strftime('%H:%M:%S')} connect failed: {e}", flush=True)
        state["client"] = None
        print(f"{time.strftime('%H:%M:%S')} camera disconnected; will reconnect", flush=True)
        await asyncio.sleep(2.0)


async def request(sock_path, req):
    r, w = await asyncio.open_unix_connection(sock_path, limit=1 << 22)
    w.write((json.dumps(req) + "\n").encode())
    await w.drain()
    line = await r.readline()
    w.close()
    return json.loads(line)


class RemoteLink:
    """Drop-in for x5_probe.Link that goes through a running session."""

    def __init__(self, sock_path):
        self.sock = sock_path
        self.frames = []

    async def send(self, code, body=b"", wait=1.2):
        out = await request(self.sock, {"op": "send", "code": code, "body": body.hex(), "wait": wait})
        for f in out["notifs"]:
            self.frames.append((f[0], f[1], f[2], f[3], bytes.fromhex(f[4])))
        rp = out["reply"]
        if rp:
            rp = (rp[0], rp[1], rp[2], rp[3], bytes.fromhex(rp[4]))
            self.frames.append(rp)
        return out["seq"], rp


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "serve":
        asyncio.run(serve(sys.argv[2]))
    elif len(sys.argv) >= 4 and sys.argv[1] == "send":
        code, _, body = sys.argv[3].partition(":")
        wait = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5
        print(json.dumps(asyncio.run(request(sys.argv[2], {"op": "send", "code": int(code, 16), "body": body, "wait": wait}))))
    elif len(sys.argv) >= 3 and sys.argv[1] == "history":
        # notifications of the last N seconds (default: all kept), e.g. 0x2065 setting pushes
        since = time.time() - float(sys.argv[3]) if len(sys.argv) > 3 else 0
        print(json.dumps(asyncio.run(request(sys.argv[2], {"op": "history", "since": since}))))
    else:
        print(__doc__)
