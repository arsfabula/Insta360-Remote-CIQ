"""Verify the UCD2 trailer constants compiled into BLEBarrel.mc.

This parses the constants straight out of the barrel source - not a generated
copy in a temp directory - so it verifies what actually ships. The previous
version read %TEMP%/opencode/x6/trailer.txt, an artifact of an earlier run
that could drift from the barrel and still report ALL MATCH.

Two things are checked:

  1. the affinity identity trailer(seq, op) = BASE[op] XOR seqXor(bits of seq)
     reproduces checksum() for all 256 sequences and both ops, and
  2. ucd2StampSeq in the barrel indexes the constants the same way this model
     does (a guarded lookup on f[12] and a per-bit walk of seq), so the model
     is not validating an algorithm the barrel no longer implements.

Exits non-zero on any mismatch.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import insta360_ucd2 as u

BARREL = os.path.join(os.path.dirname(HERE), "BLE Barrel", "BLEBarrel.mc")


def parse_array(src, name):
    """Bytes of a `const <name> = [ ... ]b;` declaration."""
    m = re.search(r"const\s+%s\s*=\s*\[(.*?)\]b\s*;" % re.escape(name),
                  src, re.S)
    if not m:
        raise SystemExit("FATAL: %s not found in %s" % (name, BARREL))
    return bytes(int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{2})", m.group(1)))


def main():
    src = open(BARREL, encoding="utf-8").read()

    start = parse_array(src, "ucd2TrailStartBase")
    stop = parse_array(src, "ucd2TrailStopBase")
    seq_xor = parse_array(src, "ucd2SeqXor")
    assert len(start) == 4, len(start)
    assert len(stop) == 4, len(stop)
    assert len(seq_xor) == 8 * 4, len(seq_xor)

    # 2. the barrel must still implement the algorithm this model mirrors.
    stamp = re.search(r"function ucd2StampSeq\b.*?\n\t\}", src, re.S)
    if not stamp:
        raise SystemExit("FATAL: ucd2StampSeq not found in %s" % BARREL)
    body = stamp.group(0)
    for token in ("ucd2TrailStartBase", "ucd2TrailStopBase", "ucd2SeqXor",
                  "ucd2OpStop", "f[12]", "bit < 8", "1 << bit"):
        if token not in body:
            raise SystemExit("FATAL: ucd2StampSeq no longer references %r;\n%s"
                             % (token, body))
    if re.search(r"ucd2TrailStart\b|ucd2TrailStop\b", src):
        raise SystemExit("FATAL: a per-sequence trailer table is back in the barrel")

    # 1. the affinity identity, over every sequence and both ops.
    ok = True
    for seq in range(256):
        for code, base in ((u.CMD_START_CAPTURE, start),
                           (u.CMD_STOP_CAPTURE, stop)):
            v = bytearray(base)
            for j in range(8):
                if seq & (1 << j):
                    for i in range(4):
                        v[i] ^= seq_xor[j * 4 + i]
            ok &= bytes(v) == bytes(u.build_file_command(seq, code, 1)[-4:])
            if not ok:
                raise SystemExit("MISMATCH at seq=%d code=%d" % (seq, code))

    print("start seq0 :", start.hex(), "ok:", start.hex() == "5b4d4b5a")
    print("stop  seq0 :", stop.hex(), "ok:", stop.hex() == "45fa0bf1")
    print("seqXor     : %d bytes (was 2048 for the old lookup tables)" % len(seq_xor))
    print("ALL MATCH" if ok else "MISMATCH")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())