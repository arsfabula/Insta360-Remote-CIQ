# Protocol extraction from `Insta360_v2.34.5_526204.apk`

Source APK: `Insta360_v2.34.5_526204.apk` (package `com.arashivision.insta360akiko`,
version 2.34.5, versionCode 526204, minSdk 28, targetSdk 35).

Companion raw extractions live in `tools/apk_extract/`:
`phone_commands.txt`, `camera_notifs.txt`, `factory_cmds.txt`,
`messages.txt`, `uuids.txt`, `enums-apk-2026.txt`.

## 1. Methodology and limits

The APK is protected by the **Ashield** packer: `AndroidManifest.xml` declares
`android:name="com.ashield.Stub"`, `classes.dex` is a 138.7 MB stub of only 4
classes, and the real bytecode is decrypted at runtime into an anonymous `rwxp`
mapping. Consequences:

- Static decompilation (`jadx` on `classes.dex`) yields only `com.ashield.Stub`.
- Method bodies are encrypted; numeric protobuf enum values, field tags and
  frame-building logic cannot be recovered statically from the APK.
- What *is* recoverable without decryption: the DEX **string pool** (class names,
  message names, field names, enum constant names, UUIDs), the **assets**
  (`assets/capture/proto.json` enum mappings, React Native bundle, configs) and
  the **native libraries** (protobuf descriptors embedded in `libarvbmg.so`).

Runtime instrumentation (Frida/`wrap.sh`, see `rea/07-instrumentation-runtime.md`)
is required to obtain the actual numeric command IDs and field tags for the new
commands. The numbers below for the *old* commands are taken from the public
`insta360-ble-api` descriptor (`insta360-ref/.../pb2/message_code_pb2.py`) and
are assumed stable; the 172 commands new to 2.34.5 have no verified numbers yet.

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
0..1    2     total frame length, uint16 little-endian
2..3    2     0x0000
4       1     frame type: 0x04 = command, 0x05 = keep-alive
5..6    2     0x0000
7       1     command id (MessageCode)
8..9    2     0x0000
10..11  2     sequence number, uint16 little-endian (0xFF default)
12..13  2     0x8000
14..15  2     0x0000
16..    n     protobuf payload
```

- Camera → app codes: `0x06` saving, `0x10` record started/ended, `0x0a` photo,
  `0xc8` OK, `0xf4` busy.
- Frames longer than 20 bytes are split into 20-byte writes.
- X5 notification constants: `0x2053` sub-mode, `0x2010` capture status,
  `0x2040` record state, `0x2003/0x2004` battery, `0x2006/0x2007` storage.
- X6 uses the UCD2 envelope (`tools/insta360_ucd2.py`).

## 4. Command catalog (MessageCode)

Extracted **names** only (249 `PHONE_COMMAND_*`, 152 `CAMERA_NOTIFICATION_*`,
78 `FACTORY_COMMAND_*`). Numeric IDs for the 172 commands new to 2.34.5 are not
recoverable statically (encrypted). See `tools/apk_extract/`.

Representative core commands (numbers from the public descriptor, stable since
the ONE RS / X4 era):

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

New in 2.34.5 (names only, numbers TBD via runtime): AI assistant/voice,
Airetouch, cloud storage, playback, tracking/PTZ, quick reader, find-my,
multi-host, webcam, translate, robot mode, interval-rec feedback, etc.
Full list: `tools/apk_extract/phone_commands.txt`.

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

## 6. Enumerations from `assets/capture/proto.json`

The APK ships a JSON enum table (21 KB) mapping logical names to numeric
values. Extracted mappings include:

- `record_resolution` — 513 entries (`3840_1920_30`→0, `2880_2880_30`→10,
  `3840_1920_20`→21, `3840_3840_30`→167, `7680_4320_30`→154, …).
- `color_mode` — 46 entries (STANDARD…LEICA_3, etc.).
- `exposure_individual`, `photo_size`, FOV, function-mode, …
- Full file: `tools/apk_extract/enums-apk-2026.txt`.

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

## 9. Next steps to close the gaps

1. **Numeric IDs for the 172 new commands**: requires runtime instrumentation
   (Frida gadget via `wrap.sh`, debuggable APK already documented in
   `rea/04-extraction-du-dex.md`). Hook the protobuf enum constructor / the
   frame builder to log `(name, number)`.
2. **Field tags for new messages**: same approach — hook `FileDescriptor` /
   generated message `internalGetFieldAccessorTable`.
3. **X4 / X5 / GO Ultra gating**: branch on model strings in the encrypted
   code; recoverable via string search + Frida tracing.
4. **UCD2 (X6)**: already covered by `tools/insta360_ucd2.py`.

## 10. Conclusion

The APK's control protocol is the same protobuf-over-BLE scheme already
documented in this repo (16-byte envelope + protobuf body on service
`0000be80-...`). Version 2.34.5 extends the `MessageCode` enum from ~77 to
249 commands and the `insta360.messages.*` catalog to 777 types, mostly for
AI/voice, playback, tracking/PTZ, cloud and companion features. The names and
enum mappings are extracted; the numeric IDs need runtime tracing because of
Ashield.