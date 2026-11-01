#!/usr/bin/env python3
"""Dynamic BLE probe for the Insta360 camera (step 3).

Runs WITHOUT the Garmin SDK: drives the Linux BLE adapter via gatttool.
Verifies commands from BLE Barrel/BLEBarrel.mc against a real camera.

Usage:
    # 1. find the camera
    python tools/ble_probe.py --scan

    # 2. send a command (handles are auto-discovered)
    python tools/ble_probe.py --addr B8:2D:28:F3:A5:AC \\
        --cmd "0e 00 00 00 04 00 00 04 00 02 00 01 00 80 00 00 08 01" \\
        --listen 5

The command is the full frame (16-byte envelope + protobuf) as hex.
Handles for the write characteristic (BE81) and the notify CCCD are discovered
automatically from gatttool's characteristic listing.
"""

import argparse
import re
import select
import subprocess
import sys
import time


def scan():
    print("Scanning for BLE devices (12s)... look for Insta360*")
    subprocess.run(["timeout", "12", "hcitool", "lescan"], check=False)


def discover_handles(addr, addr_type):
    """Connect, list characteristics, return (write_handle, cccd_handle) or (None,None)."""
    proc = subprocess.Popen(
        ["gatttool", "-i", "hci0", "-b", addr, "-t", addr_type, "-I"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    def send(cmd, wait=0.6):
        proc.stdin.write(cmd + "\n")
        proc.stdin.flush()
        time.sleep(wait)

    send("connect", 2.5)
    send("characteristics", 1.5)
    # read all available output
    time.sleep(1.0)
    lines = []
    while True:
        r, _, _ = select.select([proc.stdout], [], [], 0.3)
        if not r:
            break
        line = proc.stdout.readline()
        if not line:
            break
        lines.append(line.rstrip())
    send("disconnect", 0.5)
    proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()

    write_handle = None
    notify_handle = None
    cccd_handle = None
    for line in lines:
        # format: handle = 0xXXXX, char properties = 0xXX, char value handle = 0xXXXX, uuid = 0000be81-...
        m = re.search(r"handle = (0x[0-9a-fA-F]+).*uuid = ([0-9a-fA-F-]+)", line)
        if not m:
            continue
        h = int(m.group(1), 16)
        uuid = m.group(2).lower()
        if "be81" in uuid:
            write_handle = h
        if "be82" in uuid:
            notify_handle = h
    # CCCD is usually notify_handle + 1 or + 2; find via descriptors listing is complex.
    # We'll attempt write_handle+1 as a heuristic and let the user override.
    if notify_handle is not None and cccd_handle is None:
        cccd_handle = notify_handle + 1
    return write_handle, cccd_handle, lines


def send_and_listen(addr, addr_type, cmd_hex, listen_sec, write_handle, cccd_handle):
    proc = subprocess.Popen(
        ["gatttool", "-i", "hci0", "-b", addr, "-t", addr_type, "-I"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    def send(cmd, wait=0.4):
        proc.stdin.write(cmd + "\n")
        proc.stdin.flush()
        time.sleep(wait)

    print("Connecting to %s ..." % addr)
    send("connect", 2.5)
    if cccd_handle is not None:
        print("Subscribing to notifications (CCCD handle %s)..." % hex(cccd_handle))
        send("char-write-req 0x%04x 0100" % cccd_handle, 0.5)
    print("Writing to handle %s: %s" % (hex(write_handle), cmd_hex))
    send("char-write-req 0x%04x %s" % (write_handle, cmd_hex), 0.5)
    print("Listening for %d s..." % listen_sec)
    end = time.time() + listen_sec
    while time.time() < end:
        r, _, _ = select.select([proc.stdout], [], [], 0.2)
        if r:
            line = proc.stdout.readline()
            if line:
                print("  " + line.rstrip())
    send("disconnect", 0.5)
    proc.stdin.close()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scan", action="store_true")
    ap.add_argument("--addr")
    ap.add_argument("--addr-type", default="public", choices=["public", "random"])
    ap.add_argument("--discover", action="store_true", help="list characteristics and exit")
    ap.add_argument("--cmd", help="hex bytes to send")
    ap.add_argument("--write-handle", type=lambda x: int(x, 0), default=0x002a,
                    help="ATT handle of write char BE81 (default 0x002a for X5 3S6GEW)")
    ap.add_argument("--cccd-handle", type=lambda x: int(x, 0), default=0x002d,
                    help="ATT handle of BE82 CCCD (default 0x002d for X5 3S6GEW)")
    ap.add_argument("--listen", type=int, default=5)
    args = ap.parse_args()

    if args.scan:
        scan()
        return
    if not args.addr:
        print("error: --addr required (use --scan to find it)", file=sys.stderr)
        sys.exit(2)
    if args.discover:
        wh, ch, lines = discover_handles(args.addr, args.addr_type)
        for ln in lines:
            print(ln)
        print("\nDiscovered: write_handle=%s  cccd_handle=%s" % (
            hex(wh) if wh else None, hex(ch) if ch else None))
        return
    if not args.cmd:
        print("error: --cmd required", file=sys.stderr)
        sys.exit(2)

    if args.write_handle is not None:
        wh = args.write_handle
        ch = args.cccd_handle
    else:
        wh, ch, _ = discover_handles(args.addr, args.addr_type)
        if wh is None:
            print("error: could not discover write handle (BE81)", file=sys.stderr)
            sys.exit(1)
    send_and_listen(args.addr, args.addr_type, " ".join(args.cmd.split()),
                    args.listen, wh, ch)


if __name__ == "__main__":
    main()
