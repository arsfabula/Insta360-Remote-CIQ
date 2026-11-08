"""Table des reponses code=200/400 dont le CORPS tient dans la fenetre de la
montre: la montre ne voit que 4 octets de corps (enveloppe de 16 + charge ATT de
20), donc declared <= 4 = corps ENTIER, declared <= 6 = les deux varints de tete.
C'est la liste des questions utilisables par le baril sans rien perdre.

usage: x5_frames_short_answers.py <artefacts dir>
"""
import glob
import os
import re
import sys
from collections import Counter

LINE = re.compile(
    r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(\w+)->(\w+)\s+code=(\d+)\s+([A-Za-z_]*)\s*"
    r"seq=(\d+)\s+declared=(\d+)\s+corps=0x([0-9a-fA-F]*)\s*$")


def main():
    d = sys.argv[1]
    files = sorted(glob.glob(os.path.join(d, "*-frames.log")))
    short = Counter()
    detail = {}
    for f in files:
        last_app = None
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, src, dst, code, name, seq, decl, hexs = m.groups()
            code, decl = int(code), int(decl)
            name = name.strip()
            if src == "APP":
                last_app = (code, name, hexs)
                continue
            if code not in (200, 400):
                continue
            if decl > 6 or decl == 0:
                continue
            key = (("cmd %d %s corps=%s" % last_app) if last_app
                   else "sans commande")
            short[(key, hexs, decl)] += 1
            detail.setdefault((key, hexs, decl), os.path.basename(f))
    print("reponses code=200/400 entieres (<=20 octets), %d formes:" % len(short))
    for (key, hexs, decl), n in short.most_common(60):
        vis = hexs[:8]
        print("   n=%-4d corps=%d visible4=%s%s | %s | %s"
              % (n, decl, vis, "" if decl <= 4 else " (COUPE)", key,
                 detail[(key, hexs, decl)]))


if __name__ == "__main__":
    main()
