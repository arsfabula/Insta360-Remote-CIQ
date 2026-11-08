"""Focus offline pass on the PC corpora (-frames.log): bodies of the pushes the
watch bench cares about, and the app command that preceded each one.

usage: x5_frames_focus.py <artefacts dir> [code ...]
"""
import glob
import os
import re
import sys
from collections import Counter, defaultdict

LINE = re.compile(
    r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(\w+)->(\w+)\s+code=(\d+)\s+([A-Za-z_]*)\s*"
    r"seq=(\d+)\s+declared=(\d+)\s+corps=0x([0-9a-fA-F]*)\s*$")


def main():
    d = sys.argv[1]
    want = [int(x) for x in sys.argv[2:]] or None
    files = sorted(glob.glob(os.path.join(d, "*-frames.log")))
    print("fichiers frames: %d" % len(files))
    bodies = defaultdict(Counter)
    names = defaultdict(Counter)
    prev_cmd = defaultdict(Counter)      # push code -> preceding APP->CAM command
    seqs = defaultdict(Counter)
    for f in files:
        last_app = None
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, src, dst, code, name, seq, decl, hexs = m.groups()
            code = int(code)
            name = name.strip()
            if src == "APP":
                last_app = (code, name, hexs)
                continue
            if code < 8000:
                continue
            if want and code not in want:
                continue
            bodies[code][hexs] += 1
            names[code][name] += 1
            seqs[code][len(hexs) // 2] += 1
            prev_cmd[code][("cmd %d %s %s" % last_app) if last_app else "aucune"] += 1
    for code in sorted(bodies):
        tot = sum(bodies[code].values())
        print("\n== push %d (0x%04x)  n=%d  noms=%s  tailles=%s" % (
            code, code, tot, dict(names[code]), dict(seqs[code])))
        for h, n in bodies[code].most_common(10):
            print("   n=%-4d corps=%s" % (n, h or "(vide)"))
        for k, n in prev_cmd[code].most_common(6):
            print("   avant: n=%-4d %s" % (n, k))


if __name__ == "__main__":
    main()
