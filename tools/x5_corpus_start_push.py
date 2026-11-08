"""What the camera pushes at session start: every RX that arrives before the first
TX of a capture (i.e. unsolicited, right after the PC connected and enabled notify).
"""
import re
import sys
import glob
import os
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_corp import decode  # noqa: E402

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-fA-F]*)\s*$")


def main():
    d = sys.argv[1]
    files = [f for f in sorted(glob.glob(os.path.join(d, "ble-*.log"))) if not f.endswith("-frames.log")]
    per = defaultdict(lambda: defaultdict(int))
    detail = {}
    for f in files:
        base = os.path.basename(f).replace(".log", "")
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, length, hexs = m.groups()
            if dirn == "TX":
                break  # session traffic started
            fr = bytes.fromhex(hexs)
            if len(fr) < 16:
                kind = "beat/short"
                per[base][kind] += 1
                continue
            code = int.from_bytes(fr[7:9], "little")
            ctype = fr[4]
            body = fr[16:]
            kind = "code=%d(type%d,len%d)" % (code, ctype, len(fr))
            per[base][kind] += 1
            detail.setdefault(kind, body.hex())
    totals = defaultdict(int)
    for base, c in per.items():
        for k, n in c.items():
            totals[k] += n
    print("=== par capture : RX avant le premier TX ===")
    for base in sorted(per):
        items = ", ".join("%s x%d" % (k, n) for k, n in sorted(per[base].items()))
        print("%-28s %s" % (base, items or "(aucun)"))
    print("\n=== total des captures ===")
    for k, n in sorted(totals.items(), key=lambda x: -x[1]):
        b = detail.get(k, "")
        vis = bytes.fromhex(b)[:4].hex() if b else ""
        print("%-34s x%-4d corps_complet=%-24s visible_watch=%s" % (k, n, b, vis))


if __name__ == "__main__":
    main()
