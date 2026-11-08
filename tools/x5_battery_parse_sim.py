#!/usr/bin/env python3
# Regression replay of the BLEBarrel battery parsers (x5Varint,
# x5ParseVarintField, x5ParseBatteryField, x5ParseOptionsBattery,
# x5ParseOptionBlockBattery) on the frames really captured from the X5
# (fw v1.13.21, serial IAHEA2503S6GEW) on 2026-11-04, artefacts
# ble-20261104-105458* / ble-20261104-110441*. The transcriptions follow the
# Monkey C line by line, including the quirks: x5Varint returns null past a
# 28-bit shift, and the battery parsers refuse an incomplete block instead of
# guessing a value from bytes cut at the MTU ceiling.
#
# See PROTOCOL_APK.md section 14 for the protocol reading of these frames.

x5_varint_end = [0]


def x5_varint(buf, i, n):
    value = 0
    shift = 0
    while i < n:
        o = buf[i] & 0xff
        value += (o & 0x7f) << shift
        i += 1
        if (o & 0x80) == 0:
            x5_varint_end[0] = i
            return value
        shift += 7
        if shift > 28:
            x5_varint_end[0] = i
            return None
    x5_varint_end[0] = n
    return None


def x5_parse_varint_field(buf, start, end, field):
    i = start
    while i < end:
        tag = x5_varint(buf, i, end)
        if tag is None:
            return None
        i = x5_varint_end[0]
        if (tag & 7) != 0:
            return None
        v = x5_varint(buf, i, end)
        if v is None:
            return None
        i = x5_varint_end[0]
        if (tag >> 3) == field:
            return v
    return None


def x5_parse_battery_field(buf, field):
    n = len(buf)
    if n <= 16:
        return None
    i = 16
    while i < n:
        tag = x5_varint(buf, i, n)
        if tag is None:
            return None
        i = x5_varint_end[0]
        wire = tag & 7
        if wire == 0:
            v = x5_varint(buf, i, n)
            if v is None:
                return None
            i = x5_varint_end[0]
            if (tag >> 3) == field:
                return v
            continue
        if wire != 2:
            return None
        ln = x5_varint(buf, i, n)
        if ln is None:
            return None
        i = x5_varint_end[0]
        if (tag >> 3) == 1:
            # the watch ceiling cuts the nested block mid-body: scan only the
            # octets that crossed
            stop = min(i + ln, n)
            if stop <= i:
                return None
            return x5_parse_varint_field(buf, i, stop, field)
        if i + ln > n:
            return None
        i += ln
    return None


def x5_parse_option_block_battery(buf, frm, to):
    i = frm
    while i < to:
        tag = x5_varint(buf, i, to)
        if tag is None:
            return None
        i = x5_varint_end[0]
        wire = tag & 7
        if wire == 0:
            v = x5_varint(buf, i, to)
            if v is None:
                return None
            i = x5_varint_end[0]
            continue
        if wire != 2:
            return None
        ln = x5_varint(buf, i, to)
        if ln is None:
            return None
        i = x5_varint_end[0]
        if i + ln > to:
            return None
        if (tag >> 3) == 11:
            return x5_parse_varint_field(buf, i, i + ln, 2)
        i += ln
    return None


def x5_parse_options_battery(buf):
    n = len(buf)
    if n <= 16:
        return None
    i = 16
    while i < n:
        tag = x5_varint(buf, i, n)
        if tag is None:
            return None
        i = x5_varint_end[0]
        wire = tag & 7
        if wire == 0:
            v = x5_varint(buf, i, n)
            if v is None:
                return None
            i = x5_varint_end[0]
            continue
        if wire != 2:
            return None
        ln = x5_varint(buf, i, n)
        if ln is None:
            return None
        i = x5_varint_end[0]
        if i + ln > n:
            return None
        if (tag >> 3) == 2:
            level = x5_parse_option_block_battery(buf, i, i + ln)
            if level is not None:
                return level
        i += ln
    return None


def main():
    # 0x2003 push, whole 24 octets, charger IN then charger OUT, both levels 57
    push_in = bytes.fromhex("18000000040000032002ff8a43f400000a06080110392000")
    push_out = bytes.fromhex("18000000040000032002ff8a43f400000a06080010392000")
    assert len(push_in) == 24 and len(push_out) == 24
    assert (push_in[7] | (push_in[8] << 8)) == 0x2003
    assert x5_parse_battery_field(push_in, 1) == 1
    assert x5_parse_battery_field(push_in, 2) == 57
    assert x5_parse_battery_field(push_out, 1) == 0
    assert x5_parse_battery_field(push_out, 2) == 57

    # the same push cut at the watch ceiling (measured 2026-11-04 on the watch:
    # declared 24, arrived 20, no continuation): the power type sits at the
    # twentieth octet and reads true off the fragment, the level sits past the
    # cut and stays unreported
    push_in_cut = push_in[:20]
    assert x5_parse_battery_field(push_in_cut, 1) == 1
    assert x5_parse_battery_field(push_in_cut, 2) is None
    assert x5_parse_battery_field(push_out[:20], 1) == 0
    assert x5_parse_battery_field(push_out[:20], 2) is None
    # one octet deeper, cut right after the level's tag: still no guessed level
    assert x5_parse_battery_field(push_in[:21], 2) is None
    assert x5_parse_battery_field(push_in[:22], 2) == 57

    # code 200 answer to cmdGetBattery (0a 02 0b 14 = options 11 and 20),
    # declared 51, whole on a wide-MTU link: battery 57 on the cell
    resp51 = bytes.fromhex(
        "33000000040000c80002010000800000080b0814121d5a06080010392000"
        "a201120800108080a0d7f70618808080f8b8072000")
    assert len(resp51) == 51
    assert (resp51[7] | (resp51[8] << 8)) == 200
    assert x5_parse_options_battery(resp51) == 57
    assert x5_parse_options_battery(resp51[:20]) is None

    # code 200 answer to the wide request (options 11, 15, 16, 20, 30, 48),
    # 148 octets: battery 61 next to serial, uuid, storage, firmware, model
    resp148 = bytes.fromhex(
        "94000000040000c80002010000800000080b080f08100814081e083012765a06080"
        "0103d20007a0e494148454132353033533647455782012d696e7374613336302d64"
        "323036636130632d653930372d343134632d383366382d6338323138613861626161"
        "36a201120800108080a0d7f70618808080f8b8072000f2010876312e31332e323182"
        "030b496e737461333630205835")
    assert len(resp148) == 148
    assert x5_parse_options_battery(resp148) == 61
    assert x5_parse_options_battery(resp148[:20]) is None

    # the code 200 answer to the stop candidate as the watch saw it (declared
    # 66, arrived 20): nothing about a battery can read off that fragment
    cut66 = bytes.fromhex("42000000040000c800020300008000000a300a2e")
    assert len(cut66) == 20
    assert x5_parse_options_battery(cut66) is None

    print("OK: poussee 57% (adapter/cell), code 8 51 octets -> 57, "
          "148 octets -> 61; coupe montre 20/24 -> power seul, niveau jamais "
          "devine; reponses 200 coupees -> aucune valeur")


if __name__ == "__main__":
    main()
