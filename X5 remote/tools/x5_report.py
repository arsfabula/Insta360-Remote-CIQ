#!/usr/bin/env python3
"""Turn an x5_probe.py result into markdown tables.

  x5_report.py PROBE.json [insta360_messages.proto]

The .proto (community, github.com/iliakonnov/insta360-nas) is only used to print names.
"""
import json
import re
import sys


def enum(proto, name):
    m = re.search(r"enum %s \{(.*?)\n\}" % name, proto, re.S)
    out = {}
    if m:
        for k, v in re.findall(r"(\w+) = (\d+);", m.group(1)):
            out[int(v)] = k
    return out


# device-specific values (lens calibration, activation time, sensor timing): shown as a size only
REDACT_OPTIONS = {6, 19, 22, 39, 69, 70, 78, 79, 80, 81}
REDACT_CMDS = {66, 216}


def short(v, n=90):
    s = json.dumps(v, separators=(",", ":"))
    return s if len(s) <= n else s[: n - 1] + "…"


def main():
    res = json.load(open(sys.argv[1]))
    proto = open(sys.argv[2]).read() if len(sys.argv) > 2 else ""
    opt_names = enum(proto, "OptionType")
    opt_names.setdefault(11, "BATTERY_INFO (missing from enum; Options field 11)")
    codes = enum(proto, "MessageCode")
    items = res["items"]

    def status(r):
        st = r.get("status")
        return {None: "no reply", 200: "200 OK", 400: "400", 500: "500", 501: "501"}.get(st, str(st))

    print(f"Camera `{res['camera'][:3]}…` (serial suffix omitted), run {res['started']}, Mac ATT MTU {res.get('mtu')}.\n")
    print("### Read-only commands (empty request body)\n")
    print("| Code | Command | Result | Reply bytes | Fits 20 B | Decoded reply |")
    print("|---:|---|---|---:|:-:|---|")
    for r in items:
        if r["kind"] != "cmd":
            continue
        print(f"| {r['code']} (0x{r['code']:02x}) | {r['name']} | {status(r)} | {r.get('total_len', '')} | "
              f"{'yes' if r.get('fits_ciq') else ('no' if r.get('status') else '')} | "
              f"{('(device-specific, ' + str(r.get('total_len')) + ' B, not published)') if r['code'] in REDACT_CMDS and r.get('reply') else (short(r.get('decoded', '')) if r.get('reply') else '')} |")

    print("\n### GET_OPTIONS, one OptionType at a time\n")
    print("Only options that returned a value are listed. `Fits 20 B` = whole reply ≤ 20 bytes, i.e. readable on Connect IQ.\n")
    print("| # | OptionType | Reply bytes | Fits 20 B | Value (decoded Options field) |")
    print("|---:|---|---:|:-:|---|")
    empty, failed = [], []
    for r in items:
        if r["kind"] != "option":
            continue
        n = int(r["name"].split()[1])
        nm = opt_names.get(n, "?")
        if r.get("status") != 200:
            failed.append(f"{n} {nm} ({status(r)})")
            continue
        dec = r.get("decoded") or []
        val = [x for x in dec if x[0] == 2]
        if not val or val[0][1] in ([], "", None):
            empty.append(f"{n} {nm}")
            continue
        shown = "(device-specific, not published)" if n in REDACT_OPTIONS else short(val[0][1])
        print(f"| {n} | {nm} | {r['total_len']} | {'yes' if r['fits_ciq'] else 'no'} | {shown} |")
    print(f"\nAnswered 200 but empty (not supported on this camera): {', '.join(empty) or 'none'}.\n")
    print(f"Rejected / no reply: {', '.join(failed) or 'none'}.\n")

    print("### Control commands used by the watch app\n")
    print("| Command | Result | Reply bytes | Fits 20 B | Decoded reply |")
    print("|---|---|---:|:-:|---|")
    for r in items:
        if r["kind"] == "control":
            print(f"| {r['name']} | {status(r)} | {r.get('total_len', '')} | {'yes' if r.get('fits_ciq') else 'no'} | {short(r.get('decoded', ''))} |")

    print("\n### Notifications seen during the run\n")
    print("| Code | Name | Bytes | Fits 20 B | Body |")
    print("|---|---|---:|:-:|---|")
    seen = set()
    for n in res["notifications"]:
        key = (n["code"], n["body"])
        if key in seen:
            continue
        seen.add(key)
        nm = codes.get(n["code"], "?").replace("CAMERA_NOTIFICATION_", "")
        print(f"| 0x{n['code']:04x} | {nm} | {n['total_len']} | {'yes' if n['fits_ciq'] else 'no'} | {short(n['decoded'])} |")


if __name__ == "__main__":
    main()
