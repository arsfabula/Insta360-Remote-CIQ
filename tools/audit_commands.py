"""Audit the shipping command arrays against what their labels claim.

Run: python tools/audit_commands.py

This is deliberately independent of test_golden.py: it does not share the
expected (resolution, function_mode) table, because a shared table would make
the two agree by construction and detect nothing. The expectations here are
written from the labels in BLEBarrel.mc, Modes.txt and the official app's
behaviour, then compared against what the bytes actually encode.

Exit status is 0 even when divergences are found: a divergence is a finding to
report, not a broken test.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ciq_arrays
import insta360_proto as proto


# name -> (expected resolution, expected function mode, what the label promises)
DECLARED_INTENT = {
    "cmdSet5k30": (proto.RES_2880_2880P30, proto.FM_NORMAL_VIDEO, "5.7K 360 @30, normal video"),
    "cmdSet5k25": (proto.RES_2880_2880P25, proto.FM_NORMAL_VIDEO, "5.7K 360 @25, normal video"),
    "cmdSet5k24": (proto.RES_2880_2880P24, proto.FM_NORMAL_VIDEO, "5.7K 360 @24, normal video"),
    "cmdSet4k50": (proto.RES_3840_1920P50, proto.FM_NORMAL_VIDEO, "4K 360 @50, normal video"),
    "cmdSet4k30": (proto.RES_3840_1920P30, proto.FM_NORMAL_VIDEO, "4K 360 @30, normal video"),
    # 3008x1504@100 is used twice on purpose: as a plain 3K100 menu entry, and
    # again by cmdSetBullet with FUNCTION_MODE_HIGH_FRAME_RATE for bullet time.
    "cmdSet3k100": (proto.RES_3008_1504P100, proto.FM_NORMAL_VIDEO, "3K 360 @100 as a normal video mode"),
    "cmdSet8k30": (proto.RES_3840_3840P30, proto.FM_NORMAL_VIDEO, "8K 360 @30, normal video"),
    "cmdSetTL": (proto.RES_2880_2880P30, proto.FM_MOBILE_TIMELAPSE, "mobile timelapse"),
    "cmdSetBullet": (proto.RES_3008_1504P100, proto.FM_HIGH_FRAME_RATE, "bullet time / high frame rate"),
    "cmdSetHDR": (proto.RES_2880_2880P30, proto.FM_HDR_VIDEO, "HDR video at 5.7K @30"),
}

# Commands whose payload is not a SetPhotographyOptions message are listed
# separately below, by command id, and left undecoded on purpose.


def resolution_text(value):
    if value is None:
        return "ABSENT (proto3 default = %s)" % proto.RESOLUTION_NAMES[proto.RES_3840_1920P30]
    return proto.RESOLUTION_NAMES.get(value, "unknown(%d)" % value)


def mode_text(value):
    if value is None:
        return "ABSENT (defaults to FUNCTION_MODE_NORMAL)"
    return proto.FUNCTION_MODE_NAMES.get(value, "unknown(%d)" % value)


def print_candidates():
    print("=" * 100)
    print("CANDIDATE CORRECTIONS (NOT applied - each needs a hardware check)")
    print("=" * 100)

    candidates = [
        ("cmdSet4k30 as shipped: resolution implied by the proto3 default",
         proto.set_video_mode(None, proto.FM_NORMAL_VIDEO),
         "canonical", "PhotographyOptions is present but empty (12 00)"),
        ("cmdSet4k30 with the resolution written out explicitly",
         proto.set_video_mode(proto.RES_3840_1920P30, proto.FM_NORMAL_VIDEO,
                              emit_default_zero=True),
         "NON-canonical", "f8 01 00 is a default value a canonical writer omits"),
        ("cmdSetHDR as shipped",
         proto.set_video_mode(proto.RES_3840_1920P20, proto.FM_NORMAL_VIDEO),
         "canonical", "asks for 4K@20 as a *normal* video mode"),
        ("cmdSetHDR corrected: 5.7K@30, HDR video",
         proto.set_video_mode(proto.RES_2880_2880P30, proto.FM_HDR_VIDEO),
         "canonical", "matches Modes.txt: the app offers HDR at 5k30/25/24"),
        ("cmdSetHDR corrected: 4K@30, HDR video",
         proto.set_video_mode(proto.RES_3840_1920P30, proto.FM_HDR_VIDEO,
                              emit_default_zero=True),
         "NON-canonical", "would need the explicit zero to survive"),
    ]
    for title, frame, kind, note in candidates:
        print("  %s" % title)
        print("    %-14s %s" % (kind, proto.to_hex(frame)))
        print("    note: %s" % note)
        print()

    print("  proto3 cannot express 'set resolution to 0' in canonical form, so")
    print("  4K30 and any 4K-based HDR variant depend on the camera reading an")
    print("  absent field as its default. That is the single biggest unknown here.")
    print("  The HDR-at-5.7K candidate avoids the problem entirely and is the one")
    print("  to try first, since the official app documents HDR at 5k30/25/24.")
    print()


def main():
    commands = ciq_arrays.read_commands()
    print("Source: %s" % ciq_arrays.source_path())
    print("Command arrays found: %d" % len(commands))
    print()

    divergences = []
    undecodable = []

    print("=" * 100)
    print("VIDEO MODE COMMANDS")
    print("=" * 100)
    print()

    for name in sorted(commands):
        if name not in DECLARED_INTENT:
            continue
        frame = commands[name]["bytes"]
        try:
            decoded = proto.describe_video_mode_frame(frame)
        except proto.CodecError as exc:
            undecodable.append((name, str(exc)))
            continue
        label = commands[name].get("comment", "")
        expected_res, expected_mode, promise = DECLARED_INTENT[name]
        actual_res = decoded.get("record_resolution")
        actual_mode = decoded.get("function_mode")
        agrees = actual_res == expected_res and actual_mode == expected_mode

        print("  %s" % name)
        print("    label in source : %s" % label)
        print("    label promises  : %s" % promise)
        print("    line %d, %d bytes" % (commands[name]["line"], len(frame)))
        print("    bytes           : %s" % proto.to_hex(frame))
        print("    resolution      : %s" % decoded.get("resolution_name"))
        print("    function mode   : %s" % decoded.get("function_mode_name"))
        if agrees:
            print("    OK              : payload matches the label")
        else:
            print("    MISMATCH:")
            print("      resolution    : expected %s" % resolution_text(expected_res))
            print("                       actual   %s" % resolution_text(actual_res))
            print("      function mode : expected %s" % mode_text(expected_mode))
            print("                       actual   %s" % mode_text(actual_mode))
            divergences.append(name)
        print()

    print("=" * 100)
    print("OTHER COMMANDS (out of scope for the video-mode audit)")
    print("=" * 100)
    for name in sorted(commands):
        if name in DECLARED_INTENT:
            continue
        frame = commands[name]["bytes"]
        try:
            info = proto.describe_frame(frame)
        except proto.CodecError as exc:
            print("  %-18s %3d bytes  <undecodable: %s>" % (name, len(frame), exc))
            undecodable.append((name, str(exc)))
            continue
        print("  %-18s %3d bytes  cmd=0x%02x %s"
              % (name, len(frame), info["command_id"], info["command_name"]))
    print()

    print("=" * 100)
    print("SUMMARY")
    print("=" * 100)
    if divergences:
        print("Divergences between label and payload: %s" % ", ".join(sorted(divergences)))
    else:
        print("No divergences found.")
    if undecodable:
        print("Payloads not decoded: %s" % ", ".join(n for n, _ in undecodable))
    print()
    print("Note: 3840x3840@30 is the per-eye half of a 7680x3840 8K 360 frame,")
    print("so cmdSet8k30 is correct and must not be 'fixed' to a 7680-wide value.")
    print()
    print_candidates()
    return 0


if __name__ == "__main__":
    sys.exit(main())
