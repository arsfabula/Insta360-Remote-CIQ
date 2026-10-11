"""Generate the UCD2 trailer constants for BLEBarrel.mc.

Every frame this widget ever emits is one of two 25 byte FILE commands -
START (code 4) or STOP (code 5) - that differ only in byte 12. The trailer is
the last 4 bytes: checksum(frame[0..20]) from insta360_ucd2, i.e. Insta360's
CRC-32 variant.

Running that CRC on the watch tripped the VM watchdog ("Code Executed Too
Long"), and the first workaround - a 256 entry per-sequence lookup table - was
the Out Of Memory Error on Instinct 3 Solar 45/50mm. Main.onStart calls
`new BLEBarrel.BleDevice()`, which forces the barrel module to load, and
module-scope constants are materialised exactly there (reported as
Main.onStart:23). Two 1024 byte tables were allocated before open() even
started.

So neither. Only byte 7 (seq) and byte 12 (op) of the frame vary, and the CRC
is affine over GF(2), which makes the trailer exactly decomposable:

    trailer(seq, op) = BASE[op] XOR (ucd2SeqXor[j] for each set bit j of seq)

That is 40 bytes of module-scope data instead of 2048, in 8 iterations of
bytewise XOR - cheaper than the CRC loop it replaces.

Verification: tools/verify_tables.py checks the emitted constants against
insta360_ucd2.checksum for all 256 sequences and both ops. tools/test_golden.py
independently pins the resulting frames.

Writes to stdout a Monkey C declaration block, or to argv[1] if given.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import insta360_ucd2 as u

SEQ_BITS = 8


def crc_of(seq, code):
    return u.checksum(bytes(u.build_file_command(seq, code, 1, trailer=False)))


def le(value):
    """CRC as the 4 little-endian bytes that go on the wire."""
    return bytes((value >> (8 * i)) & 0xFF for i in range(4))


def constants():
    zero = crc_of(0, 0)
    base_start = crc_of(0, u.CMD_START_CAPTURE)
    base_stop = crc_of(0, u.CMD_STOP_CAPTURE)
    seq_xor = [crc_of(1 << j, 0) ^ zero for j in range(SEQ_BITS)]
    return le(base_start), le(base_stop), [le(e) for e in seq_xor]


def render():
    start, stop, seq_xor = constants()
    fmt = lambda bs: ", ".join("0x%02x" % b for b in bs)
    rows = "".join("\t\t" + fmt(row) + ",\n" for row in seq_xor)
    return (
        "const ucd2TrailStartBase = [%s]b;\n" % fmt(start)
        + "const ucd2TrailStopBase = [%s]b;\n" % fmt(stop)
        + "const ucd2SeqXor = [\n%s]b;\n" % rows
    )


def selfcheck():
    """Fail loudly here rather than shipping constants that drifted."""
    start, stop, seq_xor = constants()
    for seq in range(256):
        for code, base in ((u.CMD_START_CAPTURE, start),
                           (u.CMD_STOP_CAPTURE, stop)):
            v = bytearray(base)
            for j in range(SEQ_BITS):
                if seq & (1 << j):
                    for i in range(4):
                        v[i] ^= seq_xor[j][i]
            if bytes(v) != bytes(u.build_file_command(seq, code, 1)[-4:]):
                raise SystemExit("decomposition failed at seq=%d code=%d"
                                 % (seq, code))


if __name__ == "__main__":
    selfcheck()
    text = render()
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    else:
        sys.stdout.write(text)