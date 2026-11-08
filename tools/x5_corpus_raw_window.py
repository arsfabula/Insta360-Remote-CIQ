"""Decode the RAW PC captures (out/rea/artefacts/ble-2026*.log, no -frames).

Raw lines:  HH:MM:SS.mmm  RX|TX  len=N  0x<hex>
The PC leg negotiated ATT MTU 517, so an RX frame is delivered whole (the capture
tool itself caps at 240 octets).

For each camera frame we print the envelope, the full body, the protobuf entries,
and the 20-octet window a CIQ watch would have received.
"""
import re
import sys
import glob
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_corp import varint, decode  # noqa: E402

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-fA-F]*)\s*$")

CAP = 20


def entries(body):
    out = []
    i = 0
    while i < len(body):
        tag, j = varint(body, i)
        if tag is None:
            break
        fnum, wt = tag >> 3, tag & 7
        if wt == 0:
            v, k = varint(body, j)
            if v is None:
                out.append((fnum, 0, None, body[j:j], j, True))
                break
            out.append((fnum, 0, v, body[j:k], j, False))
            i = k
        elif wt == 2:
            ln, k = varint(body, j)
            if ln is None:
                break
            out.append((fnum, 2, ln, body[k:k + ln], k, len(body[k:k + ln]) < ln))
            i = k + ln
        else:
            out.append((fnum, wt, None, b"", j, True))
            break
    return out


def main():
    files = sorted(glob.glob(os.path.join(sys.argv[1], "ble-*.log")))
    files = [f for f in files if not f.endswith("-frames.log")]
    want = set(int(x) for x in sys.argv[2:]) if len(sys.argv) > 2 else None
    for f in files:
        base = os.path.basename(f)
        for ln, raw in enumerate(open(f, errors="replace"), 1):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, length, hexs = m.groups()
            fr = bytes.fromhex(hexs)
            if dirn != "RX" or len(fr) < 16:
                continue
            declared = int.from_bytes(fr[0:4], "little")
            code = int.from_bytes(fr[7:9], "little")
            body = fr[16:]
            if want is not None and code not in want:
                continue
            ent = entries(body)
            interesting = False
            for (fn, wt, v, vb, off, cut) in ent:
                if fn == 1 and wt == 0:
                    interesting = True
            if not interesting:
                continue
            print("\n%s:%d %s code=%d declared=%d captured=%d bodylen=%d" %
                  (base, ln, t, code, declared, len(fr), len(body)))
            print("  full frame : %s" % fr.hex())
            print("  watch sees : %s%s" % (fr[:CAP].hex(), "  <-- cut" if declared > CAP else "  (whole)"))
            for (fn, wt, v, vb, off, cut) in ent:
                vs, ve = 16 + off, 16 + off + len(vb) - 1
                vis = "FULL" if ve < CAP else ("PART" if vs < CAP else "NONE")
                info = "val=%s" % v if wt == 0 else "len=%d %s" % (len(vb), vb.hex())
                print("   f%-3d wt%d @body%-4d frame[%3d..%3d] %-4s %s%s" %
                      (fn, wt, off, vs, ve, vis, info, " CUT" if cut else ""))
                if wt == 2 and vb:
                    for s in decode(vb, 1, 3):
                        print("        %s" % s)


if __name__ == "__main__":
    main()
