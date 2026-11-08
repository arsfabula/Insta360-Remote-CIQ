"""Repond aux questions "quelle est la reponse complete de la camera a la
commande N ?" en recollant les morceaux du fil PC (voir x5_corpus_full.py).

Pour chaque requete APP->CAM d'un code donne, on cherche la trame CAM->APP
code=200 qui a le meme seq dans la meme session, et on imprime son corps complet
+ l'arbre protobuf. Utile pour les commandes dont la reponse depasse les 20
premiers octets (asks 8, 10, 15).

Usage: python tools/x5_corpus_answer.py [artefacts-dir] [--codes 8,10,15]
"""
import collections
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from x5_corpus_full import frames_of, envelope, pb, load_names, NAMES  # noqa: E402


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "out/rea/artefacts"
    codes = [15]
    args = sys.argv[2:]
    while args:
        a = args.pop(0)
        if a == "--codes":
            codes = [int(x) for x in args.pop(0).split(",")]
    load_names(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "apk_extract", "message_code_map.txt"))
    for code in codes:
        seen = collections.Counter()
        shapes = collections.Counter()
        nreq = 0
        for fp in sorted(glob.glob(os.path.join(d, "ble-2026*.log"))):
            if fp.endswith("-frames.log"):
                continue
            reqs = {}
            for _t, dirn, env, body in frames_of(fp):
                e = envelope(env)
                if dirn == "TX" and e["code"] == code:
                    reqs[e["seq"]] = body
                    nreq += 1
                elif dirn == "RX" and e["code"] == 200 and e["seq"] in reqs:
                    seen[body.hex()] += 1
                    shapes[" | ".join(pb(body))] += 1
        print("=== ask code=%d (%s) : %d requetes, %d reponses 200 ===" %
              (code, NAMES.get(code, ""), nreq, sum(seen.values())))
        for h, n in seen.most_common(6):
            print("  x%-4d corps=%s" % (n, h))
        for s, n in shapes.most_common(4):
            print("  x%-4d %s" % (n, s))
        print()


if __name__ == "__main__":
    main()
