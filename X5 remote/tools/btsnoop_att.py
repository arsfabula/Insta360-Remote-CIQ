#!/usr/bin/env python3
"""Decode ATT writes/notifications from an Android btsnoop (H4) log.

Usage: btsnoop_att.py <btsnoop_hci.log> [--all]
Prints one line per ATT Write Request/Command and Handle Value Notification:
time, direction, opcode, ATT handle, captured/original length, hex payload.
Without --all, only packets that look like Insta360 frames (bytes 2..6 = 00 00 04 00 00,
or the 7-byte keep-alive 07 00 00 00 05 00 00) are shown.
"""
import struct
import sys
from datetime import datetime, timedelta

EPOCH = datetime(2000, 1, 1) - timedelta(microseconds=0x00dcddb30f2f8000 - 0x00E03AB44A676000)
OPS = {0x12: "WRITE_REQ", 0x52: "WRITE_CMD", 0x1b: "NOTIFY", 0x1d: "INDICATE", 0x0b: "READ_RSP"}


def records(path):
    with open(path, "rb") as f:
        hdr = f.read(16)
        if hdr[:8] != b"btsnoop\0":
            raise SystemExit("not a btsnoop file")
        while True:
            rh = f.read(24)
            if len(rh) < 24:
                return
            olen, ilen, flags, _drops, ts = struct.unpack(">IIIIq", rh)
            data = f.read(ilen)
            yield olen, ilen, flags, ts, data


def is_insta(v):
    return (len(v) >= 7 and v[2:7] == b"\x00\x00\x04\x00\x00") or v[:7] == b"\x07\x00\x00\x00\x05\x00\x00"


def main():
    path = sys.argv[1]
    show_all = "--all" in sys.argv
    n = 0
    for olen, ilen, flags, ts, d in records(path):
        if not d or d[0] != 0x02 or len(d) < 10:  # H4 ACL only
            continue
        l2_cid = struct.unpack("<H", d[7:9])[0]
        if l2_cid != 0x0004:  # ATT
            continue
        att = d[9:]
        op = att[0]
        if op not in OPS or len(att) < 3:
            continue
        handle = struct.unpack("<H", att[1:3])[0]
        val = att[3:]
        if not show_all and not is_insta(val):
            continue
        sent = "->cam" if (flags & 1) == 0 else "<-cam"
        t = (datetime(1, 1, 1) + timedelta(microseconds=ts)).strftime("%H:%M:%S.%f")[:-3] if ts > 0 else "?"
        trunc = "" if ilen == olen else " TRUNC(%d/%d)" % (ilen, olen)
        print("%s %s %-9s h=0x%04x len=%d%s  %s" % (t, sent, OPS[op], handle, len(val), trunc, val.hex(" ")))
        n += 1
    print("# %d ATT packets shown" % n, file=sys.stderr)


if __name__ == "__main__":
    main()
