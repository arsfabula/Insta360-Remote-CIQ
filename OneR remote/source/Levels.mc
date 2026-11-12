// Levels — the chain of menu levels, the axis 2 of the architecture (the axis 1,
// the frame envelope, is detected in the protocol barrel and lives nowhere here).
//
// A level is a delta on the level below it. The menu of a level is the base
// (Level 0) plus every delta up to that level, assembled by rowsMain() and
// rowsRes() below — never a table copied per model. Similar generations share
// a level; a real jump of functions opens a new one. A level that REPLACES the
// chain (REPLACE_FROM, today levels 2 and 3) answers with its own rows alone:
// rows documented for an older envelope are not offered to a newer camera.
// That is the bench of 12 nov. speaking (real X5 fw 1.13.21, bench-run
// logs): it ACQUITTED the legacy mode frames of the stacked level-1 rows and
// did nothing - zero push, zero change on its own screen, while the watch
// displayed the new mode (a screen lie) - and its no-frame rows (Video,
// Starlapse) blocked the wheel where a measured ladder waited behind them.
// a replacing level is therefore a complete menu, and this is what its section
// says it measured. A camera the chain does not name stays at Level 0, the
// universal fallback: Level 0 holds no mode list and no
// option value, only what is proven to cross the 20-octet wall on
// every known format (the Default Video entry, the start/stop of the main
// view, the state pushes 0x2010/0x2040, the card push 0x2006).
//
// Provenance of every row is a comment at the row, with the reduced
// vocabulary of the architecture:
//   mesure:  a frame of this barrel was written to that camera at the bench
//            (the X5 line, fw 1.13.21, docs/data/x5-mode-catalog-fw1.13.21.md
//            and docs/data/x5-ble-survey-fw1.13.21.md)
//   doc:     a column of the official documentation (out/rea/11-capacites-cross-model.md)
//   no marker: plumbing of the application, not a capability
// A doc row names a key, never a protocol number (rea/11: the numbering of a
// cell is not a protocol value and is not a scale across models). The key
// resolves at refFrame() in InputDelegate.mc, the single site that turns a
// key into a frame; a row whose key answers no frame stays visible and is
// refused at its selection. The masks and their API are gone with the
// capability barrel: the table below IS the menu, and the state read on the
// camera never filters it (the rule is written once in the application: an
// state seen on the camera and absent here stays visible and reusable).
//
// Row format, positional, one array per entry (the id, the label, the key and
// the family of an entry are one datum and cannot be paired wrong):
//   [0] id     the string the selection brings back
//   [1] label  what the item prints
//   [2] key    the key of refFrame(); "" names no frame, the id names itself
//   [3] fam    "v" video mode, "p" photo mode, "r" resolution, "x" sentinel
//   [4] sub    1 opens the resolution submenu, 0 does not
// The id namespace is scoped by the level: rowOfId() answers only through the
// rows of the level in force, so an id never resolves through the rows of
// another level and no hand-written pair can disagree with a row.

using Toybox.Lang;

module Levels {

const MAX_LEVEL = 3;

// The first level that replaces the chain instead of adding to it. Chosen at
// the bench of 12 nov. on the real X5 (see the header): a camera of a newer
// line is served the menu of its own line, nothing else.
const REPLACE_FROM = 2;

// Index of a row (the row format above).
const RID = 0;
const RLB = 1;
const RKEY = 2;
const RFAM = 3;
const RSUB = 4;

// ---------------------------------------------------------------------------
// Axis model: the table modele -> niveau. One line per model, one provenance
// per line. This table and the prefix chain of the protocol barrel
// (BLEBarrel.onScanResults) answer the same datum, the model of a name and
// its level: keep the two in step, the chain names the model over the air,
// this table is what the application reads for a forced choice and for the
// choices of the MenuLevel submenu.
const models = [
    "X5",       // mesure: releve over BLE; UCD2-era menu of the X5 line
    "X4 Air",   // doc: same line as the X4, the name decides over the air
    "X4",       // doc: the X5 line before the X5
    "X3",       // doc: the older envelope
    "X2",       // doc: the older envelope, never the level 0 (the X2 is pre-UCD2)
    "ONE X",    // doc: the older envelope
    "X6"        // doc: the UCD2 envelope
];
const modelLevels = [2, 2, 2, 1, 1, 1, 3];

// The level of a model name; -1 names no model of the table, and the caller
// keeps the level the chain of the barrel left standing. The content test of
// a String is .equals(), never == on a String, which compares object
// identity. The walk is an index walk: Lang.Array.find answers on no target.
// The function is untyped on purpose, like the numeric helpers of the house:
// the type checker reads a const Array of Int as Number, and a declared Int
// return then cannot receive modelLevels[i] (measured at the gate, 9.1.0).
function levelOfName(name) {
    var i = 0;
    while (i < models.size()) {
        if (models[i].equals(name)) {
            return modelLevels[i];
        }
        i += 1;
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Level 0, the base: no mode row, no option row. The application adds its own
// plumbing (MenuLevel, the GPS toggle, the Default Video entry) below Level 3.
const rowsMainL0 = [];
const rowsResL0 = [];

// ---------------------------------------------------------------------------
// Level 1, the older envelope: the doc columns of the X3, X2 and ONE X
// matrices (out/rea/11 §4-§6). One menu per level: a row of one model of the
// level is a row of the level, and a row whose key answers no frame is
// refused at the selection, never hidden. The ids are the keys themselves —
// the numbering of the protocol exists over BLE on the X5 only (rea/11).
// These rows reach level 1 alone: from REPLACE_FROM up the chain is replaced,
// so none of them is offered to the newer lines (bench of 12 nov., header).
const rowsMainL1 = [
    ["Video",         "Video",       "",             "v", 1],  // doc: opens the res submenu; no frame names this mode of the older envelope
    ["TimeLapse",     "Timelapse",   "TimeLapse",    "v", 0],  // doc: column X3/X2/ONE X; the reference app wrote cmdSetTL for it
    ["BulletTime",    "Bullet Time", "BulletTime",   "v", 0],  // doc: column X3/X2/ONE X; the reference app wrote cmdSetBullet for it
    ["Photo",         "Photo",       "Photo",        "p", 0],  // doc: column X3/X2/ONE X; reference frame cmdSetPhoto
    ["PhotoHDR",      "HDR Photo",   "PhotoHDR",     "p", 0],  // doc: column X3/X2/ONE X; reference frame cmdSetPhotoHDR
    ["PhotoStar",     "Starlapse",   "",             "p", 0],  // doc: column X3/X2, official cell, no frame
    ["PhotoInterval", "Interval",    "PhotoInterval","p", 0],  // doc: column X3/X2/ONE X; reference frame cmdSetInterval
    ["PhotoBurst",    "Burst Photo", "PhotoBurst",   "p", 0],  // doc: column X3/X2; reference frame cmdSetPhotoBurst
    ["NightShot",     "Night Shot",  "NightShot",    "p", 0]   // doc: column X2 only; reference frame cmdSetNightShot — one menu per level
];
const rowsResL1 = [
    ["5k30",  "5.7K 30", "5k30",  "r", 0],  // doc: column X3/X2/ONE X
    ["5k25",  "5.7K 25", "5k25",  "r", 0],  // doc: column X3/X2
    ["5k24",  "5.7K 24", "5k24",  "r", 0],  // doc: column X3/X2/ONE X (the ONE X column orders 5.7K 24 before 5.7K 25)
    ["4k60",  "4K 60",   "",      "r", 0],  // doc: column X3 only, no frame
    ["4k50",  "4K 50",   "4k50",  "r", 0],  // doc: column X3/X2/ONE X
    ["4k30",  "4K 30",   "4k30",  "r", 0],  // doc: column X3/X2/ONE X
    ["4k24",  "4K 24",   "",      "r", 0],  // doc: column X3 only, no frame
    ["4k25",  "4K 25",   "",      "r", 0],  // doc: column X3 only, no frame
    ["3k100", "3K 100",  "3k100", "r", 0]   // doc: column X3/X2; the reference app wrote a frame for it
];

// ---------------------------------------------------------------------------
// Level 2, the X5 line (X4 Air, X4, X5). The X5 rows are hand-written from
// the measured column of docs/data/x5-mode-catalog-fw1.13.21.md and the
// frames this barrel measured on fw 1.13.21; the id of a measured row is the
// protocol number of the X5 (option 41, option 40, option 31) — the id IS the
// key, and the 0x2053 echo gate and the 0x190 degradations derive that same
// id from a frame of the wire. Starlapse (12) stays out of the table: the app
// offers no Starlapse entry (decision of the bench, CdC item 100); the frame
// stays declared in the barrel as the datum of the rungs S-17 and S-23.
// This level replaces the chain (REPLACE_FROM): it IS the menu of the X5 line,
// and the bench of 12 nov. is why — with the level-1 rows stacked under it,
// the X5 acquitted their frames without moving and the no-frame rows blocked
// the wheel. X4 Air and X4 map to this level on the documentation ("the X5
// line before the X5"); only the X5 has ever been walked at a bench, so for
// those two this menu is doc, not mesure.
const rowsMainL2 = [
    ["v0",  "Video",          "v0",  "v", 1],  // mesure: cmdSetVideoSubNormal, opens the res submenu (record_resolution is pilotable inside VIDEO_NORMAL only, rea/11 §5.3)
    ["v1",  "Bullet Time",    "v1",  "v", 0],  // mesure: cmdSetVideoSubBulletTime
    ["v2",  "Timelapse",      "v2",  "v", 0],  // mesure: cmdSetVideoSubTimelapse
    ["v4",  "TimeShift",      "v4",  "v", 0],  // mesure: cmdSetVideoSubTimeShift
    ["v6",  "Loop Recording", "v6",  "v", 0],  // mesure: cmdSetVideoSubLoop
    ["v11", "PureVideo",      "v11", "v", 0],  // mesure: cmdSetVideoSubPure
    ["v14", "Road Mode",      "v14", "v", 0],  // mesure: cmdSetVideoSubRoad
    ["v15", "InstaFrame",     "v15", "v", 0],  // mesure: cmdSetVideoSubInstaFrame
    ["p0",  "Photo",          "p0",  "p", 0],  // mesure: cmdSetPhotoSubNormal; the capture belongs to the press, never to the selection
    ["p2",  "Interval",       "p2",  "p", 0],  // mesure: cmdSetPhotoSubInterval
    ["p3",  "Burst Photo",    "p3",  "p", 0]   // mesure: cmdSetPhotoSubBurst
];
// The order is the decision of the app (CdC item 107: the resolutions live
// under the Video entry, high pixel class to low; the protocol numbers carry
// no order — 0 is 4K 30, 167 is 8K 30).
const rowsResL2 = [
    ["r167", "8K 30",    "r167", "r", 0],  // mesure: cmdSet8k30
    ["r10",  "5.7K 30",  "r10",  "r", 0],  // mesure: cmdSet5k30
    ["r19",  "5.7K 25",  "r19",  "r", 0],  // mesure: cmdSet5k25
    ["r20",  "5.7K 24",  "r20",  "r", 0],  // mesure: cmdSet5k24
    ["r12",  "4K 50",    "r12",  "r", 0],  // mesure: cmdSet4k50
    ["r0",   "4K 30",    "r0",   "r", 0]   // mesure: cmdSet4k30
];

// ---------------------------------------------------------------------------
// Level 3, the UCD2 envelope (X6). The jump is real, so the level replaces
// rather than adds: a camera of this envelope answers one entry, and the
// legacy rows of the levels below are not offered to it — the gate of the
// application builds no level under this one (rowsOfLevel() stops the chain
// at a replacing level). The X6Video entry arms the envelope; its write is
// not a frame of this table (the "x" family of the row says so, and the
// legacy frames never reach this camera).
const rowsMainL3 = [
    ["X6Video", "X6 Video", "", "x", 0]
];
const rowsResL3 = [];

// The chain of the main menu and of the resolution submenu, per level.
const chainMain = [rowsMainL0, rowsMainL1, rowsMainL2, rowsMainL3];
const chainRes = [rowsResL0, rowsResL1, rowsResL2, rowsResL3];

// The rows of a level. Below REPLACE_FROM the menu is the base plus every
// delta up to that level. At REPLACE_FROM and above, the level IS the menu:
// the chain stops at it (REPLACE_FROM names the bench evidence, and the L3
// envelope argument it always carried). The walk is by index; Lang.Array.find
// answers on no target.
function rowsOfLevel(chain, level) {
    var out = [];
    if (level > MAX_LEVEL) {
        level = MAX_LEVEL;
    }
    if (level < 0) {
        return out;
    }
    if (level >= REPLACE_FROM) {
        return chain[level];
    }
    var i = 0;
    while (i <= level) {
        var rows = chain[i];
        var k = 0;
        while (k < rows.size()) {
            out.add(rows[k]);
            k += 1;
        }
        i += 1;
    }
    return out;
}

function rowsMain(level) {
    return rowsOfLevel(chainMain, level);
}

function rowsRes(level) {
    return rowsOfLevel(chainRes, level);
}

// The row of an id, in the level in force: id, label, key and family answer
// one position of one chain (the tell and the decision answer one datum). An
// id the level does not answer returns null — a plumbing id, an id of another
// level, or nothing; the caller prints the absence and sends no frame. The
// content test is .equals(), never == on a String.
function rowOfId(level, id) {
    if (id == null || id.length() == 0) {
        return null;
    }
    var rows = rowsMain(level);
    var i = 0;
    while (i < rows.size()) {
        if (rows[i][RID].equals(id)) {
            return rows[i];
        }
        i += 1;
    }
    rows = rowsRes(level);
    i = 0;
    while (i < rows.size()) {
        if (rows[i][RID].equals(id)) {
            return rows[i];
        }
        i += 1;
    }
    return null;
}

// The row the screen must hold when the level in force answers nothing under
// the mode in force. The rule is one datum, not an inference: the menu and the
// mode are the same chain, so a level change (a detection, a forced model)
// leaves a pose that no row carries, and the screen would name a mode that
// does not exist - the bench of 12 nov. watched "DEFAULT VIDEO" over the
// eleven dots of the X5 line, a name open() poses and no level lists.
//
// The decision, in the order the user chose at that bench (12 nov.): the mode
// this camera last CONFIRMED, kept under its name by the barrel at its echo;
// else the first row of the level, which is the normal video of that line;
// else nothing to pose - no rows (level 0, the legacy pose of the app) or the
// mode already answers a row of this menu (browsing, a resolution submenu).
// The kept id is only asked through this level's rows: an id of another level
// never comes back, that is what rowOfId() means.
function poseFor(level, keptId, currentId) {
    var rows = rowsMain(level);
    if (rows.size() == 0) {
        return null;
    }
    if (rowOfId(level, currentId) != null) {
        return null;
    }
    var kept = rowOfId(level, keptId);
    if (kept != null) {
        return kept;
    }
    return rows[0];
}

}
