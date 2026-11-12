# Insta360 X5 remote-control protocol (BLE and Wi-Fi)

An interoperability reference for controlling an Insta360 X5 from your own software: a watch, a
script or a bike computer. Everything here was observed or tested against a retail X5 that we own.

* **Camera firmware:** `v1.13.21` (read from the camera itself, option 30)
* **Tested:** November 2026, from a Mac (BLE, ATT MTU 515) and from a Garmin Descent Mk3i through
  Connect IQ (BLE, 20-byte notifications)
* **Status markers used below**
  * ✅ **verified:** sent to the camera and the effect was confirmed (reply, read-back and/or the
    camera screen)
  * ☑️ **answers:** the camera replied 200 OK, but the effect was not checked further
  * ⚠️ **caveat:** works with a limitation, as noted
  * ❌ **rejected:** 400 / no effect

Not affiliated with Insta360. No firmware or app code was decompiled; message names come from the
community protobuf schema [iliakonnov/insta360-nas](https://github.com/iliakonnov/insta360-nas)
(made for older cameras), checked against real X5 traffic. The BLE framing was first documented by
[soul667/insta360-x5-toolkit](https://github.com/soul667/insta360-x5-toolkit).

---

## 1. Transport

| | BLE | Wi-Fi |
|---|---|---|
| Discovery | advertises as `X5 <serial-suffix>`, service `0xBE80` | camera AP `X5 <serial-suffix>.OSC`, the camera is the gateway of its own network |
| Channel | write `0xBE81` (write + read), notify `0xBE82` (enable its CCCD), `0xBE83` read-only (always `11 22 33 44`) | TCP port `6666` |
| Framing | identical: see §2 | identical: see §2 |
| Max frame | the host must split writes into ≤ 20-byte chunks; **keep each request frame small (see §2.4)** | no practical limit |

The BLE GATT table exposes only `0xBE80` (plus GAP/GATT). No separate "watch" service exists.

## 2. Framing

Every frame is `[u32 LE total_length, including these 4 bytes][payload]`. Payload byte 0 is the
packet type:

| Type | Name | Payload |
|---|---|---|
| `0x04` | MESSAGE | 12-byte header + protobuf body |
| `0x05` | KEEPALIVE | `05 00 00` (frame: `07 00 00 00 05 00 00`) |
| `0x06` | SYNC | `06 00 00` + ASCII `syNceNdinS`; the camera echoes it |
| `0x09` | (unknown) | the camera sends `0a 00 00 00 09 00 00 01 02 01` right after SYNC |

MESSAGE header (bytes after the length):

```
04 00 00 | code u16 LE | 02 | seq u24 LE | flags | 00 00 | protobuf body...
```

* Host → camera: `flags = 0x80`, `seq` = your counter. The reply echoes `seq`, and its `code` is the
  status: `0x00C8` 200 OK, `0x0190` 400, `0x01F4` 500, `0x01F5` 501.
* Camera notifications: `code >= 0x2000`, `flags = 0xF4`, `seq` = a per-session constant.

### 2.1 Session

1. Connect, then enable notifications on `0xBE82`.
2. Send SYNC (optional on current firmware, but harmless).
3. Send a KEEPALIVE about every 2 s. The camera sends one per second.

### 2.2 Authorization (optional)

`CHECK_AUTHORIZATION` (0x27) with `{1: id string, 2: initiator_type}` makes the camera show an
**"allow this device?" prompt**. The phone app sends `initiator_type = 2` (Android); `17` is
`WATCH_GARMINOS`. The camera answers `{1: 1}` (UNAUTHORIZED) immediately, then sends notification
`0x2011` AUTHORIZATION_RESULT `{1: 0}` once the user taps Allow.

**Control and reads work without it** (§3–§6 were all tested unauthorized). Sending it from a host
whose BLE address rotates, such as macOS, re-prompts on every connection. Approval does **not**
unlock longer or extra replies.

### 2.3 Field encoding

Bodies are protobuf. Defaults are often omitted (proto3): an empty body or a missing field means 0.
Values are mostly plain varints. Signed fields (`exposure_bias`) are zig-zag `sint32`.

### 2.4 ⚠️ Request-size limit

A single ~230-byte request (GET_PHOTOGRAPHY_OPTIONS for 111 option types at once, sent as 12 BLE
chunks) made the camera drop the link. Afterwards **no command was answered, even after reconnecting,
until the camera was power-cycled.** Frames up to ~40 bytes were always fine. Likewise, a chunk lost
or interleaved inside a multi-chunk frame desyncs the camera's stream parser. Use one writer at a
time and never insert keep-alives between the chunks of one frame.

---

## 3. Modes

### 3.1 Select a mode ✅

`SET_OPTIONS` (0x07) with `{1: [option type], 2: Options{field: value}}`:

| Purpose | Body |
|---|---|
| Video sub-mode *n* | `08 29 12 03 c8 02 <n>` (OptionType 41 VIDEO_SUB_MODE, Options field 41) |
| Photo sub-mode *n* | `08 28 12 03 c0 02 <n>` (OptionType 40 PHOTO_SUB_MODE, Options field 40) |
| *n* = 0 | `08 29 12 00` / `08 28 12 00` |

The camera confirms with notification `0x2053` (see §3.2). All 13 values below were set one by one
and confirmed by that notification and by read-back:

| Kind | Value | Camera catalog name (§7) | Notes |
|---|---:|---|---|
| video | 0 | `VIDEO_NORMAL` | Video |
| video | 1 | `VIDEO_BULLETTIME` | Bullet Time |
| video | 2 | `VIDEO_TIMELAPSE` | Timelapse |
| video | 4 | `VIDEO_TIMESHIFT` | TimeShift |
| video | 6 | `VIDEO_LOOPRECORDING` | Loop Recording |
| video | 11 | `VIDEO_PURE` | PureVideo |
| video | 12 | not in catalog | the camera showed "Starlapse" for it |
| video | 14 | `VIDEO_DASHCAM` | Road / dash-cam mode |
| video | 15 | `VIDEO_GIMBAL` | Gimbal (4K flat, record_resolution 24) |
| photo | 0 | `PHOTO_SINGLE` | Photo |
| photo | 2 | `PHOTO_INTERVAL` | Interval |
| photo | 3 | `PHOTO_BURST` | Burst |
| photo | 7 | `PHOTO_STARLAPSE` | Starlapse |

Value 100 means "none": in photo modes video = 100, and the other way round.

### 3.2 Read / follow the mode ✅

* **Push:** notification `0x2053` CAM_SUBMODE_CHANGE `{1: photo sub-mode, 2: video sub-mode,
  3: active lens}`. It is sent on every change, **including changes made on the camera's own
  screen**. Lens: 3 = both (360°), 1 = front, 2 = rear.
* **Pull:** `GET_OPTIONS` (0x08) `08 28 08 29` → `{1:[40,41], 2:{40: photo, 41: video}}`.

### 3.3 360° / single lens ✅ (front) ⚠️ (rear)

`SET_ACTIVE_SENSOR` (0x41 = 65), body `{1: sensor}`: `08 03` both (360°), `08 01` front only.
Switching to front put the camera into single-lens Video at 4K (confirmed on screen).
`08 02` (rear) is accepted and read back as 2, but nothing visible changed. `GET_ACTIVE_SENSOR`
(0x42) returns `{1: sensor, 2: <lens calibration string>}`.

---

## 4. Capture

| Action | Code | Body | Result |
|---|---|---|---|
| Start recording | `0x04` START_CAPTURE | `08 01` | ✅ 200; capture state → 1 |
| Stop recording | `0x05` STOP_CAPTURE | (empty) | ✅ 200, body `{1:{1:"/DCIM/Camera01/VID_….insv"}}` |
| Single photo | `0x03` TAKE_PICTURE | `20 03 30 03` | ✅ 200, body `{1:{1:"/DCIM/Camera01/IMG_….jpg"}}`; the reply can take >15 s |
| Burst | `0x03` TAKE_PICTURE | `08 03 20 03 30 03` | ✅ shoots; saving takes minutes, and the camera is busy (state 10) meanwhile |
| Interval start / stop | `0x16` / `0x17` START/STOP_TIMELAPSE | `08 02` | ✅ state → 3 while running |
| Starlapse start / stop | `0x16` / `0x17` | `08 05` | ✅ state → 19 while running |
| Highlight while recording | `0x3C` | (empty) | ❌ 400; needs a body (not found yet) |

Notes:

* TAKE_PICTURE with an **empty** body is ignored. The phone app sends `{2: GPS metadata,
  4: raw_capture_type = 3, 6: focus_sensor = 3}`. Fields 4 and 6 are enough.
* START_CAPTURE in a photo mode returns 200 **without** taking a photo. Use TAKE_PICTURE.
* A photo is also visible from notifications: `0x2010` state 4 (SINGLE_SHOOTING) → `0x2006` storage
  update → `0x2010` state 0.

### 4.1 Capture status ✅

`GET_CURRENT_CAPTURE_STATUS` (0x0F), empty body → `{1: {1: state, 2: …, 10: submode}}`. Push
version: notification `0x2010`. States seen: 0 idle, 1 recording, 3 interval shooting, 4 single photo,
10 burst, 19 starlapse (enum `CameraCaptureState`). On connect, this tells you whether, and in which
mode, the camera is already capturing.

---

## 5. Footage settings (per mode) ✅

These are not in `Options`. They live in **PhotographyOptions**, one block per *function mode*.

* **Read** `GET_PHOTOGRAPHY_OPTIONS` (0x0A): `{1: [type…], 2: function_mode}` →
  `{1:[types], 2: PhotographyOptions{type: value}, 3: function_mode}`
* **Write** `SET_PHOTOGRAPHY_OPTIONS` (0x09): `{1: [type], 2: PhotographyOptions{type: value},
  3: function_mode}` → `{1: [successful types]}`
* PhotographyOptions **field numbers equal the PhotographyOptionType values**.
* Request **≤ 8 types at a time** (§2.4).

Function modes used by the X5 (enum `FunctionMode`): 6 Photo, 7 Video, 3 Interval, 5 Burst,
18 Starlapse, 2 Timelapse, 12 TimeShift, 27 PureVideo, 17 Loop, 63 Dash cam, 64 PTZ/Gimbal.

Tested by changing each value and confirming it **on the camera screen**, with the camera first put
into the matching mode, because the screen only shows the current mode's settings:

| Setting | Type # | Example | Confirmed |
|---|---:|---|---|
| Video resolution + frame rate | 31 `record_resolution` (enum `VideoResolution`) | Video: 252 (5.7K 60 fps) → 10 (5.7K 30 fps) | ✅ on screen |
| Photo self-timer (s) | 26 `photography_self_timer` | Photo: 0 → 3 | ✅ on screen |
| Photo size | 40 `photo_resolution` (enum `PhotoSize`) | Photo: 11 (11968×5984, 72 MP) → 12 (5952×2976, 18 MP) | ✅ on screen |
| Exposure compensation | 7 `exposure_bias` (sint32, zig-zag) | Video: raw +3 → screen **+0.3**: value = EV × 10 (camera steps −40, −37, −33 … +40) | ✅ on screen |
| Loop segment length (s) | 29 `record_duration`, mode 17 | 180 → 300 (3 → 5 min); 0 = ∞ | ✅ on screen |
| TimeShift speed | 37 `accelerate_frequency`, mode 12 | 0 (Auto) → 10 (10×) | ✅ on screen |
| Burst | 44 shots + 51 seconds, mode 5 | 15/1 → 10/1: screen "18MP/10P/1s" | ✅ on screen |
| Remaining recording time (s) | 41 `remaining_time` | 19685 s (5 h 28 min) | ☑️ read-only |

**Video resolution values (option 31, function mode 7)**, each set from BLE and read on the
camera screen. The numbers reuse the schema's per-lens names for 8K / 5.7K (`RES_3840_3840P30`
= 8K/30, `RES_2880_2880P60` = 5.7K/60) but the full-frame names for 4K (`RES_3840_1920P120` =
4K/120), so do not derive them from the names:

| Screen | Value | Screen | Value | Screen | Value |
|---|---:|---|---:|---|---:|
| 8K/30 | 167 | 5.7K/60 | 252 | 4K/120 | 348 |
| 8K/25 | 166 | 5.7K/50 | 251 | 4K/100 | 250 |
| 8K/24 | 165 | 5.7K/30 | 10 | 4K/60 | 11 |
| 5.7K+/30 | 317 | 5.7K/25 | 19 | 4K/50 | 12 |
| 5.7K+/25 | 318 | 5.7K/24 | 20 | 4K/48 | 208 |
| 5.7K+/24 | 319 | | | 4K/30 | 0 |
| | | | | 4K/25 | 98 |
| | | | | 4K/24 | 97 |

The same values hold in the other video modes; each was set under the mode's function mode and
read on the screen (webcam pointed at the camera, label checked per value):

| Mode (function mode) | Accepted values |
|---|---|
| PureVideo (27) | 8K 30/25/24, 5.7K 30/25/24, 4K 30/25/24 (167…, 10/19/20, 0/98/97) |
| Loop Rec (17), Road / dash cam (63) | the full Video list above (incl. 4K/48 = 208) |
| Timelapse (2) | **11K/30 = 306** (`RES_5632_5632P30`), 8K/30 = 167, 5.7K/30 = 10 |
| TimeShift (12) | 8K/30 = 167, 5.7K/30 = 10 |
| Bullet Time (**4**, `HIGH_FRAME_RATE`) | **5.7K/120 = 307**, **3K/240 = 262** |
| Gimbal (64) | flat output: 4K/30 = **24** (`RES_3840_2160P30`). GET in function mode 64 answers empty, SET works; writing 360° values there makes the screen show "Unknown" |

5.7K/48 (listed in the catalog) could not be set: 476 (`RES_2880_2880P48`), 316, 367 and 448
were refused (200 but the value read back unchanged); 290 was turned into 10. At 4K/120 the
camera shows Active HDR and AdaptiveTone as "Not supported". Switching HDR / AdaptiveTone on the
camera moved options 61, 86 and 87 (not yet mapped).

**Changes made on the camera's own screen** are not pushed to a BLE client and only reach the
options once the camera's menu is closed; while its menu is open, SETs from BLE are also not
applied.

The camera's own catalog (§7) lists every settable attribute and its allowed values per mode:
EV −4…+4 in ⅓ steps, white balance auto or 2000–10000 K, ISO, shutter, colour/log profile, FOV and
more. Values for the X5 enums may differ from the names in the community schema (built for older
cameras): trust the catalog strings (`3840_2160_60`) over enum names.

Notification `0x2065` (CAMERA_NOTIFICATION_WATCH_RES) pushes PhotographyOptions changes:
`{1: [types], 2: {type: value}, 3: ?}`. For example, after a mode change: `{1:[30,40], 2:{30:0,40:12}}`.

### 5.1 Interval / timelapse timing ✅

`GET_TIMELAPSE_OPTIONS` (0x11) `{1: TimelapseMode}` →
`{1: TimelapseOptions{1: duration_s, 2: lapse_time_ms, 3: output_type, 4: accelerate}}`.
`SET_TIMELAPSE_OPTIONS` (0x12) `{1: TimelapseOptions{…}, 2: TimelapseMode}`.

TimelapseMode 2 = interval shooting (default 3000 ms, duration 0 = unlimited), 1 = timelapse video
(2000 ms), 5 = starlapse. Confirmed on the camera screen:

| Mode | Change | Body |
|---|---|---|
| Interval photo (2) | interval 3 → 5 s ("5 s, ∞, 72 MP") | `0a 03 10 88 27 10 02` |
| Timelapse video (1) | interval 2 → 5 s | `0a 03 10 88 27 10 01` |
| Starlapse (5) | total time ∞ → 10 min (field 1 = 600 s) | `0a 03 08 d8 04 10 05` |

For Starlapse the time on screen is this `duration`, not PhotographyOptions type 29 (setting 29 in
mode 18 is stored but not shown).

---

## 6. Camera status (`GET_OPTIONS` 0x08, one type at a time)

The full table, with reply sizes, is in [`data/x5-ble-survey-fw1.13.21.md`](data/x5-ble-survey-fw1.13.21.md).
The useful ones:

| OptionType | Reply value |
|---|---|
| 11 battery_info | `{1: power_type (1 = USB power), 2: level %, 4: ?}` |
| 20 storage_state | `{1: card_state, 2: free bytes, 3: total bytes, 4: location}` |
| 30 firmware revision | `"v1.13.21"` |
| 40 / 41 | current photo / video sub-mode |
| 48 camera type | `"Insta360 X5"` |
| 93 camera posture | number (5 = upright in our test) |

Not supported on this firmware (200 with an empty value): video resolution, photo size, remaining
pictures/time, self-timer, LED, beep and auto power-off as *Options*. Use PhotographyOptions (§5)
for the per-mode equivalents.

**Sound** ✅: `MUTE` (14) is supported. `GET_OPTIONS 08 0e` → `08 0e 12 02 70 <0|1>` (22 B, so the
watch's 20-byte cut loses the value); `SET_OPTIONS 08 0e 12 02 70 01` mutes (mute shown on the camera),
`… 70 00` restores. `LED_SWITCH` (120, `08 78 12 03 c0 07 <v>`) and `BEEP_SWITCH` (121,
`08 79 12 03 c8 07 <v>`) answer 200 to a SET but the value is not stored (read-back stays empty) and
nothing changes: no LED or beep control over BLE on firmware 1.13.21.

**Indicator light and screen lock are not Options.** Every option type 1–195 was read before and after
switching *Indicator Light* off, and again after toggling the screen lock, both in the camera's
swipe-down menu: only battery level (11) and media time (29) changed. `CHILD_MODE` (151,
`ChildModeInfo{enable, close_sound, close_led, close_button}`) answers 200 to a SET but is not stored;
`GET_INTERVALREC_FEEDBACK_CFG` (206) answers 400. No BLE route to the LED or the lock was found.

**Power.** `SET_STANDBY_MODE` (56, `08 01` low energy / `08 02` wake) answers 400. `SET_SHUTDOWN`
(219, empty body) answers 200 and powers the camera off; it then sends no advertisements at all, so it
sends nothing while off.

**Remote power-on ✅ (wake beacon, like Wake-on-LAN).** With `BT_WAKEUP_SW` (97) = 1 (camera setting
*Bluetooth Wake-up*), the off camera listens for an Apple iBeacon advertisement sent by the phone:

```
4C 00 02 15  09 'O' 'R' 'B' 'I' 'T' 09 FF 0F 00  <S1..S6>  00 00 00 00  E4
iBeacon      UUID bytes 0-9 (constant)          UUID 10-15 major minor tx power
```

`S1..S6` = the last six ASCII characters of the camera serial (= the suffix in its BLE name). Format
from the X3 / ONE RS reverse engineering in pchwalek/insta360_ble_esp32. On the X5 (fw 1.13.21) a
Mac advertising it (CoreBluetooth, `kCBAdvDataAppleBeaconKey`; tool `tools/wake.swift`) woke the
camera 14 s after a `SET_SHUTDOWN`. A Connect IQ watch app cannot advertise (central role only), so
the watch itself cannot wake the camera.

**`GET_STORAGE` (0xA6)** ✅ takes `{1: location}`:

| Body | Reply (code 200) |
|---|---|
| empty | 400 |
| `08 00` (SD card) | 36 B, `{1: {1: card_state, 2: free bytes, 3: total bytes, 4: 0}}` |
| `08 01`, `08 02`, `08 03` | 26 B, `{1: {1: 1 (no card), 2: 0, 3: 0, 4: 1}}`: other storage location |
| `10 xx`, `12 00` | same as `08 00` |
| `12 01` | 400 |

`card_state` is `CardState`: 0 OK, 1 no card, 2 full, 3 invalid format, 4 write-protected,
5 other error. On a 20-byte link the `08 00` reply ends exactly after `card_state`
(`0a 12 08 <state>`), so **the card state can be read at connect time on a watch**; the sizes
(bytes, varints at offset 22 and later) cannot.

`GET_CAMERA_PARAMS_JSON` (0xD8) returns a **zip containing `camera_params.json`** (~126 KB): the
camera's own capability catalog (§7).

---

## 7. Capability catalog (`camera_params.json`)

Two lens layouts: `Sphere06C` (360°, 14 modes) and `Fisheyes06C` (single lens: Photo, Video,
Loop, Selfie/"Me", Super). For each mode it lists `support_attrs`, and for each attribute its allowed
values (`list`), sometimes depending on other attributes (`depend_on`). A summary is in
[`data/x5-mode-catalog-fw1.13.21.md`](data/x5-mode-catalog-fw1.13.21.md).

The `video_sub_mode` / `photo_sub_mode` arrays in it list the available modes per lens layout.

---

## 8. Notifications seen

| Code | Name | Body |
|---|---|---|
| `0x2003` | BATTERY_UPDATE | `{1: {1: power_type 0 battery / 1 USB, 2: level %, 4: 0}}`, 24 B, e.g. `0a 06 08 01 10 31 20 00`; pushed on plug / unplug |
| `0x2004` | BATTERY_LOW | meaning is in the header |
| `0x2006` | CARD_UPDATE | `{1: card state, 2: location}`, 20 B, e.g. `08 00 10 00`; also after a file is written. No sizes |
| `0x2010` | CURRENT_CAPTURE_STATUS | `{1: state, 2: …, 7: …}` |
| `0x2011` | AUTHORIZATION_RESULT | `{1: 0}` = user tapped Allow |
| `0x2017` | CAM_WIFI_START | empty |
| `0x201b` | (LIVEVIEW_BEGIN_ROTATE in schema) | small varint |
| `0x203c` | DARK_EIS_STATUS | `{1: n}` |
| `0x2053` | CAM_SUBMODE_CHANGE | `{1: photo, 2: video, 3: lens}` (§3.2) |
| `0x2065` | WATCH_RES | PhotographyOptions change push (§5) |
| `0x2067` | WIFI_INTERFERENCE_STATUS | `{1: …, 4: channel}` |

`0x2003` is pushed only when the power source changes (seen three times in 3 s for one cable
replug, as the contact bounced), not on level changes during hours on battery.
The BLE advertisement (manufacturer id 0x1a2b, data `00 XX 01`) carries no status: `XX` counts
down about once per second.

---

## 9. Wi-Fi (TCP 6666): what the phone app does

Decrypted from an 802.11 capture of the official Android app (same framing as BLE). In order:

1. `GET_OPTIONS` (camera type, serial, battery, …), `GET_CURRENT_CAPTURE_STATUS`, then a large
   `GET_OPTIONS`
2. `CHECK_AUTHORIZATION` (initiator 2 = Android)
3. Cloud and status housekeeping (`0xA0`, `0xD9`, `0xE1`, `0x26`, `0x0D` GET_FILE_LIST, `0xC9`)
4. **Mode changes:** `SET_OPTIONS` sub-mode (§3.1), followed by `GET_OPTIONS 08 14 08 b0 01 08 b1 01`
   (storage) and `GET_PHOTOGRAPHY_OPTIONS 08 29 08 63 10 <mode>` (remaining time for that mode)
5. **Photo:** `TAKE_PICTURE {2: GPS, 4: 3, 6: 3}`; **video:** `START_CAPTURE 08 01`, then `UPLOAD_GPS`
   (0x35) during recording, then `STOP_CAPTURE {1: GPS, 2: 1}`

Over Wi-Fi the camera also streams preview and thumbnails. Message counts and bodies are in the
capture analysis (`tools/insta_frames.py`). Note that GPS metadata in captures contains your location.

---

## 10. Limits on Garmin Connect IQ

Connect IQ delivers **at most 20 bytes per notification**, has no MTU request, does not expose the
standard Battery Service and does not implement long reads/writes. The X5 does not split replies, so
on a watch you get the 16-byte header plus the first 4 body bytes only.

| Readable on Connect IQ (≤ 20 B) | Cut off (> 20 B) |
|---|---|
| all control acks (200 / 400) | battery (28 B), storage (41 B), current mode via GET_OPTIONS (28 B) |
| `0x2053` mode push: first two fields (photo, video) | remaining time (≥ 23 B), PhotographyOptions replies |
| capture-status reply: first field (state) | photo / video file name in the ack |
| `0x2011`, `0x2010` (first fields), `0x2006` | `0x2065` WATCH_RES (25–30 B) |
| `0x2003` battery push: power_type only (`0a 06 08 01`) | battery level in the same push (bytes 20–21) |
| `0x2004` low battery; `GET_STORAGE 08 00`: card_state | card free / total space |

Checked against the watch logs: 72 notifications, none longer than 20 bytes, and the notification
after a cut frame always starts a new frame header (the camera never continues a cut frame).
This matches independent measurements by the upstream project on an Epix 2 Pro
([Insta360-Remote-CIQ `PROTOCOL_APK.md`](https://github.com/arsfabula/Insta360-Remote-CIQ) §15,
which also disassembled the official Garmin app v4.27.2: it reads battery with the same
`GET_OPTIONS [11]` and `0x2003`, and storage with option 20 after `0x2006`, so on this firmware it
receives the same cut frames). Garmin tracks the 20-byte limit as an open developer-forum bug.

## 11. Reproduce / extend

Tools are in [`../tools/`](../tools/); see [`tools.md`](tools.md). Contributions welcome, especially:
results from other firmware versions, the highlight-marker body, the unit of `exposure_bias`, and how
long values could reach a 20-byte client.
