using Toybox.System;
using Toybox.BluetoothLowEnergy;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Application as App;
using Toybox.Position;
using Toybox.Graphics;
using Toybox.Application.Storage;

module BLEBarrel {

// const DEVICE_NAME = "ONE "; // Full name is "ONE R DV6W5S";
// const DEVICE_NAME2 = "GO2 "; 
// const DEVICE_NAME3 = "X3 "; // Full name is "X3 7MN5JB";
// const DEVICE_NAME4 = "GO3 "; 
// const DEVICE_NAME5 = "Ace ";
// const DEVICE_NAME6 = "X4 ";
// const DEVICE_NAME7 = "GO 3"; 


const LBS_SERVICE = BluetoothLowEnergy.stringToUuid("0000BE80-0000-1000-8000-00805F9B34FB");    // Camera Service entry point
const LBS_RW_CHAR = BluetoothLowEnergy.stringToUuid("0000BE81-0000-1000-8000-00805F9B34FB");    // Camera command channel
const LBS_NOTIF_CHAR = BluetoothLowEnergy.stringToUuid("0000BE82-0000-1000-8000-00805F9B34FB"); // Camera notification channel
const LBS_NOTIF_DESC = BluetoothLowEnergy.cccdUuid();
const BATT_SERVICE = BluetoothLowEnergy.stringToUuid("0000180F-0000-1000-8000-00805F9B34FB"); // standard Battery Service
const BATT_CHAR = BluetoothLowEnergy.stringToUuid("00002A19-0000-1000-8000-00805F9B34FB");    // Battery Level (1 byte %)
// b after the array is for ByteArray
const stateBusy =  0xf4; // Byte Array starts with  a "33" Error message when camera is busy
const stateCmdErr = 34; // Byte Array starts with a "34" Error message when an invalid command is sent.
const stateStandby = [0x7, 0, 0, 0, 0x5, 0, 0]b;
const responseSig =[0x00, 0x00, 0x04, 0x00, 0x00]b;
const stateStopRec = 0;
const stateStartRec = 1;
const stateStarting = 2;
const stateStopping = 3;
const SeqPos = 10;

var recState = stateStopRec;
var startRecTime = Time.now(); 
var elapsedRecTime;
var clockTime;
var lastTime = Time.now();
var GPSon = false;
var GPSaccuracy = Position.QUALITY_NOT_AVAILABLE;
var connecting = false;
var menuLevel = 1;
var deviceName ="n/a";

 
var SeqNo = 1;
var queue = [];
var cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
var cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
var cmdApply =    [0x10, 0, 0, 0, 0x4, 0, 0, 0xf, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b; // Apply settings
var cmdSet5k24 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x14, 0x18, 0x7]b; // Set video mode to 5.7k 24fps
var cmdSet5k25 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x13, 0x18, 0x7]b; // Set video mode to 5.7k 25fps
var cmdSet5k30 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x7]b; // Set video mode to 5.7k 30fps
var cmdSet8k30 =  [0x1b, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x4, 0xf8, 0x1, 0xa7, 0x01, 0x18, 0x7]b; // Set video mode to 8k 30fps
var cmdSet4k30 =  [0x17, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x0, 0x18, 0x7]b; // Set video mode to 4k 30fps
var cmdSet4k50 =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0c, 0x18, 0x7]b; // Set video mode to 4k 50fps
var cmdSet3k100 = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x7]b; // Set video mode to 3k 100fps
var cmdSetHDR =   [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x15, 0x18, 0x7]b; // Set video mode to HDR
var cmdSetTL =    [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x2]b; // Set video mode to Timelapse
var cmdSetBullet= [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x4]b; // Set video mode to Bullet time
var cmdSetPhoto =      [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetPhotoHDR =   [0x46, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x01, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00, 0x1a, 0x03, 0x27, 0x00, 0x4e]b;
var cmdSetPhotoBurst = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x0a, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x03, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetInterval =   [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetNightShot = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x2b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x04, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdHighlight = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0x8b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xde, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x68, 0x69, 0x67, 0x68, 0x6c, 0x69, 0x67, 0x68, 0x74]b;
var cmdTrackThat = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0xa8, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xf8, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x74, 0x72, 0x61, 0x63, 0x6b, 0x54, 0x68, 0x61, 0x74]b;
// X5 "network frame" protocol (see docs: soul667/insta360-x5-toolkit x5-ble-protocol.md)
var cmdTakePictureX5 = [0x10, 0, 0, 0, 0x04, 0, 0, 0x03, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0]b; // TAKE_PICTURE, empty body
const frameSyncX5 = [0x11, 0, 0, 0, 0x06, 0, 0, 0x73, 0x79, 0x4E, 0x63, 0x65, 0x4E, 0x64, 0x69, 0x6E, 0x53]b; // "syNceNdinS"
var photoSeq = -1;      // sequence number of the pending TAKE_PICTURE
var photoResult = null; // :ok / :rejected / :noShot, consumed by the UI
var lapseSeq = -1;      // sequence number of a pending START/STOP_TIMELAPSE

// Camera status for the outer widget ring (null = unknown)
var camBattery = null;   // %
var camOnPower = false;  // BatteryInfo.power_type == ADAPTER
var camPowerKnown = false; // power_type seen (0x2003 push; it crosses the 20-byte cut, the level does not)
var camBattLow = false;  // 0x2004 BATTERY_LOW push (meaning is in the header, crosses at any size)
var camShots = null;     // Options.remaining_pictures
var camRecSecs = null;   // Options.remaining_capture_time
var camFree = null;      // StorageState.free_space (bytes, Long)
var camTotal = null;     // StorageState.total_space (bytes, Long)
var camCard = null;      // CardState: 0 ok, 1 no card, 2 full, 3 bad format, 4 write-protected
var optSeq = -1;         // sequence number of the pending GET_OPTIONS
var rxBuf = null;        // reassembly of a multi-notification frame
var rxNeed = 0;
var rxAge = 0;

// --- minimal protobuf reader -------------------------------------------------
// returns [value(Long), nextPos]
function pbVarint(b, pos) {
	var v = 0l;
	var shift = 0;
	while (pos < b.size()) {
		var x = b[pos];
		pos++;
		v = v | ((x & 0x7f).toLong() << shift);
		if ((x & 0x80) == 0) { break; }
		shift += 7;
	}
	return [v, pos];
}

// Calls back field-by-field: returns array of [fieldNo, wireType, value] where value is a
// Long for varints and a ByteArray for length-delimited fields.
function pbFields(b) {
	var out = [];
	var pos = 0;
	while (pos < b.size()) {
		var t = pbVarint(b, pos);
		pos = t[1];
		var key = t[0].toNumber();
		var fno = key >> 3;
		var wt = key & 7;
		if (wt == 0) {
			var v = pbVarint(b, pos);
			pos = v[1];
			out.add([fno, wt, v[0]]);
		} else if (wt == 2) {
			var l = pbVarint(b, pos);
			pos = l[1];
			var end = pos + l[0].toNumber();
			if (end > b.size()) { end = b.size(); } // truncated by the 20-byte BLE notification limit
			out.add([fno, wt, b.slice(pos, end)]);
			pos = end;
		} else if (wt == 1) { pos += 8; }
		else if (wt == 5) { pos += 4; }
		else { break; }
	}
	return out;
}

function parseBatteryInfo(b) {
	// BatteryStatus {1 power_type, 2 level, 4 battery_type}. The camera always encodes
	// power_type, so over Connect IQ (20-byte notifications) only power_type arrives;
	// the level is read only when a longer link delivers it.
	var f = pbFields(b);
	for (var i = 0; i < f.size(); i++) {
		if (f[i][1] != 0) { continue; }
		if (f[i][0] == 1) {
			camOnPower = f[i][2] == 1;
			camPowerKnown = true;
			if (camOnPower) { camBattLow = false; }
		}
		if (f[i][0] == 2) { camBattery = f[i][2].toNumber(); }
	}
}

function parseOptions(b) {
	var f = pbFields(b);
	for (var i = 0; i < f.size(); i++) {
		var n = f[i][0];
		if (n == 9 && f[i][1] == 0) { camRecSecs = f[i][2].toNumber(); }
		else if (n == 10 && f[i][1] == 0) { camShots = f[i][2].toNumber(); }
		else if (n == 11 && f[i][1] == 2) { parseBatteryInfo(f[i][2]); }
		else if (n == 20 && f[i][1] == 2) {
			var st = pbFields(f[i][2]);
			camCard = 0;
			for (var j = 0; j < st.size(); j++) {
				if (st[j][1] != 0) { continue; }
				if (st[j][0] == 1) { camCard = st[j][2].toNumber(); }
				else if (st[j][0] == 2) { camFree = st[j][2]; }
				else if (st[j][0] == 3) { camTotal = st[j][2]; }
			}
		}
	}
}

// CameraCaptureState -> watch mode id (only states that identify a mode)
function modeForCaptureState(st) {
	var map = {1 => "v0", 2 => "v2", 3 => "p2", 7 => "v1", 13 => "v4", 18 => "v6",
		19 => "p7", 24 => "v11", 29 => "v14", 30 => "v15"};
	return map.get(st);
}

// GET_OPTIONS (0x0008): battery_info(11), remaining_capture_time(9), remaining_pictures(10), storage_state(20)
const cmdGetStatusX5 = [0x18, 0, 0, 0, 0x04, 0, 0, 0x08, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0,
	0x08, 0x0b, 0x08, 0x09, 0x08, 0x0a, 0x08, 0x14]b;

// SET_OPTIONS (0x0007) frame selecting a sub-mode: body = OptionType list + Options{field 40|41 = n}
function setSubModeX5(video, n) {
	var opt = video ? 0x29 : 0x28;           // OptionType VIDEO_SUB_MODE=41 / PHOTO_SUB_MODE=40
	var tag0 = video ? 0xc8 : 0xc0;          // Options field 41/40 -> tag bytes c8 02 / c0 02
	var body = (n == 0) ? [0x08, opt, 0x12, 0x00]b : [0x08, opt, 0x12, 0x03, tag0, 0x02, n]b;
	var f = [0, 0, 0, 0, 0x04, 0, 0, 0x07, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0]b;
	f.addAll(body);
	f[0] = f.size();
	return f;
}

function pbVar(n) {
	var out = []b;
	do {
		var x = n & 0x7f;
		n = n >> 7;
		out.add(n > 0 ? (x | 0x80) : x);
	} while (n > 0);
	return out;
}

function frameX5(code, body) {
	var f = [0, 0, 0, 0, 0x04, 0, 0, code & 0xff, (code >> 8) & 0xff, 0x02, 0, 0, 0, 0x80, 0, 0]b;
	f.addAll(body);
	f[0] = f.size();
	return f;
}

// SET_PHOTOGRAPHY_OPTIONS (0x09) {1: type, 2: {type: v}, 3: function mode}
function setPhotoOptX5(fm, type, v) {
	var inner = pbVar(type << 3);
	inner.addAll(pbVar(v));
	var b = [0x08]b; b.addAll(pbVar(type));
	b.add(0x12); b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x18); b.addAll(pbVar(fm));
	return frameX5(0x09, b);
}

// SET_TIMELAPSE_OPTIONS (0x12) {1: {2: lapse_ms}, 2: timelapse mode}
function setLapseX5(tm, ms) {
	var inner = [0x10]b; inner.addAll(pbVar(ms));
	var b = [0x0a]b; b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x10); b.addAll(pbVar(tm));
	return frameX5(0x12, b);
}

// SET_TIMELAPSE_OPTIONS (0x12) {1: {1: duration_s}, 2: timelapse mode} (Starlapse total time)
function setLapseDurX5(tm, s) {
	var inner = [0x08]b; inner.addAll(pbVar(s));
	var b = [0x0a]b; b.addAll(pbVar(inner.size())); b.addAll(inner);
	b.add(0x10); b.addAll(pbVar(tm));
	return frameX5(0x12, b);
}

// SET_ACTIVE_SENSOR (0x41): 3 both lenses (360), 1 front
function setSensorX5(v) { return frameX5(0x41, [0x08, v]b); }
function shutdownX5() { return frameX5(0xDB, []b); }   // SET_SHUTDOWN, empty body

function isX5() {
	return deviceName != null && deviceName.length() >= 3 && deviceName.substring(0, 3).equals("X5 ");
}

var currentMode = "DefaultV";
// Mode echo guard: the camera confirms each SET with a 0x2053 push ~0.3-0.5 s later. While the
// user browses or a request is in flight, only the echo of the latest request counts.
var modeReq = null;      // last mode id sent to the camera
var camMode = null;      // the camera's mode while the watch shows its Settings page
// Per-frame log lines (rx / frame / adverts). Off: the watch keeps only ~5 KB of log, and frames
// pushed connection events out within seconds.
const LOG_FRAMES = false;
var profileRegs = 0;     // BLE profile registrations (Connect IQ allows only a few per app run)
function inSettings() { return currentMode instanceof Toybox.Lang.String && currentMode.equals("set"); }
var modeHoldUntil = 0;   // System.getTimer() ms until which other 0x2053 values are not adopted

function holdMode(ms) {
	var t = System.getTimer() + ms;
	if (t > modeHoldUntil) { modeHoldUntil = t; }
}
var videoMode = true;
var currentLabel = "Default Video";
var startMessage = "";
	
(:glance)
// Ring buffer of the last 80 BLE log lines, persisted to Application.Storage
// (readable from the watch's GARMIN/Apps/DATA files over USB).
var logBuf = [];
var logDirty = false;

function logLine(str) {
	var t = System.getClockTime();
	logBuf.add(t.hour.format("%02d") + ":" + t.min.format("%02d") + ":" + t.sec.format("%02d") + " " + str);
	if (logBuf.size() > 80) { logBuf = logBuf.slice(logBuf.size() - 80, null); }
	logDirty = true;
}

function flushLog() {
	if (logDirty) {
		Storage.setValue("blelog", logBuf);
		logDirty = false;
	}
}

class BleDevice extends BluetoothLowEnergy.BleDelegate {
	var scanning = false;
	var scanTimeout = 64;
	var device = null;
	var button = 0;

	hidden function debug(str) {
		System.println("[ble] " + str);
		logLine(str);
	}

	function initialize() {
		BleDelegate.initialize();
		debug("initialize");
	}

	// Send command to BLE device
	function sendCMD(value) {
		var service;
		var ch;
		var i;
		var j;

		// check that the camera is actually connected, otherwise start a scan
		// debug("sendCMD: new scan ? " + scanning + " " + (device == null));
		if (!scanning) {
			if (device == null) {
		    	recState = stateStopRec;
				debug("[sendCMD] No device connected, starting scan");
				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
				return;
//			} else if (!device.isConnected()) {
//		    	recState = stateStopRec;
//		    	BluetoothLowEnergy.unpairDevice(device);
//				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
//				return;
			} else {
				service = device.getService(LBS_SERVICE);
				// debug("sendCMD: service null "  + (service == null));
				if (service == null) {
					// Services not discovered yet (just connected). Never unpair / rescan here:
					// that dropped a healthy link and left the camera needing a power cycle.
					debug("[sendCMD] service not ready, dropped");
					return;
				}
				if (isX5() && !linkReady) {
					debug("[sendCMD] link not ready, dropped");
					return;
				}
			}
		} else {
			return ;
		}
		
		// the ble messages are numbered in sequence (byte 10)
		SeqNo = SeqNo + 1;
		if (SeqNo > 254) {
			SeqNo = 1;
		}
		value[SeqPos] = SeqNo; 
		debug("[tx] " + hex(value, 24));

		// max message length = 20. the message has to be split into 20 bytes parts which are put in a queue.
		// each write operation has to be finished before the next one can occur.
		// the dequeuing is done in the onCharacteristicWrite function
		if (value.size() > 20) {
			j = (value.size()-1)/20;
			for (i = 0; i <= j.toNumber(); i++) { 
				queue.add(value.slice(i*20,(i+1)*20));
			} 	
		} else {
			queue.add(value);
		}
		pump();
	}

	// --- single-writer queue -----------------------------------------------------
	// The X5 reads BE81 as a byte stream of length-prefixed frames. A dropped chunk, or a
	// keep-alive slipped between two chunks of one frame, desyncs the camera's parser until
	// it is power-cycled. So: exactly one write in flight, a chunk leaves the queue only
	// once its write was accepted, and keep-alives are only sent when the queue is idle.
	var writing = false;
	var writingTicks = 0;
	var linkReady = false;
	var notifRetry = 0;   // X5: notifications enabled + sync sent; nothing is sent before

	function pump() {
		if (writing || device == null) { return; }
		if (queue.size() == 0) {
			if (battPending) {
				battPending = false;
				try {
					var bs = device.getService(BATT_SERVICE);
					if (bs != null) {
						bs.getCharacteristic(BATT_CHAR).requestRead();
						writing = true;
						writingTicks = 0;
					} else {
						debug("[batt] no battery service");
					}
				} catch (ex) {
					battPending = true; // busy, retry later
				}
			}
			return;
		}
		try {
			var svc = device.getService(LBS_SERVICE);
			if (svc == null) { return; }
			svc.getCharacteristic(LBS_RW_CHAR).requestWrite(queue[0], {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
			writing = true;
			writingTicks = 0;
			queue = queue.slice(1, queue.size());
		} catch (ex) {
			// stack busy: keep the chunk, retry from the next callback / keep-alive tick
			debug("[pump] busy, " + queue.size() + " queued");
		}
	}

	var syncOnConnect = false;
	var battPending = false;
	var battProfile = false;

	function ensureX5Mode() {
		var id = currentMode;
		if (!(id instanceof Toybox.Lang.String) || id.length() < 2 || !(id.substring(0, 1).equals("v") || id.substring(0, 1).equals("p"))) {
			adoptMode("v0");
		}
	}

	function adoptMode(id) {
		var items = $.modeListX5();
		for (var i = 0; i < items.size(); i++) {
			if (items[i][1].equals(id)) {
				currentMode = id;
				currentLabel = items[i][0];
				videoMode = id.substring(0, 1).equals("v");
				debug("[sync] mode -> " + currentLabel);
				return;
			}
		}
	}

	function requestBattery() {
		battPending = true;
		pump();
	}

	function onCharacteristicRead(ch, status, value) {
		writing = false;
		if (status == 0 && value != null && value.size() > 0) {
			camBattery = value[0];
			debug("[batt] " + camBattery + "%");
		} else {
			debug("[batt] read status " + status);
		}
		pump();
	}

	function resetLink() {
		linkReady = false;
		authStatus = -1;
		syncOnConnect = false;
		battPending = false;
		queue = [];
		writing = false;
		rxBuf = null;
		photoSeq = -1; lapseSeq = -1; optSeq = -1; capSeq = -1; storSeq = -1; setSeq = -1;
	}

	// Whole X5 message frames (after reassembly).
	function onFrameX5(f) {
		if (f.size() < 16 || f[4] != 0x04) { return; }
		var code = f[7] | (f[8] << 8);
		var body = f.slice(16, f.size());
		var total = f[0] | (f[1] << 8);
		if (LOG_FRAMES) { debug("[frame] code=" + code.format("%04x") + " seq=" + f[10] + " total=" + total + " got=" + f.size() + " body=" + hex(body, 8)); }
		if (authSeq >= 0 && f[10] == authSeq && code < 0x1000) {
			// CheckAuthorizationResp {1: status}: 0 AUTHORIZED (field omitted), 1 UNAUTHORIZED, 2 BUSY,
			// 3/4/5/6 connected by another phone/watch/cyclocomputer/remote, 7 sleeping
			var st = 0;
			var t = pbFields(body);
			for (var i = 0; i < t.size(); i++) { if (t[i][0] == 1 && t[i][1] == 0) { st = t[i][2].toNumber(); } }
			authStatus = st;
			debug("[auth] reply code " + code + " status=" + st + (st == 0 ? " AUTHORIZED" : (st == 1 ? " UNAUTHORIZED (camera asks)" : "")));
			authSeq = -1;
		}
		if (code == 0x2011) {
			// AUTHORIZATION_RESULT (user answered the camera's "allow" prompt) {1: 0 SUCCESS, 1 REJECT, 2 TIMEOUT, 3 BUSY}
			var r = -1;
			var t2 = pbFields(body);
			r = 0;
			for (var i = 0; i < t2.size(); i++) { if (t2[i][0] == 1 && t2[i][1] == 0) { r = t2[i][2].toNumber(); } }
			authStatus = (r == 0) ? 0 : 1;
			debug("[auth] camera answered prompt: " + (r == 0 ? "ALLOWED" : (r == 1 ? "REJECTED" : "result " + r)));
		}
		if (code == 200 && optSeq >= 0 && f[10] == optSeq) {
			optSeq = -1;
			var top = pbFields(body);
			for (var i = 0; i < top.size(); i++) {
				if (top[i][0] == 2 && top[i][1] == 2) { parseOptions(top[i][2]); }
			}
			debug("[status] bat=" + camBattery + " shots=" + camShots + " rec=" + camRecSecs + " card=" + camCard);
		} else if (setSeq >= 0 && f[10] == setSeq && (code == 200 || code == 0x190)) {
			debug("[set] " + setKey + " -> " + code);
			if (code == 200) {
				Settings.acked[setKey] = true;
			} else {
				Settings.vals.remove(setKey);
				Settings.acked.remove(setKey);
				setResult = :rejected;
			}
			setSeq = -1;
		} else if (code == 200 && storSeq >= 0 && f[10] == storSeq) {
			// GET_STORAGE reply {1: StorageState{1 card_state, 2 free, 3 total, 4 location}}, 36 B.
			// Over Connect IQ it is cut after card_state (frame byte 19); the sizes never arrive.
			storSeq = -1;
			var top = pbFields(body);
			for (var i = 0; i < top.size(); i++) {
				if (top[i][0] == 1 && top[i][1] == 2) {
					var st = pbFields(top[i][2]);
					camCard = 0;
					for (var j = 0; j < st.size(); j++) {
						if (st[j][1] != 0) { continue; }
						if (st[j][0] == 1) { camCard = st[j][2].toNumber(); }
						else if (st[j][0] == 2) { camFree = st[j][2]; }
						else if (st[j][0] == 3) { camTotal = st[j][2]; }
					}
				}
			}
			debug("[card] connect read state=" + camCard);
		} else if (code == 200 && capSeq >= 0 && f[10] == capSeq) {
			capSeq = -1;
			var st = -1;
			var top = pbFields(body);
			for (var i = 0; i < top.size(); i++) {
				if (top[i][0] == 1 && top[i][1] == 2) {
					var inner = pbFields(top[i][2]);
					st = 0;
					for (var j = 0; j < inner.size(); j++) {
						if (inner[j][0] == 1 && inner[j][1] == 0) { st = inner[j][2].toNumber(); }
					}
				}
			}
			debug("[cap] state=" + st + " rec=" + recState + (syncOnConnect ? " (connect sync)" : ""));
			if (syncOnConnect) {
				syncOnConnect = false;
				var id = (st > 0) ? modeForCaptureState(st) : null;
				if (id != null) {
					// camera is already capturing: follow it
					adoptMode(id);
					recState = stateStartRec;
					startRecTime = Time.now();
				} else {
					// camera idle: make it match the mode the watch shows
					ensureX5Mode();
					$.sendCurrentMode(self);
				}
				return;
			}
			if (st > 0 && recState == stateStarting && photoSeq < 0) {
				recState = stateStartRec;
				startRecTime = Time.now();
				lapseSeq = -1;
			} else if (st == 0 && recState == stateStopping) {
				recState = stateStopRec;
				lapseSeq = -1;
			}
		} else if (code == 0x2010) {
			// CAPTURE_STATUS push {1: state}: confirms a pending start / stop, never restarts one
			var t = pbFields(body);
			var st = -1;
			for (var i = 0; i < t.size(); i++) {
				if (t[i][0] == 1 && t[i][1] == 0) { st = t[i][2].toNumber(); }
			}
			if (st < 0 && body.size() == 0) { st = 0; }   // empty body = field 1 is 0 (idle)
			debug("[cap] push state=" + st + " rec=" + recState);
			if (st > 0 && recState == stateStarting && photoSeq < 0) {
				recState = stateStartRec;
				startRecTime = Time.now();
				lapseSeq = -1;
			} else if (st == 0 && recState == stateStopping && photoSeq < 0) {
				recState = stateStopRec;
				lapseSeq = -1;
			}
		} else if (code == 0x2053) {
			// CAM_SUBMODE_CHANGE: {1: photo sub-mode, 2: video sub-mode}, 100 = none.
			// Sent when the mode changes, also when it is changed on the camera itself.
			var t = pbFields(body);
			var ph = 100; var vi = 100;
			for (var i = 0; i < t.size(); i++) {
				if (t[i][1] != 0) { continue; }
				if (t[i][0] == 1) { ph = t[i][2].toNumber(); }
				if (t[i][0] == 2) { vi = t[i][2].toNumber(); }
			}
			var id = (ph != 100) ? "p" + ph : ((vi != 100) ? "v" + vi : null);
			debug("[mode] camera says photo=" + ph + " video=" + vi + " -> " + id);
			if (id != null && modeReq != null && id.equals(modeReq)) {
				modeReq = null;      // our latest request confirmed; the hold runs out by itself
				return;
			}
			if (System.getTimer() < modeHoldUntil) {
				debug("[mode] stale echo ignored");
				return;
			}
			if (id != null && inSettings()) { camMode = id; return; }   // stay on the Settings page
			if (id != null && !id.equals(currentMode) && recState == stateStopRec) {
				adoptMode(id);
				WatchUi.requestUpdate();
			}
		} else if (code == 0x2003 || code == 0x2004) { // battery update / low
			debug("[batt] notify " + code.format("%04x") + " " + hex(body, 12));
			if (code == 0x2004) { camBattLow = true; }
			var t = pbFields(body);
			for (var i = 0; i < t.size(); i++) {
				if (t[i][0] == 1 && t[i][1] == 2) { parseBatteryInfo(t[i][2]); }
			}
		} else if (code == 0x2006) {
			// NotificationCardUpdate {1 state, 2 location}: 20 bytes, crosses whole. No sizes.
			var t = pbFields(body);
			var st = 0;
			for (var i = 0; i < t.size(); i++) {
				if (t[i][0] == 1 && t[i][1] == 0) { st = t[i][2].toNumber(); }
			}
			camCard = st;
			debug("[card] state=" + st);
		}
	}

	// GET_CURRENT_CAPTURE_STATUS (0x0F): reply body 0a <len> 08 <state> ... ; state != 0 = capturing
	var capSeq = -1;
	function queryCaptureX5() {
		if (device == null) { return; }
		sendCMD([0x10, 0, 0, 0, 0x04, 0, 0, 0x0f, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0]b);
		capSeq = SeqNo;
	}

	// A settings write from the watch; the reply (200 / 400) marks it acked or rejected.
	var setSeq = -1;
	var setKey = null;
	var setResult = null;   // :rejected, consumed by the UI
	function sendSettingX5(frames, key) {
		if (device == null) { return; }
		for (var i = 0; i < frames.size(); i++) { sendCMD(frames[i]); }
		setSeq = SeqNo;   // the last frame's reply decides
		setKey = key;
	}

	// GET_STORAGE (0xA6) body {1: location 0 = SD card}: card state at connect.
	var storSeq = -1;
	function queryStorageX5() {
		if (device == null) { return; }
		sendCMD([0x12, 0, 0, 0, 0x04, 0, 0, 0xa6, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x08, 0x00]b);
		storSeq = SeqNo;
	}

	// CHECK_AUTHORIZATION (0x27) as a Garmin watch: {1: id string, 2: initiator_type = 17 WATCH_GARMINOS}.
	// The phone app sends this first (with type 2 = Android). Experiment: the camera has watch-specific
	// replies (CAMERA_NOTIFICATION_WATCH_RES 0x2065) that may fit Connect IQ's 20-byte notifications.
	function checkAuthX5() {
		var id = "garmin-remote";
		var uid = System.getDeviceSettings().uniqueIdentifier;
		if (uid != null && uid.length() >= 12) { id = uid.substring(0, 12); }
		var f = [0, 0, 0, 0, 0x04, 0, 0, 0x27, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x0a, id.length()]b;
		f.addAll(id.toUtf8Array());
		f.addAll([0x10, 0x11]b);
		f[0] = f.size();
		sendCMD(f);
		authSeq = SeqNo;
		debug("[auth] CHECK_AUTHORIZATION as WATCH_GARMINOS seq=" + SeqNo);
	}
	var authSeq = -1;
	var authStatus = -1;   // -1 unknown, 0 authorized, 1 waiting for "allow" on the camera

	function queryStatusX5() {
		if (device == null) { return; }
		sendCMD(cmdGetStatusX5);
		optSeq = SeqNo;
	}

	// Connect IQ caps notifications at 20 bytes and the X5 does not fragment: each notification
	// is one frame, possibly cut short. Parse what arrived.
	function reassembleX5(value) {
		if (value.size() >= 16 && value[4] == 0x04) { onFrameX5(value); }
	}

	function onCharacteristicChanged(ch, value) {
		if (isX5()) { reassembleX5(value); }
		if (LOG_FRAMES && value.size() != 7) { debug("[rx] " + value.size() + "b " + hex(value, 40)); } // skip 1 Hz keep-alives
		// X5 response: [len u32][04 00 00][code u16][02][seq u24][80|f4][00 00]
		if (value.size() >= 16 && value[4] == 0x04 && photoSeq >= 0 && value[10] == photoSeq) {
			var code = value[7] | (value[8] << 8);
			debug("[photo] response code " + code);
			var total = value[0] | (value[1] << 8);
			// A real shot answers 200 with a TakePictureResponse (file path); a bare 200 means nothing was taken.
			photoResult = (code != 200) ? :rejected : ((total > 16) ? :ok : :noShot);
			debug("[photo] total=" + total + " -> " + photoResult);
			photoSeq = -1;
			recState = stateStopRec;
		}
		if (value.size() >= 16 && value[4] == 0x04 && lapseSeq >= 0 && value[10] == lapseSeq) {
			var lcode = value[7] | (value[8] << 8);
			debug("[lapse] response code " + lcode);
			lapseSeq = -1;
			if (lcode == 200 && recState == stateStarting) {
				recState = stateStartRec;
				startRecTime = Time.now();
			} else if (lcode == 200) {
				recState = stateStopRec;
			} else {
				recState = (recState == stateStarting) ? stateStopRec : stateStartRec;
				photoResult = :rejected;
			}
		}
		// except for keep alive mesages that are 7 bytes long all others are at least 16 bytes long
		if (value.size() >=  18) {
		// messages are cut into 20 bytes max length (but can be shorter)
		// The necessary info are in the first 20 bytes, the rest is ignored
		// 2 first bytes is the length of the message (little endian). 
		// followed by 00 00 04 00 00. Check for this value
		  if (responseSig.equals(value.slice(2,7))) {
			// debug("[onCharChanged] " + ch.getUuid() + " " + value + " Size: " + value.size()); 
			// the 8th byte is the "command" code
			// Check to see if we got a Stop or Start recording event. 
			// Command byte == 0x10 position 17 is >0 = start. 0=end.
			// Legacy cameras only: on the X5 the code is 16 bits and 0x2010 (capture status push,
			// sent again while the camera finishes a file) matched this low-byte check and
			// restarted the recording timer. X5 frames are handled in onFrameX5.
			if (!isX5() and (value[7] == 0x10) and (value[17] > 0x00) and videoMode) {
				// debug("Start Shooting");
				mMessage = "Shooting";
				recState = stateStartRec;
				startRecTime = Time.now();
//				WatchUi.pushView(new ViewData(BleDevice2), new InputDelegate(BleDevice2), WatchUi.SLIDE_IMMEDIATE);
				
			} else 	if (!isX5() and (value[7] == 0x10) and (value[17] == 0x00) and photoSeq < 0 and lapseSeq < 0) {
				// debug("Stop Shoot");
				mMessage = currentLabel + "\n" + startMessage;
				recState = stateStopRec;
			} else if (stateBusy.equals(value[7])) {
				// sendCMD(cmdStopRec);
				mMessage = "Busy...";
   			} else if (stateCmdErr.equals(value[0])) {
				mMessage = currentLabel + "\n" + startMessage;
				recState = stateStopRec;
			} else {
				 if (LOG_FRAMES) { debug("Unknown Response " + value); }
				// mMessage = "-";
			}
		  }
		} 	
		
		//second guess elapsed recording time (don't know how to decode the protbuf status)
		if (recState == stateStartRec) {
			clockTime = Time.now();
			elapsedRecTime = clockTime.subtract(startRecTime);
			mMessage = currentLabel + "\n" + toTimeString(elapsedRecTime.value()); 
		} else {
			// mMessage = "Stopped\n" + currentLabel + "\n" + startMessage;
		}
		WatchUi.requestUpdate();
	}
	
	function onCharacteristicWrite(ch, st) {
		if (st != 0) { debug("[onCharWrite] status " + st); }
		writing = false;
		pump();
	}
	
	function hex(b, max) {
		var n = b.size() < max ? b.size() : max;
		var out = "";
		for (var i = 0; i < n; i++) { out += b[i].format("%02x"); }
		return out;
	}

	function toTimeString(seconds) {
		var hours = seconds/3600;
    	var min = (seconds - hours*3600)/60;
    	var sec = (seconds - hours*3600 - min*60);
    	
    	return ("" + hours + ":" + min.format("%02d") + ":" + sec.format("%02d"));
	}
	

	function onProfileRegister(uuid, status) {
		debug("registered: " + uuid + " " + status);
	}

	// Called by open() function, part of initialization process.
	function registerProfiles() {
		var profile = {
			:uuid => LBS_SERVICE,
			:characteristics => [{
				:uuid => LBS_RW_CHAR,
                        }, {
				:uuid => LBS_NOTIF_CHAR,
				:descriptors => [LBS_NOTIF_DESC],
			}]
		};
		if (profileRegs > 0) { return; }   // once per app run: a second registration fails later
		try {
			profileRegs++;
			BluetoothLowEnergy.registerProfile(profile);
		} catch (ex) {
			    debug("[sendCMD] exception: " + ex.getErrorMessage());
		}

	}

	function onScanStateChange(scanState, status) {
		debug("scanstate: " + scanState + " " + status);

		if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
			scanning = true;
			mMessage = "Scanning...\n" + scanTimeout;
			WatchUi.requestUpdate() ;
			
		} else {
			scanning = false;
			scanTimeout = 64;
			if (device == null) {
				mMessage = startMessage + "\nto scan";
			} else {
				mMessage = currentLabel + "\n" + startMessage;
			}
			WatchUi.requestUpdate() ;
		}
	}

	function onConnectedStateChanged(dev, state) {
		// debug("connected: " + dev.getName() + " " + dev.isConnected() + " " + state);
		mMessage = currentLabel + "\n" + startMessage;
		WatchUi.requestUpdate();
		if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
			debug("[link] connected");
			connecting = false;
			debug("[onCSC] scanning OFF");
			if (scanning) {
			try {
				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
			} catch (ex) {
			    debug("[onConStateChg] OFF exception: " + ex.getErrorMessage());
		    }
			
				scanning = false;
			}
			device = dev;
			resetLink();
			enableNotifications();
		} else {
			// Link lost (camera standby, out of range). Do NOT re-run open(): that registered the
			// profile again (Connect IQ refuses it after a few times, then no reconnect works) and
			// reloaded the recording state saved at the last close. Release the old pairing, so
			// the system does not reconnect it while we scan and pair again, then scan.
			debug("[link] disconnected");
			resetLink();
			if (device != null) {
				try { BluetoothLowEnergy.unpairDevice(device); } catch (ex) { debug("[link] unpair: " + ex.getErrorMessage()); }
			}
			device = null;
			connecting = false;
			if (!scanning) {
				scanning = true;
				try {
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
				} catch (ex) {
					debug("[link] scan: " + ex.getErrorMessage());
				}
			}
		}
	}

	// Subscribe to the camera's notification channel (CCCD = 0x0001). Without this the
	// camera never reports start/stop, so the watch can't confirm anything.
	function enableNotifications() {
		try {
			var svc = device.getService(LBS_SERVICE);
			if (svc == null) { debug("[notif] no service"); return; }
			var ch = svc.getCharacteristic(LBS_NOTIF_CHAR);
			if (ch == null) { debug("[notif] no notif char"); return; }
			var cccd = ch.getDescriptor(BluetoothLowEnergy.cccdUuid());
			if (cccd == null) { debug("[notif] no cccd"); return; }
			cccd.requestWrite([0x01, 0x00]b);
			debug("[notif] cccd write requested");
		} catch (ex) {
			debug("[notif] exception: " + ex.getErrorMessage());
		}
	}

	function onDescriptorWrite(descriptor, status) {
		debug("[notif] cccd write status " + status);
		if (isX5() && status == 0) {
			sendRaw(frameSyncX5);
			linkReady = true;
			debug("[x5] sync sent, link ready");
			syncOnConnect = true;
			checkAuthX5();
			queryCaptureX5();
			queryStorageX5();
		}
	}

	// Queue a pre-built frame (no sequence rewrite) and kick the write chain.
	function sendRaw(frame) {
		if (device == null) { return; }
		queue.add(frame);
		pump();
	}

	// Keep-alive frame; also kicks the queue (onCharacteristicWrite drains it).
	// Called every 2 s by the view. Sends a keep-alive only when nothing else is queued,
	// and recovers if a write callback never came back.
	function keepAlive() {
		if (device == null) { return; }
		if (isX5() && !linkReady) {
			// services may not have been discovered at connect time: retry the CCCD write
			notifRetry++;
			if (notifRetry % 2 == 0) { enableNotifications(); }
			return;
		}
		if (writing) {
			writingTicks++;
			if (writingTicks >= 2) { debug("[pump] write callback lost, resuming"); writing = false; }
		}
		if (rxBuf != null) {
			rxAge++;
			if (rxAge >= 2) { debug("[rx] dropping incomplete frame"); rxBuf = null; }
		}
		if (queue.size() == 0 && !writing) {
			queue.add(stateStandby);
		}
		pump();
	}

	// X5: START_CAPTURE fires whatever mode the camera is in; in photo modes it takes the shot.
	// Single / Burst: TAKE_PICTURE with the fields the Insta360 app sends
	// (raw_capture_type=3, focusSensor=3; mode=BURST for burst). The GPS block is optional.
	function shutterX5() {
		var burst = currentMode.equals("p3");
		var f = burst
			? [0x16, 0, 0, 0, 0x04, 0, 0, 0x03, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x08, 0x03, 0x20, 0x03, 0x30, 0x03]b
			: [0x14, 0, 0, 0, 0x04, 0, 0, 0x03, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x20, 0x03, 0x30, 0x03]b;
		sendCMD(f);
		photoSeq = SeqNo;
		photoResult = null;
		debug("[photo] TAKE_PICTURE seq=" + SeqNo + (burst ? " burst" : ""));
	}

	// Interval / Starlapse: START_TIMELAPSE (0x16) / STOP_TIMELAPSE (0x17), body TimelapseMode
	// (2 = interval shooting, 5 = starlapse shooting).
	function lapseX5(start) {
		var m = currentMode.equals("p7") ? 0x05 : 0x02;
		sendCMD([0x12, 0, 0, 0, 0x04, 0, 0, start ? 0x16 : 0x17, 0x00, 0x02, 0, 0, 0, 0x80, 0, 0, 0x08, m]b);
		lapseSeq = SeqNo;
		debug("[lapse] " + (start ? "START" : "STOP") + " mode=" + m + " seq=" + SeqNo);
	}

	// Interval / Starlapse run like a recording (timer on screen, START again to stop).
	function isTimedPhotoX5() {
		return currentMode.equals("p2") || currentMode.equals("p7");
	}

	function takePictureX5() {
		sendCMD(cmdTakePictureX5);
		photoSeq = SeqNo;
		photoResult = null;
		debug("[photo] TAKE_PICTURE seq=" + SeqNo);
	}

	private function connect(result) {
		// debug("[connect] " + result.getDeviceName());
		try {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
			// debug("[connect] scanning OFF");
		} catch (ex) {
		    debug("[connect] scan OFF exception: " + ex.getErrorMessage());
		}
		debug("[link] pairing, rssi " + result.getRssi());
		try {
			device = BluetoothLowEnergy.pairDevice(result);
		} catch (ex) {
		    debug("[Connect] Pair exception: " + ex.getErrorMessage());
		}
		// debug("[connect] is Connected " + device.isConnected());
			
	}

//	private function dumpUuids(iter) {
//		for (var x = iter.next(); x != null; x = iter.next()) {
//			debug("uuid: " + x);
//		}
//		return false;
//	}

	function onScanResults(scanResults) {
//		debug("scan results");
		var uuids;
		// var name;
		// var rssi;
		var iter;

		for (var result = scanResults.next(); result != null; result = scanResults.next()) {
			uuids = result.getServiceUuids();
			deviceName = result.getDeviceName();
			if (deviceName != null && deviceName.length() >= 3 && deviceName.substring(0, 3).equals("X5 ")) {
				var raw = result.getRawData();
				if (LOG_FRAMES && raw != null) { debug("[adv] " + hex(raw, 40)); }
			}
			// rssi = result.getRssi();

			// debug("[onScanResults] device: " + name + " rssi: " + rssi);
//			dumpUuids(uuids);

			//search for an insta360 device based on service UUID
			for (iter = uuids.next(); iter != null; iter = uuids.next()) {
//				debug("uuid: " + iter);
				menuLevel = 0;
				if (iter.equals(LBS_SERVICE) and (deviceName != null)) {
					// debug("Connect " + iter);
					if (deviceName.substring(0,3).equals("ONE")) {
						menuLevel = 1;
					}
					if (deviceName.substring(0,3).equals("X3 ")) {
						menuLevel = 1;
					}

					if (deviceName.substring(0,3).equals("X4 ")) {
						menuLevel = 2;
					}
					if (deviceName.substring(0,3).equals("X5 ")) {
						menuLevel = 2;
					}
					connect(result);
					return;
				}
			}

//			if (name != null) {
//				// debug ("device name: [" + name.substring(0,4) +"]");
//				if (DEVICE_NAME.equals(name.substring(0,4)) or 
//					DEVICE_NAME2.equals(name.substring(0,4)) or
//					DEVICE_NAME3.equals(name.substring(0,3)) or
//					DEVICE_NAME4.equals(name.substring(0,4)) or
//					DEVICE_NAME5.equals(name.substring(0,4)) or
//					DEVICE_NAME6.equals(name.substring(0,3)) or
//					DEVICE_NAME7.equals(name.substring(0,4))) {
//
//						//For Ace & Ace pro devices, only "Default Video" mode is supported. 
//						if (DEVICE_NAME5.equals(name.substring(0,4)) or 
//						    DEVICE_NAME7.equals(name.substring(0,4))) {
//							menuLevel = 0;
//						}
//
//						try {
//							Storage.setValue("device", result);
//						} catch (ex) {
//			    			debug("[onScanResult] storage write exception " + ex.getErrorMessage());
//						}
//						connect(result);
//					return;
//				}
//			}
			scanTimeout--;
			mMessage = "Scanning...\n" + scanTimeout;
			WatchUi.requestUpdate() ;
			
			if (scanTimeout == 0) {
				debug("[onSR] Scan timeout, scan OFF");
				try {
					BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
				} catch (ex) {
			    	debug("[onConStateChg] OFF exception: " + ex.getErrorMessage());
		    	}
			}
		}
	}

	function toDouble(single) {
		// convert a 32bit float to 64-bit, signed, in a bitArray. 
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
		// Need to convert to float 64bit, but not directly supported by Connect IQ.
		// convert back and forth from 32bit float to 32bit INT to have a "bitwise" representation
		t32.encodeNumber(single,Lang.NUMBER_FORMAT_FLOAT,null);
		tb = t32.decodeNumber(NUMBER_FORMAT_UINT32, null);
		// get the sign
		ts = tb & 0x80000000;
		// get the exponent part 
		te = tb & 0x7f800000;
		te >>= 23;
		// new 64bit based bias
		bias = te - 127 + 1023;
		bias <<= 52;
		// get the mantisse part and shift it 
		tm = tb & 0x007fffff;
		tm <<= 29;
		// add the new bias to the mantis and the sign
		ts <<= 32;
		tb = ts + bias + tm;
		// cut the new value in 2 32bit chunks
		tb1 = tb;
		tb1 >>= 32;
		d1.encodeNumber(tb1, NUMBER_FORMAT_UINT32, null);
		tb1 <<=32;
		tb2 = tb - tb1;
		d2.encodeNumber(tb2, NUMBER_FORMAT_UINT32, null);
		// debug ("[toDouble] " + tb.format("%x"));
		// build the final bitArray, little endian
		double.addAll(d2);
		double.addAll(d1);
		return double;
	}

	function sendPosition(info) {
		// Build a byte array with the following info in HEX format, all Little endian
		// byte position - value
		// 00-13 47 00 00 00 04 00 00 35 00 02 ff 00 00 80 
		// 14-17 00 00 0a 35 ?
		// 18-21 UX Epoch (int 32)
		// 22-25 00 00 00 00 
		// 26-28 00 00 41 ?
		// 29-36 Latitude (double float)
		// 37    N / S (ASCII)
		// 38-45 Longitude (double float)
		// 46    E / W (ASCII) 
		// 47-54 Speed meters per seconds (double float) 
		// 55-62 Heading, degrees  (double float) 
		// 63-70 Altitude Meters (double float)


		var header = [0x47, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x35, 0x00, 0x02, 0xff, 0x00, 0x00, 0x80, 0x00, 0x00, 0x0a, 0x35]b;
		var uxEpoch = info.when;
		var filler = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41];
		var location = [0,0];
		var latitude = 0;
		var longitude = 0;
		var speed = info.speed;
		var heading = 0; 
		var altitude = info.altitude;
		var temp32 = new[4]b;
		var temp64 = new[8]b;
		var sector = 0x4e;
		
		GPSaccuracy = info.accuracy;
		WatchUi.requestUpdate();
		// debug("[sendPosition] Accuracy: " + GPSaccuracy); 
		

		if ((device == null) or (recState != stateStartRec)) { return; }
		
		if (info.position != null) {
			location = info.position.toDegrees();
			latitude = location[0];
			longitude = location[1];
			
		} else { return; }
		//heading is provided in radians, convert to degrees
		if (info.heading != null) {
			heading = info.heading*180/Math.PI;
			if (heading < 0) {
				heading = 360 + heading;
			}
		} else { return; }
		
		if (speed == null) {
			speed = 0;
		}
		
		// debug ("[onPosition] " + uxEpoch.value() + " " + latitude + " " + longitude + " " + speed + " " + heading + " " + altitude);

		// Video & Photo telemetry are encoded differently.
		if (videoMode) {
			// encode timestamp
			temp32.encodeNumber(uxEpoch.value(),Lang.NUMBER_FORMAT_UINT32,null);
			header.addAll(temp32);
			header.addAll(filler);
			// North or South
			if (latitude >= 0) {
				sector = 0x4e; // ASCII 'N'
			} else {
				sector = 0x53; // ASCII 'S'
			}
			// encode latitude
			temp64 = toDouble(latitude.abs());
			header.addAll(temp64);
			header.add(sector);
			// East or West
			if (longitude >= 0) {
				sector = 0x45; // ASCII 'E'
			} else {
				sector = 0x57; // ASCII 'W'
			}
			// encode longitude
			temp64 = toDouble(longitude.abs());
			header.addAll(temp64);
			header.add(sector);
			// encode speed
			temp64 = toDouble(speed.abs());
			header.addAll(temp64);
			
			// encode heading
			temp64 = toDouble(heading);
			header.addAll(temp64);
			
			// encode altitude		
			temp64 = toDouble(altitude.abs());
			header.addAll(temp64);
	
			// debug ("hex " +header.size() +" "+ header); 
			sendCMD(header);
		} 
	}
	
	
	// Storage cannot hold ByteArrays: persist them as {"b"=>[numbers]}.
	function toStore(v) {
		if (v instanceof Toybox.Lang.ByteArray) {
			var a = new [v.size()];
			for (var i = 0; i < v.size(); i++) { a[i] = v[i]; }
			return {"b" => a};
		}
		return v;
	}

	function fromStore(v) {
		if (v instanceof Toybox.Lang.Dictionary && v.hasKey("b")) {
			var a = v["b"];
			var b = new [a.size()]b;
			for (var i = 0; i < a.size(); i++) { b[i] = a[i]; }
			return b;
		}
		return v;
	}

	function open() {
		var temp;

		// Check if watch is touch screen capable
		if (System.getDeviceSettings().isTouchScreen) {
			startMessage = "Tap Here";
		} else {
			startMessage = "Press Start";
		}
		// debug("open");
		// Load last state of app
		recState = Storage.getValue("recState");
		if (recState == null) {
			recState = stateStopRec;
		}
		currentMode = fromStore(Storage.getValue("currentMode"));
		currentLabel = Storage.getValue("currentLabel");
		if (currentMode == null) {
			currentMode = "DefaultV";
			currentLabel = "Default Video";
		}
		lastTime = Time.now();
		temp = Storage.getValue("startRecTime");
		startRecTime = (temp != null) ? new Time.Moment(temp) : Time.now();
		temp = fromStore(Storage.getValue("cmdStartRec"));
		if (temp != null) {
			cmdStartRec = temp;
		}
		
		temp = fromStore(Storage.getValue("cmdStopRec"));
		if (temp != null) {
			cmdStopRec = temp;
		}
		GPSon = Storage.getValue("GPSon");
		if (GPSon == null) {
			GPSon = false;
		}
		// Bluetooth initialisation
		debug("[open] Start Scan, CIQ V " + System.getDeviceSettings().monkeyVersion);
		registerProfiles();
		BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
		// try to connect directly to the last known device.
//		result = Storage.getValue("device");
//		if (result != null) {
//			debug ("[open] direct connect");
//			connect(result);
//		} 
				
	}

	function close() {
		debug("close");
		flushLog();
		// Save current state of app 
		Storage.setValue("recState", recState);
		Storage.setValue("startRecTime", startRecTime.value());
		Storage.setValue("currentMode", toStore(currentMode));
		Storage.setValue("currentLabel", currentLabel);
		Storage.setValue("cmdStartRec", toStore(cmdStartRec));
		Storage.setValue("cmdStopRec", toStore(cmdStopRec));
		Storage.setValue("GPSon", GPSon);
		if (scanning) {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
		}
		if (device) {
			BluetoothLowEnergy.unpairDevice(device);
		}
		Position.enableLocationEvents(Position.LOCATION_DISABLE,null);
	}
}


}
