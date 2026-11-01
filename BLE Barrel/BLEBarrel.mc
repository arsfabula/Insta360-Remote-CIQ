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
const responseSig = [0x00, 0x00, 0x04, 0x00, 0x00]b;
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







const X6_TEST_HOOK = false;
const X6_TEST_HOOK_NAME = "X5 3S6GEW";

// Ceiling of the writes of the test hook of the menu. The hook forces the menu
// and the envelope of a model on a camera of ANOTHER model, so the frames of
// the family forced reach the camera the user owns. The ceiling is the bound
// of that: a frame of the forced family crosses only while the counter stays
// under it, and the refusal answers with a print at the transport, never by
// silence (criterion 14 of 11.3). The datum counts the frames that crossed.
const HOOK_WRITE_CEILING = 3;


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
const X5_RECORD_STATE_NOTIF = 0x2040;


const X5_STORAGE_NOTIF = 0x2006;
const X5_STOP_PUSH_NOTIF = 0x2062;




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
(:glance)
class BleDevice extends BluetoothLowEnergy.BleDelegate {
 var scanning as Lang.Boolean = false;
 var scanTimeout as Lang.Number = 64;
 var device as BluetoothLowEnergy.Device or Null = null;
 var button as Lang.Number = 0;
 var retryTimer as Timer.Timer or Null = null;
 var retryKind as Lang.Number = 0;
 var retryCount as Lang.Number = 0;
 var inRetry as Lang.Boolean = false;
 var startDelayTimer as Timer.Timer or Null = null;
 var pendingStart as Lang.Boolean = false;
 var ucd2Profile as Lang.Dictionary or Null = null;
 var startAckSeen as Lang.Boolean = false;
 var startWaitCount as Lang.Number = 0;
 var startPhase as Lang.Number = 0;



 var applyBursts as Lang.Number = 0;
 var writing as Lang.Boolean = false;

	protected function debug(str as Lang.String) as Void {
		if (DEBUG_TRACE) {
			System.println("[ble] " + str);
		}
	}







	protected function wireBytes(tag as Lang.String, data as Lang.Array) as Void {
		if (!wireTrace) {
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
				return false;
			}
			x5RxWant = declared;
			x5RxWasNotif = x5IsNotif(value);
			x5RxNewFrame = true;
			x5RxBuf = ucd2Cat(null, value);
		} else if (x5RxBuf == null) {
			return false;
		} else if (value.size() == 7 && value[0] == 0x07 && value[4] == 0x05) {




			x5RxBuf = null;
			x5RxWant = 0;
			return false;
		} else {



			x5RxNewFrame = false;
			x5RxBuf = ucd2Cat(x5RxBuf, value);
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






		if (x5RxNewFrame && x5RxWasNotif) {
			notifCount++;
			// S-25 (CdC item 97): the content of a notification, read once per notification
			// received, at the site that decodes it. The observer of the delegate keeps one slot
			// per field, so a window answers for the LAST notification only and cannot name which
			// echo a set of fields belongs to (note 26, note 27). The print sits before the branch
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






	function x5ApplyNotif() as Void {



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
			return;
		}
		if (notifCode == X5_OPTIONS_NOTIF) {





			if (notifVal3 > 0) {
				x5FuncMode = notifVal3;
			}
			if (notifOptTag == 31) {
				x5ResNow = notifOptVal;
			}
			return;
		}
		if (notifCode != X5_CAPTURE_STATUS_NOTIF && notifCode != X5_RECORD_STATE_NOTIF) {
			return;
		}
		if (notifVal1 > 0) {
			cancelRetry();
			cancelPendingStart();
			mMessage = "Shooting";


			recState = stateStartRec;


			startRecTime = Time.now();
		} else {
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;




			recState = stateStopRec;
		}
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
		wireLine("armed", "every byte crossing the delegate is printed from now on");
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


		x5SubPhoto = null;
		x5SubVideo = null;
		x5ResNow = null;
		x5FuncMode = null;
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


		return v.toString();
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
		if (startDelayTimer != null) {
			startDelayTimer.stop();
		}
		var t = new Timer.Timer();
		startDelayTimer = t;
		if (applyBursts >= 2) {


			startPhase = 1;
			t.start(method(:onStartDelay), START_WAIT_MS, false);
		} else {
			startPhase = 0;
			t.start(method(:onStartDelay), START_DELAY_MS, false);
		}
	}

	function onStartDelay() as Void {
		startDelayTimer = null;
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
			var t = new Timer.Timer();
			startDelayTimer = t;
			t.start(method(:onStartDelay), START_WAIT_MS, false);
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
		var t = new Timer.Timer();
		startDelayTimer = t;
		t.start(method(:onStartDelay), START_WAIT_MS, false);
	}

	function fireStart() as Void {
		pendingStart = false;
		startAckSeen = false;
		startWaitCount = 0;
		startPhase = 0;
		if (startDelayTimer != null) {
			startDelayTimer.stop();
			startDelayTimer = null;
		}
		transmit(cmdStartRec);
	}

	function cancelPendingStart() as Void {
		pendingStart = false;
		startAckSeen = false;
		startWaitCount = 0;
		startPhase = 0;
		if (startDelayTimer != null) {
			startDelayTimer.stop();
			startDelayTimer = null;
		}
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
				wireLine("requestWrite issued", "chunk in flight");
			} else {
				wireLine("characteristic missing", "getCharacteristic(LBS_RW_CHAR) is null, write refused");
			}
		} catch (ex) {
			wireLine("requestWrite refused", "exception: " + ex.getErrorMessage());
			writing = false;

		}
	}


	function scheduleRetry(kind as Lang.Number) as Void {



		if (retryKind != kind) {
			retryCount = 0;
		}
		retryKind = kind;
		startRetryTimer();
	}

	function cancelRetry() as Void {
		retryKind = 0;
		retryCount = 0;
		if (retryTimer != null) {
			retryTimer.stop();
			retryTimer = null;
		}
	}

	function startRetryTimer() as Void {
		if (retryTimer != null) {
			retryTimer.stop();
		}
		retryTimer = new Timer.Timer();
		retryTimer.start(method(:onRetry), RETRY_DELAY_MS, false);
	}


	function onRetry() as Void {
		retryTimer = null;
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
		startRetryTimer();
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











		if (x5Armed && (x5IsFrame(value) || x5RxBuf != null)) {
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
			} else if (x5RxWasNotif) {


				return;
			}
		}


		if (value.size() >= 18) {




			if (responseSig.equals(value.slice(2, 7))) {





				var isRecReport = (value[7] == recReportCode) || (value[7] == recReportCodeLegacy);
				if (isRecReport && value[17] > 0x00) {

					if (recState != stateStartRec) {

					}
					cancelRetry();
					cancelPendingStart();
					mMessage = "Shooting";
					recState = stateStartRec;
					startRecTime = Time.now();


				} else if (isRecReport && value[17] == 0x00) {

					if (recState != stateStopRec) {

					}
					cancelRetry();
					cancelPendingStart();
					applyBursts = 0;
					mMessage = currentLabel + "\n" + startMessage;
					recState = stateStopRec;
				} else if (value[7] == stateBusy) {

					mMessage = "Busy...";
				} else if (value[0] == stateCmdErr) {
					cancelRetry();
					cancelPendingStart();
					mMessage = currentLabel + "\n" + startMessage;
					recState = stateStopRec;
				} else if (value[7] == ACK_CODE) {


					if (pendingStart && startPhase == 1 && !startAckSeen) {
						startAckSeen = true;
						fireStart();
					}
				} else {


				}
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
			if (!scanning) {
				scanning = true;
				device = null;
				open();






			}
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
