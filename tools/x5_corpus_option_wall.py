"""Per-option visibility table from the PC corpora (MTU 517 => full bodies).

Answers of the GET_OPTIONS family look like:
    08 <optid> 12 <len> <value bytes>   (repeated entries)
For each entry we report: option id, value wire type, value length, the frame
octet where the value starts, and whether the whole value fits inside the
20-octet window a CIQ watch can receive.
"""
import re
import sys
import glob
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decode_corp import varint  # noqa: E402

LINE = re.compile(
    r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(APP->CAM|CAM->APP)\s+code=(\d+)\s+(\S+)\s+"
    r"seq=(\d+)\s+declared=(\d+)\s+corps=0x([0-9a-fA-F]*)$"
)

ENV = 16          # envelope octets before the protobuf body
CAP = 20          # CIQ notification cap


def parse_entries(body):
    """returns list of (optid, valtag_fnum, valwt, valbytes, off_of_valuebytes)"""
    out = []
    i = 0
    n = len(body)
    while i < n:
        tag, j = varint(body, i)
        if tag is None or (tag >> 3) != 1 or (tag & 7) != 0:
            break
        optid, j = varint(body, j)
        if optid is None:
            break
        if j >= n:
            out.append((optid, None, None, b"", j))
            break
        tag2, k = varint(body, j)
        if tag2 is None:
            break
        wt2 = tag2 & 7
        if wt2 == 0:
            v, k2 = varint(body, k)
            out.append((optid, tag2 >> 3, 0, body[k:k2], k))
            i = k2
        elif wt2 == 2:
            ln, k2 = varint(body, k)
            if ln is None:
                break
            out.append((optid, tag2 >> 3, 2, body[k2:k2 + ln], k2))
            i = k2 + ln
        else:
            break
    return out


def main():
    d = sys.argv[1]
    only = set(int(x) for x in sys.argv[2:]) if len(sys.argv) > 2 else None
    agg = {}
    for f in sorted(glob.glob(os.path.join(d, "ble-*-frames.log"))):
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, code, name, seq, decl, hexs = m.groups()
            if dirn != "CAM->APP" or int(code) not in (200, 400) or not hexs:
                continue
            body = bytes.fromhex(hexs)
            total = ENV + len(body)
            for (optid, fnum2, wt2, vb, off) in parse_entries(body):
                if only is not None and optid not in only:
                    continue
                vstart, vend = ENV + off, ENV + off + len(vb) - 1
                vis = "FULL" if vend < CAP else ("PART" if vstart < CAP else "NONE")
                key = (optid, wt2, len(vb), total, vstart, vend, vis)
                a = agg.setdefault(key, {"n": 0, "hex": set()})
                a["n"] += 1
                if len(a["hex"]) < 3:
                    a["hex"].add(vb.hex())
    print("%-5s %-3s %-5s %-6s %-6s %-6s %-5s %s" %
          ("opt", "wt", "vlen", "frame", "vstart", "vend", "vis", "value hex examples"))
    for key in sorted(agg, key=lambda k: (k[0], k[3])):
        optid, wt2, vlen, total, vstart, vend, vis = key
        a = agg[key]
        print("%-5s %-3s %-5s %-6d %-6d %-6d %-5s n=%-3d %s" %
              (optid, wt2, vlen, total, vstart, vend, vis, a["n"], " ".join(sorted(a["hex"]))))


if __name__ == "__main__":
    main()
