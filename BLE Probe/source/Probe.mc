// BLE ladder probe for the Insta360 X5.
//
// A test bench, not a product. It drives a fixed ladder of rungs through the
// BLE Barrel's own transport, so a rung that passes here exercised the same
// write path and the same notification reassembly the product app runs on the
// watch. One verdict per rung:
//
//   PASS         the evidence the rung asked for arrived
//   FAIL         it did not
//   NO EVIDENCE  BLE cannot tell the two cases apart, so nothing is claimed
//
// The authority rules follow the cahier des charges: a reply (code 200) proves
// the camera holds a value, only a notification the camera pushes (8275/8293/
// 8208/8256) proves it acted, and nothing is timed from the watch's own clock.
// Rung T5 says that split out loud, because it is where readback and effect
// part ways.

using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;
using Toybox.Lang;
using BLEBarrel;

var bleDevice = null;
var ladderTimer = null;
var actIx = 0;
var sub = 0;
var baseSeen = 0;
var baseCount = 0;
// The counts of the codes the judges ask about, read at the start of a
// rung: a bit cannot tell that a code arrived again during that window,
// and the stop of a capture pushes 8208 and 8256 after the start already
// set their bits.
var baseSub = 0;
var baseCap1 = 0;
var baseCap2 = 0;
// The codes the candidate window of the S-15 axis asks about: 8210 is the
// camera's own count of an Interval sequence, 8198 and 8290 arrive when it
// registers the files it made.
var baseTL = 0;
var baseSto = 0;
var baseInfo = 0;
var lastGroup = "";
var verdicts = 0;
var log = [] as Lang.Array<Lang.String>;
// The raz verdict is a snapshot taken at the raz tick, not the state read at
// the end of the window: a live camera keeps pushing after a reset, and a
// later arrival is a fact about the camera, never evidence that the reset
// failed. The delegate can only hand bytes over between ticks, so a read
// done right after resetNotif(), in the same tick, cannot hold an arrival.
var razClean = false;

const TICK_MS = 500;
const WRITE_WAIT_TICKS = 6;
const SCAN_WAIT_TICKS = 40;
const LISTEN_TICKS = 40;
const LINES_ON_SCREEN = 5;

const ACT_WAIT = 1;
const ACT_GET = 2;
const ACT_SET = 3;
const ACT_START = 4;
const ACT_STOP = 5;
const ACT_LISTEN = 6;
const ACT_RAZ = 7;
const ACT_CAND = 8;
const ACT_PHOTO = 9;
// CdC item 65, axis S-15: the candidate stop of a photo Interval sequence, ONE
// candidate per run. The number picks the frame the candidate rung sends; the run
// that measures a candidate closes its turn, the next run changes the number.
//   1  code 5, body 10 01 - STOP_CAPTURE, Capture_MODE_NORMAL: the frame the widget
//      sends today, measured REFUSED against an Interval sequence on the X5 (item 65).
//   2  code 23, body 08 02 - STOP_TIMELAPSE, mode field 1 of the enum TimelapseMode,
//      value 2 = TIMELAPSE_INTERVAL_SHOOTING (outils/insta360-ref/timelapse_pb2.py): the
//      vocabulary names this very mode, so this is the candidate of the next run. The
//      mark stays OFFICIAL: no code 22 nor 23 frame exists on any wire artefact.
//   3  code 6, body empty - CANCEL_CAPTURE of the reference vocabulary.
//   4  code 5, body 10 02 - STOP_CAPTURE with the value 2 = Capture_MODE_BULLETTIME,
//      kept last: CaptureMode has no Interval member, so this rung only settles that
//      STOP_CAPTURE cannot speak of an Interval at all.
const CAND = 2;

// opt 31 record resolution, 40 photo sub-mode, 41 video sub-mode, 63 HDR,
// 86 Adaptive Tone (the ids and their meaning come from capacites_camera.py,
	// which is the source of truth for what the X5 holds).
var ladder = [
	{ :group => "T0 raw dump", :act => ACT_LISTEN, :ticks => SCAN_WAIT_TICKS,
			:label => "listen 20 s, send nothing (raw dump)" },
	{ :group => "T1 discovery", :act => ACT_WAIT, :ticks => SCAN_WAIT_TICKS,
			:label => "wait for the X5 service" },
		{ :group => "T2 GET", :act => ACT_GET, :opt => 31,
			:label => "GET record resolution (31)" },
		{ :group => "T2 GET", :act => ACT_GET, :opt => 41,
			:label => "GET video sub-mode (41)" },
		{ :group => "T2 GET", :act => ACT_GET, :opt => 40,
			:label => "GET photo sub-mode (40)" },
		{ :group => "T2 GET", :act => ACT_GET, :opt => 63,
			:label => "GET HDR (63)" },
		{ :group => "T3 start/stop", :act => ACT_START,
			:label => "start capture" },
		{ :group => "T3 start/stop", :act => ACT_LISTEN, :ticks => 4,
			:label => "let the capture run 2 s (window)" },
		{ :group => "T3 start/stop", :act => ACT_STOP,
			:label => "stop capture" },
		{ :group => "T4 sub-mode", :act => ACT_SET, :opt => 41, :val => 0,
			:label => "SET video sub-mode = 0 (Normal)" },
		{ :group => "T4 sub-mode", :act => ACT_SET, :opt => 41, :val => 11,
			:label => "SET video sub-mode = 11 (PureVideo, restore)" },
		{ :group => "T5 phantom write", :act => ACT_SET, :opt => 86, :val => 1,
			:label => "SET Adaptive Tone (86) = 1" },
		{ :group => "T5 phantom write", :act => ACT_GET, :opt => 86,
			:label => "readback 86 : storage, never execution" },
		{ :group => "T5 phantom write", :act => ACT_SET, :opt => 86, :val => 0,
			:label => "SET Adaptive Tone (86) = 0 (restore)" },
		{ :group => "T6 camera side", :act => ACT_LISTEN, :ticks => LISTEN_TICKS,
			:label => "change the mode on the camera screen now" },
		{ :group => "T7 RAZ", :act => ACT_RAZ,
			:label => "local reset-to-zero of the observer" }
];

// The candidate ladder of the S-15 axis (CdC item 65). The two first legs are
// re-reads of rungs the ladder already closed (the mode write S-13, the capture of
// the press S-14): they are there to reach the state the question needs and they
// ask no question of their own. ONE candidate frame leaves per run, and its window
// is the tell: the sequence is read on the camera by the eye, never claimed here.
function candLadder() as Lang.Array {
	var code = 5;
	var body = [0x10, 0x01]b;
	if (CAND == 2) {
		code = 23;
		body = [0x08, 0x02]b;
	} else if (CAND == 3) {
		code = 6;
		body = new [0]b;
	} else if (CAND == 4) {
		code = 5;
		body = [0x10, 0x02]b;
	}
	return [
		{ :group => "C0 bond", :act => ACT_WAIT, :ticks => SCAN_WAIT_TICKS,
				:label => "wait for the X5 service" },
		{ :group => "C1 mode", :act => ACT_SET, :opt => 40, :val => 2,
				:label => "SET photo sub-mode = 2 (Interval): the S-13 re-read" },
		{ :group => "C2 capture", :act => ACT_PHOTO,
				:label => "TAKE_PICTURE, empty body: the capture of the press (S-14)" },
		{ :group => "C3 run", :act => ACT_LISTEN, :ticks => 60,
				:label => "let the Interval sequence shoot 30 s (listen, never poll)" },
		{ :group => "C4 candidate", :act => ACT_CAND, :code => code, :body => body,
				:ticks => 20,
				:label => "stop candidate code=" + code.toString()
					+ " body=" + BLEBarrel.bytesToHex(body) },
		{ :group => "C5 after", :act => ACT_LISTEN, :ticks => 40,
				:label => "listen 20 s: does 8210 keep counting, does 8208 leave the capture?" }
	];
}

class ProbeView extends WatchUi.View {

	function initialize() {
		WatchUi.View.initialize();
	}

	function onUpdate(dc) {
		var w = dc.getWidth();
		var h = dc.getHeight();
		dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
		dc.clear();
		dc.drawText(w / 2, h / 4, Graphics.FONT_SMALL, "X5 BLE ladder",
				(Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER));
		var top = log.size() - LINES_ON_SCREEN;
		if (top < 0) {
			top = 0;
		}
		var y = h / 2;
		var i = top;
		while (i < log.size()) {
			dc.drawText(10, y, Graphics.FONT_TINY, log[i], Graphics.TEXT_JUSTIFY_LEFT);
			y += 18;
			i++;
		}
		// The full record stays on the console: the screen only holds the tail
		// of it, which is enough to follow the ladder on a 51 mm watch.
		// Nothing here is read back off the camera; the view only shows what
		// the ladder already concluded.
	}

	// EF-27 and the ladder's own rule: the observer is rebuilt from zero, by
	// listening again. The screen shows the tail of what was seen, never a
	// state read back off the camera.
	function compute(info) {
		return true;
	}
}

class Probe extends Application.AppBase {

	function initialize() {
		AppBase.initialize();
	}

	function onStart(state) as Void {
		bleDevice = new BLEBarrel.BleDevice();
		// The bench asks the shipping transport for its raw wire log before any
		// gate can drop a byte, so the first run is read from the bytes and not
		// from what the decoders made of them.
		bleDevice.armWire();
		BluetoothLowEnergy.setDelegate(bleDevice);
		bleDevice.open();
		// The bench arms the X5 decoder itself rather than trusting discovery to
		// carry the camera's name: the envelope alone cannot tell an X5 reply
		// from an X3/X4 one, and a replayed device has no name at all.
		bleDevice.armX5();
		bleDevice.resetNotif();
		// The ladder always answers through the BLE delegate, so the rungs are
		// driven by the clock and need no key press.
		// CdC item 65: a run of the S-15 axis answers only that question.
		if (CAND != 0) {
			ladder = candLadder();
			say("== candidate ladder: CAND=" + CAND.toString() + " ==");
		}
		ladderTimer = new Timer.Timer();
		ladderTimer.start(method(:ladderTick), TICK_MS, true);
		say("== X5 BLE ladder ==");
	}

	function onStop(state) as Void {
		if (ladderTimer != null) {
			ladderTimer.stop();
			ladderTimer = null;
		}
		bleDevice.close();
	}

	function getInitialView() {
		return [ new ProbeView() ];
	}

	// ----------------------------------------------------------------
	// The machine
	//
	// One rung at a time: the action fires on the first tick, then the machine
	// only counts ticks while it waits. Nothing is re-sent during that wait,
	// so waiting is listening and never polling.
	function ladderTick() as Void {
		if (actIx >= ladder.size()) {
			if (ladderTimer != null) {
				ladderTimer.stop();
				ladderTimer = null;
			}
			say("== ladder over: " + verdicts.toString() + " verdicts ==");
			return;
		}
		var a = ladder[actIx];
		if (a[:group] != lastGroup) {
			lastGroup = a[:group];
			say("-- " + lastGroup);
		}
		var want = WRITE_WAIT_TICKS;
		if (a[:ticks] != null) {
			want = a[:ticks];
		}
		if (sub == 0) {
			say("   " + a[:label]);
			baseSeen = bleDevice.peekX5Seen();
			baseCount = bleDevice.peekNotifCount();
			baseSub = bleDevice.peekCodeCount(BLEBarrel.X5_SUB_MODE_NOTIF);
			baseCap1 = bleDevice.peekCodeCount(BLEBarrel.X5_CAPTURE_STATUS_NOTIF);
			baseCap2 = bleDevice.peekCodeCount(BLEBarrel.X5_RECORD_STATE_NOTIF);
			baseTL = bleDevice.peekCodeCount(0x2012);
			baseSto = bleDevice.peekCodeCount(BLEBarrel.X5_STORAGE_NOTIF);
			baseInfo = bleDevice.peekCodeCount(BLEBarrel.X5_STOP_PUSH_NOTIF);
			fire(a);
		}
		sub++;
		if (sub <= want) {
			return;
		}
		judge(a);
		// The last frame the observer holds, as the bytes that crossed the
		// delegate. Emptiness by length: the barrel's typed accessors hand a
		// String, and == on a String is an identity test, not a content test.
		var heldHex = bleDevice.peekNotifHex();
		if (heldHex.length() > 0) {
			say("   last frame: " + heldHex);
		}
		actIx++;
		sub = 0;
	}

	// The rungs go out through the barrel, never through a socket of their own:
	// the bench tests the shipping transport, not a re-creation of it.
	function fire(a) as Void {
		var act = a[:act];
		if (act == ACT_GET) {
			bleDevice.sendCMD(getFrame(a[:opt]));
		} else if (act == ACT_SET) {
			bleDevice.sendCMD(setFrame(a[:opt], a[:val]));
		} else if (act == ACT_START) {
			bleDevice.sendCMD(BLEBarrel.cmdStartRec);
		} else if (act == ACT_STOP) {
			bleDevice.sendCMD(BLEBarrel.cmdStopRec);
		} else if (act == ACT_PHOTO) {
			// The capture of the press of the photo family: TAKE_PICTURE, empty body,
			// the 16-octet frame the item 44 fixed and the item 57 put at the press.
			bleDevice.sendCMD(x5Frame(3, new [0]b));
		} else if (act == ACT_CAND) {
			// The candidate stop frame, handed to the same transport the product uses.
			bleDevice.sendCMD(x5Frame(a[:code], a[:body]));
		} else if (act == ACT_RAZ) {
			// EF-27: a local reset-to-zero. It clears the view, restarts the
			// sequence, and emits no command to the camera.
			bleDevice.resetNotif();
			// The snapshot at the raz tick, same synchronous call chain: what
			// arrives during the window after it belongs to the camera, not
			// to the raz (measured 25/10: a 0x2065 crossed at recv #241
			// inside the raz window while the reset itself held).
			razClean = bleDevice.peekNotifCount() == 0
				&& bleDevice.peekX5Seen() == 0
				&& bleDevice.peekNotifHex().length() == 0;
		}
	}

	function judge(a) as Void {
		var act = a[:act];
		// A run where the delegate received no byte at all cannot speak about the
		// camera: a transport that refusee silently and a camera that never answer
		// producee the same log, and a verdict taken from it is void (§11.3 criterion
		// 14). The absence printe itself, so the log of a dead link never carrye a
		// FAIL that a later reader could take for a refusal of the X5. The scope is
		// the rungs that fire a write: for them a silent window could else be read
		// for a refusal of the camera. The listen and discovery judges keep their
		// own message, which name the window and stay precise while the scan of
		// the delegate is still runing — a window full of `scan uuid` lines and
		// zero `recv` saw nothing, and that is not a dead link.
		// The raz keeps its own verdict: it is about the observer, and it needs no
		// camera.
		if ((act == ACT_GET || act == ACT_SET || act == ACT_START || act == ACT_STOP)
		&& bleDevice.peekWireRecv() == 0) {
			verdicts++;
			say("   NO EVIDENCE the link delivered no byte since open() (wireEvents="
				+ bleDevice.peekWireEvents().toString() + ")");
			return;
		}
		if (act == ACT_WAIT) {
			// menuLevel 2 is what discovery sets for a name starting "X5 ", so
			// it is the rung's own evidence that this camera is an X5.
			verdicts++;
			if (BLEBarrel.menuLevel == 2) {
				say("   PASS discovered as an X5: " + BLEBarrel.deviceName);
				return;
			}
			say("   FAIL not discovered as an X5 (menuLevel="
				+ BLEBarrel.menuLevel.toString() + " name=" + BLEBarrel.deviceName
				+ ")");
			return;
		}
		if (act == ACT_GET) {
			verdicts++;
			getJudge(a[:opt]);
			return;
		}
		if (act == ACT_SET) {
			verdicts++;
			setJudge(a[:opt], a[:val]);
			return;
		}
		if (act == ACT_START || act == ACT_STOP || act == ACT_PHOTO) {
			verdicts++;
			captureJudge(a[:label]);
			return;
		}
		if (act == ACT_CAND) {
			verdicts++;
			candJudge(a[:label]);
			return;
		}
		if (act == ACT_LISTEN) {
			verdicts++;
			listenJudge();
			return;
		}
		if (act == ACT_RAZ) {
			verdicts++;
			razJudge();
		}
	}

	// A readback: the reply carries the value the camera holds. That is storage;
	// it is never read as proof that anything took effect.
	function getJudge(opt as Lang.Number) as Void {
		var code = bleDevice.peekNotifCode();
		if (code != 200) {
			say("   FAIL no reply to the GET (notifCode=" + code.toString() + ")");
			return;
		}
		// The reply itself may be cut by the delegate: a 66-byte stop reply
		// crossed as 20. An option past that cut cannot be told from an option
		// the camera did not send, so the rung says NO EVIDENCE instead of
		// claiming it is absent.
		var declared = bleDevice.peekNotifDeclared();
		var arrived = bleDevice.peekNotifArrived();
		var cut = declared > arrived;
		var v = bleDevice.lastOption(opt);
		if (v != null) {
			say("   PASS readback opt " + opt.toString() + " = " + v.toString()
				+ " (storage, not execution)");
			return;
		}
		if (bleDevice.peekNotifVal1() == opt) {
			say("   PASS option " + opt.toString() + " named in the reply, no value"
				+ (cut ? ", cut reply: " + arrived.toString() + " of " + declared.toString()
					+ " bytes crossed" : ""));
			return;
		}
		if (cut) {
			say("   NO EVIDENCE opt " + opt.toString() + " not in the "
				+ arrived.toString() + " bytes that crossed a " + declared.toString()
				+ "-byte reply: absent cannot be told from past the cut");
			return;
		}
		// An option the camera does not hold is dropped from the reply, and a
		// dropped field is evidence of a dropped write, not of a hidden one.
		say("   FAIL option " + opt.toString() + " absent from the reply");
	}

	function setJudge(opt as Lang.Number, val as Lang.Number) as Void {
		var fresh = bleDevice.peekX5Seen() & (~baseSeen);
		// Counted during the window, not flagged since the raz: 8275 may have
		// arrived for an earlier rung and be read as this rung's otherwise.
		var subMode = (bleDevice.peekCodeCount(BLEBarrel.X5_SUB_MODE_NOTIF)
			- baseSub) > 0;
		var ack = (bleDevice.peekNotifCode() == 200);
		if (opt == 40 || opt == 41) {
			// A sub-mode change answers with 8275: field 1 is the photo sub-mode
			// and field 2 the video one, 100 meaning not applicable.
			// A value of 0 is a legitimate mode, and protobuf never serialises 0,
			// so an absent field is read as the default, not as a refusal.
			if (!subMode) {
				say("   NO EVIDENCE: " + (ack ? "written (code 200), nothing pushed"
					: "no ack, nothing pushed")
					+ " (8275 arrived "
					+ (bleDevice.peekCodeCount(BLEBarrel.X5_SUB_MODE_NOTIF)
					- baseSub).toString() + " time(s) during the window)");
				return;
			}
			var seen = (opt == 40) ? bleDevice.peekNotifVal1() : bleDevice.peekNotifVal2();
			// The notification is the camera's own report, so this is the only
			// rung here that can claim the camera acted.
			if (seen == val) {
				say("   PASS 8275 pushed sub-mode " + val.toString()
					+ " = the value written");
				return;
			}
			say("   FAIL 8275 pushed " + seen.toString() + " for option "
				+ opt.toString() + ", not " + val.toString());
			return;
		}
		// The HDR and Adaptive Tone switches were never observed to push anything
		// (rea/10 §5 has no code for them), so BLE cannot separate a switch the
		// camera applied from one it only stored. The rung says so instead of
		// guessing, and an ack of 400 is named: the camera refused that write,
		// which is a refusal, not a silence.
		if (fresh != 0) {
			say("   PASS write accepted, a notification arrived (bits="
				+ fresh.toString() + ")");
			return;
		}
		var ackCode = bleDevice.peekNotifCode();
		say("   NO EVIDENCE: " + (ack ? "code 200" : (ackCode != 0
			? "code " + ackCode.toString() : "no ack"))
			+ ", nothing pushed: stored cannot be told from applied");
	}

	// 8208 capture status and 8256 record state (the code measured on the wire,
	// 0x2040) are the camera's own report of a capture, so their arrival is what
	// stands as proof, not the write. 8198 storage update and 8290 arrive at a
	// stop too and are counted as pushes, not as proof that the capture ended.
	function captureJudge(name as Lang.String) as Void {
		// The counts of the window, not the bits: the stop of a capture pushes
		// 8208 and 8256 again, and the start already set their bits, so a bit
		// test would read that stop as no arrival at all. The counts answer
		// the question the rung asks.
		var got1 = bleDevice.peekCodeCount(BLEBarrel.X5_CAPTURE_STATUS_NOTIF)
			- baseCap1;
		var got2 = bleDevice.peekCodeCount(BLEBarrel.X5_RECORD_STATE_NOTIF)
			- baseCap2;
		if (got1 > 0 || got2 > 0) {
			say("   PASS " + name + ": the camera pushed 8208/8256 (8208=+"
				+ got1.toString() + " 8256=+" + got2.toString() + ")");
			return;
		}
		say("   NO EVIDENCE " + name + ": no capture notification (recState="
			+ BLEBarrel.recState.toString() + " 8208=+" + got1.toString()
			+ " 8256=+" + got2.toString() + ")");
	}

	// The window of the candidate stop of an Interval sequence. The judgement is a
	// reading of the window, and it is an EVIDENCE line and not a PASS: 8210 is the
	// camera's own counter of the sequence (the reference proto names one field,
	// interval_count), 8208 is its report of the capture, 8198 and 8290 say the files
	// were registered. Whether the sequence stopped is read on the camera by the eye
	// beside the window; the window alone never says it (EF-22, note 14 of the CdC).
	function candJudge(name as Lang.String) as Void {
		var tl = bleDevice.peekCodeCount(0x2012) - baseTL;
		var cap = bleDevice.peekCodeCount(BLEBarrel.X5_CAPTURE_STATUS_NOTIF) - baseCap1;
		var rec = bleDevice.peekCodeCount(BLEBarrel.X5_RECORD_STATE_NOTIF) - baseCap2;
		var sto = bleDevice.peekCodeCount(BLEBarrel.X5_STORAGE_NOTIF) - baseSto;
		var info = bleDevice.peekCodeCount(BLEBarrel.X5_STOP_PUSH_NOTIF) - baseInfo;
		say("   EVIDENCE " + name + " pushes: 8210=+" + tl.toString()
			+ " 8208=+" + cap.toString() + " 8256=+" + rec.toString()
			+ " 8198=+" + sto.toString() + " 8290=+" + info.toString());
		say("   EVIDENCE last code=" + bleDevice.peekNotifCode().toString()
			+ " declared=" + bleDevice.peekNotifDeclared().toString()
			+ " arrived=" + bleDevice.peekNotifArrived().toString()
			+ " cut=" + (bleDevice.peekNotifTruncated() ? "true" : "false")
			+ " wireEvents=" + bleDevice.peekWireEvents().toString());
		say("   eye: is the Interval sequence still shooting? (never read here)");
	}

	// T6 is the camera side of the loop: the rung sends nothing. A mode changed
	// on the camera's own screen must push the same events as one changed from
	// the watch, so anything that arrived during the window is the evidence.
	function listenJudge() as Void {
		var freshCount = bleDevice.peekNotifCount() - baseCount;
		var fresh = bleDevice.peekX5Seen() & (~baseSeen);
		// The wire counter is printed as well, so "nothing crossed the delegate"
		// can be told apart from "bytes crossed it and no frame was made". A
		// keepalive is not a frame worth decoding, so it moves the wire counter
		// and not this one: the two together say the link is alive and quiet.
		if (freshCount > 0) {
			say("   PASS " + freshCount.toString()
				+ " frame(s) pushed by the camera (bits=" + fresh.toString()
				+ " wireEvents=" + bleDevice.peekWireEvents().toString() + ")");
			return;
		}
		say("   NO EVIDENCE nothing was pushed during the window (wireEvents="
			+ bleDevice.peekWireEvents().toString() + ")");
	}

	function razJudge() as Void {
		// The dump counter is read here so a run that received nothing at all can
		// be told apart from a run whose bytes arrived and were dropped by a
		// silent gate. Emptiness is asked by length on the value the barrel hands
		// back, never by == on a String read across the module boundary: a bench
		// run showed an empty notifHex holding (notifHex == "") as false, which
		// is an identity test, not a test of content.
		var hex = bleDevice.peekNotifHex();
		say("   observer dump: notifHex length=" + hex.length().toString()
			+ " wireEvents=" + bleDevice.peekWireEvents().toString());
		// Every code that arrived since the raz, named or not, so an unknown
		// value stays visible and reusable at the end of the run.
		var codes = bleDevice.peekSeenCodes();
		if (codes.size() > 0) {
			var s = "";
			for (var i = 0; i < codes.size(); i++) {
				s = s + " code=" + codes[i].toString();
			}
			say("   codes seen since the raz:" + s);
		}
		if (razClean && bleDevice.peekNotifCount() == 0 && bleDevice.peekX5Seen() == 0
			&& hex.length() == 0) {
			say("   PASS observer back to zero: no view, no count, no command sent");
			return;
		}
		if (razClean) {
			// The snapshot at the raz tick was zero: the reset worked. What the
			// dump holds now crossed the delegate after the reset — a live
			// camera keeps pushing, and those arrivals are recorded as facts
			// about the camera, not as a failure of the observer.
			say("   PASS the raz cleared the observer: zero at the raz, "
				+ bleDevice.peekNotifCount().toString()
				+ " arrival(s) after the raz (bits=" + bleDevice.peekX5Seen().toString()
				+ " hexLength=" + hex.length().toString() + ")");
			return;
		}
		say("   FAIL the raz did not clear the observer (non-zero at the raz tick): "
			+ "count=" + bleDevice.peekNotifCount().toString()
			+ " bits=" + bleDevice.peekX5Seen().toString()
			+ " hexLength=" + hex.length().toString());
	}

	// ----------------------------------------------------------------
	// Frames
	//
	// The measured X5 envelope: [u32 LE total][04 00 00][code u16 LE][02]
	// [seq 3B LE][80 00 00][protobuf body], so the body starts at 16 and the
	// sequence sits at byte 10, which transmit() stamps with its own counter.
	function x5Frame(code as Lang.Number, body as Lang.ByteArray) as Lang.ByteArray {
		var total = 16 + body.size();
		var f = new [total]b;
		f[0] = total & 0xff;
		f[1] = (total >> 8) & 0xff;
		f[2] = 0;
		f[3] = 0;
		f[4] = 0x04;
		f[5] = 0;
		f[6] = 0;
		f[7] = code & 0xff;
		f[8] = (code >> 8) & 0xff;
		f[9] = 0x02;
		f[10] = 0;
		f[11] = 0;
		f[12] = 0;
		f[13] = 0x80;
		f[14] = 0;
		f[15] = 0;
		var i = 0;
		while (i < body.size()) {
			f[16 + i] = body[i];
			i++;
		}
		return f;
	}

	function getFrame(opt as Lang.Number) as Lang.ByteArray {
		// A GET asks for one option: field 1 holds the option id.
		return x5Frame(10, [0x0a, 0x01, opt & 0xff]b);
	}

	function setFrame(opt as Lang.Number, val as Lang.Number) as Lang.ByteArray {
		// field 1 = option id, field 2 = a nested message holding that option's own
		// field number then the new value. Both are varints, hence the widths.
		var tag = opt << 3;
		var tagLen = (tag > 127) ? 2 : 1;
		var valLen = (val > 127) ? 2 : 1;
		var body = new [4 + tagLen + valLen]b;
		body[0] = 0x08;
		body[1] = opt & 0xff;
		body[2] = 0x12;
		body[3] = tagLen + valLen;
		var n = 4;
		if (tagLen == 2) {
			body[n] = (tag & 0x7f) | 0x80;
			n++;
			body[n] = (tag >> 7) & 0x7f;
		} else {
			body[n] = tag & 0x7f;
		}
		n = 4 + tagLen;
		if (valLen == 2) {
			body[n] = (val & 0x7f) | 0x80;
			n++;
			body[n] = (val >> 7) & 0x7f;
		} else {
			body[n] = val & 0x7f;
		}
		// CdC item 66: code 9 is measured on the wire as SET_PHOTOGRAPHY_OPTIONS,
		// whose body starts 0a 01 <opt> - not the body this encoder builds. The
		// body here (08 <opt> 12 <tag> <val>) is the SET_OPTIONS shape, measured
		// as code 7 (rea/10 §4, and the PC logs' code=7 SET_OPTIONS the product
		// closed at S-13). The stage of the candidate ladder must speak a frame
		// a log measured, so it carries the code of the shape it builds.
		return x5Frame(7, body);
	}

	function say(line as Lang.String) as Void {
		var n = log.size();
		if (n > 400) {
			// The bench keeps a bounded tail for the screen; the console keeps
			// everything, so nothing is lost from the record.
			log = [];
		}
		log.add(line);
		System.println(line);
	}
}
