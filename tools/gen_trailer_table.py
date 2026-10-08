"""Generate the per-sequence UCD2 trailer tables for BLEBarrel.mc.

The on-watch CRC loop tripped the VM watchdog ("Code Executed Too Long"), so
the trailer must be a lookup, not a computation. Every frame this widget ever
emits is one of two 25 byte FILE commands - START (code 4) or STOP (code 5) -
that differ only in byte 12. Their trailers therefore depend only on the
sequence, and 256 entries cover any sequence the transmitter is allowed to
use. The bytes written here come from insta360_ucd2.checksum, the exact
reference the golden frames in test_golden.py are pinned to.

Writes to stdout two Monkey C declarations:
    const ucd2TrailStart = [ ... ]b;   // index = seq, one 4 byte LE trailer
    const ucd2TrailStop  = [ ... ]b;
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import insta360_ucd2 as u


def emit(name, op):
    rows = []
    for seq in range(256):
        frame = u.build_file_command(seq, op, u.ucd2ReqId if hasattr(u, "ucd2ReqId") else 1)
        if len(frame) != 25:
            raise SystemExit(f"{name}: build_file_command({seq},{op}) != 25 bytes")
        trailer = frame[-4:]
        rows.append("0x%02x, 0x%02x, 0x%02x, 0x%02x" % tuple(trailer))
    lines = []
    for i in range(0, len(rows), 4):
        lines.append("\t\t" + ", ".join(rows[i:i + 4]) + ",")
    body = "\n".join(lines).rstrip(",")
    print(f"const {name} = [\n{body}\n\t]b;")


def emit(name, op):
    rows = []
    for seq in range(256):
        frame = u.build_file_command(seq, op, 1)
        if len(frame) != 25:
            raise SystemExit(f"{name}: build_file_command({seq},{op}) != 25 bytes")
        trailer = frame[-4:]
        rows.append("0x%02x, 0x%02x, 0x%02x, 0x%02x" % tuple(trailer))
    lines = []
    for i in range(0, len(rows), 4):
        lines.append("\t\t" + ", ".join(rows[i:i + 4]) + ",")
    body = "\n".join(lines).rstrip(",")
    return f"const {name} = [\n{body}\n\t]b;"


if __name__ == "__main__":
    out = [emit("ucd2TrailStart", u.CMD_START_CAPTURE), "", emit("ucd2TrailStop", u.CMD_STOP_CAPTURE)]
    text = "\n".join(out)
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    else:
        sys.stdout.write(text)