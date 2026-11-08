"""What the camera answers to PHONE_COMMAND_GET_OPTIONS, option id by option id.

Pairs every code=8 request with the code=200 answer that carries the same seq in
the same session (see x5_corpus_full.py for the reassembly), then groups the
option values by protobuf field number. The field number of an answer entry IS
the option id that was asked for: request `0a 06 0b 0f 10 14 1e 30` (ids 11,15,
16,20,30,48) is answered with `08 0b 08 0f ...` (same ids echoed in field 1) plus
one entry per id in field <id>.

Usage: python tools/x5_corpus_options.py [artefacts-dir]
"""
import collections
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from x5_corpus_full import frames_of, envelope, varint, load_names, NAMES  # noqa: E402


def ids_of(body):
    """packed repeated field 1 -> list of ids (varints, so ids >= 128 are 2 bytes)."""
    out = []
    i = 0
    while i < len(body):
        tag, j = varint(body, i)
        if tag is None:
            break
        f, wt = tag >> 3, tag & 7
        if wt == 2:
            ln, k = varint(body, j)
            if ln is None:
                break
            end = k + ln
            while k < end:
                v, k = varint(body, k)
                if v is None:
                    break
                out.append(v)
            i = end
        elif wt == 0:
            v, k = varint(body, j)
            if v is None:
                break
            out.append(v)
            i = k
        else:
            break
    return out


def entries(body):
    """field number -> list of ('v', int) or ('b', bytes) at this level."""
    top = collections.defaultdict(list)
    i = 0
    while i < len(body):
        tag, j = varint(body, i)
        if tag is None:
            break
        f, wt = tag >> 3, tag & 7
        if wt == 0:
            v, k = varint(body, j)
            if v is None:
                break
            top[f].append(("v", v))
            i = k
        elif wt == 2:
            ln, k = varint(body, j)
            if ln is None:
                break
            top[f].append(("b", body[k:k + ln]))
            i = k + ln
        else:
            break
    return top


def render(sub):
    parts = []
    for g, vals in sorted(sub.items()):
        for kind, v in vals:
            if kind == "v":
                parts.append("%d=%d" % (g, v))
            else:
                txt = "".join(chr(c) if 32 <= c < 127 else "." for c in v)
                if len(v) > 1 and all(32 <= c < 127 for c in v):
                    parts.append('%d="%s"' % (g, txt))
                else:
                    inner = render(entries(v))
                    parts.append("%d{%s}" % (g, " ".join(inner) if inner else v.hex()))
    return parts


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "out/rea/artefacts"
    load_names(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "apk_extract", "message_code_map.txt"))
    asked = collections.Counter()
    forms = collections.defaultdict(collections.Counter)
    pairs = 0
    for fp in sorted(glob.glob(os.path.join(d, "ble-2026*.log"))):
        if fp.endswith("-frames.log"):
            continue
        reqs = {}
        for _t, dirn, env, body in frames_of(fp):
            e = envelope(env)
            if e["code"] == 8:
                reqs[e["seq"]] = tuple(ids_of(body))
                asked[reqs[e["seq"]]] += 1
            elif e["code"] == 200 and e["seq"] in reqs:
                pairs += 1
                # envelope body = {1: [ids echoed], 2: {<option id>: <value>, ...}}
                top = entries(body)
                blocks = [v for k, v in top.get(2, []) if k == "b"]
                for blk in blocks:
                    for f, vals in entries(blk).items():
                        for kind, v in vals:
                            if kind == "v":
                                forms[f]["varint %d" % v] += 1
                            else:
                                forms[f]["len%-3d {%s}" % (len(v), " ".join(render(entries(v))))] += 1
    print("%d requetes GET_OPTIONS, %d reponses codees" % (sum(asked.values()), pairs))
    print("\n=== listes d'options demandees (champ 1 packed) ===")
    for k, n in asked.most_common(40):
        print("  x%-4d ids=%s" % (n, list(k) if len(k) <= 8 else "%d ids %d..%d" % (len(k), k[0], k[-1])))
    print("\n=== ce que la camera repond, par numero de champ = id d'option ===")
    for f in sorted(forms):
        print("option %-4s  %d formes" % (f, len(forms[f])))
        for s, n in forms[f].most_common(5):
            print("    x%-4d %s" % (n, s))


if __name__ == "__main__":
    main()
