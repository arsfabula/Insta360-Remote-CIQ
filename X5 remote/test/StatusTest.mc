using Toybox.Test;
using BLEBarrel;

// Real X5 reply from the watch log: GET_CURRENT_CAPTURE_STATUS answered while Starlapse runs,
// cut at 20 bytes by Connect IQ. Connect sync must adopt Starlapse and show recording.
(:test)
function connectSyncAdoptsStarlapse(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.currentMode = "v0"; BLEBarrel.currentLabel = "Video"; BLEBarrel.videoMode = true;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	d.capSeq = 0x41;
	d.syncOnConnect = true;
	d.reassembleX5([0x18, 0, 0, 0, 0x04, 0, 0, 0xc8, 0x00, 0x02, 0x41, 0, 0, 0x80, 0, 0, 0x0a, 0x06, 0x08, 0x13]b);
	logger.debug("mode=" + BLEBarrel.currentMode + " label=" + BLEBarrel.currentLabel + " rec=" + BLEBarrel.recState);
	return BLEBarrel.currentMode.equals("p7") && BLEBarrel.recState == BLEBarrel.stateStartRec;
}

// Idle camera (state 0): the watch keeps its own mode (and pushes it to the camera).
(:test)
function connectSyncIdleKeepsWatchMode(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.currentMode = "p3"; BLEBarrel.currentLabel = "Photo Burst"; BLEBarrel.videoMode = false;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	d.capSeq = 0x42;
	d.syncOnConnect = true;
	d.reassembleX5([0x18, 0, 0, 0, 0x04, 0, 0, 0xc8, 0x00, 0x02, 0x42, 0, 0, 0x80, 0, 0, 0x0a, 0x06, 0x08, 0x00]b);
	logger.debug("mode=" + BLEBarrel.currentMode + " rec=" + BLEBarrel.recState);
	return BLEBarrel.currentMode.equals("p3") && BLEBarrel.recState == BLEBarrel.stateStopRec;
}

// Real 0x2053 from the watch log (after Photo Burst was set): watch follows the camera.
(:test)
function submodeChangeFollowsCamera(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.currentMode = "v0"; BLEBarrel.currentLabel = "Video"; BLEBarrel.videoMode = true;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	d.reassembleX5([0x16, 0, 0, 0, 0x04, 0, 0, 0x53, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x03, 0x10, 0x64]b);
	logger.debug("mode=" + BLEBarrel.currentMode + " label=" + BLEBarrel.currentLabel);
	return BLEBarrel.currentMode.equals("p3") && !BLEBarrel.videoMode;
}

// Real 0x2003 from the replug monitor (USB plugged), as Connect IQ delivers it: cut at 20 bytes
// right after power_type. Charging is read, the level is not invented.
(:test)
function batteryPushCutGivesPowerOnly(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.camBattery = null; BLEBarrel.camPowerKnown = false; BLEBarrel.camOnPower = false;
	d.reassembleX5([0x18, 0, 0, 0, 0x04, 0, 0, 0x03, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x0a, 0x06, 0x08, 0x01]b);
	var ok1 = BLEBarrel.camPowerKnown && BLEBarrel.camOnPower && BLEBarrel.camBattery == null;
	// unplugged: 0a 06 08 00 ...
	d.reassembleX5([0x18, 0, 0, 0, 0x04, 0, 0, 0x03, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x0a, 0x06, 0x08, 0x00]b);
	logger.debug("bat=" + BLEBarrel.camBattery + " power=" + BLEBarrel.camOnPower + " known=" + BLEBarrel.camPowerKnown);
	return ok1 && BLEBarrel.camPowerKnown && !BLEBarrel.camOnPower && BLEBarrel.camBattery == null;
}

// Whole 24-byte 0x2003 (a link without the 20-byte cut): level is read too.
(:test)
function batteryPushWholeGivesLevel(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.camBattery = null;
	d.reassembleX5([0x18, 0, 0, 0, 0x04, 0, 0, 0x03, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x0a, 0x06, 0x08, 0x00, 0x10, 0x31, 0x20, 0x00]b);
	logger.debug("bat=" + BLEBarrel.camBattery);
	return BLEBarrel.camBattery == 49 && !BLEBarrel.camOnPower;
}

// 0x2004 BATTERY_LOW: the header alone carries the meaning.
(:test)
function batteryLowPush(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.camBattLow = false;
	d.reassembleX5([0x10, 0, 0, 0, 0x04, 0, 0, 0x04, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0]b);
	return BLEBarrel.camBattLow;
}

// 0x2006 card update, 20 bytes whole (body 08 <state> 10 <location>): no card, then OK.
(:test)
function cardPushState(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.camCard = null;
	d.reassembleX5([0x14, 0, 0, 0, 0x04, 0, 0, 0x06, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x01, 0x10, 0x00]b);
	var ok1 = BLEBarrel.camCard == 1;
	d.reassembleX5([0x14, 0, 0, 0, 0x04, 0, 0, 0x06, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x00, 0x10, 0x00]b);
	logger.debug("card=" + BLEBarrel.camCard);
	return ok1 && BLEBarrel.camCard == 0;
}

// Real GET_STORAGE 08 00 reply (Mac capture, 36 B), cut at 20 bytes: card state 0 is read.
(:test)
function storageReplyCutGivesCardState(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.camCard = null; BLEBarrel.camFree = null;
	d.storSeq = 0x0a;
	d.reassembleX5([0x24, 0, 0, 0, 0x04, 0, 0, 0xc8, 0x00, 0x02, 0x0a, 0, 0, 0x80, 0, 0, 0x0a, 0x12, 0x08, 0x00]b);
	logger.debug("card=" + BLEBarrel.camCard + " free=" + BLEBarrel.camFree);
	return BLEBarrel.camCard == 0 && BLEBarrel.camFree == null;
}

// Real sequence from the watch log: watch sent Timelapse (v2), user already browsed on to
// Starlapse (v12); the late v2 echo must not pull the cursor back.
(:test)
function staleModeEchoIgnored(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.modeReq = "v12";
	BLEBarrel.modeHoldUntil = 0;
	BLEBarrel.holdMode(3000);
	BLEBarrel.currentMode = "v12"; BLEBarrel.currentLabel = "Star Video"; BLEBarrel.videoMode = true;
	d.reassembleX5([0x16, 0, 0, 0, 0x04, 0, 0, 0x53, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x64, 0x10, 0x02]b);
	var ok1 = BLEBarrel.currentMode.equals("v12");
	d.reassembleX5([0x16, 0, 0, 0, 0x04, 0, 0, 0x53, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x64, 0x10, 0x0c]b);
	logger.debug("mode=" + BLEBarrel.currentMode + " req=" + BLEBarrel.modeReq);
	return ok1 && BLEBarrel.currentMode.equals("v12") && BLEBarrel.modeReq == null;
}

// No request in flight, no browsing: a change made on the camera is still followed.
(:test)
function cameraSideModeChangeFollowed(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	BLEBarrel.modeReq = null; BLEBarrel.modeHoldUntil = 0;
	BLEBarrel.currentMode = "v0"; BLEBarrel.currentLabel = "Video"; BLEBarrel.videoMode = true;
	d.reassembleX5([0x16, 0, 0, 0, 0x04, 0, 0, 0x53, 0x20, 0x02, 0xff, 0x8a, 0x43, 0xf4, 0, 0, 0x08, 0x64, 0x10, 0x02]b);
	return BLEBarrel.currentMode.equals("v2");
}

// Settings frames match the bodies confirmed on the camera screen (Mac session, fw 1.13.21).
function bodyHex(f) {
	var s = "";
	for (var i = 16; i < f.size(); i++) { s += f[i].format("%02x"); }
	return s;
}

(:test)
function settingsFramesMatchCamera(logger) {
	BLEBarrel.deviceName = "X5 1ABCDE";
	var ok = true;
	// SOUND Off = SET_OPTIONS MUTE 1 (camera read back 70 01)
	var m = Settings.frames(Settings.rows("set")[0], 1)[0];
	ok = ok && m[7] == 0x07 && bodyHex(m).equals("080e12027001");
	var sd = BLEBarrel.shutdownX5();
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
	logger.debug("4k120 " + bodyHex(f));
	// EV -0.3 in Video: -3 zig-zag = 5
	var evRow = Settings.ev(7);
	var i = evRow[5].indexOf(-3);
	f = Settings.frames(evRow, evRow[5][i])[0];
	ok = ok && bodyHex(f).equals("0807120238051807") && evRow[2][i].equals("-0.3") && evRow[2][evRow[7]].equals("±0.0");
	logger.debug("ev " + bodyHex(f) + " " + evRow[2][i] + " n=" + evRow[5].size());
	// Burst 10P/1s: two writes, 44 then 51, function mode 5
	var b = Settings.frames(Settings.rows("p3")[0], [10, 1]);
	ok = ok && b.size() == 2 && bodyHex(b[0]).equals("082c1203e0020a1805") && bodyHex(b[1]).equals("083312039803011805");
	logger.debug("burst " + bodyHex(b[0]) + " " + bodyHex(b[1]));
	return ok;
}

// Camera goes to standby: the link drops, possibly several times. A disconnect must not
// re-run the app start-up (no second profile registration: Connect IQ allows only a few,
// then every reconnect fails; no reload of the recording state saved at the last close).
(:test)
function disconnectDoesNotReinit(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	Toybox.Application.Storage.setValue("recState", BLEBarrel.stateStartRec);   // stale saved state
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	var before = BLEBarrel.profileRegs;
	d.onConnectedStateChanged(null, Toybox.BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED);
	d.scanning = false;
	d.onConnectedStateChanged(null, Toybox.BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED);
	Toybox.Application.Storage.deleteValue("recState");
	logger.debug("regs " + before + "->" + BLEBarrel.profileRegs + " rec=" + BLEBarrel.recState);
	return BLEBarrel.profileRegs == before && BLEBarrel.recState == BLEBarrel.stateStopRec;
}

// Real watch log: after STOP the X5 keeps pushing 0x2010 capture status (08 18 = state 24 while it
// finishes the file). The legacy start/stop check (command byte 0x10) read it as "recording
// started": the watch went back to recording and the timer restarted at 0.
(:test)
function captureStatusPushDoesNotRestartRecording(logger) {
	var d = new BLEBarrel.BleDevice();
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.videoMode = true; BLEBarrel.photoSeq = -1; BLEBarrel.lapseSeq = -1;
	var push = [0x14, 0, 0, 0, 0x04, 0, 0, 0x10, 0x20, 0x02, 0xff, 0, 0, 0x80, 0, 0, 0x08, 0x18, 0x10, 0x06]b;
	BLEBarrel.recState = BLEBarrel.stateStopping;
	d.onCharacteristicChanged(null, push);
	var afterStop = BLEBarrel.recState;
	// while recording, the same push must not reset the start time
	BLEBarrel.recState = BLEBarrel.stateStartRec;
	var t0 = new Toybox.Time.Moment(Toybox.Time.now().value() - 60);
	BLEBarrel.startRecTime = t0;
	d.onCharacteristicChanged(null, push);
	logger.debug("afterStop=" + afterStop + " start moved=" + (BLEBarrel.startRecTime.value() != t0.value()));
	return afterStop != BLEBarrel.stateStartRec && BLEBarrel.startRecTime.value() == t0.value();
}

// Watch log: RES sent right after the app switched the camera to Video was refused (400); the same
// frame a few seconds later was accepted. A setting waits while a mode change is unconfirmed,
// but never longer than the mode hold (a camera that never echoes must not block settings).
(:test)
function settingWaitsForModeChange(logger) {
	var now = Toybox.System.getTimer();
	BLEBarrel.modeReq = "v0"; BLEBarrel.modeHoldUntil = now + 3000;
	var pending = BLEBarrel.settingMayGo();
	BLEBarrel.modeReq = null;
	var confirmed = BLEBarrel.settingMayGo();
	BLEBarrel.modeReq = "v0"; BLEBarrel.modeHoldUntil = now - 1;
	var expired = BLEBarrel.settingMayGo();
	BLEBarrel.modeReq = null; BLEBarrel.modeHoldUntil = 0;
	logger.debug("pending=" + pending + " confirmed=" + confirmed + " expired=" + expired);
	return !pending && confirmed && expired;
}
