#!/usr/bin/env python3
"""Inventaire des commandes BLE envoyees par un .prg Garmin.

Point de depart: l'unique site d'appel de BluetoothLowEnergy.Characteristic#requestWrite.
On remonte a l'expediteur de trame (celui qui construit l'en-tete de 16 octets) puis a
l'envoyeur (`send(payload, code, ...)`), et on liste tous les sites qui l'appellent en
arguments constants: ce sont les codes de commande utilises par l'application.

Le P-code Garmin n'a pas de table de symboles dans un .prg distribue: les methodes sont
designees par leur numero de champ (slot virtuel). Un meme numero peut etre partage par
plusieurs classes (surcharge), d'ou la resolution en priorite dans la classe englobante.

Usage:
    python tools/prg_sendcmds.py <file.prg> [--write-site 0xcca2] [--map tools/apk_extract/message_code_map.txt]

Ne modifie jamais la cible.
"""

import argparse
import collections
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_analyze import Prg, build_uses, build_callgraph

# instructions qui preparent un argument, dans l'ordre ou elles poussent sur la pile
ARGOPS = ("npush", "ipush", "ipush1", "ipush2", "ipush3", "ipushz", "bfpush", "btpush",
          "frpush", "lgetv", "getselfv", "getsv", "getmv", "spush", "newc", "news",
          "fpush", "lpush", "apush", "bapush", "hpush", "getself", "getlocalv", "argc",
          "argincisp", "argcincsp", "dup", "popv", "invokemz", "invoke", "invv", "newd",
          "newa", "newba", "addv", "aputv", "putv", "lputv")


def arg_sequence(p, pc_start, call_pc, call_end):
    """Sequence d'instructions entre l'appel et la preparation des arguments."""
    seq = []
    for q, mn, arg, ann in p.disasm(pc_start):
        if q < call_pc:
            continue
        if q > call_end:
            break
        a = "" if arg is None else ("%d %d" % arg if isinstance(arg, tuple) else str(arg))
        seq.append((q, mn, a, ann))
        if mn.startswith("invoke"):
            break
    return seq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("--api-db", default=None)
    ap.add_argument("--write-site", default="0xcca2",
                    help="adresse du getsv requestWrite dans le P-code")
    ap.add_argument("--map", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "apk_extract", "message_code_map.txt"))
    args = ap.parse_args()
    db = args.api_db
    if db is None:
        cands = sorted(glob.glob(os.path.expanduser("~/.Garmin/ConnectIQ/Sdks/*/bin/api.db")))
        db = cands[-1] if cands else None
    p = Prg(args.prg, db)
    build_uses(p)

    # 1. nom de la classe qui ecrit, et sa methode d'envoi
    wsite = int(args.write_site, 0)
    wmethod = p.method_at(wsite)
    if not wmethod:
        print("site d'ecriture introuvable")
        return 1
    wpc, wcls, wsym, wflags = wmethod
    print("# classe transport: class @data+%#x, methode d'ecriture code+%#x" % (wcls, wpc))

    # 2. chaine d'appels: requestWrite -> expediteur de trame -> envoyeur
    build_callgraph(p)

    def direct(pc):
        return p.callers.get(pc, [])

    def name(pc):
        c, s, f = p.methods[pc]
        return "code+%#x (%s.%s)" % (pc, hex(c), p.api.get(s, s))

    # couche 1: qui appelle la methode d'ecriture
    lvl1 = {c for q, c, mn, amb in direct(wpc)}
    # couche 2: qui appelle ces fonctions
    lvl2 = set()
    for c in lvl1:
        lvl2 |= {x for q, x, mn, amb in direct(c)}
    # couche 3
    lvl3 = set()
    for c in lvl2:
        lvl3 |= {x for q, x, mn, amb in direct(c)}
    for lbl, ensemble in (("L1 (a l'interieur de requestWrite)", lvl1),
                          ("L2", lvl2), ("L3", lvl3)):
        print("\n# %s: %s" % (lbl, ", ".join(sorted(name(c) for c in ensemble))))

    # 3. pour chaque classe qui definit un slot d'envoi appele en L2/L3, lister les sites
    #    avec leurs arguments
    senders = collections.defaultdict(list)   # (classe, slot) -> sites
    for c in (lvl1 | lvl2 | lvl3 | {wpc}):
        cls_off, sym, flags = p.methods[c]
        for q, caller, mn, amb in direct(c):
            co, cs, cf = p.methods[caller]
            senders[(c, co, cs)].append(q)
    print("\n=== sites d'appel des fonctions de la chaine d'envoi ===")
    for (callee, co, cs), sites in sorted(senders.items()):
        print("\n### %s appelee depuis class @data+%#x meth %s(%d) : %d sites"
              % (name(callee), co, p.api.get(cs, cs), cs, len(sites)))
        for q in sites:
            caller = p.method_at(q)[0]
            seq = arg_sequence(p, caller, q, q + 40)
            txt = " | ".join("%s %s" % (mn, a) for _, mn, a, _ in seq)
            anns = [ann[4:] for _, mn, a, ann in seq if ann.startswith("  ; ")]
            print("  code+%#05x: %s" % (q, txt))
            if anns:
                print("       refs: %s" % "; ".join(dict.fromkeys(anns)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
