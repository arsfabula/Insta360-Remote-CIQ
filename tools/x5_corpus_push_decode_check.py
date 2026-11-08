#!/usr/bin/env python3
"""Controle hors ligne du decodage v6 de la FramingProbe.

Miroir Python exact de pushDecode()/pushNote() tels qu'ecrits dans
probe/v6/push.txt, appliques au corpus PC (out/rea/artefacts/ble-*.log)
mais avec chaque notification TRONQUEE A 20 OCTETS, ce que la jambe montre
produit (16 octets d'enveloppe + 4 de corps). Si le decodage dit la bonne
chose sur des trames tronquees comme sur les completes, la sonde est juste.
"""
import glob
import re
import collections

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-f]*)\s*$")


def pb(fr, at):
    return fr[at] if 0 <= at < len(fr) else -1


def push_decode(code, fr):
    if code == 8208 and pb(fr, 16) == 0x08:
        s = "etat=" + str(pb(fr, 17))
        if pb(fr, 18) == 0x10:
            s += " sec=" + str(pb(fr, 19))
        return s
    if code == 8256 and pb(fr, 16) == 0x08:
        return "enreg=" + str(pb(fr, 17))
    if code == 8198 and pb(fr, 16) == 0x08:
        return "stock f1=" + str(pb(fr, 17)) + " f2=" + str(pb(fr, 19))
    if code == 8195 and pb(fr, 16) == 0x0a and pb(fr, 18) == 0x08:
        return "charge=" + str(pb(fr, 19))
    if code == 8275 and pb(fr, 16) == 0x08:
        return "mode f1=" + str(pb(fr, 17)) + " f2=" + str(pb(fr, 19))
    if code == 8215:
        return "wifi"
    return ""


def hexr(fr, at, n):
    return " ".join("%02x" % b for b in fr[at:min(at + n, len(fr))])


out = collections.defaultdict(collections.Counter)
for f in [x for x in sorted(glob.glob("/media/greg/media/kDrive/git/Insta360-Remote-CIQ"
                                      "/out/rea/artefacts/ble-*.log"))
          if not x.endswith("-frames.log")]:
    for l in open(f, errors="replace"):
        m = LINE.match(l.strip())
        if not m:
            continue
        fr = bytes.fromhex(m.group(4))
        if len(fr) < 16:
            continue
        code = int.from_bytes(fr[7:9], "little")
        if m.group(2) != "RX":
            continue
        full = push_decode(code, fr)
        watch = push_decode(code, fr[:20])
        out[code][(len(fr) - 16, full, len(fr[:20]) - 16, watch)] += 1

for code in sorted(out):
    n = sum(out[code].values())
    print("== code %d (0x%04x) n=%d" % (code, code, n))
    for (bl, full, wl, watch), c in out[code].most_common(6):
        same = "IDENTIQUE" if full == watch else "DIVERGE"
        print("   corps=%-3d vu=%-3d n=%-4d %-14s -> %-30s | %-30s %s"
              % (bl, wl, c, hexr(b"", 0, 0) or "", full, watch, same))
        _ = hexr
    # une seule ligne par code: le mot que la montre lirait
    ws = {w for (_, _, _, w), _n in out[code].items() if w}
    if ws:
        print("   ce que la montre imprimerait:", " / ".join(sorted(ws)[:6]))
