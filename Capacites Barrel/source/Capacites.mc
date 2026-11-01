// GENERATED FILE. Do not edit it. Regenerate it from the single
// source of truth capacites_camera.py with :
//   python gen_capacites_ciq.py --mc "Capacites Barrel/source/Capacites.mc"
//
// Capabilities of the Insta360 cameras, for the menus of the apps.
// This module is data only: it knows no protocol frame, no view, no
// device. The protocol barrel stays pure (architecture rule), and an
// application resolves an entry of this module to a protocol frame, and
// a small switch of its own.
//
// Two axes are mandatory (cahier section 8) : a value only makes sense
// against its MODE and its MODEL. Concretely, a video resolution means
// something inside VIDEO_NORMAL only, elsewhere the field record_
// resolution stays fixed on a dead value.
//
// Provenance of every cell (cahier section 8.3, matrix rea/):
//   BLE         measured over BLE on that camera -> authorises a write
//   OFFICIAL    a page of insta360.com      -> a label and a frame rate,
//                 never a write : an OFFICIAL cell never authorises a
//                 command over BLE
//   SCREEN      read at the screen of the camera -> aligns a label to a
//                 value
//   UNVERIFIED  is not a refusal. The application says so, this table
//                 never hides a mode because a measurement is missing
//                 (EF-26)
//
// The masks generate the menus. They never filter the current state of
// the camera : a value seen on the camera and absent here stays visible
// and reusable unchanged (EF-23, EF-25).

using Toybox.Lang;

module CapacitesBarrel {

// --------------------------------------------------------------------------
// Axis model. Only the models measured over BLE are listed here. For the
// others, in the matrix of rea/, no protocol value is known at all,
// the application proposes nothing: unverified is not a refusal.
const capModels = ["X5"];
const capMeasured = [true];

// --------------------------------------------------------------------------
// Masks of the values that can be offered. Bit v of a mask is set when
// the value v can be offered. The masks GENERATE the menus; they never
// filter the state read on the camera: a value the camera carries and
// which is absent here stays visible and reusable (EF-23, EF-25).

// Video sub-modes, field VIDEO_SUB_MODE (BLE, X5, measured 2026-10-18).
const capMaskVideo = [0x57, 0xc8]b;
// values that can be offered: 0 1 2 4 6 11 14 15. The bit of the sub-mode
// 12 (Starlapse) is CLEAR: the entry is not offered (CdC item 100, a decision
// of the app, not a datum of the camera). The measured datum stays: the
// official table of modes never lists Starlapse as a video mode on the X5,
// where it is a photo mode, and the sub-mode 12 is measured over BLE (BLE).
// The two cells stay apart, never merged into one cell.
const capVideoValues = [0, 1, 2, 4, 6, 11, 14, 15];
const capVideoLabels = [
    "Video", "Bullet Time", "Timelapse",
    "TimeShift", "Loop Recording", "PureVideo",
    "Road Mode", "InstaFrame"
];

// Photo sub-modes, field PHOTO_SUB_MODE (BLE, X5, measured 2026-10-18).
const capMaskPhoto = [0x0d]b;
// values that can be offered: 0 2 3
// Labels verbatim of the table "Supported photo modes by model", line X5
// (OFFICIAL). The screen of the camera names the sub-mode 3 "Rafale" :
// the name of the measurement corpus and the official label are two
// names for one same cell (SCREEN bridge).
const capPhotoValues = [0, 2, 3];
const capPhotoLabels = ["Photo", "Interval", "Burst Photo"];

// Video resolutions, field record_resolution, valid inside VIDEO_NORMAL
// ONLY: measured on the eight other modes, the field stays fixed on a
// dead value (cahier section 8.2). The numbering reaches 348, so the mask
// costs 44 bytes.
const capMaskRes = [
    0x01, 0x1c, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0xe0, 0x00, 0x00, 0x04, 0x10
]b;
// Labels = tier + frame rate of the page "X Series: Photo & Video
// Specifications" (OFFICIAL). 5.7K and 5.7K+ are two tiers, and the
// frame rate is the only thing which distinguishes them: a label of
// one tier alone never tells the two apart.
const capResValues = [
    0, 10, 11, 12, 19, 20, 97, 98, 165, 166, 167, 208,
    250, 251, 252, 317, 318, 319, 338, 348
];
const capResLabels = [
    "4K 30", "5.7K 30", "4K 60",
    "4K 50", "5.7K 25", "5.7K 24",
    "4K 24", "4K 25", "8K 24",
    "8K 25", "8K 30", "4K 48",
    "4K 100", "5.7K 50", "5.7K 60",
    "5.7K+ 30", "5.7K+ 25", "5.7K+ 24",
    "5.7K 48", "4K 120"
];
// HDR, PhotographyOptionType 63. The protocol accepts the write
// everywhere, the screen of the camera applies it in 4K and 5.7K only:
// in 8K and 5.7K+ the camera stores the value without effect: a
// phantom write, invisible to a readback (cahier section 10.3).
const capHdrFlags = [
    true, true, true, true, true, true, true, true, false, false, false, true,
    true, true, true, false, false, false, true, true
];
// Adaptive Tone, PhotographyOptionType 86. Same rule: the write is
// accepted everywhere, the camera applies it in 8K only.
const capAdaptiveFlags = [
    false, false, false, false, false, false, false, false, true, true, true, false,
    false, false, false, false, false, false, false, false
];

// --------------------------------------------------------------------------
// An Array answers size(), a String answers length(). Every helper of this module
// walks an Array or a ByteArray, so every one of them says size().
// Helpers. A menu reads these instead of the tables above. An
// empty label means no official name for that value, so the menu
// proposes nothing for it (EF-26).

function capBit(mask, v) as Lang.Boolean {
  if (v < 0) { return false; }
  var at = v / 8;
  if (at >= mask.size()) { return false; }
  return (mask[at] & (1 << (v % 8))) != 0;
}

function capIndexOf(values, v) as Lang.Int {
  for (var i = 0; i < values.size(); i += 1) {
    if (values[i] == v) { return i; }
  }
  return -1;
}

function labelVideo(v) as Lang.String {
  var i = capIndexOf(capVideoValues, v);
  if (i < 0) { return ""; }
  return capVideoLabels[i];
}

function labelPhoto(v) as Lang.String {
  var i = capIndexOf(capPhotoValues, v);
  if (i < 0) { return ""; }
  return capPhotoLabels[i];
}

function labelRes(v) as Lang.String {
  var i = capIndexOf(capResValues, v);
  if (i < 0) { return ""; }
  return capResLabels[i];
}

function resIndexOf(v) as Lang.Int {
  return capIndexOf(capResValues, v);
}

// The index is an index of capResValues, so both flags answer about
// one resolution of the VIDEO_NORMAL menu.
function hdrAppliesIndex(i) as Lang.Boolean {
  if (i < 0 || i >= capHdrFlags.size()) { return false; }
  return capHdrFlags[i];
}

function adaptiveAppliesIndex(i) as Lang.Boolean {
  if (i < 0 || i >= capAdaptiveFlags.size()) { return false; }
  return capAdaptiveFlags[i];
}

function modelIndexOfName(name) as Lang.Int {
  for (var i = 0; i < capModels.size(); i += 1) {
    if (capModels[i] == name) { return i; }
  }
  return -1;
}

// False for a model of the matrix never measured over BLE: the
// application proposes no value and says UNVERIFIED. It never says
// "the model has never been verified over BLE".
function modelMeasured(i) as Lang.Boolean {
  if (i < 0 || i >= capMeasured.size()) { return false; }
  return capMeasured[i];
}
}