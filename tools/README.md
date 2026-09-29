# tools

Host-side tooling for the Insta360 remote. Not part of the Connect IQ build
and not shipped to the watch. Plain Python 3, no dependencies, no `protoc`.

## Why

The camera command payloads live in `BLE Barrel/BLEBarrel.mc` as hard-coded
byte arrays. Reverse-engineering them by hand is slow and error-prone, and the
same 5.7K/8K values get copy-pasted between the watch app, the data field and
`Modes.txt`. These tools decode the shipped arrays, re-encode them, and prove
the two agree byte for byte, so a payload can be reasoned about as a value
instead of a hex blob.

## Files

| File | Purpose |
| --- | --- |
| `insta360_proto.py` | Frame layout + protobuf encoder/decoder. No repo knowledge. |
| `ciq_arrays.py` | Reads the `var cmdX = [...]b;` arrays straight out of `BLEBarrel.mc`. |
| `test_golden.py` | Golden-byte tests: the encoder must reproduce every shipped command. |
| `audit_commands.py` | Compares each command's payload against what its label claims. |

`ciq_arrays.py` deliberately parses the `.mc` source instead of holding a copy
of the bytes, so the tests cannot drift away from what actually ships.

## Usage

```
python tools/test_golden.py      # 17 tests, all must pass
python tools/audit_commands.py   # human-readable report + candidate fixes
```

`audit_commands.py` always exits 0: a divergence between a label and its
payload is a finding to report, not a test failure.

## Protocol summary

A command is a 16-byte header followed by a protobuf payload:

```
offset  size  meaning
0..1    2     total frame length, uint16 little-endian
2..3    2     0x0000
4       1     0x04, frame type
5..6    2     0x0000
7       1     command id (MessageCode)
8..9    2     0x0002
10..11  2     sequence number, uint16 little-endian
12..13  2     0x8000
14..15  2     0x0000
16..    n     protobuf payload
```

Byte 10 is overwritten with the sequence number on every send; the arrays in
`BLEBarrel.mc` therefore ship with `ff 00` in that position. Frames longer than
20 bytes are split into 20-byte writes.

Video mode changes are `SetPhotographyOptions` (command 9):

```
field 1  repeated PhotographyOptionType option_types   (packed)
field 2  PhotographyOptions value
field 3  FunctionMode function_mode
```

and only the resolution is ever set, at `PhotographyOptions.record_resolution`
(field 31).

## Two things that bite

**Repeated fields are packed.** `option_types` travels as `0a 01 1f`
(length-delimited), not `08 1f`. An unpacked encoding still parses, but it will
never match the golden bytes.

**proto3 cannot express "set resolution to 0" canonically.** 0 is the default
of `record_resolution` (`RES_3840_1920P30`, 4K@30), so a canonical writer emits
nothing. The shipped `cmdSet4k30` sends an empty `PhotographyOptions` and relies
on the camera reading the absent field as its default. `emit_default_zero=True`
writes the zero out anyway, which is legal on the wire but non-canonical, and
whether the camera honours it is unverified.

## Current findings

`audit_commands.py` reports two label/payload mismatches, both left unfixed
because each needs a hardware check:

- `cmdSetHDR` asks for 3840x1920@20 in `FUNCTION_MODE_NORMAL_VIDEO`, so it is
  not an HDR mode at all. The HDR video mode is
  `FUNCTION_MODE_HDR_VIDEO` (9).
- `cmdSet4k30` depends on the proto3 default described above.

`cmdSet8k30` looks wrong at a glance (167 is not a wide resolution) but is
correct: 3840x3840 is the per-eye half of a 7680x3840 8K 360 frame.
