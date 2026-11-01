#!/usr/bin/env python3
"""Disassemble the P-code (Code section) of a Garmin Connect IQ .prg.

Produces a readable listing with annotations:
  - spush immediates resolved against the Data-section string pool
  - method entry points (from class-def Method fields) marked
  - relative branch targets computed

Usage:
    python tools/prg_disasm.py <file.prg> [--out DIR] [--functions-only]

This is a static aid for protocol reverse-engineering (step 2). It does NOT
decompile to C; pair it with Ghidra + GhidraGarminApp for full decompilation.
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prg_dump

# opcode -> (mnemonic, total instruction size in bytes, arg format)
# arg format: None, 'u1','u2','u3','u4','u8','u1u4','u4u4','u2rel'
OPCODES = {
    0x00: ("nop", 1, None),
    0x01: ("incsp", 2, "u1"),
    0x02: ("popv", 1, None),
    0x03: ("addv", 1, None),
    0x04: ("subv", 1, None),
    0x05: ("mulv", 1, None),
    0x06: ("divv", 1, None),
    0x07: ("andv", 1, None),
    0x08: ("orv", 1, None),
    0x09: ("modv", 1, None),
    0x0a: ("shlv", 2, "u1"),
    0x0b: ("shrv", 2, "u1"),
    0x0c: ("xorv", 1, None),
    0x0d: ("getv", 1, None),
    0x0e: ("putv", 1, None),
    0x0f: ("invoke", 2, "u1"),
    0x10: ("agetv", 1, None),
    0x11: ("aputv", 2, "u1"),
    0x12: ("lgetv", 2, "u1"),
    0x13: ("lputv", 2, "u1"),
    0x14: ("newa", 1, None),
    0x15: ("newc", 1, None),
    0x16: ("return", 1, None),
    0x17: ("ret", 1, None),
    0x18: ("news", 5, "u4"),
    0x19: ("goto", 3, "u2rel"),
    0x1a: ("eq", 1, None),
    0x1b: ("lt", 1, None),
    0x1c: ("lte", 1, None),
    0x1d: ("gt", 1, None),
    0x1e: ("gte", 1, None),
    0x1f: ("ne", 1, None),
    0x20: ("isnull", 1, None),
    0x21: ("isa", 1, None),
    0x22: ("canhazplz", 1, None),
    0x23: ("jsr", 3, "u2rel"),
    0x24: ("ts", 1, None),
    0x25: ("ipush", 5, "u4"),
    0x26: ("fpush", 5, "u4"),
    0x27: ("spush", 5, "u4"),
    0x28: ("bt", 3, "u2rel"),
    0x29: ("bf", 3, "u2rel"),
    0x2a: ("frpush", 1, None),
    0x2b: ("bpush", 2, "u1"),
    0x2c: ("npush", 1, None),
    0x2d: ("invv", 1, None),
    0x2e: ("dup", 2, "u1"),
    0x2f: ("newd", 1, None),
    0x30: ("getm", 1, None),
    0x31: ("lpush", 9, "u8"),
    0x32: ("dpush", 9, "u8"),
    0x33: ("throw", 1, None),
    0x34: ("cpush", 5, "u4"),
    0x35: ("argc", 2, "u1"),
    0x36: ("newba", 1, None),
    0x37: ("ipushz", 1, None),
    0x38: ("ipush1", 2, "u1"),
    0x39: ("ipush2", 3, "u2"),
    0x3a: ("ipush3", 4, "u3"),
    0x3b: ("fpushz", 1, None),
    0x3c: ("lpushz", 1, None),
    0x3d: ("dpushz", 1, None),
    0x3e: ("btpush", 1, None),
    0x3f: ("bfpush", 1, None),
    0x40: ("apush", 5, "u4"),
    0x41: ("bapush", 5, "u4"),
    0x42: ("hpush", 5, "u4"),
    0x43: ("getselfv", 5, "u4"),
    0x44: ("getself", 1, None),
    0x45: ("getmv", 9, "u4u4"),
    0x46: ("getlocalv", 6, "u1u4"),
    0x47: ("getsv", 5, "u4"),
    0x48: ("invokemz", 1, None),
    0x49: ("aputvdup", 1, None),
    0x4a: ("argcincsp", 3, "u2"),
    0x4b: ("isnotnull", 1, None),
    0x4c: ("lgoto", 5, "u4"),
}


def parse_args_bytes(code, pc, fmt):
    if fmt is None:
        return "", 0
    if fmt == "u1":
        return " %d" % code[pc], 1
    if fmt == "u2":
        return " %d" % struct.unpack(">H", code[pc:pc + 2])[0], 2
    if fmt == "u3":
        return " %d" % int.from_bytes(code[pc:pc + 3], "big"), 3
    if fmt == "u4":
        return " %d" % struct.unpack(">I", code[pc:pc + 4])[0], 4
    if fmt == "u8":
        return " %d" % struct.unpack(">Q", code[pc:pc + 8])[0], 8
    if fmt == "u1u4":
        u1 = code[pc]
        u4 = struct.unpack(">I", code[pc + 1:pc + 5])[0]
        return " %d %d" % (u1, u4), 5
    if fmt == "u4u4":
        u4a = struct.unpack(">I", code[pc:pc + 4])[0]
        u4b = struct.unpack(">I", code[pc + 4:pc + 8])[0]
        return " %d %d" % (u4a, u4b), 8
    if fmt == "u2rel":
        v = struct.unpack(">H", code[pc:pc + 2])[0]
        target = pc + 2 + v  # relative to end of instruction? adjust below
        return " %d (->%d)" % (v, target), 2
    return " ?", 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("--out", default=None)
    ap.add_argument("--functions-only", action="store_true")
    args = ap.parse_args()

    data = open(args.prg, "rb").read()
    start, sections = prg_dump.parse_sections(data)

    # find Data and Code sections
    data_sec = [s for s in sections if s[1] == "Data"][0]
    code_sec = [s for s in sections if s[1] == "Code"][0]
    dstart, dname, dln, dcs, dce = data_sec
    cstart, cname, cln, ccs, cce = code_sec
    content = data[dcs:dce]
    code = data[ccs:cce]

    # parse data section
    strings, classes, arrays, containers, entries = prg_dump.parse_data_section(content)

    # string pool: offset -> str (already in `strings`)
    # method map: code_offset -> (class_off, symbol, flags)
    methods = {}
    for offc, cls in classes:
        for f in cls["fields"]:
            if f["type_name"] == "Method":
                code_off = f["value"] & 0x0FFFFFFF
                methods[code_off] = (offc, f["symbol"], f["flags"], f["value"])

    # sort method offsets
    method_offsets = sorted(methods.keys())

    def method_at(pc):
        # find the method whose range contains pc
        # methods are not necessarily contiguous; use nearest preceding method offset
        cand = None
        for mo in method_offsets:
            if mo <= pc:
                cand = mo
            else:
                break
        if cand is None:
            return None
        # heuristic: method spans until next method offset or end
        idx = method_offsets.index(cand)
        nxt = method_offsets[idx + 1] if idx + 1 < len(method_offsets) else len(code)
        if pc < nxt:
            return cand, methods[cand]
        return None

    out_dir = args.out
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    lines = []
    lines.append("=== disassembly of %s (code section %#x..%#x, %d bytes) ===" % (
        args.prg, ccs, cce, len(code)))
    lines.append("methods found in data section: %d" % len(methods))
    lines.append("")

    # write method map
    if out_dir:
        with open(os.path.join(out_dir, "methods.txt"), "w") as fh:
            fh.write("# code_offset  class_off  symbol  flags\n")
            for mo in method_offsets:
                co, sym, fl, raw = methods[mo]
                fh.write("%#x  %#x  %d  %d  (raw=%#x)\n" % (mo, co, sym, fl, raw))

    pc = 0
    n_instr = 0
    unknown = 0
    while pc < len(code):
        # mark method entry
        m = method_at(pc)
        if m is not None and m[0] == pc:
            co, sym, fl, raw = m[1]
            lines.append("")
            lines.append("### METHOD entry @code+%#x  (data class %#x, symbol %d, flags %d)" % (
                pc, co, sym, fl))

        op = code[pc]
        if op not in OPCODES:
            lines.append("%05x:  %02x  <UNKNOWN OPCODE>" % (pc, op))
            pc += 1
            unknown += 1
            continue
        mnem, size, fmt = OPCODES[op]
        if pc + size > len(code):
            lines.append("%05x:  %02x  <TRUNCATED>" % (pc, op))
            break
        argstr, arglen = parse_args_bytes(code, pc + 1, fmt)
        # verify arglen == size-1
        # annotations
        annot = ""
        if op == 0x27:  # spush: resolve string
            val = struct.unpack(">I", code[pc + 1:pc + 5])[0]
            # try direct string pool lookup
            if val in strings:
                annot = "  ; str: %r" % strings[val]
            else:
                # try parse string_def at val
                s, _ = prg_dump.parse_string_def(content, val)
                if s is not None:
                    annot = "  ; str: %r" % s
        if op in (0x19, 0x23, 0x28, 0x29):  # branches: fix relative target
            # recompute: target = pc + size + signed? Kaitai says u2; assume relative to pc+size
            v = struct.unpack(">H", code[pc + 1:pc + 3])[0]
            target = pc + size + v
            argstr = " %d (->code+%#x)" % (v, target)
        if op == 0x4c:  # lgoto: u4
            v = struct.unpack(">I", code[pc + 1:pc + 5])[0]
            target = pc + size + v
            argstr = " %d (->code+%#x)" % (v, target)

        lines.append("%05x:  %02x %-10s%s%s" % (pc, op, mnem, argstr, annot))
        pc += size
        n_instr += 1

    lines.append("")
    lines.append("=== stats: %d instructions, %d unknown opcodes ===" % (n_instr, unknown))

    text = "\n".join(lines)
    if args.functions_only:
        # print only method entries + a few lines
        out_lines = [l for l in lines if l.startswith("###") or l.startswith("===")]
        text = "\n".join(out_lines)

    if out_dir:
        with open(os.path.join(out_dir, "disasm.txt"), "w") as fh:
            fh.write("\n".join(lines))
        print("wrote %s/disasm.txt" % out_dir)
        print("methods: %d, instructions: %d, unknown: %d" % (len(methods), n_instr, unknown))
    else:
        print(text)


if __name__ == "__main__":
    main()
