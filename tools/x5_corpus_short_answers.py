"""Group every ask->answer pair in the RAW PC captures and report the answer
size, full body, and the exact 20-octet window a CIQ watch would receive.

Raw lines:  HH:MM:SS.mmm  RX|TX  len=N  0x<hex>
PC leg used ATT MTU 517 (capture tool caps at 240), so bodies are complete.

A pair is matched by the 24-bit seq in envelope bytes 10..12: a TX frame carries
the seq; the RX answer echoes it. Frames longer than 20 octets are reassembled
from the capture tool's own segmentation when needed (we just use the whole hex).
"""
import re
import sys
import glob
import os
from collections import defaultdict

sys.path.insert(0, "/tmp/opencode")
from decode_corp import varint, decode  # noqa: E402

LINE = re.compile(r"^(\d\d:\d\d:\d\d\.\d\d\d)\s+(RX|TX)\s+len=(\d+)\s+0x([0-9a-fA-F]*)\s*$")
CAP = 20
ENV = 16


def body_of(fr):
    return fr[ENV:]


def main():
    d = sys.argv[1]
    maxlen = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    files = [f for f in sorted(glob.glob(os.path.join(d, "ble-*.log")))
             if not f.endswith("-frames.log")]
    agg = defaultdict(lambda: {"n": 0, "bodies": defaultdict(int)})
    for f in files:
        asks = {}
        for raw in open(f, errors="replace"):
            m = LINE.match(raw.strip())
            if not m:
                continue
            t, dirn, ln, hexs = m.groups()
            fr = bytes.fromhex(hexs)
            if len(fr) < ENV + 4:
                continue
            declared = int.from_bytes(fr[0:4], "little")
            code = int.from_bytes(fr[7:9], "little")
            seq = int.from_bytes(fr[10:13], "little")
            rcode = int.from_bytes(fr[9:11], "little")  # not used
            if dirn == "TX":
                asks[seq] = (code, body_of(fr).hex())
            else:
                if seq not in asks:
                    continue
                ac, ab = asks[seq]
                if ENV + len(body_of(fr)) > maxlen:
                    continue
                a = agg[(ac, ab, code)]
                a["n"] += 1
                a["bodies"][body_of(fr).hex()] += 1
    print("ask  req-corps            ans   total  visible20-corps          full-corps                n")
    for key in sorted(agg, key=lambda k: (k[0], k[2], k[1])):
        ac, ab, code = key
        a = agg[key]
        for bh, n in sorted(a["bodies"].items(), key=lambda x: -x[1]):
            body = bytes.fromhex(bh)
            total = ENV + len(body)
            vis = body[:CAP - ENV]
            print("%-4d %-20s %-5d %-6d %-24s %-24s n=%d" %
                  (ac, ab or "-", code, total, vis.hex() or "-", bh or "-", n))


if __name__ == "__main__":
    main()
