"""Byte-exact Insta360 BLE command codec (dependency-free Python 3).

Reverse-engineered from the command arrays shipping in
`BLE Barrel/BLEBarrel.mc` and validated against the official `libOne`
protobuf definitions shipped with the Insta360 phone app.

Hand-rolled on purpose: the watch app has no dependencies and no protobuf
runtime, and this repo must stay testable with a bare Python 3. There is no
`protoc` requirement either.

The encoder is proven against the 20 command arrays already shipping in
BLEBarrel.mc, which are ground truth that works on X4/X5 hardware; see
`test_golden.py`. Anything this module emits for a *new* model must still be
confirmed on the physical camera.
"""

import struct

HEADER_LEN = 16
MAX_WIRE_PACKET = 20
SEQ_POS = 10
PROTOBUF_POS = 16

WIRE_VARINT = 0
WIRE_64BIT = 1
WIRE_LEN = 2
WIRE_32BIT = 5

DEFAULT_SEQUENCE = 0xFF

# MessageCode, byte 7 of the frame. Only the codes this app actually sends.
CMD_TAKE_PICTURE = 3
CMD_START_CAPTURE = 4
CMD_STOP_CAPTURE = 5
CMD_SET_PHOTOGRAPHY_OPTIONS = 9
CMD_GET_CURRENT_CAPTURE_STATUS = 15
CMD_SET_KEY_TIME_POINT = 60
CMD_UPLOAD_GPS = 53

# CaptureMode, StartCapture.mode / StopCapture.mode
CAPTURE_MODE_VIDEO = 1

# PhotographyOptionType
OPT_RECORD_RESOLUTION = 31
OPT_RECORD_DURATION = 29
OPT_PHOTO_SIZE_ID = 30
OPT_COLOR_MODE = 35
OPT_HDR_SWITCH_STATUS = 63

# FunctionMode
FM_NORMAL = 0
FM_MOBILE_TIMELAPSE = 2
FM_INTERVAL_SHOOTING = 3
FM_HIGH_FRAME_RATE = 4
FM_NORMAL_VIDEO = 7
FM_HDR_VIDEO = 9
FM_INTERVAL_VIDEO = 10

# VideoResolution. Only the values this project references; the full 229-entry
# enum lives in the app's video.proto and is not duplicated here.
RES_3840_1920P30 = 0
RES_2880_2880P30 = 10
RES_3840_1920P50 = 12
RES_3008_1504P100 = 13
RES_2880_2880P25 = 19
RES_2880_2880P24 = 20
RES_3840_1920P20 = 21
RES_3840_3840P30 = 167
RES_7680_4320P30 = 154
RES_7680_3268P30 = 213

RESOLUTION_NAMES = {
    RES_3840_1920P30: "3840x1920@30 (4K 360)",
    RES_2880_2880P30: "2880x2880@30 (5.7K 360, per eye)",
    RES_3840_1920P50: "3840x1920@50 (4K 50 360)",
    RES_3008_1504P100: "3008x1504@100 (3K 100 360)",
    RES_2880_2880P25: "2880x2880@25 (5.7K 25, per eye)",
    RES_2880_2880P24: "2880x2880@24 (5.7K 24, per eye)",
    RES_3840_1920P20: "3840x1920@20",
    RES_3840_3840P30: "3840x3840@30 (8K 360, per eye)",
    RES_7680_4320P30: "7680x4320@30 (8K DCI)",
    RES_7680_3268P30: "7680x3268@30 (8K)",
}

FUNCTION_MODE_NAMES = {
    FM_NORMAL: "FUNCTION_MODE_NORMAL",
    FM_MOBILE_TIMELAPSE: "FUNCTION_MODE_MOBILE_TIMELAPSE",
    FM_INTERVAL_SHOOTING: "FUNCTION_MODE_INTERVAL_SHOOTING",
    FM_HIGH_FRAME_RATE: "FUNCTION_MODE_HIGH_FRAME_RATE",
    FM_NORMAL_VIDEO: "FUNCTION_MODE_NORMAL_VIDEO",
    FM_HDR_VIDEO: "FUNCTION_MODE_HDR_VIDEO",
    FM_INTERVAL_VIDEO: "FUNCTION_MODE_INTERVAL_VIDEO",
}

# PhotographyOptions field numbers worth naming when auditing a payload.
PHOTOGRAPHY_OPTION_FIELDS = {
    29: "record_duration",
    30: "photo_size_id",
    31: "record_resolution",
    32: "video_bitrate",
    35: "color_mode",
    40: "photo_resolution",
    63: "hdr_switch_status",
}

COMMAND_NAMES = {
    CMD_TAKE_PICTURE: "PHONE_COMMAND_TAKE_PICTURE",
    CMD_START_CAPTURE: "PHONE_COMMAND_START_CAPTURE",
    CMD_STOP_CAPTURE: "PHONE_COMMAND_STOP_CAPTURE",
    CMD_SET_PHOTOGRAPHY_OPTIONS: "PHONE_COMMAND_SET_PHOTOGRAPHY_OPTIONS",
    CMD_GET_CURRENT_CAPTURE_STATUS: "PHONE_COMMAND_GET_CURRENT_CAPTURE_STATUS",
    CMD_SET_KEY_TIME_POINT: "PHONE_COMMAND_SET_KEY_TIME_POINT",
    CMD_UPLOAD_GPS: "PHONE_COMMAND_UPLOAD_GPS",
}


class CodecError(ValueError):
    pass


def varint(value):
    if value < 0:
        raise CodecError("varint must be non-negative, got %d" % value)
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def read_varint(data, pos):
    result = 0
    shift = 0
    while True:
        if pos >= len(data):
            raise CodecError("truncated varint at offset %d" % pos)
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, pos
        shift += 7
        if shift > 63:
            raise CodecError("varint wider than 64 bits")


def tag(field_number, wire_type):
    return varint((field_number << 3) | wire_type)


class PbWriter:
    """Minimal proto3 writer.

    proto3 omits scalar fields that hold their default value. `emit_default_zero`
    forces the field out anyway, which is how an explicit "set resolution to 0"
    is expressed; a canonical proto3 reader is still free to ignore it, so this
    must be confirmed against the camera before being relied on.
    """

    def __init__(self, emit_default_zero=False):
        self._buf = bytearray()
        self.emit_default_zero = emit_default_zero

    def _varint_field(self, field_number, value):
        if value < 0:
            raise CodecError("field %d: use sint encoding for negatives" % field_number)
        if value == 0 and not self.emit_default_zero:
            return self
        self._buf += tag(field_number, WIRE_VARINT) + varint(value)
        return self

    def uint32(self, field_number, value, default=0):
        if value is None or int(value) == default:
            return self
        return self._varint_field(field_number, int(value))

    def enum(self, field_number, value):
        return self._varint_field(field_number, int(value))

    def repeated_uint32(self, field_number, values):
        """Emit a repeated scalar in proto3's default *packed* form.

        Packing is the proto3 default for numeric scalars, and the camera's own
        app uses it: option_types=31 travels as `0a 01 1f` (length-delimited)
        rather than `08 1f`. A proto3 parser accepts both, but matching the
        official encoding keeps the golden bytes honest.
        """
        values = [int(v) for v in values]
        if not values:
            return self
        packed = b"".join(varint(v) for v in values)
        self._buf += tag(field_number, WIRE_LEN) + varint(len(packed)) + packed
        return self

    def message(self, field_number, payload):
        payload = bytes(payload)
        self._buf += tag(field_number, WIRE_LEN) + varint(len(payload)) + payload
        return self

    def bytes(self):
        return bytes(self._buf)


def iter_fields(data):
    """Yield (field_number, wire_type, value) for a protobuf message.

    Length-delimited values are yielded as raw bytes; recurse with `iter_fields`
    or use `decode_nested` for sub-messages.
    """
    data = bytes(data)
    pos = 0
    while pos < len(data):
        key, pos = read_varint(data, pos)
        field_number = key >> 3
        wire_type = key & 0x07
        if wire_type == WIRE_VARINT:
            value, pos = read_varint(data, pos)
        elif wire_type == WIRE_LEN:
            length, pos = read_varint(data, pos)
            value = data[pos:pos + length]
            if len(value) != length:
                raise CodecError("truncated length-delimited field %d" % field_number)
            pos += length
        elif wire_type == WIRE_32BIT:
            value = data[pos:pos + 4]
            pos += 4
        elif wire_type == WIRE_64BIT:
            value = data[pos:pos + 8]
            pos += 8
        else:
            raise CodecError("unsupported wire type %d" % wire_type)
        yield field_number, wire_type, value


def iter_packed_varints(data):
    pos = 0
    while pos < len(data):
        value, pos = read_varint(data, pos)
        yield value


def decode_nested(data):
    """Best-effort recursive decode: nested messages become lists of fields."""
    out = []
    for field_number, wire_type, value in iter_fields(data):
        if wire_type == WIRE_LEN:
            try:
                value = decode_nested(value)
            except CodecError:
                pass
        out.append((field_number, wire_type, value))
    return out


def build_frame(command_id, payload=b"", sequence=DEFAULT_SEQUENCE):
    """Build a complete 16-byte-header command frame.

    Layout, confirmed against every array in BLEBarrel.mc:
      0..1   total frame length, uint16 little-endian
      2..3   0x0000
      4      0x04 frame type
      5..6   0x0000
      7      command id
      8..9   0x0002
      10..11 sequence number, uint16 little-endian (overwritten per send)
      12..13 0x8000
      14..15 0x0000
      16..   protobuf payload
    """
    payload = bytes(payload)
    total = HEADER_LEN + len(payload)
    if total > 0xFFFF:
        raise CodecError("frame too long: %d bytes" % total)
    header = bytearray(HEADER_LEN)
    struct.pack_into("<H", header, 0, total)
    header[4] = 0x04
    header[7] = command_id & 0xFF
    header[9] = 0x02
    header[10] = sequence & 0xFF
    header[11] = (sequence >> 8) & 0xFF
    header[13] = 0x80
    return bytes(header) + payload


def split_packets(frame):
    """Split a frame into the 20-byte BLE writes, as sendCMD() does."""
    frame = bytes(frame)
    count = (len(frame) - 1) // MAX_WIRE_PACKET
    return [frame[i * MAX_WIRE_PACKET:(i + 1) * MAX_WIRE_PACKET] for i in range(count + 1)]


def encode_photography_options(record_resolution=None, emit_default_zero=False,
                                extra_fields=()):
    """Encode a PhotographyOptions message with only the fields we set.

    `record_resolution=None` leaves the field out entirely, which is how the
    camera receives "change resolution" with no value attached.
    """
    writer = PbWriter(emit_default_zero=emit_default_zero)
    if record_resolution is not None:
        writer.enum(31, record_resolution)
    for field_number, value in extra_fields:
        writer.uint32(field_number, value)
    return writer.bytes()


def encode_set_photography_options(option_types, photography_options=None,
                                   function_mode=None):
    """Encode SetPhotographyOptions (option_types=1, value=2, function_mode=3).

    `photography_options=None` omits field 2 entirely; `b""` emits it as a
    present-but-empty sub-message (`12 00`), which is what "change the
    resolution" with no value attached actually looks like on the wire.
    """
    writer = PbWriter()
    writer.repeated_uint32(1, option_types)
    if photography_options is not None:
        writer.message(2, photography_options)
    if function_mode is not None:
        writer.enum(3, function_mode)
    return writer.bytes()


def set_video_mode(record_resolution, function_mode=FM_NORMAL_VIDEO,
                   emit_default_zero=False):
    """Build the full frame for "switch the camera to this video mode"."""
    options = encode_photography_options(
        record_resolution=record_resolution,
        emit_default_zero=emit_default_zero,
    )
    payload = encode_set_photography_options(
        option_types=[OPT_RECORD_RESOLUTION],
        photography_options=options,
        function_mode=function_mode,
    )
    return build_frame(CMD_SET_PHOTOGRAPHY_OPTIONS, payload)


def encode_start_capture(mode=CAPTURE_MODE_VIDEO):
    return build_frame(CMD_START_CAPTURE, PbWriter().enum(1, mode).bytes())


def encode_stop_capture(mode=CAPTURE_MODE_VIDEO):
    return build_frame(CMD_STOP_CAPTURE, PbWriter().enum(2, mode).bytes())


def describe_frame(frame):
    """Return a human-readable dict describing a command frame."""
    frame = bytes(frame)
    if len(frame) < HEADER_LEN:
        raise CodecError("frame shorter than the %d byte header" % HEADER_LEN)
    declared = struct.unpack_from("<H", frame, 0)[0]
    out = {
        "declared_length": declared,
        "actual_length": len(frame),
        "frame_type": frame[4],
        "command_id": frame[7],
        "command_name": COMMAND_NAMES.get(frame[7], "unknown(0x%02x)" % frame[7]),
        "sequence": struct.unpack_from("<H", frame, SEQ_POS)[0],
        "payload": frame[PROTOBUF_POS:],
    }
    if declared != len(frame):
        out["length_mismatch"] = True
    if out["payload"]:
        try:
            out["fields"] = decode_nested(out["payload"])
        except CodecError as exc:
            out["decode_error"] = str(exc)
    return out


def describe_set_photography_options(payload):
    """Interpret a SetPhotographyOptions payload as (options, resolution, mode)."""
    result = {"option_types": [], "function_mode": None,
              "record_resolution": None, "present": False}
    for field_number, wire_type, value in iter_fields(payload):
        if field_number == 1:
            # Accept both the packed form the app uses and the unpacked one.
            if wire_type == WIRE_LEN:
                result["option_types"].extend(iter_packed_varints(value))
            else:
                result["option_types"].append(value)
        elif field_number == 2:
            result["present"] = True
            for sub_number, _sub_wire, sub_value in iter_fields(value):
                if sub_number == 31:
                    result["record_resolution"] = sub_value
                else:
                    result.setdefault("other_options", []).append(
                        (sub_number, PHOTOGRAPHY_OPTION_FIELDS.get(sub_number, "?"), sub_value))
        elif field_number == 3:
            result["function_mode"] = value
    return result


def describe_video_mode_frame(frame):
    """Summarise a video-mode command: what the camera is actually being told."""
    info = describe_frame(frame)
    payload = info.get("payload", b"")
    if not payload:
        info["intent"] = "no payload"
        return info
    described = describe_set_photography_options(payload)
    resolution = described["record_resolution"]
    info["option_types"] = described["option_types"]
    info["record_resolution"] = resolution
    info["function_mode"] = described["function_mode"]
    info["function_mode_name"] = FUNCTION_MODE_NAMES.get(described["function_mode"])
    if resolution is None:
        info["resolution_name"] = "absent (proto3 default 0 = %s)" % RESOLUTION_NAMES[RES_3840_1920P30]
    else:
        info["resolution_name"] = RESOLUTION_NAMES.get(resolution, "unknown(%d)" % resolution)
    return info


def to_hex(data, separator=" "):
    return separator.join("%02x" % b for b in data)
