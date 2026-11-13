using Toybox.Test;
using Toybox.System;
using Toybox.Time;
using Toybox.Application;
using Toybox.BluetoothLowEnergy;
using BLEBarrel;

// The protocol half of the unit suite, ported from PR #2's reference suite
// (@no84by, branch pr2-ref, X5 remote/test/StatusTest.mc, 18/18 green there).
// The frames are the real corpus and the two benches: the X5 fw 1.13.21 as the
// watch saw it, the Mac capture for the settings bodies. Names are kept
// wherever the behavior is the same, so the suite reads as a delta against the
// PR's; where the mainline reading of the same frame differs, the vector says
// so and asserts this repository's design (PROTOCOL_APK sections 15.27 and 16):
//   * the ask-15 answer is read for exactly 0 and 1; other state values are
//     real readings kept in x5CamState but they never move recState - the
//     state>0 machine is the 0x2010 push, the next vectors name it;
//   * the camera's mode is a reading (peekCamMode), never a move of the
//     watch's cursor - what to follow is the app's decision;
//   * the echo gate is observed through modeReqId / settingMayGo, the two
//     symbols this barrel keeps.

// One clean link per vector: everything the receive pipeline and the witnesses
// book across a link goes back to its before-the-first-ask value, and a fresh
// device answers. (The degraded set is deliberately not reset here - it
// belongs to the camera name, and one vector names it on purpose.)
function freshLink() {
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.mMessage = "Start";
	BLEBarrel.currentMode = "DefaultV";
	BLEBarrel.currentLabel = "Default Video";
	BLEBarrel.videoMode = true;
	BLEBarrel.startRecTime = Time.now();
	BLEBarrel.lastCmdSeq = -1;
	BLEBarrel.authProbeAsked = false;
	BLEBarrel.authProbeSeq = -1;
	BLEBarrel.authProbeStatus = -1;
	BLEBarrel.x5StatusAsked = false;
	BLEBarrel.x5StatusTries = 0;
	BLEBarrel.x5StorageAsked = false;
	BLEBarrel.x5StorageAskSeq = -1;
	BLEBarrel.x5PhotoSeq = -1;
	BLEBarrel.x5PhotoResult = null;
	BLEBarrel.x5WriteSeq = -1;
	BLEBarrel.x5WriteName = "";
	BLEBarrel.x5WriteResult = null;
	BLEBarrel.x5SubPhoto = null;
	BLEBarrel.x5SubVideo = null;
	BLEBarrel.modeReqId = null;
	BLEBarrel.modeHoldUntil = 0;
	BLEBarrel.camModeId = null;
	BLEBarrel.x5CamState = null;
	BLEBarrel.x5StorageState = null;
	BLEBarrel.x5StorageMode = null;
	BLEBarrel.x5BatteryLevel = null;
	BLEBarrel.x5BatteryPowerType = 0;
	BLEBarrel.x5BatteryArrived = false;
	BLEBarrel.x5BatteryLow = false;
	BLEBarrel.x5RxBuf = null;
	BLEBarrel.x5RxWant = 0;
	BLEBarrel.x5RxWasNotif = false;
	BLEBarrel.x5RxHeadSize = 0;
	BLEBarrel.x5RxLast = null;
	BLEBarrel.x5RxFrag = 0;
	BLEBarrel.x5RxFragCount = 0;
	BLEBarrel.deviceName = "X5 1ABCDE";
	return new BLEBarrel.BleDevice();
}

// A frame as this link carries it: the 16-octet envelope the corpus shows
// (declared total, then 04 00 00, the code as 16 little-endian bits, the 02
// flag, the sequence at octet 10, the 80 mark at 13) plus the body octets
// that survive the 20-octet wall. declared is what the header announces, and
// it may stand above the bytes actually handed over - that is the cut.
function frame(declared, codeLo, codeHi, seq, body) {
	var f = [declared & 0xff, (declared >> 8) & 0xff, 0, 0, 0x04, 0, 0, codeLo, codeHi, 0x02, seq & 0xff, (seq >> 8) & 0xff, 0, 0x80, 0, 0]b;
	f.addAll(body);
	return f;
}

function show(v) {
	if (v == null) {
		return "null";
	}
	return v.toString();
}

// Ask-15 answer of a camera already recording when the watch connected, the
// verified shape of PROTOCOL_APK 16 (0a 06 08 01 declared 24, the state the
// last octet across the wall): the reading lands in peekCamState and the one
// edge it is allowed to move - nothing pending on the watch - moves recState,
// which is the whole reason the ask exists.
(:test)
function connectSyncAdoptsRecording(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x41, [0x0a, 0x06, 0x08, 0x01]b));
	logger.debug("camState=" + show(d.peekCamState()) + " rec=" + BLEBarrel.recState.toString());
	return d.peekCamState() == 1 && d.peekCamRecording() && BLEBarrel.recState == BLEBarrel.stateStartRec;
}

// The same question answered by the PR's bench while Starlapse ran: the state
// octet reads 19, not 1. This barrel keeps the reading and moves nothing -
// only the 0x2010 push carries a state>0 machine, and the adoption of a mode
// found at connect is the app's decision over peekCamState, never this
// reader's. Divergence from the PR's own assertion, on purpose.
(:test)
function connectSyncUnknownStateStaysUnknown(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x41, [0x0a, 0x06, 0x08, 0x13]b));
	logger.debug("camState=" + show(d.peekCamState()) + " rec=" + BLEBarrel.recState.toString());
	return d.peekCamState() == 19 && !d.peekCamRecording() && BLEBarrel.recState == BLEBarrel.stateStopRec;
}

// Idle camera (state 0): recState stays at rest and the watch keeps the mode
// it chose - the answer of ask 15 never touches currentMode in this tree.
(:test)
function connectSyncIdleKeepsWatchMode(logger) {
	var d = freshLink();
	BLEBarrel.currentMode = "p3";
	BLEBarrel.currentLabel = "Photo Burst";
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x41, [0x0a, 0x06, 0x08, 0x00]b));
	logger.debug("mode=" + BLEBarrel.currentMode + " rec=" + BLEBarrel.recState.toString());
	return BLEBarrel.recState == BLEBarrel.stateStopRec && d.peekCamState() == 0 && BLEBarrel.currentMode.equals("p3");
}

// The first link of the bench of 12 nov. 17:59, octets verbatim from the wire
// log: that camera pushed no 0x2017 at all - the first frame of 16 octets or
// more across the wall was the code-200 auth answer, with nothing before it
// but 7-octet keepalive beats, then the cut state and card answers back to
// back. The app died on exactly that stream (Illegal Access, Out of Bounds,
// at the hex witness of x5DecodeNotif) and the suite had never fed a beat
// ahead of a first frame - the whole first-connection order was an untested
// leg. Here the three answers are read by their sequences and the beat closes
// nothing that was not open: the verdict is the stream surviving end to end.
(:test)
function firstLinkBeatsThenCode200Answers(logger) {
	var d = freshLink();
	var beat = [0x07, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00]b;
	d.onCharacteristicChanged(null, beat);
	d.onCharacteristicChanged(null, beat);
	d.onCharacteristicChanged(null, beat);
	BLEBarrel.authProbeSeq = 2;
	d.onCharacteristicChanged(null, frame(18, 0xc8, 0x00, 0x02, [0x08, 0x00]b));
	var auth = BLEBarrel.authProbeStatus;
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x03, [0x0a, 0x06, 0x08, 0x00]b));
	var cam = d.peekCamState();
	BLEBarrel.x5StorageAskSeq = 4;
	d.onCharacteristicChanged(null, frame(36, 0xc8, 0x00, 0x04, [0x0a, 0x12, 0x08, 0x00]b));
	var card = d.peekStorageState();
	logger.debug("auth=" + show(auth) + " cam=" + show(cam) + " card=" + show(card));
	return auth == 0 && cam == 0 && card == 0;
}

// The witness's own alphabet, at the octets the bench died on. Two sessions of
// 12 nov. lost the link inside the hex printer of x5DecodeNotif (Illegal Access,
// Out of Bounds) - on the same bytes that decode cleanly in the unit binary. The
// mask hypothesis says a ByteArray element above 0x7f reaches the printer as a
// negative number, which makes b >> 4 a negative index of HEX_DIGITS. This names
// what the engine really hands back (the debug line prints the raw element) and
// pins the digits owed for 0xc8, the code-200 answer the dead frames carried,
// and 0xff / 0x8a, which every 0x2017 push carries.
(:test)
function hexWitnessPrintsHighOctets(logger) {
	var hi = [0xc8, 0x80, 0xff, 0x7f, 0x00]b;
	logger.debug("raw0=" + hi[0].toString() + " raw2=" + hi[2].toString() + " hex=" + BLEBarrel.bytesToHex(hi));
	return BLEBarrel.bytesToHex(hi).equals("c880ff7f00");
}

// No request in flight, no browsing: a mode change made on the camera is read
// as a reading (peekCamMode names v2). The PR's barrel also moved its own
// cursor here; this one separates the reading from the decision (criterion:
// the decision belongs to the app).
(:test)
function cameraSideModeChangeFollowed(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x02]b));
	var cam = d.peekCamMode();
	logger.debug("camMode=" + show(cam));
	return cam != null && cam.equals("v2");
}

// The echo gate, both sides. The echo of this watch's own write opens the
// gate (modeReqId clears, as the PR's vector asserted through modeReq). An
// echo that is not the one in flight, while the hold runs, must not open it:
// the reading is still recorded (peekCamMode names the camera's truth) but
// settingMayGo stays false until the real echo or the hold's end.
(:test)
function modeEchoGateOpensOnOwnEchoOnly(logger) {
	var d = freshLink();
	d.noteModeWrite("v12");
	d.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x0c]b));
	var opened = BLEBarrel.modeReqId == null;
	d.noteModeWrite("v12");
	d.onCharacteristicChanged(null, frame(22, 0x53, 0x20, 0xff, [0x08, 0x64, 0x10, 0x02]b));
	var held = BLEBarrel.modeReqId != null && !d.settingMayGo();
	var read = d.peekCamMode();
	logger.debug("opened=" + opened + " held=" + held + " read=" + show(read));
	return opened && held && read != null && read.equals("v2");
}

// 0x2003 cut at the wall (declared 24, body 0a 06 08 01): the power type is
// the half that crosses, the level sits past it and stays null - the app
// shows unknown, never a number (PROTOCOL_APK 15.27).
(:test)
function batteryPushCutGivesPowerOnly(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(24, 0x03, 0x20, 0xff, [0x0a, 0x06, 0x08, 0x01]b));
	logger.debug("bat=" + show(d.peekBatteryLevel()) + " power=" + show(d.peekBatteryPowerType()) + " known=" + d.peekBatteryArrived());
	return d.peekBatteryPowerType() == 1 && d.peekBatteryArrived() && d.peekBatteryLevel() == null;
}

// The same push whole (24 octets arrive - a bigger-bond link, or this test):
// the nested field 2 is the percentage, 0x31 = 49 as the PR's frame carries.
(:test)
function batteryPushWholeGivesLevel(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(24, 0x03, 0x20, 0xff, [0x0a, 0x06, 0x08, 0x00, 0x10, 0x31, 0x20, 0x00]b));
	logger.debug("bat=" + show(d.peekBatteryLevel()));
	return d.peekBatteryLevel() == 49;
}

// The 0x2004 low-battery alarm stands... until the camera says it runs on
// external power (power_type 1 in a 0x2003): the rule the PR's reader applies
// too, kept with the alarm as a fact of the wire log only.
(:test)
function batteryLowClearedByExternalPower(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(18, 0x04, 0x20, 0xff, [0x08, 0x01]b));
	var low = d.peekBatteryLow();
	d.onCharacteristicChanged(null, frame(24, 0x03, 0x20, 0xff, [0x0a, 0x06, 0x08, 0x01, 0x10, 0x31, 0x20, 0x00]b));
	logger.debug("low=" + low + " after=" + d.peekBatteryLow());
	return low && !d.peekBatteryLow();
}

// 0x2006 card update, whole at 20 octets: the card state moves 1 then 0, the
// slot the connect-time card ask shares.
(:test)
function cardPushState(logger) {
	var d = freshLink();
	d.onCharacteristicChanged(null, frame(20, 0x06, 0x20, 0xff, [0x08, 0x01, 0x10, 0x00]b));
	var ok1 = d.peekStorageState() == 1;
	d.onCharacteristicChanged(null, frame(20, 0x06, 0x20, 0xff, [0x08, 0x00, 0x10, 0x00]b));
	logger.debug("card=" + show(d.peekStorageState()));
	return ok1 && d.peekStorageState() == 0;
}

// Real GET_STORAGE 166 answer (Mac capture, declared 36), cut at 20: the
// answer is taken by its sequence - the card ask armed it - and its code-200
// shape never reaches the capture-state reading. The free and total sizes sit
// past the cut and stay unknown, as the rule says.
(:test)
function storageReplyCutGivesCardState(logger) {
	var d = freshLink();
	BLEBarrel.x5StorageAskSeq = 0x0a;
	d.onCharacteristicChanged(null, frame(36, 0xc8, 0x00, 0x0a, [0x0a, 0x12, 0x08, 0x00]b));
	logger.debug("card=" + show(d.peekStorageState()) + " free=" + show(d.peekStorageFreeBytes()));
	return BLEBarrel.x5StorageAskSeq == -1 && d.peekStorageState() == 0 && d.peekStorageFreeBytes() == null;
}

// Real watch log, verbatim from the PR: after STOP the X5 keeps pushing
// 0x2010 (state 0x18 while it finishes the file). Read as a start it undid
// the user's stop; while already recording it restarted the clock at 0. The
// push confirms and never re-starts: the stop stands through the pending
// stateStopping, and a repeat push leaves startRecTime put.
(:test)
function captureStatusPushDoesNotRestartRecording(logger) {
	var d = freshLink();
	var push = frame(20, 0x10, 0x20, 0xff, [0x08, 0x18, 0x10, 0x06]b);
	BLEBarrel.recState = BLEBarrel.stateStopping;
	d.onCharacteristicChanged(null, push);
	var afterStop = BLEBarrel.recState;
	BLEBarrel.recState = BLEBarrel.stateStartRec;
	var t0 = new Time.Moment(Time.now().value() - 60);
	BLEBarrel.startRecTime = t0;
	d.onCharacteristicChanged(null, push);
	var moved = BLEBarrel.startRecTime.value() != t0.value();
	logger.debug("afterStop=" + afterStop + " start moved=" + moved);
	return afterStop != BLEBarrel.stateStartRec && !moved;
}

// A settings write waits while a mode change is unconfirmed, and never longer
// than the mode hold (a camera that never echoes must not block settings).
// The PR's vector verbatim, through this barrel's two symbols.
(:test)
function settingWaitsForModeChange(logger) {
	var d = freshLink();
	var now = System.getTimer();
	BLEBarrel.modeReqId = "v0";
	BLEBarrel.modeHoldUntil = now + 3000;
	var pending = d.settingMayGo();
	BLEBarrel.modeReqId = null;
	var confirmed = d.settingMayGo();
	BLEBarrel.modeReqId = "v0";
	BLEBarrel.modeHoldUntil = now - 1;
	var expired = d.settingMayGo();
	BLEBarrel.modeReqId = null;
	BLEBarrel.modeHoldUntil = 0;
	logger.debug("pending=" + pending + " confirmed=" + confirmed + " expired=" + expired);
	return !pending && confirmed && expired;
}

// Settings frames match the bodies confirmed on the camera screen (the PR's
// Mac-session oracle, fw 1.13.21), through this barrel's builders (x5BodyFrame
// is frameX5's shape, kept byte-for-byte by the port) and this app's ported
// Settings page. The shutdown frame is this barrel's cmdShutdownX5 constant -
// the PR asked its builder for the same bytes.
function bodyHex(f) {
	var s = "";
	for (var i = 16; i < f.size(); i++) {
		s += f[i].format("%02x");
	}
	return s;
}

(:test)
function settingsFramesMatchCamera(logger) {
	var d = freshLink();
	BLEBarrel.menuLevel = 2;
	var ok = true;
	// SOUND Off = SET_OPTIONS MUTE 1 (camera read back 70 01)
	var m = Settings.frames(Settings.rows("set")[0], 1)[0];
	ok = ok && m[7] == 0x07 && bodyHex(m).equals("080e12027001");
	var sd = BLEBarrel.cmdShutdownX5;
	ok = ok && sd[7] == 0xDB && sd[8] == 0 && sd.size() == 16 && sd[0] == 16;
	// Timelapse interval 5 s (timelapse mode 1)
	var f = BLEBarrel.setLapseX5(1, 5000);
	ok = ok && f[7] == 0x12 && bodyHex(f).equals("0a031088271001") && f[0] == f.size();
	// Starlapse duration 10 min (timelapse mode 5, field 1)
	f = BLEBarrel.setLapseDurX5(5, 600);
	ok = ok && bodyHex(f).equals("0a0308d8041005");
	// Video 4K/120 = 348
	f = BLEBarrel.setPhotoOptX5(7, 31, 348);
	ok = ok && f[7] == 0x09 && bodyHex(f).equals("081f1204f801dc021807");
	// EV -0.3 in Video: -3 zig-zag = 5
	var evRow = Settings.ev(7);
	var i = evRow[5].indexOf(-3);
	f = Settings.frames(evRow, evRow[5][i])[0];
	ok = ok && bodyHex(f).equals("0807120238051807") && evRow[2][i].equals("-0.3") && evRow[2][evRow[7]].equals("±0.0");
	// Burst 10P/1s: two writes, 44 then 51, function mode 5
	var b = Settings.frames(Settings.rows("p3")[0], [10, 1]);
	ok = ok && b.size() == 2 && bodyHex(b[0]).equals("082c1203e0020a1805") && bodyHex(b[1]).equals("083312039803011805");
	logger.debug("ev " + bodyHex(f) + " burst " + bodyHex(b[0]));
	return ok;
}

// The shot's three-way verdict, by sequence, as the PR's reading: a code-200
// that declares more than the bare frame means the camera took the order and
// the state octet follows; the empty 16-octet ack is a refused shape (the
// :noShot class); a 400 answering the shot's sequence is its rejection, not
// a mode entry to mark. Reading clears: one answer colors one screen.
(:test)
function photoAckThreeWayVerdicts(logger) {
	var d = freshLink();
	BLEBarrel.lastCmdSeq = 0x55;
	d.armPhotoAck();
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x55, [0x0a, 0x06, 0x08, 0x00]b));
	var v1 = d.photoResultTaken();
	BLEBarrel.lastCmdSeq = 0x56;
	d.armPhotoAck();
	d.onCharacteristicChanged(null, frame(16, 0xc8, 0x00, 0x56, []b));
	var v2 = d.photoResultTaken();
	BLEBarrel.lastCmdSeq = 0x57;
	d.armPhotoAck();
	d.onCharacteristicChanged(null, frame(18, 0x90, 0x01, 0x57, [0x08, 0x01]b));
	var v3 = d.photoResultTaken();
	var cleared = d.photoResultTaken() == null;
	logger.debug("v1=" + (v1 == :ok ? "ok" : (v1 == :noShot ? "noShot" : "other")) +
		" v2=" + (v2 == :noShot ? "noShot" : "other") + " v3=" + (v3 == :rejected ? "rejected" : "other"));
	return v1 == :ok && v2 == :noShot && v3 == :rejected && cleared;
}

// A settings write's own answer, and the refusal that belongs to a mode
// write instead: the 400 whose sequence this watch stamped, with the echo
// gate naming the entry it sent, marks that entry degraded and closes the
// write cycle - the axis the menu reads, kept by camera name.
(:test)
function writeAckOkRefusalMarksDegraded(logger) {
	var d = freshLink();
	BLEBarrel.lastCmdSeq = 0x66;
	d.armWriteAck("ev");
	d.onCharacteristicChanged(null, frame(16, 0xc8, 0x00, 0x66, []b));
	var wv = d.settingResultTaken();
	var d2 = freshLink();
	d2.noteModeWrite("zz");
	BLEBarrel.lastCmdSeq = 0x77;
	d2.onCharacteristicChanged(null, frame(18, 0x90, 0x01, 0x77, [0x08, 0x01]b));
	var marked = d2.isEntryDegraded("zz");
	var released = BLEBarrel.modeReqId == null;
	logger.debug("writeVerdict=" + (wv == :ok ? "ok" : "other") + " marked=" + marked + " gateReleased=" + released);
	return wv == :ok && marked && released;
}

// The camera going to standby drops the link, possibly reporting it twice.
// The teardown is the same both times and its contract holds: the device is
// gone, one re-scan is open (the guard refuses a second), and every
// connect-time ask is re-armed so the next bond asks again. The PR watched
// the same fault through its profile-registration counter; this barrel names
// the contract directly.
(:test)
function disconnectRearmsAsksKeepsOneScan(logger) {
	var d = freshLink();
	BLEBarrel.x5StorageAskSeq = 0x33;
	BLEBarrel.x5StatusAsked = true;
	d.onCharacteristicChanged(null, frame(24, 0x03, 0x20, 0xff, [0x0a, 0x06, 0x08, 0x01]b));
	d.onConnectedStateChanged(null, BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED);
	var scanOpen = d.scanning;
	var gone = d.device == null;
	var rearmed = !BLEBarrel.x5StatusAsked && BLEBarrel.x5StorageAskSeq == -1 && BLEBarrel.authProbeSeq == -1;
	d.onConnectedStateChanged(null, BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED);
	var stillOne = d.scanning;
	logger.debug("scan=" + scanOpen + " gone=" + gone + " rearmed=" + rearmed);
	return scanOpen && gone && rearmed && stillOne && BLEBarrel.recState == BLEBarrel.stateStopRec;
}

// The menu's level axis, at the unit level (the PR had no equivalent - the
// chain is this repository's model): the table answers for every model it
// names, an unknown name answers -1 and the application's fallback is level
// 0, level 0 carries no mode row and no v*/p* id resolves there, level 1
// answers with its own keys - and those keys reach this app's frame resolver,
// which is how the legacy envelope's start/stop rungs keep being patched at
// the selection. From REPLACE_FROM up a level replaces the chain - the bench
// of 12 nov. chose that path (the real X5 acquitted the stacked legacy frames
// without moving, and their no-frame rows blocked the wheel): no level-1 row
// resolves through the X5 line, its measured ids do, and the X6 level answers
// its own rows alone. A confirmed level is kept by name for the next bond,
// and a known name never lets it override the table.
(:test)
function levelsChainTableFallbackAndConfirm(logger) {
	var d = freshLink();
	var ok = true;
	var i = 0;
	while (i < Levels.models.size()) {
		if (Levels.levelOfName(Levels.models[i]) != Levels.modelLevels[i]) {
			ok = false;
		}
		i++;
	}
	ok = ok && Levels.levelOfName("X9 Tomorrow") == -1;
	ok = ok && Levels.rowsMain(0).size() == 0;
	ok = ok && Levels.rowOfId(0, "v0") == null;
	var r2 = Levels.rowOfId(2, "v0");
	ok = ok && r2 != null && r2[Levels.RID].equals("v0");
	// L2 replaces: the legacy ids of L1 answer nothing at L2, and the measured
	// ids answer their own row. The frame resolver still knows the legacy keys
	// (they belong to L1 cameras); it is the menu that no longer offers them.
	ok = ok && Levels.rowOfId(2, "TimeLapse") == null;
	ok = ok && Levels.rowOfId(2, "PhotoHDR") == null;
	var p0 = Levels.rowOfId(2, "p0");
	ok = ok && p0 != null && p0[Levels.RKEY].equals("p0") && entryFrame("p0") != null;
	// L3 answers its own rows alone, like every replacing level.
	ok = ok && Levels.rowOfId(3, "v0") == null;
	var r1 = Levels.rowOfId(1, "TimeLapse");
	ok = ok && r1 != null && r1[Levels.RKEY].equals("TimeLapse") && entryFrame("TimeLapse") != null;
	ok = ok && entryFrame("PhotoHDR") != null;
	ok = ok && entryFrame("zz no key") == null;
	d.noteConfirmedLevel("ZZ 9", 1);
	var stored = Application.getApp().getProperty("lvl.ZZ 9");
	ok = ok && stored != null && stored == 1;
	ok = ok && Levels.levelOfName("X5") == 2;
	logger.debug("stored=" + show(stored));
	return ok;
}

// The mode axis: the keep is the camera's own confirmation, the load is per
// name, and the pose that the screen takes is one decision (Levels.poseFor).
// The pose exists because the bench of 12 nov. showed a screen naming a mode no
// row carries - "Default Video", the pose open() leaves, over the eleven dots of
// the X5 line, with an empty Settings row list - and the same title over the
// rows of another row after a power cycle. The screen is drawn from two data
// (the barrel's currentLabel for the title, this app's currentModeId for the
// option rows), so the pose is due when they no longer name one row. The order
// of the choice is the user's rule of that bench: the last mode this camera
// confirmed, else the normal video of the level; a coherent pair is never moved
// (browsing, the resolution legs); a level with no rows (0) keeps the app's
// legacy pose.
(:test)
function modeKeepLoadAndPoseForTheLevel(logger) {
	var d = freshLink();          // freshLink names the bond: deviceName = "X5 1ABCDE"
	var ok = true;

	// The keep answers only a confirmed echo, and only under a name.
	d.noteConfirmedMode(null);
	d.noteConfirmedMode("");
	var keptNone = Application.getApp().getProperty("mode.X5 1ABCDE");
	d.noteConfirmedMode("p0");
	var stored = Application.getApp().getProperty("mode.X5 1ABCDE");
	ok = ok && stored != null && stored.equals("p0");
	// Confirmed now, kept now: the same echo answers through peekKeptModeId
	// without any reload. The bench of 12 nov., third session, needed exactly
	// this - the paired device came back on its own, no scan classified it,
	// loadKeptMode never ran, and the pose had to name the photo mode this
	// process had just confirmed.
	var live = d.peekKeptModeId();
	ok = ok && live != null && live.equals("p0");
	// A name of its own keeps its own mode: the second camera inherits nothing.
	BLEBarrel.deviceName = "Q1 0000ZZ";
	d.loadKeptMode();
	ok = ok && d.peekKeptModeId() == null;
	BLEBarrel.deviceName = "X5 1ABCDE";
	d.loadKeptMode();
	var loaded = d.peekKeptModeId();
	ok = ok && loaded != null && loaded.equals("p0");
	logger.debug("kept=" + show(stored) + " loaded=" + show(loaded) + " before=" + show(keptNone));

	// The pose is due on the screen's pair of data, not on a level change: the
	// title is the barrel's currentLabel, the rows are the app's currentModeId.
	// The start pose of open() is not a row, so a pose is due, and the kept id
	// wins.
	var poseKept = Levels.poseFor(2, "p0", "DefaultV", "Default Video");
	ok = ok && poseKept != null && poseKept[Levels.RID].equals("p0");
	// The bench of 12 nov., second session: the title DEFAULT VIDEO over the
	// photo row's rows (the camera was power-cycled, the barrel had re-posed its
	// label while this app still carried the photo id). One row answers both
	// data again, and it is the row that id names.
	var pair = Levels.poseFor(2, "p0", "p0", "Default Video");
	ok = ok && pair != null && pair[Levels.RID].equals("p0") && pair[Levels.RLB].equals("Photo");
	// A coherent pair answers nothing: the wheel stays where the user left it,
	// the resolution legs included (their row is a row of this level too).
	ok = ok && Levels.poseFor(2, "p0", "p0", "Photo") == null;
	ok = ok && Levels.poseFor(2, "p3", "v6", "Loop Recording") == null;
	ok = ok && Levels.poseFor(2, "p0", "r167", "8K 30") == null;
	// Nothing kept: the first row of the level, the normal video of that line.
	var first = Levels.poseFor(2, null, "DefaultV", "Default Video");
	ok = ok && first != null && first[Levels.RID].equals("v0") && first[Levels.RLB].equals("Video");
	// An id of another level never comes back through this level's rows.
	var fb = Levels.poseFor(2, "TimeLapse", "DefaultV", "Default Video");
	ok = ok && fb != null && fb[Levels.RID].equals("v0");
	// The level the user forced to: the kept id of the X5 line is not a row of
	// the UCD2 level, so that level's own first row answers.
	var l3 = Levels.poseFor(3, "p0", "v6", "Loop Recording");
	ok = ok && l3 != null && Levels.rowOfId(3, l3[Levels.RID]) != null;
	// No rows: nothing to pose, the app's legacy pose stays (level 0).
	ok = ok && Levels.poseFor(0, "p0", "DefaultV", "Default Video") == null;
	ok = ok && Levels.poseFor(0, null, null, null) == null;
	logger.debug("pose crossed");
	return ok;
}

// The trigger of the three first asks, corrected by the bench of 12 nov. (real
// X5 fw 1.13.21 over the PC Bluetooth, trace lifted by int-x5-build\benchbuild.ps1):
// the profile-register callback runs at OPEN, right after the scan turns on and
// before any pair - the log prints it with status=0 in both sessions. The asks
// armed there came due while no device existed and were refused by the ask
// guards: the first session connected, started and stopped a recording without
// one question reaching the wire. The asks arm at armLinkAsks now, at the site
// the walk finds the LBS characteristic and the link is demonstrably writable -
// the 16:15 session then asked them all and the camera answered all three.
// What this vector pins is the split, on the schedule itself: calling the
// callback by name leaves the booking untouched, calling armLinkAsks books the
// three, the probe first. That the asks cross the wire on a real connect is
// stage E1's oracle - this host has no GATT device to walk, and no vector here
// pretends to have seen one.
(:test)
function asksArmAtTheLinkNotTheProfile(logger) {
	var dev = freshLink();
	// Open the schedule the way the link itself does, not by assigning null to
	// the module dates: the default type check flow-types a field written null
	// here into the comparisons far below (and refuses lt on Null/Null), while
	// dates cleared inside methods stay the declared Number or Null. The probe
	// has no cancel: onAuthProbe into a link with no device is refused by its
	// own guard, after clearing the date.
	dev.cancelStatusTimer();
	dev.cancelStorageAskTimer();
	dev.cancelRetry();
	dev.cancelPendingStart();
	dev.onAuthProbe();
	BLEBarrel.authProbeAsked = false;
	BLEBarrel.x5StatusAsked = false;
	BLEBarrel.x5StorageAsked = false;
	var before = dev.earliestAskDue();
	dev.onProfileRegister(BLEBarrel.LBS_SERVICE, BluetoothLowEnergy.STATUS_SUCCESS);
	var quiet = dev.earliestAskDue() == before &&
		BLEBarrel.authProbeDue == null && BLEBarrel.x5StatusDue == null &&
		BLEBarrel.x5StorageAskDue == null;
	dev.armLinkAsks();
	// The ordering of the three bookings, observed the way the default type
	// check accepts nullable module fields: every relational comparison sits
	// right after the null guard of its own left operand (linkScheduleKeepsNearestDate
	// in UiTest observes the same dates in the same shape).
	var booked = true;
	booked = booked && BLEBarrel.authProbeDue != null && BLEBarrel.authProbeDue < BLEBarrel.x5StatusDue &&
		BLEBarrel.x5StatusDue != null && BLEBarrel.x5StatusDue < BLEBarrel.x5StorageAskDue &&
		BLEBarrel.x5StorageAskDue != null;
	var probeFirst = dev.earliestAskDue() == BLEBarrel.authProbeDue;
	logger.debug("quiet=" + quiet + " booked=" + booked + " probeFirst=" + probeFirst);
	return quiet && booked && probeFirst;
}

// The stop tail, on the leg PR #2's bench found and this barrel left open:
// during a stop the camera sends state=1 and THEN state=0, and a real start
// arrives only after the 0 - found on a Descent Mk3i with the same X5 fw
// 1.13.21 (no84by 34a00c2). The 0x2010 push path refuses this read since the
// vector above; the status ANSWER was the leg never guarded - the stop's own
// retry asks command 15, and its state=1 used to restart the clock and undo
// the user's stop.
(:test)
function statusAnswerStopTailDoesNotRestart(logger) {
	var d = freshLink();
	BLEBarrel.recState = BLEBarrel.stateStopping;
	BLEBarrel.recJoined = false;
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x73, [0x0a, 0x06, 0x08, 0x01]b));
	var stopStands = BLEBarrel.recState == BLEBarrel.stateStopping && !BLEBarrel.recJoined;
	// The state-0 of the tail: at rest this is the confirmation of the stop;
	// while the watch is stopping the stop's own retry path owns that move
	// (applyCamState names the split), so the machine not moving here is the
	// design, and the line records it rather than pretending.
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x74, [0x0a, 0x06, 0x08, 0x00]b));
	logger.debug("stopStands=" + stopStands.toString() + " recAfterTail=" + BLEBarrel.recState.toString());
	return stopStands;
}

// A recording the watch joined is named as one. The elapsed seconds sit past
// the cut of every status answer (declared=24 arrived=20 in our own traces) and
// no push carries them, so a clock counting from the join would claim to be
// the recording's own length. The flag below is what the screen reads instead:
// REC and a joined note (the same reading on PR #2's bench, no84by 5383db9).
// The split tested here is the one the transition makes: the same state=1,
// from rest, joined; from the app's own pending start, ours.
(:test)
function recordingFoundFromRestIsMarkedJoined(logger) {
	var d = freshLink();
	// The status answer, from rest: joined.
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.recJoined = false;
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x75, [0x0a, 0x06, 0x08, 0x01]b));
	var answerJoined = BLEBarrel.recState == BLEBarrel.stateStartRec && BLEBarrel.recJoined;
	// The same answer, while the watch's own start is pending (stateStarting
	// is only ever the app's press, the InputDelegate writes it): ours.
	BLEBarrel.recState = BLEBarrel.stateStarting;
	BLEBarrel.recJoined = false;
	d.onCharacteristicChanged(null, frame(24, 0xc8, 0x00, 0x76, [0x0a, 0x06, 0x08, 0x01]b));
	var answerOurs = BLEBarrel.recState == BLEBarrel.stateStartRec && !BLEBarrel.recJoined;
	// The 0x2010 push, from rest: joined. The frame is a whole 20 (declared
	// equals arrived), field 1 carries the state, the shape captureStatusPush-
	// DoesNotRestartRecording above uses.
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.recJoined = false;
	d.onCharacteristicChanged(null, frame(20, 0x10, 0x20, 0xff, [0x08, 0x01, 0x10, 0x00]b));
	var pushJoined = BLEBarrel.recState == BLEBarrel.stateStartRec && BLEBarrel.recJoined;
	// And the watch's own start, confirmed by the recording report: ours. The
	// report code never reaches the notification side, so the flag clears.
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.recJoined = true;
	d.onCharacteristicChanged(null, frame(22, 0x40, 0x00, 0x77, [0x08, 0x01, 0x01]b));
	var reportOurs = BLEBarrel.recState == BLEBarrel.stateStartRec && !BLEBarrel.recJoined;
	logger.debug("answerJoined=" + answerJoined.toString() + " answerOurs=" + answerOurs.toString() + " pushJoined=" + pushJoined.toString() + " reportOurs=" + reportOurs.toString());
	return answerJoined && answerOurs && pushJoined && reportOurs;
}
