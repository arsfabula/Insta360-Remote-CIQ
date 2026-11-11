using Toybox.WatchUi as Ui;
using Toybox.Application;
using Toybox.Attention;
using Toybox.BluetoothLowEnergy;
using Toybox.Position;
using Toybox.System as Sys;
using Toybox.Timer;
using BLEBarrel;

function buzz(ms) {
	if (Attention has :vibrate) {
		Attention.vibrate([new Attention.VibeProfile(60, ms)]);
	}
}

// Input events in the watch log (Apps/LOGS/INSTAREM.TXT): which path triggered START.
function inLog(msg) {
	Sys.println("[in] " + msg);
	BLEBarrel.logLine("[in] " + msg);
}

class RemoteDelegate extends Ui.BehaviorDelegate {
	hidden var dev;
	hidden var sendTimer;
	hidden var pendingSend = false;
	hidden var setTimer;
	hidden var tapTimer;
	hidden var startKeyAt = null;   // time of the last START key press (onKeyPressed), null = none pending
	hidden var tapPending = false;

	function initialize(device) {
		BehaviorDelegate.initialize();
		dev = device;
		sendTimer = new Timer.Timer();
		setTimer = new Timer.Timer();
		tapTimer = new Timer.Timer();
	}

	// Connect IQ turns a screen tap into the SELECT behaviour first and only calls onTap when
	// onSelect returns false. A START press always reaches onKeyPressed (KEY_ENTER) before
	// onSelect, a tap never does. So onSelect without a fresh START key press is a tap: hand it
	// to onTap (which knows where the finger was). If no onTap follows, the fallback timer runs
	// START anyway, so a press is never lost.
	function onSelect() {
		var key = startKeyAt != null && Sys.getTimer() - startKeyAt < 2000;
		inLog("select key=" + key);
		startKeyAt = null;
		if (!key) {
			tapPending = true;
			tapTimer.stop();
			tapTimer.start(method(:onTapTimeout), 150, false);
			return false;
		}
		return runStart();
	}

	function onTapTimeout() as Void {
		if (tapPending) { tapPending = false; inLog("fallback START (no tap followed)"); runStart(); }
	}

	// START button (or a tap outside the rows): one press = one action, no menus.
	function runStart() {
		var s = uiState(dev);
		inLog("START state=" + s + " mode=" + BLEBarrel.currentMode + " focus=" + Settings.focus);
		if (s == UI_SEARCHING) {
			return true;
		}
		if (s == UI_NOT_FOUND) {
			BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
			Ui.requestUpdate();
			return true;
		}
		if (s == UI_RECORDING) {
			BLEBarrel.recState = BLEBarrel.stateStopping;
			if (BLEBarrel.isX5() && !BLEBarrel.videoMode && dev.isTimedPhotoX5()) {
				dev.lapseX5(false);
			} else {
				dev.sendCMD(BLEBarrel.cmdStopRec);
			}
			buzz(80);
			Ui.requestUpdate();
			return true;
		}
		if (s == UI_STARTING || s == UI_STOPPING || s == UI_BUSY) {
			// Camera never confirmed: drop back to ready so the next press retries.
			BLEBarrel.recState = BLEBarrel.stateStopRec;
			mMessage = "";
			Ui.requestUpdate();
			return true;
		}
		// Settings page: START runs the focused action (Exit), never the shutter
		if (BLEBarrel.inSettings()) {
			var rows = Settings.rows(BLEBarrel.currentMode);
			if (Settings.focus > 0 && Settings.focus <= rows.size()) {
				var k = rows[Settings.focus - 1][3];
				if (k == :exit) { Sys.exit(); }
				if (k == :power) { confirmPowerOff(dev); }
			}
			return true;
		}
		// READY: start recording / take the shot
		sendTimer.stop();
		flushMode();
		BLEBarrel.recState = BLEBarrel.stateStarting;
		if (BLEBarrel.isX5() && !BLEBarrel.videoMode && dev.isTimedPhotoX5()) {
			dev.lapseX5(true);
		} else if (BLEBarrel.isX5() && BLEBarrel.videoMode) {
			dev.sendCMD(BLEBarrel.cmdStartRec);
		} else if (BLEBarrel.videoMode) {
			if (!BLEBarrel.currentMode.equals("DefaultV")) {
				dev.sendCMD(BLEBarrel.currentMode);
				dev.sendCMD(BLEBarrel.cmdApply);
			}
			dev.sendCMD(BLEBarrel.cmdStartRec);
		} else if (BLEBarrel.isX5()) {
			dev.shutterX5();
		} else {
			dev.sendCMD(BLEBarrel.cmdApply);
			dev.sendCMD(BLEBarrel.currentMode);
		}
		buzz(150);
		Ui.requestUpdate();
		return true;
	}

	// Touch: tap / hold a settings row to focus it; tap elsewhere = START. Swipes arrive as
	// onPreviousPage / onNextPage, so swiping up / down changes the focused value.
	function onTap(evt) {
		tapPending = false;
		tapTimer.stop();
		if (focusRowAt(evt)) { return true; }
		return runStart();
	}

	function onHold(evt) {
		return focusRowAt(evt);
	}

	hidden function focusRowAt(evt) {
		if (uiState(dev) != UI_READY || Settings.hitYs == null) { return false; }
		var xy = evt.getCoordinates();
		var i = Settings.rowAt(xy[0], xy[1]);
		inLog("tap " + xy[0] + "," + xy[1] + " -> entry " + i);
		if (i < 0) { return false; }
		// a second tap on a focused action row (Power off / Exit) runs it, like START
		if (i == Settings.focus && i > 0 && BLEBarrel.inSettings()) {
			var k = Settings.rows(BLEBarrel.currentMode)[i - 1][3];
			if (k == :exit || k == :power) { return runStart(); }
		}
		Settings.focus = i;
		buzz(20);
		Ui.requestUpdate();
		return true;
	}

	// BACK: move the focus Mode -> setting rows -> Mode; in a mode without settings it exits.
	// Long-press BACK belongs to the OS: "Exit app" is in the hold-UP menu.
	function onKeyPressed(evt) {
		// Probe: log every key the system passes to the app (does LIGHT ever arrive?)
		var kmsg = "[key] pressed " + evt.getKey() + (evt.getKey() == Ui.KEY_LIGHT ? " (LIGHT)" : "");
		Sys.println(kmsg);
		BLEBarrel.logLine(kmsg);
		if (evt.getKey() == Ui.KEY_ENTER) { startKeyAt = Sys.getTimer(); }
		return false;
	}

	function onBack() {
		var n = Settings.rows(BLEBarrel.currentMode).size();
		if (uiState(dev) != UI_READY || n == 0) { return false; }
		Settings.focus = (Settings.focus + 1) % (n + 1);
		buzz(20);
		Ui.requestUpdate();
		return true;
	}

	// UP / DOWN in ready state: change the focused row (the mode, or a setting).
	hidden function stepFocused(dir) {
		if (Settings.focus == 0) { stepMode(dir); return; }
		var rows = Settings.rows(BLEBarrel.currentMode);
		if (Settings.focus > rows.size()) { Settings.focus = 0; stepMode(dir); return; }
		var row = rows[Settings.focus - 1];
		if (row[3] == :exit || row[3] == :power) { return; }
		pendingSetFrame = Settings.step(BLEBarrel.currentMode, row, dir);
		pendingSetKey = Settings.key(BLEBarrel.currentMode, row);
		setTimer.stop();
		setTimer.start(method(:flushSetting), 800, false);
		Ui.requestUpdate();
	}

	hidden var pendingSetFrame = null;
	hidden var pendingSetKey = null;

	function flushSetting() as Void {
		if (pendingSetFrame == null) { return; }
		if (demoState == null && !BLEBarrel.settingMayGo()) {
			// the camera is still switching modes: try again shortly
			setTimer.start(method(:flushSetting), 300, false);
			return;
		}
		if (demoState != null) {
			Settings.acked[pendingSetKey] = true;   // simulator demo: pretend the camera acked
		} else {
			dev.sendSettingX5(pendingSetFrame, pendingSetKey);
		}
		pendingSetFrame = null;
		Ui.requestUpdate();
	}

	// UP: highlight while recording, otherwise previous mode (-)
	function onPreviousPage() {
		var s = uiState(dev);
		if (s == UI_RECORDING) {
			dev.sendCMD(BLEBarrel.cmdHighlight);
			buzz(40);
			toast("Highlight added");
			return true;
		}
		if (s == UI_READY) { stepFocused(-1); return true; }
		return false;
	}

	// DOWN: Track That while recording, otherwise next mode (+)
	function onNextPage() {
		var s = uiState(dev);
		if (s == UI_RECORDING) {
			dev.sendCMD(BLEBarrel.cmdTrackThat);
			buzz(40);
			toast("Track That");
			return true;
		}
		if (s == UI_READY) { stepFocused(1); return true; }
		return false;
	}

	// Change the shown mode at once; tell the camera only once the user settles.
	hidden function stepMode(dir) {
		var items = modeList();
		var idx = 0;
		for (var i = 0; i < items.size(); i++) {
			if (items[i][0].equals(BLEBarrel.currentLabel)) { idx = i; break; }
		}
		idx = (idx + dir + items.size()) % items.size();
		applyMode(dev, items[idx][1], items[idx][0], false);
		if (demoState != null) { Ui.requestUpdate(); return; }
		BLEBarrel.holdMode(800 + 3000);   // browsing: don't let late camera echoes move the cursor
		pendingSend = true;
		sendTimer.stop();
		sendTimer.start(method(:flushMode), 800, false);
		Ui.requestUpdate();
	}

	function flushMode() as Void {
		if (pendingSend) {
			pendingSend = false;
			sendCurrentMode(dev);
		}
	}

	function onMenu() {
		if (uiState(dev) == UI_RECORDING) {
			return true; // don't change mode mid-recording
		}
		var items = modeList();
		var menu = new Ui.Menu2({:title => "Mode"});
		var focus = 0;
		for (var i = 0; i < items.size(); i++) {
			var cur = items[i][0].equals(BLEBarrel.currentLabel);
			if (cur) { focus = i; }
			menu.addItem(new Ui.MenuItem(items[i][0], cur ? "current" : null, items[i][1], {}));
		}
		// GPS overlay only feeds the legacy cameras' photo command; the X5 path never uses it
		if (!BLEBarrel.isX5()) {
			menu.addItem(new Ui.MenuItem("GPS overlay", BLEBarrel.GPSon ? "on" : "off", "GPSon", {}));
		}
		menu.addItem(new Ui.MenuItem("Exit app", null, "exit", {}));
		menu.setFocus(focus);
		Ui.pushView(menu, new ModeDelegate(dev), Ui.SLIDE_UP);
		return true;
	}
}

// X5: modes are SET_OPTIONS sub-modes, ids "v<n>" (VIDEO_SUB_MODE, option 41) / "p<n>" (PHOTO_SUB_MODE, option 40).
// Values captured from the Insta360 app over WiFi; names from the community insta360_messages.proto.
function modeListX5() {
	return [
		["Video", "v0"], ["PureVideo", "v11"], ["Gimbal", "v15"], ["Star Video", "v12"], ["Timelapse", "v2"],
		["TimeShift", "v4"], ["Bullet Time", "v1"], ["Loop Rec", "v6"], ["Road Mode", "v14"],
		["Photo", "p0"], ["Photo Interval", "p2"], ["Photo Burst", "p3"], ["Starlapse", "p7"],
		["Settings", "set"]   // watch-side page, not a camera mode
	];
}

function modeList() {
	if (BLEBarrel.isX5()) { return modeListX5(); }
	var items = [];
	if (BLEBarrel.menuLevel >= 2) { items.add(["8K / 30", "8k30"]); }
	if (BLEBarrel.menuLevel >= 1) {
		items.addAll([
			["5.7K / 30", "5k30"], ["5.7K / 25", "5k25"], ["5.7K / 24", "5k24"],
			["4K / 50", "4k50"], ["4K / 30", "4k30"], ["HDR Video", "HDR"],
			["Timelapse", "TimeLapse"], ["Bullet Time", "BulletTime"],
			["Photo", "Photo"], ["Photo HDR", "PhotoHDR"], ["Photo Burst", "PhotoBurst"],
			["Photo Interval", "PhotoInterval"], ["Night Shot", "NightShot"]
		]);
	}
	items.add(["Default Video", "DefaultV"]);
	return items;
}

function sendCurrentMode(dev) {
	// Photo "modes" are the shutter command itself: never send them while browsing.
	// The X5 ignores the legacy mode commands (its own are not mapped yet).
	if (BLEBarrel.isX5()) {
		var id = BLEBarrel.currentMode;
		if (BLEBarrel.inSettings()) { return; }
		if (id instanceof Toybox.Lang.String && id.length() >= 2) {
			BLEBarrel.modeReq = id;
			BLEBarrel.holdMode(3000);
			dev.sendCMD(BLEBarrel.setSubModeX5(id.substring(0, 1).equals("v"), id.substring(1, id.length()).toNumber()));
		}
		return;
	}
	if (!BLEBarrel.videoMode) { return; }
	if (!(BLEBarrel.currentMode instanceof Toybox.Lang.String)) {
		dev.sendCMD(BLEBarrel.currentMode);
		dev.sendCMD(BLEBarrel.cmdApply);
	}
}

// Select a mode: set label, mode command and patched start/stop commands; optionally send now.
function applyMode(dev, id, label, send) {
	// Reset start/stop commands; some modes patch them below.
	BLEBarrel.cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;
	BLEBarrel.cmdStopRec =  [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	if (id.equals("set")) {
		// Settings page: the camera keeps its mode (remembered for the return)
		if (!BLEBarrel.inSettings()) { BLEBarrel.camMode = BLEBarrel.currentMode; }
		BLEBarrel.currentMode = id;
		BLEBarrel.currentLabel = label;
		return;
	}
	BLEBarrel.videoMode = true;

	if (id.length() >= 2 && (id.substring(0, 1).equals("v") || id.substring(0, 1).equals("p")) && BLEBarrel.isX5()) {
		BLEBarrel.videoMode = id.substring(0, 1).equals("v");
		BLEBarrel.currentMode = id;
		BLEBarrel.currentLabel = label;
		if (send) { sendCurrentMode(dev); }
		return;
	}

	switch (id) {
		case "8k30": BLEBarrel.currentMode = BLEBarrel.cmdSet8k30; break;
		case "5k30": BLEBarrel.currentMode = BLEBarrel.cmdSet5k30; break;
		case "5k25": BLEBarrel.currentMode = BLEBarrel.cmdSet5k25; break;
		case "5k24": BLEBarrel.currentMode = BLEBarrel.cmdSet5k24; break;
		case "4k30": BLEBarrel.currentMode = BLEBarrel.cmdSet4k30; break;
		case "4k50": BLEBarrel.currentMode = BLEBarrel.cmdSet4k50; break;
		case "HDR":
			BLEBarrel.cmdStartRec[17] = 0x03; BLEBarrel.cmdStartRec[7] = 0x04;
			BLEBarrel.cmdStopRec[17] = 0x03;  BLEBarrel.cmdStopRec[7] = 0x05;
			BLEBarrel.currentMode = BLEBarrel.cmdSetHDR;
			break;
		case "TimeLapse":
			BLEBarrel.cmdStartRec[7] = 0x16;
			BLEBarrel.cmdStopRec[16] = 0x08; BLEBarrel.cmdStopRec[7] = 0x17;
			BLEBarrel.currentMode = BLEBarrel.cmdSetTL;
			break;
		case "BulletTime":
			BLEBarrel.cmdStartRec[17] = 0x02; BLEBarrel.cmdStopRec[17] = 0x02;
			BLEBarrel.currentMode = BLEBarrel.cmdSetBullet;
			break;
		case "Photo":
			if (BLEBarrel.GPSon) { BLEBarrel.cmdSetPhoto = photoWithGps(dev); }
			BLEBarrel.currentMode = BLEBarrel.cmdSetPhoto;
			BLEBarrel.videoMode = false;
			break;
		case "PhotoHDR":   BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoHDR;   BLEBarrel.videoMode = false; break;
		case "PhotoBurst": BLEBarrel.currentMode = BLEBarrel.cmdSetPhotoBurst; BLEBarrel.videoMode = false; break;
		case "PhotoInterval":
			BLEBarrel.currentMode = BLEBarrel.cmdSetInterval;
			BLEBarrel.cmdStartRec[17] = 0x02; BLEBarrel.cmdStartRec[7] = 0x16;
			BLEBarrel.cmdStopRec[17] = 0x02;  BLEBarrel.cmdStopRec[16] = 0x08; BLEBarrel.cmdStopRec[7] = 0x17;
			break;
		case "NightShot":  BLEBarrel.currentMode = BLEBarrel.cmdSetNightShot;  BLEBarrel.videoMode = false; break;
		default:           BLEBarrel.currentMode = "DefaultV";
	}
	BLEBarrel.currentLabel = label;
	if (send) { sendCurrentMode(dev); }
}

function photoWithGps(dev) {
	var info = Position.getInfo();
	var header = [0x3f, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x02, 0xe3, 0x00, 0x00, 0x80, 0x00, 0x00, 0x12, 0x2d, 0x5a, 0x18]b;
	var filler = [0x6a, 0x02, 0x30, 0x01, 0x9a, 0x01, 0x00, 0xaa, 0x01, 0x00, 0xba, 0x01, 0x00, 0xd2, 0x01, 0x00, 0xe2, 0x02, 0x00]b;
	if (info == null || info.position == null) {
		return BLEBarrel.cmdSetPhoto;
	}
	var loc = info.position.toDegrees();
	header.addAll(dev.toDouble(loc[0]));
	header.addAll(dev.toDouble(loc[1]));
	header.addAll(dev.toDouble(info.altitude != null ? info.altitude : 0.0));
	header.addAll(filler);
	return header;
}

class ModeDelegate extends Ui.Menu2InputDelegate {
	hidden var dev;

	function initialize(device) {
		Menu2InputDelegate.initialize();
		dev = device;
	}

	function onSelect(item) {
		var id = item.getId();
		if (id.equals("exit")) { Sys.exit(); }
		if (id.equals("GPSon")) {
			BLEBarrel.GPSon = !BLEBarrel.GPSon;
			Application.getApp().gpsSync();
			item.setSubLabel(BLEBarrel.GPSon ? "on" : "off");
			return;
		}
		applyMode(dev, id, item.getLabel(), true);
		Ui.popView(Ui.SLIDE_DOWN);
		Ui.requestUpdate();
	}
}

// "Power off camera?" -> SET_SHUTDOWN. The camera then drops the link; the app keeps scanning.
// A menu, not Ui.Confirmation: on the Mk3i the native confirmation has no visible focus and a
// second START press confirms it. Here "No" is the first, focused item, so START twice = No.
function confirmPowerOff(dev) {
	var menu = new Ui.Menu2({:title => "Power off camera?"});
	menu.addItem(new Ui.MenuItem("No", "keep it on", :no, {}));
	menu.addItem(new Ui.MenuItem("Yes, power off", null, :yes, {}));
	menu.setFocus(0);
	Ui.pushView(menu, new PowerOffDelegate(dev), Ui.SLIDE_UP);
}

class PowerOffDelegate extends Ui.Menu2InputDelegate {
	hidden var dev;
	function initialize(device) { Menu2InputDelegate.initialize(); dev = device; }
	function onSelect(item) {
		Ui.popView(Ui.SLIDE_DOWN);
		if (item.getId() == :yes) {
			if (demoState == null) { dev.sendCMD(BLEBarrel.shutdownX5()); }
			buzz(150);
			toast("Camera powering off");
		}
	}
}
