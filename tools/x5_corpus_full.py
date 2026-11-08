"""Reassemble and decode the RAW PC captures end to end.

Source: out/rea/artefacts/ble-2026*.log (the lines the sniffer wrote *before*
its own 48-octet `corps=` truncation, so nothing is lost here).

Raw line format:  HH:MM:SS.mmm  RX|TX  len=N  0x<hex>
One line = one ATT write / one notification value. A frame bigger than the ATT
MTU is split: the FIRST chunk carries the 16-octet envelope (its first four
octets are the u32 LE total length, envelope included), the following chunks
carry bare continuation bytes. TX chunks are 20 octets (phone->camera leg was
kept at 20 in these captures); RX chunks can reach 148.

This tool stitches chunks back together per direction, then prints for every
complete frame: envelope, full body hex, protobuf tree, and what a CIQ watch
(20-octet notifications) would have to concatenate to see the same fields.

Usage:
    python tools/x5_corpus_full.py <artefacts-dir> [--codes 8,200] [--grep HEX]
"""
import glob
import os
import re
import struct
import sys

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-fA-F]*)\s*$")

ENV = 16

# From tools/apk_extract/message_code_map.txt (APK side, reference only).
NAMES = {}


def load_names(path):
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.strip()
        if not ln or ln.startswith("#") or "=" not in ln:
            continue
        k, _, v = ln.partition("=")
        try:
            NAMES[int(v)] = k
        except ValueError:
            pass


def varint(b, i):
    v = 0
    sh = 0
    while i < len(b):
        c = b[i]
        v |= (c & 0x7F) << sh
        i += 1
        if not c & 0x80:
            return v, i
        sh += 7
    return None, i


def pb(b, depth=0, maxdepth=5):
    """protobuf tree, tolerant of truncation."""
    out = []
    i = 0
    while i < len(b):
        tag, j = varint(b, i)
        if tag is None:
            out.append("%s<cut>" % ("  " * depth))
            break
        f, wt = tag >> 3, tag & 7
        pad = "  " * depth
        if wt == 0:
            v, j = varint(b, j)
            if v is None:
                out.append("%s%d: <cut varint>" % (pad, f))
                break
            out.append("%s%d: %d (0x%x)" % (pad, f, v, v))
            i = j
        elif wt == 2:
            ln, j = varint(b, j)
            if ln is None:
                out.append("%s%d: <cut len>" % (pad, f))
                break
            sub = b[j:j + ln]
            cut = len(sub) < ln
            inner = pb(bytes(sub), depth + 1, maxdepth) if sub and depth < maxdepth else []
            clean = inner and not any("<cut" in x for x in inner)
            txt = "".join(chr(c) if 32 <= c < 127 else "." for c in sub)
            if clean and all(32 <= c < 127 for c in sub) and len(sub) > 1:
                out.append('%s%d: "%s"' % (pad, f, txt))
            elif clean or cut:
                out.append("%s%d: {%d o%s}" % (pad, f, ln, " CUT" if cut else ""))
                out.extend(inner)
            else:
                out.append('%s%d: b"%s"' % (pad, f, txt))
            i = j + len(sub)
        elif wt == 5:
            out.append("%s%d: i32 %s" % (pad, f, b[j:j + 4].hex()))
            i = j + 4
        elif wt == 1:
            out.append("%s%d: i64 %s" % (pad, f, b[j:j + 8].hex()))
            i = j + 8
        else:
            out.append("%s%d: <wiretype %d>" % (pad, f, wt))
            break
    return out


def frames_of(path):
    """Yield (t, dirn, envelope_bytes, body) for every reassembled frame."""
    pend = {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        m = LINE.match(raw.strip())
        if not m:
            continue
        t, dirn, _ln, hexs = m.groups()
        if not hexs:
            continue
        c = bytes.fromhex(hexs)
        want = pend.get(dirn)
        if want is None:
            if len(c) < 4:
                continue
            total = struct.unpack_from("<I", c, 0)[0]
            if not (ENV <= total <= 4096):
                continue
            if len(c) == total:
                yield t, dirn, c[:ENV], c[ENV:]
            elif len(c) < total:
                pend[dirn] = (t, c, total)
            else:
                pend[dirn] = (t, c[:total], total)
            continue
        t0, buf, total = want
        buf = buf + c
        if len(buf) < total:
            pend[dirn] = (t0, buf, total)
            continue
        del pend[dirn]
        yield t0, dirn, buf[:ENV], buf[ENV:]


def envelope(env):
    total = struct.unpack_from("<I", env, 0)[0]
    code = struct.unpack_from("<H", env, 7)[0]
    seqraw = struct.unpack_from("<I", env, 10)[0]
    return dict(total=total, b4=env[4], code=code, b9=env[9],
                flags=seqraw >> 24, seq=seqraw & 0xFFFFFF, raw=env.hex())


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "out/rea/artefacts"
    codes = None
    grep = None
    args = sys.argv[2:]
    while args:
        a = args.pop(0)
        if a == "--codes":
            codes = set(int(x) for x in args.pop(0).split(","))
        elif a == "--grep":
            grep = args.pop(0).lower()
    load_names(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "apk_extract", "message_code_map.txt"))
    nfr = 0
    for f in sorted(glob.glob(os.path.join(d, "ble-2026*.log"))):
        if f.endswith("-frames.log"):
            continue
        shown = False
        for t, dirn, env, body in frames_of(f):
            e = envelope(env)
            if codes is not None and e["code"] not in codes:
                continue
            if grep is not None and grep not in body.hex():
                continue
            if not shown:
                print("\n########## %s ##########" % os.path.basename(f))
                shown = True
            nfr += 1
            nm = NAMES.get(e["code"], "")
            print("%s %-4s code=%-5d %-34s flags=%#04x seq=%-8d declared=%-4d corps(%d)=%s" %
                  (t, dirn, e["code"], nm, e["flags"], e["seq"], len(body), len(body), body.hex()))
            if body:
                for ln in pb(body):
                    print("   %s" % ln)
    print("\n%d frames reassembles" % nfr)


if __name__ == "__main__":
    main()
