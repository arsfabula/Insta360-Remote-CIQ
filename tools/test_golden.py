"""Golden-byte tests for the Insta360 BLE codec.

Run: python tools/test_golden.py

The command arrays in BLEBarrel.mc are ground truth: they drive real X4/X5
hardware and have been working for years. This suite proves our encoder
reproduces them exactly, so anything we generate for X6 / Ace / Go is built on
a codec that is already known to speak to the camera.

Two groups:
  * KNOWN_GOOD - commands verified against hardware. Byte-exact match required.
  * CHARACTERISED - commands whose bytes are reproduced as-is, even though the
    payload looks wrong. Characterisation, not endorsement: when a payload is
    fixed these tests fail, which is the signal to update the table deliberately
    rather than silently.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ciq_arrays
import insta360_proto as proto


# (record_resolution, function_mode) as the camera is really being addressed.
KNOWN_GOOD = {
    "cmdSet5k30": (proto.RES_2880_2880P30, proto.FM_NORMAL_VIDEO),
    "cmdSet5k25": (proto.RES_2880_2880P25, proto.FM_NORMAL_VIDEO),
    "cmdSet5k24": (proto.RES_2880_2880P24, proto.FM_NORMAL_VIDEO),
    "cmdSet4k50": (proto.RES_3840_1920P50, proto.FM_NORMAL_VIDEO),
    "cmdSet3k100": (proto.RES_3008_1504P100, proto.FM_NORMAL_VIDEO),
    # 3840x3840 is the per-eye half of a 7680x3840 8K 360 frame: correct for X4.
    "cmdSet8k30": (proto.RES_3840_3840P30, proto.FM_NORMAL_VIDEO),
    "cmdSetTL": (proto.RES_2880_2880P30, proto.FM_MOBILE_TIMELAPSE),
    "cmdSetBullet": (proto.RES_3008_1504P100, proto.FM_HIGH_FRAME_RATE),
}

# Reproduced verbatim, but the payload is questionable - see audit_commands.py.
CHARACTERISED = {
    # RECORD_RESOLUTION is announced, then an empty PhotographyOptions is sent.
    "cmdSet4k30": (None, proto.FM_NORMAL_VIDEO),
    # 3840x1920@20 requested as a *normal* video mode, not an HDR one.
    "cmdSetHDR": (proto.RES_3840_1920P20, proto.FM_NORMAL_VIDEO),
}


def load_source():
    commands = ciq_arrays.read_commands()
    if not commands:
        raise RuntimeError("no cmd* arrays found in BLEBarrel.mc")
    return commands


class EncoderMatchesSourceTest(unittest.TestCase):
    """The codec must reproduce every shipping command byte for byte."""

    @classmethod
    def setUpClass(cls):
        cls.commands = load_source()

    def assert_matches(self, name, record_resolution, function_mode):
        self.assertIn(name, self.commands, "%s missing from BLEBarrel.mc" % name)
        expected = self.commands[name]["bytes"]
        actual = list(proto.set_video_mode(record_resolution, function_mode))
        self.assertEqual(
            expected, actual,
            "%s mismatch\n  source: %s\n  ours  : %s"
            % (name, proto.to_hex(expected), proto.to_hex(actual)),
        )

    def test_known_good_video_modes(self):
        for name, (resolution, function_mode) in sorted(KNOWN_GOOD.items()):
            with self.subTest(command=name):
                self.assert_matches(name, resolution, function_mode)

    def test_characterised_video_modes(self):
        for name, (resolution, function_mode) in sorted(CHARACTERISED.items()):
            with self.subTest(command=name):
                self.assert_matches(name, resolution, function_mode)

    def test_start_and_stop_capture(self):
        self.assertEqual(
            list(proto.encode_start_capture()),
            self.commands["cmdStartRec"]["bytes"],
        )
        self.assertEqual(
            list(proto.encode_stop_capture()),
            self.commands["cmdStopRec"]["bytes"],
        )

    def test_apply_command_is_command_15_with_no_payload(self):
        apply_bytes = self.commands["cmdApply"]["bytes"]
        info = proto.describe_frame(apply_bytes)
        self.assertEqual(16, len(apply_bytes))
        self.assertEqual(proto.CMD_GET_CURRENT_CAPTURE_STATUS, info["command_id"])
        self.assertEqual(b"", info["payload"])


class FrameStructureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.commands = load_source()

    def test_declared_length_matches_every_source_frame(self):
        for name, entry in sorted(self.commands.items()):
            with self.subTest(command=name):
                info = proto.describe_frame(entry["bytes"])
                self.assertNotIn("length_mismatch", info)
                self.assertEqual(len(entry["bytes"]), info["declared_length"])

    def test_header_layout_holds_for_every_source_frame(self):
        for name, entry in sorted(self.commands.items()):
            with self.subTest(command=name):
                frame = entry["bytes"]
                self.assertEqual(0x00, frame[2])
                self.assertEqual(0x00, frame[3])
                self.assertEqual(0x04, frame[4])
                self.assertEqual(0x00, frame[5])
                self.assertEqual(0x00, frame[6])
                self.assertEqual(0x00, frame[8])
                self.assertEqual(0x02, frame[9])
                self.assertEqual(0x00, frame[12])
                self.assertEqual(0x80, frame[13])
                self.assertEqual(0x00, frame[14])
                self.assertEqual(0x00, frame[15])

    def test_sequence_byte_position_is_ten(self):
        self.assertEqual(10, proto.SEQ_POS)
        frame = bytearray(proto.set_video_mode(proto.RES_2880_2880P30))
        frame[proto.SEQ_POS] = 0x2A
        info = proto.describe_frame(frame)
        self.assertEqual(0x2A, info["sequence"])

    def test_packets_are_never_longer_than_twenty_bytes(self):
        for name, entry in sorted(self.commands.items()):
            with self.subTest(command=name):
                packets = proto.split_packets(entry["bytes"])
                self.assertEqual(b"".join(packets), bytes(entry["bytes"]))
                for packet in packets:
                    self.assertLessEqual(len(packet), proto.MAX_WIRE_PACKET)

    def test_multi_packet_frame_round_trips(self):
        packets = proto.split_packets(self.commands["cmdSetPhotoHDR"]["bytes"])
        self.assertGreater(len(packets), 1)
        self.assertEqual(
            bytes(self.commands["cmdSetPhotoHDR"]["bytes"]),
            b"".join(packets),
        )


class VarintTest(unittest.TestCase):
    def test_round_trip(self):
        for value in (0, 1, 12, 127, 128, 300, 167, 213, 1000, 2 ** 31):
            with self.subTest(value=value):
                self.assertEqual(value, proto.read_varint(proto.varint(value), 0)[0])

    def test_multi_byte_forms(self):
        self.assertEqual(b"\x00", proto.varint(0))
        self.assertEqual(b"\x7f", proto.varint(127))
        self.assertEqual(b"\x80\x01", proto.varint(128))
        self.assertEqual(b"\xa7\x01", proto.varint(167))
        self.assertEqual(b"\xd5\x01", proto.varint(213))

    def test_truncated_varint_raises(self):
        with self.assertRaises(proto.CodecError):
            proto.read_varint(b"\x80", 0)


class DecodeTest(unittest.TestCase):
    def test_video_mode_round_trip(self):
        for resolution in (proto.RES_2880_2880P30, proto.RES_3840_3840P30,
                           proto.RES_3008_1504P100, proto.RES_7680_3268P30):
            with self.subTest(resolution=resolution):
                info = proto.describe_video_mode_frame(
                    proto.set_video_mode(resolution, proto.FM_HDR_VIDEO))
                self.assertEqual([proto.OPT_RECORD_RESOLUTION], info["option_types"])
                self.assertEqual(resolution, info["record_resolution"])
                self.assertEqual(proto.FM_HDR_VIDEO, info["function_mode"])
                self.assertEqual("FUNCTION_MODE_HDR_VIDEO", info["function_mode_name"])

    def test_explicit_zero_resolution_can_be_emitted(self):
        frame = proto.set_video_mode(
            proto.RES_3840_1920P30, proto.FM_NORMAL_VIDEO, emit_default_zero=True)
        self.assertIn(b"\xf8\x01\x00", bytes(frame))
        described = proto.describe_set_photography_options(bytes(frame)[proto.PROTOBUF_POS:])
        self.assertEqual(proto.RES_3840_1920P30, described["record_resolution"])

    def test_canonical_proto3_omits_zero_resolution(self):
        frame = proto.set_video_mode(
            proto.RES_3840_1920P30, proto.FM_NORMAL_VIDEO, emit_default_zero=False)
        self.assertNotIn(b"\xf8\x01", bytes(frame))
        described = proto.describe_set_photography_options(bytes(frame)[proto.PROTOBUF_POS:])
        self.assertIsNone(described["record_resolution"])

    def test_empty_options_message_is_announced(self):
        frame = proto.set_video_mode(None, proto.FM_NORMAL_VIDEO)
        payload = bytes(frame)[proto.PROTOBUF_POS:]
        self.assertEqual(b"\x0a\x01\x1f\x12\x00\x18\x07", payload)
        described = proto.describe_set_photography_options(payload)
        self.assertTrue(described["present"])
        self.assertIsNone(described["record_resolution"])

    def test_command_id_is_nine_for_video_modes(self):
        info = proto.describe_frame(proto.set_video_mode(proto.RES_2880_2880P30))
        self.assertEqual(proto.CMD_SET_PHOTOGRAPHY_OPTIONS, info["command_id"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
