"""Decode the PC BLE corpora (out/rea/artefacts/ble-2026*-frames.log).

MTU on the PC leg was 517, so corps= carries the FULL payload. For every frame
we show the full protobuf tree and, separately, what a CIQ watch (20-octet
notification cap) would have been able to see.
"""
import re
import sys
import glob
import os

LINE = re.compile(
    r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(APP->CAM|CAM->APP)\s+code=(\d+)\s+(\S+)\s+"
    r"seq=(\d+)\s+declared=(\d+)\s+corps=0x([0-9a-fA-F]*)$"
)


def varint(b, i):
    v = 0
    sh = 0
    while i < len(b):
        c = b[i]
        v |= (c & 0x7F) << sh
        i += 1
        if not (c & 0x80):
            return v, i
        sh += 7
    return None, i  # truncated varint


def decode(b, depth=0, maxdepth=4):
    """protobuf tree, tolerant of truncation."""
    out = []
    i = 0
    n = len(b)
    while i < n:
        tag, j = varint(b, i)
        if tag is None:
            out.append("%s<truncated tag @%d>" % ("  " * depth, i))
            return out
        fnum, wt = tag >> 3, tag & 7
        pad = "  " * depth
        if wt == 0:
            v, j = varint(b, j)
            if v is None:
                out.append("%s%d: <cut varint>" % (pad, fnum))
                return out
            out.append("%s%d: %d (0x%x)" % (pad, fnum, v, v))
            i = j
        elif wt == 2:
            ln, j = varint(b, j)
            if ln is None:
                out.append("%s%d: <cut len>" % (pad, fnum))
                return out
            sub = b[j:j + ln]
            cut = len(sub) < ln
            if depth < maxdepth and sub and all(0 <= x < 256 for x in sub):
                inner = decode(bytes(sub), depth + 1, maxdepth)
                looks_like_pb = len(inner) > 0 and not any("<cut" in x or "<trunc" in x for x in inner)
                if looks_like_pb or cut:
                    out.append("%s%d: {%d o%s}" % (pad, fnum, ln, " CUT" if cut else ""))
                    out.extend(inner)
                    i = j + len(sub)
                    continue
            txt = "".join(chr(c) if 32 <= c < 127 else "." for c in sub)
            out.append('%s%d: "%s" (%d o%s)' % (pad, fnum, txt, ln, " CUT" if cut else ""))
            i = j + len(sub)
        elif wt == 5:
            out.append("%s%d: i32 %s" % (pad, fnum, b[j:j + 4].hex()))
            i = j + 4
        elif wt == 1:
            out.append("%s%d: i64 %s" % (pad, fnum, b[j:j + 8].hex()))
            i = j + 8
        else:
            out.append("%s%d: <wiretype %d>" % (pad, fnum, wt))
            return out
    return out


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(glob.glob(os.path.join(d, "ble-*-frames.log")))
    only = set(int(x) for x in sys.argv[2:]) if len(sys.argv) > 2 else None
    for f in files:
        base = os.path.basename(f).replace("-frames.log", "")
        shown = False
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, code, name, seq, declared, hexs = m.groups()
            code = int(code)
            declared = int(declared)
            body = bytes.fromhex(hexs)
            if only is not None and code not in only:
                continue
            if not shown:
                print("\n########## %s ##########" % base)
                shown = True
            total = 16 + len(body)
            watch = "WATCH_SEES %d/%d o" % (min(total, 20), total)
            print("%s %-8s code=%-5d %-26s seq=%-8s declared=%-4d corps=%s" %
                  (t, dirn, code, name, seq, declared, hexs or "0x"))
            if body:
                print("   " + " | ".join(decode(body)).replace("\n", ""))
                print("   %s  body_hex=%s" % (watch, body.hex()))


if __name__ == "__main__":
    main()
