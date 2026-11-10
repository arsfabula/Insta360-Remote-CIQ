# Watch app: how it uses the protocol, and how to extend it

Connect IQ widget for the Garmin Descent Mk3i 51 mm (other round Connect IQ ≥ 3.1 devices should
work). It is a fork of ArsFabula's Insta360 Remote (MPL-2.0) with a new UI and X5 support.

## What it does

| Feature | Protocol ([`x5-protocol.md`](x5-protocol.md)) | Code |
|---|---|---|
| Connect, notifications, sync, keep-alive | §2.1 | `BLEBarrel.mc` `enableNotifications`, `onDescriptorWrite`, `keepAlive` |
| One write at a time, chunks never interleaved | §2.4 | `BLEBarrel.mc` `pump`, `onCharacteristicWrite` |
| Mode list and switching | §3.1 | `RemoteDelegate.mc` `modeListX5`, `sendCurrentMode`; `BLEBarrel.setSubModeX5` |
| Follow mode changes made on the camera | §3.2 `0x2053` | `BLEBarrel.onFrameX5` |
| Sync on connect: adopt a running capture, otherwise push the watch's mode | §4.1 | `BLEBarrel.queryCaptureX5`, `syncOnConnect` |
| Video, photo, burst, interval, starlapse | §4 | `RemoteDelegate.onSelect`; `BLEBarrel.shutterX5`, `lapseX5` |
| Every action waits for the camera (state poll every 2 s, 60 s safety net) | §4.1 | `RemoteView.onTick` |
| Charging / on-battery, low-battery alarm, SD card state (no card / full / error) on the ring, with toasts | §6 `GET_STORAGE`, §8 `0x2003` `0x2004` `0x2006` | `BLEBarrel.onFrameX5`, `queryStorageX5`; `RemoteView.drawWidgets` |
| Identify as a Garmin watch; "Allow on camera" / "Camera allowed" toasts | §2.2 | `BLEBarrel.checkAuthX5` |
| Settings page (last entry of the mode list, gear icon): SOUND, Power off camera, Exit app. BACK moves the focus, START (or a second tap on the focused row) runs Power off / Exit | — | `Settings.rows("set")`, `RemoteDelegate.onSelect` |
| SOUND On / Off = camera mute | §6 `MUTE` (14) | `Settings.frames` `:mute` |
| Power off camera, after a confirmation. Power-on is not possible from the watch: it needs the wake beacon (§6), and Connect IQ apps cannot advertise. `tools/wake.swift` sends it from a Mac | §6 `SET_SHUTDOWN` (219) | `PowerOffDelegate`; `BLEBarrel.shutdownX5` |
| Exit: Settings → Exit app, hold UP → Exit app, or BACK in a mode without settings. Long-press BACK belongs to the OS | — | `RemoteDelegate.onSelect`, `onMenu`, `onBack` |

Connect IQ quirks the app works around:

* **20-byte notifications:** parse each notification as one possibly truncated frame
  (`reassembleX5`, lenient `pbFields`).
* **`onStart` also runs for the glance:** start BLE only from `getInitialView`, otherwise the glance
  steals the BLE delegate.
* **A missing GATT service right after connecting is normal:** never unpair or rescan on it
  (the original code did, which left the camera needing a power cycle).

## Not possible on Connect IQ today

Battery **level**, card **space**, remaining time and footage settings come back in replies longer
than 20 bytes (§10), so the watch only sees their first bytes. What does cross is shown instead:
USB / BAT / LOW and the card state. The settings can still be **written** from the watch
(writes are small): see below.

## Ideas, with the protocol already confirmed on a camera

| Feature | How | Effort |
|---|---|---|
| 360° / single-lens toggle | `SET_ACTIVE_SENSOR 08 03 / 08 01` (§3.3); lens state is in `0x2053` field 3, but that field is cut off on Connect IQ (22 B), so track it locally | small |
| Self-timer 0 / 3 / 10 s for photos | `SET_PHOTOGRAPHY_OPTIONS` mode 6, type 26 (§5) | small |
| Interval time picker (e.g. 3 / 5 / 10 / 30 s) | `SET_TIMELAPSE_OPTIONS 0a 03 10 <ms varint> 10 02` (§5.1) | small |
| Resolution / frame-rate picker per mode | type 31 / 40 (§5); allowed values from the catalog (§7), hard-coded per mode | medium |
| EV ± buttons (useful underwater) | type 7, zig-zag sint32; confirm the unit on the camera first | small |
| Highlight marker while recording | `0x3C` needs a body, still unknown | research |
