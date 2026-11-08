"""protobuf message schemas of a CIQ .prg, one line per message class.

How it works (the prg ships no protobuf descriptor, only P-code):
  * every message class has an `initialize()` (api symbol 8388702) that builds
    the field table: `ipush1 <numero>` then `apush <offset Data>` for the type
    descriptor container, so field number -> type is literal in the code;
  * the same class has a `print()` (symbol 8388712) that `news` the string
    "ClassName {" and one "     <field>: " per field, in the same order the
    fields were declared in the .proto;
  * zipping the two gives: field number, field name, type.
Descriptor containers carry the type name (int32/int64/bool/string/embedded/
enum/uint32/uint64) as a string_def in the Data section.

Usage:
    python tools/prg_schemas.py <file.prg> [--name Filtr] [--json out.json]
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prg_analyze import Prg, load_api_db, DESCRIPTOR_METHOD, NAME_METHOD  # noqa: E402

API_DB = os.path.expanduser("~/connectiq_sdk/bin/api.db")


def type_of(p, off):
    """descriptor container at Data offset `off` -> readable type."""
    raw = p.cmap.get(off)
    if raw is None:
        return "?"
    txt = "".join(chr(c) if 32 <= c < 127 else " " for c in raw)
    for cand in ("uint64", "uint32", "int64", "int32", "bool", "string", "bytes", "embedded", "enum", "float", "double"):
        if re.search(r"\b%s\b" % cand, txt):
            return cand
    return "msg@" + hex(off)


def main():
    path = sys.argv[1]
    filt = None
    asjson = None
    args = sys.argv[2:]
    while args:
        a = args.pop(0)
        if a == "--name":
            filt = args.pop(0)
        elif a == "--json":
            asjson = args.pop(0)
    p = Prg(path)
    p.api = load_api_db(API_DB if os.path.exists(API_DB) else
                       "/home/greg/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b/bin/api.db")
    p.cmap = {off: raw for off, raw in p.containers}
    out = []
    for off, cls in sorted(p.classes.items()):
        meths = p.methods_by_class.get(off, [])
        init = next((pc for sym, _f, pc in meths if sym == DESCRIPTOR_METHOD), None)
        prn = next((pc for sym, _f, pc in meths if sym == NAME_METHOD), None)
        if init is None:
            continue
        body = list(p.disasm(init))
        fields = []
        num = None
        for _q, mn, arg, _ann in body:
            if mn in ("ipush1", "ipush2", "ipush") and isinstance(arg, int) and 0 < arg < 4096:
                num = arg
            elif mn == "apush" and isinstance(arg, int) and num is not None:
                fields.append([num, None, type_of(p, arg)])
                num = None
        name = None
        names = []
        if prn is not None:
            for _q, mn, arg, _ann in p.disasm(prn):
                if mn == "news":
                    s = p.strings.get(arg, "")
                    if s.endswith(" {") and name is None:
                        name = s[:-2]
                    elif s.strip().endswith(":") and s.startswith(" "):
                        names.append(s.strip()[:-1])
        if name is None:
            name = "<class@%#x>" % off
        if filt and filt.lower() not in name.lower():
            continue
        for i, f in enumerate(fields):
            if i < len(names):
                f[1] = names[i]
        out.append(dict(cls_hex="%x" % off, name=name, parent_module=cls.get("parent_module_id"),
                        fields=fields))
    for m in sorted(out, key=lambda m: m["name"]):
        print("%-42s @data+0x%-6s (%d champs)" % (m["name"], m["cls_hex"], len(m["fields"])))
        for num, fname, t in m["fields"]:
            print("    %-3s %-26s %s" % (num, fname or "?", t))
    if asjson:
        json.dump(out, open(asjson, "w"), indent=1)
        print("\nwrote %s (%d messages)" % (asjson, len(out)))
    print("\n%d message classes" % len(out))


if __name__ == "__main__":
    main()
