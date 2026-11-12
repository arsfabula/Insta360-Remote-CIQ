using Toybox.System;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Application as App;
using Toybox.Position;
using Toybox.Graphics;
using Toybox.Application.Storage;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Timer;

module BLEBarrel {









const LBS_SERVICE = BluetoothLowEnergy.stringToUuid("0000BE80-0000-1000-8000-00805F9B34FB");
const LBS_RW_CHAR = BluetoothLowEnergy.stringToUuid("0000BE81-0000-1000-8000-00805F9B34FB");
const LBS_NOTIF_CHAR = BluetoothLowEnergy.stringToUuid("0000BE82-0000-1000-8000-00805F9B34FB");
const LBS_NOTIF_DESC = BluetoothLowEnergy.cccdUuid();

const stateBusy = 0xf4;
const stateCmdErr = 34;
const stateStandby = [0x7, 0, 0, 0, 0x5, 0, 0]b;
const stateStopRec = 0;
const stateStartRec = 1;
const stateStarting = 2;
const stateStopping = 3;




const recReportCode = 0x40;
const recReportCodeLegacy = 0x10;
const SeqPos = 10;



const RETRY_DELAY_MS = 2500;
const RETRY_MAX = 3;
const retryKindStart = 1;
const retryKindStop = 2;





const ACK_CODE = 0xC8;





const START_DELAY_MS = 1200;
const START_WAIT_MS = 400;
const START_WAIT_MAX = 3;

// Pump watchdog. The queue only moves on a requestWrite and its write callback;
// when the stack keeps refusing writes, nothing here recovers on its own - no
// timer re-kicks the pump, the next kick is whatever the user does next. After
// this many consecutive refused writes the bond is declared dead: the unpair
// and the teardown of the disconnect path (linkGone) run, and the normal
// re-scan brings a fresh bond.
const WEDGE_REFUSALS_MAX = 4;







const UCD2_HDR = 8;
const UCD2_FLAGS = 0x0c;
const UCD2_TYPE = 6;
const UCD2_SEQ = 7;
const UCD2_LEN = 8;
const UCD2_PAY = 12;
const UCD2_TAIL = 4;
const ucd2TypeFile = 0x04;
const ucd2OpStart = 4;
const ucd2OpStop = 5;
const ucd2ReqId = 1;
const ucd2FileMarker = 0x02;

const ucd2FileFlags = [0x00, 0x80, 0x00, 0x00]b;




















const ucd2TrailStartBase = [0x5b, 0x4d, 0x4b, 0x5a]b;
const ucd2TrailStopBase = [0x45, 0xfa, 0x0b, 0xf1]b;
const ucd2SeqXor = [0x9b, 0x7a, 0xbf, 0x64, 0x36, 0xf5, 0x7e, 0xc9, 0xdb, 0xf7, 0x3c, 0x96, 0x01, 0xf2, 0xb8, 0x28, 0x02, 0xe4, 0x71, 0x51, 0x04, 0xc8, 0xe3, 0xa2, 0xbf, 0x8d, 0x06, 0x41, 0x7e, 0x1b, 0x0d, 0x82]b;










const ucd2RxMaxBody = 512;



const DEBUG_TRACE = false;

// LOG_FRAMES (item 9 of the integration, the hygiene of the log): the lines of
// per-frame CONTENT - the hex of every chunk across the delegate (wireBytes) and
// the decoded field line of every notification (the [nf] line) - are what fills
// the ~90 lines the watch keeps in X5remote.TXT/BAK within seconds of a running
// recording (docs/x5-protocol.md, the retention datum), so the verdict lines of
// the decisions are out of the file before a user can pull it. The lines of
// EVENTS (the wireLine family) answer the same facts named, one line per fact,
// and they are the bench datum surface; the per-frame content answers the bytes,
// which is only asked when the bytes themselves are on trial. This constant
// turns the content lines off; armWire, the [wire] event lines it arms, and
// every verdict line are untouched. With the constant false, every #n of the
// wire log is one event line and no hex sits between them. The counters the
// peek* API answers move whatever these lines print: the counters are a datum
// apart from the log, never a print of it.
const LOG_FRAMES = false;







const X6_TEST_HOOK = false;
const X6_TEST_HOOK_NAME = "X5 3S6GEW";

// of that: a frame of the forced family crosses only while the counter stays
// under it, and the refusal answers with a print at the transport, never by
// silence (criterion 14 of 11.3). The datum counts the frames that crossed.
// The bound counts the writes of the run of a family forced, not the writes
// of one entry: a video session of a family forced answers its start and its
// stop among them, so the bound has to leave room for a session, and the
// axis moved it from 3 to 10 on 2026-11-01 at the request of the user (CdC
// item 159). The datum a run answers stays the line [hook] refused beside the
// count of the writes that reached, never a reply of the camera (EF-22).
// The counter is taken back at two sites: the clearing of the forcing at a
// re-connect, and the selection of the entry MenuLevel, which ends one visit
// of the axis and opens the next (a fresh visit is a fresh ceiling, CdC item
// 159). The value is a decision of the axis of safety, never a reading of a
// rung: a camera never asked for a frame never refuses it.
const HOOK_WRITE_CEILING = 10;


var recState as Lang.Number = stateStopRec;
var startRecTime as Time.Moment = Time.now();
var elapsedRecTime as Time.Duration or Null = null;
var clockTime as Time.Moment or Null = null;
var lastTime as Time.Moment = Time.now();
var GPSon as Lang.Boolean = false;
var GPSaccuracy as Position.Quality = Position.QUALITY_NOT_AVAILABLE;
var connecting as Lang.Boolean = false;
var menuLevel as Lang.Number = 1;
var deviceName as Lang.String = "n/a";
// Axis model: the model of the capability matrix that the menu is built for, and
// the model the scan detected. The two stay apart because the hook of the menu
// forces the menu of another model on the camera the user owns: the forcing
// overwrites capModel and menuLevel, never detectedModel and detectedLevel, so a
// forced run says which model was detected and which one is in force (note 8 of
// the CdC: the tell and the decision answer one datum).
var capModel as Lang.String = "n/a";
var detectedLevel as Lang.Number = 1;
var detectedModel as Lang.String = "n/a";
// The forcing of the menu, at runtime, by the entry MenuLevel. It answers the
// model of the matrix in force and the envelope to build for it, and the datum
// of the writes that crossed while it is on.
var testModel as Lang.String = "";
var testLevel as Lang.Number = -1;
var hookSent as Lang.Number = 0;

// CdC item 107, the datum of the pop depth of the resolution sub-menu. The
// resolutions are not entries of the main menu any more: the entry Video
// pushes a Menu2 of its own, so the view stack is one deeper while that
// sub-menu is on the screen, and the selection of a resolution has to leave
// two views to come back to the main one. The flag lives in this barrel and
// not in the delegate: the delegate of the sub-menu is a new instance of the
// same class, so it cannot carry what the delegate of the main menu set. It
// is set at the push site and cleared at the pop site, the shape the flags of
// the arming settled at items 68 and 93 (a barrel boolean survives a
// re-assignment, a patched array did not).
var resolutionSubmenuOn as Lang.Boolean = false;
	// The datum of the pop depth of the submenu of MenuLevel, the way the
	// resolution submenu carries its own flag: the delegate of a submenu is a
	// new instance of the same class, so it cannot carry what the delegate of
	// the main menu set, and the depth is not a fact of the view but a fact of
	// the navigation (CdC item 107). Two submenus, two flags, never one flag
	// read for two submenus (note 8 of the CdC).
	// A fresh view of the main menu re-derives the depth, so this datum needs no
	// clearing at the re-connect: it lives with the navigation, not with the
	// forcing of the model (CdC item 158, axis of the persistence).
var menuLevelSubmenuOn as Lang.Boolean = false;

var SeqNo as Lang.Number = 1;



var ucd2Armed as Lang.Boolean = false;
var ucd2SeqNo as Lang.Number = 1;



var txUcd2 as Lang.Boolean = false;
var ucd2TxKind as Lang.Number = 0;


var ucd2RxBuf as Lang.ByteArray or Null = null;
var ucd2RxWant as Lang.Number = 0;



var queue as Lang.Array = [];
var cmdStartRec as Lang.ByteArray = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;
var cmdStopRec as Lang.ByteArray = [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b;
var cmdApply as Lang.ByteArray = [0x10, 0, 0, 0, 0x4, 0, 0, 0xf, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b;
var cmdSet5k24 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x14, 0x18, 0x7]b;
var cmdSet5k25 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x13, 0x18, 0x7]b;
var cmdSet5k30 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x7]b;
var cmdSet8k30 as Lang.ByteArray = [0x1b, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x4, 0xf8, 0x1, 0xa7, 0x01, 0x18, 0x7]b;
var cmdSet4k30 as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x0, 0x18, 0x7]b;
var cmdSet4k50 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0c, 0x18, 0x7]b;
var cmdSet3k100 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x7]b;
var cmdSetHDR as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x15, 0x18, 0x7]b;
var cmdSetTL as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x2]b;
var cmdSetBullet as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x4]b;
var cmdSetPhoto as Lang.ByteArray = [0x10, 0, 0, 0, 0x4, 0, 0, 0x3, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b;
var cmdSetPhotoHDR as Lang.ByteArray = [0x46, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x01, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00, 0x1a, 0x03, 0x27, 0x00, 0x4e]b;
var cmdSetPhotoBurst as Lang.ByteArray = [0x10, 0, 0, 0, 0x4, 0, 0, 0x3, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b;






var cmdSetPhotoSubBurst as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x28, 0x12, 0x3, 0xc0, 0x2, 0x3]b;
var cmdSetPhotoSubNormal as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x28, 0x12, 0x3, 0xc0, 0x2, 0x0]b;
var photoBurstMode as Lang.Boolean = false;
var cmdSetPhotoSubInterval as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x28, 0x12, 0x3, 0xc0, 0x2, 0x2]b;
var photoCaptureMode as Lang.Boolean = false;
var timelapseStopMode as Lang.Boolean = false;
var cmdStopTimelapse as Lang.ByteArray = [0x12, 0, 0, 0, 0x4, 0, 0, 0x17, 0, 0x02, 0xff, 0, 0, 0x80, 0, 0, 0x08, 0x02]b;
    // S-23 (CdC item 93): the start of the Timelapse command, with the TimelapseMode member
    // that names a Starlapse (5 = TIMELAPSE_STARLAPSE_SHOOTING, an OFFICIAL word mark and
    // never a BLE datum) in field 1 of the body. The flag is re-set on every selection and
    // armed only by a v12 selection, the shape the stop of the p2 entry settled at item 68.

    var starlapseStartMode as Lang.Boolean = false;
    var cmdStartStarlapse as Lang.ByteArray = [0x12, 0, 0, 0, 0x4, 0, 0, 0x16, 0, 0x02, 0xff, 0, 0, 0x80, 0, 0, 0x08, 0x05]b;


var cmdSetVideoSubNormal as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0x0]b;
var cmdSetVideoSubBulletTime as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0x1]b;
var cmdSetVideoSubTimelapse as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0x2]b;
var cmdSetVideoSubTimeShift as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0x4]b;
var cmdSetVideoSubLoop as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0x6]b;
var cmdSetVideoSubPure as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0xb]b;
var cmdSetVideoSubStarlapse as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0xc]b;
var cmdSetVideoSubRoad as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0xe]b;
var cmdSetVideoSubInstaFrame as Lang.ByteArray = [0x17, 0, 0, 0, 0x4, 0, 0, 0x7, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x29, 0x12, 0x3, 0xc8, 0x2, 0xf]b;


var cmdSetInterval as Lang.ByteArray = [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetNightShot as Lang.ByteArray = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x2b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x04, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdHighlight as Lang.ByteArray = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0x8b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xde, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x68, 0x69, 0x67, 0x68, 0x6c, 0x69, 0x67, 0x68, 0x74]b;
var cmdTrackThat as Lang.ByteArray = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0xa8, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xf8, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x74, 0x72, 0x61, 0x63, 0x6b, 0x54, 0x68, 0x61, 0x74]b;

// Battery of the X5 on demand: GET_OPTIONS (code 8) with the packed option
// list asking option 11 (battery) and option 20 (storage state), the two that
// carry the cell. The request frame is 20 octets, one write chunk at the
// 20-octet ceiling; the answer may be wider than that ceiling, and the
// declared/arrived pair answers what crossed. Verified on the live X5 under
// code 8; the bench's getFrame runs code 10, another GET of the family.
var cmdGetBattery as Lang.ByteArray = [0x14, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x08, 0x00, 0x02, 0xff, 0x00, 0x00, 0x80, 0x00, 0x00, 0x0a, 0x02, 0x0b, 0x14]b;

// Powering the camera off (SET_SHUTDOWN, code 0xDB, empty body). The datum is the PR's,
// run by its author on his own X5; here it is a frame until the Phase 5 bench answers
// for it. One write, no body: the 20-octet ceiling keeps the whole frame and leaves the
// same 16-octet answer shape as every write of this family.
var cmdShutdownX5 as Lang.ByteArray = [0x10, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x0db, 0x00, 0x02, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00]b;

// The varint writer of the protobuf bodies. Static frames above carry their body as
// declared; a value that varies at runtime (an option id, an interval in seconds) is
// written through this: one byte under 0x80, the 0x80 bit chaining the longer values.
// The same encoder the PR names pbVar at its setter sites. Untyped, like the numeric
// helpers of the house: it hands Numbers, never the Int the constants typecheck as.
function pbVar(n) {
	var out = []b;
	while (true) {
		var x = n & 0x7f;
		n = n >> 7;
		out.add(n > 0 ? (x | 0x80) : x);
		if (n <= 0) { break; }
	}
	return out;
}

// The 16-octet envelope of a request with a body, the shape every write of this family
// keeps: declared length at 0..3 (self-stamped), service octets, the command as 16 bits
// at 7..8, 0x02, the sequence left at 0..0 here because sendCMD stamps octet 10 on the
// way out, and the 0x80 tail. The PR's frameX5, under this house's name.
function x5BodyFrame(code, body) {
	var f = [0, 0, 0, 0, 0x04, 0, 0, code & 0xff, (code >> 8) & 0xff, 0x02, 0, 0, 0, 0x80, 0, 0]b;
	f.addAll(body);
	f[0] = f.size();
	return f;
}

// The option writes whose value varies at runtime, the family the static frames above
// declare one instance of. Shapes are the PR's, run by its author on his X5; they send
// nothing until the Phase 4 settings page asks, and the Phase 5 bench answers for them.
// The photo (option 40) and video (option 41) sub-modes: the body is a SET of the option,
// and the camera answers them with the 0x2053 echo the gate of this module already reads.
function setSubModeX5(video, n) {
	var opt = video ? 0x29 : 0x28;           // OptionType VIDEO_SUB_MODE=41 / PHOTO_SUB_MODE=40
	var tag0 = video ? 0xc8 : 0xc0;          // Options field 41/40 -> tag bytes c8 02 / c0 02
	var body = (n == 0) ? [0x08, opt, 0x12, 0x00]b : [0x08, opt, 0x12, 0x03, tag0, 0x02, n]b;
	return x5BodyFrame(0, body);
}

// SET_PHOTOGRAPHY_OPTIONS (0x09) {1: type, 2: {type: v}, 3: function mode}
function setPhotoOptX5(fm, type, v) {
	var inner = pbVar(type << 3);
	inner.addAll(pbVar(v));
	var b = [0x08]b; b.addAll(pbVar(type));
	b.add(0x12); b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x18); b.addAll(pbVar(fm));
	return x5BodyFrame(0x09, b);
}

// SET_TIMELAPSE_OPTIONS (0x12) {1: {2: lapse_ms}, 2: timelapse mode}
function setLapseX5(tm, ms) {
	var inner = [0x10]b; inner.addAll(pbVar(ms));
	var b = [0x0a]b; b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x10); b.addAll(pbVar(tm));
	return x5BodyFrame(0x12, b);
}

// SET_TIMELAPSE_OPTIONS (0x12) {1: {1: duration_s}, 2: timelapse mode} (Starlapse total time)
function setLapseDurX5(tm, s) {
	var inner = [0x08]b; inner.addAll(pbVar(s));
	var b = [0x0a]b; b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x10); b.addAll(pbVar(tm));
	return x5BodyFrame(0x12, b);
}

// SET_ACTIVE_SENSOR (0x41): 3 both lenses (360), 1 front
function setSensorX5(v) { return x5BodyFrame(0x41, [0x08, v]b); }

var currentMode as Lang.String or Lang.ByteArray = "DefaultV";
var videoMode as Lang.Boolean = true;
var currentLabel as Lang.String = "Default Video";
var startMessage as Lang.String = "";
var mMessage as Lang.String = "Start";



























const NOTIF_MIN = 0x2000;
const X5_SUB_MODE_NOTIF = 0x2053;
const X5_OPTIONS_NOTIF = 0x2065;
const X5_CAPTURE_NUM_NOTIF = 0x2064;
const X5_CAPTURE_STATUS_NOTIF = 0x2010;
const X5_AUTH_RESULT_NOTIF = 0x2011;
const X5_RECORD_STATE_NOTIF = 0x2040;


const X5_STORAGE_NOTIF = 0x2006;
const X5_STOP_PUSH_NOTIF = 0x2062;

// Battery of the X5. The camera pushes 0x2003 (8195, the message code map names
// it CAMERA_NOTIFICATION_BATTERY_UPDATE) whenever the power source changes: the
// charger in, the charger out, and nothing else was seen moving it. 0x2004
// (8196) is the low-battery alarm of the same family. The body is a protobuf:
// one nested status block at field 1, holding field 1 the power source (0 runs
// on the cell, 1 sits on the adapter), field 2 the level in percent, the scale
// never sent.
// The watch measurement (BLE Probe run of 2026-11-04): the delegate negotiates
// ATT MTU 23, its notifications top out at 20 octets, and the camera truncates
// an oversized frame instead of continuing it. The push declares 24 and crosses
// as 20, which still carries the power type at the twentieth octet but leaves
// the level past the cut; the GET_OPTIONS reply of the same datum (51 octets,
// and no smaller shape is defined) can never carry it on that link at all.
const X5_BATTERY_NOTIF = 0x2003;
const X5_BATTERY_LOW_NOTIF = 0x2004;

// Option id 11 of the GET_OPTIONS reply carries the same battery, nested one
// block deeper, next to option 20 for the storage state.
const X5_OPT_BATTERY = 11;
const X5_OPT_STORAGE_STATE = 20;

// Command 15 in the same envelope, PHONE_COMMAND_GET_CURRENT_CAPTURE_STATUS in
// the APK map. It is the only request measured on this link that puts a state
// byte under the 20-octet notification ceiling: the camera answers code 200
// with body 0a 06 08 <state> 10 <seconds> 50 <n> and the watch leg keeps
// 0a 06 08 <state>, because the state sits at frame octet 19, one octet inside
// the cut, while the seconds sit at 21 and 22, outside it. Measured at rest and
// while recording on the bench of 2026-11-05 (PROTOCOL_APK.md 15.21, 15.24 and
// 15.27): 0 is at rest, 1 is recording. cmdApply further down is this command
// with an empty body; the start sequence reads its code-200 answer as the ACK
// of the mode write, and the very same frame is read here for the state.
// The seconds, the option 11 battery level and the option 20 free bytes all
// start at octet 21 or later and have never crossed this link, so this is also
// the whole of what a connect-time read can learn about the camera.
const X5_GET_CAPTURE_STATUS = 15;
const X5_STATE_AT_REST = 0;
const X5_STATE_RECORDING = 1;
const STATUS_ASK_MS = 1500;
const STATUS_RETRY_MS = 6000;
const STATUS_RETRY_MAX = 2;

// The bound of the mode echo gate: the camera's confirmation of a mode write
// was seen 0.3 to 0.5 s after it on both benches, so 3 s covers the answer
// with room, and the gate opens by itself if the answer never comes. The PR
// holds the same value (holdMode(3000)); its browsing hold of 800+3000 is an
// app decision, not a protocol one, and sits with the app.
const MODE_ECHO_HOLD_MS = 3000;

// The authorization handshake, part of every connect on a legacy-framed link:
// CHECK_AUTHORIZATION (39) as a WATCH_GARMINOS client, 500 ms after the notify
// profile opens. The camera only pushes to a client that completed this handshake
// (measured twice on X5 fw 1.13.21: PR #2 by @no84by and this barrel's own
// probe; PROTOCOL_APK.md §15.14). The answer moves no UI state yet, it only
// feeds the wire log and authProbeStatus.
const AUTH_CMD = 0x27;
const AUTH_PROBE_MS = 500;

// The card-state ask at connect, third in the ladder. The 0x2006 push names
// the card only when it moves, never when the bond opens, so until something
// moves the card state would stay unknown. GET_STORAGE (166) with body
// {1: location 0} is the phone app's ask; its answer is one of the shapes
// the docs name readable on this link - card_state inside the 20 octets, the
// sizes past the cut and unknown as everywhere here (docs §10 of
// x5-protocol.md; the PR's bench answered this frame, storSeq line of its
// barrel). Asked once per link, 2500 ms, after the auth and status asks so
// it never slips between them.
const STORAGE_CMD = 0xA6;
const STORAGE_ASK_MS = 2500;




const X5_PERIODIC_NOTIF = 0x2017;
const x5PhotoSubModeNotif = 1;
const x5VideoSubModeNotif = 2;





const x5FuncModeNormalVideo = 7;
const x5SubModeNotApplicable = 100;
const x5NotifMaxBody = 512;













var x5Armed as Lang.Boolean = false;
var x5RxBuf as Lang.ByteArray or Null = null;
var x5RxWant as Lang.Number = 0;
var x5RxLast as Lang.ByteArray or Null = null;
var x5RxWasNotif as Lang.Boolean = false;
var x5RxNewFrame as Lang.Boolean = false;
var x5RxDeclared as Lang.Number = 0;
var x5RxArrived as Lang.Number = 0;
var x5RxTruncated as Lang.Boolean = false;
var x5VarintEnd as Lang.Number = 0;

// How much of a frame the first notification carried. The transport cuts a
// frame that is bigger than the notification budget, and the pieces that come
// after such a cut are not the missing middle - the bench run of 2026-11-05
// caught them at some two hundred octets into the answer (PROTOCOL_APK.md
// 15.27). They are counted, never glued back onto the frame.
var x5RxHeadSize as Lang.Number = 0;
var x5RxFrag as Lang.Number = 0;
var x5RxFragCount as Lang.Number = 0;








var x5CodesSeen as Lang.Array = [];
var x5CodeCounts as Lang.Array = [];



var notifCode as Lang.Number = 0;
var notifSeq as Lang.Number = 0;
var notifVal1 as Lang.Number = 0;
var notifVal2 as Lang.Number = 0;
var notifVal3 as Lang.Number = 0;
var notifOptTag as Lang.Number = 0;
var notifOptVal as Lang.Number = 0;
var notifOptTag2 as Lang.Number = 0;
var notifOptVal2 as Lang.Number = 0;
var notifOptCount as Lang.Number = 0;
var notifCount as Lang.Number = 0;
var notifHex as Lang.String = "";








var x5SubPhoto as Lang.Number or Null = null;
var x5SubVideo as Lang.Number or Null = null;
var x5ResNow as Lang.Number or Null = null;
var x5FuncMode as Lang.Number or Null = null;

// The mode echo gate, ported from PR #2 (settingMayGo), where the author
// measured what both benches confirm: the camera answers a mode SET with a
// 0x2053 push 0.3 to 0.5 s after the write, and refuses option writes while
// it is still switching modes (error 400). modeReqId is the mode id of the
// last mode this watch wrote, in the entry vocabulary the app itself uses
// ("p3", "v7"), null while nothing is in flight; modeHoldUntil is the
// System.getTimer() ms past which the gate reopens on its own, because the
// gate never closes forever; camModeId is the mode the camera last said it
// is in, from the same 0x2053 fields, null while that reading is not trusted.
var modeReqId as Lang.String or Null = null;
var modeHoldUntil as Lang.Number = 0;
var camModeId as Lang.String or Null = null;

// The invalidation bookkeeping of the option rows. 0x2065 (WATCH_RES) is the
// camera naming the options that moved: its body carries the option ids as a
// repeated field 1, inside the 20-octet window (the survey records ids 30 and
// 40 at octets 17 to 20), while the values sit in the nested map past octet
// 21, in frames declared 26 to 30 that this bond cuts and the camera never
// continues. So this push invalidates a row, it never fills one, and nothing
// re-asks the option: a GET meets the same wall. x5StaleOptions holds one
// entry per named id until a write of the option itself clears it.
var x5StaleOptions as Lang.Array = [];

// The degraded-axis. Entries this camera, named by the name it carries on air,
// was seen refusing a user command: one set per camera name, kept across
// links and across runs. It is fed by failures of user commands - the code
// 400 answer named by its sequence, below, and the application's own write
// pages when they run - never by a probe: the three asks this barrel sends
// at connect (auth, status, card) name a state, never a menu, and that is
// the point of the level chain (no probing frames; the phase-5 test counts
// them). lastCmdSeq is the stamped sequence of the last legacy frame this
// watch sent, which is the sequence a refusal of it answers by.
var x5Degraded as Lang.Array = [];
var lastCmdSeq as Lang.Number = -1;

var x5BatteryLevel as Lang.Number or Null = null;
var x5BatteryPowerType as Lang.Number = 0;
var x5BatteryArrived as Lang.Boolean = false;
var x5BatteryLow as Lang.Boolean = false;

// What the connect-time read of the camera answered (X5_STATE_AT_REST /
// X5_STATE_RECORDING), null while no answer has been read. Deliberately kept
// apart from recState: recState is what the user asked the camera to do, this
// is what the camera says it is doing.
var x5CamState as Lang.Number or Null = null;
var x5StatusAsked as Lang.Boolean = false;
var x5StatusTries as Lang.Number = 0;
// The date the state ask is due at, in the System.getTimer() domain. Not a
// Timer object: see the schedule note above armLinkAlarm.
var x5StatusDue as Lang.Number or Null = null;

// The authorization probe's bookkeeping. authProbeSeq is the stamped sequence
// of the request, used to pick its answer out of the responses, -1 when no
// probe is in flight; authProbeStatus is the answered status (-1 while no
// answer): 0 authorized, 1 unauthorized with an Allow pending on the camera,
// 2 busy, 3..6 a client of each kind already connected, 7 sleeping.
var authProbeStatus as Lang.Number = -1;
var authProbeSeq as Lang.Number = -1;
var authProbeAsked as Lang.Boolean = false;
var authProbeDue as Lang.Number or Null = null;

// The card-state ask: asked once per link, the seq picks its answer out of
// the responses (-1 when nothing is in flight), the same rule as the auth
// probe just above. The state it answers is the one slot the 0x2006 push
// also owns; the sizes are not in either half and stay unknown.
var x5StorageAsked as Lang.Boolean = false;
var x5StorageAskSeq as Lang.Number = -1;
var x5StorageAskDue as Lang.Number or Null = null;

// The 0x2006 storage push, two small flags. The push carries no sizes: the free
// and total byte counts live in option 20 and in the 0x2062 push, past octet 20
// (PROTOCOL_APK.md 15.27), so nothing here holds a free-space figure and the
// app must show that as unknown, not as zero.
var x5StorageState as Lang.Number or Null = null;
var x5StorageMode as Lang.Number or Null = null;

// The answer of a shot this watch fired, followed by the sequence stamped on its
// capture frame - the same shape as the auth probe and the storage ask of this module,
// for the same reason: only the frame carrying that sequence answers that request. The
// three-way reading is the PR's, and it is the reading the 20-octet ceiling allows: a
// 200 whose declared length is above 16 carries the picture path, so a shot happened; a
// bare 200 means the camera took nothing; anything else refused the request. The app arms
// the witness at the send site (armPhotoAck), reads it once (photoResultTaken), and the
// reset at the link edge clears it with the other sequences.
var x5PhotoSeq as Lang.Number = -1;
var x5PhotoResult = null;   // :ok / :noShot / :rejected, consumed by the app

// The same witness for one settings write (an option of the family above, the shutdown
// frame): armWriteAck after the send, the 200 answer names the write accepted, the 0x190
// answer names it refused. The name travels only so the wire line says which write the
// verdict answers for; the verdict itself is read once by settingResultTaken(). This is
// the consumer side the echo gate has been waiting for: the settings page ported from the
// PR writes as it selects, and needs the answer to show ok or refused at the row.
var x5WriteSeq as Lang.Number = -1;
var x5WriteName as Lang.String = "";
var x5WriteResult = null;   // :ok / :rejected, consumed by the app






var wireTrace as Lang.Boolean = false;
var wireEvents as Lang.Number = 0;





var wireRecv as Lang.Number = 0;






var x5Seen as Lang.Number = 0;



const HEX_DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"] as Lang.Array<Lang.String>;

function bytesToHex(data as Lang.ByteArray) as Lang.String {
	var out = "";
	for (var i = 0; i < data.size(); i++) {
		var b = data[i];
		out += HEX_DIGITS[b >> 4];
		out += HEX_DIGITS[b & 0x0f];
	}
	return out;
    }
// ---- the schedule of the link's delayed actions: ONE Timer object ----
// Toybox.Timer states the budget in its own documentation: "The number of
// available timers (default 3) and the minimum time value (default 50 ms)
// depends on the host system. An error will occur if too many timers are set."
// That budget belongs to the process, and a widget pays it once for everything
// the process runs - the glance session and the opened app are one process, one
// pool. The app's own view keeps a repeating timer (the tick that repaints the
// screen), so the five delayed actions of this link - the authorization probe,
// the camera state ask, the card ask, the write retry, the start delay - cannot
// own a Timer object each. This is not a theoretical limit: at the moment the
// notify profile opens, three of them are armed at once (500, 1500 and 2500 ms
// from the same callback), and the view's tick was the fourth - the "Too Many
// Timers" crash a widget run took at RemoteView.onShow, while the same app in
// the older shape, which owned no view timer, sat exactly at the ceiling.
// So a delayed action of the link is booked as a date in the System.getTimer()
// domain, the same domain the mode-echo gate books its hold in (modeHoldUntil),
// and the link owns one Timer object, linkAlarm, armed for the earliest date.
// When it fires, every action whose date has come runs, and the alarm is armed
// again for the earliest date still in the future. Nothing is lost, nothing
// needs a second object.
const ASK_NONE = 0x7FFFFFFF;
const ASK_MIN_MS = 50;

var linkAlarm as Timer.Timer or Null = null;

(:glance)
class BleDevice extends BluetoothLowEnergy.BleDelegate {
 var scanning as Lang.Boolean = false;
 var scanTimeout as Lang.Number = 64;
 var device as BluetoothLowEnergy.Device or Null = null;
 var button as Lang.Number = 0;
 var retryDue as Lang.Number or Null = null;
 var retryKind as Lang.Number = 0;
 var retryCount as Lang.Number = 0;
 var inRetry as Lang.Boolean = false;
 var startDelayDue as Lang.Number or Null = null;
 var pendingStart as Lang.Boolean = false;
 var ucd2Profile as Lang.Dictionary or Null = null;
 var startAckSeen as Lang.Boolean = false;
 var startWaitCount as Lang.Number = 0;
 var startPhase as Lang.Number = 0;



 var applyBursts as Lang.Number = 0;
 var writing as Lang.Boolean = false;
 // The pump's consecutive refused writes (the exception branch of kickQueue
 // only). Cleared when a chunk is issued, and when the bond changes; at
 // WEDGE_REFUSALS_MAX the bond is declared dead.
 var wedgeCount as Lang.Number = 0;

	protected function debug(str as Lang.String) as Void {
		if (DEBUG_TRACE) {
			System.println("[ble] " + str);
		}
	}







	// A byte array is an array of numbers at runtime, but the compiler wants the
	// exact type, so the hex walk takes a ByteArray: every caller hands it one.
	// The constant gate of LOG_FRAMES sits here, at the single site of the hex
	// dump, not at the callers: the send and receive sites keep naming their
	// event, and this answers whether the bytes of the event are printed too
	// (the constant's comment names why the answer is no by default).
	protected function wireBytes(tag as Lang.String, data as Lang.ByteArray) as Void {
		if (!wireTrace || !LOG_FRAMES) {
			return;
		}
		wireEvents = wireEvents + 1;
		var s = "";
		var k = 0;
		while (k < data.size()) {
			var b = data[k] as Lang.Number;
			s = s + HEX_DIGITS[(b >> 4) & 0xf] + HEX_DIGITS[b & 0xf] + " ";
			k = k + 1;
		}
		System.println("[wire] " + tag + " #" + wireEvents.toString() + " n=" + data.size().toString() + " " + s);
	}




	protected function wireLine(tag as Lang.String, extra as Lang.String) as Void {
		if (!wireTrace) {
			return;
		}
		wireEvents = wireEvents + 1;
		System.println("[wire] " + tag + " #" + wireEvents.toString() + " " + extra);
	}

	function initialize() {
		BleDelegate.initialize();
		debug("initialize");
	}











	function ucd2StampSeq(f as Lang.ByteArray, seq as Lang.Number) as Void {
		f[UCD2_SEQ] = seq & 0xff;
		var base = f[12] == ucd2OpStop ? ucd2TrailStopBase : ucd2TrailStartBase;
		var v0 = base[0];
		var v1 = base[1];
		var v2 = base[2];
		var v3 = base[3];
		var bit = 0;
		while (bit < 8) {
			if ((seq & (1 << bit)) != 0) {
				var ix = bit * 4;
				v0 = v0 ^ ucd2SeqXor[ix];
				v1 = v1 ^ ucd2SeqXor[ix + 1];
				v2 = v2 ^ ucd2SeqXor[ix + 2];
				v3 = v3 ^ ucd2SeqXor[ix + 3];
			}
			bit = bit + 1;
		}
		var at = f.size() - UCD2_TAIL;
		f[at] = v0;
		f[at + 1] = v1;
		f[at + 2] = v2;
		f[at + 3] = v3;
	}




	function ucd2Frame(op as Lang.Number) as Lang.ByteArray {
		var f = new [25]b;
		f[0] = 0x55;
		f[1] = 0x43;
		f[2] = 0x44;
		f[3] = 0x32;
		f[4] = 0x01;
		f[5] = UCD2_FLAGS;
		f[6] = ucd2TypeFile;
		f[7] = 0;
		f[8] = 9;
		f[9] = 0;
		f[10] = 0;
		f[11] = 0;
		f[12] = op & 0xff;
		f[13] = (op >> 8) & 0xff;
		f[14] = ucd2FileMarker;
		f[15] = ucd2ReqId & 0xff;
		f[16] = (ucd2ReqId >> 8) & 0xff;
		f[17] = ucd2FileFlags[0];
		f[18] = ucd2FileFlags[1];
		f[19] = ucd2FileFlags[2];
		f[20] = ucd2FileFlags[3];
		ucd2StampSeq(f, 1);
		return f;
	}


	function ucd2Send(trigger as Lang.ByteArray) as Void {
		var kind = 0;
		var op = ucd2OpStart;
		if (trigger == cmdStopRec) {
			kind = retryKindStop;
			op = ucd2OpStop;
			cancelPendingStart();
		} else if (trigger == cmdStartRec) {
			kind = retryKindStart;
		}
		if (kind == 0) {
			return;
		}
		// Axis of the ceiling: the UCD2 leg is asked the same question as the
		// legacy one, so a forced X6 family on a camera of another model is bounded
		// the same way and answers with the same line (criterion 14).
		if (hookCeiling()) {
			return;
		}
		var frame = ucd2Frame(op);
		txUcd2 = true;
		ucd2TxKind = kind;
		transmit(frame);
		txUcd2 = false;
	}






	function ucd2IsUcd2(value as Lang.ByteArray) as Lang.Boolean {
		if (value.size() < UCD2_HDR) {
			return false;
		}
		return (value[0] & 0xff) == 0x55 and (value[1] & 0xff) == 0x43 and
			(value[2] & 0xff) == 0x44 and (value[3] & 0xff) == 0x32;
	}








	function ucd2IsAck(value as Lang.ByteArray) as Lang.Boolean {
		if (value.size() < 17) {
			return false;
		}
		if (!ucd2IsUcd2(value)) {
			return false;
		}
		if ((value[12] & 0xff) != 0xc8 or (value[13] & 0xff) != 0x00) {
			return false;
		}
		var reqid = (value[15] & 0xff) | ((value[16] & 0xff) << 8);
		return reqid == ucd2ReqId;
	}




	function ucd2RxFeed(value as Lang.ByteArray) as Lang.Boolean {
		if (ucd2IsUcd2(value)) {

			var declared = (value[UCD2_LEN] & 0xff) | ((value[UCD2_LEN + 1] & 0xff) << 8) |
				((value[UCD2_LEN + 2] & 0xff) << 16);
			if (declared > ucd2RxMaxBody) {

				ucd2RxBuf = null;
				ucd2RxWant = 0;
				return false;
			}
			ucd2RxWant = 16 + declared;
			ucd2RxBuf = ucd2Cat(null, value);
		} else if (ucd2RxBuf == null) {
			return false;
		} else {
			ucd2RxBuf = ucd2Cat(ucd2RxBuf, value);
		}
		var buf = ucd2RxBuf;
		if (buf == null) {
			return false;
		}
		if (buf.size() > ucd2RxWant) {
			ucd2RxBuf = buf.slice(0, ucd2RxWant);
		}
		buf = ucd2RxBuf;
		if (buf == null or buf.size() < ucd2RxWant) {
			return false;
		}
		ucd2RxBuf = null;
		ucd2RxWant = 0;
		return true;
	}


	function ucd2Cat(a as Lang.ByteArray or Null, b as Lang.ByteArray) as Lang.ByteArray {
		var an = 0;
		if (a != null) {
			an = a.size();
		}
		var bn = b.size();
		var out = new [an + bn]b;
		var i;
		if (a != null) {
			for (i = 0; i < an; i++) {
				out[i] = a[i];
			}
		}
		for (i = 0; i < bn; i++) {
			out[an + i] = b[i];
		}
		return out;
	}















	function x5IsFrame(value as Lang.ByteArray) as Lang.Boolean {

		return value.size() >= 10 && value[4] == 0x04 && value[5] == 0x00 && value[6] == 0x00;
	}



	function x5IsNotif(value as Lang.ByteArray) as Lang.Boolean {
		return x5IsFrame(value) && (value[8] & 0xff) >= 0x20;
	}

	function x5RxFeed(value as Lang.ByteArray) as Lang.Boolean {


		if (x5IsFrame(value)) {
			var declared = (value[0] & 0xff) |
			    (value[1] & 0xff) << 8 |
			    (value[2] & 0xff) << 16 |
			    (value[3] & 0xff) << 24;
			if (declared > x5NotifMaxBody) {


				x5RxBuf = null;
				x5RxWant = 0;
				// The flag follows the frame it was set for: leaving the old one
				// set would make the swallow below answer for frames that were
				// never the notification's.
				x5RxWasNotif = false;
				return false;
			}
			x5RxWant = declared;
			x5RxWasNotif = x5IsNotif(value);
			x5RxNewFrame = true;
			x5RxHeadSize = value.size();
			x5RxBuf = ucd2Cat(null, value);
		} else if (x5RxBuf == null) {
			return false;
		} else if (value.size() == 7 && value[0] == 0x07 && value[4] == 0x05) {


			// The beat closes the frame it arrives in: what crossed is kept,
			// the rest is abandoned. The flag goes with the frame.

			x5RxBuf = null;
			x5RxWant = 0;
			x5RxWasNotif = false;
			return false;
		} else {



			x5RxNewFrame = false;
			// A notification with no envelope. On this link a frame bigger than the
			// budget is cut, never continued: the pieces that follow a cut frame come
			// from the middle of the answer, not from where the cut left it, and they
			// carry no option boundary (PROTOCOL_APK.md 15.27, three runs and the
			// S12-S15 controls of 15.14). Gluing them would let the decoder read the
			// camera's own option text as varint fields and invent a battery level or
			// a free-space figure out of ASCII. So only what could still be this
			// frame's first notification is taken; the rest is counted. A link with a
			// bigger budget is not affected: its first notification is bigger, and a
			// real continuation of a split frame stays inside that size.
			var head = x5RxHeadSize;
			var have = x5RxBuf.size();
			if (have >= head) {
				x5RxFrag = x5RxFrag + value.size();
				x5RxFragCount = x5RxFragCount + 1;
			} else if (have + value.size() <= head) {
				x5RxBuf = ucd2Cat(x5RxBuf, value);
			} else {
				x5RxBuf = ucd2Cat(x5RxBuf, value.slice(0, head - have));
				x5RxFrag = x5RxFrag + (have + value.size() - head);
				x5RxFragCount = x5RxFragCount + 1;
			}
		}
		var buf = x5RxBuf;
		if (buf == null) {
			return false;
		}
		if (buf.size() > x5RxWant) {


			x5RxBuf = buf.slice(0, x5RxWant);
			buf = x5RxBuf;
		}



		x5RxDeclared = x5RxWant;
		x5RxArrived = buf.size();
		x5RxTruncated = buf.size() < x5RxWant;
		x5RxLast = buf;
		if (x5RxTruncated) {


			return true;
		}
		x5RxBuf = null;
		return true;
	}





	function x5Varint(buf as Lang.ByteArray, i as Lang.Number, n as Lang.Number) as Lang.Number or Null {
		var value = 0;
		var shift = 0;
		while (i < n) {
			var o = buf[i] & 0xff;
			value += (o & 0x7f)<< shift;
			i++;
			if ((o & 0x80) == 0) {
				x5VarintEnd = i;
				return value;
			}
			shift += 7;
			if (shift > 28) {
				x5VarintEnd = i;
				return null;
			}
		}
		x5VarintEnd = n;
		return null;
	}







	function x5DecodeNotif() as Void {
		var buf = x5RxLast;



		if (buf == null || buf.size() < 16) {
			return;
		}
		notifCode = (buf[7] & 0xff) | ((buf[8] & 0xff) << 8);
		notifSeq = (buf[10] & 0xff) | ((buf[11] & 0xff) << 8) | ((buf[12] & 0xff) << 16);
		notifHex = bytesToHex(buf);
		notifVal1 = 0;
		notifVal2 = 0;
		notifVal3 = 0;
		notifOptTag = 0;
		notifOptVal = 0;
		notifOptTag2 = 0;
		notifOptVal2 = 0;
		notifOptCount = 0;

		// Battery reads enter at this site because every whole frame passes
		// through it, the 0x2003 push as much as the code 200 answer to a GET
		// (that answer is not a notification, its high code byte is 00, so
		// x5ApplyNotif never sees one). The recording runs first so a push
		// still moves the seen-map and the per-code count before the return;
		// the walk below reads the flat option list only and must not chew a
		// battery body: its nested block would be met as an unknown wire and
		// break the walk, which is how the old battery attempt lost the value.
		if (notifCode == 200) {
			var optLevel = x5ParseOptionsBattery(buf);
			if (optLevel != null) {
				x5BatteryLevel = optLevel;
				x5BatteryArrived = true;
				wireLine("battery", optLevel.toString() + "% from the code 200 reply");
			}
		}
		if (notifCode == X5_BATTERY_LOW_NOTIF) {
			x5BatteryLow = true;
			x5RecordNotif();
			wireLine("battery", "low battery alarm (0x2004)");
			return;
		}
		if (notifCode == X5_STORAGE_NOTIF) {
			// 8198 STORAGE_UPDATE. Its frame is 20 octets, so it is one of the few
			// pushes that cross this link whole - and what crosses names no sizes:
			// two small flags, taken here as they come. The free and total byte
			// counts of the same storage sit in option 20 and in the 0x2062 push,
			// past octet 20, and no run has ever brought them over (15.27).
			var bs = buf.size();
			var st = x5ParseVarintField(buf, 16, bs, 1);
			var md = x5ParseVarintField(buf, 16, bs, 2);
			if (st != null) {
				x5StorageState = st;
			}
			if (md != null) {
				x5StorageMode = md;
			}
			x5RecordNotif();
			wireLine("storage", "0x2006 f1=" + showValue(st) + " f2=" + showValue(md) +
				" (no sizes in this push; the sizes stay unknown)");
			return;
		}
		if (notifCode == X5_BATTERY_NOTIF) {
			x5RecordNotif();
			var power = x5ParseBatteryPower(buf);
			var level = x5ParseBatteryLevel(buf);
			if (level != null) {
				x5BatteryLevel = level;
				x5BatteryArrived = true;
			}
			// The power source stands on its own: at the watch ceiling it is
			// the half of the push that crosses, and charger in/out is a real
			// datum even while the level sits past the cut.
			if (power != null) {
				x5BatteryPowerType = power;
				x5BatteryArrived = true;
				// The 0x2004 low-battery alarm goes stale the moment the
				// camera says it runs on external power (power_type 1): the
				// rule the PR's reader applies on its side too. The alarm
				// stays a fact of the wire log; the standing flag clears.
				if (power == 1 && x5BatteryLow) {
					x5BatteryLow = false;
					wireLine("battery", "0x2004 alarm cleared: the camera is on external power");
				}
			}
			if (level != null) {
				wireLine("battery", level.toString() + "% power_type=" +
					power.toString());
			} else if (power != null) {
				wireLine("battery", "power_type=" + power.toString() +
					" off the cut push, the level past the cut stays unknown");
			} else {
				wireLine("battery", "0x2003 arrived, nothing readable in its body");
			}
			return;
		}
		if (notifCode == X5_OPTIONS_NOTIF) {
			// WATCH_RES, answered here rather than by the walk below, and not
			// returned to: the ids are read from the raw window, the values are
			// not asked for. What crosses of this frame is the repeated field 1
			// of its body, the list of option ids (the survey names [30, 40] at
			// octets 17 to 20); the map that would carry their values sits past
			// octet 21 and no run on either bench has ever brought it over. The
			// rows the camera names become untrusted here, and the app's cache
			// reads that through optionIsStale; the reading of a value comes
			// only from a write this watch made and the camera confirmed.
			x5RecordNotif();
			var named = x5CollectOptionIds(buf);
			wireLine("options", "0x2065 invalidated options=" + named + " (values past the cut, never re-asked)");
			return;
		}

		var n = buf.size();
		var i = 16;
		while (i < n) {
			var tag = x5Varint(buf, i, n);
			if (tag == null) {
				break;
			}
			i = x5VarintEnd;
			var field = tag >> 3;
			var wire = tag & 7;
			if (wire == 0) {
				var v = x5Varint(buf, i, n);
				if (v == null) {
					break;
				}
				i = x5VarintEnd;
				if (field == x5PhotoSubModeNotif) {
					notifVal1 = v;
				} else if (field == x5VideoSubModeNotif) {
					notifVal2 = v;
				} else if (field == 3) {
					notifVal3 = v;
				}
			} else if (wire == 2) {
				var len = x5Varint(buf, i, n);
				if (len == null) {
					break;
				}
				i = x5VarintEnd;
				if (i + len <= n) {


					var j = i;
					var k = i + len;
					while (j < k) {
						var inner = x5Varint(buf, j, k);
						if (inner == null) {
							break;
						}
						j = x5VarintEnd;
						if ((inner & 7) != 0) {
							break;
						}
						var iv = x5Varint(buf, j, k);
						if (iv == null) {
							break;
						}
						j = x5VarintEnd;
						if (notifOptCount == 0) {
							notifOptTag = inner >> 3;
							notifOptVal = iv;
						} else if (notifOptCount == 1) {
							notifOptTag2 = inner >> 3;
							notifOptVal2 = iv;
						}
						notifOptCount++;
					}
				}
				i += len;
			} else {


				break;
			}
		}






		x5RecordNotif();
	}

	// The observer's bookkeeping, once per notification frame: the count, the
	// per-code tally, the seen-map. Pulled out of the decode so the battery
	// branches, which answer before the walk, still move it.
	function x5RecordNotif() as Void {
		if (x5RxNewFrame && x5RxWasNotif) {
			notifCount++;
			// S-25 (CdC item 97): the content of a notification, read once per notification
			// received, at the site that decodes it. The observer of the delegate keeps one slot
			// per field, so a window answers for the LAST notification only and cannot name which
			// echo a set of fields belongs to (note 26, note 27). The print sits before the
			// branch that counts below, the way it always did.
			// Item 9 of the integration, the hygiene of the log: this is a line of per-frame
			// content - one per notification, with the hex of its body - and it printed
			// unconditionally, the way it was written before any line of events existed.
			// LOG_FRAMES answers now, and with the constant at its default the decoded fields
			// stay datum of the peek* slots while the watch log keeps the events that NAME
			// these fields (the battery, storage, capture and auth lines of wireLine).
			if (wireTrace && LOG_FRAMES) {
				System.println("[nf] code=" + notifCode.toString() + " f1=" + notifVal1.toString() + " f2=" + notifVal2.toString() + " f3=" + notifVal3.toString() + " opts=" + notifOptCount.toString() + " o1=" + notifOptTag.toString() + ":" + notifOptVal.toString() + " o2=" + notifOptTag2.toString() + ":" + notifOptVal2.toString() + " hex=" + notifHex);
			}
			System.println("[nf] code=" + notifCode.toString() + " f1=" + notifVal1.toString() + " f2=" + notifVal2.toString() + " f3=" + notifVal3.toString() + " opts=" + notifOptCount.toString() + " o1=" + notifOptTag.toString() + ":" + notifOptVal.toString() + " o2=" + notifOptTag2.toString() + ":" + notifOptVal2.toString() + " hex=" + notifHex);
			var ix = x5CodeIndex(notifCode);
			if (ix < 0) {
				x5CodesSeen.add(notifCode);
				x5CodeCounts.add(1);
			} else {
				x5CodeCounts[ix] = x5CodeCounts[ix] + 1;
			}
			x5Seen = x5Seen | x5NotifBit(notifCode);
		}
	}






	// A named option id joins the stale list once; the list answers the app's
	// cache, which decides what an untrusted row means on screen. The scan is
	// explicit on purpose: the array family is where the SDK API is the most
	// treacherous (the note of tools/mc_check.py), and an index walk answers
	// on every API level this project targets.
	function x5StaleIndex(opt as Lang.Number) as Lang.Number {
		var i = 0;
		while (i < x5StaleOptions.size()) {
			if (x5StaleOptions[i] == opt) {
				return i;
			}
			i++;
		}
		return -1;
	}

	function x5MarkOptionStale(opt as Lang.Number) as Void {
		if (x5StaleIndex(opt) < 0) {
			x5StaleOptions.add(opt);
		}
	}

	// The option ids of a WATCH_RES body: the repeated varint field 1 from
	// octet 16 up to wherever the bond cut the frame. The walk's shape, kept
	// separate on purpose - it stops at the first nested field (the value map,
	// whose ids are not the window's) and at the cut, and it says what it
	// named, for the wire line.
	function x5CollectOptionIds(buf as Lang.ByteArray) as Lang.String {
		var found = "";
		var n = buf.size();
		var i = 16;
		while (i < n) {
			var tag = x5Varint(buf, i, n);
			if (tag == null) {
				break;
			}
			i = x5VarintEnd;
			var field = tag >> 3;
			var wire = tag & 7;
			if (wire != 0) {
				break;
			}
			var v = x5Varint(buf, i, n);
			if (v == null) {
				break;
			}
			i = x5VarintEnd;
			if (field == x5PhotoSubModeNotif) {
				x5MarkOptionStale(v);
				if (found.length() > 0) {
					found += ",";
				}
				found += v.toString();
			}
		}
		return found;
	}

	// The mode id named by a 0x2053 pair: the half that is not 100 names the
	// mode, "p" for the photo half, "v" for the video half — the same names
	// the app's menu entries carry. Two halves at 100, or both set, answer
	// null: neither has ever been seen on either bench, one half is always
	// the none flag (docs/x5-protocol.md §3.1).
	function x5ModeIdOf(photo as Lang.Number, video as Lang.Number) as Lang.String or Null {
		if (photo != x5SubModeNotApplicable && video == x5SubModeNotApplicable) {
			return "p" + photo.toString();
		}
		if (video != x5SubModeNotApplicable && photo == x5SubModeNotApplicable) {
			return "v" + video.toString();
		}
		return null;
	}

	function x5ApplyNotif() as Void {
		if (notifCode == X5_AUTH_RESULT_NOTIF) {
			// AUTHORIZATION_RESULT: the camera says the user answered its Allow
			// prompt (field 1 = 0, the only answer ever observed on either bench).
			// The gate of this link is open now; say so once in the wire log.
			if (authProbeStatus != 0) {
				authProbeStatus = 0;
				wireLine("auth probe", "open now, 0x2011 from the user f1=" + notifVal1.toString());
			}
			return;
		}



		if (notifCode == X5_SUB_MODE_NOTIF) {





			if (notifVal1 == x5SubModeNotApplicable) {
				x5SubPhoto = null;
			} else {
				x5SubPhoto = notifVal1;
			}
			if (notifVal2 == x5SubModeNotApplicable) {
				x5SubVideo = null;
			} else {
				x5SubVideo = notifVal2;
			}
			// The mode echo gate (ported from PR #2, measured on both benches).
			// The id of this push names the mode the camera says it is in; the
			// half that is 100 says "not this family". The reading is recorded
			// first, the decision of what to do with it belongs to the app.
			var id = x5ModeIdOf(notifVal1, notifVal2);
			if (id != null) {
				camModeId = id;
			}
			if (id != null && modeReqId != null && id.equals(modeReqId)) {
				// The echo of this watch's own mode write: the gate opens here,
				// the hold runs out by itself.
				modeReqId = null;
				System.println("[mode] echo confirmed id=" + id);
			} else if (modeReqId != null && System.getTimer() < modeHoldUntil) {
				// An echo that is not the one in flight while a request is in
				// flight: not trusted, the PR's guard, kept verbatim in purpose.
				// A late echo of the previous mode would otherwise move the app
				// off the mode the user just asked for.
				System.println("[mode] stale echo ignored id=" + (id == null ? "?" : id) + " waiting=" + modeReqId);
			}
			return;
		}
		if (notifCode == X5_OPTIONS_NOTIF) {
			// The reads that used to sit here (field 3 read as a family, the
			// option 31 value out of the nested map) answer on bytes this bond
			// never delivers - every 0x2065 is declared 26 to 30 and cut at
			// octet 20 - and the frame site now answers the push before the
			// walk ever sees it. The invalidation is the whole reading;
			// peekResNow and peekFuncMode still answer, and on this link their
			// null is the truth of the wall.
			return;
		}
		if (notifCode != X5_CAPTURE_STATUS_NOTIF && notifCode != X5_RECORD_STATE_NOTIF) {
			return;
		}
		// The capture-state push confirms, it never re-starts. The PR's author
		// found it on his own camera and the bench agrees: the camera pushes
		// 0x2010 again while it finalizes a file, and read here as a fresh
		// start that push moved startRecTime - the on-screen recording clock
		// began again in the middle of a recording. So the push only moves the
		// machine on an edge of the watch's own state, the same discipline
		// onUcd2Frame keeps for this on the ucd2 envelope: state>0 from
		// anything but stateStartRec (the app's pending start - it writes
		// stateStarting at the press, InputDelegate - or the camera's own
		// button from rest, which both benches proved arrives unprompted),
		// never while the watch already shows recording. A repeat push
		// answers with a wire line and leaves the clock put.
		if (notifVal1 > 0) {
			if (recState == stateStartRec) {
				wireLine("capture", "push state=" + notifVal1.toString() + " while already recording, the clock stays put");
			} else if (recState == stateStopping) {
				// A state>0 push while a stop is pending is the same finalization
				// push the comment above names: read as a start it would undo the
				// user's stop and move the clock again, exactly the fault PR #2's
				// vector captureStatusPushDoesNotRestartRecording met on its bench
				// and the one this branch was written against. The stop stands; the
				// state-0 answer below is what confirms it, and the stop's own
				// retry path still owns it if that answer never comes.
				wireLine("capture", "push state=" + notifVal1.toString() + " while a stop is pending, the stop stands");
			} else {
				cancelRetry();
				cancelPendingStart();
				mMessage = "Shooting";
				recState = stateStartRec;
				startRecTime = Time.now();
			}
		} else {
			// State 0 is idempotent at rest (the message and the burst count
			// reset to what they already are), and while a stop is pending -
			// the app's stateStopping from the press - this is exactly the
			// confirmation of it, which is what recState becomes anyway.
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;
			recState = stateStopRec;
		}
	}

	// The response side of the legacy machine, moved out of the raw scan the old
	// responseSig block used to run on every notification. It sees the ASSEMBLED
	// frame, so it answers whether the camera sent the response in one
	// notification or spread it over continuations, and it only ever runs for a
	// frame x5RxFeed has completed or delivered as cut. The low-byte trap the
	// PR met stays closed by construction here: that camera re-pushed 0x2010
	// while finalizing a file, the old raw scan read octet 7 alone as the
	// command - and 0x2010 is 0x10 at that octet - so the capture push looked
	// like a legacy start and moved the clock again. Here the code is read as
	// 16 bits, and x5IsNotif sends every frame with octet 8 at 0x20 or above
	// to the notification side, so this function never sees one; keep both if
	// this region is ever edited again. The recording report
	// (code 0x40, and 0x10 on older firmware) names start and stop with the flag
	// at octet 17; busy speaks for itself; the command error ends the start
	// sequence; and the ACK of the start sequence is what lets fireStart go.
	function x5ApplyResponse(buf as Lang.ByteArray) as Void {
		// The floor is a whole frame header, 16 octets, and not 18: a code-200
		// answer with no body is a frame of exactly 16 (4 804 of them in the
		// corpus, PROTOCOL_APK 15.27), and that short frame is what carries two
		// verdicts this function must answer - the shot's :noShot (the capture
		// command's empty ack, the PR's three-way reading) and the start
		// sequence's ACK. The branches that read past octet 17 say so at their
		// own condition; the rest read only the header, which this floor names.
		if (buf == null || buf.size() < 16) {
			return;
		}
		var code = (buf[7] & 0xff) | ((buf[8] & 0xff) << 8);
		var isRecReport = (code == recReportCode || code == recReportCodeLegacy) && buf.size() >= 18;
		if (isRecReport && buf[17] > 0x00) {
			cancelRetry();
			cancelPendingStart();
			mMessage = "Shooting";
			recState = stateStartRec;
			startRecTime = Time.now();
		} else if (isRecReport && buf[17] == 0x00) {
			cancelRetry();
			cancelPendingStart();
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;
			recState = stateStopRec;
		} else if (code == stateBusy) {
			mMessage = "Busy...";
		} else if (buf[0] == stateCmdErr) {
			cancelRetry();
			cancelPendingStart();
			mMessage = currentLabel + "\n" + startMessage;
			recState = stateStopRec;
		} else if (authProbeSeq >= 0 && buf[10] == authProbeSeq && code < 0x1000) {
			// The answer carrying the probe's sequence is the authorization
			// answer, whatever code it echoes. This runs ahead of the ACK
			// branch on purpose: the same code 200 shape would otherwise be
			// parsed as a capture-state answer to command 15.
			applyAuthProbe(buf);
		} else if (x5StorageAskSeq >= 0 && buf[10] == x5StorageAskSeq && code < 0x1000) {
			// The card ask's answer goes by its sequence, like the auth
			// answer, and for the same reason runs ahead of the ACK branch:
			// its code 200 shape would else be met as a capture-state answer.
			applyStorageAsk(buf);
		} else if (x5PhotoSeq >= 0 && buf[10] == x5PhotoSeq && code < 0x1000) {
			// The shot's answer runs ahead of the refusal branch on purpose: when the
			// camera refuses a capture, that refusal is the shot's verdict, not a mode
			// entry to mark degraded - a capture never sets modeReqId, and a degraded
			// mark read from one would name the mode the menu last held. The declared
			// length is read from the header, which the ceiling never cuts, so a short
			// arrival classifies the same as a whole one (the PR's three-way reading).
			var photoDeclared = (buf[0] & 0xff) | ((buf[1] & 0xff) << 8);
			var photoVerdict = :rejected;
			if (code == ACK_CODE && photoDeclared > 16) { photoVerdict = :ok; }
			else if (code == ACK_CODE) { photoVerdict = :noShot; }
			wireLine("photo", "ack code=" + code.toString() + " declared=" + photoDeclared.toString() + " shot=" + (photoVerdict == :rejected ? "refused" : (photoVerdict == :ok ? "taken" : "none")));
			if (code == ACK_CODE) {
				// The answer of a capture command carries the state byte at octet 19,
				// the same byte the state read parses there (x5ParseCaptureState): a
				// timed photo still running reads as a start, which is the clock of
				// stateStartRec this frame should begin. A shot answer without that
				// shape answers null at that site and moves nothing.
				applyCamState(buf);
			}
			x5PhotoResult = photoVerdict;
			x5PhotoSeq = -1;
		} else if (x5WriteSeq >= 0 && buf[10] == x5WriteSeq && (code == ACK_CODE || code == 0x190)) {
			// A settings write's answer, ahead of the refusal branch for the same
			// reason as the shot above: this 0x190 belongs to a write the menu never
			// named as a mode, and the row of the settings page is where its refusal
			// must answer - not a degraded mark on an unrelated entry.
			x5WriteResult = (code == ACK_CODE) ? :ok : :rejected;
			wireLine("setting", x5WriteName + " -> " + (code == ACK_CODE ? "ok" : "refused 400"));
			x5WriteSeq = -1;
			x5WriteName = "";
		} else if (code == 0x190 && lastCmdSeq >= 0 && buf[10] == lastCmdSeq) {
			// The camera refused the write this watch just made, named by its
			// sequence (0x190 = 400, the same shape the PR matched with its
			// setSeq). When that write was a mode write, the id its page named
			// before the send - modeReqId, in the app's entry vocabulary of
			// the echo gate - is exactly the entry this camera is known not to
			// take: the entry takes the degraded mark, kept by camera name
			// across links and runs, and the write cycle closes (the hold of
			// the gate runs out by itself, as ever). A refusal whose writer
			// named no id gets the line and nothing else: what a refusal was
			// about is not guessed here.
			var refused = modeReqId;
			var refusedSeq = lastCmdSeq;
			lastCmdSeq = -1;
			if (refused != null) {
				modeReqId = null;
				noteDegraded(refused);
				wireLine("write refused", "400 on seq " + refusedSeq.toString() + " entry=" + refused + " marked degraded");
			} else {
				wireLine("write refused", "400 on seq " + refusedSeq.toString() + " no id known, nothing marked");
			}
		} else if (code == ACK_CODE) {
			// One frame, two jobs. The code-200 answer to command 15 is also the ACK
			// the start sequence waits for, so the state read runs first and does not
			// consume the ACK: both are taken from the same assembled frame.
			applyCamState(buf);
			if (pendingStart && startPhase == 1 && !startAckSeen) {
				startAckSeen = true;
				fireStart();
			}
		}
	}

	// The capture-state answer of command 15, read where it lands. Shape first,
	// then the one byte: the frame declares 24 and arrives as 20, so the state is
	// the last octet that survives the cut, at index 19. An empty code-200 ack, an
	// 18-octet id echo or any other answer does not match and gives null.
	function x5ParseCaptureState(buf as Lang.ByteArray) as Lang.Number or Null {
		if (buf == null || buf.size() < 20) {
			return null;
		}
		if (buf[16] != 0x0a || buf[17] != 0x06 || buf[18] != 0x08) {
			return null;
		}
		return buf[19] & 0xff;
	}

	// What the state read is for. The value is kept for the app beside recState,
	// which is the delegate's own idea of what it asked the camera to do; the two
	// only disagree when the camera was already recording before the watch connected.
	// Moving recState is what starts the on-screen clock, and it is done only while
	// no start or stop sequence is in flight. The seconds field of the answer sits
	// past the cut, so a recording found at connect is timed from the connect.
	function applyCamState(buf as Lang.ByteArray) as Void {
		var st = x5ParseCaptureState(buf);
		if (st == null) {
			return;
		}
		x5CamState = st;
		x5StatusAsked = false;
		x5StatusTries = 0;
		cancelStatusTimer();
		wireLine("cam state", "state=" + st.toString() + " " +
			(st == X5_STATE_RECORDING ? "recording" : "at rest") +
			" arrived=" + x5RxArrived.toString() + " of " + x5RxDeclared.toString());
		if (st == X5_STATE_RECORDING && !pendingStart && recState != stateStartRec) {
			recState = stateStartRec;
			startRecTime = Time.now();
			mMessage = "Shooting";
		} else if (st == X5_STATE_AT_REST && !pendingStart && recState == stateStartRec) {
			recState = stateStopRec;
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;
		}
		WatchUi.requestUpdate();
	}

	// Asks the camera what it is doing. Command 15 with an empty body, which is
	// cmdApply: the one request whose answer puts a state byte inside the
	// notification ceiling (see X5_GET_CAPTURE_STATUS above). The answer also
	// carries the elapsed seconds, the battery level and the free bytes, and all
	// three sit past the cut - they stay unknown, which is why this asks for the
	// state and nothing pretends to know the rest.
	function askCamStatus() as Void {
		if (x5StatusAsked || device == null) {
			return;
		}
		x5StatusAsked = true;
		x5StatusTries = x5StatusTries + 1;
		transmit(cmdApply);
		wireLine("cam state", "asked command 15, try " + x5StatusTries.toString());
		if (x5StatusTries <= STATUS_RETRY_MAX) {
			scheduleStatusTimer(STATUS_RETRY_MS);
		}
	}

	// The one alarm of the link, armed for the earliest date still in the
	// future. Every schedule* and cancel* function below ends by calling this,
	// and so does the pump: the alarm is never armed for anything but the
	// nearest date, which is what lets five delayed actions live in one object.
	function armLinkAlarm() as Void {
		var next = earliestAskDue();
		if (linkAlarm == null) {
			if (next == ASK_NONE) {
				return;
			}
			linkAlarm = new Timer.Timer();
		}
		linkAlarm.stop();
		if (next == ASK_NONE) {
			return;
		}
		var waitms = next - System.getTimer();
		if (waitms < ASK_MIN_MS) {
			// The date came due while this was being written. The host's own
			// minimum (50 ms, the same sentence of the Timer documentation) is
			// the shortest honest hop: the next callback reaches it.
			waitms = ASK_MIN_MS;
		}
		linkAlarm.start(method(:onLinkAlarm), waitms, false);
	}

	// The nearest date of the five, ASK_NONE when none is booked. Written as a
	// chain of pairwise choices so every local stays a plain Number - the
	// nullable-number locals this file otherwise uses are module vars, and the
	// type check of the app is at its default level, not off.
	function earliestAskDue() as Lang.Number {
		var next = ASK_NONE;
		if (authProbeDue != null && authProbeDue < next) { next = authProbeDue; }
		if (x5StatusDue != null && x5StatusDue < next) { next = x5StatusDue; }
		if (x5StorageAskDue != null && x5StorageAskDue < next) { next = x5StorageAskDue; }
		if (retryDue != null && retryDue < next) { next = retryDue; }
		if (startDelayDue != null && startDelayDue < next) { next = startDelayDue; }
		return next;
	}

	// The single callback: run every action whose date has come, in the order
	// the delays were armed (the authorization probe, then the state ask, then
	// the card ask, then the write retry, then the start delay), and arm the
	// alarm again for whatever is left. An action that re-books itself, like
	// the state ask's retry or the start delay's next wait, is reached by that
	// re-arm, never twice in one pass.
	function onLinkAlarm() as Void {
		var now = System.getTimer();
		if (authProbeDue != null && now >= authProbeDue) {
			authProbeDue = null;
			onAuthProbe();
		}
		if (x5StatusDue != null && now >= x5StatusDue) {
			x5StatusDue = null;
			onStatusAsk();
		}
		if (x5StorageAskDue != null && now >= x5StorageAskDue) {
			x5StorageAskDue = null;
			onStorageAsk();
		}
		if (retryDue != null && now >= retryDue) {
			retryDue = null;
			onRetry();
		}
		if (startDelayDue != null && now >= startDelayDue) {
			startDelayDue = null;
			onStartDelay();
		}
		armLinkAlarm();
	}

	// The three first asks of a link, armed at the one place this link is
	// demonstrably able to answer: the walk in discoverServices has just found
	// the LBS characteristic, and kickQueue writes from that same line. Why
	// this site and not the profile-register callback: the bench of 12 nov.
	// (real X5 fw 1.13.21, PC Bluetooth, trace lifted by int-x5-build\benchbuild.ps1)
	// connected, started a recording and stopped one - and the callback printed
	// nothing, in a log that printed every other wire event. The connection here
	// is manual - pairDevice, then discoverServices walks the services itself -
	// so the profile registered at open is never negotiated and the callback
	// never runs. An ask armed there was an ask never asked. The guards inside
	// each schedule* keep a repeat call of this one harmless.
	function armLinkAsks() as Void {
		scheduleAuthProbe();
		scheduleCamStatusAsk();
		scheduleStorageAsk();
	}

	// First ask after the link can answer: the camera answers an ask 0.6 to
	// 3.9 s later on this link, and an ask written before the descriptor settles
	// is answered into a closed window.
	function scheduleCamStatusAsk() as Void {
		if (x5StatusDue != null || x5StatusAsked) {
			return;
		}
		x5StatusTries = 0;
		scheduleStatusTimer(STATUS_ASK_MS);
	}

	function scheduleStatusTimer(ms as Lang.Number) as Void {
		cancelStatusTimer();
		x5StatusDue = System.getTimer() + ms;
		armLinkAlarm();
	}

	function onStatusAsk() as Void {
		x5StatusDue = null;
		askCamStatus();
	}

	function cancelStatusTimer() as Void {
		x5StatusDue = null;
		armLinkAlarm();
	}

	// The authorization handshake, asked once per link, 500 ms after the link
	// became writable and so before the status ask at 1500 ms: the camera only
	// pushes to an authorized client, so the ask has to open the gate in time
	// for the status answer. The frame is the phone app's CHECK_AUTHORIZATION
	// (39), field 1 = client id, field 2 = 17 = WATCH_GARMINOS, the shape the
	// camera answers. This is X5 legacy framing only: a UCD2 link is a
	// different protocol and stays untouched.
	function scheduleAuthProbe() as Void {
		if (authProbeDue != null || authProbeAsked || ucd2Armed) {
			return;
		}
		authProbeDue = System.getTimer() + AUTH_PROBE_MS;
		armLinkAlarm();
	}

	function onAuthProbe() as Void {
		authProbeDue = null;
		askAuthProbe();
	}

	function askAuthProbe() as Void {
		if (authProbeAsked || device == null || ucd2Armed) {
			return;
		}
		authProbeAsked = true;
		var id = "garmin-remote";
		var uid = System.getDeviceSettings().uniqueIdentifier;
		if (uid != null && uid.length() >= 12) {
			id = uid.substring(0, 12);
		}
		var f = [0, 0, 0, 0, 0x4, 0, 0, AUTH_CMD, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x0a, id.length()]b;
		f.addAll(id.toUtf8Array());
		f.addAll([0x10, 0x11]b);
		f[0] = f.size();
		transmit(f);
		authProbeSeq = SeqNo;
		wireLine("auth probe", "asked cmd=" + AUTH_CMD.toString() + " id=" + id + " seq=" + authProbeSeq.toString());
	}

	// CheckAuthorizationResp, read by the probe's sequence. Shape first like
	// everywhere else: field 1 is the status varint at octet 16, an answer
	// without the field is status 0 (authorized), the encoding the PR's doc
	// describes. What the camera is doing afterwards is not tracked here: the
	// [nf] print of x5RecordNotif already names every push that arrives.
	function applyAuthProbe(buf as Lang.ByteArray) as Void {
		var st = 0;
		if (buf.size() >= 18 && buf[16] == 0x08) {
			st = buf[17] & 0xff;
		}
		authProbeStatus = st;
		authProbeSeq = -1;
		wireLine("auth probe", "answer status=" + st.toString() + " " + authStatusName(st));
	}

	function authStatusName(st as Lang.Number) as Lang.String {
		if (st == 0) {
			return "authorized";
		}
		if (st == 1) {
			return "unauthorized, Allow pending on the camera";
		}
		if (st == 2) {
			return "busy";
		}
		if (st >= 3 && st <= 6) {
			return "a client is already connected";
		}
		if (st == 7) {
			return "sleeping";
		}
		return "unknown status";
	}

	// The card-state ask, once per link at 2500 ms: after the auth probe and
	// the status ask, so it never slips between them. GET_STORAGE (166) with
	// body {1: location 0} asks the SD-card state, the one card datum this
	// link can get asked: the state is readable, the free and total bytes sit
	// past the cut (docs §10). Later changes belong to the 0x2006 push as
	// ever - this ask only answers the state at connect, which no push brings
	// until the card moves.
	function scheduleStorageAsk() as Void {
		if (x5StorageAskDue != null || x5StorageAsked || ucd2Armed) {
			return;
		}
		x5StorageAskDue = System.getTimer() + STORAGE_ASK_MS;
		armLinkAlarm();
	}

	function onStorageAsk() as Void {
		x5StorageAskDue = null;
		askStorageState();
	}

	function askStorageState() as Void {
		if (x5StorageAsked || device == null || ucd2Armed) {
			return;
		}
		x5StorageAsked = true;
		// The frame the PR's bench proved: header, then body 08 00 = field 1,
		// location 0.
		transmit([0x12, 0, 0, 0, 0x04, 0, 0, STORAGE_CMD, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x08, 0x00]b);
		x5StorageAskSeq = SeqNo;
		wireLine("storage", "asked command 166, seq=" + x5StorageAskSeq.toString());
	}

	function cancelStorageAskTimer() as Void {
		x5StorageAskDue = null;
		armLinkAlarm();
	}

	// The card answer, taken by its sequence like the auth answer above.
	// Shape first, like everywhere else: the body opens 0a (the nested
	// storage block), and the first inner field is 08 - the state octet is
	// the one that survives the cut of this 41-byte answer. An empty ack or
	// any other answer with this sequence gives null, writes nothing, and
	// names itself in the log.
	function x5ParseStorageAnswer(buf as Lang.ByteArray) as Lang.Number or Null {
		if (buf == null || buf.size() < 20 || buf[16] != 0x0a || buf[18] != 0x08) {
			return null;
		}
		return buf[19] & 0xff;
	}

	function applyStorageAsk(buf as Lang.ByteArray) as Void {
		x5StorageAskSeq = -1;
		var st = x5ParseStorageAnswer(buf);
		if (st != null) {
			x5StorageState = st;
		}
		wireLine("storage", "166 answer state=" + showValue(st) + " (the sizes past the cut, unknown here too)");
	}








	function lastOption(option as Lang.Number) as Lang.Number or Null {
		var buf = x5RxLast;
		if (buf == null) {
			return null;
		}
		var n = buf.size();
		var i = 16;
		while (i < n) {
			var tag = x5Varint(buf, i, n);
			if (tag == null) {
				break;
			}
			i = x5VarintEnd;
			var field = tag >> 3;
			var wire = tag & 7;
			if (wire == 0) {
				var v = x5Varint(buf, i, n);
				if (v == null) {
					break;
				}
				i = x5VarintEnd;
				if (field == option) {
					return v;
				}
			} else if (wire == 2) {
				var len = x5Varint(buf, i, n);
				if (len == null) {
					break;
				}
				i = x5VarintEnd;
				if (i + len > n) {
					break;
				}
				var j = i;
				var k = i + len;
				while (j < k) {
					var inner = x5Varint(buf, j, k);
					if (inner == null) {
						break;
					}
					j = x5VarintEnd;
					if ((inner & 7) != 0) {

						break;
					}
					var iv = x5Varint(buf, j, k);
					if (iv == null) {
						break;
					}
					j = x5VarintEnd;
					if ((inner >> 3) == option) {
						return iv;
					}
				}
				i += len;
			} else {

				break;
			}
		}
		return null;
	}


	// One varint field read straight out of a protobuf body, from a known offset
	// to a known end. The 0x2003 body is short and fixed in shape, so it needs
	// no general walk: walk it would only be a chance to lose the field.
	function x5ParseVarintField(buf as Lang.ByteArray, start as Lang.Number,
                             end as Lang.Number, field as Lang.Number) as Lang.Number or Null {
		var i = start;
		while (i < end) {
			var tag = x5Varint(buf, i, end);
			if (tag == null) {
				return null;
			}
			i = x5VarintEnd;
			if ((tag & 7) != 0) {
				return null;
			}
			var v = x5Varint(buf, i, end);
			if (v == null) {
				return null;
			}
			i = x5VarintEnd;
			if ((tag >> 3) == field) {
				return v;
			}
		}
		return null;
	}

	function x5ParseBatteryPower(buf as Lang.ByteArray) as Lang.Number or Null {
		// The observed push nests its status block at field 1 (0a 06 08 01 10 39
		// 20 00): power type and level live inside it. A flat field 1 varint at
		// the top level is read first, so a firmware that ever sends the datum
		// loose is still read right.
		return x5ParseBatteryField(buf, 1);
	}

	function x5ParseBatteryLevel(buf as Lang.ByteArray) as Lang.Number or Null {
		return x5ParseBatteryField(buf, 2);
	}

	function x5ParseBatteryField(buf as Lang.ByteArray, field as Lang.Number) as Lang.Number or Null {
		var n = buf.size();
		if (n <= 16) {
			return null;
		}
		var i = 16;
		while (i < n) {
			var tag = x5Varint(buf, i, n);
			if (tag == null) {
				return null;
			}
			i = x5VarintEnd;
			var wire = tag & 7;
			if (wire == 0) {
				var v = x5Varint(buf, i, n);
				if (v == null) {
					return null;
				}
				i = x5VarintEnd;
				if ((tag >> 3) == field) {
					return v;
				}
				continue;
			}
			if (wire != 2) {
				return null;
			}
			var len = x5Varint(buf, i, n);
			if (len == null) {
				return null;
			}
			i = x5VarintEnd;
			if ((tag >> 3) == 1) {
				// The watch ceiling cuts this block mid-body (declared 24, 20
				// cross). The bytes that did cross are the camera's own datum:
				// scan only up to what arrived, so a wire-0 field wholly inside
				// them reads true. The observed cut ends after 0a 06 08 01, so
				// the power type reads off the fragment and the level, sitting
				// past the cut, stays unreported rather than guessed.
				var blockEnd = i + len;
				if (blockEnd > n) {
					blockEnd = n;
				}
				if (blockEnd <= i) {
					return null;
				}
				return x5ParseVarintField(buf, i, blockEnd, field);
			}
			if (i + len > n) {
				return null;
			}
			i += len;
		}
		return null;
	}

	// The battery inside the GET_OPTIONS reply (code 200): the result block at
	// field 1, the option list at field 2, and each option a block of its own,
	// so the battery of option 11 sits two blocks deep where lastOption only
	// walks one. The walk below goes the two levels, and stops on any shape it
	// does not know: a wrong read of a battery is worse than no read.
	function x5ParseOptionsBattery(buf as Lang.ByteArray) as Lang.Number or Null {
		var n = buf.size();
		if (n <= 16) {
			return null;
		}
		var i = 16;
		while (i < n) {
			var tag = x5Varint(buf, i, n);
			if (tag == null) {
				return null;
			}
			i = x5VarintEnd;
			var wire = tag & 7;
			if (wire == 0) {
				var v = x5Varint(buf, i, n);
				if (v == null) {
					return null;
				}
				i = x5VarintEnd;
				continue;
			}
			if (wire != 2) {
				return null;
			}
			var len = x5Varint(buf, i, n);
			if (len == null) {
				return null;
			}
			i = x5VarintEnd;
			if (i + len > n) {
				return null;
			}
			if ((tag >> 3) == 2) {
				var level = x5ParseOptionBlockBattery(buf, i, i + len);
				if (level != null) {
					return level;
				}
			}
			i += len;
		}
		return null;
	}

	// One pass over the Options block: each option is a field-2 block holding
	// its type first, and the battery block lives inside the option 11.
	function x5ParseOptionBlockBattery(buf as Lang.ByteArray, from as Lang.Number,
                                     to as Lang.Number) as Lang.Number or Null {
		var i = from;
		while (i < to) {
			var tag = x5Varint(buf, i, to);
			if (tag == null) {
				return null;
			}
			i = x5VarintEnd;
			var wire = tag & 7;
			if (wire == 0) {
				var v = x5Varint(buf, i, to);
				if (v == null) {
					return null;
				}
				i = x5VarintEnd;
				continue;
			}
			if (wire != 2) {
				return null;
			}
			var len = x5Varint(buf, i, to);
			if (len == null) {
				return null;
			}
			i = x5VarintEnd;
			if (i + len > to) {
				return null;
			}
			if ((tag >> 3) == 11) {
				return x5ParseVarintField(buf, i, i + len, 2);
			}
			i += len;
		}
		return null;
	}




	function x5NotifBit(code as Lang.Number) as Lang.Number {
		if (code == X5_SUB_MODE_NOTIF) {
			return 1;
		}
		if (code == X5_OPTIONS_NOTIF) {
			return 2;
		}
		if (code == X5_CAPTURE_NUM_NOTIF) {
			return 4;
		}
		if (code == X5_CAPTURE_STATUS_NOTIF) {
			return 8;
		}
		if (code == X5_RECORD_STATE_NOTIF) {
			return 16;
		}
		if (code == X5_STORAGE_NOTIF) {
			return 64;
		}
		if (code == X5_STOP_PUSH_NOTIF) {


			return 128;
		}
		if (code == X5_PERIODIC_NOTIF) {



			return 256;
		}
		if (code == X5_BATTERY_NOTIF) {
			return 512;
		}
		if (code == X5_BATTERY_LOW_NOTIF) {
			return 1024;
		}



		return 32;
	}





	function x5CodeIndex(code as Lang.Number) as Lang.Number {
		var i = 0;
		while (i < x5CodesSeen.size()) {
			if (x5CodesSeen[i] == code) {
				return i;
			}
		i = i + 1;
		}
		return -1;
	}




	function x5CodeCount(code as Lang.Number) as Lang.Number {
		var ix = x5CodeIndex(code);
		if (ix < 0) {
			return 0;
		}
		return x5CodeCounts[ix];
	}





	function armX5() as Void {
		x5Armed = true;
	}


	function armWire() as Void {
		wireTrace = true;
		// The promise this line makes is the promise LOG_FRAMES keeps: the events
		// crossing the delegate are printed from now on, one line per event; the
		// bytes of those events answer only when that constant is flipped too
		// (item 9 of the integration, the constant's comment holds the why).
		wireLine("armed", "every event crossing the delegate is printed from now on");
	}





	function resetNotif() as Void {
		x5RxBuf = null;
		x5RxWant = 0;
		x5RxWasNotif = false;
		x5RxLast = null;
		x5VarintEnd = 0;
		notifCode = 0;
		notifSeq = 0;
		notifCount = 0;
		notifHex = "";
		notifVal1 = 0;
		notifVal2 = 0;
		notifVal3 = 0;
		notifOptTag = 0;
		notifOptVal = 0;
		notifOptTag2 = 0;
		notifOptVal2 = 0;
		notifOptCount = 0;
		x5Seen = 0;
		x5CodesSeen = [];
		x5CodeCounts = [];
		x5RxNewFrame = false;
		x5RxDeclared = 0;
		x5RxArrived = 0;
		x5RxTruncated = false;
		x5RxHeadSize = 0;
		x5RxFrag = 0;
		x5RxFragCount = 0;


		x5SubPhoto = null;
		x5SubVideo = null;
		x5ResNow = null;
		x5FuncMode = null;
		modeReqId = null;
		modeHoldUntil = 0;
		camModeId = null;
		x5StaleOptions = [];
		lastCmdSeq = -1;
		x5PhotoSeq = -1;
		x5PhotoResult = null;
		x5WriteSeq = -1;
		x5WriteName = "";
		x5WriteResult = null;
	}









	function peekNotifCode() as Lang.Number {
		return notifCode;
	}
	function peekNotifCount() as Lang.Number {
		return notifCount;
	}
	function peekNotifVal1() as Lang.Number {
		return notifVal1;
	}
	function peekNotifVal2() as Lang.Number {
		return notifVal2;
	}
	function peekNotifHex() as Lang.String {
		if (notifHex == null) {
			return "";
		}
		return notifHex;
	}
	function peekX5Seen() as Lang.Number {
		return x5Seen;
	}
	function peekWireEvents() as Lang.Number {
		return wireEvents;
	}


	function peekWireRecv() as Lang.Number {
		return wireRecv;
	}
	function peekNotifDeclared() as Lang.Number {
		return x5RxDeclared;
	}
	function peekNotifArrived() as Lang.Number {
		return x5RxArrived;
	}
	function peekNotifTruncated() as Lang.Boolean {
		return x5RxTruncated;
	}
	function peekBatteryLevel() as Lang.Number or Null {
		return x5BatteryLevel;
	}
	function peekBatteryPowerType() as Lang.Number {
		return x5BatteryPowerType;
	}
	function peekBatteryArrived() as Lang.Boolean {
		return x5BatteryArrived;
	}
	function peekBatteryLow() as Lang.Boolean {
		return x5BatteryLow;
	}


	// What the camera said about itself at connect: X5_STATE_AT_REST,
	// X5_STATE_RECORDING, or null while no answer has been read. null is a real
	// answer to the app - it means unknown, and the screen must not turn it into
	// "at rest".
	function peekCamState() as Lang.Number or Null {
		return x5CamState;
	}
	function peekCamRecording() as Lang.Boolean {
		return x5CamState != null && x5CamState == X5_STATE_RECORDING;
	}

	// The answer of the authorization probe (39): -1 while no answer has come,
	// else the status the camera gave - 0 the link is open, 1 the camera is
	// showing its own Allow prompt, 2 busy, 3..6 a client of that kind is
	// already connected, 7 sleeping; authStatusName below words them. When the
	// user answers the prompt on the camera, its 0x2011 push moves this to 0 in
	// x5ApplyNotif, so a screen that reads the edge is following the camera, not
	// a guess. -1 is a real answer to the app: it means not yet known.
	function peekAuthStatus() as Lang.Number {
		return authProbeStatus;
	}

	// The two flags of the 0x2006 storage push, and the free space, which is not
	// there to be had: the option 20 entry and the 0x2062 varints both begin at
	// octet 21 or later of their frame and have never crossed this link, so this
	// accessor answers null until a run brings the bytes over, and the app shows
	// "unknown" rather than a number.
	function peekStorageState() as Lang.Number or Null {
		return x5StorageState;
	}
	function peekStorageMode() as Lang.Number or Null {
		return x5StorageMode;
	}

	// Arms the answer of a shot: the app calls this right after the sendCMD of a
	// capture frame, at the same site that prints the frame's tell. lastCmdSeq is the
	// sequence the transport just stamped, the one the answer will carry - the same
	// follow-by-sequence discipline as the auth probe and the storage ask, asked from the
	// app side because there the capture frame is assembled.
	function armPhotoAck() as Void {
		x5PhotoSeq = lastCmdSeq;
		x5PhotoResult = null;
	}

	// Reads the shot's verdict once, as the PR's UI consumes photoResult: a read clears
	// it, so one answer colors one screen and never leaks into the next press. Untyped
	// like the symbols it hands over - the house rule for the values that are not numbers.
	function photoResultTaken() {
		var r = x5PhotoResult;
		x5PhotoResult = null;
		return r;
	}

	// Arms the answer of one settings write, same stamp site; the name only lets the
	// wire line say which write the verdict answers for.
	function armWriteAck(name as Lang.String) as Void {
		x5WriteSeq = lastCmdSeq;
		x5WriteName = name;
		x5WriteResult = null;
	}

	// Reads a settings verdict once, same clearing as the shot above.
	function settingResultTaken() {
		var r = x5WriteResult;
		x5WriteResult = null;
		return r;
	}
	function peekStorageFreeBytes() as Lang.Number or Null {
		return null;
	}

	// Octets, and pieces, that arrived after a frame was cut and were not glued to
	// it. Non-zero values are the expected shape of this link (15.27); they are
	// counted so a bench run can see them, not so they can be used.
	function peekRxFragments() as Lang.Number {
		return x5RxFrag;
	}
	function peekRxFragCount() as Lang.Number {
		return x5RxFragCount;
	}



	function peekSubPhoto() as Lang.Number or Null {
		return x5SubPhoto;
	}
	function peekSubVideo() as Lang.Number or Null {
		return x5SubVideo;
	}
	function peekResNow() as Lang.Number or Null {
		return x5ResNow;
	}
	function peekFuncMode() as Lang.Number or Null {
		return x5FuncMode;
	}

	// The mode echo gate, asked at the app's write sites (the shape PR #2 put
	// on its delegate, and measured there): noteModeWrite is asked just before
	// a mode write, with the id of the entry the user picked, the same name
	// the menu carries. An option write may then cross once its echo has been
	// seen, or once the hold ran out — never before, the camera answers 400
	// while it is still switching modes.
	function noteModeWrite(id as Lang.String) as Void {
		modeReqId = id;
		var t = System.getTimer() + MODE_ECHO_HOLD_MS;
		if (t > modeHoldUntil) {
			modeHoldUntil = t;
		}
		System.println("[mode] gate armed id=" + id);
	}

	// Extends the hold without arming a request: the app asks it while the
	// user browses, so a late echo of the camera cannot move a cursor.
	function holdMode(ms as Lang.Number) as Void {
		var t = System.getTimer() + ms;
		if (t > modeHoldUntil) {
			modeHoldUntil = t;
		}
	}

	function settingMayGo() as Lang.Boolean {
		return modeReqId == null || System.getTimer() >= modeHoldUntil;
	}

	// The mode the camera last said it is in (its own screen moves it, both
	// benches measured it), null while no trusted reading exists yet. What to
	// do with it is the app's decision, never this reader's.
	function peekCamMode() as Lang.String or Null {
		return camModeId;
	}

	// The rows a WATCH_RES named since the last link reset: the cache of the
	// app asks here whether a remembered option value still stands. The mark
	// clears only on a confirmation this watch drove - a write of the option
	// the camera answers 200 - never on a re-ask, which would meet the same
	// wall the value never crossed.
	function optionIsStale(opt as Lang.Number) as Lang.Boolean {
		return x5StaleIndex(opt) >= 0;
	}
	function peekStaleOptions() as Lang.Array {
		return x5StaleOptions;
	}
	function clearOptionStale(opt as Lang.Number) as Void {
		if (x5StaleIndex(opt) < 0) {
			return;
		}
		var keep = [];
		var i = 0;
		while (i < x5StaleOptions.size()) {
			if (x5StaleOptions[i] != opt) {
				keep.add(x5StaleOptions[i]);
			}
			i++;
		}
		x5StaleOptions = keep;
	}
	function peekSeenCodes() as Lang.Array {
		return x5CodesSeen;
	}



	function peekCodeCount(code as Lang.Number) as Lang.Number {
		return x5CodeCount(code);
	}



	function showValue(v as Lang.Value or Null) as Lang.String {
		if (v == null) {
			return "null";
		}
		if (v instanceof Lang.Boolean) {
			if (v) {
				return "true";
			} else {
				return "false";
			}
		}
		if (v instanceof Lang.Number) {
			return v as Lang.Number;
		}
		if (v instanceof Lang.String) {
			return "\"" + v as Lang.String + "\"";
		}
		if (v instanceof Lang.ByteArray) {
			return bytesToHex(v as Lang.ByteArray);
		}


		// Lang.Value has no toString and no getType; anything else gets a label.
		return "<other>";
	}










	function onUcd2Frame() as Void {
		cancelRetry();
		if (recState == stateStarting) {
			mMessage = "Shooting";
			recState = stateStartRec;
			startRecTime = Time.now();
			cancelPendingStart();
		} else if (recState == stateStopping) {
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;
			recState = stateStopRec;
			cancelPendingStart();
		}
	}






	// The confirmed-level axis of the menu. The chain at the scan answers by
	// the name the camera carries on air; the entry MenuLevel of the app
	// answers by what the user confirmed when the name matched no model. Both
	// confirmations are kept by the name on air, so a later bond with that
	// name resumes there; the fallback when neither answers is level 0, the
	// universal one. Nothing here is ever verified by asking the camera -
	// this barrel sends three asks at connect (auth, status, card), none of
	// them asks a menu.
	function noteConfirmedLevel(name as Lang.String, level as Lang.Number) as Void {
		if (name == null || name.equals("n/a") || level < 0) {
			System.println("[lvl] confirm refused name=" + (name == null ? "none" : name) + " level=" + level.toString());
			return;
		}
		App.getApp().setProperty("lvl." + name, level);
		System.println("[lvl] confirmed name=" + name + " level=" + level.toString() + " (kept for the next bond with this name)");
	}

	// The degraded axis: three questions and one note, per camera name. The
	// note comes from a failed user command - the 400 branch above, or the
	// app's own write pages when they run - never from a probe. The set
	// belongs to the camera name on air and crosses links and runs: an entry
	// this camera refused once stays named, and the menu decides what a named
	// entry means.
	function noteDegraded(id as Lang.String) as Void {
		if (id == null || id.length() == 0) {
			return;
		}
		if (isEntryDegraded(id)) {
			// Already kept: one line for one fact (criterion 14).
			System.println("[degr] noted again id=" + id + " (already kept)");
			return;
		}
		x5Degraded.add(id);
		keepDegraded();
		System.println("[degr] noted id=" + id + " kept=" + x5Degraded.size().toString());
	}

	function isEntryDegraded(id as Lang.String) as Lang.Boolean {
		var i = 0;
		while (i < x5Degraded.size()) {
			if ((x5Degraded[i] as Lang.String).equals(id)) {
				return true;
			}
			i++;
		}
		return false;
	}

	function peekDegraded() as Lang.Array {
		return x5Degraded;
	}

	// One comma-joined string per camera name. The tokenizer is the manual
	// scan on purpose: the string family of the SDK is where the API is the
	// most treacherous (the note of tools/mc_check.py), and a scan on indexOf
	// runs on every API level this project targets.
	function keepDegraded() as Void {
		if (deviceName == null || deviceName.equals("n/a")) {
			System.println("[degr] kept refused: no name to key the set on");
			return;
		}
		var s = "";
		var i = 0;
		while (i < x5Degraded.size()) {
			if (i > 0) {
				s += ",";
			}
			s += x5Degraded[i].toString();
			i++;
		}
		App.getApp().setProperty("degr." + deviceName, s);
	}

	// The set for a name, loaded at the classification that named this bond,
	// before any menu entry is reachable. The load starts a fresh set every
	// bond: a later camera of another name never inherits this one's facts.
	function loadDegradedForName() as Void {
		x5Degraded = [];
		if (deviceName == null || deviceName.equals("n/a")) {
			return;
		}
		var v = App.getApp().getProperty("degr." + deviceName);
		if (v == null) {
			System.println("[degr] name=" + deviceName + " nothing kept");
			return;
		}
		var s = v as Lang.String;
		if (s == null || s.length() == 0) {
			System.println("[degr] name=" + deviceName + " kept set empty");
			return;
		}
		var i = 0;
		while (i < s.length()) {
			var j = i;
			while (j < s.length() && !s.substring(j, j + 1).equals(",")) {
				j++;
			}
			var item = s.substring(i, j);
			if (item.length() > 0) {
				x5Degraded.add(item);
			}
			i = j + 1;
		}
		System.println("[degr] name=" + deviceName + " loaded kept=" + x5Degraded.size().toString());
	}

	// Axis model, the forcing of the menu (the entry MenuLevel of the
	// application). Three questions, three functions, each answering at its
	// own boundary, so the forcing is never read through a write (note 8 of
	// the CdC: the tell and the decision answer one datum).
	//
	// Is a run forced at all? The datum is the model of the matrix in force;
	// an empty String answers a run that is not forced. The content test of a
	// Lang.String is .equals(), never ==, which compares object identity and
	// is never true on a String (note 9 of the CdC, item 14).
	function hookForced() as Lang.Boolean {
		// Silent on its own: the state of the forcing prints at the gate of the
		// menu, where the run names it once, and a print per write here would bury
		// the rungs of the ladder under a line that answers nothing (criterion 14
		// reads an armed marker, not a flood).
		return !testModel.equals("");
	}

	// Axis of the ceiling of the forcing, asked at the transport. A write of a
	// family forced on another camera crosses the bond of the camera the user
	// owns, so the forcing is bounded: the datum counts the writes that
	// crossed while forced, and the refusal answers at the site that withholds
	// the write, never by an absence of a line (criterion 14 of 11.3). A frame
	// refused is not a frame the camera refused: nothing was asked of it, no
	// reply exists for it, and an acceptance never closes on a reply (EF-22).
	// One call per write, never one per chunk of the transport below, which
	// chunks a frame at 20 octets (note 23's rule).
	function hookCeiling() as Lang.Boolean {
		if (!hookForced()) {
			// Not a write of a forced family: the ceiling never applies, and no
			// line prints, because a line here would answer for a write the
			// forcing did not arm.
			return false;
		}
		if (hookSent >= HOOK_WRITE_CEILING) {
			System.println("[hook] refused ceiling=" + HOOK_WRITE_CEILING.toString() + " sent=" + hookSent.toString() + " model=" + testModel + " level=" + testLevel.toString());
			return true;
		}
		hookSent = hookSent + 1;
		var left = HOOK_WRITE_CEILING - hookSent;
		System.println("[hook] sent n=" + hookSent.toString() + " left=" + left.toString() + " model=" + testModel + " level=" + testLevel.toString());
		return false;
	}

	function sendCMD(value as Lang.ByteArray) as Void {
		if (ucd2Armed) {
			ucd2Send(value);
			return;
		}
		if (value == cmdStopRec) {
			cancelPendingStart();
		}
		// Axis of the ceiling: the question is asked before the frame is handed to
		// the transport, so a refused write never reaches the bond and the line of
		// hookCeiling() answers for it. The frame is not filtered by content here:
		// a write of the family forced is a write of the protocol of that family,
		// and the datum is how many of them crossed.
		if (hookCeiling()) {
			return;
		}
		transmit(value);
	}



	function transmit(value as Lang.ByteArray) as Void {
		if (scanning) {
		    System.println("[scan] press scanning=" + scanning.toString() + " deviceNull=" + (device == null).toString());
			return;
		}
		// Press tell: the print sits after the scanning guard, so the line answers only the presses that reach the device check; a press swallowed while the widget searches answers by silence at this site.
		var dev = device;
		if (dev == null) {
			recState = stateStopRec;
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
			return;
		}

		if (value == cmdApply) {
			applyBursts += 1;
		}




		if (txUcd2) {
			ucd2SeqNo = ucd2SeqNo + 1;
			if (ucd2SeqNo > 254) {
				ucd2SeqNo = 1;
			}
			ucd2StampSeq(value, ucd2SeqNo);
		} else {
			SeqNo = SeqNo + 1;
			if (SeqNo > 254) {
				SeqNo = 1;
			}
			value[SeqPos] = SeqNo;
			// The sequence a refusal of this frame answers by (the 0x190
			// branch of x5ApplyResponse matches against this).
			lastCmdSeq = SeqNo;
		}

		wireBytes("sent frame", value);




		if (value.size() > 20) {
			var j = (value.size() - 1) / 20;
			for (var i = 0; i <= j.toNumber(); i++) {
				var chunk = value.slice(i*20,(i + 1) * 20);
				queue.add(chunk);
				wireBytes("sent chunk", chunk);
			}
		} else {
			queue.add(value);
			wireBytes("sent chunk", value);
		}




		if (!inRetry) {
			if (txUcd2) {


				scheduleRetry(ucd2TxKind);
			} else if (value == cmdStartRec) {
				scheduleRetry(retryKindStart);
			} else if (value == cmdStopRec) {
				scheduleRetry(retryKindStop);
			}
		}





		var service = dev.getService(LBS_SERVICE);
		if (service == null) {
			discoverServices(dev);
			return;
		}

		kickQueue(dev);
	}





	function deferStart() as Void {
		pendingStart = true;
		startAckSeen = false;
		startWaitCount = 0;
		if (applyBursts >= 2) {
			startPhase = 1;
			armStartDelay(START_WAIT_MS);
		} else {
			startPhase = 0;
			armStartDelay(START_DELAY_MS);
		}
	}

	// One wait of the start sequence, booked as a date like every other delayed
	// action of the link (see armLinkAlarm).
	function armStartDelay(ms as Lang.Number) as Void {
		startDelayDue = System.getTimer() + ms;
		armLinkAlarm();
	}

	function onStartDelay() as Void {
		startDelayDue = null;
		if (!pendingStart) {
			return;
		}
		if (startPhase == 0) {


			startPhase = 1;
			startWaitCount = 0;
			if (currentMode instanceof Lang.ByteArray) {
				transmit(currentMode as Lang.ByteArray);
			}
			transmit(cmdApply);
			armStartDelay(START_WAIT_MS);
			return;
		}
		if (startAckSeen) {
			fireStart();
			return;
		}
		startWaitCount += 1;
		if (startWaitCount > START_WAIT_MAX) {
			fireStart();
			return;
		}
		armStartDelay(START_WAIT_MS);
	}

	function fireStart() as Void {
		pendingStart = false;
		startAckSeen = false;
		startWaitCount = 0;
		startPhase = 0;
		startDelayDue = null;
		armLinkAlarm();
		transmit(cmdStartRec);
	}

	function cancelPendingStart() as Void {
		pendingStart = false;
		startAckSeen = false;
		startWaitCount = 0;
		startPhase = 0;
		startDelayDue = null;
		armLinkAlarm();
	}






	function kickQueue(dev as BluetoothLowEnergy.Device) as Void {
		if (writing) {
			wireLine("write in flight", "one requestWrite is pending, this call is a no-op");
			return;
		}
		if (queue.size() == 0) {
			wireLine("queue empty", "nothing queued, nothing to write");
			return;
		}
		var service = dev.getService(LBS_SERVICE);
		if (service == null) {
			wireLine("service missing", "getService(LBS_SERVICE) is null, write refused");
			return;
		}
		try {
			var ch = service.getCharacteristic(LBS_RW_CHAR);
			if (ch != null) {
				writing = true;

				ch.requestWrite(queue[0] as Lang.ByteArray, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
				// An issued write answers that the stack takes writes again: the
				// dead-bond count clears here.
				wedgeCount = 0;
				wireLine("requestWrite issued", "chunk in flight");
			} else {
				// Not counted as a refused write: this is a pre-discovery state,
				// and the service walk re-kicks the queue when it finds the
				// characteristic (the kick at the end of discoverServices).
				wireLine("characteristic missing", "getCharacteristic(LBS_RW_CHAR) is null, write refused");
			}
		} catch (ex) {
			wireLine("requestWrite refused", "exception: " + ex.getErrorMessage() + " count=" + (wedgeCount + 1).toString());
			writing = false;
			// The pump is the only writer, and no timer re-kicks it: if the
			// stack keeps refusing, the wedge outlives the app's own retries
			// (which work on responses, not on writes). Past the ceiling the
			// bond is declared dead, below.
			wedgeCount += 1;
			if (wedgeCount >= WEDGE_REFUSALS_MAX) {
				// Declare the bond dead. unpairDevice is the counterpart of
				// the pairDevice that made this bond - the same teardown the
				// app's own close() runs, Device has no close() on this API -
				// and the teardown after it is the one a real disconnect runs,
				// extracted into linkGone so both reach the same code. The
				// queue keeps its chunks exactly as the disconnect path
				// leaves them: a service walk on the new bond kicks it again.
				wireLine("pump wedge", "close the bond after " + wedgeCount.toString() + " refused writes");
				wedgeCount = 0;
				try {
					BluetoothLowEnergy.unpairDevice(dev);
				} catch (ex2) {
					wireLine("pump wedge unpair refused", ex2.getErrorMessage());
				}
				linkGone();
			}
		}
	}


	function scheduleRetry(kind as Lang.Number) as Void {



		if (retryKind != kind) {
			retryCount = 0;
		}
		retryKind = kind;
		armRetry();
	}

	function cancelRetry() as Void {
		retryKind = 0;
		retryCount = 0;
		retryDue = null;
		armLinkAlarm();
	}

	// The write retry, booked as a date like the rest of the schedule.
	function armRetry() as Void {
		retryDue = System.getTimer() + RETRY_DELAY_MS;
		armLinkAlarm();
	}


	function onRetry() as Void {
		retryDue = null;
		if (retryKind == 0) {
			return;
		}
		retryCount += 1;
		if (retryCount > RETRY_MAX) {

			var wasStart = (retryKind == retryKindStart);
			cancelRetry();


			recState = wasStart ? stateStopRec : stateStartRec;
			if (ucd2Armed) {



				mMessage = "No answer from camera";
			}
			WatchUi.requestUpdate();
			return;
		}

		inRetry = true;
		if (retryKind == retryKindStart) {
			resendStart();
		} else {
			sendCMD(cmdStopRec);
		}
		inRetry = false;
		armRetry();
	}





	function resendStart() as Void {
		sendCMD(cmdStartRec);
	}

	function onCharacteristicChanged(ch as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {


		wireBytes("recv", value);
		wireRecv = wireRecv + 1;





		if (ucd2Armed) {




			if (ucd2IsAck(value)) {
				if (ucd2RxBuf != null) {

				ucd2RxBuf = null;
				ucd2RxWant = 0;
			}
			onUcd2Frame();
			WatchUi.requestUpdate();
			return;
		}
		if (ucd2RxFeed(value)) {

			onUcd2Frame();
			WatchUi.requestUpdate();
			return;
		}
		if (ucd2RxBuf != null) {


			return;
		}
		}











		// One machine reads the legacy envelope now. Every notification either
		// opens a frame (a header), extends one (a continuation), or closes one
		// (the beat), and x5RxFeed says when a frame is ready, whole or cut.
		// There is no second reader of the raw notification below this point:
		// the old responseSig block that scanned raw notifications for the
		// recording report's signature is gone, its branches live in
		// x5ApplyResponse, which runs on the assembled frame instead.
		// The x5Armed gate is gone too: the bench (X5-fw-legacy-v2) showed the
		// camera pushing 0x2010, 0x2040 and 0x2006 on its own, with no request
		// from the watch, so the request state must not decide whether a push
		// is read.
		if (x5IsFrame(value) || x5RxBuf != null) {
			if (x5RxFeed(value)) {



				x5DecodeNotif();




				if (x5RxTruncated) {
					wireLine("frame cut", "declared=" + x5RxDeclared.toString() + " arrived=" +
                      x5RxArrived.toString());
				}
				if (x5RxWasNotif) {
					x5ApplyNotif();
					WatchUi.requestUpdate();


					return;
				}
				x5ApplyResponse(x5RxLast);
			} else if (x5RxWasNotif) {


				return;
			}
		}


		if (recState == stateStartRec) {
			clockTime = Time.now();
			var diff = clockTime.subtract(startRecTime);
			if (diff instanceof Time.Duration) {
				elapsedRecTime = diff;
				mMessage = currentLabel + "\n" + toTimeString(elapsedRecTime.value());
			}
		} else {

		}
		WatchUi.requestUpdate();
	}

	function onCharacteristicWrite(ch as BluetoothLowEnergy.Characteristic, st as BluetoothLowEnergy.Status) as Void {





		wireLine("write done", "status=" + st.toString() + " leftInQueue=" + queue.size().toString());
		writing = false;
		if (queue.size() > 0) {

			var remaining = [] as Lang.Array;
			for (var k = 1; k < queue.size(); k++) {
				remaining.add(queue[k] as Lang.ByteArray);
			}
			queue = remaining;
		}
		var dev = device;
		if (dev != null && queue.size() > 0) {
			kickQueue(dev);
		} else {
			debug("[onCharWrite] queue empty Status " + st.toString());
		}
	}

	function toTimeString(seconds as Lang.Number) as Lang.String {
		var hours = seconds / 3600;
		var min = (seconds - hours * 3600) / 60;
		var sec = (seconds - hours * 3600) - min * 60;

		return hours.toString() + ":" + min.format("%02d") + ":" + sec.format("%02d");
	}

	function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
		wireLine("profile register", uuid.toString() + " status=" + status.toString());
		// Named by an unconditional println, the way the [scan] axis lines are,
		// because this callback had been invisible in every real log: the bench
		// of 12 nov. connected a real X5 without ever printing this line - the
		// profile registered at open is not negotiated on a manually paired
		// link. The link's asks no longer ride this trigger (see armLinkAsks);
		// the print stays so the callback is never again trusted silently.
		System.println("[ask] profile register uuid=" + uuid.toString() + " status=" + status.toString());
		if (DEBUG_TRACE) {
			debug("registered");
		}
	}



	function onEncryptionStatus(dev as BluetoothLowEnergy.Device, status as BluetoothLowEnergy.Status) as Void {
		wireLine("encrypt status", status.toString());
	}


function registerProfiles() as Void {



		if (ucd2Profile == null) {
			ucd2Profile = {
				:uuid => LBS_SERVICE,
				:characteristics => [
					{ :uuid => LBS_RW_CHAR },
					{
						:uuid => LBS_NOTIF_CHAR,
						:descriptors => [ LBS_NOTIF_DESC ]
					}
				] };
		}
		try {
			BluetoothLowEnergy.registerProfile(ucd2Profile);
		} catch (ex) {


			wireLine("register refused", ex.getErrorMessage());
		}

	}




	function discoverServices(dev as BluetoothLowEnergy.Device) as Void {
		if (dev == null) {
			return;
		}
		try {
			var iter = dev.getServices();
			var count = 0;
			while (iter != null) {
				var svc = iter.next() as BluetoothLowEnergy.Service;
				if (svc == null) {
					break;
				}
				var su = svc.getUuid();
				if (su == null) {
					wireLine("svc uuid", "null");
				} else {
					wireLine("svc uuid", su.toString());
				}
				count = count + 1;
			}
			var lbs = dev.getService(LBS_SERVICE);


			wireLine("services walked", "count=" + count.toString() + " queued=" + queue.size().toString());
			if (lbs == null) {
				wireLine("lbs service", "getService(LBS_SERVICE) is null");
			} else {
				wireLine("lbs service", "found");
			}


			if (lbs != null) {
				// The link can be written from here on - so its first asks are
				// booked from here on (armLinkAsks names why this site).
				armLinkAsks();
				kickQueue(dev);
			}
		} catch (ex) {
			wireLine("walk refused", ex.getErrorMessage());
		}
	}

	function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
		wireLine("scan state", scanState.toString() + " status=" + status.toString());
		if (DEBUG_TRACE) {
			debug("scanstate");
		}
		System.println("[scan] state=" + scanState.toString() + " status=" + status.toString() + " wasScanning=" + scanning.toString() + " deviceNull=" + (device == null).toString());
		if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
			scanning = true;
			mMessage = "Scanning...\n" + scanTimeout.toString();
			WatchUi.requestUpdate();
			System.println("[scan] on countdown=" + scanTimeout.toString());
		} else {
			scanning = false;
			scanTimeout = 64;
			if (device == null) {
				mMessage = startMessage + "\nto scan";
			} else {
				mMessage = currentLabel + "\n" + startMessage;
			}
			WatchUi.requestUpdate();
		}
	}
	// Scan axis: the state print sits at the entry of the callback, before the branch, so a state that does not cross the branch is named by a line and never by a silence.
	function onConnectedStateChanged(dev as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
		wireLine("connection state", state.toString());

		mMessage = currentLabel + "\n" + startMessage;
		WatchUi.requestUpdate();
		writing = false;
		// The bond changes (this branch runs for connected as for disconnected):
		// a fresh bond starts with a fresh pump count.
		wedgeCount = 0;
		if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
			connecting = false;
			applyBursts = 0;
			debug("[onCSC] scanning OFF");
			if (scanning) {
				try {
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
				} catch (ex) {

				}

				scanning = false;
			}
			device = dev;
			discoverServices(dev);
		} else {
			linkGone();
		}
	}

	// The normal teardown of a dead link: null the device, re-open the scan,
	// keep nothing that supposes the old bond was still answering. Two sites
	// reach it when the bond is declared dead: the real disconnect the stack
	// reports, and the pump's watchdog after WEDGE_REFUSALS_MAX refused
	// writes. The guard is part of the pattern - a scan already open is not
	// opened a second time.
	private function linkGone() as Void {
		if (!scanning) {
			scanning = true;
			device = null;
			// The link is gone: forget that a state ask was outstanding so the
			// next connect asks again, and stop the timer that would ask into a
			// dead link.
			cancelStatusTimer();
			x5StatusAsked = false;
			x5StatusTries = 0;
			authProbeAsked = false;
			authProbeSeq = -1;
			authProbeStatus = -1;
			x5StorageAsked = false;
			x5StorageAskSeq = -1;
			cancelStorageAskTimer();
			open();






		}
	}

	private function connect(result as BluetoothLowEnergy.ScanResult) as Void {

		try {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);

		} catch (ex) {

		}
		try {
			device = BluetoothLowEnergy.pairDevice(result);
			if (device == null) {
				wireLine("pair", "pairDevice returned null");
			} else {
				wireLine("pair", "paired");
			}
			if (device != null) {



				var nm = device.getName();
				if (nm == null) {
					nm = "n/a";
				}
				wireLine("dev state", "connected=" + device.isConnected().toString() + " name=" +
				              nm);
			}





			// A re-connect never keeps silently the family a test forced: the
			// datum of the detection is re-written here, and the datum of the
			// forcing is cleared. menuLevel goes back to the detected one, and
			// the counter of the writes that crossed under the forcing goes back
			// to nothing, so the ceiling of a fresh bond is a fresh ceiling
			// (axis of the persistence, one datum cleared per datum armed).
			// Axis of the persistence, one print before the decision of the
			// guard below takes it (note 8 of the CdC).
			// The print is armed at this site so the clearing answers by a line:
			// an absence of a line is never a verdict (criterion 14 of 11.3).
			menuLevel = detectedLevel;
			capModel = detectedModel;
			// The forcing itself: no model in force, no envelope forced, no write
			// counted. testLevel stays at -1, which no model of the matrix answers,
			// so the gate of the application reads a run that is not forced.
			testModel = "";
			testLevel = -1;
			hookSent = 0;
			// CdC item 158: the state of the axis model after this clearing, printed
			// here so a re-connected run names the model in force and the model
			// detected, and never leaves the two to be supposed.
			System.println("[relink] model=" + capModel + " level=" + menuLevel.toString() + " forced=" + (testLevel != -1).toString() + " detectedModel=" + detectedModel + " detectedLevel=" + detectedLevel.toString());
			if (menuLevel == 3) {
				ucd2Armed = true;
				currentLabel = "X6 Video";
			}
		} catch (ex) {

		}


	}








	function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {

		System.println("[scan] round countdown=" + scanTimeout.toString() + " deviceNull=" + (device == null).toString());
		// Scan axis: this print sits before the loop over the results, so the callbacks of the scan are counted apart from the results they carry, which is what grades the step of a countdown driven by rounds.

		for (var rawResult = scanResults.next(); rawResult != null; rawResult = scanResults.next()) {
			var result = rawResult as BluetoothLowEnergy.ScanResult;
			var uuids = result.getServiceUuids();
			var name = result.getDeviceName();
			if (name != null) {
				deviceName = name;
			}








			System.println("[det] name=" + (name == null ? "none" : name));

			for (var rawUuid = uuids.next(); rawUuid != null; rawUuid = uuids.next()) {
				var iter = rawUuid as BluetoothLowEnergy.Uuid;
				wireLine("scan uuid", iter.toString());


				if ((iter.equals(LBS_SERVICE)) and (deviceName != null)) {
				menuLevel = 0;
				// Axis model. The model of the matrix the name answers, kept apart from
				// the level: the level is the envelope of the application, the model is
				// the entry table it builds. It starts at none, so a name that matches no
				// branch of the chain names the model none at the print below, and never
				// keeps the model of a previous round of the scan.
				capModel = "none";
					if (deviceName.length() >= 3) {
					var prefix = deviceName.substring(0, 3);
				if (prefix != null) {
					if (prefix.equals("ONE")) { capModel = "ONE X";
						menuLevel = 1;
					}
					if (prefix.equals("X3 ")) { capModel = "X3";
						menuLevel = 1;
					}

					// The X2 has no branch of its own before: it belongs to the older envelope like
					// the X3 and the ONE X, so its level is 1 and never the level 0, whose menu is
					// empty (decision of the CdC, the X2 is pre-UCD2).
					if (prefix.equals("X2 ")) { capModel = "X2";
						menuLevel = 1;
					}

					// The X4 Air shares the three first characters with the X4, so the
					// full name decides between the two, and it decides only when the
					// name answers the seven first characters: the name of the X4 Air
					// over the wire was never relevee, so this test reads the datum of
					// the name and never guesses a model.
					if (prefix.equals("X4 ")) { capModel = "X4";
						if (deviceName.length() >= 7) {
							if (deviceName.substring(0, 7).equals("X4 Air")) { capModel = "X4 Air"; }
						}
						menuLevel = 2;
					}
					if (prefix.equals("X5 ")) { capModel = "X5";


						x5Armed = true;
						menuLevel = 2;
					}
					if (prefix.equals("X6 ")) { capModel = "X6";
						menuLevel = 3;
					}



					// The datum of the detection, kept apart from the datum of the forcing: the hook
					// of the menu overwrites menuLevel and capModel, and never touches these two, so
					// a run forced says which model was detected and which one is in force.
					detectedLevel = menuLevel;
					detectedModel = capModel;

					// Axis model of the scan: the classification of this round, after
					// the chain took its decision. A name that matches no branch names
					// the model none here, so the verdict answers by a line and never
					// by an absence of a line (criterion 14 of 11.3).
					System.println("[mdl] name=" + deviceName + " model=" + capModel + " level=" + menuLevel.toString() + " detectedModel=" + detectedModel + " detectedLevel=" + detectedLevel.toString());

					// The confirmed level, kept and restored by the name on air.
					// The chain above decides by that name; nothing here asks the
					// camera its menu (no probing frame is ever emitted at connect,
					// the phase-5 gate counts the frames to prove it). When the
					// chain answered a model, that level is kept for this name.
					// When the chain answered none, the kept level is tried before
					// the fallback, and the fallback is the level 0 the chain left
					// standing. The key is the name, the unit the user owns; the
					// datum of the detection above stays untouched, the restored
					// level is a level in force, named as such at its print.
					if (capModel.equals("none")) {
						var kept = App.getApp().getProperty("lvl." + deviceName);
						var keptLevel = kept as Lang.Number;
						if (keptLevel != null && keptLevel >= 0) {
							menuLevel = keptLevel;
							System.println("[lvl] restored name=" + deviceName + " level=" + menuLevel.toString() + " no model in the chain, this is the level kept");
						} else {
							System.println("[lvl] name=" + deviceName + " no model, nothing kept, level 0 stands");
						}
					} else {
						App.getApp().setProperty("lvl." + deviceName, menuLevel);
						System.println("[lvl] kept name=" + deviceName + " level=" + menuLevel.toString());
					}

					// The degradations kept for this name, loaded before any entry
					// of the menu is reachable, fresh per bond of a new name.
					loadDegradedForName();

                    // The hook of the compile-time constant, whose fault was closed with
                    // the constant at OFF (CdC item 147: the reference had `and`, the
                    // reconstruction had `or`, which forced every named camera to the
                    // level 3). This site stays as it is.
                    if (X6_TEST_HOOK and deviceName.equals(X6_TEST_HOOK_NAME)) {
						menuLevel = 3;
					}
				}
					}
					connect(result);
					return;
				}
			}
























			// Scan axis: the countdown advances inside the loop over the scan results, so one step is one result. The print below sits after the step, at the boundary the countdown crosses.
			// Scan axis: the print names the value of the countdown and whether it reached zero, where the scan is demanded to stop.
			scanTimeout--;
			mMessage = "Scanning...\n" + scanTimeout.toString();
			WatchUi.requestUpdate();
			System.println("[scan] tick countdown=" + scanTimeout.toString() + " stop=" + (scanTimeout == 0).toString());
			if (scanTimeout == 0) {
				try {
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
				} catch (ex) {

				   }
			}
		}
	}

	function photoGpsHeader(lat as Lang.Number or Lang.Float or Lang.Double,
                         lon as Lang.Number or Lang.Float or Lang.Double,
                         alt as Lang.Number or Lang.Float or Lang.Double) as Lang.ByteArray {

		var header = [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18]b;
		var filler = [0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
		header.addAll(toDouble(lat));
		header.addAll(toDouble(lon));
		header.addAll(toDouble(alt));
		header.addAll(filler);
		return header;
	}

	function toDouble(single as Lang.Number or Lang.Float or Lang.Double) as Lang.ByteArray {

		var double = new [0]b;
		var d1 = new [4]b;
		var d2 = new [4]b;
		var t32 = new [4]b;
		var ts = 0l;
		var tb = 0l;
		var tb1 = 0l;
		var tb2 = 0l;
		var te = 0l;
		var tm = 0l;
		var bias = 0l;


		t32.encodeNumber(single as Lang.Number, Lang.NUMBER_FORMAT_FLOAT, {});
		tb = t32.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {}) as Lang.Long;

		ts = tb & 0x80000000l;

		te = tb & 0x7f800000l;
		te >>= 23;

		bias = te - 127 + 1023;
		bias <<= 52;

		tm = tb & 0x007fffffl;
		tm <<= 29;

		ts <<= 32;
		tb = ts + bias + tm;

		tb1 = tb;
		tb1 >>= 32;
		d1.encodeNumber(tb1, Lang.NUMBER_FORMAT_UINT32, {});
		tb1 <<= 32;
		tb2 = tb - tb1;
		d2.encodeNumber(tb2, Lang.NUMBER_FORMAT_UINT32, {});


		double.addAll(d2);
		double.addAll(d1);
		return double;
	}

	function sendPosition(info as Position.Info) as Void {















		var header = [0x47, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x35, 0x00, 0x02, 0xff, 0x00, 0x00, 0x80, 0x00, 0x00, 0x0a, 0x35]b;
		var filler = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41]b;
		var latitude = 0;
		var longitude = 0;
		var speed = 0;
		var heading = 0;
		var altitude = 0;
		var temp32 = new [4]b;
		var temp64 = new [8]b;
		var sector = 0x4e;

		GPSaccuracy = info.accuracy;
		WatchUi.requestUpdate();


		if ((device == null) or (recState != stateStartRec)) { return; }



		var position = info.position;
		var headingInfo = info.heading;
		var whenInfo = info.when;
		if ((position == null) or (headingInfo == null) or (whenInfo == null)) { return; }

		var location = position.toDegrees();
		latitude = location[0];
		longitude = location[1];


		heading = headingInfo * 180 / Math.PI;
		if (heading < 0) {
			heading = 360 + heading;
		}

		var speedInfo = info.speed;
		if (speedInfo != null) {
			speed = speedInfo.toNumber();
		}
		var altitudeInfo = info.altitude;
		if (altitudeInfo != null) {
			altitude = altitudeInfo.toNumber();
		}




		if (videoMode) {

			temp32.encodeNumber(whenInfo.value(), Lang.NUMBER_FORMAT_UINT32, {});
			header.addAll(temp32);
			header.addAll(filler);

			if (latitude >= 0) {
				sector = 0x4e;
			} else {
				sector = 0x53;
			}

			temp64 = toDouble(latitude.abs());
			header.addAll(temp64);
			header.add(sector);

			if (longitude >= 0) {
				sector = 0x45;
			} else {
				sector = 0x57;
			}

			temp64 = toDouble(longitude.abs());
			header.addAll(temp64);
			header.add(sector);

			temp64 = toDouble(speed.abs());
			header.addAll(temp64);


			temp64 = toDouble(heading);
			header.addAll(temp64);


			temp64 = toDouble(altitude.abs());
			header.addAll(temp64);


			sendCMD(header);
		}
	}

	function open() as Void {
		System.println("[ble] open() entered");


		if (System.getDeviceSettings().isTouchScreen) {
			startMessage = "Tap Here";
		} else {
			startMessage = "Press Start";
		}


		var v = App.getApp().getProperty("recState");
		if (v == null) {
			recState = stateStopRec;
		} else {


			var storedState = v as Lang.Number;
			if (storedState != null) {
				recState = storedState;
			} else {
				recState = stateStopRec;
			}
		}





		currentMode = "DefaultV";
		currentLabel = "Default Video";


		ucd2Armed = false;
		ucd2RxBuf = null;
		ucd2RxWant = 0;
		lastTime = Time.now();
		var startProp = App.getApp().getProperty("startRecTime");
		if (startProp == null) {
			startRecTime = Time.now();
		} else {
			var storedStart = startProp as Lang.Number;
			if (storedStart != null) {
				startRecTime = new Time.Moment(storedStart);
			}
		}






		var gpsProp = App.getApp().getProperty("GPSon");
		if (gpsProp == null) {
			GPSon = false;
		} else {
			if (gpsProp instanceof Lang.Boolean) {
				GPSon = gpsProp as Lang.Boolean;
			} else {
				var s = gpsProp.toString();
				GPSon =  s.equals("true") or s.equals("1");
			}
		}

		registerProfiles();
		BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
		// Scan axis: an opening arms the scan; the print names the countdown value the new scan starts from.
		System.println("[scan] open countdown=" + scanTimeout.toString());

		wireLine("connections", BluetoothLowEnergy.getAvailableConnectionCount().toString());







	}

	function close() as Void {
		ucd2Armed = false;


		x5Armed = false;
		x5RxBuf = null;
		x5RxWant = 0;
		x5RxWasNotif = false;
		x5RxLast = null;
		ucd2RxBuf = null;
		ucd2RxWant = 0;
		notifCount = 0;
		notifHex = "";
		x5Seen = 0;

		// The link is over, so the schedule goes with it: every date is dropped
		// and the one Timer object the link owned is taken down. A session that
		// ends leaves no alarm armed, and the process's timer pool is free for
		// whatever starts next.
		authProbeDue = null;
		x5StatusDue = null;
		x5StorageAskDue = null;
		retryDue = null;
		startDelayDue = null;
		if (linkAlarm != null) {
			linkAlarm.stop();
			linkAlarm = null;
		}

		App.getApp().setProperty("recState", recState);
		App.getApp().setProperty("startRecTime", startRecTime.value());
		if (currentMode instanceof Lang.ByteArray) {
			App.getApp().setProperty("currentMode", bytesToHex(currentMode as Lang.ByteArray));
		} else {
			App.getApp().setProperty("currentMode", "DefaultV");
		}
		App.getApp().setProperty("currentLabel", currentLabel);
		App.getApp().setProperty("GPSon", GPSon);
		if (scanning) {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
		}
		if (device != null) {
			BluetoothLowEnergy.unpairDevice(device);
		}
	}
}
}
