"""Table of every camera PUSH (code >= 8000) in the PC corpora: full body, what a
CIQ watch receives under the 20-octet cap, and the protobuf tree of the visible part.
"""
import re
import sys
import glob
import os
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_corp import decode  # noqa: E402

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-fA-F]*)\s*$")
CAP = 20


def main():
    d = sys.argv[1]
    files = [f for f in sorted(glob.glob(os.path.join(d, "ble-*.log"))) if not f.endswith("-frames.log")]
    agg = defaultdict(lambda: {"n": 0, "decl": set(), "bodies": defaultdict(int)})
    for f in files:
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, length, hexs = m.groups()
            if dirn != "RX":
                continue
            fr = bytes.fromhex(hexs)
            if len(fr) < 16:
                continue
            code = int.from_bytes(fr[7:9], "little")
            if code < 8000:
                continue
            body = fr[16:]
            declared = int.from_bytes(fr[0:4], "little")
            a = agg[code]
            a["n"] += 1
            a["decl"].add(declared - 16)
            a["bodies"][body.hex()] += 1
    for code in sorted(agg):
        a = agg[code]
        print("\n== push 0x%04x (%d)  n=%d  declared-body sizes=%s" %
              (code, code, a["n"], sorted(a["decl"])))
        for bh, n in sorted(a["bodies"].items(), key=lambda x: -x[1])[:8]:
            body = bytes.fromhex(bh)
            vis = body[:CAP - 16]
            print("   n=%-3d full=%s" % (n, bh or "(empty)"))
            print("        visible20=%s  %s" % (vis.hex(), "WHOLE" if 16 + len(body) <= CAP else "cut@%d" % (CAP - 16)))
            if body:
                for s in decode(vis, 0, 3):
                    print("          %s" % s)


if __name__ == "__main__":
    main()
