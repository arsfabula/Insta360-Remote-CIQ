#!/usr/bin/env python3
"""Reassemble Insta360 TCP:6666 control frames from a tshark TSV export.

Input lines: time \t src_ip \t tcp_seq_raw \t payload_hex  (tcp.len>0 only)
Frame: [u32 LE total_len incl. itself][type][...]; type 0x04 = message:
  [04 00 00][code u16 LE][02][seq u24 LE][flags][00 00][protobuf body]
Usage: insta_frames.py <tsv> <phone_ip> [--all]
"""
import sys
from collections import defaultdict

tsv, phone = sys.argv[1], sys.argv[2]
show_all = "--all" in sys.argv
streams = defaultdict(dict)  # dir -> seq -> (time, bytes)
for line in open(tsv):
    p = line.rstrip("\n").split("\t")
    if len(p) < 4 or not p[3]:
        continue
    d = "->cam" if p[1] == phone else "<-cam"
    streams[d].setdefault(int(p[2]), (float(p[0]), bytes.fromhex(p[3].replace(":", ""))))

for d in ("->cam", "<-cam"):
    segs = sorted(streams[d].items())
    buf = b""; times = []
    nxt = None
    for seq, (t, data) in segs:
        if nxt is not None and seq < nxt:  # retransmission overlap
            data = data[nxt - seq:] if seq + len(data) > nxt else b""
            seq = nxt
        buf += data; times.append((len(buf), t)); nxt = seq + len(data) if data else nxt
    off = 0
    while off + 4 <= len(buf):
        n = int.from_bytes(buf[off:off+4], "little")
        if n < 7 or off + n > len(buf):
            break
        fr = buf[off:off+n]
        t = next(tt for end, tt in times if end >= off + 1)
        typ = fr[4]
        if typ == 0x04 and n >= 16:
            code = fr[7] | fr[8] << 8
            seqn = fr[10] | fr[11] << 8 | fr[12] << 16
            body = fr[16:]
            if show_all or d == "->cam" or code not in (0x2010,):
                print("%9.3f %s code=0x%04x seq=%-8d len=%-4d %s" % (t, d, code, seqn, len(body), body[:60].hex(" ")))
        elif show_all and typ != 0x05:
            print("%9.3f %s type=0x%02x %s" % (t, d, typ, fr[4:40].hex(" ")))
        off += n
