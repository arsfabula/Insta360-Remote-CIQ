#!/usr/bin/env python3
"""Inspect an Insta360 X5 over BLE from the Mac (larger MTU than Connect IQ's 20 bytes).

  x5_gatt.py dump                 list every service / characteristic / descriptor
  x5_gatt.py query HEX [HEX ...]  sync, then send X5 MESSAGE bodies and print full replies
                                  e.g. query 0008:080b0814   (code:body, both hex)

The camera must not be connected to the watch at the same time (close the watch app).
"""
import asyncio
import struct
import sys

from bleak import BleakClient, BleakScanner

BE81 = "0000be81-0000-1000-8000-00805f9b34fb"
BE82 = "0000be82-0000-1000-8000-00805f9b34fb"


def frame(payload: bytes) -> bytes:
    return struct.pack("<I", 4 + len(payload)) + payload


def message(code: int, seq: int, body: bytes = b"") -> bytes:
    return frame(bytes([0x04, 0, 0]) + struct.pack("<H", code) + b"\x02" + seq.to_bytes(3, "little") + b"\x80\x00\x00" + body)


async def find():
    print("scanning for X5 ...")
    dev = await BleakScanner.find_device_by_filter(lambda d, ad: (d.name or "").startswith("X5 "), timeout=20)
    if not dev:
        raise SystemExit("no X5 found (wake the camera, close the watch app)")
    print("found", dev.name, dev.address)
    return dev


async def dump():
    dev = await find()
    async with BleakClient(dev) as c:
        print("MTU", c.mtu_size)
        for s in c.services:
            print(f"service {s.uuid}  {s.description}")
            for ch in s.characteristics:
                print(f"  char {ch.uuid}  props={','.join(ch.properties)}  {ch.description}")
                if "read" in ch.properties:
                    try:
                        v = await c.read_gatt_char(ch)
                        print(f"     value {v.hex(' ')}  {v!r}")
                    except Exception as e:  # noqa: BLE001
                        print("     read failed:", e)
                for d in ch.descriptors:
                    print(f"     desc {d.uuid}  {d.description}")


async def query(items):
    dev = await find()
    buf = bytearray()

    def on_notify(_h, data: bytearray):
        buf.extend(data)
        while len(buf) >= 4:
            n = struct.unpack("<I", buf[:4])[0]
            if n < 4 or n > 65536:
                print("  <- junk", bytes(buf).hex(" "))
                buf.clear()
                return
            if len(buf) < n:
                return
            f = bytes(buf[:n])
            del buf[:n]
            if f[4] == 0x04 and len(f) >= 16:
                code = f[7] | (f[8] << 8)
                seq = f[10] | (f[11] << 8) | (f[12] << 16)
                print(f"  <- code=0x{code:04x} seq={seq} len={n} body={f[16:].hex(' ')}")
            elif f[4] != 0x05:
                print(f"  <- type=0x{f[4]:02x} {f.hex(' ')}")

    async with BleakClient(dev) as c:
        print("MTU", c.mtu_size)
        await c.start_notify(BE82, on_notify)
        await c.write_gatt_char(BE81, frame(b"\x06\x00\x00" + b"syNceNdinS"), response=True)
        await asyncio.sleep(1.0)
        for seq, it in enumerate(items, start=1):
            code_s, _, body_s = it.partition(":")
            m = message(int(code_s, 16), seq, bytes.fromhex(body_s))
            print(f"-> code=0x{int(code_s, 16):04x} seq={seq} body={body_s}")
            for i in range(0, len(m), 20):  # same 20-byte write chunks the watch uses
                await c.write_gatt_char(BE81, m[i:i + 20], response=True)
            await asyncio.sleep(1.5)
            try:
                v = await c.read_gatt_char("0000be83-0000-1000-8000-00805f9b34fb")
                print(f"   BE83 = {v.hex(' ')}")
            except Exception as e:  # noqa: BLE001
                print("   BE83 read failed:", e)
        await asyncio.sleep(4.0)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "dump":
        asyncio.run(dump())
    elif len(sys.argv) >= 3 and sys.argv[1] == "query":
        asyncio.run(query(sys.argv[2:]))
    else:
        print(__doc__)
