"""UCD2 codec, the envelope an X6 speaks.

Reference: Ripwords/insta360-luna-ultra-desktop, src-tauri/src/luna.rs. That
implementation was itself ported from diamondfsd/luna-ai-cut
(insta360TcpProtocol.ts) and carries a captured GET_OPTIONS frame as a test
vector, so the layout below is checked against bytes a real camera sent rather
than against a specification.

Frame layout (all little endian):

    0..3    magic "UCD2"
    4       version, constant 0x01
    5       flags,  constant 0x0c
    6       frame type: 0x01 MEDIA, 0x04 FILE, 0x05 STREAM
    7       sequence
    8..11   body length, uint32
    12..    body
    last 4  trailer, a checksum on FILE frames

Total length is 12 + declared + 4.

A FILE body is a fixed 9 byte envelope:

    code:u16 | 0x02 | request_id:u16 | 0x8000:u32 | payload

Byte 5 is NOT a length and byte 6 is NOT an opcode. Both were read that way from
the X6 log before the real layout was found, and both readings were wrong: every
captured notification is exactly 20 bytes, so size - 8 == 12 == 0x0c made the
arithmetic agree with a length field that is in fact constant.
"""

MAGIC = b"UCD2"
VERSION = 0x01
FLAGS = 0x0C

TYPE_MEDIA = 0x01
TYPE_FILE = 0x04
TYPE_STREAM = 0x05

HEADER_LEN = 8
LEN_POS = 8
BODY_POS = 12
TRAILER_LEN = 4
CRC_POLY = 0x04C11DB7

FILE_MARKER = 0x02
FILE_FLAGS = 0x8000

CMD_TAKE_PICTURE = 3
CMD_START_CAPTURE = 4
CMD_STOP_CAPTURE = 5
CMD_SET_OPTIONS = 7
CMD_GET_OPTIONS = 8
CMD_GET_CAPTURE_STATUS = 15

FRAME_LEN_OVERHEAD = HEADER_LEN + 4 + TRAILER_LEN  # 16


class Ucd2Error(Exception):
    pass


def _build_table():
    table = []
    for i in range(256):
        value = (i << 24) & 0xFFFFFFFF
        for _ in range(8):
            if value & 0x80000000:
                value = ((value << 1) ^ CRC_POLY) & 0xFFFFFFFF
            else:
                value = (value << 1) & 0xFFFFFFFF
        table.append(value)
    return table


_TABLE = _build_table()


def checksum(data):
    """Insta360's CRC-32 variant.

    Poly 0x04C11DB7, init 0xffffffff, no final xor. Each byte is XORed into the
    LOW byte and followed by four MSB table rounds. This is not any standard
    CRC-32 and must not be replaced with one.
    """
    crc = 0xFFFFFFFF
    for byte in data:
        crc ^= byte
        for _ in range(4):
            crc = ((crc << 8) & 0xFFFFFFFF) ^ _TABLE[(crc >> 24) & 0xFF]
    return crc


def build_ucd2(frame_type, seq, payload):
    return (MAGIC + bytes([VERSION, FLAGS, frame_type, seq & 0xFF])
            + payload)


def build_file_command(seq, code, request_id, body=b"", trailer=True):
    """A complete FILE frame, checksum appended.

    With an empty payload the body is 9 bytes and the frame is 25, which is
    longer than one BLE notification.
    """
    raw = (code.to_bytes(2, "little") + bytes([FILE_MARKER])
           + request_id.to_bytes(2, "little")
           + FILE_FLAGS.to_bytes(4, "little") + body)
    frame = build_ucd2(TYPE_FILE, seq, len(raw).to_bytes(4, "little") + raw)
    if trailer:
        frame += checksum(frame).to_bytes(4, "little")
    return frame


def frame_length(declared):
    return FRAME_LEN_OVERHEAD + declared


def declared_length(frame):
    if len(frame) < BODY_POS:
        raise Ucd2Error("frame shorter than its length field")
    return int.from_bytes(frame[LEN_POS:BODY_POS], "little")


def is_ucd2(frame):
    return len(frame) >= HEADER_LEN and frame[:4] == MAGIC


def split_notifications(frame, limit=20):
    """How a frame reaches a watch: 20 byte notifications, tail shorter."""
    return [frame[i:i + limit] for i in range(0, len(frame), limit)]


class Reassembler:
    """Rebuilds frames from notifications.

    A 25 byte frame arrives as 20 bytes then 5. The tail carries no magic, so it
    is recognised by there being a frame in progress that is not yet full. A
    frame whose tail never arrives stays incomplete and is reported rather than
    decoded as if whole.
    """

    def __init__(self):
        self.buf = b""
        self.want = 0
        self.frame_type = 0
        self.seq = 0

    @property
    def pending(self):
        return self.want > 0 and len(self.buf) < self.want

    def feed(self, fragment):
        """Returns the frames completed by this fragment."""
        done = []
        if is_ucd2(fragment):
            self.buf = bytes(fragment)
            self.frame_type = fragment[6]
            self.seq = fragment[7]
            self.want = frame_length(declared_length(fragment))
        elif self.pending:
            self.buf += bytes(fragment)
        else:
            return done
        if len(self.buf) > self.want:
            self.buf = self.buf[:self.want]
        if len(self.buf) >= self.want:
            done.append(self.buf)
            self.buf = b""
            self.want = 0
        return done


def describe_frame(frame):
    """Decodes a reassembled frame into named fields."""
    if not is_ucd2(frame):
        raise Ucd2Error("not a UCD2 frame")
    declared = declared_length(frame)
    want = frame_length(declared)
    info = {
        "version": frame[4],
        "flags": frame[5],
        "type": frame[6],
        "seq": frame[7],
        "declared": declared,
        "expected_len": want,
        "complete": len(frame) >= want,
        "trailer_ok": None,
    }
    if frame[6] == TYPE_FILE and len(frame) >= BODY_POS:
        body = frame[BODY_POS:]
        info["code"] = int.from_bytes(body[0:2], "little")
        info["marker"] = body[2]
        info["request_id"] = int.from_bytes(body[3:5], "little")
        info["file_flags"] = int.from_bytes(body[5:9], "little")
        info["payload"] = body[9:]
    if info["complete"] and len(frame) >= want:
        got = int.from_bytes(frame[want - TRAILER_LEN:want], "little")
        info["trailer_ok"] = got == checksum(frame[:want - TRAILER_LEN])
    return info