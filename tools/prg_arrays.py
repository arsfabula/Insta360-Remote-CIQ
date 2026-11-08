"""Decode the integer constant arrays of a distributed .prg Data section, and show
every `apush <tableau>` call site with the list it carries.

The Data section is a stream of typed entries. The entry that holds an integer
array was decoded as (verified against the option lists used by GET_OPTIONS):

    03 <u32BE len>                     len = 8 + len2
      da 7a da 7a <u32BE len2>         len2 = 5 + 5*count
        <u8 type = 05> <u32BE count>
        count * ( <u8 subtype = 01> <u32BE value> )

The operand of `apush N` is the offset of the entry inside the Data section, so
the table printed for `apush 39806` is the one at data+0x9b7e.

Read together with the request builders (see prg_cmd_payloads.py) this answers
"which option ids does the app ask for", which the code alone does not: the
lists are data, not code.

Usage: python tools/prg_arrays.py <file.prg> [--callsites]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_analyze import Prg, load_api_db  # noqa: E402

API_DB = os.path.expanduser("~/connectiq_sdk/bin/api.db")
SDK_DB = "/home/greg/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262/bin/api.db"


def decode_array(data, i):
    """Return the value list of the array entry starting at data[i], or None."""
    if i + 23 > len(data) or data[i] != 0x03 or data[i + 5:i + 9] != b"\xda\x7a\xda\x7a":
        return None
    ln = struct.unpack_from(">I", data, i + 1)[0]
    ln2 = struct.unpack_from(">I", data, i + 9)[0]
    if ln != 8 + ln2 or data[i + 13] != 0x05:
        return None
    cnt = struct.unpack_from(">I", data, i + 14)[0]
    if ln2 != 5 + 5 * cnt or i + 5 + ln > len(data):
        return None
    vals = []
    for k in range(cnt):
        o = i + 18 + 5 * k
        if data[o] != 0x01:
            return None
        vals.append(struct.unpack_from(">I", data, o + 1)[0])
    return vals


def main():
    p = Prg(sys.argv[1])
    p.api = load_api_db(API_DB if os.path.exists(API_DB) else SDK_DB)
    want_sites = "--callsites" in sys.argv[2:]

    arrays = {}
    for i in range(len(p.data) - 23):
        v = decode_array(p.data, i)
        if v is not None:
            arrays[i] = v
    print("=== %d integer constant arrays in the Data section ===" % len(arrays))
    for off in sorted(arrays):
        print("  apush %-6d (data+%#06x)  n=%-3d %s" % (off, off, len(arrays[off]), arrays[off]))

    if not want_sites:
        return
    print("\n=== `apush <table>` call sites: options asked, method called, callback ===")
    n = 0
    for cls_off, ms in p.methods_by_class.items():
        for sym, _flags, pc in sorted(ms, key=lambda t: t[2]):
            for q, mn, arg, _ann in p.disasm(pc):
                if mn != "apush" or arg not in arrays:
                    continue
                vals = arrays[arg]
                body = list(p.disasm(q))[1:12]
                anns = [a for _q2, _m2, _a2, a in body]
                callees = [a.split("(Method=0x")[1].split(")")[0]
                           for m2, a in zip([b[1] for b in body], anns)
                           if m2 == "getsv" and "(Method=0x" in a]
                print("  code+%#06x  class @data+%#05x  meth %s(%s)  apush %d -> %s"
                      % (q, cls_off, p.api.get(sym, str(sym)), sym, arg, vals))
                print("        called (code+): %s" % (callees[:2] or "-"))
                n += 1
    print("\n%d sites resolved" % n)


if __name__ == "__main__":
    main()
