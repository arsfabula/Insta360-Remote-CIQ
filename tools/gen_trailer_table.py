"""Generate the per-sequence UCD2 trailer table for BLEBarrel.mc.

The on-watch CRC loop tripped the VM watchdog ("Code Executed Too Long"), so
the trailer must be a lookup, not a computation. Every frame this widget ever
emits is one of two 25 byte FILE commands - START (code 4) or STOP (code 5) -
that differ only in byte 12. Their trailers therefore depend only on the
sequence, and 256 entries cover any sequence the transmitter is allowed to
use. The bytes written here come from insta360_ucd2.checksum, the exact
reference the golden frames in test_golden.py are pinned to.

Memory: BLEBarrel holds ONE table, as a hex string carried in the code
section (const, not a heap object built at module init). The STOP trailer is
derived at stamp time as START XOR ucd2TrailStopXor: the trailing checksum is
linear in the frame bytes and the two frames differ only in byte 12, so the
delta is one constant. Deriving it keeps the barrel ~1KB leaner, which matters
on the low-memory watch that hit "Out Of Memory Error" at module load.

Writes to stdout a Monkey C declaration:
    const ucd2TrailStartHex = "<256*4 bytes as 2048 hex chars>";
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import insta360_ucd2 as u


def start_hex():
    chars = []
    for seq in range(256):
        frame = u.build_file_command(seq, u.CMD_START_CAPTURE, 1)
        if len(frame) != 25:
            raise SystemExit(f"build_file_command({seq},START) != 25 bytes")
        chars.append(frame[-4:].hex())
    return "".join(chars)


def stop_xor():
    """stop = start XOR this constant, for every seq (must be exactly one set)."""
    deltas = set()
    for seq in range(256):
        st = bytes(u.build_file_command(seq, u.CMD_START_CAPTURE, 1)[-4:])
        sp = bytes(u.build_file_command(seq, u.CMD_STOP_CAPTURE, 1)[-4:])
        deltas.add(bytes(a ^ b for a, b in zip(st, sp)))
    if len(deltas) != 1:
        raise SystemExit(f"expected one XOR delta, got {len(deltas)}")
    return tuple(deltas.pop())


if __name__ == "__main__":
    text = f'const ucd2TrailStartHex = "{start_hex()}";\n'
    x = stop_xor()
    text += "const ucd2TrailStopXor = [0x%02x, 0x%02x, 0x%02x, 0x%02x]b;\n" % x
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    else:
        sys.stdout.write(text)