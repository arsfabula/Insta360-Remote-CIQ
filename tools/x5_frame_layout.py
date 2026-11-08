"""Where the bytes of one answer sit when the camera splits it over notifications.

The watch link only carries short notifications (measured: 20 octets is the budget
a watch can both write and read, see PROTOCOL_APK.md 15.9 / 15.19), so a command
answer is spread over several of them and only the 16-octet header repeats. The
official app reassembles them (meth 714 @0xd123 + initFrameParser @0x9696); a watch
that reads one notification at a time sees the body cut in the middle of a field.

This tool walks the PC corpora, reassembles each multi-notification answer
(`x5_corpus_full.frames_of`), and reports, for the fields that matter to a remote
app - the option ids, the battery value (option 11) and the storage value (option
20) - which notification they land in.

Usage: python tools/x5_frame_layout.py [artefacts-dir]
"""
import collections
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from x5_corpus_full import frames_of, envelope, varint, pb  # noqa: E402
from x5_corpus_options import entries, ids_of  # noqa: E402


def find_subseq(whole, sub):
    """byte offsets of `sub` inside `whole` (a whole-subsequence search is enough:
    we only use it on bodies where the value is known to appear)."""
    return whole.find(sub)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "out/rea/artefacts"
    hist = collections.Counter()
    shown = 0
    for fp in sorted(glob.glob(os.path.join(d, "ble-2026*.log"))):
        if fp.endswith("-frames.log"):
            continue
        rows = [(t, dirn, envelope(env), body)
                for t, dirn, env, body in frames_of(fp)]
        for i, (t, dirn, e, body) in enumerate(rows):
            hist[("TX" if dirn == "TX" else "RX", e["code"])] += 1
            if dirn != "TX" or e["code"] != 8:
                continue
            # gather the answer that follows: consecutive RX frames whose declared
            # total covers us (the answer carries the requested ids, so no seq rule
            # is needed and none holds across sessions).
            seq = []
            total = 0
            for j in range(i + 1, min(i + 60, len(rows))):
                t2, d2, e2, b2 = rows[j]
                if d2 != "RX":
                    break
                seq.append((t2, e2, b2))
                total += len(b2)
                if e2["total"] and total >= e2["total"]:
                    break
            if len(seq) < 2:
                continue
            whole = b"".join(s[2] for s in seq)
            top = entries(whole)
            blocks = [v for k, v in top.get(2, []) if k == "b"]
            if not blocks:
                continue
            sub = entries(blocks[0])
            want = {}
            for oid in (11, 20, 40, 41):
                vals = [v for k, v in sub.get(oid, []) if k == "b"]
                if vals:
                    want[oid] = vals[0]
            if len(want) < 2:
                continue
            ids = ids_of(whole)
            print("== reponse GET_OPTIONS reassemblee : %d notifications, %d octets "
                  "(%s)" % (len(seq), len(whole), os.path.basename(fp)))
            off = 0
            for k, (t2, e2, b2) in enumerate(seq):
                print("   notif #%d  payload %-3d octets  frame[%3d..%3d]  seq=%-3d "
                      "annonce=%-4d" % (k, len(b2), 16 + off, 16 + off + len(b2) - 1,
                                        e2["seq"], e2["total"]))
                off += len(b2)
            print("   ids demandees : %s" % (ids[:12] + (["..."] if len(ids) > 12 else [])))
            for oid in sorted(want):
                pos = find_subseq(whole, want[oid])
                if pos < 0:
                    continue
                acc = 0
                at = None
                for k, (_t, _e, b2) in enumerate(seq):
                    if pos < acc + len(b2):
                        at = (k, pos - acc)
                        break
                    acc += len(b2)
                print("   option %-3s valeur (%2d octets) : corps+%-3d frame[%3d] "
                      "-> notification #%s" % (oid, len(want[oid]), pos, 16 + pos,
                                               at[0] if at else "?"))
            print("   decodage : %s" % " ".join(pb(whole))[:400])
            print()
            shown += 1
            if shown >= 4:
                break
        if shown >= 4:
            break
    print("=== codes vus sur le fil ===")
    for (dside, code), n in sorted(hist.items(), key=lambda kv: -kv[1]):
        print("   %-3s code %-6d 0x%-4X  x%d" % (dside, code, code, n))


if __name__ == "__main__":
    main()
