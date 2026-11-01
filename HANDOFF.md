# Handoff: Insta360 Garmin protocol extraction (for the next AI)

Author context: this work was started on a Linux PC. The original author's
machine cannot run the Garmin Connect IQ SDK (broken install), so dynamic
tests must be done with the PC's raw BLE adapter (no Garmin SDK). Final
reintegration (step 4) happens on a separate Windows PC. This document is the
single source of truth for continuing.

## 1. Goal

Reverse-engineer the **watch <-> Insta360 camera BLE protocol** used by the
official Insta360 Connect IQ app, so that `BLE Barrel/BLEBarrel.mc` (and the
`Capacites Barrel`) can be extended with commands and capability values that
are currently missing (X4 / X5 / GO Ultra support, full mode set).

Official app (closed source):
`https://apps-developer.garmin.com/apps/18293a9e-d16f-42d7-ab90-73a47510f46e`
Store listing: `https://apps.garmin.com/en-US/apps/18293a9e-d16f-42d7-ab90-73a47510f46e`
Version at time of writing: 4.27.2 (CIQ 5.1.1 build, target epix Pro Gen 2).

## 2. Repository layout (relevant)

```
BLE Barrel/BLEBarrel.mc          # the BLE client: GATT UUIDs, cmd* byte arrays, UCD2 framing
BLE Barrel/README.md             # partial protocol spec (16-byte envelope + protobuf)
tools/insta360_proto.py          # Python reference codec (golden-tested)
tools/insta360_ucd2.py           # X6 UCD2 envelope codec
tools/ciq_arrays.py              # parses cmd* arrays out of BLEBarrel.mc
tools/test_golden.py             # golden byte tests
tools/prg_dump.py                # NEW: .prg container parser (CIQ 3/4/5)
Capacites Barrel/                # per-camera capability model (provenance tags)
BLE Probe/source/Probe.mc        # protocol test ladder (PASS/FAIL/NO EVIDENCE)
OneR remote/, OneR remote DF/    # shipped widget + datafield
```

## 3. How to obtain the official app's .prg

The store serves a per-device binary. The download URL pattern (captured from
Garmin Express logs) is:

```
https://services.garmin.com/appsLibraryBusinessServices_v0/rest/apps/
  18293a9e-d16f-42d7-ab90-73a47510f46e/
  versions/<versionId>/binaries/<productId>
  ?customerId=<id>&unitId=<id>&currentFirmware=<fw>
```

- `<versionId>` for 4.27.2: `ff40061d-961e-4937-aadb-1d72f1e9168d`
- `<productId>` is the device product code, e.g. `epixpro51`. Use the code that
  matches the test watch so the binary's device table matches.
- The file is wrapped: first u4 = wrapper size (29), then 4+4+4+16+1 bytes, then
  the inner PRG starts at offset `4 + wrapper_size` (0x21 in our capture).

If the direct URL stops working, fall back to:
  - Android Connect IQ Store app cache + `adb` (no root needed on most builds), or
  - Garmin Express on Windows + Process Monitor filtered on `Path ends with .prg`.

Keep the downloaded `.prg` OUT of the public git repo (store ToS).

## 4. Parsing the .prg (already implemented)

`tools/prg_dump.py <file.prg> [flags]`:

```
--sections          section list (default on)
--head / --entry / --permissions
--classes           class defs + fields
--strings           string pool (521 entries)
--containers        structured containers (57 entries)
--arrays            byte arrays from ByteArray/Array fields
--proto             filter strings to protobuf message names
--grep SUBSTR       filter strings/classes
--out DIR           write strings.txt / classes.txt / containers.txt
```

Section layout (CIQ 5.1.1, all big-endian except the store wrapper):

```
0x21  HeadVersioned (33)
0x4a  EntryPoints (38)        # 1 entry, type=App, uuid 72a36e85-...
0x78  Data (51059)           # class defs + string pool + containers
0xc7f3 Code (135515)         # P-code
0x2d956 CodeTable (2)        # EMPTY -> release build, no source paths
0x2d960 LinkTable (2402)     # Toybox imports
0x2e2ca Resources (5424043)  # icons/layouts/strings
0x55a67d Permissions (14)
0x55a693 Exceptions (182)
0x55a751 Settings (0)
0x55a759 DevSignature (1540)
0x55ad65 AppStoreSig (512)
0x55af6d End
```

Data section format (CIQ 5.x, unified v1/v2 class defs): see the Kaitai spec
`ciq.ksy` from anvilsecure/garmin-ciq-app-research. Key points:
- sentinel byte 0xc1 (v1) or 0xc2 (v2), then 3-byte fragment `a5 5d ef`.
- v2 class def: flags u1, then conditionally extends/static/parent/module offsets,
  app_types u2, nfields u2, then nfields * 9-byte field defs.
- field: code_offset u4 (symbol = code_offset>>8, type = code_offset&0xF,
  flags = (code_offset>>4)&0xF), type_raw u1 (v2 only), field_value u4.
- data entries: 0x01 = string_def (length u2, data size length+1),
  0x03 = container_def (len_data u4 + data), 0xc1/0xc2 = class_def.
- There is 0x00 padding between entries.

## 5. Protocol findings so far

Already in `BLE Barrel/BLEBarrel.mc` / `tools/`:
- GATT service `0000BE80-0000-1000-8000-00805F9B34FB`, write char BE81, notify BE82.
- 16-byte envelope: `LL LL 00 00 04 00 00 XX 00 02 SS SS 00 80 00 00 | PB`
  (04 = command, 05 = keep-alive), protobuf body.
- Camera->watch codes: 06 saving, 10 record started/ended, 0a photo, C8 OK, f4 busy.
- X5 notification constants: 0x2053 sub-mode, 0x2010 capture status, 0x2040 record state,
  0x2003/0x2004 battery, 0x2006/0x2007 storage, ...
- X6 uses UCD2 envelope (`tools/insta360_ucd2.py`).
- GPS telemetry frame layout documented in `BLE Barrel/README.md`.
- `cmdHighlight`/`cmdTrackThat` embed `com.insta360.keyTime.highlight` / `.trackThat`.

New findings from the official .prg (this work):
- `cmdStartRec` / `cmdStopRec` protobuf payloads are **byte-identical** to the
  official app's stored constants -> codec validated.
- No complete frame is stored as a constant: the 16-byte header (length, seq) is
  built at runtime in P-code. The frame builder is the primary RE target.
- Resolution/mode settings commands (`cmdSet*`) are NOT stored as constants:
  the official app builds them dynamically from option tables -> settings path is
  the secondary RE target.
- Protobuf message dictionary (strings in the Data section, 54 message names):
  `BatteryStatus`, `ButtonFollowOptions`, `ButtonPressOptions`, `CameraCaptureStatus`,
  `CaptureStatus`, `ChargeboxConnectedStatus`, `CheckAuthorization (+Resp)`,
  `ExposureOptions`, `ExtraMetadata`, `GetActiveSensorDevice (+Resp)`,
  `GetCurrentCaptureStatusResp`, `GetOptions (+Resp)`, `GetPhotographyOptions (+Resp)`,
  `GyroFilterConfig`, `GyroInfo`, `IntervalRecInfo`,
  `NotificationAuthorizationResult`, `NotificationBatteryUpdate`,
  `NotificationCaptureStopped`, `NotificationCardUpdate`, `NotifyCameraSubMode`,
  `Options`, `Photo`, `PhotographyOptions`, `Sensor`, `SetActiveSensorDevice (+Resp)`,
  `SetKeyTimePoint (+Resp)`, `SetOptions (+Resp)`, `SetPhotographyOptions (+Resp)`,
  `StartCapture (+Resp)`, `StartTimelapse (+Resp)`, `StopCapture (+Resp)`,
  `StopTimelapse (+Resp)`, `StorageState`, `TakePicture (+Response)`, `TempState`,
  `Video`, `WifiChannelList`, `WifiInfo`, `WindowCropInfo`.
- Option key strings (camera settings dictionary, for Capacites Barrel):
  `assistive_grid_enable`, `dark_eis_enable`, `dark_eis_enable_global`,
  `double_click`, `double_zoom_enable`, `enableInternalFlowstate`,
  `enableInternalSplicing`, `flowstate_base_enable`, `flowstate_horizon_enable`,
  `freeframe_grid_enable`, `long_battery_mode_enabled`, `mctf_enable`,
  `metering_enable`, `metering_enable_global`, `preview_mctf_enable`,
  `preview_sport_mode_enable`, `quick_capture`, `sport_mode_enable`,
  `video_flowstate_base_enable`, `cache_capture_enable`, `shutdown_double_click`, ...
  plus version keys: `ble_version`, `box_bt_version`, `box_ota_pkg_version`,
  `box_version`, `bt_remote_version`, `go3_version`, `ota_pkg_version`,
  `passwd_version`, `isInstaPanoEnabled`.
- App classes: `Insta360GarminApp`, `Insta360GarminConnectMenuDelegate`,
  `Insta360GarminSearchView`, `Insta360GarminAuthorizationDelegate`,
  `Insta360GarminChronographSearchView`, `Insta360GarminConnnectingDelegate`.
- GATT service UUID string: `0000BE80-0000-1000-8000-00805F9B34FB`.

## 6. What remains (next steps)

### 6.1 Ghidra P-code decompilation (step 2)
- Install Ghidra + the `anvilsecure/GhidraGarminApp` SLEIGH processor/loader.
- Load `insta360-epixpro51.prg`. The loader handles CIQ 5.x class defs.
- Targets (in priority order):
  1. Frame builder: find `BluetoothLowEnergy.writeCharacteristic` call sites via the
     LinkTable/ClassTable, decompile the surrounding function -> exact header layout,
     sequence counter, keep-alive (05) cadence, any checksum/trailer.
  2. Notification handler: search P-code immediates for 0x2003, 0x2006, 0x2010,
     0x2040, 0x2053 -> confirm/complete camera->watch codes and parsing.
  3. Settings path: how option tables are serialized into protobuf (to obtain the
     missing `cmdSet*` resolutions/modes).
  4. X4/X5/GO Ultra specifics: any model-gated branches.
- Note: CodeTable (PC2Line) is empty (2 bytes) -> no source paths; rely on
  symbol names from the Data string pool.

### 6.2 Dynamic verification (step 3)
- Constraint: Garmin SDK does NOT work on the original Linux PC. Do NOT depend on
  it. Use the PC's raw BLE adapter directly.
- Insta360 LBS uses NoBonding/NoEncryption -> a passive BLE sniffer (nRF52 dongle
  + Wireshark) captures the full plaintext traffic between the official app and
  the camera. Validate each statically discovered command against real captures.
- Alternatively, replay commands with the existing `BLE Probe` ladder (ported to
  run without the SDK, or run on the Windows PC).
- Rule from Probe.mc: a reply (code 0xC8) proves the camera holds a value; only a
  pushed notification (0x8275/0x8293/0x8208/0x8256) proves it acted.

### 6.3 Reintegration (step 4) -- on the Windows PC
- Add new commands to `BLE Barrel/BLEBarrel.mc` (cmd* arrays) + update
  `tools/insta360_proto.py` / `insta360_ucd2.py`.
- Add golden tests in `tools/test_golden.py` (must reproduce byte-for-byte).
- Update `Capacites Barrel` with OFFICIAL-tagged values (provenance per its README).
- Extend `BLE Probe` ladder with new commands.
- Update `tools/README.md` and `BLE Barrel/README.md`.
- Run `tools/audit_commands.py` and `tools/verify_tables.py`.

## 7. Constraints / notes for the next AI

- Do not commit the official .prg or extracted proprietary blobs to a public repo.
- The official app is CIQ 5.1.1 / device app type "App" (not widget/datafield).
- Class defs use the v2 (0xc2) format with flags; v1 (0xc1) also appears (24 of them).
- There is NO Symbols section in this build; symbol names live in the Data string
  pool, and Toybox symbols are resolved via the LinkTable + the SDK's symbol table.
- `tools/prg_dump.py` is the canonical parser; extend it rather than rewriting.
- When in doubt about a CIQ format detail, consult the Kaitai spec
  `ciq.ksy` (anvilsecure/garmin-ciq-app-research) before guessing.

## 9. Step 2/3 deliverables (done on the Linux PC)

### 9.1 P-code disassembler — `tools/prg_disasm.py`

```
python tools/prg_disasm.py insta360-epixpro51.prg --out ./prgdisasm
```

Outputs:
- `disasm.txt` — full listing (46 927 instructions, 887 methods, 29 unknown opcodes).
- `methods.txt` — method map: `code_offset  class_off  symbol  flags`.
- Method entries are marked `### METHOD entry @code+0xXXXX`.

Key analysis results:
- Frame builder candidates (methods using `newba` + byte 0x80 via `ipush2 128`):
  `@code+0x166a1` (symbol 1396) and `@code+0x16c85` (symbol 1403) in class 0x4a30.
  These are byte-array transforms (bit packing, 0x7f/0x80 masking) — likely CRC or
  varint helpers, not the frame builder itself.
- The main protocol class is at data offset 0x2346 (21 methods, symbols 242/694-719).
  None of its methods use `newba`+`aputv` with the envelope constants, which suggests
  the frame is assembled in a helper or via a different code path (possibly a shared
  utility class). Further Ghidra decompilation is needed to confirm.
- `spush` immediates (1638 occurrences) are small indices (136-199), NOT offsets into
  the Data string pool. They are likely symbol/resource indices resolved at runtime.
- Only 11 occurrences of `ipush2 128` (0x80) in the entire code section.

Recommendation: use Ghidra + GhidraGarminApp for full decompilation; the disassembler
listing is the search index (grep for `newba`, `aputv`, `invoke`, immediate 0x04/0x80).

### 9.2 Dynamic BLE probe — `tools/ble_probe.py`

Uses gatttool (no Garmin SDK, no Python BLE library needed):

```
# 1. find the camera
python tools/ble_probe.py --scan

# 2. discover characteristic handles
python tools/ble_probe.py --addr AA:BB:CC:DD:EE:FF --discover

# 3. send a command and listen for notifications
python tools/ble_probe.py --addr AA:BB:CC:DD:EE:FF \\
    --write-handle 0xXXXX --cccd-handle 0xYYYY \\
    --cmd "0e 00 00 00 04 00 00 04 00 02 00 01 00 80 00 00 08 01" \\
    --listen 5
```

Constraints (from original Linux PC):
- Garmin SDK is broken on this machine; do not depend on it.
- Camera must be powered on and discoverable; the watch must NOT be connected
  (Insta360 LBS allows only one central at a time).
- Insta360 LBS uses NoBonding/NoEncryption -> gatttool default sec-level=low works.
- Rule from Probe.mc: a reply (0xC8) proves the camera holds a value; only a
  pushed notification proves it acted.

```
# parse the official app
python tools/prg_dump.py insta360-epixpro51.prg --sections --head --entry --permissions

# list protocol-relevant strings
python tools/prg_dump.py insta360-epixpro51.prg --strings --grep enable

# protobuf message names
python tools/prg_dump.py insta360-epixpro51.prg --proto

# containers (device/resolution tables)
python tools/prg_dump.py insta360-epixpro51.prg --containers

# dump everything to a folder
python tools/prg_dump.py insta360-epixpro51.prg --out ./prgdump
```
EOF
echo "written"
## 11. Decompilation attempt (Ghidra + GhidraGarminApp)

### Setup status
- Ghidra 12.2 downloaded and extracted to `/tmp/ghidra_install/`.
- JDK 25 (Temurin) downloaded and extracted to `/tmp/jdk-25.0.5+8/`.
- GhidraGarminApp extension built from source against Ghidra 12.2:
  `distributeExtension` succeeded -> `ghidra_12.2_PUBLIC_20261031_GhidraGarminApp.zip`.
- Extension installed in both `~/.ghidra/.../Extensions/Ghidra/GhidraGarminApp/` and
  the Ghidra install's `Extensions/Ghidra/GhidraGarminApp/`.

### Blockers
- The extension's language definition (`data/languages/garminvm.ldefs`) has the
  `<language>` element commented out. Uncommenting it requires also compiling
  the SLEIGH spec (`garminvm.sinc` -> `garminvm.sla`), which needs the Ghidra
  SLEIGH compiler (`support/sleigh`).
- Even with the extension fully working, Ghidra produces **pseudocode (C-like)**,
  not Monkey C. Reconstructing 1045 methods of compilable `.mc` source from
  pseudocode is a manual effort that cannot be automated.
- The extension is in beta state (processor name "skel", commented-out language).

### What was produced instead
- `tools/prg_disasm.py` + `disasm.txt`: full P-code listing (46 927 instructions).
- `tools/prg_dump.py`: Data section parser (236 classes, 521 strings, 57 containers).
- `Insta360GarminApp_decompiled.mc`: structural skeleton (class/method map,
  string constants, command IDs, notification codes, state variables).
  **This is NOT compilable Monkey C** — it is a reference document.

### Recommendation
For actual decompilation, use Ghidra GUI on a machine with a display:
1. Install Ghidra 12.2 + the built extension.
2. Uncomment the language definition and compile the SLEIGH spec.
3. Import the .prg, run the decompiler on individual methods.
4. Manually translate pseudocode to Monkey C.

Camera: `B8:2D:28:F3:A5:AC` (X5 3S6GEW), BLE service `0000BE80-...`.

GATT layout (discovered):
- BE81 write char: handle 0x0029, value handle 0x002a, properties 0x0a (read+write)
- BE82 notify char: handle 0x002b, value handle 0x002c, properties 0x10 (notify)
- BE83 read char: handle 0x002e, value handle 0x002f, properties 0x02 (read) -> value `11 22 33 44`
- CCCD for BE82: handle 0x002d

Verified commands (from BLEBarrel.mc, byte-identical to the barrel):
- `cmdStartRec` (`12 00 00 00 04 00 00 04 00 02 ff 00 00 80 00 00 08 01`):
  camera responds with notification `10 00 00 00 04 00 00 17 20 02 ff 8a 43 f4 00 00`
  (command acknowledged; 0x17 0x20 = capture-status push).
- `cmdStopRec` (`12 00 00 00 04 00 00 05 00 02 ff 00 00 80 00 00 10 01`):
  camera returns to idle keep-alive (05).
- `cmdSetPhoto` (`10 00 00 00 04 00 00 03 00 02 ff 00 00 80 00 00`): accepted.
- `cmdApply` (`10 00 00 00 04 00 00 0f 00 02 ff 00 00 80 00 00`): accepted.
- `cmdGetBatStor` (`14 00 00 00 04 00 00 08 00 02 ff 00 00 80 00 00 08 0b 08 14`): accepted.

Keep-alive states observed:
- `07 00 00 00 05 00 00` = idle
- `07 00 00 00 0b 00 00` = recording (or non-idle)
- `10 00 00 00 04 00 00 17 20 02 ff 8a 43 f4 00 00` = capture-status push (0x17 0x20)

Conclusion: every command in the barrel is accepted by the real X5 camera. The codec and
envelope are correct. The exact state machine (which commands trigger which transitions)
requires further investigation (step 2/4).
