# Watch app: how it uses the protocol, and how to extend it

Connect IQ watch app for the Garmin Descent Mk3i 51 mm (other round Connect IQ ≥ 3.1 devices should
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
| Charging / on-battery, low-battery alarm, SD card state (no card / full / error) on the top arcs, with toasts. No battery level or card space on the X5 (see below) | §6 `GET_STORAGE`, §8 `0x2003` `0x2004` `0x2006` | `BLEBarrel.onFrameX5`, `queryStorageX5`; `RemoteView.drawWidgets` |
| Identify as a Garmin watch; "Allow on camera" / "Camera allowed" toasts | §2.2 | `BLEBarrel.checkAuthX5` |
| Settings page, pushed above the base: SOUND, Power off camera, and the current mode's option rows. Reached by one action, three entries: a long press on START (the threshold rule is `RemoteDelegate.holdingDue`, 700 ms — the release under it decides, the view's tick at it pages; the SELECT of a key press is only consumed, for the base view delivers it at the key DOWN — the bench of 18 nov. 2026 named this and moved the venues), a long press at the screen (`onHold`), and a tap of the gear icon — drawn at the ring's top right beside the START cue (decision 6 of 17 nov. 2026: the red START point at 2 o'clock is the anchor, the gear sits above it; permanent dim, the tap target published with the icon). In the page UP / DOWN is the menu's own focus, START steps the row once and the row stays focused with its new value; the write crosses at that same moment (the base page's deferred pump cannot ring while the page is on top — see the pitfall below, and `pump.flushSetting` at the select), and a write the mode-window guard holds is retried once more by the page's `onBack` before it pops the page itself. BACK returns to the base (system behaviour, as in every menu). The pseudo-mode "set" this page used to be is gone (decision of 17 nov. 2026, design B): the page names the family to the Settings module per row — "set" for these rows, the current mode's id for the option rows | — | `Settings.rows("set")`, `RemoteDelegate.openSettingsPage`, `buildSettingsMenu`, `SettingsPageDelegate`, `holdingDue`, `onKeyReleased`, `flushSetting`, `RemoteView.drawSettingsCue` |
| SOUND On / Off = camera mute | §6 `MUTE` (14) | `Settings.frames` `:mute` |
| Power off camera, after a No / Yes menu with *No* focused (not `Ui.Confirmation`: on the Mk3i it shows Cancel / Confirm without a visible focus, and a second START press confirms). Power-on is not possible from the watch: it needs the wake beacon (§6), and Connect IQ apps cannot advertise. `tools/wake.swift` sends it from a Mac | §6 `SET_SHUTDOWN` (219) | `confirmPowerOff`, `PowerOffDelegate`; `BLEBarrel.shutdownX5` |
| Per-mode settings: resolution / frame rate, EV (stops at ±4.0), lens, self-timer, photo size, interval, burst, loop length, TimeShift speed, Starlapse duration — two ways in: on the base page of the touch devices (tap focuses a row, a swipe steps it — kept by decision 5 of 17 nov. 2026), and on the pushed settings page everywhere else (START steps the focused row once) | §3.3, §5, §5.1 | `Settings.rows`, `Settings.frames`; `RemoteDelegate.stepFocused`, `stepRow` |
| Highlight / *Track That* while recording (UP / DOWN) | §4 `0x3C` | `RemoteDelegate.onPreviousPage`, `onNextPage` |
| Touch: tap a row = focus it, tap the gear = push the settings page, long press at the screen = the same page, tap elsewhere = START | — | `RemoteDelegate.onSelect`, `onTap`, `gearTapped`, `onHold`, `focusRowAt` |
| GPS overlay (hold-UP menu): older cameras only; hidden and GPS off with an X5 | — | `RemoteDelegate.onMenu`, `Main.gpsSync`, `photoWithGps` |
| Exit: BACK is pure — the base view never claims it, and the app exits by the standard mechanism of the root view, identical on both generations. No `onBack` override stands anywhere in the app (decision of 17 nov. 2026; the exit ladder that preceded this by one commit is in the git history and the code note). Long-press BACK belongs to the OS (the hold-UP menu carries no exit row). No `System.exit()` call stands anywhere in the app (see the quirk below) | — | none — system behaviour |

Connect IQ quirks the app works around:

* **20-byte notifications:** parse each notification as one possibly truncated frame
  (`reassembleX5`, lenient `pbFields`).
* **`onStart` also runs for the glance:** start BLE only from `getInitialView`, otherwise the glance
  steals the BLE delegate.
* **`System.exit()` is a no-op on the widget-loop devices** (every API ≤ 3.4 class of the SDK table,
  plus the two widget-hosted Edges): the call returns, its base view may not be popped, and Garmin's
  own engineers name BACK at the root view as the only clean exit of that generation. The app calls
  it nowhere; leaving stands in the system's own BACK at the root view, never overloaded, on every
  device (decision of 17 nov. 2026, named on the marq sim bench; see the Exit row above).
* **The base view of a widget-loop device takes no UP / DOWN:** the SDK is formal (it "will never
  receive either the up/down button or up/down swipe events"); only views pushed above it escape —
  "Any views pushed on top of the base view... will not have these input restrictions". That is why
  the settings live in a pushed page (`RemoteDelegate.openSettingsPage`) and not on the state
  screen, while the state screen keeps its direct way for the touch devices only (decision of
  17 nov. 2026, after the user's marq sim bench of that day).
* **A pushed view silences the base view's tick:** `View.onHide` is documented to fire "when a new
  View object is pushed on top of the current one", and `RemoteView.onHide` stops the 125 ms timer
  there — the timer is the app's only pump (the due-date debounces of `pumpDue`). Any due date a
  pushed page books on that pump rings at the earliest after a return, and this app will not trust
  the platform to wake a covered widget-loop base: the settings page answers its write AT the
  select (`SettingsPageDelegate.onSelect` → `pump.stepRow` + `pump.flushSetting` at once — the
  `applyMode` precedent of the Mode menu, the pushed menu that has always crossed), and its
  `onBack` gives one last try to a write the mode-window guard held before popping. The bench of
  18 nov. 2026 (evening run, marq + epix sims) named the old shape — "les valeurs sélectionnées
  ne semblent pas être transmises à la caméra" while the touch path on the base screen crossed
  fine. Every setting write now prints its fate: `[set] <key> sent xN` at the transport, `[set]
  <key> held, ...` once when the guard defers it.
* **A missing GATT service right after connecting is normal:** never unpair or rescan on it
  (the original code did, which left the camera needing a power cycle).
* **A tap arrives as `onSelect` first:** `BehaviorDelegate` maps a screen tap to the SELECT
  behaviour and calls `onTap` only when `onSelect` returns false. A START press reaches
  `onKeyPressed(KEY_ENTER)` before `onSelect`, a tap does not, so `onSelect` without that key
  declines and `onTap` focuses the tapped row (a 150 ms fallback runs START if no `onTap` follows).
  And the SELECT of a key press arrives at the key DOWN, a few ms after `onKeyPressed` — never at
  the end of the press — so that callback may be nowhere a press is decided: the press length is
  answered at the key up (`onKeyReleased`, it decides under the `holdingDue` threshold) or by the
  view's tick at the threshold (`pumpDue`, it pages). The bench of 18 nov. 2026 (marq + epix
  sims: "ça démarre directement un enregistrement") named exactly this, when a long press ported
  from the PR shot the shutter at the key down; whether a host delivers the key up is the open
  question above, and the `[in] key up ENTER held=…` line names the hosts that answer it.
* **The native toast (`WatchUi.showToast`) swallows the next button press** (it only dismisses
  itself). The app draws its own toast instead (`RemoteView.drawToast`), which takes no input.

## Not possible on Connect IQ today

Battery **level**, card **space**, remaining time and footage settings come back in replies longer
than 20 bytes (§10), so the watch only sees their first bytes. What does cross is shown instead:
USB / BAT / LOW and the card state. The settings can still be **written** from the watch
(writes are small): see the per-mode settings above.

## Open items

The earlier ideas (lens toggle, self-timer, interval, resolution / frame rate, EV) are built; see
the table above.

| Item | Status |
|---|---|
| Highlight / *Track That* marker | The watch sends `0x3C` with the key-time body of the original app; whether the X5 stores the marker in the file is not verified (an empty body is rejected, see the capture section of the protocol notes) |
