# Capacites Barrel

Generated barrel of the capability model: what each Insta360 model can offer,
per mode, with the English labels printed by the official manuals. Data only.
No protocol, no view, no device.

The barrel is generated. Do not edit `source/Capacites.mc`; regenerate it from
the single source of truth (`outils/capacites_camera.py`, measurements on the
X5 of 2026-10-18):

```
python ../../Documents/Default Project/Insta360 Remote/outils/gen_capacites_ciq.py \
    --mc "Capacites Barrel/source/Capacites.mc"
```

Then rebuild the artefact (same route as the `BLE Barrel`):

```
cd "Capacites Barrel"
<SDK>\bin\barrelbuild.bat -w -o "Capacites Barrel-1.0.0.barrel" -f "monkey.jungle" \
    --override-devices-json "C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Devices"
```

Current artefact: `Capacites Barrel-1.0.0.barrel`, **5 174 bytes**, from a module of
185 lines / 7 525 bytes of source (emitted comments in English, helpers on `size()`).
The md5 is NOT a stable handle of this barrel: `barrelbuild` folds the compilation in,
so recompiling the same source moves it (`410c31345f585ea3dffcd4100622639b`, then
`5c64f4ae79e59c4284816f9ed371ebda`). Quote the size; measure the md5 of the build you hold.

## Why a second barrel

The architecture rule (`ProtocolRemote` knows neither view, mask nor camera
model) forbids putting the masks in the protocol barrel. The menus of the
applications need them, so they come in a barrel of their own which both
applications link. The app resolves an entry of this barrel to a protocol
frame with a small switch of its own; the protocol barrel never sees an
option value.

## Content

| Piece | Cost | What it is |
| --- | --- | --- |
| `capMaskVideo` | 2 B | bit table of the video sub-modes proposable (max value 15) |
| `capMaskPhoto` | 1 B | bit table of the photo sub-modes (max 3) |
| `capMaskRes` | 44 B | bit table of the video resolutions of `VIDEO_NORMAL` (max 348) |
| `capVideoValues` / `capVideoLabels` | 9 entries | values and official labels |
| `capPhotoValues` / `capPhotoLabels` | 3 entries | idem, photo side |
| `capResValues` / `capResLabels` | 20 entries | idem, resolutions |
| `capHdrFlags` / `capAdaptiveFlags` | 20 + 20 | HDR and Adaptive Tone apply per resolution |
| helpers | 10 functions | `capBit`, `capIndexOf`, `label*`, `hdrAppliesIndex`, `adaptiveAppliesIndex`, `modelIndexOfName`, `modelMeasured` |

The three masks total **47 octets** for the X5 universe.

## Provenance, kept visible

Each cell declares its origin, and the origins are not interchangeable:

- **BLE** — measured over BLE on that camera. This is the only origin that
  authorises a write.
- **OFFICIAL** — a page of insta360.com. It gives a label and a cadence, and
  it never authorises a command over BLE.
- **SCREEN** — read at the screen of the camera: it aligns a label to a value.
- **UNVERIFIED** — not a refusal. The application says so; this table never
  hides a mode because a measurement is missing.

Only the X5 has been measured over BLE, so only the X5 has protocol values.
For X6, X4 Air, X4, X3, X2 and ONE X the values are unknown and the
applications propose nothing — see the matrix `rea/11-capacites-cross-model.md`.

## Two rules the helpers carry

The masks **generate** the menus; they never filter the current state of the
camera. A value the camera carries and which is absent from a mask stays
visible and reusable.

A value with an empty label is proposed never: no official name, no offer.
The reason shown to the user is `UNVERIFIED`, never a silent refusal.
