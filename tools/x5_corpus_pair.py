"""Pair asks with their answers in the PC corpora and print the FULL answer body.

Usage: python3 pair.py <dir> <code> [<code> ...]
"""
import re
import sys
import glob
import os

LINE = re.compile(
    r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(APP->CAM|CAM->APP)\s+code=(\d+)\s+(\S+)\s+"
    r"seq=(\d+)\s+declared=(\d+)\s+corps=0x([0-9a-fA-F]*)$"
)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_corp import decode  # noqa: E402


def main():
    d = sys.argv[1]
    want = [int(x) for x in sys.argv[2:]]
    files = sorted(glob.glob(os.path.join(d, "ble-*-frames.log")))
    for f in files:
        base = os.path.basename(f).replace("-frames.log", "")
        rows = []
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if m:
                rows.append(m.groups())
        # seq -> ask info
        asks = {}
        for t, dirn, code, name, seq, decl, hexs in rows:
            if dirn == "APP->CAM" and int(code) in want:
                asks[int(seq)] = (t, int(code), name, hexs, int(decl))
        out = []
        for t, dirn, code, name, seq, decl, hexs in rows:
            seq = int(seq)
            if dirn == "APP->CAM" and seq in asks:
                at, ac, an, ah, ad = asks[seq]
                out.append("ASK  %s code=%-3d %-24s seq=%-4d declared=%-4d corps=%s" % (at, ac, an, seq, ad, ah or "0x"))
                if ah:
                    out.append("     " + " | ".join(decode(bytes.fromhex(ah))))
            elif dirn == "CAM->APP" and seq in asks and int(code) in (200, 400):
                total = 16 + int(decl)
                out.append("ANSW %s code=%-5s seq=%-4d declared=%-4d total=%-4d watch_sees=%d corps=%s" %
                           (t, code, seq, int(decl), total, min(total, 20), hexs or "0x"))
                if hexs:
                    out.append("     " + " | ".join(decode(bytes.fromhex(hexs))))
                    b = bytes.fromhex(hexs)
                    out.append("     FIRST20FRAME=%s" % (("16-octet envelope + " + b[:4].hex()) if total > 20 else b.hex()))
        if out:
            print("\n########## %s (%d asks) ##########" % (base, len(asks)))
            print("\n".join(out))


if __name__ == "__main__":
    main()
