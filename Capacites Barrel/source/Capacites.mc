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
// Axis model, complete. Every model of the matrix of rea/ is listed, and
// capMeasured says which one was ever relevE over BLE: the X5 only. The
// others are listed because their LABELS are a datum of the official
// documentation, and a label is what an item prints (EF-24). The index of
// this table is the index of every other table of the module.
const capModels = [
    "X5", "X4 Air", "X4",
    "X3", "X2", "ONE X",
    "X6"
];
const capMeasured = [true, false, false, false, false, false, false];
// The envelope the application builds for that model: 1 the older
// envelope as the reference application offers it, 2 the family generated
// by the capability model, 3 the UCD2 envelope. The X2 has no branch of
// its own in the prefix chain of the protocol barrel and belongs to the
// older envelope like the X3 and the ONE, so its level is 1, never 0.
const capMenuLevel = [2, 2, 2, 1, 1, 1, 3];

// --------------------------------------------------------------------------
// Masks of the values that can be offered. Bit v of a mask is set when
// the value v can be offered. The masks GENERATE the menus; they never
// filter the state read on the camera: a value the camera carries and
// which is absent here stays visible and reusable (EF-23, EF-25).

// Video sub-modes, field VIDEO_SUB_MODE (BLE, X5, measured 2026-10-18).
const capMaskVideo = [0x57, 0xd8]b;
// values that can be offered: 0 1 2 4 6 11 12 14 15
// Labels verbatim of the page "X Series: Camera Shooting Modes &
// Features", table "Supported video recording modes by model", line X5
// (OFFICIAL). Starlapse is the exception: the official table of modes
// never lists it as a video mode on the X5, where it is a photo mode,
// yet the sub-mode 12 is measured over BLE (BLE). The two cells stay
// apart, never merged into one cell.
const capVideoValues = [0, 1, 2, 4, 6, 11, 12, 14, 15];
const capVideoLabels = [
    "Video", "Bullet Time", "Timelapse",
    "TimeShift", "Loop Recording", "PureVideo",
    "Starlapse", "Road Mode", "InstaFrame"
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
// Entries of the models never relevE over BLE, by family and by the index
// of capModels. Three tiers cohabit and are never merged (cahier section
// 8.3, and the decision of the axis model of the application):
//   ble         relevE over BLE on THAT camera, a write is authorised.
//                 Only the X5 has such entries, and its menu stays
//                 generated from the masks and the measured frames above,
//                 so the X5 holds nothing here and its rungs stay citable
//                 at that build.
//   reference   the label names a frame of the vocabulary of the barrel of
//                 the official application (the frames of the older
//                 envelope of salvaged/BLEBarrel-1004.mc, -1012.mc and
//                 -1022.mc, whose own annotation is the datum). A frame
//                 exists, so a write is possible; the cell was never
//                 relevE over BLE on the model concerned, so a rung never
//                 reads such a write as BLE-measured (note 52).
//   official    a page of insta360.com documents the mode for that model
//                 and nothing more: a label, no protocol value, no frame,
//                 no write. The entry appears, and the refusal answers at
//                 the write with a print, never by silence.
//
// The id of an entry is o<index of the model><letter of the family><index
// of the entry>, so it is a key of the LABEL and never a number of the
// protocol of the X5: the numbering exists over BLE on the X5 only, and
// the numbering is not a scale across the models (rea/11). The key names
// the frame of the vocabulary of the reference application, and it is an
// empty String when the tier is official.
//
// The X5 (index 0) and the X6 (index 6) hold nothing: the menu of the X6
// keeps its one entry whose UCD2 start and stop were relevE, and the
// documented modes of the X6 stay in the matrix, because the numbering of
// them was never relevE and no frame of the reference vocabulary names a
// frame of the UCD2 envelope.
// Entries of the video family.
const capEntryIdsVideo = [
      [],
      [
          "o1v0", "o1v1", "o1v2", "o1v3", "o1v4", "o1v5",
          "o1v6", "o1v7", "o1v8", "o1v9"
        ],
      [
          "o2v0", "o2v1", "o2v2", "o2v3", "o2v4", "o2v5",
          "o2v6", "o2v7"
        ],
      [
          "o3v0", "o3v1", "o3v2", "o3v3", "o3v4", "o3v5",
          "o3v6"
        ],
      ["o4v0", "o4v1", "o4v2", "o4v3"],
      ["o5v0", "o5v1", "o5v2"],
      []
    ];
const capEntryLabelsVideo = [
      [],
      [
          "Video", "Timelapse", "TimeShift", "FreeFrame Video", "Active HDR Video", "Loop Recording",
          "Road Mode", "Me Mode", "Bullet Time", "InstaFrame"
        ],
      [
          "Video", "Timelapse", "TimeShift", "FreeFrame Video", "Active HDR Video", "Loop Recording",
          "Me Mode", "Bullet Time"
        ],
      [
          "Video", "Timelapse", "TimeShift", "Active HDR Video", "Loop Recording", "Me Mode",
          "Bullet Time"
        ],
      ["Video", "Timelapse", "TimeShift", "Bullet Time"],
      ["Video", "Timelapse", "Bullet Time"],
      []
    ];
const capEntryTiersVideo = [
      [],
      [
          "official", "reference", "official", "official", "official", "official",
          "official", "official", "reference", "official"
        ],
      [
          "official", "reference", "official", "official", "official", "official",
          "official", "reference"
        ],
      [
          "official", "reference", "official", "official", "official", "official",
          "reference"
        ],
      ["official", "reference", "official", "reference"],
      ["official", "reference", "reference"],
      []
    ];
const capEntryKeysVideo = [
      [],
      [
          "", "TimeLapse", "", "", "", "",
          "", "", "BulletTime", ""
        ],
      [
          "", "TimeLapse", "", "", "", "",
          "", "BulletTime"
        ],
      [
          "", "TimeLapse", "", "", "", "",
          "BulletTime"
        ],
      ["", "TimeLapse", "", "BulletTime"],
      ["", "TimeLapse", "BulletTime"],
      []
    ];

// Entries of the photo family.
const capEntryIdsPhoto = [
      [],
      ["o1p0", "o1p1", "o1p2", "o1p3", "o1p4"],
      ["o2p0", "o2p1", "o2p2", "o2p3", "o2p4"],
      ["o3p0", "o3p1", "o3p2", "o3p3", "o3p4"],
      ["o4p0", "o4p1", "o4p2", "o4p3", "o4p4", "o4p5"],
      ["o5p0", "o5p1", "o5p2"],
      []
    ];
const capEntryLabelsPhoto = [
      [],
      ["Photo", "HDR Photo", "Starlapse", "Interval", "Burst Photo"],
      ["Photo", "HDR Photo", "Starlapse", "Interval", "Burst Photo"],
      ["Photo", "HDR Photo", "Starlapse", "Interval", "Burst Photo"],
      ["Photo", "HDR Photo", "Starlapse", "Interval", "Burst Photo", "Night Shot"],
      ["Photo", "HDR Photo", "Interval"],
      []
    ];
const capEntryTiersPhoto = [
      [],
      ["reference", "reference", "official", "reference", "reference"],
      ["reference", "reference", "official", "reference", "reference"],
      ["reference", "reference", "official", "reference", "reference"],
      ["reference", "reference", "official", "reference", "reference", "reference"],
      ["reference", "reference", "reference"],
      []
    ];
const capEntryKeysPhoto = [
      [],
      ["Photo", "PhotoHDR", "", "PhotoInterval", "PhotoBurst"],
      ["Photo", "PhotoHDR", "", "PhotoInterval", "PhotoBurst"],
      ["Photo", "PhotoHDR", "", "PhotoInterval", "PhotoBurst"],
      ["Photo", "PhotoHDR", "", "PhotoInterval", "PhotoBurst", "NightShot"],
      ["Photo", "PhotoHDR", "PhotoInterval"],
      []
    ];

// Entries of the res family.
const capEntryIdsRes = [
      [],
      [
          "o1r0", "o1r1", "o1r2", "o1r3", "o1r4", "o1r5",
          "o1r6", "o1r7", "o1r8", "o1r9", "o1r10", "o1r11",
          "o1r12"
        ],
      [
          "o2r0", "o2r1", "o2r2", "o2r3", "o2r4", "o2r5",
          "o2r6", "o2r7", "o2r8", "o2r9", "o2r10", "o2r11",
          "o2r12", "o2r13", "o2r14", "o2r15", "o2r16"
        ],
      [
          "o3r0", "o3r1", "o3r2", "o3r3", "o3r4", "o3r5",
          "o3r6", "o3r7", "o3r8"
        ],
      ["o4r0", "o4r1", "o4r2", "o4r3", "o4r4", "o4r5"],
      ["o5r0", "o5r1", "o5r2", "o5r3", "o5r4", "o5r5"],
      []
    ];
const capEntryLabelsRes = [
      [],
      [
          "8K 30", "8K 25", "8K 24", "6K 50", "6K 48", "6K 30",
          "6K 25", "6K 24", "4K 50", "4K 48", "4K 30", "4K 25",
          "4K 24"
        ],
      [
          "8K 30", "8K 25", "8K 24", "5.7K+ 30", "5.7K+ 25", "5.7K+ 24",
          "5.7K 60", "5.7K 50", "5.7K 30", "5.7K 25", "5.7K 24", "4K 100",
          "4K 60", "4K 50", "4K 30", "4K 25", "4K 24"
        ],
      [
          "5.7K 30", "5.7K 25", "5.7K 24", "4K 60", "4K 30", "4K 24",
          "4K 25", "4K 50", "3K 100"
        ],
      ["5.7K 30", "5.7K 25", "5.7K 24", "4K 50", "4K 30", "3K 100"],
      ["5.7K 30", "5.7K 24", "5.7K 25", "4K 50", "4K 30", "3K 100"],
      []
    ];
const capEntryTiersRes = [
      [],
      [
          "reference", "official", "official", "official", "official", "official",
          "official", "official", "reference", "official", "reference", "official",
          "official"
        ],
      [
          "reference", "official", "official", "official", "official", "official",
          "official", "official", "reference", "reference", "reference", "official",
          "official", "reference", "reference", "official", "official"
        ],
      [
          "reference", "reference", "reference", "official", "reference", "official",
          "official", "reference", "reference"
        ],
      ["reference", "reference", "reference", "reference", "reference", "reference"],
      ["reference", "reference", "reference", "reference", "reference", "reference"],
      []
    ];
const capEntryKeysRes = [
      [],
      [
          "8k30", "", "", "", "", "",
          "", "", "4k50", "", "4k30", "",
          ""
        ],
      [
          "8k30", "", "", "", "", "",
          "", "", "5k30", "5k25", "5k24", "",
          "", "4k50", "4k30", "", ""
        ],
      [
          "5k30", "5k25", "5k24", "", "4k30", "",
          "", "4k50", "3k100"
        ],
      ["5k30", "5k25", "5k24", "4k50", "4k30", "3k100"],
      ["5k30", "5k24", "5k25", "4k50", "4k30", "3k100"],
      []
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
    // The content test of Lang.String is .equals(): == on a String
    // compares object identity, never content, so this lookup would
    // answer -1 whatever the name (note 9 of the CdC, measured at a
    // barrel boundary at item 14).
    if (capModels[i].equals(name)) { return i; }
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

// The four views of one family are one datum: an entry has one id, one
// label, one tier and one key. One call answers the four views of a
// family, so a menu cannot pair the label of an entry with the tier of
// another (note 8 of the CdC: the tell and the decision answer one
// datum). A family is 0 the video modes, 1 the photo modes, 2 the
// resolutions of the family VIDEO_NORMAL. A model that has no entry of
// a family answers an empty Array, never Null, and an index out of
// range never raises: the menu of a model the matrix does not know
// stays empty, and the walk the application prints says so, because
// the absence of a line is never a verdict.
function rowIds(family, mi) as Lang.Array {
  if (mi < 0) { return []; }
  if (family == 0) {
    if (mi < capEntryIdsVideo.size()) { return capEntryIdsVideo[mi]; }
    return [];
  }
  if (family == 1) {
    if (mi < capEntryIdsPhoto.size()) { return capEntryIdsPhoto[mi]; }
    return [];
  }
  if (family == 2) {
    if (mi < capEntryIdsRes.size()) { return capEntryIdsRes[mi]; }
    return [];
  }
  return [];
}

function rowLabels(family, mi) as Lang.Array {
  if (mi < 0) { return []; }
  if (family == 0) {
    if (mi < capEntryLabelsVideo.size()) { return capEntryLabelsVideo[mi]; }
    return [];
  }
  if (family == 1) {
    if (mi < capEntryLabelsPhoto.size()) { return capEntryLabelsPhoto[mi]; }
    return [];
  }
  if (family == 2) {
    if (mi < capEntryLabelsRes.size()) { return capEntryLabelsRes[mi]; }
    return [];
  }
  return [];
}

function rowTiers(family, mi) as Lang.Array {
  if (mi < 0) { return []; }
  if (family == 0) {
    if (mi < capEntryTiersVideo.size()) { return capEntryTiersVideo[mi]; }
    return [];
  }
  if (family == 1) {
    if (mi < capEntryTiersPhoto.size()) { return capEntryTiersPhoto[mi]; }
    return [];
  }
  if (family == 2) {
    if (mi < capEntryTiersRes.size()) { return capEntryTiersRes[mi]; }
    return [];
  }
  return [];
}

function rowKeys(family, mi) as Lang.Array {
  if (mi < 0) { return []; }
  if (family == 0) {
    if (mi < capEntryKeysVideo.size()) { return capEntryKeysVideo[mi]; }
    return [];
  }
  if (family == 1) {
    if (mi < capEntryKeysPhoto.size()) { return capEntryKeysPhoto[mi]; }
    return [];
  }
  if (family == 2) {
    if (mi < capEntryKeysRes.size()) { return capEntryKeysRes[mi]; }
    return [];
  }
  return [];
}

// Membership of an Array of String. The content test is .equals(), never
// == on a String, which compares object identity (note 9 of the CdC).
function indexOfIn(ids, id) as Lang.Int {
  var k = 0;
  while (k < ids.size()) {
    if (ids[k].equals(id)) { return k; }
    k += 1;
  }
  return -1;
}

// The position of an entry of a model answers the family it belongs to
// and the index of the entry, as one number: family * 1000 + k. One
// scan answers both, so the family, the tier and the key of the entry
// a selection carries cannot disagree about that entry.
function entryIndexOfId(mi, id) as Lang.Int {
  var at = indexOfIn(rowIds(0, mi), id);
  if (at >= 0) { return at; }
  at = indexOfIn(rowIds(1, mi), id);
  if (at >= 0) { return 1000 + at; }
  at = indexOfIn(rowIds(2, mi), id);
  if (at >= 0) { return 2000 + at; }
  return -1;
}

// The tier and the key of the entry an id names, in the menu of a model.
// The position comes from entryIndexOfId above, so the four views of the
// entry a selection carries stay one datum: the id, the label, the tier
// and the key all answer the same position (note 8 of the CdC). An id
// the model does not answer asks for no frame, so the tier is the empty
// String and the key the empty String: the caller prints the refusal and
// sends nothing, and an absence of a line is never a verdict (criterion
// 14 of 11.3).
function entryTierOfId(mi, id) as Lang.String {
  var at = entryIndexOfId(mi, id);
  if (at < 0) { return ""; }
  var family = at / 1000;
  var k = at % 1000;
  var tiers = rowTiers(family, mi);
  if (k < tiers.size()) { return tiers[k]; }
  return "";
}

// The semantic key of the same entry, the datum that names the frame of
// the entry without naming a protocol number: the key is the one the
// reference app speaks (TimeLapse, BulletTime, 5k30), and the frame
// arrives at the one site refFrame() below, never by a number carried
// from the menu (rea/11: the numbering of an OFFICIAL cell is not a
// protocol value, and the numbering is not a scale across models).
function entryKeyOfId(mi, id) as Lang.String {
  var at = entryIndexOfId(mi, id);
  if (at < 0) { return ""; }
  var family = at / 1000;
  var k = at % 1000;
  var keys = rowKeys(family, mi);
  if (k < keys.size()) { return keys[k]; }
  return "";
}

// The envelope the application builds for that model, by name. The name is
// the datum the choice of the entry MenuLevel carries (CdC item 158), so
// a choice and the envelope of that model answer the two tables of one
// datum, and the choice of off, which gives the detected model back,
// reads the level of the model the bond named from the same table: no
// hand-written number can disagree with a detection. A name the matrix
// does not know answers -1, a level no case of the gate answers, so an
// unknown model offers no menu and the print at the gate says so.
function menuLevelOfName(name) as Lang.Int {
  var i = indexOfIn(capModels, name);
  if (i < 0) { return -1; }
  return capMenuLevel[i];
}
}