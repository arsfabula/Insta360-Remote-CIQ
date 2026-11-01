#!/usr/bin/env python3
"""Parse a Garmin Connect IQ .prg (CIQ 3.x/4.x/5.x) and dump its contents.

Focus: protocol reverse-engineering of the Insta360 official app
(apps-developer.garmin.com/apps/18293a9e-d16f-42d7-ab90-73a47510f46e).

Usage:
    python tools/prg_dump.py <file.prg> [--sections] [--head] [--entry] [--classes]
                                   [--strings] [--arrays] [--permissions]
                                   [--out DIR]

Defaults to printing a summary + sections + entry points + head.
"""

import argparse
import os
import struct
import sys

MAGICS = {
    0xd000d000: "Head",
    0xd000d00d: "HeadVersioned",
    0x6060c0de: "EntryPoints",
    0xda7ababe: "Data",
    0xc0debabe: "Code",
    0xc0de7ab1: "CodeTable(PC2Line)",
    0xc1a557b1: "LinkTable",
    0xf00d600d: "Resources",
    0x6000db01: "Permissions",
    0x0ece7105: "Exceptions",
    0x5717b015: "Symbols",
    0xbaada555: "StringResourceSymbols",
    0x5e771465: "Settings",
    0xe1c0de12: "DevSignature",
    0xd011aaa5: "AppUnlock",
    0x00005161: "AppStoreSig",
    0xd0000d1e: "Debug",
    0xfaceda7a: "Complication",
    0xdefeca7e: "BgResource",
    0xd00dface: "GlanceResource",
}

FIELD_TYPE = {
    0: "Null", 1: "Int", 2: "Float", 3: "String", 4: "Object", 5: "Array",
    6: "Method", 7: "Class", 8: "Symbol", 9: "Bool", 10: "Module", 11: "Hash",
    12: "Resource", 13: "PrimitiveObj", 14: "Long", 15: "Double", 16: "WeakPtr",
    17: "PrimitiveMod", 18: "SysPtr", 19: "Char", 20: "ByteArray",
}

APP_TYPE = {0: "WatchFace", 1: "App", 2: "DataField", 3: "Widget",
            4: "Background", 5: "AudioProvider", 6: "Glance"}


def find_inner_prg_start(data):
    """Skip the store wrapper (4 + 29 bytes) and return offset of first section."""
    # The store wraps the PRG: first u4 = size of the rest of the wrapper.
    outer = struct.unpack(">I", data[:4])[0]
    if 0 < outer < 64 and 4 + outer + 4 <= len(data):
        cand = 4 + outer
        v = struct.unpack(">I", data[cand:cand + 4])[0]
        if v in MAGICS:
            return cand
    # fallback: byte-aligned scan
    for off in range(0, 64):
        v = struct.unpack(">I", data[off:off + 4])[0]
        if v in MAGICS:
            return off
    return 0


def parse_sections(data):
    start = find_inner_prg_start(data)
    pos = start
    sections = []
    while pos + 8 <= len(data):
        v = struct.unpack(">I", data[pos:pos + 4])[0]
        if v == 0:
            sections.append((pos, "End", 0, pos, pos + 4))
            break
        if v not in MAGICS:
            # unknown trailing bytes
            sections.append((pos, "Unknown(%#x)" % v, len(data) - pos, pos, len(data)))
            break
        ln = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        sections.append((pos, MAGICS[v], ln, pos + 8, pos + 8 + ln))
        pos += 8 + ln
    return start, sections


def parse_head(content):
    # content = section content bytes
    if not content:
        return {}
    out = {}
    out["header_version"] = content[0]
    if len(content) >= 4:
        out["ciq_version"] = "%d.%d.%d" % (content[1], content[2], content[3])
    i = 4
    # optional background offsets
    if i + 8 <= len(content):
        out["m_data_offset"] = struct.unpack(">I", content[i:i + 4])[0]
        out["m_code_offset"] = struct.unpack(">I", content[i + 4:i + 8])[0]
        i += 8
    if i < len(content):
        out["app_lock_indicator"] = content[i]
        out["app_lock"] = content[i] != 0
        i += 1
    if i + 4 <= len(content):
        out["unused1"] = struct.unpack(">I", content[i:i + 4])[0]
        i += 4
    if i + 4 <= len(content):
        out["unused2"] = struct.unpack(">I", content[i:i + 4])[0]
        i += 4
    if i + 8 <= len(content):
        out["glance_data_offset"] = struct.unpack(">I", content[i:i + 4])[0]
        out["glance_code_offset"] = struct.unpack(">I", content[i + 4:i + 8])[0]
        i += 8
    if i + 4 <= len(content):
        out["flags"] = struct.unpack(">I", content[i:i + 4])[0]
        i += 4
    return out


def parse_string_def(content, off):
    """Return (string, new_offset) or (None, off)."""
    if off >= len(content) or content[off] != 0x01:
        return None, off
    if off + 3 > len(content):
        return None, off
    slen = struct.unpack(">H", content[off + 1:off + 3])[0]
    # data size is length+1 (trailing null)
    data_size = slen + 1
    end = off + 3 + data_size
    if end > len(content):
        return None, off
    raw = content[off + 3:off + 3 + data_size]
    s = raw.split(b"\x00", 1)[0].decode("utf-8", "replace")
    return s, end


def parse_class_def(content, off):
    """Parse one class_def starting at sentinel (0xc1/0xc2). Return (dict, new_off)."""
    if off >= len(content) or content[off] not in (0xc1, 0xc2):
        return None, off
    is_v2 = content[off] == 0xc2
    pos = off + 1  # consume sentinel
    # sentinel_fragment 3 bytes
    pos += 3
    flags = 0
    if is_v2:
        flags = content[pos]
        pos += 1
    extends_offset = None
    extended_offsets = None
    statics_entry = None
    static_entry = None
    parent_module_id = None
    module_id = None
    if not is_v2:
        extends_offset = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
        statics_entry = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
    else:
        if flags & 1:
            extended_offsets = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
        if flags & 2:
            static_entry = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
    if (not is_v2) or (flags & 4):
        parent_module_id = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
    if (not is_v2) or (flags & 8):
        module_id = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
    app_types = struct.unpack(">H", content[pos:pos + 2])[0]; pos += 2
    if not is_v2:
        nfields = content[pos]; pos += 1
    else:
        nfields = struct.unpack(">H", content[pos:pos + 2])[0]; pos += 2
    field_size = 9 if is_v2 else 8
    fields = []
    for _ in range(nfields):
        if pos + field_size > len(content):
            break
        if is_v2:
            code_offset = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
            type_raw = content[pos]; pos += 1
            field_value = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
            ftype = type_raw
        else:
            code_offset = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
            field_value = struct.unpack(">I", content[pos:pos + 4])[0]; pos += 4
            ftype = code_offset & 0x0F
        symbol = (code_offset >> 8) & 0x00FFFFFF
        flags_f = (code_offset >> 4) & 0x0F
        section_loc = field_value & 0xF0000000
        fields.append({
            "symbol": symbol,
            "flags": flags_f,
            "type": ftype,
            "type_name": FIELD_TYPE.get(ftype, "?%d" % ftype),
            "value": field_value,
            "section_loc": section_loc,
        })
    return {
        "is_v2": is_v2,
        "flags": flags,
        "extends_offset": extends_offset,
        "extended_offsets": extended_offsets,
        "statics_entry": statics_entry,
        "static_entry": static_entry,
        "parent_module_id": parent_module_id,
        "module_id": module_id,
        "app_types": app_types,
        "permission_required": (app_types & 0x8000) != 0,
        "actual_app_types": (app_types & 0xFFFF7FFF) & 0xFFFF,
        "nfields": nfields,
        "fields": fields,
    }, pos


def parse_data_section(content):
    """Walk data_entry list. Return (strings dict offset->str, classes list, arrays list, containers)."""
    strings = {}   # offset of string_def start -> str
    classes = []
    arrays = []    # list of (field dict, bytes)
    containers = []
    pos = 0
    # collect string offsets first pass
    # We'll walk and record
    entries = []
    pos = 0
    while pos < len(content):
        # skip padding
        if content[pos] == 0x00:
            pos += 1
            continue
        sent = content[pos]
        if sent == 0x01:
            s, npos = parse_string_def(content, pos)
            if s is None:
                # bail
                break
            strings[pos] = s
            entries.append(("string", pos, npos, s))
            pos = npos
        elif sent == 0x03:
            if pos + 5 > len(content):
                break
            ln = struct.unpack(">I", content[pos + 1:pos + 5])[0]
            end = pos + 5 + ln
            if end > len(content):
                break
            containers.append((pos, content[pos + 5:end]))
            entries.append(("container", pos, end, ln))
            pos = end
        elif sent in (0xc1, 0xc2):
            cls, npos = parse_class_def(content, pos)
            if cls is None:
                break
            classes.append((pos, cls))
            entries.append(("class", pos, npos, cls))
            pos = npos
        else:
            # unknown sentinel -> stop
            entries.append(("stop", pos, pos, "sentinel=%#x" % sent))
            break
    return strings, classes, arrays, containers, entries


def dump_byte_array(content, field):
    """Given a field with type Array/ByteArray and value offset, extract bytes."""
    off = field["value"]
    if off >= len(content):
        return None
    # If it points at a string_def (0x01 sentinel), treat payload as bytes
    if content[off] == 0x01:
        s, npos = parse_string_def(content, off)
        if s is not None:
            # raw bytes = content[off+3 : npos] (length+1 sized), strip trailing null
            raw = content[off + 3:npos]
            if raw.endswith(b"\x00"):
                raw = raw[:-1]
            return raw
    # Otherwise: try length-prefixed u2
    if off + 2 <= len(content):
        ln = struct.unpack(">H", content[off:off + 2])[0]
        if 0 < ln <= len(content) - off - 2:
            return content[off + 2:off + 2 + ln]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("--sections", action="store_true", default=True)
    ap.add_argument("--no-sections", dest="sections", action="store_false")
    ap.add_argument("--head", action="store_true", default=True)
    ap.add_argument("--entry", action="store_true", default=True)
    ap.add_argument("--classes", action="store_true")
    ap.add_argument("--strings", action="store_true")
    ap.add_argument("--arrays", action="store_true")
    ap.add_argument("--permissions", action="store_true")
    ap.add_argument("--containers", action="store_true")
    ap.add_argument("--grep", help="filter strings/classes by substring")
    ap.add_argument("--proto", action="store_true", help="print protobuf message-name strings only")
    ap.add_argument("--out", help="write dumps to directory")
    args = ap.parse_args()
    if args.proto:
        args.strings = True

    data = open(args.prg, "rb").read()
    start, sections = parse_sections(data)

    print("=== %s (%d bytes) ===" % (args.prg, len(data)))
    print("inner PRG start offset: %#x" % start)

    if args.sections:
        print("\n--- sections ---")
        for off, name, ln, cs, ce in sections:
            print("  %#08x  %-22s len=%d" % (off, name, ln))

    # head
    head_sec = [s for s in sections if s[1].startswith("Head")]
    if args.head and head_sec:
        off, name, ln, cs, ce = head_sec[0]
        print("\n--- head (%s) ---" % name)
        h = parse_head(data[cs:ce])
        for k, v in h.items():
            print("  %s: %s" % (k, v))

    # entry points
    ep_sec = [s for s in sections if s[1] == "EntryPoints"]
    if args.entry and ep_sec:
        off, name, ln, cs, ce = ep_sec[0]
        content = data[cs:ce]
        n = struct.unpack(">H", content[0:2])[0]
        print("\n--- entry points (n=%d) ---" % n)
        for i in range(n):
            base = 2 + i * 36
            chunk = content[base:base + 36]
            if len(chunk) < 36:
                break
            uuid = chunk[0:16].hex()
            uuid_fmt = "%s-%s-%s-%s-%s" % (uuid[0:8], uuid[8:12], uuid[12:16], uuid[16:20], uuid[20:32])
            module_id = struct.unpack(">I", chunk[16:20])[0]
            class_id = struct.unpack(">I", chunk[20:24])[0]
            label_id = struct.unpack(">I", chunk[24:28])[0]
            icon = struct.unpack(">I", chunk[28:32])[0]
            apptype = struct.unpack(">I", chunk[32:36])[0]
            print("  entry %d: uuid=%s type=%s(%d) module=%d class=%d label=%d icon=%#x" % (
                i, uuid_fmt, APP_TYPE.get(apptype, "?"), apptype, module_id, class_id, label_id, icon))

    # permissions
    perm_sec = [s for s in sections if s[1] == "Permissions"]
    if args.permissions and perm_sec:
        off, name, ln, cs, ce = perm_sec[0]
        content = data[cs:ce]
        n = struct.unpack(">H", content[0:2])[0]
        print("\n--- permissions (n=%d) ---" % n)
        for i in range(n):
            pid = struct.unpack(">I", content[2 + i * 4:2 + (i + 1) * 4])[0]
            print("  %#08x" % pid)

    # data section
    data_sec = [s for s in sections if s[1] == "Data"]
    if data_sec:
        off, name, ln, cs, ce = data_sec[0]
        content = data[cs:ce]
        strings, classes, arrays, containers, entries = parse_data_section(content)

        if args.classes:
            print("\n--- data: %d class defs ---" % len(classes))
            for offc, cls in classes:
                print("  @data+%#x  v%d parent_module=%s module=%s app_types=%#x nfields=%d" % (
                    offc, 2 if cls["is_v2"] else 1, cls["parent_module_id"], cls["module_id"],
                    cls["app_types"], cls["nfields"]))
                for f in cls["fields"]:
                    print("      sym=%-7d %-12s flags=%d value=%#x" % (
                        f["symbol"], f["type_name"], f["flags"], f["value"]))

        if args.strings:
            items = sorted(strings.items())
            if args.grep:
                items = [(o, s) for o, s in items if args.grep.lower() in s.lower()]
            if args.proto:
                items = [(o, s) for o, s in items if "{" in s or "Resp" in s or "Req" in s]
            print("\n--- data: %d strings ---" % len(items))
            for off_s, s in items:
                print("  @data+%#x  %r" % (off_s, s))

        if args.containers:
            print("\n--- data: %d containers ---" % len(containers))
            for off_c, raw in containers:
                runs = []
                cur = bytearray()
                for byte in raw:
                    if 32 <= byte < 127:
                        cur.append(byte)
                    else:
                        if len(cur) >= 4:
                            runs.append(cur.decode("ascii"))
                        cur = bytearray()
                if len(cur) >= 4:
                    runs.append(cur.decode("ascii"))
                print("  @data+%#x  len=%d  strings=%s" % (off_c, len(raw), runs))

        if args.arrays:
            print("\n--- data: byte arrays (from ByteArray/Array fields) ---")
            cnt = 0
            for offc, cls in classes:
                for f in cls["fields"]:
                    if f["type_name"] in ("ByteArray", "Array", "Resource"):
                        raw = dump_byte_array(content, f)
                        if raw is None:
                            continue
                        cnt += 1
                        print("  class@%#x field sym=%d type=%s value=%#x len=%d" % (
                            offc, f["symbol"], f["type_name"], f["value"], len(raw)))
                        print("     hex: %s" % raw[:64].hex(" "))
                        try:
                            txt = raw.split(b"\x00", 1)[0].decode("utf-8")
                            if len(txt) > 4 and all(32 <= ord(c) < 127 for c in txt):
                                print("     str: %r" % txt)
                        except Exception:
                            pass
            print("  total arrays dumped: %d" % cnt)

        # save dumps if --out
        if args.out:
            os.makedirs(args.out, exist_ok=True)
            with open(os.path.join(args.out, "strings.txt"), "w") as fh:
                for off_s, s in sorted(strings.items()):
                    fh.write("%#x\t%s\n" % (off_s, s))
            with open(os.path.join(args.out, "classes.txt"), "w") as fh:
                for offc, cls in classes:
                    fh.write("=== class @%#x (v%d) parent=%s module=%s app_types=%#x ===\n" % (
                        offc, 2 if cls["is_v2"] else 1, cls["parent_module_id"], cls["module_id"], cls["app_types"]))
                    for f in cls["fields"]:
                        fh.write("  sym=%-7d %-12s flags=%d value=%#x\n" % (
                            f["symbol"], f["type_name"], f["flags"], f["value"]))
            with open(os.path.join(args.out, "containers.txt"), "w") as fh:
                for off_c, raw in containers:
                    fh.write("@%#x\tlen=%d\t%s\n" % (off_c, len(raw), raw.hex()))
            print("\nwrote %s/{strings,classes,containers}.txt" % args.out)

    # containers (JSON) summary
    if data_sec and containers:
        print("\n--- data: %d containers ---" % len(containers))
        for off_c, raw in containers[:5]:
            print("  @data+%#x  len=%d  head=%s" % (off_c, len(raw), raw[:40]))

    # store prg metadata
    print("\n=== summary ===")
    print("  sections: %d" % len(sections))
    print("  inner start: %#x" % start)


if __name__ == "__main__":
    main()
