# Protocol extraction from `Insta360_v2.34.5_526204.apk`

Source APK: `Insta360_v2.34.5_526204.apk` (package `com.arashivision.insta360akiko`,
version 2.34.5, versionCode 526204, minSdk 28, targetSdk 35).

Companion raw extractions live in `tools/apk_extract/`:
`phone_commands.txt`, `camera_notifs.txt`, `factory_cmds.txt`,
`messages.txt`, `uuids.txt`, `enums-apk-2026.txt`.

## 1. Methodology and results

The APK is protected by the **Ashield** packer: `AndroidManifest.xml` declares
`android:name="com.ashield.Stub"`, `classes.dex` is a 138.7 MB stub of only 4
classes, and the real bytecode is decrypted at runtime into anonymous `rwxp`
mappings. Consequently:

- Static decompilation (`jadx` on `classes.dex`) yields only `com.ashield.Stub`.
- Strings, enum constant names, UUIDs, asset tables are recoverable from the
  stub DEX string pool and assets (see sections 4–7).
- **Numeric IDs recovered**: the device was rooted (Magisk, unlocked bootloader)
  and the decrypted DEX was dumped from process memory
  (`/proc/<pid>/mem`, 16 DEX files, ~162 MB total) and decompiled with `jadx`.
  This yielded the full `insta360.messages.MessageCode` enum (539 entries) with
  verified (name, number) pairs, plus `FunctionMode` (69) and
  `PhotographyOptionType` (103). See `tools/apk_extract/message_code_map.txt`,
  `function_mode_map.txt`, `photo_opt_type_map.txt`.

## 2. GATT topology (from DEX string pool)

Primary camera control service (matches the existing repo findings):

| UUID | Role |
|---|---|
| `0000be80-0000-1000-8000-00805f9b34fb` | Service (Insta360 LBS) |
| `0000be81-...` (char) | Write (command) — handle 0x002A |
| `0000be82-...` (char) | Notify (status) — handle 0x002C |
| `0000be83-...` (char) | Read — returns `11 22 33 44` |

Additional services found in the APK (companion / remote-control / UART-style):

| UUID | Notes |
|---|---|
| `0000ce80/ce81/ce82/ce83-...` | Secondary service (4 chars) — likely detachable-screen / companion |
| `0000fff0/fff1/fff2/fff3-...` | Generic BLE UART-style service |
| `0000ffd0..ffd5,ffd8-...` | Vendor-specific (6 chars) |
| `0000ae00/ae01/ae02-...` | Vendor-specific (3 chars) |
| `00001101,1105,1108,110a..1134-...` | Standard Bluetooth profiles (SPP, OBEX, …) |

## 3. Frame / envelope layout (validated on X5)

Unchanged from the existing repo (`BLE Barrel/README.md`,
`tools/insta360_proto.py`). Re-stated here for completeness:

```
offset  size  meaning
0..1    2     total frame length, uint16 little-endian (= the whole frame,
              header included; the reassembly target, called `want` in the tools)
2..3    2     0x0000
4       1     frame type: 0x04 = command, 0x05 = keep-alive
5..6    2     0x0000
7..8    2     command id (MessageCode), uint16 little-endian
9       1     0x02 marker
10..11  2     sequence number, uint16 little-endian (0xFF default)
12..13  2     0x8000
14..15  2     0x0000
16..    n     protobuf payload
```

Corrected 2026-11-04 against the raw wire captures (`rea/artefacts/ble-*.log`,
17 792 RX + 17 305 TX records) rather than against the Java layer:

- There is **no `55 AA` magic** anywhere in this envelope; the frame starts at
  its own length. The 16-octet header is fixed and the payload starts at 16.
- The command id is **16 bits**, not one byte: the X5 pushes carry `0x2017`,
  `0x2040`, `0x2053`, i.e. `[7]=0x17 [8]=0x20`. Reading only byte 7 makes every
  push look like a small code and hides the `0x0190` (400) refusal, which is
  `[7]=0x90 [8]=0x01`.
- `want` is the full frame length including the header, so a 16-octet empty ACK
  announces 16 and a continuation only ends when the sum of received
  notifications reaches that value.

- Camera → app codes: `0x06` saving, `0x10` record started/ended, `0x0a` photo,
  `0xc8` OK, `0xf4` busy.
- Frames longer than 20 bytes are split into 20-byte writes.
- X5 notification constants: `0x2053` sub-mode, `0x2010` capture status,
  `0x2040` record state, `0x2003/0x2004` battery, `0x2006/0x2007` storage.
- X6 uses the UCD2 envelope (`tools/insta360_ucd2.py`).

## 4. Command catalog (MessageCode)

Fully recovered: **539 entries** with verified (name → number) pairs, from the
decrypted DEX (`insta360.messages.MessageCode`). Full table:
`tools/apk_extract/message_code_map.txt`.

Core commands (unchanged since the ONE RS / X4 era):

| # | Name |
|---|---|
| 3 | `PHONE_COMMAND_TAKE_PICTURE` |
| 4 | `PHONE_COMMAND_START_CAPTURE` |
| 5 | `PHONE_COMMAND_STOP_CAPTURE` |
| 7 | `PHONE_COMMAND_SET_OPTIONS` |
| 8 | `PHONE_COMMAND_GET_OPTIONS` |
| 9 | `PHONE_COMMAND_SET_PHOTOGRAPHY_OPTIONS` |
| 10 | `PHONE_COMMAND_GET_PHOTOGRAPHY_OPTIONS` |
| 15 | `PHONE_COMMAND_GET_CURRENT_CAPTURE_STATUS` |
| 53 | `PHONE_COMMAND_UPLOAD_GPS` |
| 60 | `PHONE_COMMAND_SET_KEY_TIME_POINT` |

New in 2.34.5 (now with verified numbers): AI assistant/voice, Airetouch,
cloud storage, playback, tracking/PTZ, quick reader, find-my, multi-host,
webcam, translate, robot mode, interval-rec feedback, drone (FC_*) control,
etc. Examples:
`PHONE_COMMAND_AI_INTENT=20080`, `PHONE_COMMAND_OPEN_TRACKING=20045`,
`PHONE_COMMAND_START_CAMERA_LIVE=20037`,
`PHONE_COMMAND_SET_PTZ_OPTION=20008`, `PHONE_COMMAND_GIMBAL_CONTROL=20066`,
`PHONE_COMMAND_QUICKREADER_CONFIG=20024`, `PHONE_COMMAND_FINDMY_CTRL=20022`.
Full list: `tools/apk_extract/message_code_map.txt`.

## 5. Protobuf message catalog

777 message/enum types under `insta360.messages.*` are referenced by the DEX
string pool (full list: `tools/apk_extract/messages.txt`). Key ones for the
camera control path:

`BatteryStatus`, `ButtonFollowOptions`, `ButtonPressOptions`,
`CameraCaptureStatus`, `CaptureStatus`, `ChargeboxConnectedStatus`,
`CheckAuthorization (+Resp)`, `ExposureOptions`, `ExtraMetadata`,
`GetActiveSensorDevice (+Resp)`, `GetCurrentCaptureStatusResp`,
`GetOptions (+Resp)`, `GetPhotographyOptions (+Resp)`, `GyroFilterConfig`,
`GyroInfo`, `IntervalRecInfo`, `NotificationAuthorizationResult`,
`NotificationBatteryUpdate`, `NotificationCaptureStopped`,
`NotificationCardUpdate`, `NotifyCameraSubMode`, `Options`,
`Photo`, `PhotographyOptions`, `Sensor`, `SetActiveSensorDevice (+Resp)`,
`SetKeyTimePoint (+Resp)`, `SetOptions (+Resp)`,
`SetPhotographyOptions (+Resp)`, `StartCapture (+Resp)`,
`StartTimelapse (+Resp)`, `StopCapture (+Resp)`, `StopTimelapse (+Resp)`,
`StorageState`, `TakePicture (+Response)`, `TempState`, `Video`,
`WifiChannelList`, `WifiInfo`, `WindowCropInfo`.

Field names are consistent with the public proto (366/367 public field names
found verbatim in the DEX string pool); `record_resolution` (field 31 of
`PhotographyOptions`) and `function_mode` remain the key settings fields.

## 6. Enumerations

### 6.1 From `assets/capture/proto.json`
The APK ships a JSON enum table (21 KB) mapping logical names to numeric
values:
- `record_resolution` — 513 entries (`3840_1920_30`→0, `2880_2880_30`→10,
  `3840_1920_20`→21, `3840_3840_30`→167, `7680_4320_30`→154, …).
- `color_mode` — 46 entries (STANDARD…LEICA_3, etc.).
- `exposure_individual`, `photo_size`, FOV, function-mode, …
- Full file: `tools/apk_extract/enums-apk-2026.txt`.

### 6.2 From the decrypted DEX
- `FunctionMode` — 69 entries (NORMAL=0, NORMAL_VIDEO=7, HDR_VIDEO=9,
  HIGH_FRAME_RATE=4, MOBILE_TIMELAPSE=2, INTERVAL_SHOOTING=3,
  INTERVAL_VIDEO=10, TIMESHIFT=24, …). Full table:
  `tools/apk_extract/function_mode_map.txt`.
- `PhotographyOptionType` — 103 entries (RECORD_RESOLUTION=31,
  RECORD_DURATION=29, PHOTO_SIZE_ID=30, COLOR_MODE=35,
  HDR_SWITCH_STATUS=63, …). Full table:
  `tools/apk_extract/photo_opt_type_map.txt`.

Resolution numbers match the existing `tools/insta360_proto.py`
(`RES_3840_1920P30=0`, `RES_2880_2880P30=10`, …).

## 7. Option key strings (camera settings dictionary)

For `Capacites Barrel` provenance, the APK string pool contains the option keys:
`assistive_grid_enable`, `dark_eis_enable`, `dark_eis_enable_global`,
`double_click`, `double_zoom_enable`, `enableInternalFlowstate`,
`enableInternalSplicing`, `flowstate_base_enable`, `flowstate_horizon_enable`,
`freeframe_grid_enable`, `long_battery_mode_enabled`, `mctf_enable`,
`metering_enable`, `metering_enable_global`, `preview_mctf_enable`,
`preview_sport_mode_enable`, `quick_capture`, `sport_mode_enable`,
`video_flowstate_base_enable`, `cache_capture_enable`, `shutdown_double_click`,
plus version keys `ble_version`, `box_bt_version`, `box_ota_pkg_version`,
`box_version`, `bt_remote_version`, `go3_version`, `ota_pkg_version`,
`passwd_version`, `isInstaPanoEnabled`.

## 8. BLE UUIDs summary

Full UUID list: `tools/apk_extract/uuids.txt`.

## 9. Cameras using the UCD2 envelope

The 16-byte envelope (section 3) is used by all cameras **except** those whose
device config carries `"ucd2": true` in
`assets/ins_config_files/phoneApp/<dir>/basic/business.json`:

- **Insta360 X6** (directory `c9`)
- **Insta360 Luna Ultra** (directory `z03`)
- **Insta360 Luna Pro** (directory `z05`)

These use the UCD2 envelope (`tools/insta360_ucd2.py`). The flag is read at
runtime via `DeviceConfigManager.getBasicConfig(cameraType).ucd2`
(`BaseCamera.isUseUcd2FromDeviceName`).

## 10. Remaining gaps:

1. **Field tags for the new messages** (PhotographyOptions has 40+ fields;
   only 31=record_resolution, 29=record_duration, 30=photo_size_id,
   35=color_mode, 63=hdr_switch_status are named). The full field-tag tables
   can be extracted from the same decrypted DEX by parsing the Square Wire
   `ProtoAdapter` classes.
2. **X4 / X5 / GO Ultra gating**: model-specific branches in the encrypted
   code; recoverable via string search + Frida tracing on the rooted device.
3. **UCD2 (X6)**: already covered by `tools/insta360_ucd2.py`.

## 11. Note on the rooted-device extraction

The device was rooted (Magisk) and the decrypted DEX dumped from process
memory (`/proc/<pid>/mem`, 16 DEX files, 162 MB) and decompiled with `jadx`.
This recovered the full `MessageCode` (539), `FunctionMode` (69) and
`PhotographyOptionType` (103) enums with verified numbers, closing the main
gap. The heap dump (`heap.hprof`) and the Frida-server / `wrap.sh` setup
remain available for further tracing.

## 12. Additional findings from the phone's heap dump

A heap dump (`heap.hprof`, 71 MB) captured on the connected device
(Fairphone 4, Android 16) was pulled and parsed (HPROF string records).
It confirms the 249 `PHONE_COMMAND_*` names and adds the full
`FUNCTION_MODE_*` catalog (50 modes) now used by the camera:
`FUNCTION_MODE_NORMAL`, `FUNCTION_MODE_NORMAL_VIDEO`, `FUNCTION_MODE_HDR_VIDEO`,
`FUNCTION_MODE_HIGH_FRAME_RATE`, `FUNCTION_MODE_MOBILE_TIMELAPSE`,
`FUNCTION_MODE_INTERVAL_SHOOTING`, `FUNCTION_MODE_INTERVAL_VIDEO`,
`FUNCTION_MODE_TIMESHIFT`, `FUNCTION_MODE_LOOP_RECORDING_VIDEO`,
`FUNCTION_MODE_PURE_VIDEO`, `FUNCTION_MODE_SLOWMOTION_VIDEO`,
`FUNCTION_MODE_STARLAPSE_IMAGE`, `FUNCTION_MODE_PANORAMA`, `FUNCTION_MODE_PTZ`,
`FUNCTION_MODE_DASH_CAM`, `FUNCTION_MODE_LIVE_STREAM`, etc.
(see `tools/apk_extract/function_modes.txt`).

The heap dump strings do **not** contain the numeric `MessageCode` values nor
the protobuf field tags — those live in the encrypted native code and are not
recoverable without runtime instrumentation. The frida-server / `wrap.sh` /
`libfrida.so` present on the device provide the injection path, but attaching
requires either a debuggable (patched) APK or root, neither of which is
available on this release build.

## 13. Conclusion

The APK's control protocol is the same protobuf-over-BLE scheme already
documented in this repo (16-byte envelope + protobuf body on service
`0000be80-...`). Version 2.34.5 extends the `MessageCode` enum to 539
entries (including drone/FC control) and the `insta360.messages.*` catalog to
777+ types, mostly for AI/voice, playback, tracking/PTZ, cloud and companion
features. The enum (name → number) mappings are now fully recovered via the
rooted device, along with `FunctionMode` (69) and `PhotographyOptionType`
(103). Remaining work: field-tag tables for the new messages and X4/X5/GO
Ultra model gating.

## 14. Live X5 validation (2026-11-04, X5 fw v1.13.21, serial IAHEA2503S6GEW)

The enum numbers recovered above were confirmed against the live camera over
the PC's BLE adapter (artefacts `ble-20261104-105458*` and `ble-20261104-110441*`
under the tools folder's `rea/artefacts/`).

### Battery, two carriers

1. **Push `0x2003` (8195, `CAMERA_NOTIFICATION_BATTERY_UPDATE`)**. The camera
   pushes it when the power source changes (charger in, charger out); nothing
   else was seen to move it. The frame is 24 octets and arrived whole:

   ```
   18 00 00 00 04 00 00 03 20 02 ff 8a 43 f4 00 00 | 0a 06 08 01 10 39 20 00
   ```

   The body is one nested block: field 1 (wire 2) holds the status message —
   field 1 `power_type` (0 = battery, 1 = adapter), field 2 `battery_level`
   (0x39 = 57, the scale is never sent), field 3 `battery_type` (0). A body
   read at the top level misses every value: the nesting is mandatory.
   `0x2004` (8196) is the same family's `CAMERA_NOTIFICATION_BATTERY_LOW`.

2. **GET_OPTIONS (code 8) asking option 11**. The request is the packed
   option list of `PhotographyOptionType`:

   ```
   14 00 00 00 04 00 00 08 00 02 01 00 00 80 00 00 | 0a 02 0b 14
   ```

   field 1 wire 2, two raw varints: 11 (`BATTERY_STATUS`) and 20
   (`STORAGE_STATE`). The answer (code 200, declared 51) echoes the option
   numbers as repeated field-1 varints, then one field-2 block holding the
   option blocks: `5a 06` (field 11, battery, same status message as above),
   `a2 01 12` (field 20, storage state, free/total beyond 32 bit). The wide
   request `0a 06 0b 0f 10 14 1e 30` (options 11, 15, 16, 20, 30, 48) answers
   148 octets and carries serial (`7a`, field 15), uuid (`82 01`, field 16),
   firmware `v1.13.21` (`f2 01`, field 30) and `Insta360 X5` (`82 03`,
   field 48).

   The option ids the reply confirms: 11 battery, 15 serial, 16 uuid, 20
   storage state, 30 firmware revision, 48 camera type. (The barrel's
   `X5_OPT_BATTERY`/`X5_OPT_STORAGE_STATE` constants carry 11 and 20.)

### The MTU ceiling question — measured on the watch (BLE Probe run, 2026-11-04)

The watch run answered it: the CIQ delegate negotiates **ATT MTU 23**, every
notification tops out at **20 octets**, and the camera **truncates an
oversized frame instead of continuing it** — a `declared=66` code-200 answer
crossed as 20 octets and no follow-up chunk ever arrived (the second 66-octet
frame in the log is a re-answer with its own header and a different seq, not
a continuation). Frames of 20 octets or less cross whole (a 16-octet code-200
ack and an 18-octet 0x2010 push both did). On the PC, BlueZ negotiated a wide
MTU, which is why 24- and 148-octet frames crossed in one notification there.

Consequences for the battery on the watch link:

- The **GET_OPTIONS carrier cannot deliver it**: the answer is 51 octets, and
  no defined shape of it is smaller (the option-11 block alone starts at
  octet 22). The code-8 rung on the watch answers `NO EVIDENCE … 20 of 51
  crossed` — a truth about the ceiling, not about the camera.
- The **0x2003 push crosses as 20 of 24**: the fragment ends exactly after
  `0a 06 08 01`, so the **power type (charger in/out) reads off the cut** and
  the level, sitting at octets 21–22, never crosses. The barrel accepts a cut
  nested block, reports the power type it can see, and refuses to guess the
  level (replayed in `tools/x5_battery_parse_sim.py`).
- TX is not the limit: the watch splits its writes into 20-octet chunks and
  the camera reassembles them (23-octet SET frames ran). The limit is only
  the camera's one-notification-per-frame send side.

The window itself, measured across every cut of that run: the camera's
notifications lead with their small varint fields, so a 4-octet body window
carries a whole state when the state is two varints (0x2010 capture start/
stop, 0x2053 photo and video sub-modes, the degenerate 0x2006 card-absent
push) and only option *names* when it is a change list (0x2065), while any
GET answer keeps its values inside a field-2 block starting at octet 22 at
the earliest — no GET can deliver a value under this ceiling, battery
included. The 0x2004 low-battery alarm needs no body: its code sits in the
header, so it decodes at any ceiling.

The official Garmin remote parses `NotificationBatteryUpdate`, which is the
push — at this ceiling it can see only the power source half of it too.

The earlier PC runs had left the question open: at MTU 23 the camera
truncates a declared-51 answer at 20 octets with no follow-up chunk (this is
why the old battery GET attempt read empty), while the BlueZ runs above
negotiated a large MTU and delivered whole frames. The `cmdGetBattery`
request itself, at 20 octets, crosses any ceiling — it is only the answer
that cannot.

A request whose declared length disagrees with the frame is refused with code
`0x190` (400, `BAD_REQUEST`) — the length prefix is `16 + body` as u32 LE.

### Watch-side reading

The official Garmin remote parses `NotificationBatteryUpdate` (see HANDOFF
§prg dictionary), which is the push, not the GET: the push is the shape the
official watch path relies on. `BLE Barrel/BLEBarrel.mc` now decodes both
carriers (`x5ParseBatteryField`, `x5ParseOptionsBattery`), records 0x2003 in
the seen-map (bit 512) and the per-code counts, and exposes
`peekBatteryLevel`/`peekBatteryPowerType`/`peekBatteryArrived`; the BLE Probe
bench gained three rungs (GET opt 11, GET code 8 with the cut/no-cut verdict,
and two push windows around charging-plug changes) that answer the MTU
question on the watch itself.
## 15. Framing Probe: the measurement bench, and what the corpora say before it runs

The MTU question is now carried by its own app, `Framing Probe/`
(`type="app"`, own `BleDelegate`, no `barrels.jungle`). It is standalone on
purpose: the BLE Probe bench routes RX through the barrel pipeline that is
being rewritten, and a transport under construction cannot testify about what
crossed the wire. The probe measures and decides nothing: every notification
is printed before any test is applied to it, with no buffer, no
`size() >= 18` gate, and no reassembly. Its verdict taxonomy is what the rungs
print:

- **A CONTINUATION** – head plus following notifications sum to exactly `want`;
- **A ENTIERE d'un bloc** – `want` arrived in one notification;
- **A DEBORDE** – the sum passed `want` (the `want` read is wrong, not the wire);
- **B TRONCATURE-UNIQUE** – a new head arrived before `want` was reached: the
  rest of the frame never crossed;
- **C TRONCONS-SANS-EN-TETE** – sum < `want` and no head follows: nothing on the
  wire says where a frame ends.

Two offline tools hold the proof that the machine on the watch is the machine
described here, since no Garmin SDK is installed on this PC:

- `tools/mc_check.py` – SDK-free static check of a Monkey C file: brace/paren
  balance with the opening line, symbols used with no visible declaration, and
  double declarations inside one block. Baseline, clean on every `.mc` of the
  repo (`BLE Barrel`, `BLE Probe`, `OneR remote`, `Framing Probe`); it catches
  typos, not types.
- `tools/probe_frame_sim.py` – ports `legacyFrame`, `ucd2Frame`, `ucd2Stamp`,
  `headOf`, `isBeat`, `feed`, `verdictOf` line for line and replays them on the
  recorded streams. `selfTest()` on the watch compares the builders with the
  same observed frames before any radio traffic, so the two paths meet at the
  same assertions.

Replay of the 65 PC sessions (BlueZ negotiated the MTU, so it varies per run):
8927 answers **whole in one notification**, **154 A CONTINUATION**, 0 truncated,
and the continuations appear only in the sessions whose largest notification is
240 – the camera writes 240 then 60 for a declared 2445, so the fragmentation
unit on the wire is the camera's own write size, not the link MTU.

Replay of the two watch corpora (`OneRremote X6a.TXT`, `X6b.TXT`, 363 RX
notifications) already answers most of the question for the X6:

- **every notification is exactly 20 octets** – the watch link is MTU 23 and
  Connect IQ offers no MTU API to change that;
- the camera's UCD2 pushes declare `want = 25` (`declared = 9`) and only 20
  arrive, and the next notification is a **new head** (seq +1): verdict **B
  TRONCATURE-UNIQUE**, 68 of them, with **no continuation anywhere**;
- the trailer of those pushed frames therefore never arrives: a UCD2 CRC check
  is impossible on that corpus, and a strict "deliver only at `want`" rule would
  drop every X6 push the product handles today. The unification must deliver on
  the frame boundary (next head) with truncation flagged, not on `want` alone;
- a **legacy ask is answered in UCD2** (`demande=LEG REPONSE=UCD2`, codes
  `0x2017`, `0x5079`): the X6 answers the old envelope with new-envelope
  frames, so the RX engine must recognize both envelopes in one stream, not one
  per connection.

The probe run on the watch (X6 bench, then X5/One R) confirms or refutes this
on the link the product actually uses, and the rungs `L6`/`L8`/`U5` measure the
`requestWrite` ceiling instead of assuming 20. Until that trace is pasted back,
the safety rule already folded into the probe holds for the product: a frame
whose `want` is not reached is never delivered as complete, headless fragments
are dropped and not stacked, abandonment is traced, and the delivery of a
truncated-but-bounded frame is a separate decision with its own trace.

### 15.1 Lessons from the first build attempt of the probe (other machine)

- `Lang.Array` has **no `delete`, no `insert`, no `at`**. The documented surface is
  `add addAll indexOf remove removeAll reverse size slice sort toString`, with
  `slice(start, end) as Lang.Array` since API 1.3.0. Trimming the log window is
  therefore `log = log.slice(log.size() - LOG_MAX, log.size())`, and the array must
  be declared un-annotated for the `slice` result to re-bind. Consequence for the
  barrel unification: a reassembly buffer cannot drop an already-joined fragment, so
  the engine advances an index instead of deleting.
- Two applications **cannot share a manifest `id`**: the probe inherited the id of
  `BLE Probe` and the watch refused it. A dedicated 32-hex id settles it; an `app`
  and a `widget` coexist happily.
- `entry` in the manifest must name the `Application.AppBase` subclass, and the first
  view comes from `getInitialView()` returning `[View, InputDelegate]` (the pattern
  already running on the watch), not from `pushView()` inside `onStart()`.
- `tools/mc_check.py` grew a fourth gate: every `.member(` name is compared with the
  names used by the 14 `.mc` files of the five projects that are known to load on the
  watch. Anything else is reported and checked against the official Toybox
  documentation — that is how `delete` surfaced and why `getMtu`/`requestMtu` stay out.
- **An inherited callback must be declared with the number of parameters the
  framework passes.** `AppBase` calls `onStart(state)` and `onStop(state)`; declaring
  them without the parameter made the simulator crash at app start with
  `Too Many Arguments Error / Failed invoking <symbol>`, pointing at the first line
  inside `onStart()` and never naming the symbol. Every shipped project declares
  `onStart(state)`, and `tools/mc_api_diff.py` now compares inherited-callback
  declarations against those references (the gate flagged `onStart`/`onStop` before
  the fix and is silent on all 16 `.mc` of the repo afterwards).
- The failing barrel builds do not come from the code in this repository. The  `Capacites Barrel-1.0.0.barrel` artifact (Oct 26) embeds a 184-line `Capacites.mc`
  that is the **SDK project template** ("module is ..." wording), and the compiler
  message quoted the literal placeholder `does not match module name '<module name>'`.
  A barrel built from a template exports no members, which is what makes the app fail
  with `Undefined symbol 'sendCMD'`; in this repository `sendCMD` is defined at
  `BLEBarrel.mc:1606` inside `class BleDevice` and appears in all five shipped binaries.
- The `barrels.jungle` files carry **absolute Windows paths**
  (`C:\Users\greg\git\Insta360-Remote-CIQ\...`): a build reads that tree, not the one
  edited here, so every fix has to be copied across before it can be tested.

### 15.2 The probe now builds with the real compiler (SDK 9.1.0, headless, Linux)

SDK 9.1.0 is installed locally (`~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.1.0-2026-03-09-6a872a80b`)
and `bin/monkeyc` works on Linux without a simulator, so inference-based checking is
no longer the source of truth. Recipe that works:

```bash
openssl genrsa -out rsa.pem 1024 && openssl rsa -in rsa.pem -outform DER -out rsa.der
# scratch copy of the project + a one-line jungle (do NOT point -f at manifest.xml)
echo 'project.manifest = manifest.xml' > monkey.jungle
$SDK/bin/monkeyc -f monkey.jungle -d epix2pro51mm -y rsa.der -o out.prg -l 1 -w
```

- `-m manifest.xml` alone dies with `getJungleManager() is null`; `-f manifest.xml`
  makes the compiler throw a `StackOverflowError` in the ANTLR lexer; `-s source` and
  `-r` no longer exist in 9.1.0. A DER RSA key is required (`-y`), and
  `openssl genrsa -outform der` writes a PKCS#8 the loader rejects — go through PEM.
- `bin/simulator` is unusable on this Ubuntu box (`libwebkit2gtk-4.0.so.37` missing,
  the distro ships 4.1) and `bin/era` is only an image downloader, so runs still
  happen on the Windows PC.
- Current state: **0 error, `FramingProbe.prg` produced**. The 20 errors of the first
  real compile were all type errors that the IDE build hides (its type checking is off),
  so they were latent runtime bugs, not build blockers:
  - `Lang.String` has **no `size()`**, only `length()` (`api.mir` line 12072): the
    probe hit this on a UUID dump and on the on-screen log line.
  - `ByteArray` is **not** a subclass of `Array` (`api.mir` line 12399). Passing one to
    a parameter declared `Lang.Array` is an error, so `hexOf()` is now declared
    `as Lang.ByteArray`, which is what every call site passes.
  - `method(:sym)` is `Lang.Object.method`, i.e. an instance member: at **module**
    scope there is no `self` and the compiler says
    `Cannot find symbol ':method' on type 'self'`. Fixed with a tiny `TimerHost`
    class whose three methods (`clockCb`/`rungCb`/`bilanCb`, deliberately not named
    after the module functions, which would make them recurse) call the module
    functions, and `timerHost.method(:clockCb)` at each `Timer.start`.
  - `BluetoothLowEnergy.setDelegate(null)` is not a thing: no shipped project clears
    the delegate, so `onStop()` only stops the timers.

### 15.3 One message, one budget: the watchdog that killed the probe at boot

`Watchdog Tripped Error - Code Executed Too Long`, stack
`ucd2Stamp() ← ucd2Frame() ← buildLadder() ← startRun() ← onStart()`. Nothing in that
trace is wrong code: the whole boot (3 CRC stamps in `selfTest()` plus 22 frames built
by `buildLadder()`, 5 of them UCD2) ran inside a **single** `onStart()` message and the
budget died inside the CRC loop — the hottest code, which had already survived three
stamps and was killed on the fourth. So the CIQ VM allows only a few thousand inner CRC
steps per message, and `System.println` volume counts against the same budget.

The fix is cost, not the CRC: the proven 4-byte-state implementation is untouched
(rewriting it "long" would have added a new crash class for nothing). What changed:

- **one CRC stamp instead of three** at boot: `selfTest()` became `testLegacy()`
  (five legacy builders compared to the wire + the 107-octet GET_OPTIONS rebuild, one
  summary line, detail only on divergence) and `testUcd2()` (a single stamp checked
  against the observed GET_OPTIONS trailer).
- **frames are built at the rung, not at boot**: the ladder carries `:gix => MK_*`
  ids and `buildFrame(gix)` returns the bytes when the rung runs, so no message ever
  holds more than one CRC, and the ladder is 22 dictionaries instead of 22 buffers.
- **boot steps spread over clock ticks** (`clockTick()`: `testLegacy` → `testUcd2` →
  `buildLadder`, one per 100 ms tick) so `onStart()` returns immediately. A
  `bootStep < 3` guard in `beginLadder()` plus a check in `clockTick()` covers the
  race where the link comes up before the ladder exists — otherwise `nextRung()` sees
  an empty ladder and prints the bilan at once.
- **the bilan paginates**: the watch corpora produce 68 verdicts, and one message of
  ~70 `println`s is itself a watchdog risk, so `bilanPage()` prints `LOG_PAGE = 10`
  lines per timer tick.
- `ucd2Stamp()` refuses absurd sizes (`n < 12 || n > 512` prints
  `[crc] garde refusee` and returns) so a bad length is reported, not computed.

### 15.4 The bench ran: what the watch link actually does (2026-11-04)

X5 fw v1.13.21 serial `IAHEA2503S6GEW` (scan name `X5 3S6GEW`), watch build for
family `006-B4314-00`. 20 rungs, 62 notifications, 543 octets. Full log kept in
`out/bench/X5-fw-legacy-20261104.log`. No watchdog, no crash: the boot
lines printed (`[test] legacy …`, `[test] ucd2 … identique`, `[echelle] 20 etages
prets`) and the bilan paginated to the end.

**TX ceiling, measured instead of assumed**

```
[tx] UNE ecriture n=24 …
[cap] requestWrite REFUSEE n=24: Long Writes are not supported
[cap] requestWrite REFUSEE n=107: Long Writes are not supported
```

The watch has no BLE long write (Prepare/Execute), so one `requestWrite` carries at
most `ATT_MTU - 3`. The 20-octet unit that the PC corpora showed is therefore not a
convention of the official app: on this link it is the **only** unit that can be
sent. Chunking is mandatory, and a 24-octet frame (GET_OPTIONS) must be split —
which the camera accepts: `[tx] decoupe en 2 ecritures … status=0 file=2 / file=1`.

**RX ceiling**

`[bilan] notification la plus grande recue = 20 octets, donc MTU negocie >= 23`, and
the size histogram is `7x53 20x7 16x2`: nothing above 20 was ever seen. There is no
MTU API in CIQ, so this is the whole story: **MTU 23 both directions**.

**The framing verdicts — the question this bench exists for**

| asked | camera said | what arrived | verdict |
| --- | --- | --- | --- |
| code 15 | `code=0xc8 want=24` | head 20, next notification is a keepalive | **B TRONCATURE-UNIQUE**, tail of 4 never arrives |
| code 66 | `code=0xc8 want=475` | head 20 + one headless 20 (`5f 32 2e 30 36 …` = `_2.066433191-3.2`), then silence | **C TRONCONS-SANS-EN-TETE**: continuations exist, the stream stops at 40 |
| code 8 | `code=0xc8 want=2445` | head 20 + 20 + 20, then the camera never pushed again | truncated, and the link died (below) |
| code 8 | `code=0x2017 want=16` | 16 octets in one notification, `10 00 00 00 04 00 00 17 20 02 ff 8a 43 f4 00 00` | **ENTIERE d'un bloc** |

Consequences for the RX engine in `BLE Barrel/BLEBarrel.mc`:

1. **A (continuation) and B (truncation) are both real on hardware**; a whole frame
   with `want > 20` never arrives. The engine must append headless notifications,
   but must also deliver at the next frame head with a truncation flag, because the
   strict `want` gate would drop every response the product handles today.
2. **The keepalive is a frame boundary, never a continuation.** 53 keepalives,
   7 octets, one per ~1.0 s (`[nf] #n len=7 07 00 00 00 05 00 00`), unsolicited.
3. `code=0x2017` (16 octets, payload `ff 8a 43 f4 00 00`, identical each time) is the
   camera's **legacy ACK** of an accepted request. It arrives before the real answer,
   so a window that judges only the first head measures the ACK, not the response.
4. On this firmware legacy `GET_OPTIONS` is not answered with the 2445-octet list
   captured on PC: the ACK comes back, and the `code=0xc8` frame that follows
   (148, 2445 announced) is cut at 20–60 octets. With the X6 corpora (legacy asks
   answered in UCD2) the option list is a UCD2-era exchange.
5. **Never ask for the big lists over this link** (`GET_OPTIONS`, `GET_FILE_LIST`):
   the answer cannot fit and the camera stops pushing (next section).

**Two bench-side failures, and what they prove about the link**

- From the end of the 2445 response on, the camera sent **nothing at all** for 12
  rungs: no keepalive, no answer to a 16-octet code 66, no `0x0190` for the
  declared/sent length control (that control is therefore *unconfirmed* here, not
  refuted). Writes still returned `status=0`, so the GATT link was alive while the
  camera's notification side was stuck. Rule: **a truncated stream can wedge the
  camera for the rest of the session.** — *superseded by §15.6: on the v2 run the
  link never died (keepalives never stopped, `relances de lien=0`); this silence was
  the probe's own TX jam, and later silence is per-request, not link death.*
- From rung U2 on, `onCharacteristicWrite` never came back and every later write was
  refused with `Operation already in Progress` — the probe's `flush()` had cleared
  its `writing` flag and kept knocking. So: **one `requestWrite` in flight at a
  time**, and a missing write completion means the link is not usable, not "retry".
- API fact found while fixing: `BluetoothLowEnergy.Device` has **no `disconnect()`**
  in SDK 9.1.0 (only `getName`, `requestBond`, `isConnected`, `getServices`,
  `isBonded`, `getService`, `getDescriptor(s)`, `getUuid`). The module offers
  `unpairDevice`, `getAvailableConnectionCount`, `setConnectionStrategy`. The only
  way for a CIQ app to drop a stuck BLE link is `unpairDevice()` + rescan.

### 15.5 Probe v2, so the next log is read correctly

The first run contains two measurement bugs of the probe itself; both are fixed and
the log now carries `[build] v2 2026-11-04 …` so the two runs cannot be confused.

- **Keepalive counted as a continuation** (the `A DEBORDE` verdicts of L2/L4:
  `recus=27` for `want=24` was `20 + 7` keepalive). `feed()` now decides
  "frontier" before anything else: a beat or a new head closes the open frame and
  names the frontier (`clos=frontiere: battement`), so a cut response reads
  `B TRONCATURE-UNIQUE` instead of `A DEBORDE`. UCD2 beats are detected by their
  type byte (`[6] = 0x05`, code `0x5079`), not by code.
- **One set of counters per window** attributed the measurement to the first head
  seen, which was the `0x2017` ACK. A window now keeps up to `MAXF = 3` frames, each
  with its own `want / recus / morceaux / clos / verdict`, printed as
  `trame 0 …`, `trame 1 …`, plus `trames=N battements=… orphelines=… frontieres=…
  tetesApresClose=…`. Orphan lines are no longer printed for keepalives (46 of the
  62 notifications were beats: that noise also cost watchdog budget).
- **Link life is measured**: `lastNfTick` tracks the last notification; a rung that
  starts `WEDGE_TICKS = 35` ticks (3.5 s, three missing beats) after the last one
  prints `[alarme] plus aucune notification depuis ~… ms: la camera ne pousse plus`
  and calls `recover()` (`unpairDevice` + rescan, at most 3). A pending write at a
  rung change prints `[tx] ATTENTION: requestWrite toujours en suspens` and blocks
  the next emission instead of knocking. `[bilan] … relances de lien=N` closes the run.
- **Ladder order changed**: the UCD2 block runs first (that is what the first run
  never got to measure, and its frames cannot wedge the link), the benign legacy
  rungs next, the `0x0190` control while the camera is still healthy, and the
  wedge-prone big answers (`475`, `107`, `2445`) last — with `[L10]/[L15]`
  "does the keepalive come back" probes and an `L11` code-66 re-ask between them, so
  "camera wedged" and "just that stream lost" are told apart.

### 15.6 Probe v2 on hardware: measured verdicts (2026-11-04, second run)

Same X5 (fw v1.13.21, serial `IAHEA2503S6GEW`), same watch family. 23 rungs, 343
notifications, 165 keepalives ~1 s apart, biggest notification 20 octets (MTU 23
both ways), no watchdog, no TX jam: `[bilan] ecritures en suspens au changement
d'etage=0 relances de lien=0`. Full log:
`out/bench/X5-fw-legacy-v2-20261104.log`. The user also drove real camera
events at the end of the run (charger plug, unplug, 10 s of 8K30 recording, stop),
which produced the push verdicts below.

**The link survives a truncated frame — §15.4's wedge rule is retired.** Across
the whole v2 run the keepalive never stopped (165 beats, none missing after the
`2445`-announced GET_OPTIONS ask, after code 66 twice, after the 107-octet ask),
every write completed (`file=N` countdown to 1, no `Operation already in Progress`),
and the link was never re-launched. What §15.4 read as "the camera's notification
side is stuck" was the probe's own TX jam from rung U2 on. Silence on a later
request is **per-request**, not link death.

**Request-rung verdicts (legacy ladder)**

| rung | camera answer | received | verdict |
| --- | --- | --- | --- |
| L2 code 15 | `0xc8 want=24` | head 20, frontier = next beat | **B TRONCATURE-UNIQUE**, tail of 4 never arrives |
| L4 code 8 (small) | `0x2017 want=16`, then `0xc8 want=51` | ACK whole, then head 20 of 51 | ACK **ENTIERE**, answer **B TRONCATURE-UNIQUE** |
| L5 code 13 GET_FILE_LIST | `0xc8 want=4008` | head 20 + **18 headless 20-octet continuations** = 380, camera stopped | **B**, but the reassembly path is proven end-to-end on the watch (filenames visible in the hex) |
| L7 control declared=26 / sent=24 | answered ~2 s late at the next rung: `10 00 00 00 04 00 00 90 01 02 01 00 00 80 00 00` echoing request seq `01 00` | 16 octets whole | **`0x0190` BAD_REQUEST confirmed on hardware** |
| L3 code 3; L9 and L11 code 66 | nothing, twice each | — | unanswered (request-specific, link alive) |
| L12/L13 code 8 large; L14 code 8 GET_OPTIONS | nothing | — | unanswered, or later than the window |
| U1–U7, all six UCD2 rungs (incl. the CRC-computed START, trailer self-check passed) | nothing | `orphelines=0` | **UCD2 still unproven on this firmware** |

**Push verdicts (user-triggered events, end of run)** — pushes carry seq `ff 8a`
(`seq=35583`) in the legacy envelope; the 20-octet notification budget decides what
crosses:

| push | enum | declared | received | verdict |
| --- | --- | --- | --- | --- |
| battery `0x2003` (plug **and** unplug) | 8195 | body 8 | 4 of 8 | **B, twice, no continuation ever** |
| capture status `0x2010` (start, stop) | 8208 | body 6 | 4 of 6 | B, tail `38 xx` lost |
| record state `0x2040` (start, stop) | 8256 | body 2 | whole | **ENTIERE** |
| storage `0x2006` (x2) | 8198 | body 4 | whole | **ENTIERE** |
| dashcam info `0x2062` | 8290 | body 22 | 4 of 22 | B, cut at octet 4 of the body |

**Battery: final.** `0x2003` was seen exactly twice, once per charger event, each
time `want=24 recus=20 manque=4` with **no headless continuation** — the last 4
octets of the 8-octet body never cross on this link. Combined with the GET answers
(51 and 2445 announced, 20 crossed) that cannot carry it either, the battery
**level is unreachable over the watch link**; only the first 4 body octets cross,
which hold the charger-connected flag (wire decode below). No further charger
experiment is needed.

#### Wire decode of the push bodies (PC corpus bodies, matched to the watch cuts)

The PC captures (`rea/artefacts/ble-*-frames.log`, decoded lines below) give the
whole bodies; the watch window shows how much of each survives the 16-octet header
plus 20-octet notification budget:

- `0x2003` BATTERY_UPDATE, declared=8: `0a 06 08 01 10 39 20 00` = f1
  submessage(6): `power_type` f1 = 1/0 (adapter/battery, toggles with the charger),
  `battery_level` f2 = 0x39/0x27 (57 %, 39 %), f4 = 0. The watch cut keeps exactly
  `0a 06 08 <power_type>`: **the charger flag crosses, the level never does.**
- `0x2006` STORAGE_UPDATE, declared=4: `08 00 10 00` = f1 = 0, f2 = 0. **Whole on
  the watch** (4 body octets fit), so it is usable as a feature carrier.
- `0x2010` CURRENT_CAPTURE_STATUS, declared=6: observed `08 04 10 02 38 03`,
  `08 00 10 00 38 00`, `08 01 10 00 38 00`, `08 01 10 12 38 02` = f1, f2, f7
  (f7 = 0 when idle, nonzero while recording). The watch cut keeps `08 x 10 x` =
  **f1 + f2, loses f7**.
- `0x2040`, declared=2: `08 00` / `08 01` = one boolean-like flag. The APK enum
  name for 8256 is `CAMERA_NOTIFICATION_SUPPORT_TAKE_PHOTO_ON_REC_STATUS`
  (`message_code_map.txt`), but the frame decoder labels it `RECORD_STATE`, and on
  the bench this push fired exactly at record start and record stop — treat it as
  the **recording flag**; it **crosses whole**, so record state is a free feature.
- `0x2062` DASH_CAM_INFO, declared=22: `08 80 80 80 f8 b8 07 10 80 80 90 f7 b8 07
  18 b3 e6 cc a5 5f 20 00` = f1 = 0x3b8f000000 (= 137 438 953 472 = 128 GiB, the
  card size), f2 = 0x3b8ee40000 (~same scale, used/free), f3, f4 = 0. These look
  like byte counts carried as varints whose low 16 bits are always zero. The watch
  cut keeps `08 80 80 80` = the first varint's first four bytes; completing it with
  `f8 b8 07` from the PC corpus gives the 128 GB capacity. Not urgent.

Consequences for the RX unification in `BLE Barrel/BLEBarrel.mc`: deliver a frame
at the next frontier (beat or new head) with a truncation flag, and decode only
what is known to survive — `0x2040` record state (whole), `0x2006` storage
(whole), `0x2010` f1+f2, `0x2003` power_type only. Battery level stays out.

Probe v3 wish list, if another bench pass is wanted: print full notification hex
(the `[nf]` preview cuts at 15 octets, so push bodies were lost on the watch even
when they crossed), and probe why code 3, code 66 and every UCD2 rung go unanswered
on this firmware.

### 15.7 Probe v3 built: the requested size is a varint, and the sweep that decides the 380

**Correction to a corpus decode.** The official GET_FILE_LIST body `18 c8 01` is
field 3 as a protobuf varint: `0xc8` carries the continuation bit, low 7 bits
`0x48` = 72, plus `0x01 << 7` = 128, so **the official request asks for 200
entries, not 456** (an earlier note read the pair as 456). The `08 01 18 32`
variant is field 1 = 1 with field 3 = 50. That also retires one assumption: the
same body declared 113 to the PC and 4008 to the watch, so the declared size
follows card content, not only the request — v3 measures the relation instead of
assuming it.

**What v3 is for.** §15.6 left two readings of `want=4008 / recus=380` open, and
the 16-octet `[nf]` preview could not separate them: the camera stops at 20 octets
per request whatever the need, or it chunks up to a ceiling (19 notifications of
20 = 380 exactly) and the tail never came. v3 keeps only the questions that bear
on answers above 20 octets and sweeps one request (code 13) over the requested
size, f3 = 1, 2, 3, 5, 10, 20, 50, 50 (f1 = 1), 100 (f1 = 1), 200, 456. f3 = 200
is byte-for-byte the official PC frame and is what `gflSelfTest()` compares to it
at boot; f3 = 456 encodes as `18 c8 03`. Three readings decide the question:
does `declared` follow the request; does a 40..482-octet answer arrive whole (the
PC saw 482 announced 482, so if it crosses, no 380-octet link ceiling exists);
and the trailer `10 nn` plus the path text say where the content really ended.
Also raised: `MAXWANT` 4096 → 12000, because a head announcing around 9000 (f3 =
456) was being dropped before it could be judged; `WEDGE_TICKS` 3.5 s → 4.5 s,
consistent with silence being per-request (§15.6).

**UCD2 is set aside, not concluded.** Per the bench decision, no rung asks a UCD2
question in v3: the boot call is `// testUcd2();` and the seven rungs stay in
`buildLadder` as comments, with the machine (`ucd2Frame`, `ucd2Stamp`, the UCD2
`headOf`) still in the file. §15.6's "UCD2 still unproven on this firmware"
therefore stays open. The answered-everything-but-UCD2 pattern of §15.6 is the
reason, not new evidence.

**Console budget is part of the design.** The v2 log cost 37 521 octets of which
18 600 (309 lines) were keepalive lines saying one thing. v3 groups keepalives
into one line per series and prints the rest in full, capped at 80 octets with
the cut announced by `hexOf` (`..(total n)`). Projected ~45 Ko against the ~60 Ko
of two rolling 30 Ko console files. Per-category numbers and the exact hex of
every frame v3 sends: `out/bench/v3-plan-20261104.md`.

**Compiler traps met while building it** (the probe file has no `module`
declaration, so its symbols sit in the file's default scope):

- an en-tête rewrite that spans to the first `const` eats the `using Toybox.*`
  block; every type then fails to resolve and the error list starts at the first
  typed member, hundreds of lines away from the cause;
- `const X = [...]b` refuses a value above 255 (`Byte array instantiated with
  value '456'`) — a table of quantities is a table of numbers, not of bytes;
- `[Lang.Number]` on the literal keeps the arithmetic at the index site clean
  (`var A = [1, 2, 456] as [Lang.Number];`); a bare `as Lang.Array` forces a
  cast at every index and adds "Cannot determine if container access" warnings;
- local variable types are inferred: `var z as Lang.Number = 0;` is now
  `Invalid explicit typing of a local variable`;
- `d[:key] as Lang.Number` on an absent key is not a no-op: the cast of a
  missing dictionary key throws `UnexpectedTypeException` at the callee's first
  use of the parameter. v3 crashed at rung 0 on exactly this — the listen rungs
  (A0/A14/A18) carry no `:gix`, and `buildFrame(rung[:gix] as Lang.Number)`
  died inside `buildFrame`'s first `if`, so the stack blamed line 1489, not the
  call site. The compiler never flags it; a rung dictionary must be audited
  key by key against every unguarded cast in `nextRung`.

**v3 first boot (2026-11-04): frame generation confirmed on the watch, then a
crash at rung 0.** The boot self-test passed on hardware — `[test] GFL f3=200
(officiel) identique a la trame PC`, `f3=456 ... (varint ok)`, `f1=1 f3=50
identique a la variante PC`, the 11 `[quest]` lines match the plan hex, and
scan/connect/LBS found `X5 3S6GEW` with `[echelle] 19 etages prets`. It then
threw `UnexpectedTypeException ... given null` at `buildFrame` ← `nextRung` on
the first (listen) rung. Fixed in **v3a** by an `else if (rung[:gix] == null)`
branch before the send chain; banners now print `v3a` so a bench log proves
which binary ran. The v2 → v3 recipe `mk_v3.py` can no longer be replayed (the
v2 source was lost when /tmp was cleaned; only its `.prg` and MIR survive), so
the generated v3 became the baseline and each later fix is an idempotent
anchor in `/tmp/opencode/probe/mk_v31.py`.

Status: source `Framing Probe/source/FramingProbe.mc` (v3a, `BUILD SUCCESSFUL`,
22 warnings identical to v3, 134 604-byte `.prg` at
`out/bench/FramingProbe-v3a-20261104.prg`), awaiting the X5 run. Edit
the recipe (`mk_v31.py` from here on), not the generated file, because kDrive
has already overwritten one full write of the source with the older v2.

### 15.8 v3a over the simulator + nRF52840 dongle: the wedge hits early, and v3b answers

Run of 2026-11-04, simulator + dongle, real `X5 3S6GEW` found and connected,
all boot self-tests green again. What the run settled:

- **The declared size follows the request**: `f3=1 -> 66`, `f3=2 -> 113`,
  `f3=3 -> 161`, `f3=5 -> 256`, `f3=10 -> 493` — about `18 + 47.5 x f3`, the
  request's entry count times the average record plus framing. The varint in
  the request is read end-to-end by the camera.
- **Continuations are confirmed and their pieces are not fixed-size**:
  A6 (`f3=5`) sent head 20 + one headless 16 (36 of 256), then went back to
  beats; A7 (`f3=10`) sent 20 + 20 + 13 and was still streaming when the
  window closed. The 20-octet notification cap holds; piece size varies.
- A6/A7 bodies open exactly like the PC corpus (`0a 2e "/D...insv`,
  `0a 2d "/DCI...lrv`) and both visible streams end on `10 58`: trailer
  (field 2 = 88 files) or padding inside a fixed-size record — undecided,
  the full-hex rerun answers it.
- **The wedge is far cheaper than v2 suggested**: after A7's partial stream
  the camera stopped pushing beats and never resumed, while the link stayed
  connected (no `[lien] etat=0`). v3a's guard then did `unpairDevice` on a
  live link, the camera never re-advertised, and eleven rungs ran empty.
- v3b (bench `.prg` 136 508 B): the watch screen shows the ladder position
  big (`N/19` + current label, `CAMERA MUETTE` red, `TERMINE`), every `say()`
  redraws it, two silent rungs in a row end the ladder without touching the
  bond, and the rung number is kept in app storage: restart the camera,
  restart the probe, it resumes at the next rung (`MENU-HAUT` clears it).
  SDK 9.1.0 API check the hard way: `WatchUi.scheduleDraw`,
  `Toybox.Properties`, `Properties.save` and `Storage.setNumber` do not
  exist there; `View.update()` and `Application.Storage.setValue/getValue`
  do.

v3b then crashed on the physical watch (`Symbol Not Found Error: Could not
find symbol 'update'` from `say()`): `View.update()` is protected — the
compiler accepts calling it from outside the class, the runtime cannot resolve
it (same family of trap as the rung-0 `as Lang.Number` cast: compiled, threw on
hardware). v3c replaces it with the public entry from the SDK doc,
`WatchUi.requestUpdate()` ("request a call to the onUpdate() method for the
current view", API 1.0.0, no argument, works from any callback), and drops the
now useless global view handle. Bench `.prg` 136 428 B, 22 warnings (parity),
banner `v3c`, resume tag `v3c19` so no resume point crosses builds.

v3c simulator rerun (same day, `out/bench/X5-fw-legacy-v3c-sim-20261104.log`):
the early stop worked as designed — mute rung 1/2 at A7, 2/2 at A8, `[arret]`
+ bilan, resume point stored at rung 9, `relances de lien=0` (no unpair on a
live link). What it measured:

- The silence started inside A6's own window (`[nf] ... sur 7s`): A6's 2-piece
  answer (head + one headless 16) was the last thing the camera pushed. A7 was
  sent into an already dead pipe — the v3a run shows the same 7 s gap in A6's
  window, its `[fr]` only closed later. So no request "killed" the camera:
  the first answer that needs more than one piece stops the beat push within
  ~7 s. The v2 hardware run behaved differently (19 continuations in one
  burst, 343 notifications before the wall) — the physical v3c rerun decides
  which behavior is the camera's.
- Declared vs f3: 1->66, 2->113, 3->161, 5->256 (body = declared-16, roughly
  47.5 per entry; A7 declared 493 in v3a). The official PC frame (declared
  113) is byte-for-byte what the watch request of A4 (f3=2) produces — the
  PC answer's 113 was an f3=2 list, not f3=200 content.
- Open protobuf question from A6's full hex: `0a 2e` says field 1 LEN 46, yet
  `10 58` shows up 18 octets into that string and the continuation ends there.
  Either `10 58` = field 2 varint 88 (file count, PC corpus trailer was
  `10 02`) and the LEN is not what it reads, or the answer is fixed-size
  records and the head is not at the notification's byte 16. A complete
  answer settles it; do not decode half-streams further.

### 15.9 The physical watch run: no wedge, real streaming, the 21-notification wall

Full v3c run on the watch (`out/bench/FramingProbe-phys-BAK-20261104.log`,
console rolled so the [nf] detail of rungs A1..A15 is lost; A16 tail and all 33
verdicts survived). 257 notifications, 3114 octets, sizes `16x4 7x151 20x98
13x1 8x1 6x2`, no orphan, no link restart:

- **The wedge is a simulator/dongle artifact, not camera behavior.** On
  hardware the camera streamed 420-octet answers back-to-back and kept beating
  after, through all 19 rungs. Design the barrel for the physical behavior.
- **Truncation is chunked streaming, not one-piece loss**: A7 20+20+13=53,
  A8 88 (5 pieces), A9 240 (12), A10/A11 106 (6), A12/A13/A17 420 (21). The
  first >20 answer ever asked on hardware (v2, 380) and now 420 both arrived
  head + headless pieces. The 380 of v2 was NOT a ceiling.
- **Declared tracks the request** up to a ceiling: 1->66, 2->113, 3->161,
  5->256, 10->493, 20->968, 50->2393 (body ~= 47.5 per requested unit), but
  f3=200 and f3=456 both declare 4198: the camera caps the answer at 4198
  (404-octet body? no: 4198-16 = 4182 of content) whatever the ask. f1=1
  gives declared 1026 for both f3=50 and f3=100 (also capped, differently).
- **Content structure (A17, first full chunk decoded)**: NOT a flat text
  stream. The body is protobuf chunks: `0a 2e` + 46 printable, `0a 2d` + 45,
  `0a 2e` + 46... — repeated field 1 whose entries hold 45/46-char slices of
  the path list; paths carry a leading type marker (`.`/`-`) and are
  newline-separated (`./DCIM/Camera01/VID_20261101_103834_105018_00_037.insv`,
  `.lrv`, `C_008.insv`, `am25.lrv`). The sim A6 decode suggested the first
  entry can be short (`0a 12` = one 18-char path) closed by `10 58` (field 2
  varint 88); both readings cannot hold at once — full answers will say which
  framing is right.
- **Two new complete pushes** in the code-8/GET_OPTIONS windows: reponse=0x2017,
  want=16, arrived whole (16 octets, twice in windows 16 s apart). Not
  decoded yet.
- GET_OPTIONS (ask 0x8) declared 148 this run vs 2445 in v2: card/session
  dependent.
- Delivery wall: the two biggest answers both stopped at exactly 21
  notifications (420 octets), while the same camera kept streaming beats right
  after; smaller answers stopped at 2/3/5/6/12 pieces. Per-request credits,
  or 8 s windows cutting live streams - the probe timestamped pieces only at
  100 ms resolution, cannot tell. v4 must: open-ended windows (close on
  want-complete or 2 s of silence), per-notification dt, repeat the same
  request twice and compare (start-of-answer determinism already shown:
  A12/A13/A17 heads identical).

### 15.10 Probe v4 built: status-only ladder, lean console (2026-11-04)

Chunking is settled (15.9), so v4 asks only about camera **status at connect**:
battery, storage left, mode, recording state. `mk_v4.py` anchors on the v3c
baseline (`df0cd015…`); installed source sha `155083c6…`, `.prg` 137 820 B
sha256 `c704f67a…`, banner `FRAMING PROBE v4`, build `v4a`, `RUN_TAG v4a18`.

The ladder is 15 rungs, legacy envelope only:

- S0 / S11 (10 s) / S14 — passive listens: unasked pushes are the cheapest
  measurement there is (`0x2003` battery, `0x2006` storage, `0x2010` capture
  status, `0x2040` recording, `0x2017`/`0x2062` periodic).
- Known asks first as calibration + late life probes: ask 15 (24 declared),
  ask 8 options 11+20 (51), ask 8 wide (148 seen in v3c), ask 15 again.
- Unknown asks, each **repeated** so the declared size is measured twice:
  ask 10 GET_PHOTOGRAPHY_OPTIONS, ask 43 GET_SUBMODE_OPTIONS, ask 166
  GET_STORAGE (empty body). Then life probes ask 15 + ask 8 again.
- Every rung carries its own request seq (`31 + 2*rungIx`); the camera echoes
  it, so the two answers of a repeated ask are distinguishable in the window.

Open enum question that v4 measures directly: PROTOCOL_APK labels code-8
options 11=BATTERY_STATUS / 20=STORAGE_STATE from the observed X5 answers,
but `photo_opt_type_map.txt` names 11=AE_METER_MODE, 20=STILL_EXPOSURE_OPTIONS
inside `PhotographyOptionType` — the id families used by code 8 vs code 10/43
may differ. v4 sends the 8-family body `0a 02 0b 14` to asks 10 and 43 as a
hypothesis; the declared/echoed answer shape settles it.

Console budget (the watch console holds ~5 KB + ~5 KB `.bak`; v3c lost the
`[nf]` detail of rungs A1..A15 to rolling): `[fr]` lines dropped (they
duplicated the verdict lines), the `0x2017` ACK is printed twice then counted,
notification hex capped at 20 octets (was 80), `status=0` write confirmations
counted not printed, blank rung separators dropped, and each window **closes
early**: after the last frame of a window is frontier-closed, two beats end it
(`endWindowEarly`), ~3-4 s instead of 8. Estimated total output ≈ 8-9 KB,
under main + `.bak` together.

### 15.11 v4 measured on the X5 firmware (simulator + nRF52840 dongle, 2026-11-04)

`out/bench/FramingProbe-v4-sim-20261104.log` (complete, nothing rolled: 27 verdicts,
`[fin]` present, ~9 KB). The extracted firmware behaves like the camera on the
points that matter: MTU 23 with 20-octet notifications, one ~1 s beat
(`07 00 00 00 05 00 00`), `0xc8` answers that echo the request body, and —
decisively — **the same declared sizes as the PC corpus**: ask 8 (ids 11+20)
declares 51, ask 8 (ids 11,15,16,20,30,48) declares **148**, ask 15 declares 24.
Declared sizes are firmware constants, so the sim can measure them instead of
the watch. Notifications 61 / 594 octets, sizes `7x46 20x8 16x7`, no orphan,
no link restart, and the console budget held: v4 printed every verdict.

Measured per ask (declared = total frame, body counted after the 16-octet
envelope), each unknown asked twice:

| rung | ask | declared | first body octets | note |
| --- | --- | --- | --- | --- |
| S1/S4/S12 | 15 capture status | **24** (three measures, stable) | `0a 06 08 00` | nested field 1 (6 octets), inner field 1 = 0; the cut keeps 4 of 8 body octets — the same geometry as the `0x2003` battery push, whose next two octets (`10 <value>`) sit just past the wall |
| S2/S13 | 8 options 11+20 | **51** (matches PC) | `08 0b 08 14` | body opens with the echo of the requested ids as repeated field-1 varints, exactly the PC shape |
| S3 | 8 options 11,15,16,20,30,48 | **148** (matches PC) | `08 0b 08 0f` | same echo |
| S5/S8 | 10 photography options 11+20 | **39** (new) | `08 0b 08 14` | **the code-10 answer uses the code-8 carrier**: ids 11 and 20 come back as field-1 varints, so the 8-family option ids are valid inside ask 10 on this firmware |
| S6/S9 | 43 submode options 11+20 | **16** | (none) | answered `0xc8` with **no body at all**: 11/20 are not part of the 43 family - the enum-family question is settled by a refusal, not by a size |
| S7/S10 | 166 storage, empty body | **16** | (none) | answered **`0x190` = 400 refusal**: ask 166 exists but needs a body we do not have |

Other facts from this run:

- **The legacy ACK (`0x2017`, 16 octets, `10 00 00 00 04 00 00 17 20 02 ff 8a
  43 f4 00 00`) only precedes a code-8 answer** - 3 in the run, one per code-8
  ask; asks 10/15/43/166 answer directly. The judge counts them
  (`accuses 0x2017=3`) instead of judging them as responses.
- **Per-rung sequence numbers work as correlation tags**: 10 of 11 answers carry
  the seq we sent (`31 + 2*rung`). The exception is S8, whose answer carried
  S5's seq (41) with byte-identical content: this firmware **re-sends the
  previous answer for an identical request** instead of re-answering. Asking
  twice still measures the size, but read the seq before attributing an answer
  to a rung.
- **This firmware pushes nothing on a quiet link**: S0 (10 s), S11 (10 s after
  the asks) and S14 (6 s) saw beats only - no `0x2003`, `0x2010`, `0x2040`,
  `0x2062`. The passive-listen rungs only pay off against the real camera.
- **Nothing above 20 octets crossed**, whatever the ask: all four oversized
  answers (24, 39, 51, 148) arrived as a single 20-octet head and stopped
  (`B TRONCATURE-UNIQUE`), with two full beats of silence after. The firmware
  chunks its **file-list** answers (420 octets seen on hardware, §15.9) but not a
  normal response, so the battery level, the storage byte counts and the
  capture-status tail sit behind that wall.

Consequence for the product: on the 23-byte watch link the status that crosses
today is `0x2040` (record flag, whole), `0x2010` f1+f2 (mode), `0x2053`
(sub-mode, whole), `0x2006` (card state, whole) and `0x2003` power type only.
Reaching the four octets past a 24-octet cut means testing the one thing the
phone never needed (its MTU is wide): whether this firmware will **continue** a
truncated response when prompted - plus a body sweep for ask 166, whose 400
refusal says that carrier exists but wants an argument.

### 15.12 v4 on the physical watch: the bench is faithful, and an idle X5 pushes nothing

The same build (`v4a18`) run on the watch against the X5, camera idle, card in
place. `out/bench/FramingProbe-v4-phys-TXT-20261104.log` is the surviving tail
(bilan + 27 `[resume]` + `[fin]`), `out/bench/FramingProbe-v4-phys-BAK-20261104.log`
is the rolled part (rungs 5..14). The `[nf]` detail of S0..S4 was lost to
console rolling exactly as §15.10 planned for, and every one of the 27 verdicts
survived because `bilan` reprints them. Run totals: 59 notifications / 589
octets, largest received 20 (MTU 23), 43 beats, 16 heads, 0 orphan, sizes
`16x8 7x43 20x8`, `accuses 0x2017=4`. Its `ecritures OK=0` is **not** a write
failure - the same run prints `[tx] ecriture terminee status=0 file=1` in the
error branch: the counter compared strings with `==`, see §15.13.

**Simulator + dongle measured what the camera answers, octet for octet.** Every
one of the six asks matched the physical run on declared size and on the body
octets that fit inside the 20-octet notification:

| ask | sim | watch |
| --- | --- | --- |
| 15 capture status | w=24, body `0a 06 08 00`, manque=4 | identical |
| 8 options 11+20 | w=51, body `08 0b 08 14`, manque=31 | identical |
| 8 options 11,15,16,20,30,48 | w=148, body `08 0b 08 0f`, manque=128 | identical |
| 10 photography options 11+20 | w=39, body `08 0b 08 14`, manque=19 | identical |
| 43 submode options 11+20 | w=16, no body | identical |
| 166 storage, empty body | w=16, code `0x190` | identical |

Two places where the sim must **not** be believed, both visible in the diff:

- **Seq correlation is trustworthy on the camera, and the sim's replay was a sim
  artifact**: on the watch, S8's answer carried S8's own seq (47) while S5's
  carried 41 - the content identical, the seq per rung. All 8 answers whose
  `[nf]` line survived matched `31 + 2*rungIx`, so the per-rung seq tag of §15.10
  works on hardware and §15.11's "the camera re-sends the previous answer" is
  off the hook.
- **Do not read the sim's envelope octets at `[8:10]`**: one sim answer (S12)
  printed `... c8 00 00 02 37 ...` where the camera sends `... c8 00 02 37 ...`
  (and 21 hex octets under `len=20`). The `0x2017` ack, the answer codes and the
  protobuf octets do match, so only that one envelope field is sim-made.

**An idle X5 pushes nothing at all.** The accounting closes exactly: 59
notifications = 43 beats + 16 heads, and those 16 heads are 4 `0x2017` + 2 ask-43
answers + 2 ask-166 answers + 8 ask answers. During the three listen rungs (S0 6
s, S11 10 s, S14 6 s) and during the ~2.5 min of the whole run: no `0x2003`
battery, no `0x2006` storage, no `0x2010` capture status, no `0x2040` recording,
no `0x2062`. The product therefore **cannot** learn camera state at connect by
listening - it has to ask (that is what §14's decodes of those notifications
describe: what the camera pushes when the phone drives it, not what a quiet
camera does). Bilan counted 4 `0x2017` for the 3 code-8 asks, so one arrived
unasked or late; its `[nf]` line rolled away with S0, so it cannot be placed.

Nothing above 20 octets crossed on hardware either: all four oversized answers
are `B TRONCATURE-UNIQUE` with the same missing counts as the sim (4, 19, 31,
128) and two beats of silence after. The ask-15 cut is the same shape on both
benches, and it leaves exactly one status octet inside the wall: body
`0a 06 08 00` puts **the inner field-1 value at notification octet 19** (the
`08 <v>` pair, capture status enum, read 0 with the camera idle in video). The
battery level, the storage byte counts and the rest of the capture status sit at
octets 20 and past.

v5 (next section) therefore asks three things the wall cannot answer by itself:
does that octet-19 value **move** when the camera state moves (the state matrix,
run last, since only the tail of the console survives rolling); do the ask-8
and ask-166 **body** sweeps give an answer small enough to fit, or an answer at
all; and does a **nudge** (an ack frame echoing the request seq, or a re-ask)
inside a long window pull the missing 4/19/31 octets out of a truncated answer.

### 15.13 Probe v5 built: body sweeps, truncated-answer nudges, camera-state matrix

Built by `mk_v5.py` anchored on the v4 master (archived in the repo as
`out/bench/FramingProbe-v4-source-20261104.mc`, sha `155083c6…`).
Installed source `Framing Probe/source/FramingProbe.mc` sha `5dffacf2…`,
`.prg` 143 148 B sha `6bc4dc7c…`, banner `FRAMING PROBE v5`, build `v5a07`,
`RUN_TAG v5a07` (a stale v4 resume point is therefore ignored). Compiles
against `epix2pro51mm`: `BUILD SUCCESSFUL`, 26 warnings = v4's 25 + 2 new
"Cannot determine if container access" on the new `:hint` / `:nudge` / `:hold`
rung reads, no new warning class.

**One measurement bug found in v4's own log.** The physical bilan said
`ecritures OK=0` while the same run printed
`[tx] ecriture terminee status=0 file=1` - in the *error* branch. In Monkey C
`==` does not compare two `Lang.String` by value, so
`st.toString() == "0"` was never true. v5 uses `.equals("0")`. Nothing about the
link was wrong in v4: writes completed, only the counter was blind. Trap worth
remembering for the barrel too.

25 rungs, three blocks, and the **order is itself a measurement** (the console
keeps only its tail: ~5 KB live plus a ~5 KB `.BAK`, rolling):

1. **Body sweeps** (S1..S11) - ask 8 with option 11 alone (`0a 01 0b`) and
   option 20 alone (`0a 01 14`): two options declare 51 octets, does one fit
   under 20? ask 15 with body `08 01` and `12 00`; ask 166 with `0a 01 01`,
   `08 01`, `12 00` (its empty body only earned a `0x190` refusal, so the
   carrier exists and wants an argument); ask 71 `GET_RECORDING_FILE` empty
   body; and ask 8 with a 9-option body so the **request is 27 octets** - the
   smallest MTU overrun, to find where the TX chunker cuts and whether the
   camera accepts a reassembled request. `[tx] decoupe en N ecritures` is
   printed again for that.
2. **The tail** (S12..S15) - four rungs with the window held open 12 s
   (`:hold`, no early close, since two silent beats are exactly what v4 judged
   dead). S12 is a witness with **no** nudge; S13/S14/S15 nudge: `N_ACK` sends a
   16-octet frame carrying code `0xc8` with the request's own seq (the ack the
   protocol suggests), `N_REASK` re-sends the same question with a fresh seq.
   A nudge only arms when a closed frame sits **below** its declared size, so a
   complete `0x2017` never triggers traffic; it is armed from `feed()` but sent
   from `clockTick()` three ticks later (never `requestWrite` from a BLE
   callback - that cost v3 eleven rungs).
3. **The camera-state matrix** (M16..M23, S24) - the same ask 15 (and ask 8
   option 11) asked again while the camera state is changed by hand: idle video,
   photo, recording, after stop, on the charger. A quiet camera pushes nothing
   (§15.12), so state has to be pulled, and the only status octet inside the
   wall is ask 15's inner field-1 value (`08 <v>`, notification octet 19). These
   rungs are last so their hex survives console rolling, and each carries a
   `:hint`: printed twice in the console (what this rung measures, and what to
   set up for the next one) and shown on the watch under the rung counter as
   `REGLER: ...` one rung ahead.

Answer octets now ride **inside the verdict line** (`corps=` 8 octets of body,
`queue=` first 12 octets of each of the first two headless chunks), and
`bilan` reprints every verdict - which is how a middle rung survives after its
`[nf]` lines rolled out of both console files.

**Working-tree note (same day).** The bench folder moved from
`Framing Probe/bench/` to the repository top level, `out/bench/`: a second
archived `FramingProbe*.mc` (the v4 master) sitting inside the project folder
made the VS Code build pull the v4 source into the v5 compile. Nothing in the
manifest or the jungles changed - only the location. All paths above now read
`out/bench/…`, and future anchor scripts read the v4 master from there.

### 15.14 v5 measured on the X5 firmware (simulator + nRF52840 dongle, 2026-11-04)

Full log pasted by the user (repo copy pending as
`out/bench/FramingProbe-v5-sim-20261104.log`); the watch's own v5 run follows
in the next bench. Banner `v5a07`, all 25 rungs, no wedge, and the bilan is
healthy at last: `ecritures OK=30` (the `Lang.String` fix counts what v4 could
not see), 139 notifications, `tailles: 7x103 16x14 20x22`, orphelines=0. The
link shape is v4's again: 7-octet beats about 1/s, answers capped at exactly 20.

**Body sweeps.**

- ask 8 option 11 alone (`0a 01 0b`): answer **28 octets**, body `08 0b` then
  `12 08` + an 8-octet payload. The payload begins at frame octet 20 - the first octet
  the wall hides - so the battery block is structurally invisible under the wall, and
  `morceaux=0`: the camera sent nothing after the head.
- ask 8 option 20 alone (`0a 01 14`): answer **41 octets**, `08 14` then
  `12 15` + 21 octets - every storage byte above the wall.
- ask 8 with both (`0a 02 0b 14`): **51**, as in v4 physical (the bench stays
  faithful); note 12+25 blocks would give 53, so the per-option blocks do not
  add up simply.
- ask 15 with bodies `08 01` and `12 00`: both accepted (no 400) and the answer
  is **byte-identical to the bare ask** (24, `0a 06 08 00`).
  GET_CURRENT_CAPTURE_STATUS ignores its request body; its shape is fixed:
  `0a 06` + inner {`08 <v>` visible at octet 19} + {`12 02` + 2 octets at 20..24,
  never visible}.
- ask 166 GET_STORAGE: `0a 01 01` -> `0x190`; `08 01` -> **26** (`0a 08 08 01`,
  the answer echoes the argument); `12 00` -> **36** (`0a 12 08 00`). The
  argument changes the answer size, so GET_STORAGE is argument-sensitive -
  but no argument probed so far brings the answer under the wall.
- ask 71 GET_RECORDING_FILE idle -> `0x190`, as in v4.
- ask 8 with the 9-option body (**request 27 octets, written 20+7**): the
  camera answered with the `0x2017` push that every code-8 ask earns, then
  `0x190` - a refusal of the *option content*, from a camera that **did
  reassemble the two-chunk request**. TX reassembly proven again, at 27.

**Nudges.** S12 (window held 12 s, no nudge): answer at +1.8 s, ten more beats,
nothing continues - the cut tail is gone for good. S13/S15 (bare `0xc8` header
frame, request's own seq, empty body): the camera answers **each ack with
`0x190`** and continues nothing, so a bare ack is refused outright. S14
(re-ask with fresh seq): three asks, three fresh answers, all truncated at 20
with identical `corps` - the answer is deterministic, not a lost-fragment
accident. Nothing on this link recovers octets beyond 20 for a command answer;
only the file-transfer module ever chunked (§15.9), command answers never.

**0x2017 accounting.** 7 pushes = exactly the 7 code-8 asks of the run
(S1,S2,S3,S11,S15,M20,M23): asking options always wakes `CAM_WIFI_START`.

**State matrix (M16..M23): void in this run - the user touched nothing.** The
camera stayed in one state the whole sim run, so those rungs only re-measured
the idle answer (which is itself a nice determinism proof: M16..M23 answers are
byte-identical to S4). The physical watch run (§15.15) is the one that drives
the states.

**What this closes and what it opens.** Every GET carrier probed for
battery/storage/state declares more than 20 and puts its value bytes at octet
20+; the battery push (`0x2003`, 24) cuts after `0a 06 08 <power type>` with
the level at 21..22 (§14). Under the CIQ ceiling no *ask* can deliver status.
The only shapes that could are pushes - and an X5 that has not been through
the APK's connect sequence pushes nothing at all, not even while recording. The
APK does something at connect that no probe has ever done: the code map offers
CHECK_AUTHORIZATION=39 / REQUEST_AUTHORIZATION=86 (pushes 8209 `AUTHORIZATION_
RESULT`, 8228 `CHECK_AUTHORIZATION_RESULT`), 8329 `LOGIN_REQUEST`, 8240
`HEARTBEAT_TICKING` - and the camera beats at us every second while we never
answer. v6 should try, cheaply: (1) echo the 7-octet beat back on the RW
characteristic and listen for `0x2003/0x2006/0x2010/0x2040`; (2) asks 39/86 and
watch for `0x2009/0x2024` pushes; (3) an ask 166 argument sweep (`08 00`,
`08 02`, `08 03`, `08 01 12 00`) hunting an answer that fits under the wall;
(4) ask 43 with a proper sub-mode body (the `0x2053` push shape was two
varints - a 20-octet answer is possible). The PC corpora (`ble-2026*`) would
answer (1) and (2) without any new build - they hold the APK's real connect
sequence and its real ack frames; copies belong in `out/bench/`.

### 15.15 v5 on the physical watch: identical to the bench, and one push that was not asked

Watch logs saved as `out/bench/FramingProbe-v5-phys-TXT-20261104.log` (surviving
tail: resumes 39..58 + `[fin]`) and `out/bench/FramingProbe-v5-phys-BAK-20261104.log`
(bilan + resumes 0..38). `corps=` riding inside the verdict lines did its job:
even with every `[nf]` line rolled away, the body octets of all 59 verdicts
survived. No wedge, no orphans, `ecritures OK=30`.

**Every rung byte-identical to the sim bench.** All 25: same declared sizes
(24/28/41/51/26/36/16), same `corps` (`0a 06 08 00`, `08 0b 12 08`, `08 14 12 15`,
`0a 08 08 01`, `0a 12 08 00`, ...), same verdicts, same `0x190` refusals (asks
71, 166-with-bad-body, the bare `0xc8` acks, the 9-option body), same three
identical re-ask answers, same nothing-after-20 with the window held 12 s. The
sim + dongle bench is a faithful stand-in for the X5 link, again.

**One divergence, and it is the interesting one.** bilan counts differ only in:
`notifications=138 octets=1387 tetes=37 ... 16x15` vs sim's `139/1385/36/16x14`,
and `accuses 0x2017=8` vs sim's 7. The seven code-8 asks still account for
seven of those pushes - **one `0x2017` push was unsolicited**. Its `[nf]` line
rolled out of the console, so the trigger (recording start? charger?) is not
timestamped; M18's 12 s window is the prime suspect. That breaks "an idle X5
pushes nothing" (§15.12): the idle part holds, but a state change can push to a
client that never joined any session.

**If the matrix was driven on this run** (the on-watch `REGLER:` prompts were
shown; the unsolicited push suggests at least the recording happened): mode,
record state and charger leave **no observable difference** inside the wall -
ask 15 fixed `0a 06 08 00` (24) across idle video, photo, recording, after stop
and charger; ask 8 option 11 fixed `08 0b 12 08` (28) during recording and on
charger (its 8-octet payload at octet 22+ may still differ - invisible). So
status-by-GET is closed: the values live at octet 20+ in every carrier, and the
only live channel is pushes - whose one observed sample (`0x2017`, whole, 16
octets) carries no state either, at least not in its visible 4 body octets.

v6 must therefore: timestamp pushes precisely (a `:hold` listen window around
each state change, one `[nf]` per push with dt), try joining the session
(answer the beat, asks 39/86) and see whether `0x2003/0x2006/0x2010/0x2040/0x2053`
pushes start - those pushes are the shapes that fit the wall (0x2010's body is
4 octets, 0x2053's two varints), and sweep ask 166 arguments and ask 43 with a
proper sub-mode body for any answer that finally lands under 20.

### 15.16 The PC corpora, decoded offline: the state is in the pushes, and it fits the wall

§15.14 asked for the `ble-2026*` corpora to be mined before any new build. They answer
that ask, and they reverse the conclusion of §15.15: the wall is not the problem, the
*carrier* was. Every piece of status the X5 reports sits in the four body octets a
watch-sized frame can carry (`16..19` = 20-octet ATT payload minus the 16-octet
envelope) - but only inside pushes the camera emits by itself, and only when the
camera is actually doing something.

**Tooling.** Eight decoders now live in the repo: `tools/x5_corpus_frames.py`
(envelope/label decode), `_pair.py` (question → answer pairing), `_raw_window.py`
(window of raw frames around an event), `_option_wall.py` and `_short_answers.py`
(the ask-8 size sweep), `_start_push.py` and `_push_table.py` (push inventory), and
`_push_decode_check.py` (the v6 decoder replay, below). The raw `ble-*.log` files
carry complete frames (the capture tool caps at 240 octets); the `-frames.log`
siblings are labelled but their hex is cut at 48 characters, so all decoding runs on
the raw files.

**The envelope, reconfirmed on 30 k+ frames**: `[0:4]` = u32 LE total length
including the header, `[4..6] = 04 00 00`, `[7:9]` = code LE, `[9] = 02`,
`[10:13]` = seq 24-bit LE, `[13..15] = 80 00 00`, protobuf from 16.

**§15.14 items (1) and (2): the first half holds, the conclusion is inverted (closed 2026-11-12).** Across the whole corpus the APK
never sends `CHECK_AUTHORIZATION=39` or `REQUEST_AUTHORIZATION=86`, and it never
answers the 7-octet beat on the RW characteristic. But the pushes are **not** unconditional: two independent benches
against the X5 fw 1.13.21 (PR #2 by @no84by on his side, and a one-shot probe patched
into `BLE Barrel` here) show the same gate and the same handshake, frame for frame:
`CHECK_AUTHORIZATION(0x27)` body `{1: id (≤12 chars), 2: 17 WATCH_GARMINOS}`; the camera
first answers its generic 16-octet blanket ACK (`0x2017`), then a `0x00c8` response
echoing the request's seq with body `{1: status}` (0 authorized / 1 unauthorized with
the Allow prompt on the camera screen / 2 busy / 3-6 another client of that type already
connected / 7 sleeping), and the push `0x2011 AUTHORIZATION_RESULT` carries the user's
answer on the camera. **A client that never completes this handshake receives no push at
all** - which is exactly why the months-long watch corpus holds zero pushes while its
control commands always worked. Two boundaries measured with it: the approval is per
client and per session (the same id string re-presents, the prompt reappears after a
hard link loss), and the camera serves one client slot, so `status=2/3..6` reproduces
readily on any leg holding stale bonds. Why the APK receives pushes without ever sending
39 stays open - its pairing/login flow presumably carries an implicit grant; a watch
client does not need that path, the handshake covers it end to end. The full flow,
frame for frame, is documented in `docs/x5-protocol.md` (imported from PR #2, credited);
the mainline barrel adopts the handshake at connect. What §15.15 was reaching for is
real after all - keyed to authorization, not to joining.

**Action → push timeline** (`ble-20261014-171953`/`-172014`/`-184011`/`-184026`, the
only captures containing labelled captures):

| phone sends | camera pushes, in order |
| --- | --- |
| `code 4 START_CAPTURE` body `08 01` | `0x2010 08 01 10 00 38 00`, then `0x2040 08 01` |
| `code 5 STOP_CAPTURE` body `10 01` | `0x2010 08 01 10 <sec> 38 02` → `0x2040 08 00` → `0x2006 08 00 10 00` ×2 → `0x2010 08 00 10 00 38 00` → `0x2062` (22) |

`0x2010`'s `10 <n>` is elapsed capture seconds - the `-172014` stop names 18 (`0x12`)
for a recording started at 17:20:00 and stopped at 17:20:18 - and `38 <n>` is the file
counter, so it is the one field that falls just outside the watch window. `0x2010`
field 1 is the capture state: 0 = idle (×30), 1 = capturing (×4, always with a
non-zero `sec` or one right after a start), 4 = ×28 with `sec=2` in the photo-mode
captures.

**Push inventory** (all `CAM->APP` frames in the corpus, with what the watch leg would
keep):

| push | code | body | inside `16..19` | what it gives the watch |
| --- | --- | --- | --- | --- |
| `0x2010` CURRENT_CAPTURE_STATUS | 8208 | 6 (×62) | `08 <state> 10 <sec>` | state + seconds, **whole**; `38 <n>` lost |
| `0x2040` | 8256 | 2 (×4) | `08 01` / `08 00` | record flag, **whole** |
| `0x2006` STORAGE_UPDATE | 8198 | 4 (×32) | `08 00 10 00` | **whole**; twice per written file, ~1 s after stop |
| `0x2003` BATTERY_UPDATE | 8195 | 8 (×1) | `0a 06 08 <powerType>` | charger flag only - the level is at octet 21..22, unreachable (§14, §15.15) |
| `0x2053` CAM_SUBMODE_CHANGE | 8275 | 6 (×110) | `08 <f1> 10 <f2>` | the only mode carrier inside the window |
| `0x2017` CAM_WIFI_START | 8215 | 0 (×811) | - | period 1-3 s, the "beat" the watch counts |
| `0x2065` WATCH_RES | 8293 | 6-14 (×994) | `08 1e/1f 12 <len>` | structure only, no status |

`0x2065` (8293) is the answer to `code 7 = SET_OPTIONS`: the APK writes option changes
roughly every two seconds and the camera answers twice, 200 ms apart, with
`WATCH_RES`. Its payload (`08 1e 08 28 12 06 f0 01 00 c0 02 0c 18 06`) keeps every
interesting byte past octet 19, so it is not a status carrier for the watch.

**8275 carries the option that was set.** Pairing each `0x2053` with the `SET_OPTIONS`
write that preceded it: option 40 (`0a 01 28 …`) produces `08 <value> 10 64 18 03`,
option 41 (`0a 01 29 …`) produces `08 64 10 <value> 18 03`, where `0x64`=100 marks
"this half did not change". Observed option-40 values: 0, 2, 3, 4, 5, 7; option-41
values: 0..4, 11, 12, 14. In the APK's option table those ids read
`PHOTO_RESOLUTION=40` / `REMAINING_TIME=41`, which is not how they behave here - so
whether the X5's physical mode dial also moves `0x2053`, and in which of `f1`/`f2`, is
exactly what the v6 action matrix has to measure on the watch.

**The v6 decoder, replayed against the corpus.** `tools/x5_corpus_push_decode_check.py`
mirrors `pushDecode()`/`pushNote()` from the probe source and runs them twice: on the
full corpus frame, and on the same frame cut to 20 octets as the watch leg receives it.
For all six carriers the decoded string is **identical** - `etat=1 sec=18`,
`enreg=1`, `stock f1=0 f2=0`, `charge=1`, `mode f1=100 f2=3`, `wifi`. The probe's
field offsets are therefore right, and the truncation costs nothing for these shapes.

### 15.17 v6 deployed on the watch: an action matrix, and a push table that survives the console

`out/bench/FramingProbe-v6-20261104.prg` (source `out/bench/sources/FramingProbe-v6-source-20261104.mc`,
installed as `Framing Probe/source/FramingProbe.mc`, banner `v6a01`, sha `8a77e283…`,
built `-d epix2pro51mm -l 1 -w`). Generator: `out/bench/sources/mk_v6-20261104.py`
with its two out-of-script blocks `ladder.txt` and `push.txt`; baseline sha-checked
against the v5 source in the repo, so the anchor chain survives a `/tmp` clean.

What changed, and why:

- **Raw `[nf]` lines are replaced, inside listen windows, by a per-window push table**
  (`pushNote`/`pushFlush`): dedup by `code/corps4`, counter, first offset in the
  window, decoded fields. A 15 s window around a mode change receives tens of frames;
  the table prints one line per distinct value, through `verdict()`, so `bilan`
  reprints it and the ~5 KB console tail cannot kill it. This answers §15.15's lost
  `[nf]` lines.
- **Ten windows `E0..E9` drive the camera**, not the probe: mode change, photo, start
  recording, stop, charger, mode again, with ask 15 at connect / while recording / at
  the end (E1, E5, E9) to compare the same GET under three states. The action and its
  countdown are on the watch screen and in a `>>> FAIRE MAINTENANT` console line,
  plus a vibration. The v5 physical run proved the need: its state rungs ran with
  nobody touching the camera, and measured nothing.
- **Decoded where it is read**: ask 15's answer prints `ETAT=<hex>` from the body
  string, and each known push prints its fields, so nothing depends on hex that has
  already scrolled away.
- `0x2017` suppression is skipped in table windows (the dedup handles the flood), and
  `ackSeen` resets per window so the cadence measurement stays per-window.

**Compile trap for this SDK**: `Attention.vibe(:defaultMode)` does not exist in
9.1.0 (`ERROR ... Undefined symbol ':vibe'`). The public entry is
`Attention.vibrate([new Attention.VibeProfile(duty, durationMs)])`, guarded with
`if (Attention has :vibrate)`. Note also that `-l 3` cannot type-check this file at
all (module-level `var x = null` members are rejected as untyped), so probe builds
are validated with `-l 1 -w` as all previous versions were.

**To measure** (one run, ~2 min, the operator acts on the camera when the watch
vibrates): does a physical mode change emit `0x2053` at all, and is the mode in `f1`
or `f2`; does `0x2010` distinguish photo (`etat=4`?) from video; do `0x2040`/`0x2006`
reach the watch whole as the corpus predicts; does the charger push `0x2003` show
`0a 06 08 <powerType>` on the watch as it does on the PC. Those five answers are what
`BLE Barrel/BLEBarrel.mc` needs before the parsers go in.

### 15.18 v6 measured on the bench (simulator + dongle, 2026-11-04): recording state reached

`out/bench/FramingProbe-v6-sim-dongle-20261104.log` (header only: the console files
themselves stayed on the simulator machine, the measured lines were pasted into the
session and are retranscribed below). Build `v6a01`, source sha `8a77e283…`, bench
Garmin simulator + nRF52840 dongle.

**The recording-state objective is met.** ask 15 prints its body and its state:

| window | state asked | answer body | verdict |
| --- | --- | --- | --- |
| E1, E9 | at rest | `0a 06 08 00` → `ETAT=00` | idle |
| E5 | recording | `0a 06 08 01` → `ETAT=01` | recording |

Both frames are truncated (`w=24 r=20`, the varint `want` trap of §15.7) and it does
not matter: the state byte is the fourth body byte, well inside the 20 that cross.
So `BLE Barrel/BLEBarrel.mc` can decide idle-vs-recording with one ask 15 at connect -
that is the answer §15.13 had declared unreachable through the ask route.

**The pushes arrived as the PC corpus predicted**, decoded at the source:

- `8256 (0x2040)` record flag: `08 01` on start, `08 00` on stop, received **whole in
  one block** (`w=18 r=18`, no chunking): the cheapest usable "is it recording" push.
- `8208 (0x2010)` capture status: `08 01 10 00`, `08 01 10 04`, `08 00 10 00`,
  `08 04 10 02` - the `38 <n>` tail still missing, but `etat` and the seconds field
  cross. `08 04 …` was seen once, so a photo value exists next to the video ones.
- `8198 (0x2006)` storage: `08 00 10 00` twice, ~2 s after the stop (writing the file).
  Whole, but **the storage quantity is not in the part that crosses** - both fields
  read 0 in every window, so storage stays out of reach on the watch leg.
- `8293 (0x2065)`: `08 1f 12 03` (E4) and `08 1e 08 28` (E8), four body bytes visible.
- `8290 (0x2062)`: `08 80 80 80`, partial.
- `8195 (0x2003)` battery: one push, `0a 06 08 00` at +8 s of its window. The charging
  flag is the only battery information inside the wall and this sample is not
  conclusive (charger not plugged at that moment); the level stays unreachable (§15.13).
- `8275 (0x2053)` sub-mode: only `08 64 10 00` (E4) and `08 00 10 64` (E8) - 100 being
  the "this half did not change" marker of §15.16. **Which of `f1`/`f2` is the mode
  dial is still not decided**, and only the two extreme values were seen.
- Anomaly: after the photo (E3), `code 200` carried body `0a 30 0a 2e`, which is not
  the `0a 06 08 …` shape of ask 15's answer - the camera answered 200 to something
  else in that window. Noted, not followed.

Bilan counters: `notifications=81 octets=823 tetes=20 battements=61 orphelines=0
tailles: 7x61 20x18 18x2`, `ecritures OK=3`, `accuses 0x2017=0`, 28 verdicts
reprinted by `bilan`. `0x2017` produced no acknowledgement traffic in this run, and
`tailles` confirms the 7-byte beat dominating the leg.

**What the run says about the bench itself**: the action windows were only **partly
followed**. The operator needs ~15 s between reading an instruction and acting on the
camera, and a 15 s window was half spent printing the hint lines before the `>>>
FAIRE MAINTENANT` line appeared; on the watch screen the instruction was glued to the
countdown on one line cut at 30 characters, i.e. unreadable; and the next step was
never announced. The charger rung asked for plug-and-unplug inside one 15 s window.
So the mode/charger measurements above are single, loosely timed samples. The
decision taken from this: the bench channel stays simulator + dongle, and the next
build fixes the rhythm before anything else is measured.

### 15.19 Probe v7 built: the ladder runs at the operator's pace

`out/bench/FramingProbe-v7-20261104.prg`, installed as
`Framing Probe/source/FramingProbe.mc` (banner `v7a01`, source sha `c966d70c…`,
111 524 octets, built `-d epix2pro51mm -l 1 -w`). Generator
`out/bench/sources/mk_v7-20261104.py` with its blocks in
`out/bench/sources/v7/` (`ladder.txt`, `rung.txt`, `view.txt`, `helpers.txt`,
`header.txt`, `build.txt`, `const.txt`, `globals.txt`, `begin.txt`, `clock.txt`,
`keys.txt`) and the v6-to-v7 diff as `v7/v6_to_v7-20261104.diff`. The baseline is the
installed v6 source, sha-checked before editing, so the chain is reproducible from
the repo alone.

The measurements themselves are untouched; what moved is when and how the operator is
asked:

- **`ACT_MS` = 30 s action windows, closed by a key press + a 6 s tail**
  (`TAIL_TICKS = 60` at `CLOCK_MS = 100`). Pressing any key records `keyTick`;
  `clockTick()` ends the window 6 s after the **last** press, so late pushes are
  still collected (the `0x2006` leaves ~2 s after the stop, `0x2053` ~1 s after a
  mode change) and a window that took 8 s does not run 30. Question windows use
  `ASK_MS` = 10 s and are never closed by a key: their answer closes them
  (`endWindowEarly`). A mid-window `[rappel]` line repeats the action and names the
  next step; every window now announces the **next** step when it opens.
- **Which key**: `WatchUi.InputDelegate` has no `onUpButton`/`onDownButton` on this
  VM - the method table in `bin/api.debug.xml` of SDK 9.1.0 (parent
  `Toybox_WatchUi_InputDelegate`) lists only `onKey`, `onKeyPressed`, `onKeyReleased`,
  `onSelectable`, `onDrag`, `onFlick`, `onHold`, `onRelease`, `onSwipe`, `onTap`
  (`onBackButton` itself appears 0 times in that table), and the SDK HTML names no
  button at all. So the confirmation is armed on `onKey` + `onKeyPressed`
  (`noteKey(keyEvent.getKey())`, `return false` so the event keeps travelling); any
  face button confirms, `KEY_MENU`/`KEY_POWER` never do, and the `ACT_MS` timeout is
  the fallback if no key ever arrives. Pressing a button prints
  `[touche] confirmee a +Ns` once, so the bench also learns *which* path the VM uses.
- **Quit is a two-step confirmation, armed on both paths**: since a window now closes
  on a key press, the stop button sits under the same thumb as the confirmation.
  `onBackButton` calls `noteEsc()`, and `noteKey` routes `KEY_ESC` to `noteEsc()` too,
  because which of the two this VM calls is not established - no archived log has ever
  shown `[fin] arrete par la touche` (nor `[vue] lignes d'ecran` from `onSelect`), so
  both are armed and the dedup guard (`clockTicks - escArm < 2` rejects the second call
  of one physical press) keeps them from double-firing. The first press prints
  `[touche] RETOUR appuye: la sonde CONTINUE` and arms `escArm`; a second press within
  30 s runs `stopProbe()`, which stops the rung/clock/bilan timers, closes the link and
  reprints the verdicts before popping the view.
- **Screen**: the instruction is drawn on its own lines, wrapped at 16 characters
  (`wrapLines`, `substring(from, to)` with exclusive `to`), countdown below it, next
  step below that, log lines cut at 34 instead of 30 (epix Pro 51 mm, 390 px). The
  rung number shown is `winRung`, not `rungIx`: `nextRung()` advances `rungIx` at its
  end, so the v6 screen showed the *next* rung's number during the whole window.
- **Console volume**: inside table windows (`agg=1`, which is every rung now)
  `beatFlush()` still counts beats - `beatTotal`, the wedge guard, the bilan - but
  prints nothing; one `E<n> fil: N battements ~1s, N notifications, N octets` line is
  printed at the close through `verdict()`, so `bilan` reprints it. §15.18's 61 beat
  lines against 28 verdict lines is what this removes, in a console that keeps only
  ~5 KB + its 5 KB `.BAK`.
- **Ladder 10 to 12 rungs**: the charger is now three rungs (plug / ask 15 while
  charging / unplug), because the v6 charger window asked both gestures in 15 s and
  produced one `0a 06 08 00` sample that cannot be read either way. `E1`, `E5`, `E8`,
  `E11` are the same ask 15 under four states, which is the comparison that decides
  the battery-flag polarity.

**The operator's sheet for this bench** is `out/bench/consigne-banc-v7-20261104.md`: the
twelve rungs, what each one asks on the camera, and what line has to show up. Worst
case it runs 4 min 16 (7 action windows at 30 s + 4 question windows at 10 s + the 6 s
opening listen); confirming every gesture shortens it to about 3 min 15.

**Still to be settled by this bench**: which of `f1`/`f2` in `0x2053` is the mode dial
(v6 saw only `0x64` = the "did not change" marker on one side and `0x00` on the
other); whether `0x2010` `etat=4` is the photo value; the polarity of the charging
byte in `0x2003`; and what the four visible bytes of `0x2065` mean. The ask route
stays closed for battery level, storage quantity and mode - every shape that carries
them puts the value past byte 19 (§15.13, §15.16) - so the barrel will read state
from ask 15 + `0x2040`, and mode from `0x2053` only if this bench decodes it.

### 15.20 v7 measured on the bench (simulator + dongle, 2026-11-05): charging polarity and the four ask 15s

Build `v8a01`'s predecessor `v7a01`, source sha `c966d70c…`
(`out/bench/sources/FramingProbe-v7-source-20261104.mc`), bench Garmin simulator +
nRF52840 dongle. The console files stayed on the simulator machine; the measured
lines were pasted into the session and are kept as
`out/bench/FramingProbe-v7-sim-dongle-20261105-notes.md`. This is the first bench
followed almost to the end of the ladder.

**ask 15 = capture state, and nothing else.** Four windows ask the same command under
four states, and the comparison is now readable:

| window | state of the camera | answer body seen | probe verdict |
| --- | --- | --- | --- |
| E1 | at rest, photo mode | `0a 06 08 00` | `ETAT=00` |
| E5 | recording | `0a 06 08 01` | `ETAT=01` |
| E8 | at rest, **charger plugged** | `0a 06 08 00` | `ETAT=00` |
| E11 | at rest, unplugged | `0a 06 08 00` | `ETAT=00` |

So the visible byte separates idle from recording, and **plugging the charger does not
move it** - ask 15 carries the capture state, not the power state. That closes the
comparison v6 could not read (§15.18 had one unconclusive sample).

**Charging polarity settled from the push instead**: `8195 (0x2003)` printed
`0a 06 08 01` in E7 (plug) and `0a 06 08 00` in E9 (unplug) → `08 01` = charging,
which matches the single `powerType=1` push of the PC corpus (§15.16). Two samples,
but in opposite directions, and the level is still past the wall.

**The push set arrived as designed, decoded at the source:**

- `8256 (0x2040)`: `08 01` on start, `08 00` on stop, whole in one block (`w=18 r=18`).
- `8208 (0x2010)`: `08 01 10 00` → `08 01 10 14` (20 elapsed seconds) → `08 00 10 00`.
  State and elapsed seconds cross; the `38 <n>` tail still does not.
- `8198 (0x2006)`: `08 00 10 00` twice, ~0.6 s after the stop (the corpus says 1-2 s;
  both agree on "just after the stop, twice").
- `8293 (0x2065) 08 1f 12 03` and `8275 (0x2053) 08 64 10 00` at E4 +23.7 s / +24.8 s,
  i.e. in the recording window, not in a mode window. `8290 (0x2062) 08 80 80 80`.
- **E2 and E10, the two mode-change windows, produced no `0x2053` at all.** Combined
  with §15.16 (all 110 corpus samples follow a `SET_OPTIONS` option 40/41 write), the
  physical mode dial is no longer a candidate for this push - but see the caveat below.
- Same anomaly as v6: after the photo, `code 200` carried body `0a 30 0a 2e`, which is
  not ask 15's answer shape. Reproduced twice now; noted, still not followed.

**Caveat that keeps the mode question open**: no `[touche] confirmee` line appeared in
the whole run, and the action windows ran their full 30 s. So the confirmation path
(`onKey`/`onKeyPressed`, §15.19) has never been observed to fire, and there is no
record that the mode gestures in E2/E10 were actually performed inside their windows.
The "the dial does not move `0x2053`" reading is therefore **not definitive**.

Bilan counters: `notifications=191 octets=1602 tetes=21 battements=170 orphelines=0
tailles: 16x1 7x170 20x18 18x2`, `accuses 0x2017=0`, 43 verdicts reprinted. The lean
console of §15.19 works: 170 beats printed nothing, the run's verdicts survived the
~5 KB tail, and the ladder's 43 verdict lines are what the operator read back.

**Verdict on the screen** - the one thing the operator could not follow: *"sur la
montre les instructions ne sont pas lisibles: trop long, déborde de l'écran, il faut
les scinder en 2"*. v7 wrapped at 16 and 20 characters chosen by eye, and its
countdown was frozen (a `View` returned by `getInitialView()` is never repainted by
itself). §15.22.

### 15.21 Offline re-read of the corpora: APK names pin the pushes, ask 15 has three fields, ask 43 answers empty

No new bench needed for this pass: it re-decodes the archived `out/rea/artefacts/*-frames.log`
corpora against the APK's own enum tables.

**The APK names now pin the push family** (`tools/apk_extract/message_code_map.txt`):

| code | hex | APK name | what the watch sees |
| --- | --- | --- | --- |
| 8195 | `0x2003` | `CAMERA_NOTIFICATION_BATTERY_UPDATE` | `0a 06 08 <charging>` |
| 8198 | `0x2006` | `CAMERA_NOTIFICATION_STORAGE_UPDATE` | `08 00 10 00` |
| 8208 | `0x2010` | `CAMERA_NOTIFICATION_CURRENT_CAPTURE_STATUS` | `08 <etat> 10 <sec>` |
| 8215 | `0x2017` | `CAMERA_NOTIFICATION_CAM_WIFI_START` | empty body, the beat |
| 8252 | `0x203c` | `CAMERA_NOTIFICATION_DARK_EIS_STATUS` | - |
| 8256 | `0x2040` | `CAMERA_NOTIFICATION_SUPPORT_TAKE_PHOTO_ON_REC_STATUS` | `08 01` / `08 00` |
| 8275 | `0x2053` | `CAMERA_NOTIFICATION_CAM_SUBMODE_CHANGE` | `08 <f1> 10 <f2>` |
| 8290 | `0x2062` | `CAMERA_NOTIFICATION_DASH_CAM_INFO` | `08 80 80 80` partial |
| 8293 | `0x2065` | `CAMERA_NOTIFICATION_WATCH_RES` | `08 1e/1f 12 <len>` |

Two names disagree with how the pushes behave on the wire and both readings are kept:
`8256` is named "take photo on rec status" in the APK yet it labels `START_CAPTURE`
(4) / `STOP_CAPTURE` (5) exactly as a record flag, and the PC capture tool's own table
calls it `RECORD_STATE`; `8293 WATCH_RES` behaves as the echo of `SET_OPTIONS`, not as
a watch resolution. **No conclusion is drawn from a name.**

**ask 15's answer has three fields, two of them out of reach.** 42 paired
question/answer pairs across the corpora, all `declared=8`, i.e. body
`0a 06 | 08 <etat> 10 <f2> 50 <f10>` - a nested message, of which the watch leg keeps
`0a 06 08 <etat>`:

| state | n | inner body |
| --- | --- | --- |
| idle | 40 | `08 00 10 00 50 00` |
| recording | 1 | `08 01 10 03 50 06` |
| recording | 1 | `08 01 10 05 50 06` |

The two recording samples were timed 3.9 s and 5.1 s after the camera's own
`0x2010 … 08 01` start push in the same capture, so `f2` is the **elapsed capture
seconds** - the same field as `0x2010`'s - and `f10` read 6 both times against 0 in all
40 idle samples. One field, two samples: suggestive, not decisive, and in any case both
live at body offset 4 and 6, past octet 19. Confirmed: on the watch leg ask 15 gives
the capture state and nothing else.

**`0x2006` is an event, not a quantity**: `08 00 10 00` in 32 of 32 corpus samples.

**`0x2010`'s `38 <n>` is the kind of capture, not a file counter** - this supersedes
the §15.16 reading. Full body `08 <etat> 10 <sec> 38 <kind>`: `08 04 10 02 38 03` ×28
immediately after `TAKE_PICTURE` (3), `08 01 10 <sec> 38 02` while recording,
`08 00 10 00 38 00` at idle → `kind` 0 = idle, 2 = video, 3 = photo, and `etat=4` is a
photo capture in progress. It lands at body offset 5 = frame octet 21, so the kind is
**not** available on the watch leg; photo-vs-video must come from `0x2040` / `0x2006`
instead.

**Code 43 is `PHONE_COMMAND_GET_SUBMODE_OPTIONS`** (42 = `SET_SUBMODE_OPTIONS`), and
it is a dead end on the X5. Both PC sweeps (
`ble-20261014-185803` and `-185832`) try body `0x`, `08 00`…`08 64`, `08 00 10 00`,
`10 00`, ten `00` bytes, `08 ff 01`: **every one is answered `code=200 declared=0`
(empty) and no `0x2053` follows.** The message classes exist in the APK -
`GetSubmodeOptions`, `GetSubmodeOptionsResp`, `SubmodeOptions`, `SubmodeOptionType`,
`NotifyCameraSubMode`, `CaptureStateSubmode`, `PhotoSubMode`, `VideoSubMode` - but only
as names in `messages.txt` / `runtime-messages.txt` / `messages_protobuf.txt`; no field
layout for any of them appears anywhere in the extracts. So the mode stays unreachable
through any ask, and `0x2053` is produced by the camera only as the echo of a
`SET_OPTIONS` (7) option 40/41 write (§15.16).

### 15.22 Probe v8 built: the screen is measured, not guessed (benched, §15.24)

`out/bench/FramingProbe-v8-20261105.prg` (152 572 octets, sha256 `c46a3bb9…`),
installed as `Framing Probe/source/FramingProbe.mc`: banner `v8a01`, source sha
`847e4e04…`, 114 424 octets, 0 non-ASCII. Generator
`out/bench/sources/mk_v8-20261105.py` (17 anchored edits + 3 external blocks
`out/bench/sources/v8/{fit,view,build}.txt`), idempotent, baseline sha-checked against
the installed v7 source (`c966d70c…`, archived as
`out/bench/sources/FramingProbe-v7-source-20261104.mc`), diff as
`out/bench/sources/v7_to_v8-20261105.diff`. Nothing about the measurement changed:
same ladder, same envelopes, same windows.

What the operator's verdict from §15.20 forced:

- **`fitLines()` replaces `wrapLines()`**: a line is stopped by
  `Dc.getTextWidthInPixels(text, font)` (API 1.0.0) with the font that will draw it,
  word by word, and a word wider than the screen is cut by measured characters. The
  16/20-character wrapping of v7 was chosen by eye and overflowed the epix Pro screen.
- **Each rung carries a `:scr` field** - the short screen verb (`CHANGER DE MODE`,
  `PHOTO: bouton camera`, `REC: DEMARRER`, `REC: ARRETER`, `BRANCHER CHARGEUR`,
  `DEBRANCHER CHARGEUR`, `CHANGER ENCORE MODE`) - while `:act` keeps the full sentence
  for the console line and the mid-window `[rappel]`. The screen therefore never has to
  truncate a verb.
- **Vertical steps come from `Dc.getFontHeight()`** instead of v7's fixed 16 px, and
  the log tail is cut by measured width instead of 34 characters.
- **`WatchUi.requestUpdate()` once per second** in the clock tick. This is a real bug
  fix, not cosmetics: a `View` returned by `getInitialView()` is never repainted by
  itself, `View.scheduleDraw` does not exist in this API, and no `pushView` is done -
  so v7's on-screen countdown showed the value computed when the view last happened to
  repaint. `bin/api.debug.xml` lists `WatchUi.requestUpdate` (`@since 1.0.0`).

**`.prg` files are not byte-reproducible**, which explains the sizes quoted around
this build: the same source built twice in the same project gave 152 572 and 152 524
octets, and a scratch copy of the project gave 152 492. Size comparisons across builds
are therefore meaningless; what identifies a build is its banner and its symbols -
`v8a01` and `fitLines` are in the v8 artifact and in no earlier one. Warning parity was
checked by rebuilding v7 and v8 in one identical scratch project: no new warning kind
appears in v8 (21 vs 23 "Cannot determine if container access is using container
type", 2 unreachable statements, 3 uninitialized super classes, 1 launcher-icon size).

**Build path that works on Linux for this project** (it has its own
`monkey.jungle` and no barrels, so no scratch jungle is needed):

```
cd "Framing Probe" && $SDK/bin/monkeyc -f monkey.jungle -d epix2pro51mm \
  -y ~/.local/share/insta360-ciq/rsa.der -o ../out/bench/FramingProbe-v8-20261105.prg -l 1 -w
```

No manifest change is needed for v8: same permissions, same product, same entry class.
The operator's sheet is `out/bench/consigne-banc-v8-20261105.md`.

**What the v8 bench has to answer**: that the two instruction lines and the live
countdown are actually readable on the watch; that a face button prints
`[touche] confirmee a +Ns` (never observed yet, §15.20) so the mode windows can be
proved to have been acted on; and the same four ask 15 / `0x2003` / `0x2010` /
`0x2040` measures, re-taken on a screen the operator can follow. The run is §15.24: the
measures came back, and the first two questions came back unanswered again - no face
button was observed to print the confirmation line in that run either.

### 15.23 The official watch app inventoried: the commands it really sends, and how battery and storage reach it

`insta360-epixpro51.prg` (5 615 477 B, sha256 `4d2b86d7…`, inner PRG at file+0x21,
CIQ 5.1.1, app v4.27.2) has no `Symbols` section and an empty `CodeTable(PC2Line)`,
so its methods are anonymous; they were named by resolving symbol ids >= 8388608
against the SDK `bin/api.db` (identifier -> symbol table, 3069 ids in SDK 9.3.0).
Everything below comes from that listing (`out/prg/disasm/annotated.txt`: 886
methods, 46 955 instructions) cross-checked against the PC corpora. Only listings
are kept in the repository, never the `.prg` and not the proprietary blobs.

Three classes carry the protocol:

| Data offset | role |
| --- | --- |
| `@data+0xa7b` | CameraManager: 40 methods, every command send, slot 242 = `toCamera(message, code, callback)` |
| `@data+0x2346` | BLE transport: the only class that calls `BluetoothLowEnergy.requestWrite` (`@0xcca2`); frame builder meth 694 `@0xd30c`, RX chunker meth 714 `@0xd123`, RX deframer meth 700 `@0xd2af`, ack meth 716 `@0xcd5e` |
| `@data+0x1fee` | `BleDelegate` (`setListener`, write/read state machine, `initFrameParser` `@0x9696`) |

In every send method the same P-code motif appears, which is what
`tools/prg_cmd_payloads.py` now matches (the payload is the message whose local is
passed first, found by walking back from that `lgetv` to its `lputv` and then to the
nearest `getmv`):

```
getmv 38 <sym> ; newc ; getsv 8388702 ; invoke 1 ; lputv k   ; new Xxx()
lgetv k ; spush <field sym> ; lgetv <arg> ; putv            ; fill the message
getselfv 242 ; frpush ; lgetv k ; ipushN <code> ; lgetv <cb> ; invoke 4 ; toCamera
```

**Every command the official app sends** (`out/prg/cmd_payloads.txt`, 21 send sites,
14 codes; names from the app's own `PHONE_COMMAND_*` enum class `@data+0x44ed`):

| code | name | builder meth | body message |
| --- | --- | --- | --- |
| 3 | TAKE_PICTURE | `0x3466 0x3902 0x3a38 0x3bf2 0x3c97 0x3cef` | `TakePicture` |
| 4 | START_CAPTURE | `0x3d64` | `StartCapture` |
| 5 | STOP_CAPTURE | `0x4122` | `StopCapture` |
| 7 | SET_OPTIONS | `0x3831` | `SetOptions` |
| 8 | GET_OPTIONS | `0x3a98` | `GetOptions{1 option_types}` |
| 10 | GET_PHOTOGRAPHY_OPTIONS | `0x3b6d` | `GetPhotographyOptions{1 option_types}` |
| 15 | GET_CURRENT_CAPTURE_STATUS | `0x3c67` | (empty body) |
| 22 | START_TIMELAPSE | `0x3bb4 0x3d64 0x41f3` | `StartTimelapse` |
| 23 | STOP_TIMELAPSE | `0x4122` | `StopTimelapse` |
| 39 | CHECK_AUTHORIZATION | `0x423d` | `CheckAuthorization` |
| 40 | CANCEL_AUTHORIZATION | `0x34d0` | (empty body) |
| 60 | SET_KEY_TIME_POINT | `0x38b8` | `SetKeyTimePoint`, string `com.insta360.keyTime.highlight` |
| 65 | SET_ACTIVE_SENSOR | `0x3870` | `SetActiveSensorDevice` |
| 66 | GET_ACTIVE_SENSOR | `0x40ca` | `GetActiveSensorDevice` |

That is the whole set: codes 43 (GET_SUBMODE_OPTIONS) and 166 are **never** sent by
the official app - consistent with the 13/13 empty answers measured for 43 in
§15.21. TAKE_PICTURE has six call sites (one per capture mode) and START_TIMELAPSE
three; code 22/23 and 4/5 share a builder body, hence the two `@0x3d64` / `@0x4122`
rows.

**Frame header** (meth 694 `@0xd30c`, and no `55 AA` magic anywhere): a 16-octet
header, `[0..3]` u32 LE total length including the header, `[4]`=4, `[7..8]` u16 LE
command code, `[9]`=2, `[10..13]` u32 LE = `0x80000000` flag for a request OR the
29-bit sequence (`& 0x3FFFFFFF`), `[14..15]`=0, then the protobuf body. The transport
splits a body over several 20-octet writes and reassembles the far side with meth
714 `@0xd123` + meth 699/700, so multi-notification frames are the normal case, not
an error.

**What the app does with pushes** (meth `0x3e07` in the CameraManager branches on
exactly nine notification ids and news one message class each,
`out/prg/notif_blocks.txt`; a second dispatch sits at `0x129f0..0x12a78`):

| id | hex | message class the app parses |
| --- | --- | --- |
| 8209 | `0x2011` | `NotificationAuthorizationResult` |
| 8208 | `0x2010` | `CaptureStatus` |
| 8195 | `0x2003` | `NotificationBatteryUpdate{1 battery_status}` |
| 8201 | `0x2009` | `NotificationCaptureStopped{1 err_code, 2 video}` |
| 8293 | `0x2065` | `GetPhotographyOptionsResp` (see "Answer codes" below) |
| 8275 | `0x2053` | `NotifyCameraSubMode{1 photo_submode, 2 video_submode}` |
| 8198 | `0x2006` | `NotificationCardUpdate{1 state, 2 location}` |
| 8214 | `0x2016` | `TempState` |
| 8291 | `0x2063` | `GetOptionsResp` (the same option answer, push form) |

Eight of the nine are matched twice, once in meth `0x3e07` and once in the second
dispatch (`ipush2` at `0x129f0`, `0x12a01`, `0x12a12`, `0x12a23`, `0x12a34`, `0x12a56`,
`0x12a67`, `0x12a78`); `0x2011` appears once. Counting integer constants across all 886
methods (`out/prg/notif_ids_in_prg.txt`) shows the ids the app ignores: `0x2017`
(8215, the beat), `0x201B` (8219), `0x203C` (8252), `0x2040` (8256, the record flag the
probe reads) and `0x2062` (8290) appear **zero** times, although four of them are on the
wire (§15.16, §15.20). The official app therefore tracks capture state from `0x2010`
alone, not from `0x2040`.

**The option lists are data, not code.** `tools/prg_arrays.py` decodes the integer
constant arrays of the Data section, whose entries were decoded as

```
03 <u32BE len>  da7ada7a <u32BE len2 = 5+5n>  05 <u32BE n>  n * ( 01 <u32BE value> )
```

and the operand of `apush N` is that entry's offset inside the Data section. 29
arrays were decoded (`out/prg/arrays_decoded.txt`); the option-relevant ones and
their call sites:

| `apush` | array | asked where | callback |
| --- | --- | --- | --- |
| 39806 | `[11]` battery_status | meth 984 `@0x143a7` -> `GetOptions` `@0x3a98` | `0x127bc` |
| 39830 | `[20]` storage_state | meth 1023 `@0x13c2f`, meth 992 `@0x13fc8` | `0x1279f`, `0x14331` |
| 39714 | `[40, 41, 11, 20, 166]` | returned by meth 1047 `@0x14a26` (connect-time status read) | - |
| 39878 / 39902 / 39758 / 39782 / 39854 | `[40]`, `[41]`, `[1]`, `[2]`, `[29]` | single-option reads | - |
| - | `[31, 41]`, `[40, 30, 41]` | `GetPhotographyOptions` `@0x3b6d` from meth 253 `@0x13a0c` | `0x13626` |

Two independent cross-checks pin the `[40, 41, 11, 20, 166]` list: the response
handler `syncOptionFromCamera` (meth `0x14a67`, log string `option
syncOptionFromCamera:`) iterates the answer and branches on exactly option ids
40, 41, 11, 20, 166; and those five numbers are exactly the `Options` protobuf
fields `photo_sub_mode`, `video_sub_mode`, `battery_status`, `storage_state`,
`long_battery_mode_enabled` (`out/prg/schemas.txt`, `Options @data+0x64c1`, 113
fields whose field number *is* the option id - extracted by `tools/prg_schemas.py`
from the `initialize()`/`print()` pairs of the 110 message classes). The wire
request itself was never observed: the PC app reads options in pages of 20
(`out/prg/optlists_corpus.txt`, 63 distinct lists over 850 ask-8 requests), so the
batch form is inferred from the app, not measured.

**How battery reaches the watch.** Ask `GET_OPTIONS` (8) with `option_types=[11]`;
the answer is `GetOptionsResp{1 option_types (unpacked), 2 Options{11:
BatteryStatus}}` and `BatteryStatus` is `{1 power_type enum, 2 battery_level
uint32, 3 battery_scale uint32, 4 battery_type enum}`. On the wire the option-11
value is always 6 octets: `08 01 10 32 20 00` = `{1=1 2=50 4=0}` x158 and
`08 00 10 64 20 00` = `{1=0 2=100 4=0}` x32, then single steps as the battery drains
(`10 30` = 48, `10 2f` = 47, `10 2e` = 46 ...) - `out/prg/wire_status_values.txt`.
`power_type` 1 = charging, the polarity the v7 bench measured on the push (§15.20:
`08 01` with the charger plugged). Live changes come as push `0x2003` whose body is
`NotificationBatteryUpdate{1: BatteryStatus}`, e.g. `0a 06 08 01 10 27 20 00`
(power_type 1, level 39). The app's own option-11 read is meth 984 `@0x143a7`:
`GET_OPTIONS([11])` with callback `0x127bc`, which calls the generic handler `0x1279f`
and then `0x12188`, the method that keeps the new level and drives the battery display
(log strings `battery scale:` / `battery level:`). **This is the PC leg's route**: on the
watch leg the same ask crosses as `08 0b 12 08` and stops - id and length only, the
`BatteryStatus` block begins at frame octet 20 (§15.14, §15.24).

**How storage reaches the watch.** Ask `GET_OPTIONS` with `option_types=[20]`; the
answer carries `Options{20: StorageState}` = `{1 card_state enum, 2 free_space
uint64, 3 total_space uint64, 4 location enum}`. On the wire that value is always 18
octets, e.g. `{1=0 2=254456889344 3=255802212352 4=0}` - 254 456 889 344 free of
255 802 212 352 bytes (236.98 of 238.24 GiB, the X5's own card). **The card push
`0x2006` carries no sizes at all**: `NotificationCardUpdate` has only
`{1 state, 2 location}`, matching the 32 bodies `08 00 10 00` seen in §15.16. So a
card push only says "re-read": the quantities are available through option 20 and
nothing else - **on the PC leg**. On the watch leg option 20 crosses as `08 14 12 15`
(id plus the 21-octet length prefix) and the payload never arrives (§15.14, §15.24), so
the barrel has the "re-read" event and no quantity.

**Answer codes.** A command answer does **not** carry the request's code: every
GET_OPTIONS and GET_CURRENT_CAPTURE_STATUS answer in the corpora arrives as code
**200 (0xC8)** (`out/prg/codes_corpus.txt`: 8961 RX frames of code 200 against 850 ask-8
and 42 ask-15 requests), which is what §15.20's "`code 200` carried body `0a 30 0a 2e`"
already showed. On top of that the app dispatches `0x2063` as `GetOptionsResp` and
`0x2065` as `GetPhotographyOptionsResp`: the option data also arrives as a push, and
`0x2065` (994 frames) is the partner of the PC app's dominant traffic, code 9 x4591 /
code 10 x3246 - so §15.16's guess that `0x2065` answers `SET_OPTIONS` (7) is replaced
by the app's own class name: it answers the photography-options pair 9/10. `0x2063`
itself was never seen in the PC corpora, so the push form of the option answer stays an
app-side reading; what is measured is that plain command answers are code 200.

**The same answers also carry the camera's identity** (measured in
`out/prg/frame_layout.txt`): option 15 `serial_number` = `IAHEA2503S6GEW`, option 30 =
firmware `v1.13.21`, option 48 = model `Insta360 X5`, option 16 = an app session uuid.

**Where the values sit in a real answer** (`tools/x5_frame_layout.py`, four measured
answers, `out/prg/frame_layout.txt`):

| ids asked | body | option 11 value at | option 20 value (18 o) at |
| --- | --- | --- | --- |
| `11, 15, 20` | 53 o (frame 69 o) | body+10..15 | body+35..52 |
| `11, 15, 20, 30, 77, 93` | 76 o | body+16..21 | body+41..58 |
| 89 ids | 132 o (frame 148 o) | body+16..21 | body+89..106 |

A 20-octet notification carries body octets 0..19, then 20..39, and so on. So the
battery value is always inside the first notification, while the free/total pair
straddles the second and third (or, for the 89-id read, the fifth and sixth).

**The reassembly machinery is real, and it does not make these answers reachable.**
§15.13, §15.16 and §15.19 concluded that battery level and storage quantity are
unreachable on the watch leg because the value sits past frame octet 19; §15.23 first
read that as *one notification only*, because the official app's transport clearly
reassembles pieces: meth 714 `@0xd123` feeds chunks to `initFrameParser` `@0x9696`, meth
700 `@0xd2af` keeps them until `frame[0..3]` (the declared total) is reached, meth 716
`@0xcd5e` acknowledges each piece. That inference is **falsified by the bench**, and the
original §15.13/§15.16/§15.19 conclusion stands: across all eleven bench logs on disk,
every `GET_OPTIONS` answer cut by the wall crossed as exactly 20 octets with **zero
continuation pieces**, from 28 octets declared up to 148, and re-asking did not help
(§15.24). Reassembly is worth building - one code really does stream, `GET_FILE_LIST` -
but the octet table above is a PC-leg layout, not a watch-leg route to the battery and
storage values.

**Recording state** closes the loop the v6/v7 bench opened (§15.18, §15.20): ask 15 has
an empty body and the answer is `GetCurrentCaptureStatusResp{1:
CaptureStatus{1 state, 2 capture_time, 10 duration}}`, which is exactly the 8-octet
body measured in §15.21 - `0a 06 08 00 10 00 50 00` for the 40 idle samples, `0a 06 08
01 10 05 50 06` for a recording one. The app's handler `0x13432` reads the manager
status and tests `== 2` before calling the recording-started path (meth 276 `@0x13c79`),
and the live path is the `0x2010` push, whose body is a whole `CaptureStatus`
(`08 <state> 10 <sec> 38 <kind>`, §15.21).

**What this means for the barrel (corrected by §15.24).** The official app's connect-time
status read is one `GET_OPTIONS` for `[40, 41, 11, 20, 166]` plus
`GET_CURRENT_CAPTURE_STATUS`, and its live updates come from `0x2010` (capture state and
seconds), `0x2003` (battery) and `0x2006` + a re-read of option 20 (storage). That is what
the **phone** leg receives. The watch leg receives strictly less from the same questions:
ask 15 returns only the capture state (frame octet 19), `0x2010` returns state + seconds,
`0x2003` returns the charging flag only, `0x2006` carries no sizes, and ask 8 `[11]`,
`[20]`, `[11, 20]` (and ask 10 `[11, 20]`) cross only their option ids plus the length
prefix of each value (§15.14, §15.24). **Battery level and storage sizes are therefore not
obtainable by command on the watch leg as this firmware stands**, and the barrel should
show recording state, capture seconds, the charging flag, the (ambiguous) mode and
"storage changed" events - and no battery percentage or free-space figure until a bench
actually brings one back.

**Artifacts and tools added for this section**: `out/prg/cmd_payloads.txt` (the
table above), `cmd_inventory.txt`, `notif_blocks.txt` / `notif_dispatch.txt`,
`schemas.txt` + `schemas.json` (110 message schemas) from `tools/prg_schemas.py`,
`arrays_decoded.txt` from `tools/prg_arrays.py`, `optlists_corpus.txt`,
`options_corpus.txt`, `answers_corpus.txt`, `corpus_bodies_by_code.txt` from
`tools/x5_corpus_full.py` / `x5_corpus_options.py` / `x5_corpus_answer.py`, and the
class listings `out/prg/class_a7b.txt` / `class_2346.txt`. `tools/prg_commands.py`
is kept but its scope is narrower than its output suggests: its
`out/prg/uses.txt` "code NNN" rows for class `@data+0x44ed` are the app's own
command enum (values do match the codes above), but its `senders:` attributions rest
on the unverified "command registry" reading and must not be used - use
`prg_cmd_payloads.py` for sends.

### 15.24 v8 measured on the bench (simulateur + dongle nRF52840, 2026-11-05): the 20-octet wall belongs to Connect IQ, and ask 15's state octet sits exactly on it

**Run identity.** Banner `v8a01`, source sha `847e4e04…`, artifact
`out/bench/FramingProbe-v8-20261105.prg` (152 572 octets, sha `c46a3bb9…`) with its
`.prg.debug.xml`, operator sheet `out/bench/consigne-banc-v8-20261105.md`, no manifest
change (§15.22). Channel: Garmin simulateur on the Windows machine + nRF52840 dongle, the
same channel as the v6 and v7 benches.

**Provenance, stated once and remembered through the whole section**: the console files
stayed on the simulator machine, and `out/bench/` holds no v8 console dump (the logs on
disk are the v3-v6 bench logs and the two physical runs). What follows is the relevé taken
off the console during the run, like §15.20's notes file, not a re-readable log. The dump,
when it comes over, belongs at `out/bench/FramingProbe-v8-sim-dongle-20261105.log`.

**Ladder counters** (`[fin] echelle terminee`, 12/12 etages, 41 verdicts reprinted):

```
[bilan] notification la plus grande recue = 20 octets
[bilan] notifications=118 octets=1108 tetes=22 battements=96 orphelines=0
[bilan] tailles: 7x96 20x20 18x2
[bilan] accuses 0x2017=0
```

The histogram and the totals agree (`96x7 + 20x20 + 2x18 = 1108`, `96 + 20 + 2 = 118`), and
`96 battements + 22 tetes = 118 notifications`: **every notification of this run was either
a keep-alive beat or a frame head - no headless continuation at all**. 4 writes were
accepted (`ecritures OK=4`, the four ask 15), 0 relance was emitted, and 0 orphan over 118
notifications means the buffer-to-the-declared-total model held again on the watch leg.

Two of those counters need no protocol explanation, and it matters that they are not read
as findings:

- **`relances=0` is by design**: the v6/v7/v8 ladders set no `:nudge` field
  (`FramingProbe.mc:2439` reads `rung[:nudge]` and defaults it to 0), so the recovery route
  was never armed in this run.
- **`accuses 0x2017=0` is expected**: `0x2017` is the legacy 16-octet reception ACK that
  every `GET_OPTIONS` (code 8) ask earns - earlier benches counted 3, 4, 7 and 8 of them
  for their code-8 asks (§15.11, §15.12, §15.14, §15.15) - and the v6+ ladders never ask
  code 8. Nothing was lost on the link; nothing was asked that earns an ACK.

**Run quality: the same reserve as §15.20.** No `[touche] confirmee a +Ns` line appeared
anywhere in the run, and every action window ran its full 30 s with the mid-window
`[rappel]`. v8's screen work therefore has **no operator score recorded in this run**, and
the two questions §15.22 put to it - are the two measured lines plus the live countdown
actually readable, and does a face button print the confirmation - stay open. What this run
does measure is the wire: the four ask 15s and the pushes.

**The 20-octet ceiling is settled: it is a Connect IQ property, not a camera or dongle
choice.** The evidence, all of it re-runnable:

- `bin/api.db` of SDK 9.3.0 contains no `Mtu`, `MTU` or `mtu` identifier - zero occurrences
  of those three byte sequences in the whole identifier/symbol table. The only `request*`
  identifiers in the entire API are `requestApplicationWake`, `requestBond`,
  `requestPlaybackProfileUpdate`, `requestRead`, `requestUpdate`, `requestWrite`: there is
  no MTU request to make.
- `grep -ri mtu` over the SDK's whole `doc/` tree (including `doc/Toybox/BluetoothLowEnergy/`)
  and its samples returns nothing at all.
- The published BLE module page has no MTU or PDU object: its classes are `BleDelegate`,
  `Characteristic`, `Descriptor`, `Device`, `Service`, `Uuid` and the enums `ScanState`,
  `ConnectionState`, `WriteType`, `ConnectionStrategy`.
- `doc/Toybox/BluetoothLowEnergy/Characteristic.html` says in two places: *"Requesting a
  write on a characteristic longer than 20 bytes will cause an InvalidRequestException"*,
  and for `requestRead()`: *"Support for long reads is not implemented."*
- The official prg never calls `requestRead` and never writes a descriptor
  (`out/prg/api_usage.txt`: `registerProfile` x1, `getService` x1, `getCharacteristic` x1,
  `requestWrite` x1), so it does not negotiate anything either - it just reads 20-octet
  pieces and reassembles them (§15.23's meth 694 header builder, meth 716 buffer/cursor
  through self-fields 722/723, meth 714 `getsv 8391251` write).

So the watch's BLE layer neither asks for, reports, nor can negotiate a larger PDU, and the
only mechanism available for an answer over 20 octets is concatenation to the declared total
in `frame[0..3]`. The question carried since §15.4 is closed: **plan for reassembly, do not
plan for a bigger MTU.**

**ask 15 sits exactly on the wall, and its state octet is the last octet that crosses.** The
answer is declared 24 = 16-o envelope + 8-o body (`GetCurrentCaptureStatusResp{1:
CaptureStatus{1 state, 2 capture_time, 10 duration}}`, §15.21), so one 20-octet notification
carries body bytes 0..3 = `0a 06 08 <state>`: the state is at frame octet 19, the last octet
inside the window. Every v8 ask 15 (E1 at rest, E5 during recording, E8 with the charger
plugged, E11 at rest) read the same shape:

```
f0 rep=0xc8 w=24 r=20 manque=4 mor=0 clos=<frontiere> -> B TRONCATURE-UNIQUE
corps=0a 06 08 00  ETAT=00
```

The four `ETAT=00` - including E5 - must **not** be read as "ask 15 hides the state". The
state octet is one of the 20 octets that crossed (`r=20`), and both earlier benches on this
same channel measured the opposite: §15.18 (v6) and §15.20 (v7) each recorded `0a 06 08 01`
-> `ETAT=01` at their E5 recording rung. So the v8 E5 reading means the camera was **not
recording** when that rung asked, which is precisely what the missing `[touche] confirmee`
reserve warns about: with no confirmed gesture, the recording rung's precondition is not
established. What never crosses on the watch leg is only the tail, `10 <sec> 50 <n>` (frame
octets 20..23). Keep ask 15 as the connect-time state question - it is the cheapest thing
that crosses the wall - and take elapsed seconds from the `0x2010` push instead.

**Pushes decoded live on the watch leg.** `pushDecode()` reads frame octets 16..19, i.e.
exactly what survives the wall; these values are the relevé taken during the run and are not
re-checkable until the console dump is on disk:

| push | octets seen | reading |
| --- | --- | --- |
| `0x2010` (8208) `CURRENT_CAPTURE_STATUS` | `08 04 10 02`, `08 00`, `08 01 10 00`, `08 01 10 06` | state and seconds cross, the `38 <n>` tail never does. `state=4` is not new: the PC corpora already recorded `08 04 10 02 38 03` x28 (§15.6, §15.16), so the value is attested - only its name is missing, `state` 0 and 1 being idle and recording |
| `0x2040` (8256) recording flag | `08 01` then `08 00`, frames complete (`w=18 r=18`) | same as v6/v7; these are the two 18-octet notifications of the histogram |
| `0x2006` (8198) `NotificationCardUpdate` | `08 00 10 00` x2 | carries no sizes at all, which is exactly §15.23's reading: a card push means "re-read option 20" |
| `0x2003` (8195) `NotificationBatteryUpdate` | `0a 06 08 01` then `08 00` | charging flag crosses, level (frame octet 20+) never does; seen only around the charger rungs |
| `0x2053` (8275) `CAM_SUBMODE_CHANGE` | `08 00 10 64`, then `08 64 10 00` | the same 0 / 100 ambiguity v6 and v7 left open (§15.20) |
| `0x2065` (8293) photography-options | `08 1e 08 28`, `08 1f 12 03` | partner of the option pair 9/10 (§15.23), still undecoded |
| `0x2062` (8290) `DASH_CAM_INFO` | `08 80 80 80`, once | declared 22, 4 octets of 22 crossed (§15.6) |

`0x2040` and `0x2062` - and also `0x2015`, `0x2017`, `0x201B`, `0x203C` - have **zero**
integer occurrences anywhere in the official watch prg (`out/prg/notif_ids_in_prg.txt`), yet
the camera pushed `0x2040` and `0x2062` on the watch leg. The official watch app does not
handle them; the decoders above are ours, built from the PC corpora shapes, so keeping them
correct is our responsibility alone.

**What decides whether an answer continues is the declared size, not the command code.**
Counted over all eleven bench logs on disk (`out/bench/*.log`: v1, v2, v3c, v3 physical,
v4 sim/physical, v5 physical, v6), pairing every cut frame with the ask that earned it:

| ask | declared / crossed / extra pieces | continuation? |
| --- | --- | --- |
| 8 `GET_OPTIONS` | 28 / 20 / 0, 41 / 20 / 0, 51 / 20 / 0 (x3), 148 / 20 / 0 | no, at any size up to 148 |
| 10 (photo options `[11,20]`) | 39 / 20 / 0 (x4) | no |
| 15 `GET_CURRENT_CAPTURE_STATUS` | 24 / 20 / 0 (x6+) | no |
| 66 `GET_ACTIVE_SENSOR` | 475 / **40 / 1** (§15.4) | **yes** |
| 8 `GET_OPTIONS` (the 107-octet ask) | 2445 / **60 / 2** (§15.4, that run's own TX jam cut it short) | **yes** |
| 13 `GET_FILE_LIST` | 66 / 20 / 0, 113 / 20 / 0, 161 / 20 / 0, **256 / 36 / 1**, 493 / 53 / 2, 968 / 88 / 4, 1026 / 106 / 5, 2393 / 240 / 11, **4008 / 380 / 18**, **4198 / 420 / 20** | **yes** |
| pushes `0x2003` 24/20/0, `0x2010` 22/20/0, `0x2062` 22/20/0 | | no |

Two lines do the work: `GET_OPTIONS` at 148 declared gets **no** continuation while the same
code at 2445 gets two, and `GET_FILE_LIST` at 66/113/161 gets none while 256 upward gets some.
So the switch is a threshold on the declared total - somewhere between 148 and 256 - not the
command and not the module. And what crosses is strikingly proportional: 36/256, 53/493,
88/968, 106/1026, 240/2393, 380/4008, 420/4198, i.e. **almost exactly one tenth of the
declared frame every time**, which does not look like the probe's 8-second window and looks
like the camera's own pacing (send a chunk, wait to be asked for the next). Both readings are
worth testing; the useful consequence is that a **big-enough** answer does deliver more than
20 octets on the watch leg.

**The recovery route is measured too, and it is negative.** The v5 physical run armed the
two recovery rungs (§15.14): `S13 ask 15 + relance accusete 0xc8` and `S14 ask 15 + relance
re-question (seq neuf)`, plus `S15 ask 8 11+20 + relance accusete 0xc8`. Measured, in the
same order: the re-send with the answer's code earned **two `0x190` (400) error frames** and
the original 20-of-24 truncation; a fresh ask with a new seq earned **three identical 20-of-24
answers**, never the tail; and the code-8 ask with a relance still crossed 20 of 51 with
`corps=08 0b 08 14` and `mor=0`. Re-asking reproduces the truncation, it does not complete it
(`out/bench/FramingProbe-v5-phys-BAK-20261104.log`, resume 26..38).

**What crosses for the two status fields the barrel wants:**

```
ask 8 [11]   declared 28, crossed 20, corps=08 0b 12 08   -> id echo (2 o) + the Options
             field tag and length (2 o); the option-11 entry itself (tag 5a + len 06 + the
             6-octet BatteryStatus) is body[4..11] = frame octets 20..27: all of it outside
ask 8 [20]   declared 41, crossed 20, corps=08 14 12 15   -> id 20 + length 21; the storage
             payload is frame octets 20..40: all of it outside
ask 8 [11,20] declared 51, crossed 20, corps=08 0b 08 14  -> the two ids only
ask 10 [11,20] declared 39, crossed 20, corps=08 0b 08 14 -> the two ids only
push 0x2003  declared 24, crossed 20, body 0a 06 08 <pt>  -> power_type only, level at
             frame octet 20..21: outside
```

Note the arithmetic closes exactly, which is what makes the layout trustworthy: `ask 8 [11]`
= 16 + (`08 0b` + `12 08` + `5a 06` + 6 value octets) = 28 declared, and `ask 8 [11, 20]`
= 16 + (`08 0b 08 14` + `12 1d` + the same 8-octet entry + `a2 01 12` + 18 value octets)
= 51 - both measured, both matching §15.23's `frame_layout.txt` block sizes.

That is the arithmetic behind §15.13/§15.16/§15.19's conclusion, now closed on both sides:
the wall is a Connect IQ property (§ above), the camera does not continue a command answer,
and re-asking does not help. Battery **level** and storage **sizes** are out of reach on this
leg today - by 1 octet for the charging-adjacent level, by 8 for the whole battery block, by
21 for storage.

**What this means for the barrel - proven versus still inferred:**

- Proven on the watch leg: ask 15 with an empty body answers as code `200 (0xC8)` declaring
  24, and its state octet crosses; `0x2040` and `0x2006` arrive whole; `0x2003` carries the
  charging flag; `0x2010` carries state + seconds; 0 octets were orphaned across 118
  notifications. Command answers are capped at one 20-octet notification (so buffering is
  only needed for `GET_FILE_LIST`), and 0 relance was needed to keep the link alive.
- **Closed for the shapes tried, open for one untried shape**: battery level and storage
  sizes by command. Ask 8 `[11]`, `[20]`, `[11, 20]` and ask 10 `[11, 20]` were all asked on
  the watch leg in v4/v5 and all crossed their ids with the value block starting at frame
  octet 20; relancing did not help (§ above); no envelope choice changes the 20-octet
  notification ceiling, and the UCD2 leg of §15.6 was never answered by this firmware. But
  the size threshold above opens a door that has never been tried: **ask a `GET_OPTIONS`
  whose answer is big enough to continue.** A `GetOptionsResp` body is `{1 repeated ids}`,
  then `{2 Options}` where `Options` holds one entry per id under that id's field number, so
  entries come out in ascending id order - padding therefore has to use ids **above** 20.
  From the PC corpora (`out/prg/options_corpus.txt`) the long values at id > 20 are 22 (112 o),
  39 (340 o), 81 (340 o), 16 (45 o), 37 (38 o), 36 (35 o). Predicted wire sizes, built the way
  the measured answers are built (`08 <id>` per echoed id, `12 <len>` before the `Options`
  block, then `<tag> <len> <value>` per option):
  - `ask 8 [11]` → 8 + 2 + 8 = 12 body → **28 declared**, and measured exactly that.
  - `ask 8 [11, 20]` → 4 + 2 + 8 + 21 = 35 body → **51 declared**, again measured exactly.
  - `ask 8 [11, 20, 39]` → 6 + 2 + 8 + 21 + 343 = 380 body → **396 declared**; at the measured
    one-tenth pacing about 40 octets cross, covering body 0..39, and the option-11 entry sits
    at body 8..15 while the option-20 entry sits at body 16..36 - **both values inside**.
  - `ask 8 [11, 20, 39, 81]` → 8 + 2 + 8 + 21 + 343 + 343 = 725 body → **741 declared**, about
    74 octets expected: the same two values with more margin.
  - `ask 8 [39]` alone → 2 + 2 + 343 = 347 body → **363 declared**: a pure test of whether
    padding alone flips a code-8 answer into continuation mode, before spending a rung on it.
  These are predictions derived from two measured facts (the encoding of the small answers, the
  pacing of the big ones); they are exactly the kind of rung v9 exists to falsify.
- Design rule for `BLE Barrel/BLEBarrel.mc`: buffer by the declared total in `frame[0..3]`,
  treat the next beat or head as the frontier that closes a frame, match answers by code 200,
  decode by protobuf tags and never by offsets (the offsets move with the set of ids asked -
  `frame_layout.txt`: option 11 at body+10 for `[11, 15, 20]`, body+16 for the 89-id read),
  and keep the state model push-driven: ask 15 once at connect, `0x2010` and `0x2040` for
  live capture state and seconds, `0x2003` for the charging flag, `0x2006` as a
  "storage changed, re-read" event with no numbers attached.

**Files added or used for this section**: `out/bench/consigne-banc-v8-20261105.md`,
`out/bench/FramingProbe-v8-20261105.prg` (+ `.prg.debug.xml`); no v8 console log on disk.
Analyzers re-run to check the claims above: `tools/prg_analyze.py` (modes
`registry|uses|cls|method|grep|msgs|callers|body`, default `--api-db` of SDK 9.3.0),
`tools/prg_cmd_payloads.py`, `tools/prg_schemas.py`, `tools/prg_arrays.py`,
`tools/x5_frame_layout.py`, `tools/x5_corpus_full.py`, `tools/x5_corpus_options.py`.

## 15.25 The padding route, recomputed from the corpus - and the v9a03 probe that tests it

Section 15.24's padding predictions were arithmetic on **assumed** entry sizes (343-octet option
39, and a 21-octet option 20 taken once). They are now **recomposed from the corpus**: 8 961
code-200 answers in `out/rea/artefacts/ble-2026*.log` were parsed and, for every option id asked
by v9, the **exact bytes of its entry** inside the `Options` block were collected with their
lengths and frequencies (`tools/v9_expect.py`). Three facts fall out, and the first two change
the numbers:

1. **`Options` entries come out in ascending id order** - counted, not assumed: of the 3 551
   code-200 answers whose `Options` block is non-empty, **3 551 are strictly ascending** by id, 0
   descending, 0 any other order (507 further answers have an empty block; 123 answers pack field 1
   as wiretype 2 and are outside this accounting). So padding must use ids **greater than 20**:
   option 6 has a 343-octet entry, but it is answered *before* 11 and 20, and would bury both.
   `ask 8 [6,11,20]` declares 146 (short) or 397 (full) and crosses body 0..33 when it crosses at
   all: the 6 entry is read across (`opt6 21/340o`) and 11 (body 352) / 20 (body 360) are never
   reached. v9 does **not** send that question - it is only modelled in `tools/v9_expect.py` as the
   counter-example. Its control rung is Q6 = `MK_LEGBIG`, ask 8 ids **1..89** (a 91-octet body),
   recomputed at **714 declared** with short entries / **1 700** with full ones, and that rung shows
   the other half of the same fact: the head that re-reads 89 ids is itself 178 octets, so the 11
   entry sits at body **238** (short) / **484** (full) and the 20 entry at **334** / **580** - far
   past the 59-100 / 142-239 that cross. Q6 is a control for *continuation*, never a way to read
   battery or storage.
2. **Several ids answer empty or full depending on state** - 30 (3/11), 37 (3/41), 39 (3/344),
   81 (4/344) - so every question containing them has **two declared sizes**, and the run will
   show which branch this X5 is in. Fixed-size ids used for padding: 22 (115 o), 36 (38 o),
   48 (14 o), 158 (25 o), plus 11 (8 o) and 20 (17 short / 21 full).
3. **Entry shapes dominate**: 10 982 entries are `tag varint + value varint` (id 2 -> `10 00`,
   id 24 -> `c0 01 e8 07`) against 3 021 sub-messages; battery (11) and storage (20) are the
   sub-message form.

Declared totals, recomposed per branch (short = every answered id in its shortest form, full =
its longest), with the crossed band from the measured pacing rule (8.4 % - 14.1 % of the declared
total above the threshold, zero below it, threshold between 161 and 256 as measured):

| rung | ask 8 ids | declared | body | crossed expected | option 11 entry (body) | option 20 entry (body) |
| --- | --- | --- | --- | --- | --- | --- |
| Q0 | `[11,20]` | 47 / 51 | 31 / 35 | 0 (the wall, must stay) | 6..13, needs 14 | 14..30, needs 31 |
| Q1 | `[11,15,16,20,30,48]` | 136 / 148 | 120 / 132 | 0 (already measured at 148) | 14..21 | 86..102 |
| Q2 | `[11,20,39]` | 52 / **398** | 36 / 382 | 0 / **33..56** | 9..16, needs 17 -> **in** | 17..37, needs 38 -> at the edge |
| Q3 | `[11,20,39,81]` | 58 / **744** | 42 / 728 | 0 / **62..104** | 11..18, needs 19 -> **in** | 19..39, needs 40 -> **in** |
| Q4 | `[11,20,22,36,37,39]` | 215 / **598** | 199 / 582 | 18..30 / **50..84** | 15..22, needs 23 | 23..43, needs 44 |
| Q5 | `[11,20,22,36,48,158]` | **249 / 253** | 233 / 237 | **20..35** (band) | 16..23, needs 24 -> at the edge | 24..40, needs 41 -> out |
| Q6 | ids `1..89` (`MK_LEGBIG`, control) | **714 / 1 700** (lower bound) | 698 / 1 684 | **59..100 / 142..239** (2 pieces already measured) | 238..246 -> out | 334..351 -> out |

Section 15.24's `396`/`741` are superseded by `398`/`744`: the corpus entry for 39 is 344 octets,
not 343, and full option 20 is 21. Q5 is the bisection rung: its two declared totals, 249 and
253, sit **inside the 161-256 band** with constant-size padding, so it measures where the switch
really is rather than assuming it.

Q6's total is a **lower bound**: of the 89 ids that rung asks, 26 are never answered anywhere in
the corpus (5, 9, 10, 12, 13, 23, 28, 32, 35, 38, 42, 47, 49, 50, 52, 53, 55, 57, 59, 60, 64, 67,
69, 73, 74, 85), so the camera may declare more than 1 700 - the v2/v3 PC bench saw 476 declared
for a 65-id page and 2 445 for another big page, both with **two** continuation pieces already
observed. If the real declaration is larger, the crossed band is recomputed as 8.4-14.1 % of it
(2 445 -> 205..345), and the 11 stays out of reach either way. The decoder mirror for Q6 is also
unhelpful by construction: at 59 body octets it prints `COUPE: identifiant du champ 1 coupe a 59`,
and at 96-100 the whole window is still head echo (`relus: 1 2 3 4 6 7 8 11 ... 44 | valeurs:`),
which is exactly the burial being demonstrated. Judge Q6 by its **piece count**, not its decoded
lines.

**Round-trip check, stated as measured.** Of the 8 961 code-200 answers, 7 655 are *comparable* -
every id they re-read has a collected entry in the repeated-field-1 form - and **1 099 of those
recompose byte for byte** from the collected entries once the observed variant of each id is
chosen. Restricted to the ids v9 asks about, only **16 answers are comparable and 9 recompose
exactly**: the PC corpora never asked these particular combinations. So each rung's declared total
is a **sum of real, observed entry bytes**, not an observed whole answer - which is precisely why
v9 has to measure it on the watch leg rather than read it off the corpus. What is solid is the
input side: entry bytes, entry lengths, block ordering. What is predicted is the total and the
crossed band.

`tools/v9_expect.py` also **replays the probe's own decoder** on the recomposed body at the band's
two edges, so the console lines the bench should print are written down before the bench
(`out/bench/consigne-banc-v9-20261105.md` quotes them, e.g. Q3 full: `BAT alim=0 niveau=100
type=0,STO carte=0 libre=249823232+952*2^28 total=251658240+952*2^28 lieu=0`). Both the ordering
count and the round-trip count are printed by that script, so the numbers above are reproducible
with one command.

**Three defects found by review after the first v9 build** (the first build was never benched;
recording these because each one silently produced a wrong reading rather than an error):

- `optionsDecode()` read the **tag** of the repeated field 1 but never its **value** varint, so
  the next octet was parsed as a tag and every answer ended in `champ 1 genre 3 hors corpus`
  with the `Options` block never entered - the measurement itself was unreachable;
- in the `Options` block the varint-form entry printed its **tag** as its value, although that
  form is the corpus majority (10 982 vs 3 021);
- `varOf()` assembled varints with `(b & 0x7f) << sh` on Monkey C's **signed 32-bit** shift
  operators: a 6-octet varint (38 bits, the storage sizes) overflows at the 5th group. Both
  halves are now built from **four 7-bit groups each** (maximum shift 21, never the sign bit):
  `out[0]` = low 28 bits, `out[1]` = the rest, value = `out[0] + out[1] * 2^28` - a
  multiplication - and `out[1] = -1` past 8 groups prints `TROP GRAND` rather than a wrong
  number. Console storage figures therefore read like `libre=249823232+952*2^28`.

The first two are fixed in `v9a02`; the third finding is a **rung-number collision**, fixed in
`v9a03`:

- the v9 question rungs had been numbered `MK_Q3OPT..MK_Q6FIX = 49..52`, which are **already**
  `MK_B15A`, `MK_B15B`, `MK_B166A`, `MK_B166B`. `buildFrame()` compares `gix` against these
  values in source order, so a re-used number sends the wrong frame silently - a rung labelled
  "ask 15 body 08 01" would have received an options question. The v9 ladder never re-sent those
  bodies, so `v9a02` would have measured correctly, but the trap was in the file. The question
  rungs move to **55..58** (`MK_ASK71 = 54` was the previous maximum; `MK_GFL = 20` with
  `GFLN = 11` owns 20..30 and must stay clear) and `check_gix()` in the generator now refuses any
  duplicated `MK_` value and any value inside the ramp range, so the collision cannot come back.

`v9a01` and `v9a02` artifacts were **deleted** rather than kept: exactly one probe can be benched,
and a run is identified by the banner plus the `[build] v9a03` line, never by file size.

**v9a03 artifact** (`mk_v9-20261105.py` splices 11 + 3 small edits on the v8a01 snapshot, tag and
`[build]` line both `v9a03` so the console identifies the fixed decoder and the renumbered rungs):

```
source  Framing Probe/source/FramingProbe.mc        135431 o  9e3c6ba21d1e8249
        out/bench/sources/FramingProbe-v9a03.mc     (same sha)
prg     out/bench/FramingProbe-v9a03-20261105.prg   165612 o  2a98467d70a18165
        out/bench/FramingProbe-v9a03-20261105.prg.debug.xml  347060 o  01115afc650defe9
build   cd "Framing Probe" && $SDK/bin/monkeyc -f monkey.jungle -d epix2pro51mm \
          -y ~/.local/share/insta360-ciq/rsa.der -o ../out/bench/FramingProbe-v9a03-20261105.prg -l 1 -w
```

Warning profile is identical to the v8a01 baseline (28 warnings: 21 container-access, 2
container-assignment, 2 unreachable, 3 uninitialized super classes, 1 launcher-icon size); no
manifest change is needed (same permissions, product and entry class). The ladder is 19 rungs:
the seven question rungs Q0-Q6 (10 s each, no operator action) then the unchanged v8 action
matrix E0-E11; `Lang.Array` has no prepend, so `addAll` puts the action matrix behind the
questions, which also means an aborted run still judges every question.

**Falsifiers**: if Q2-full, Q3-full and Q5 answer with one 20-octet notification and zero
pieces, the declared-size rule does not hold for code 8 and there is no options route to battery
level or free bytes on the watch leg; if Q6 (714 / 1 700 declared as a lower bound, continuation
already measured twice on the PC leg) gets no pieces at all, the leg itself is at fault and
nothing about options may be concluded. Battery level and free bytes stay out of the barrel until
seen whole on the watch leg.

**Files added or used for this section**: `tools/v9_expect.py`,
`out/bench/sources/mk_v9-20261105.py` (which now also runs `check_gix()` on the produced source),
`out/bench/sources/FramingProbe-v9a03.mc`,
`out/bench/FramingProbe-v9a03-20261105.prg` (+ `.prg.debug.xml`),
`out/bench/consigne-banc-v9-20261105.md`. The v8 console dump is still not on disk; the v9 sheet
asks for the console to be saved as `out/bench/FramingProbe-v9-sim-dongle-20261105.log`.

## 15.26 v9a03 measured twice on the watch leg: the padding route fires, and one 20-octet chunk cannot be attributed

Same X5 (fw v1.13.21, serial `IAHEA2503S6GEW`), same watch (`epix2pro51mm` build target),
simulator + nRF52840 dongle, camera idle for the whole run (no capture gesture was driven).
**Two runs, not one**, because §15.24's rule is that no bench single run settles anything:

| run | file | octets | sha256 |
| --- | --- | --- | --- |
| a | `out/bench/FramingProbe-v9-sim-dongle-20261105.log` | 12 173 | `f9567591…` |
| b | `out/bench/FramingProbe-v9-sim-dongle-20261105b.log` | 12 173 | `d1060d52…` |

Byte-for-byte the two consoles differ in **24 lines, and all 24 are `+Nms` arrival offsets**
(`+3000ms` vs `+2800ms`, the `[alarme]` at `~9300 ms` vs `~9400 ms`). Every verdict, every counter,
every declared size and every decoded byte is identical. The bench channel is reproducible at the
protocol level, which is what makes the anomaly below worth reading as a fact and not as noise.

Bilan, identical in both runs:

```
[bilan] notification la plus grande recue = 20 octets, donc MTU negocie >= 23
[bilan] notifications=14 octets=177 tetes=6 battements=7 orphelines=0
[bilan] tailles: 7x7 16x3 20x4
[bilan] ecritures en suspens au changement d'etage=0 relances de lien=0 ecritures OK=7 accuses 0x2017=0
```

`tailles: 7x7 16x3 20x4` is the whole traffic of the run: seven 7-octet keepalives, three
16-octet reception ACKs, four 20-octet notifications, **14 notifications, 177 octets, 6 heads,
zero orphan chunks**. That is the 20-octet wall, measured, in one line.

**§15.25's recomputed predictions held, rung for rung.** `ask 8 [11,20]` declared **51** (predicted
51), `ask 8 [11,15,16,20,30,48]` declared **148** (predicted 148), `ask 8 [11,20,39]` declared
**398** (predicted 398 full / 52 short). 40 octets crossed out of 398 announced is **10.05 %**,
inside the 8.4-14.1 % band measured on the PC leg in §15.24 - the first time that band is confirmed
on the watch leg. Below the threshold nothing crossed, exactly as predicted:

```
[V] Q0 ask 8 [11,20] … f1 rep=0xc8 w=51  r=20 manque=31  mor=0 clos=frontiere: battement    corpsvus=4
[V]   relus: 11 20 | valeurs:
[V] Q1 ask 8 [11,15,16,20,30,48] … f1 rep=0xc8 w=148 r=20 manque=128 mor=0 clos=frontiere: battement  corpsvus=4
[V]   relus: 11 15 | valeurs:
[V] Q2 ask 8 [11,20,39] … f1 rep=0xc8 w=398 r=40 manque=358 mor=1 clos=fin de fenetre       corpsvus=24
[V]   relus: 11 20 | valeurs: | COUPE:  champ 6 genre 1 hors corpus
[V] Q3 ask 8 [11,20,39,81] … AUCUNE TETE recue (orphelines=0 battements=0)
[V] Q4 ask 8 [11,20,22,36,37,39] … AUCUNE TETE recue (orphelines=0 battements=0)
[arret] camera muette: l'echelle s'arrete a l'etage 4 (…)
```

So: 51 announced -> 20 received, 148 -> 20, **398 -> 40 with the truncation flag set**. The
padding route moves bytes across the wall on the watch leg. And the two rungs after the 398-announced
answer received **nothing at all**, keepalives included (`bat=0`): the same 398 answer stopped the
camera's push side in both runs, which is why the v10 ladder runs ascending.

**The answer layout is now recomputed, not modelled.** A code-200 answer to `ask 8` with ten ids,
seen **25 times and byte-identical all 25 times** in the corpora (body 484, declared 500), fixes the
framing:

```
08 <id> for each requested id, in REQUEST order   |   12 <len of Options block>   |   entries in ASCENDING id order
```

which decomposes the two bench answers exactly: `[11,20,39]` = 16 + 6 + 3 + 373 = **398**, with
option 11 at body 9-17, option 20 at 17-38, option 39 from 38; `[11,15,39]` = 16 + 6 + 3 + 368 =
**393**, with option 11 at 9-17, option 15 (the serial, 16 octets in all 208 corpus sightings) at
17-33, option 39 from 33. Entry framing is protobuf-varint-aware, so ids >= 20 cost **two** tag
octets (`ba 02` = field 39 wt2, `a2 01` = field 20 wt2), and options 6 and 39 both carry the same
**340-octet text block**: entry sizes 343 (`32 d4 02` + 340) and 344 (`ba 02 d4 02` + 340).

**The unattributed chunk.** The 398 window received, besides the frame head, one **headless
20-octet notification**, and `brut=` keeps its bytes after the 4 head bytes:

```
brut=08 0b 08 14 | 31 30 5f 34 32 37 33 2e 34 30 30 5f 38 30 39 34 2e 31 35 30
      08 0b 08 14   1  0  _  4  2  7  3  .  4  0  0  _  8  0  9  4  .  1  5  0
```

Headless continuations are not exotic on this leg - §15.6 recorded code 13 (`want=4008`) as head
20 + **18 headless 20-octet continuations**, filenames visible in the hex - so the mechanism
exists. What does not fit is *attribution*: the recomputed body says body offset 4 is the option-39
echo `08 27` and body 38 is `ba 02 d4 02`, so at 40 octets crossed the next bytes should be option
11's entry, not ASCII. And the text itself is *known content*: the corpus's option 6 / 39 blob is
`2_2.000000_4287.100_4288.230_2681.610_2702.100_-1.481_-0.264_87.870_2648.289_8094.150_2703…` - the
same family, and `8094.150` appears in it verbatim. So the chunk is protocol content from the
340-octet-blob family, arriving headless, but it cannot be this answer's continuation at the offset
where it appears. Two loose ends keep this open rather than resolved:

- the probe's own two paths disagree about that notification: the frame path counts it as 20
  octets (`r=40`) and keeps 24 of those 40 in `brut=`, while the push path prints
  `poussee 0 0x0 x1 premiere +700ms corps=2e 31 35 30` - **4** octets, `.150`, because the push path
  assumed a 16-octet envelope and read bytes 16-19 of a notification that has none. A headless
  notification has no declared size to anchor it, so neither count is trustworthy;
- the decoder's `COUPE: champ 6 genre 1 hors corpus` is it giving up on those bytes, not evidence
  about them.

**Two probe defects, both confirmed from source and log, both fixed in v10.** (1) Resume never
survived the wedge: the wedge path writes `RESUME_KEY, rungIx + 1` and then calls `bilan()`, which
unconditionally does `Application.Storage.setValue(RESUME_KEY, 0)` (line ~3041). Both logs print
`[arret] … reprendra a l'etage 5` and then restart at Q0. (2) `rungIx + 1` pointed past the silent
rung, so even a working resume would have skipped the next measurement. v10's `bilan(keepPoint)`
keeps the point when the stop came from a silent camera, and the point is `rungIx`, the silent rung.

**Two console-label traps** (documentation only, no code change): `[V] E<n> …` is built as
`"E" + winRung` (lines 1283 / 1470 / 1478), so it is the **window index**, not an action rung -
the `E0`…`E3` labels in these logs are Q0…Q3. And `[resume N]` (line 3222, `bilanPage()`) is the
**index of the paged verdict dump**, not a resume point; the real resume point only ever appears in
the `[arret]` / `[reprise]` lines.

**Probe v10a01 built to settle the chunk question by octets, not interpretation.** Generator
`out/bench/sources/mk_v10-20261105.py` (sha `340444b6…`, proven deterministic: two runs from
`out/bench/sources/FramingProbe-v9a03.mc` give identical bytes), source
`Framing Probe/source/FramingProbe.mc` and its frozen copy `out/bench/sources/FramingProbe-v10a01.mc`
sha `d3853f7f…`, 144 618 octets, 3 547 lines, pure ASCII (no octet outside printable/tab/LF, no
CRLF). Artifact `out/bench/FramingProbe-v10a01-20261105.prg` 167 004 octets sha `1cb1ed8e…`, debug
`d0999425…`, SDK 9.3.0, target `epix2pro51mm`; warning profile identical to the v9 baseline except
one more container-access warning (22 vs 21) from the new `ladder[winRung]` access. `RUN_TAG =
"v10a01"` deliberately invalidates any v9a03 resume point. What changed:

1. `[nfq]` raw trace, gated to question windows only (`ladder[winRung][:kind] == K_TX`): one line per
   notification with `code` and `declared` (`?` when no head is seen), received size, and the first
   `NFTRACE_HEX = 32` octets in hex; `NFTRACE = 60` lines per window so Q6's 200+ notifications do
   not bury the console. Listen windows are left untouched.
2. The ladder re-ordered by **ascending declared announcement**: Q0 (51), Q1 (148), Q5 (249/253),
   **B7** `ask 8 [11,15,39]` (51/393, new, gix `MK_B7BAT = 59`, body `0a 03 0b 0f 27`), **B8**
   `[11,20,39]` (52/398, the old Q2 re-run with the trace, reusing gix `MK_Q3OPT`), Q4 (215/598),
   Q6 (714/1 700), Q3 (58/744), then E0…E11 - **20 rungs**. B7 pads with option 15 (16-octet entry,
   id > 20 so it cannot bury option 11) instead of option 39 (344 octets): at 33-55 crossed it
   should give the battery **whole**, which is the objective, while the smaller announcement is less
   likely to be the one that wedges the camera.
3. The resume fixes above.

A third label trap, found in the probe itself while building this version: `feed()` already
prints `[nf] #N len=20 +700ms …` per notification (line 1115), **but suppresses it whenever the
rung uses a decode table (`qAgg == 1`)** - and every question rung does. That is why no v9 log
shows per-notification hex inside a question window. The v10 trace is therefore labelled
`[nfq]`, printed before that early return, so the two labels cannot be confused.

Retired artifacts were moved out of `Framing Probe/` to `out/bench/retire/`
(`FramingProbe-v9a03-ide-20261105.prg` `b0196840…`, `FramingProbe-v5a07-20261104.prg` `1d930897…`)
so that exactly one probe is installable; **the manifest is unchanged** - same application.

**Falsifiers for the v10 bench**: if B7-full prints `BAT … niveau=…` with no `valeur coupee` **and**
the `[nfq]` lines show those crossed bytes carry their own head, that is a decoding coincidence and
the padding route has still not moved battery level; if Q6's `corpsvus` stays near 20 while
`declare=1 700`, the 8-14 % rule does not apply to this leg and battery / free bytes stay out of
reach through options; if the head notification's 32 octets do not start
`08 0b 08 14 08 27 12 a5 02`, the answer-framing model above is wrong and that is the finding; if a
relaunch after `[arret]` restarts at Q0, the resume point is still not surviving.

**Files added or used for this section**: `out/bench/FramingProbe-v9-sim-dongle-20261105.log` and
`…-20261105b.log`, `out/bench/sources/mk_v10-20261105.py`,
`out/bench/sources/FramingProbe-v10a01.mc`, `out/bench/FramingProbe-v10a01-20261105.prg` (+
`.prg.debug.xml`), `out/bench/consigne-banc-v10-20261105.md`, `out/bench/retire/`,
`tools/v9_expect.py` (B7/B8 rows and their decoder mirrors), and the corpora under
`out/rea/artefacts`. The v10 log target is `out/bench/FramingProbe-v10-sim-dongle-20261105.log`;
the v8 console dump is still not on disk.

### 15.27 v10a01 measured on the bench (2026-11-05): answers are cut at 4 body octets, and the
stray fragment is the option-39 text - so `ask 8` can never carry a value to this watch

Log: `out/bench/FramingProbe-v10-sim-dongle-20261105.log`, 205 lines / 19 440 octets, sha256
`edac2e102ae231ab5e46743bd26eae4aa046610b8ae81382acce2a9ad391c2f8`, produced by
`out/bench/FramingProbe-v10a01-20261105.prg` (`1cb1ed8e…`), header `=== FRAMING PROBE v10 … ===`,
`[build] v10a01`, profile `0000BE80-0000-1000-8000-00805F9B34FB`. One session: the 41
`[resume N]` lines are the paged verdict dump (label trap 2 of §15.26), not a second run, so
**the repaired resume point was not re-exercised** - only its bookkeeping is visible
(`[arret] … l'echelle s'arrete a l'etage 6` / `elle reprendra a l'etage 6`, and rung 6 is Q6,
which is what the fix is supposed to name).
Global counters: `notifications=25 octets=317 tetes=10 battements=12 orphelines=0`,
`tailles: 7x12 16x5 20x7 13x1`, `ecritures OK=11 accuses 0x2017=0`, biggest notification 20
octets (MTU >= 23). Per rung (`w` = announced frame, `r` = octets credited to the answer):

| etage | question | `w` | `r` | `manque` | head body octets seen | `relus:` | extra |
|---|---|---|---|---|---|---|---|
| E0 | Q0 `ask 8 [11,20]` | 51 | 20 | 31 | 4 | 11 20 | - |
| E1 | Q1 `ask 8 [11,15,16,20,30,48]` | 148 | 20 | 128 | 4 | 11 15 | - |
| E2 | Q5 `ask 8 [11,20,22,36,48,158]` | 253 | 33 | 220 | 4 | 11 20 | one headless 13-octet chunk |
| E3 | B7 `ask 8 [11,15,39]` | 393 | 40 | 353 | 4 | 11 15 | one headless 20-octet chunk |
| E4 | B8 `ask 8 [11,20,39]` | 398 | 40 | 358 | 4 | 11 20 | one headless 20-octet chunk |
| E5 | Q4 `ask 8 [11,20,22,36,37,39]` | - | 0 | - | 0 | - | silent, alarm at ~9.4 s |
| E6 | Q6 `ask 8 ids 1..89` | - | 0 | - | 0 | - | silent ~19.4 s -> `[arret]` |

**Finding 1 - the head chunk is not 20 body octets, it is 16 + 4.** Every answer notification in
this run is exactly 20 octets: 16-octet envelope plus **4 body octets**, which is exactly two
`08 <id>` echoes (`[nfq] #6 … 33 00 00 00 04 00 00 c8 00 02 1f 00 00 80 00 00 | 08 0b 08 14`).
So the camera chunks its frame at 20 octets of the *whole frame*, and the first piece is
truncated to 4 octets of payload. The §15.24/§15.26 wording ("20 octets de corps par fenetre,
le premier chunk porte 20 octets") is wrong on this point and is corrected here: **only body
offsets 0..3 of an answer are ever readable on this leg**, and `corpsvus` values of 4 / 17 / 24
come from those 4 octets plus the unanchored pieces the pump glued on.

**Finding 2 - the full framing of an `ask 8` answer, taken byte-exact from the corpus.** The PC
capture `out/rea/artefacts/ble-20261014-173343.log` has the request and its whole answer
(PC MTU is large, so nothing is chunked there): TX `ask 8` declared 73, body
`0a 37 0b 0f 10 14 1e 30 4d 5d 01 02 …` (packed field 1, 55 octets of ids); RX `0xc8` declared
742, body 726 octets. That body decomposes exactly:

- `08 <id>` repeated **in request order** - 26 echoes: `11 15 16 20 30 48 77 93 7 8 14 19 22 24
  29 36 39 40 41 43 66 68 84 88 97 103`. Ids asked but unknown to the camera (1, 2, 3, 4, 5, 6 …)
  are **not echoed at all**, so the echo list is not ascending in general - it is request order
  minus the unanswered ids. (The bench heads agree: `[11,20,39]` -> `08 0b 08 14`, truncated to
  the first two ids.)
- `12 <varint 671>` then the Options block: entries in **strictly ascending id order** -
  `7(1) 8(1) 11(8) 14(1) 15(16) 16(48) 19(6) 20(21) 22(115) 24(2) 29(3) 30(11) 36(38) 39(344)
  40(1) 41(1) 43(1) 48(14) 66(1) 68(1) 77(1) 84(1) 88(1) 93(1) 97(1) 103(1)` - and **no trailer**:
  the block ends the body. `tools/v9_expect.py` reproduces this layout and the announced sizes of
  the bench rungs to the octet (Q5: body 237 = 13 head + 3 block header + 221 entries -> 253
  announced, as seen; B8: 6 + 3 + 8 + 21 + 344 = 382 -> 398, as seen; B7: 6 + 3 + 8 + 16 + 344 =
  377 -> 393, as seen).

**Finding 3 - the loose end of §15.26 is closed: the ASCII fragment is inside option 39.** Both
bench fragments (`B8 … 31 30 5f 34 32 37 33 2e 34 30 30 5f 38 30 39 34 2e 31 35 30` =
`10_4273.400_8094.150`, `B7 … 37 33 2e 34 30 30 5f 38 30 39 34 2e 31 35 30 5f 32 37 30 33` =
`73.400_8094.150_2703`) were searched in the whole corpus as raw hex: **246 exact hits**, all in
`0xc8` answer frames, and in each of them the hit lies **inside the option-39 entry** (344 octets,
`ba 02 d4 02` + 340 octets of text): positions 250 and 255 of that entry. Mapping those positions
back through the layouts recomputed in Finding 2 - option 39 starts at body 38 for B8 and body 33
for B7, payload at body 42 / 37 - gives **body offset 292 in both answers** (frame offset 308).
So the piece is protocol content, it is the option-39 text (the same static blob the corpus
carries, which is why it matches 246 times), and the 5-octet shift between B7 and B8 is exactly
the difference between the option-15 entry (16 octets) and the option-20 entry (21 octets) that
precede it. The earlier suspicion that the chunk was a filename or a headless continuation of the
head is dead.

**Finding 4 - that deep piece is not a continuation we can use.** If the camera chunked the
answer at 20-octet frame boundaries and simply lost the middle, the piece after the head would be
frame offsets 20..39 = body 4..23 = `08 27 12 f5 02 5a 06 08 00 10 64 20 00 a2 01 12 08 00 10 80`
(binary, the start of the battery + storage entries). What arrives instead sits at frame offset
308 (B7/B8) and, for Q5, at 240..252 (its 13 octets `80 f0 bb f1 06 18 b3 e6 cc a5 5f 20 00
match the recomposed tail of body 224..236 field by field, with this session's numbers where the
corpus has `80 a0 90 b4 07 …`). No stride, buffer size or last-chunk rule fits all four
observations (v9 Q5 received 1 octet where the frame-240 rule predicts 9). Recorded as
unexplained; what matters operationally is only that **the fragment is not contiguous with the
head and carries no entry boundary**, so frontier reassembly can never rebuild the answer from it.

**Finding 5 - the option route is closed, not merely unpadded.** An answer that carries one
option value costs at least `2` (id echo) + `3` (block tag + varint) + `8` (option 11, the
smallest useful entry) = 13 body octets = a 29-octet frame, while this leg delivers the whole
frame only when it is at most 20 octets (the beat `07 00 00 00 05 00 00`, the reception ACK
`10 00 00 00 04 00 00 17 20 …`, the pushes below). Every `ask 8` answer therefore loses at
least its entry bytes, whatever ids are requested. **The padding programme of §15.25 is a dead
end for getting a value through**: the announcement size only decides whether an unanchored
piece from near the middle of the option-39 text also arrives (253 -> yes, 393 -> yes, 398 ->
yes, 148 -> no). Consequence for the app: **no battery percentage and no free-bytes figure from
options, ever, from this watch** - and `ask 8` stays useful only for reading `relus:` (which ids
the camera claims to have) and for the 598-octet wedge behaviour: E5 `ask 8 [11,20,22,36,37,39]`
drew **zero** notifications and the camera stayed mute through E6 (`[arret]`), as in both v9 runs.
The corpus says the same thing from the other side: of all RX frames whose *whole* frame is at
most 20 octets (the only ones that can cross whole on the watch), the `0xc8` answers are 219 of
16 octets (empty body: id unknown to the camera), 4 804 of 18 octets (`08 <id>` only: id echoed,
no entry) and 3 of 20 octets (`08 24 12 00`: id echoed, entry empty) - **no value byte in any of
them**.

**Finding 6 - the small pushes, which are the actual route.** Re-querying the corpus for RX
frames whose whole body is short gives the frames the camera pushes by itself (APK names from
`tools/apk_extract/message_code_map.txt`):

| code | dec | APK name | corpus body | frame | seen |
|---|---|---|---|---|---|
| `0x2003` | 8195 | `CAMERA_NOTIFICATION_BATTERY_UPDATE` | `0a 06 08 01 10 27 20 00` | 24 | 1, **unsolicited** |
| `0x2006` | 8198 | `CAMERA_NOTIFICATION_STORAGE_UPDATE` | `08 00 10 00` | 20 | 32 |
| `0x2010` | 8208 | `CAMERA_NOTIFICATION_CURRENT_CAPTURE_STATUS` | `08 04 10 02 38 03` / `08 01 10 10 38 02` | 22 | 62 |
| `0x2040` | 8256 | `…_SUPPORT_TAKE_PHOTO_ON_REC_STATUS` | `08 00` / `08 01` | 18 | 4 |
| `0x2053` | 8275 | `CAMERA_NOTIFICATION_CAM_SUBMODE_CHANGE` | `08 00 10 64 18 03` / `08 64 10 0f 18 03` | 22 | 994 |
| `0x2062` | 8290 | `CAMERA_NOTIFICATION_DASH_CAM_INFO` | `08 80 80 80 f8 b8 07 10 80 80 90 f7 b8 07 18 b3 e6 cc a5 5f` | 36 | 4, **unsolicited** |
| `0x203c` | 8252 | - | `08 02` / `08 03` | 17 | 22 |

Two of these are directly what the app wants at connect: **8195 carries a percentage** (nested
field 2 = `27` = 39 in the only corpus sighting, alongside nested field 1 = 1/0 which is the
charger flag already used by the app, and nested field 3 = 0), and **8290 carries byte counts** -
field 1 = 255 802 212 352 = exactly the `952*2^28` figure of §15.13, field 2 = 255 800 377 344 /
255 019 450 368 (moves while recording), field 3 = 25 580 221 235 (= field 1 / 10), field 4 = 0.
Both were pushed with no request in front of them (`prevTX = none`), i.e. the camera offers them
unprompted.

**But the wall applies to them too, and earlier runs already measured how far they get**: the
push verdict table of §13 (confirmed by §15.13/§15.14/§15.20) has `0x2003` declared 24 -> **4 of 8
body octets, no continuation ever**, `0x2010` declared 22 -> 4 of 6 (loses `38 xx`), `0x2062`
declared 38 -> 4 of 22, while `0x2040` (18) and `0x2006` (20) arrive **whole**. That is exactly
what the 16 + 4 rule predicts: a push crosses iff its whole frame is at most 20 octets.

**Finding 7 - therefore the value we want is, on every carrier measured so far, at frame octet
21 or beyond.** Frame octet of the first value byte:

| carrier | frame | value | octet |
|---|---|---|---|
| `ask 8 [11]` option 11 entry | 16 + 2 + 3 + 8 = body 8..15 | battery fields | 26..33 |
| `ask 8 [20]` option 20 entry | body 12..32 | free/used/total varints | 37..57 |
| `0x2003` 8195 push | 24 | nested f2 = percentage | 21..22 |
| `0x2062` 8290 push | 38 | three varints | 21..37 |
| `0x2010` 8208 push | 22 | state + seconds | 17..20 (crosses), f7 at 21 (lost) |
| `0x2040` 8256 push | 18 | record flag | crosses (whole) |
| `0x2006` 8198 push | 20 | card state | crosses (whole, no sizes) |
| `ask 15` answer | 24 | state octet | 19 (crosses); inner `12 xx` at 20..24 (lost) |

Nothing on this link has ever delivered octet 20 or beyond of a *command answer* (S12-S15 of
§15.14: holding the window 12 s, acking, re-asking with a fresh sequence - "only the
file-transfer module ever chunked, command answers never"). So **battery percentage and free
bytes are not reachable by options or by pushes on this link**: every one of those numbers sits
one to seventeen octets past the ceiling. The only shape that could work is a request whose
*answer frame* is at most 20 octets and whose 4 body octets hold the number - which means one
`12 <len>` + a small varint. `ask 166` GET_STORAGE is argument-sensitive and got closest:
`08 01` -> 26, `12 00` -> 36, `0a 01 01` -> `0x190` refusal (§15.14). **That sweep is the one
cheap experiment left for storage**: find a GET_STORAGE body whose answer declares <= 20, whose
body is then `12 <n> <varint...>`, and hope the unit is megabytes or kilobytes rather than bytes
(227 MB fits in one varint octet, 243 968 KB needs three). Until such an answer is measured on
the watch, `BLE Barrel` must not print a battery percentage or a free-space figure.

**Files added or used for this section**: `out/bench/FramingProbe-v10-sim-dongle-20261105.log`,
`out/bench/FramingProbe-v10a01-20261105.prg` (+ `.prg.debug.xml`),
`out/bench/consigne-banc-v10-20261105.md`, `Framing Probe/source/FramingProbe.mc`
(`d3853f7f…`), `tools/v9_expect.py` (layouts, announced sizes, fragment search), the corpora
under `out/rea/artefacts` (notably `ble-20261014-173343.log`, the request/answer pair, and
`ble-20261018-131351.log` / `ble-20261014-184026.log` for the unsolicited 8195 and 8290 pushes),
and `tools/apk_extract/message_code_map.txt` for the push names.

## 16. The barrel asks what the camera is doing, as soon as the link opens

Everything the app would like to show at connect - recording state, mode, battery
percentage, free storage - was measured against the 16 + 4 ceiling in §15.24 and §15.27, and the
verdict was flat: only three shapes cross. This section is what was therefore put into
`BLE Barrel/BLEBarrel.mc`, with the routes and hashes of the build that proves it compiles.

**Finding 1 - what was implemented, and nothing more.** Command 15
(`PHONE_COMMAND_GET_CURRENT_CAPTURE_STATUS`) is sent once per connect, and its answer is read for
the one byte that survives the cut:

- `askCamStatus()` transmits `cmdApply` - which already was command 15 with an empty body, the
  same frame the mode-switch sequence uses - so no new frame had to be invented and no
  sequence-number bookkeeping was touched.
- `scheduleCamStatusAsk()` fires from `onProfileRegister` and waits `STATUS_ASK_MS` = 1500 ms
  before asking: an ask written while the CCCD write is still in flight is answered into a closed
  window (§15.14 measured the answer at 0.6 to 3.9 s after the write). Two retries at
  `STATUS_RETRY_MS` = 6000 ms, `STATUS_RETRY_MAX` = 2, cancelled on the first answer and on
  disconnect.
- `x5ParseCaptureState()` matches the answer's shape first (`buf[16] == 0x0a`,
  `buf[17] == 0x06`, `buf[18] == 0x08`) and then returns `buf[19] & 0xff`, the state octet that
  §15.24 put exactly on the wall: frame octet 19, one octet inside the 20. A bare 18-octet
  code-200 ack, an id echo, or any other answer does not match and gives `null` - the shape test
  is what keeps the 4 804 empty acks of the corpus from being read as "at rest".
- `applyCamState()` runs in the `code == ACK_CODE` branch of `x5ApplyResponse`, before the start
  sequence's own use of the same frame: the code-200 answer to command 15 *is* the ack the start
  sequence waits for, so one frame feeds both and neither consumes the other.
- The state is kept in `x5CamState` (`X5_STATE_AT_REST` 0, `X5_STATE_RECORDING` 1, `null` = never
  answered) and exposed as `peekCamState()` / `peekCamRecording()`. It is deliberately separate
  from `recState`: `recState` is what the watch asked for, `x5CamState` is what the camera says.
  `recState` is moved only when no start or stop is in flight - which is the whole point of the
  read, a camera that was already recording when the watch connected.
- The 0x2006 storage push is now decoded for what it carries: `x5StorageState` / `x5StorageMode`
  from `x5ParseVarintField(buf, 16, bs, 1/2)`, the two flags of a frame that is 20 octets and
  therefore one of the few pushes that cross whole (§13: `0x2006` body 4, ENTIERE).
- `peekStorageFreeBytes()` returns `null` as a hard rule, and `x5BatteryLevel` is left untouched
  by the connect path. §15.27 locating every battery percentage and every byte count at frame
  octet 21 or later makes `unknown` the only honest answer, and the app is expected to show it as
  unknown, not as 0.

**Finding 2 - the receive path stopped gluing pieces that do not belong to the frame.**
`x5RxFeed` now records the size of the notification that opened a frame (`x5RxHeadSize`) and
refuses to append anything beyond it: those octets are counted in `x5RxFrag` / `x5RxFragCount`
(readable as `peekRxFragments()` / `peekRxFragCount()`) and dropped. §15.27 caught the fragments
of a 598-octet answer at some two hundred octets in, and the two bench ASCII strings inside the
option-39 entry are the proof that what arrives after a cut is protocol text, not the missing
middle: glued, that text is a stream of bytes a varint walk will happily read as a battery level
or a free-space figure. A link with a larger budget is unaffected - its first notification is
larger, and a genuine split stays within it.

**Finding 3 - the build route on this Linux machine, recorded because it is not the route of
§15.22.** `monkeyc` cannot build a module: with a `iq:barrel` manifest it fails with "Missing the
iq:application tag", and in SDK 9.x `-m` is the manifest flag, not the module switch. The module
route is `barrelbuild`:

```
SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262
cd /tmp/opencode/barrelbuild     # BLEBarrel.mc + manifest.xml + monkey.jungle, nothing else
$SDK/bin/barrelbuild -w -o BLEBarrel.barrel -f monkey.jungle \
    --override-devices-json ~/.Garmin/ConnectIQ/Devices
```

**BUILD SUCCESSFUL**, 31 warnings, all of them the pre-existing `(:glance)` device-support notes
(one per device that has no glance) - no new warning, no type error. Two notes for whoever builds
next:

- the SDKs installed here (9.1.0, 9.2.0, 9.3.0) do not know the product
  `epix2pro47mmsystem7preview` that `BLE Barrel/manifest.xml` lists, and `barrelbuild` stops with
  "Unrecognized device found in manifest". Nothing was edited in the manifest, as always; for the
  compile check a copy of the manifest in the scratch directory had that single product line
  removed. The manifest itself needs whatever decision the user makes about that preview product -
  this work does not add, remove or change any manifest entry.
- `barrelbuild` folds the compilation in, so the hash of the artifact moves from one build to the
  next even for identical source (as already noted for the Capacites barrel). Quote sizes, not
  hashes, when comparing barrels.

**Files and hashes** (source, artifact and its debug sidecar kept out of the shipped barrel
directory, listings in `out/bench/`):

| file | octets | sha256 |
| --- | --- | --- |
| `BLE Barrel/BLEBarrel.mc` | 78 808 (2 937 lines) | `d4203779…` |
| `out/bench/sources/BLEBarrel-20261105-connectstatus.mc` | same copy | `d4203779…` |
| `out/bench/BLEBarrel-1.0.0-connectstatus-20261105.barrel` | 23 046 | `80b955c4…` |
| `out/bench/BLEBarrel-1.0.0-connectstatus-20261105.barrel.debug.xml` | 24 701 | `cb49e662…` |

The `.barrel` is a compiled proprietary artifact: it sits in `out/bench/` as a bench hand-off and
must not be committed to the public repository, the same rule as for the probe `.prg` files.
The artifact above is 23 046 octets where `BLE Barrel/BLE Barrel-1.0.0.barrel` (31 October) is
13 636 - that difference is the device set of this machine's SDK (180 devices) and the newer
compiler, not a measure of the added code.

**What a bench run has to confirm** - the code compiles, it has not yet been seen on the leg:

| line to look for | expected |
| --- | --- |
| `[cam state] asked command 15, try 1` | about 1.5 s after `profile register` |
| `[cam state] state=0 at rest arrived=20 of 24` | camera idle at connect |
| `[cam state] state=1 recording arrived=20 of 24` | camera already recording at connect |
| `[wire]` no `recording started` push needed | the state comes from the ask, not from a push |
| `[storage] 0x2006 f1=… f2=…` | only when the camera pushes it |
| no battery percentage, no free-space number anywhere | §15.27 |

If a connect draws no `[cam state]` line at all, first check that `profile register` happened
before the ask was written (the 1 500 ms), then read the retry lines: two retries with no answer
means the answer arrives as something other than `0a 06 08 <etat>` and the shape test is doing its
job of saying "unknown".
