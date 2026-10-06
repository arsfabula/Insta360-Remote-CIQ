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
// b after the array is for ByteArray
const stateBusy =  0xf4; // Byte Array starts with  a "33" Error message when camera is busy
const stateCmdErr = 34; // Byte Array starts with a "34" Error message when an invalid command is sent.
const stateStandby = [0x7, 0, 0, 0, 0x5, 0, 0]b;
const responseSig =[0x00, 0x00, 0x04, 0x00, 0x00]b;
const stateStopRec = 0;
const stateStartRec = 1;
const stateStarting = 2;
const stateStopping = 3;
// Recording-state reports carry the command id shifted left by 4 (the high
// nibble marks the frame as a response): cmdStartRec uses id 4, so the camera
// answers 0x40. 0x10 is the older encoding and is still accepted.
// The flag is byte 17: >0 means "recording", 0 means "stopped".
const recReportCode = 0x40;
const recReportCodeLegacy = 0x10;
const SeqPos = 10;
// The camera silently drops a start/stop burst that races BLE connection
// setup, so the frame never gets a "rec report" acknowledgement. If none
// arrives within this window the sequence is resent, up to RETRY_MAX times.
const RETRY_DELAY_MS = 2500;
const RETRY_MAX = 3;
const retryKindStart = 1;
const retryKindStop = 2;
// The camera only accepts the recording start if the preceding mode+apply
// pair has already been acknowledged; sending mode+apply+start as one burst
// races that and the start is dropped. The mode/apply frames are queued
// immediately, then the start waits until their acknowledgement (byte 7 ==
// 0xC8) is observed. START_WAIT_MAX caps the wait if no ack ever arrives.
const ACK_CODE = 0xC8;
// The camera accepts a start only if it has already seen a mode+apply burst
// that is NOT followed by a start, and then gets a second mode+apply burst
// carrying the start. The menu path does exactly that; a single direct burst
// gets acked but its start is ignored. So a direct start pauses, then emits
// the second burst.
const START_DELAY_MS = 1200;
const START_WAIT_MS = 400;
const START_WAIT_MAX = 3;

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


var SeqNo as Lang.Number = 1;
// Lang.Array (untyped): generic type params must be primitives/symbols.
// Lang.ByteArray is a class, so Lang.Array<Lang.ByteArray> builds an invalid
// runtime type descriptor -> "Illegal Access (Out of Bounds)" at module init.
var queue as Lang.Array = [];
var cmdStartRec as Lang.ByteArray = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;  // Start video Recording commmand
var cmdStopRec as Lang.ByteArray =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b; // Stop recording command
var cmdApply as Lang.ByteArray =    [0x10, 0, 0, 0, 0x4, 0, 0, 0xf, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0]b; // Apply settings
var cmdSet5k24 as Lang.ByteArray =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x14, 0x18, 0x7]b; // Set video mode to 5.7k 24fps
var cmdSet5k25 as Lang.ByteArray =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x13, 0x18, 0x7]b; // Set video mode to 5.7k 25fps
var cmdSet5k30 as Lang.ByteArray =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x7]b; // Set video mode to 5.7k 30fps
var cmdSet8k30 as Lang.ByteArray =  [0x1b, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x4, 0xf8, 0x1, 0xa7, 0x01, 0x18, 0x7]b; // Set video mode to 8k 30fps
var cmdSet4k30 as Lang.ByteArray =  [0x17, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x0, 0x18, 0x7]b; // Set video mode to 4k 30fps
var cmdSet4k50 as Lang.ByteArray =  [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0c, 0x18, 0x7]b; // Set video mode to 4k 50fps
var cmdSet3k100 as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x7]b; // Set video mode to 3k 100fps
var cmdSetHDR as Lang.ByteArray =   [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x15, 0x18, 0x7]b; // Set video mode to HDR
var cmdSetTL as Lang.ByteArray =    [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0a, 0x18, 0x2]b; // Set video mode to Timelapse
var cmdSetBullet as Lang.ByteArray = [0x1a, 0, 0, 0, 0x4, 0, 0, 0x9, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0xa, 0x1, 0x1f, 0x12, 0x3, 0xf8, 0x1, 0x0d, 0x18, 0x4]b; // Set video mode to Bullet time
var cmdSetPhoto as Lang.ByteArray =      [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetPhotoHDR as Lang.ByteArray =   [0x46, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x01, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00, 0x1a, 0x03, 0x27, 0x00, 0x4e]b;
var cmdSetPhotoBurst as Lang.ByteArray = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x0a, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x03, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetInterval as Lang.ByteArray =   [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdSetNightShot as Lang.ByteArray = [0x41, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0x2b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0x04, 0x12, 0x2d, 0x5a, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
var cmdHighlight as Lang.ByteArray = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0x8b, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xde, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x68, 0x69, 0x67, 0x68, 0x6c, 0x69, 0x67, 0x68, 0x74]b;
var cmdTrackThat as Lang.ByteArray = [0x36, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x3c, 0x00, 0x02, 0xa8, 0x01, 0x00, 0x80, 0x00, 0x00, 0x08, 0xf8, 0xfc, 0xd3, 0xfa, 0x05, 0x1a, 0x1e, 0x63, 0x6f, 0x6d, 0x2e, 0x69, 0x6e, 0x73, 0x74, 0x61, 0x33, 0x36, 0x30, 0x2e, 0x6b, 0x65, 0x79, 0x54, 0x69, 0x6d, 0x65, 0x2e, 0x74, 0x72, 0x61, 0x63, 0x6b, 0x54, 0x68, 0x61, 0x74]b;
var currentMode as Lang.String or Lang.ByteArray = "DefaultV";
var videoMode as Lang.Boolean = true;
var currentLabel as Lang.String = "Default Video";
var startMessage as Lang.String = "";
var mMessage as Lang.String = "Starting Widget";

// Application.PropertyValueType does not accept ByteArray, so command payloads are
// persisted as lowercase hex strings and decoded again on load.
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

function hexToBytes(hex as Lang.String) as Lang.ByteArray {
	var len = hex.length();
	var out = new [0]b;
	var i = 0;
	while (i + 1 < len) {
		var n = ("0x" + hex.substring(i, i + 2)).toNumber();
		if (n != null) {
			out.add(n.toNumber());
		}
		i += 2;
	}
	return out;
}

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
	var startAckSeen as Lang.Boolean = false;
	var startWaitCount as Lang.Number = 0;
	var startPhase as Lang.Number = 0;
	// Number of mode+apply bursts sent since the camera was last idle. The menu
	// path emits one from onSelect before the start path emits its own, so a
	// start arriving with >= 2 bursts is already primed and must not pause.
	var applyBursts as Lang.Number = 0;
	var writing as Lang.Boolean = false;

	hidden function debug(str as Lang.String) as Void {
		System.println("[ble] " + str);
	}

	function initialize() {
		BleDelegate.initialize();
		debug("initialize");
	}

	// Send command to BLE device. A recording start is deferred so the
	// mode+apply frames get acknowledged first; everything else goes straight
	// out.
	function sendCMD(value as Lang.ByteArray) as Void {
		if (value == cmdStopRec) {
			cancelPendingStart();
		}
		transmit(value);
	}

	// Queue a command and kick the write chain. No start deferral here so both
	// the deferred-start path and the retry resend can call it directly.
	function transmit(value as Lang.ByteArray) as Void {
		// check that the camera is actually connected, otherwise start a scan
		if (scanning) {
			return;
		}

		var dev = device;
		if (dev == null) {
			recState = stateStopRec;
			debug("[sendCMD] No device connected, starting scan");
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
			return;
		}

		if (value == cmdApply) {
			applyBursts += 1;
		}

		// the ble messages are numbered in sequence (byte 10)
		SeqNo = SeqNo + 1;
		if (SeqNo > 254) {
			SeqNo = 1;
		}
		value[SeqPos] = SeqNo;

		// max message length = 20. the message has to be split into 20 bytes parts which are put in a queue.
		// each write operation has to been finished before the next one can occur.
		// the dequeuing is done in the onCharacteristicWrite function
		if (value.size() > 20) {
			var j = (value.size()-1)/20;
			for (var i = 0; i <= j.toNumber(); i++) {
				queue.add(value.slice(i*20,(i+1)*20));
			}
		} else {
			queue.add(value);
		}

		// A start/stop command arms the acknowledgement watchdog: if the camera
		// never reports the new recording state the burst was probably lost to a
		// connection race and is resent. inRetry blocks re-arming from the resend.
		if (!inRetry) {
			if (value == cmdStartRec) {
				scheduleRetry(retryKindStart);
			} else if (value == cmdStopRec) {
				scheduleRetry(retryKindStop);
			}
		}

		// The command is already queued above: dropping it here would silently
		// discard the first press of a session (service discovery is async).
		// Instead leave it queued and let discoverServices() kick the write
		// chain once the service resolves.
		var service = dev.getService(LBS_SERVICE);
		if (service == null) {
			debug("[sendCMD] service not resolved yet, deferring write");
			discoverServices(dev);
			return;
		}

		kickQueue(dev);
	}

	// Hold a recording start back until the mode+apply frames queued just before
// it have been acknowledged. A 700 ms poll drives the wait; the mode/apply ack
// fires the start immediately (see onCharacteristicChanged). Re-pressing start
// restarts the wait.
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
			// A mode+apply pair was already emitted before this burst (menu
			// path): the camera is primed, start as soon as this one is acked.
			startPhase = 1;
			debug("[start] already primed, waiting for burst ack");
			t.start(method(:onStartDelay), START_WAIT_MS, false);
		} else {
			startPhase = 0;
			debug("[start] pausing before second mode+apply burst");
			t.start(method(:onStartDelay), START_DELAY_MS, false);
		}
	}

	function onStartDelay() as Void {
		startDelayTimer = null;
		if (!pendingStart) {
			return;
		}
		if (startPhase == 0) {
			// The first mode+apply burst is already out; after the pause emit a
			// second one and let its ack gate the start (menu order).
			startPhase = 1;
			startWaitCount = 0;
			debug("[start] sending second mode+apply burst");
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
			debug("[start] no ack after second burst, sending anyway");
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
		debug("[start] sending cmdStartRec");
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

	// Single-writer pump: only the first queued chunk is written, and only when
	// no write is already in flight. onCharacteristicWrite advances to the next
	// chunk. Issuing a second requestWrite while one is pending is rejected by
	// the stack ("Operation already in Progress") and silently dropped the first
	// mode frame, which is why a direct start never got its mode acknowledged.
	function kickQueue(dev as BluetoothLowEnergy.Device) as Void {
		if (writing) {
			return;
		}
		if (queue.size() == 0) {
			return;
		}
		var service = dev.getService(LBS_SERVICE);
		if (service == null) {
			return;
		}
		try {
			var ch = service.getCharacteristic(LBS_RW_CHAR);
			if (ch != null) {
				writing = true;
				debug("[kickQueue] n=" + queue.size());
				ch.requestWrite(queue[0] as Lang.ByteArray, {:writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT});
			}
		} catch (ex) {
			writing = false;
			debug("[kickQueue] exception: " + ex.getErrorMessage());
		}
	}

	// (Re)arm the acknowledgement watchdog for a start/stop attempt.
	function scheduleRetry(kind as Lang.Number) as Void {
		// Keep the attempt count when re-arming the same kind: the watchdog is
		// re-armed each time the start is (re)sent, and resetting here would let
		// a failing start retry forever.
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

	// Fired when the camera did not acknowledge the start/stop in time.
	function onRetry() as Void {
		retryTimer = null;
		if (retryKind == 0) {
			return;
		}
		retryCount += 1;
		if (retryCount > RETRY_MAX) {
			debug("[retry] giving up kind=" + retryKind);
			var wasStart = (retryKind == retryKindStart);
			cancelRetry();
			// Unblock the UI: a start that never took still leaves the camera
			// idle, and a stop that never took still leaves it recording.
			recState = wasStart ? stateStopRec : stateStartRec;
			WatchUi.requestUpdate();
			return;
		}
		debug("[retry] resend kind=" + retryKind + " attempt=" + retryCount);
		inRetry = true;
		if (retryKind == retryKindStart) {
			resendStart();
		} else {
			sendCMD(cmdStopRec);
		}
		inRetry = false;
		startRetryTimer();
	}

	// Resend the start command if the camera did not report a recording start.
	function resendStart() as Void {
		transmit(cmdStartRec);
	}

	function onCharacteristicChanged(ch as BluetoothLowEnergy.Characteristic, value as Lang.ByteArray) as Void {
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
		// Command byte == 0x40 (id 4 of cmdStartRec, shifted by the response
		// nibble) or the legacy 0x10; position 17 is >0 = start. 0=end.
		var isRecReport = (value[7] == recReportCode) || (value[7] == recReportCodeLegacy);
		if (isRecReport and (value[17] > 0x00)) {
			// debug("Start Shooting");
			if (recState != stateStartRec) {
				debug("[onChar] rec report START code=" + value[7] + " v17=" + value[17]);
			}
			cancelRetry();
			cancelPendingStart();
			mMessage = "Shooting";
			recState = stateStartRec;
			startRecTime = Time.now();
//			WatchUi.pushView(new ViewData(BleDevice2), new InputDelegate(BleDevice2), WatchUi.SLIDE_IMMEDIATE);

		} else 	if (isRecReport and (value[17] == 0x00)) {
			// debug("Stop Shoot");
			if (recState != stateStopRec) {
				debug("[onChar] rec report STOP code=" + value[7] + " v17=" + value[17]);
			}
			cancelRetry();
			cancelPendingStart();
			applyBursts = 0;
			mMessage = currentLabel + "\n" + startMessage;
			recState = stateStopRec;
} else if (value[7] == stateBusy) {
				// sendCMD(cmdStopRec);
				mMessage = "Busy...";
  			} else if (value[0] == stateCmdErr) {
				cancelRetry();
				cancelPendingStart();
				mMessage = currentLabel + "\n" + startMessage;
				recState = stateStopRec;
			} else if (value[7] == ACK_CODE) {
				// Transport ack. Only the second burst's ack (phase 1) gates the
				// start; the ack of the first burst must be ignored.
				if (pendingStart and startPhase == 1 and !startAckSeen) {
					startAckSeen = true;
					debug("[onChar] second burst acked, firing deferred start");
					fireStart();
				}
			} else {
				 debug("Unknown Response " + value.toString());
				// mMessage = "-";
			}
		  }
		}

		//second guess elapsed recording time (don't know how to decode the protbuf status)
		if (recState == stateStartRec) {
			clockTime = Time.now();
			var diff = clockTime.subtract(startRecTime);
			if (diff instanceof Time.Duration) {
				elapsedRecTime = diff;
				mMessage = currentLabel + "\n" + toTimeString(elapsedRecTime.value());
			}
		} else {
			// mMessage = "Stopped\n" + currentLabel + "\n" + startMessage;
		}
		WatchUi.requestUpdate();
	}

	function onCharacteristicWrite(ch as BluetoothLowEnergy.Characteristic, st as BluetoothLowEnergy.Status) as Void {
	// we need to wait before sending the next ble message.
	// this function is called only when the previous message has been writen to the camera (successfuly or not)
		// The chunk just written is done: clear the in-flight flag, drop it and
		// pump the next one. A write failure is treated the same as a success so
		// the queue keeps draining.
		writing = false;
		if (queue.size() > 0) {
			// Array.slice() returns Array<Object or Null>, so rebuild the typed queue.
			var remaining = [] as Lang.Array;
			for (var k = 1; k < queue.size(); k++) {
				remaining.add(queue[k] as Lang.ByteArray);
			}
			queue = remaining;
		}
		var dev = device;
		if (dev != null and queue.size() > 0) {
			kickQueue(dev);
		} else {
			debug ("[onCharWrite] queue empty Status " + st.toString());
		}
	}

	function toTimeString(seconds as Lang.Number) as Lang.String {
		var hours = seconds/3600;
    	var min = (seconds - hours*3600)/60;
    	var sec = (seconds - hours*3600 - min*60);

    	return (hours.toString() + ":" + min.format("%02d") + ":" + sec.format("%02d"));
	}


	function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
		debug("registered: " + uuid.toString() + " " + status.toString());
	}

	// Called by open() function, part of initialization process.
	function registerProfiles() as Void {
		var profile = {
			:uuid => LBS_SERVICE,
			:characteristics => [{
				:uuid => LBS_RW_CHAR,
                        }, {
				:uuid => LBS_NOTIF_CHAR,
				:descriptors => [LBS_NOTIF_DESC],
			}]
		};
		try {
			BluetoothLowEnergy.registerProfile(profile);
		} catch (ex) {
			    debug("[sendCMD] exception: " + ex.getErrorMessage());
		}

	}

	// Service discovery is lazy on this stack: getService() keeps returning
	// null until getServices() has been walked. Force it right after pairing so
	// the link is usable instead of being torn down on the first command.
	function discoverServices(dev as BluetoothLowEnergy.Device) as Void {
		if (dev == null) {
			debug("[discover] no device");
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
					debug("[discover] service <null uuid>");
				} else {
					debug("[discover] service " + su.toString());
				}
				count += 1;
			}
			var lbs = dev.getService(LBS_SERVICE);
			debug("[discover] done count=" + count + " lbsResolved=" + (lbs != null));
			// Commands queued while the service was unresolved are flushed here.
			if (lbs != null) {
				kickQueue(dev);
			}
		} catch (ex) {
			debug("[discover] exception: " + ex.getErrorMessage());
		}
	}

	function onScanStateChange(scanState as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
		debug("scanstate: " + scanState.toString() + " " + status.toString());

		if (scanState == BluetoothLowEnergy.SCAN_STATE_SCANNING) {
			scanning = true;
			mMessage = "Scanning...\n" + scanTimeout.toString();
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

	function onConnectedStateChanged(dev as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
		// debug("connected: " + dev.getName() + " " + dev.isConnected() + " " + state);
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
				    debug("[onConStateChg] OFF exception: " + ex.getErrorMessage());
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
//			try {
//				BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
//			} catch (ex) {
//			    debug("[onConStateChg] On exception: " + ex.getErrorMessage());
//		    }

			}
		}
	}

	private function connect(result as BluetoothLowEnergy.ScanResult) as Void {
		// debug("[connect] " + result.getDeviceName());
		try {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
			// debug("[connect] scanning OFF");
		} catch (ex) {
		    debug("[connect] scan OFF exception: " + ex.getErrorMessage());
		}
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

	function onScanResults(scanResults as BluetoothLowEnergy.Iterator) as Void {
//		debug("scan results");
		// var name;
		// var rssi;

		for (var rawResult = scanResults.next(); rawResult != null; rawResult = scanResults.next()) {
			var result = rawResult as BluetoothLowEnergy.ScanResult;
			var uuids = result.getServiceUuids();
			var name = result.getDeviceName();
			if (name != null) {
				deviceName = name;
			}
			// rssi = result.getRssi();

			// debug("[onScanResults] device: " + name + " rssi: " + rssi);
//			dumpUuids(uuids);

			//search for an insta360 device based on service UUID
			for (var rawUuid = uuids.next(); rawUuid != null; rawUuid = uuids.next()) {
				var iter = rawUuid as BluetoothLowEnergy.Uuid;
//				debug("uuid: " + iter);
				menuLevel = 0;
				if (iter.equals(LBS_SERVICE) and (deviceName != null)) {
					// debug("Connect " + iter);
					if (deviceName.length() >= 3) {
var prefix = deviceName.substring(0,3);
				if (prefix != null) {
					if (prefix.equals("ONE")) {
						menuLevel = 1;
					}
					if (prefix.equals("X3 ")) {
						menuLevel = 1;
					}

					if (prefix.equals("X4 ")) {
						menuLevel = 2;
					}
					if (prefix.equals("X5 ")) {
						menuLevel = 2;
					}
				}
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
//			    		debug("[onScanResult] storage write exception " + ex.getErrorMessage());
//						}
//						connect(result);
//					return;
//				}
//			}
			scanTimeout--;
			mMessage = "Scanning...\n" + scanTimeout.toString();
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

	function photoGpsHeader(lat as Lang.Number or Lang.Float or Lang.Double,
	                        lon as Lang.Number or Lang.Float or Lang.Double,
	                        alt as Lang.Number or Lang.Float or Lang.Double) as Lang.ByteArray {
		// Photo mode command with the GPS fix appended.
		var header = [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18]b;
		var filler = [0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
		header.addAll(toDouble(lat));
		header.addAll(toDouble(lon));
		header.addAll(toDouble(alt));
		header.addAll(filler);
		return header;
	}

	function toDouble(single as Lang.Number or Lang.Float or Lang.Double) as Lang.ByteArray {
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
		t32.encodeNumber(single as Lang.Number, Lang.NUMBER_FORMAT_FLOAT, {});
		tb = t32.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {}) as Lang.Long;
		// get the sign
		ts = tb & 0x80000000l;
		// get the exponent part
		te = tb & 0x7f800000l;
		te >>= 23;
		// new 64bit based bias
		bias = te - 127 + 1023;
		bias <<= 52;
		// get the mantisse part and shift it
		tm = tb & 0x007fffffl;
		tm <<= 29;
		// add the new bias to the mantis and the sign
		ts <<= 32;
		tb = ts + bias + tm;
		// cut the new value in 2 32bit chunks
		tb1 = tb;
		tb1 >>= 32;
		d1.encodeNumber(tb1, Lang.NUMBER_FORMAT_UINT32, {});
		tb1 <<=32;
		tb2 = tb - tb1;
		d2.encodeNumber(tb2, Lang.NUMBER_FORMAT_UINT32, {});
		// debug ("[toDouble] " + tb.format("%x"));
		// build the final bitArray, little endian
		double.addAll(d2);
		double.addAll(d1);
		return double;
	}

	function sendPosition(info as Position.Info) as Void {
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
		// debug("[sendPosition] Accuracy: " + GPSaccuracy.toString());


		if ((device == null) or (recState != stateStartRec)) { return; }

		// Each Position.Info accessor returns a nullable, so bind them to locals first:
		// the compiler does not narrow a repeated property access.
		var position = info.position;
		var headingInfo = info.heading;
		var whenInfo = info.when;
		if ((position == null) or (headingInfo == null) or (whenInfo == null)) { return; }

		var location = position.toDegrees();
		latitude = location[0];
		longitude = location[1];

		//heading is provided in radians, convert to degrees
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

		// debug ("[onPosition] " + info.when.value() + " " + latitude + " " + longitude + " " + speed + " " + heading + " " + altitude);

		// Video & Photo telemetry are encoded differently.
		if (videoMode) {
			// encode timestamp
			temp32.encodeNumber(whenInfo.value(), Lang.NUMBER_FORMAT_UINT32, {});
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

			// debug ("hex " +header.size() +" "+ header.toString());
			sendCMD(header);
		}
	}


	function open() as Void {

		// Check if watch is touch screen capable
		if (System.getDeviceSettings().isTouchScreen) {
			startMessage = "Tap Here";
		} else {
			startMessage = "Press Start";
		}
		// debug("open");
		// Load last state of app
		var v = App.getApp().getProperty("recState");
		if (v == null) {
			recState = stateStopRec;
		} else {
			// PropertyValueType is a union that does not expose toNumber();
			// only the numeric members are accepted by this cast.
			var storedState = v as Lang.Number;
			if (storedState != null) {
				recState = storedState;
			} else {
				recState = stateStopRec;
			}
		}

		// A start is now sent bare (no mode+apply), so the camera records in
		// whatever mode it currently holds. The app must therefore not assume it
		// knows that mode: always start from "Default Video" rather than the
		// last-selected mode. The mode is only set when chosen from the menu.
		currentMode = "DefaultV";
		currentLabel = "Default Video";
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

		// cmdStartRec/cmdStopRec are deliberately NOT restored from properties:
		// onSelect mutates them for HDR/Timelapse/Bullet/Interval modes, and a
		// persisted mutated copy would be replayed by a direct start (the camera
		// then ignores it). They always begin from the defaults declared above.

		var gpsProp = App.getApp().getProperty("GPSon");
		if (gpsProp == null) {
			GPSon = false;
		} else {
			GPSon = gpsProp.toString().equals("true");
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

	function close() as Void {
		debug("close");
		// Save current state of app
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
