#!/usr/bin/env python3
"""Listing annote du P-code d'un .prg Garmin, avec les identifiants API nommes.

Contre-la-montre de l'outillage: prg_disasm.py ne nommait rien (pas de section
Symbols dans un .prg distribue). Ici chaque symbole >= 0x800000 rencontre dans le
code est resolus contre l'api.db du SDK (identifiants predefinis de Monkey C),
les autres contre les class_defs de la section Data.

Sorties:
    <out>/annotated.txt   listing complet, methode par methode
    stdout                bilan: identifiants API utilises + compteurs

Usage:
    python tools/prg_listing.py <file.prg> [--out DIR] [--api-db FICHIER]
"""

import argparse
import collections
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_analyze import Prg, build_uses


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("--out", default="out/prg/disasm")
    ap.add_argument("--api-db", default=None)
    args = ap.parse_args()
    db = args.api_db
    if db is None:
        cands = sorted(glob.glob(os.path.expanduser("~/.Garmin/ConnectIQ/Sdks/*/bin/api.db")))
        db = cands[-1] if cands else None
    p = Prg(args.prg, db)
    build_uses(p)

    os.makedirs(args.out, exist_ok=True)
    path = os.path.join(args.out, "annotated.txt")
    n_instr = 0
    api_use = collections.Counter()
    api_at = collections.defaultdict(list)
    unresolved = collections.Counter()
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("# listing P-code de %s\n# identifiants API resolus via %s\n" % (p.path, db))
        for i, pc in enumerate(p.method_pcs):
            end = p.method_pcs[i + 1] if i + 1 < len(p.method_pcs) else len(p.code)
            cls_off, sym, flags = p.methods[pc]
            cls = p.classes[cls_off]
            fh.write("\n### METHODE code+0x%x  class @data+0x%x  nom=%s  meth=%s(%d) "
                     "module=%s parent=%s\n"
                     % (pc, cls_off, p.class_name(cls_off) or "?",
                        p.api.get(sym, str(sym)), sym,
                        cls.get("module_id"), cls.get("parent_module_id")))
            for q, mn, arg, ann in p.disasm(pc, end):
                n_instr += 1
                a = "%d %d" % arg if isinstance(arg, tuple) else ("" if arg is None else str(arg))
                fh.write("  %05x: %-11s %-12s%s\n" % (q, mn, a, ann))
                if ann.startswith("  ; ") and not ann.startswith("  ; champ") \
                        and not ann.startswith("  ; module ") and not ann.startswith("  ; '"):
                    api_use[ann[4:]] += 1
                    api_at[ann[4:]].append(q)
                if mn.startswith("?"):
                    unresolved[mn] += 1
    print("ecrit: %s  (%d methodes, %d instructions)" % (path, len(p.method_pcs), n_instr))
    print("opcodes inconnus: %s" % dict(unresolved))
    print("\n--- %d identifiants/references resolus, %d occurrences ---" % (len(api_use), sum(api_use.values())))
    for name, n in api_use.most_common():
        print("  %-45s %3d  @%s" % (name, n, ",".join("0x%x" % x for x in api_at[name][:12])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
