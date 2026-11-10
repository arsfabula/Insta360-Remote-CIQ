# Tools

Everything needed to repeat or extend the measurements in [`x5-protocol.md`](x5-protocol.md).
Python tools need [bleak](https://github.com/hbldh/bleak) (`pip install bleak`) and Python ≥ 3.10.
Close any other app connected to the camera (watch, phone) first.

## BLE (from a computer)

| Tool | Use |
|---|---|
| `x5_session.py serve SOCK` | **Start this first.** Holds one BLE connection (sync + keep-alive) and reconnects when the camera sleeps or wakes. Other tools send commands through the unix socket `SOCK`. One long-lived session avoids re-pairing prompts, since macOS rotates its BLE address on every new connection. |
| `x5_session.py send SOCK CODE[:BODY] [WAIT]` | Send one message (hex code, hex body), print the reply and notifications as JSON. Example: `send $SOCK 000f:` |
| `x5_photo.py SOCK dump OUT.json` | Read every PhotographyOptions value for each function mode (8 types per request) |
| `x5_photo.py SOCK get MODE T1,T2` / `set MODE TYPE VALUE` | Read or write footage settings, e.g. `set 6 26 3` = Photo self-timer 3 s. Raw varints: zig-zag signed values yourself. |
| `x5_test.py OUT.json --session=SOCK [--captures-only]` | Functional test: sets every sub-mode and checks the camera's confirmation, then runs photo / video / interval / starlapse once (writes a few small files) and restores Video |
| `x5_probe.py OUT.json` | Read-only survey: every GET-style command and every `GET_OPTIONS` type (direct connection, no session needed) |
| `x5_report.py OUT.json [insta360_messages.proto]` | Turns a survey into markdown tables; device-specific calibration values are redacted |
| `x5_gatt.py dump` / `query CODE:BODY …` | GATT table dump; quick one-off queries |
| `wake.swift` | Power the camera **on** from a Mac: advertises the wake beacon (x5-protocol.md §6) for N seconds. `swiftc tools/wake.swift -o wake && ./wake <last 6 chars of the serial> 30`. Needs *Bluetooth Wake-up* on in the camera; the camera starts in about 12 s. The serial suffix is the camera's wake key, so keep it out of public files. |

Safety rules built into the tools: no delete / format / shutdown / OTA / calibration commands; no
requests for secrets (Wi-Fi credentials, authorization id, licences, Find My tokens); small request
frames only (see protocol §2.4).

```sh
python3 -m venv .venv && .venv/bin/pip install bleak
.venv/bin/python tools/x5_session.py serve /tmp/x5.sock &          # once
.venv/bin/python tools/x5_session.py send /tmp/x5.sock 0008:080b    # battery (full reply)
.venv/bin/python tools/x5_photo.py /tmp/x5.sock get 7 31,41         # Video resolution, remaining time
```

## Wi-Fi traffic (phone app)

1. Capture 802.11 on the camera's channel (macOS: Wireless Diagnostics → Window → Sniffer).
2. Decrypt with Wireshark's `wpa-pwd` key `<camera Wi-Fi password>:<camera SSID>` and export TCP
   port 6666 payloads to TSV (`tshark -T fields -e frame.time_relative -e ip.src -e tcp.payload`).
3. `insta_frames.py <tsv> <phone-ip>` reassembles frames and prints one line per message.

Do not publish raw captures: they contain the Wi-Fi password exchange, GPS positions and media.

## Bluetooth snoop (Android)

`btsnoop_att.py <btsnoop_hci.log>` prints ATT writes and notifications that look like X5 frames.

## Watch (Connect IQ)

| Tool | Use |
|---|---|
| `watch-wait.sh [timeout]` | Wait until a Garmin watch is in MTP mode (`091e:507f`). After plug-in it spends 20–60 s as `091e:0003` first. |
| `mtp-put.c` | Copy a file to an MTP folder by numeric parent id (`mtp-put FILE NAME PARENT_ID`); look up ids with `mtp-folders` |
| `preview.sh` | Render UI states in the Connect IQ simulator and screenshot them |

The app's debug log is `GARMIN/Apps/LOGS/INSTAREM.TXT`. It must exist before the app starts, and it
rotates to `INSTAREM.BAK` at about 5 KB.
