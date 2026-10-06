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
import insta360_ucd2 as ucd2


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


# A real GET_OPTIONS answer, captured from a camera and used as a test vector by
# the Luna Ultra implementation this codec is ported from. CRC included.
CAPTURED_FILE_FRAME = bytes.fromhex(
    "55434432010c04100f0000000800020100008000000830080f080b7c008e7c")


class Ucd2ChecksumTest(unittest.TestCase):
    """The checksum is a nonstandard variant; pin it against captured bytes."""

    def test_matches_captured_frame_trailer(self):
        frame = CAPTURED_FILE_FRAME[:-4]
        self.assertEqual(
            ucd2.checksum(frame),
            int.from_bytes(CAPTURED_FILE_FRAME[-4:], "little"))

    def test_is_not_a_standard_crc32(self):
        import zlib
        frame = CAPTURED_FILE_FRAME[:-4]
        self.assertNotEqual(ucd2.checksum(frame), zlib.crc32(frame))

    def test_bytewise_crc_matches_reference(self):
        """The on-watch port carries the CRC as four bytes, not one Number.

        A Monkey C Number is a signed 32 bit integer with a 31 bit safe range, and
        `c << 1` leaves it as soon as bit 30 is set. The device then receives a
        Float, which has no bit operators, and the app aborts with Illegal Access.
        So the shipped algorithm shifts four bytes and must stay bit identical.
        """
        def bytewise(data):
            b0 = b1 = b2 = b3 = 0xFF
            for byte in data:
                b0 ^= byte & 0xFF
                for _ in range(4):
                    for _ in range(8):
                        carry = b3 & 0x80
                        b3 = ((b3 << 1) | (b2 >> 7)) & 0xFF
                        b2 = ((b2 << 1) | (b1 >> 7)) & 0xFF
                        b1 = ((b1 << 1) | (b0 >> 7)) & 0xFF
                        b0 = (b0 << 1) & 0xFF
                        if carry:
                            b0 ^= 0xB7
                            b1 ^= 0x1D
                            b2 ^= 0xC1
                            b3 ^= 0x04
            return bytes([b0, b1, b2, b3])

        frame = CAPTURED_FILE_FRAME[:-4]
        self.assertEqual(
            ucd2.checksum(frame).to_bytes(4, "little"), bytewise(frame))

    def test_bytewise_crc_never_exceeds_31_bits(self):
        """Every intermediate must fit the 31 bit safe range of a Number."""
        b0 = b1 = b2 = b3 = 0xFF
        peak = 0
        for byte in CAPTURED_FILE_FRAME[:-4]:
            b0 ^= byte & 0xFF
            for _ in range(4):
                for _ in range(8):
                    carry = b3 & 0x80
                    b3 = ((b3 << 1) | (b2 >> 7)) & 0xFF
                    b2 = ((b2 << 1) | (b1 >> 7)) & 0xFF
                    b1 = ((b1 << 1) | (b0 >> 7)) & 0xFF
                    b0 = (b0 << 1) & 0xFF
                    peak = max(peak, b0, b1, b2, b3)
                    if carry:
                        b0 ^= 0xB7
                        b1 ^= 0x1D
                        b2 ^= 0xC1
                        b3 ^= 0x04
        self.assertLess(peak, 512)


class Ucd2LayoutTest(unittest.TestCase):
    def test_captured_frame_decodes(self):
        info = ucd2.describe_frame(CAPTURED_FILE_FRAME)
        self.assertEqual(ucd2.TYPE_FILE, info["type"])
        self.assertEqual(0x10, info["seq"])
        self.assertEqual(15, info["declared"])
        self.assertEqual(ucd2.CMD_GET_OPTIONS, info["code"])
        self.assertEqual(1, info["request_id"])
        self.assertEqual(ucd2.FILE_FLAGS, info["file_flags"])
        self.assertTrue(info["complete"])
        self.assertTrue(info["trailer_ok"])

    def test_byte5_is_a_constant_not_a_length(self):
        # 0x0c equals 12, which is size - 8 on a 20 byte notification. That is a
        # coincidence, and reading it as a length is what the first pass did.
        self.assertEqual(0x0C, CAPTURED_FILE_FRAME[5])
        for frame_type in (ucd2.TYPE_MEDIA, ucd2.TYPE_FILE, ucd2.TYPE_STREAM):
            frame = ucd2.build_ucd2(frame_type, 1, b"")
            self.assertEqual(ucd2.FLAGS, frame[5])

    def test_byte6_is_a_type_not_an_opcode(self):
        stream = ucd2.build_ucd2(ucd2.TYPE_STREAM, 1, b"\x00" * 8)
        self.assertEqual(ucd2.TYPE_STREAM, stream[6])

    def test_total_length_is_sixteen_plus_declared(self):
        frame = ucd2.build_file_command(1, ucd2.CMD_START_CAPTURE, 1)
        self.assertEqual(9, ucd2.declared_length(frame))
        self.assertEqual(25, len(frame))
        self.assertEqual(ucd2.frame_length(9), len(frame))


class Ucd2FileCommandTest(unittest.TestCase):
    def test_body_is_code_marker_requestid_flags(self):
        frame = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        body = frame[ucd2.BODY_POS:]
        self.assertEqual(bytes([0x04, 0x00]), body[0:2])   # START_CAPTURE
        self.assertEqual(0x02, body[2])                    # marker
        self.assertEqual(bytes([0x01, 0x00]), body[3:5])   # request id 1
        self.assertEqual(bytes([0x00, 0x80, 0x00, 0x00]), body[5:9])  # 0x8000 LE

    def test_start_and_stop_differ_only_in_code_and_checksum(self):
        start = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        stop = ucd2.build_file_command(0x24, ucd2.CMD_STOP_CAPTURE, 1)
        differing = [i for i in range(len(start)) if start[i] != stop[i]]
        self.assertEqual([12, len(start) - 4, len(start) - 3,
                          len(start) - 2, len(start) - 1], differing)

    def test_trailer_sits_at_body_offset_plus_length(self):
        """The CRC trailer must begin at PAY + declared length.

        It used to be indexed as HDR + LEN + 4 + length, which overshot by 4
        and would have written the trailer past the end of the frame.
        """
        for op in (ucd2.CMD_START_CAPTURE, ucd2.CMD_STOP_CAPTURE):
            frame = ucd2.build_file_command(0x24, op, 1)
            declared = int.from_bytes(frame[8:12], "little")
            self.assertEqual(ucd2.BODY_POS + declared, len(frame) - 4)

    def test_reference_frames_are_byte_identical(self):
        """Pins the full START and STOP frames.

        The on-watch port had three separate defects that a partial assertion
        would have missed: the 0x8000 field byte swapped, the trailer offset four
        too high, and the CRC XOR reading ByteArray elements without masking
        their signedness. This pins every byte.
        """
        self.assertEqual(
            bytes.fromhex("55434432010c0424090000000400020100008000008472946e"),
            ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1))
        self.assertEqual(
            bytes.fromhex("55434432010c0424090000000500020100008000009ac5d4c5"),
            ucd2.build_file_command(0x24, ucd2.CMD_STOP_CAPTURE, 1))

    def test_checksum_covers_the_sequence_byte(self):
        first = ucd2.build_file_command(1, ucd2.CMD_START_CAPTURE, 1)
        second = ucd2.build_file_command(2, ucd2.CMD_START_CAPTURE, 1)
        self.assertNotEqual(first[-4:], second[-4:])
        self.assertEqual(first[-4:], ucd2.build_file_command(
            1, ucd2.CMD_START_CAPTURE, 1)[-4:])

    def test_reproduces_the_captured_frame(self):
        built = ucd2.build_file_command(
            0x10, ucd2.CMD_GET_OPTIONS, 1, bytes.fromhex("0830080f080b"))
        self.assertEqual(CAPTURED_FILE_FRAME, built)


class Ucd2ReassemblyTest(unittest.TestCase):
    def test_a_25_byte_frame_arrives_as_20_then_5(self):
        frame = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        parts = ucd2.split_notifications(frame)
        self.assertEqual([20, 5], [len(p) for p in parts])
        self.assertEqual(frame, b"".join(parts))

    def test_tail_carries_no_magic(self):
        frame = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        self.assertFalse(ucd2.is_ucd2(frame[20:]))

    def test_reassembles_across_the_two_notifications(self):
        frame = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        rx = ucd2.Reassembler()
        self.assertEqual([], rx.feed(frame[:20]))
        self.assertTrue(rx.pending)
        self.assertEqual([frame], rx.feed(frame[20:]))
        self.assertFalse(rx.pending)

    def test_incomplete_frame_is_not_reported_as_whole(self):
        frame = ucd2.build_file_command(0x24, ucd2.CMD_START_CAPTURE, 1)
        rx = ucd2.Reassembler()
        self.assertEqual([], rx.feed(frame[:20]))
        info = ucd2.describe_frame(frame[:20])
        self.assertFalse(info["complete"])
        self.assertEqual(25, info["expected_len"])
        self.assertIsNone(info["trailer_ok"])

    def test_several_frames_in_sequence(self):
        rx = ucd2.Reassembler()
        frames = [
            ucd2.build_file_command(i, ucd2.CMD_START_CAPTURE, 1)
            for i in range(1, 4)
        ]
        out = []
        for frame in frames:
            for part in ucd2.split_notifications(frame):
                out.extend(rx.feed(part))
        self.assertEqual(frames, out)

    def test_stream_hello_is_whole_in_one_notification(self):
        # The 16 byte hello declares 0, so its total is 16 and it is never split.
        stream = (b"UCD2" + bytes([0x01, 0x0C, ucd2.TYPE_STREAM, 4])
                  + bytes.fromhex("00000000f6cc4f09"))
        self.assertEqual(16, len(stream))
        self.assertEqual(0, ucd2.declared_length(stream))
        rx = ucd2.Reassembler()
        self.assertEqual([stream], rx.feed(stream))

    def test_orphan_tail_without_a_frame_is_dropped(self):
        rx = ucd2.Reassembler()
        self.assertEqual([], rx.feed(bytes.fromhex("0084729 46e".replace(" ", ""))))


if __name__ == "__main__":
    unittest.main(verbosity=2)
