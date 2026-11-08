"""Table commande -> message protobuf envoye, pour l'app montre Insta360 officielle.

Chemin sur (verifie methode par methode, voir out/prg/cmd_payloads.txt):

  * la classe `@data+0xa7b` est le CameraManager : toutes les commandes partent de la;
  * son slot 242 (`toCamera`) est le seul point de depart : il prend
    (message, code, callback) et les remet au slot 242 de l'objet de transport
    (`globals.sym185.getInstance()`), seule classe a appeler
    `BluetoothLowEnergy.requestWrite` (`@data+0x2346`, see class_2346.txt);
  * dans chaque methode d'envoi le motif P-code est toujours le meme :
        getmv 38 <sym> ; -> message Xxx
        newc / initialize / lputv k
        lgetv k ; spush <champ> ; lgetv <arg> ; putv      (remplit le message)
        getselfv 242 ; frpush ; lgetv k ; ipushN <code> ; lgetv <cb> ; invoke 4

  Ce script retrouve, pour chaque site `getselfv 242`, le message dont la variable
  locale est passee en argument, en remontant du `lgetv k` a son `lputv k` puis au
  `getmv 38` le plus proche.

Usage: python tools/prg_cmd_payloads.py <file.prg> [--codes 3,8]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_analyze import Prg, load_api_db  # noqa: E402

API_DB = os.path.expanduser("~/connectiq_sdk/bin/api.db")
SDK_DB = "/home/greg/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/api.db"
CLS_MANAGER = 0xA7B
SLOT_TOCAMERA = 242


def load_apk_names(path):
    out = {}
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.strip()
        if ln.startswith("PHONE_COMMAND_"):
            k, _, v = ln.partition("=")
            out[int(v)] = k[len("PHONE_COMMAND_"):]
    return out


def main():
    p = Prg(sys.argv[1])
    p.api = load_api_db(API_DB if os.path.exists(API_DB) else SDK_DB)
    only = None
    args = sys.argv[2:]
    while args:
        a = args.pop(0)
        if a == "--codes":
            only = set(int(x) for x in args.pop(0).split(","))

    # nom de chaque classe de message : son print() news "Name {"
    names = {}
    for off, cls in p.classes.items():
        for sym, _fl, pc in p.methods_by_class.get(off, []):
            if sym == 8388712:
                for _q, mn, a, _ann in p.disasm(pc):
                    if mn == "news":
                        s = p.strings.get(a, "")
                        if s.endswith(" {"):
                            names[off] = s[:-2]
    apk = load_apk_names(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      "apk_extract", "message_code_map.txt"))

    rows = []
    for sym, _fl, pc in sorted(p.methods_by_class[CLS_MANAGER], key=lambda t: t[2]):
        body = list(p.disasm(pc))
        for i, (q, mn, arg, _ann) in enumerate(body):
            if not (mn in ("getselfv", "getsv") and arg == SLOT_TOCAMERA):
                continue
            # les arguments de l'appel, jusqu'a l'invoke qui les ferme
            code = None
            slots = []
            callback = None
            for k in range(i + 1, len(body)):
                _q2, m2, a2, _an2 = body[k]
                if m2.startswith("invoke"):
                    break
                if m2.startswith("ipush") and isinstance(a2, int) and 0 < a2 < 400 and code is None:
                    code = a2
                elif m2 == "lgetv" and isinstance(a2, int):
                    slots.append(a2)
            if code is None or (only is not None and code not in only):
                continue
            # d'ou vient le premier argument (le message) ?
            msg = None
            first = None
            for k in range(i + 1, len(body)):
                _q2, m2, a2, _an2 = body[k]
                if m2.startswith("invoke"):
                    break
                if m2 == "lgetv" and isinstance(a2, int):
                    first = a2
                    break
            if first is not None:
                for k in range(i, -1, -1):
                    _q2, m2, a2, _an2 = body[k]
                    if m2 == "lputv" and a2 == first:
                        for j in range(k, -1, -1):
                            _q3, m3, a3, an3 = body[j]
                            if m3 == "getmv" and isinstance(a3, tuple):
                                msg = an3.split("-> ")[-1].strip()
                                break
                        break
            rows.append((code, q, pc, msg, slots))

    print("=== commandes envoyees par l'app montre : code, methode, message de corps ===\n")
    seen = set()
    for code, q, pc, msg, slots in sorted(rows):
        print("code %-4s %-32s meth @%#05x site %#05x   corps: %-34s locals passes: %s" %
              (code, apk.get(code, "?"), pc, q, msg or "(corps vide)", slots))
        seen.add(code)
    print("\n%d sites, %d codes differents : %s" %
          (len(rows), len(seen), sorted(seen)))


if __name__ == "__main__":
    main()
