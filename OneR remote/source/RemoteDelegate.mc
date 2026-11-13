using Toybox.WatchUi as Ui;
using Toybox.Application;
using Toybox.Attention;
using Toybox.BluetoothLowEnergy;
using Toybox.Position;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Lang;
using BLEBarrel;

// The delegate of the ported RemoteView (phase 4 of the PR #2 integration). It is the
// PR's RemoteDelegate, re-welded to this app's verified machinery: the rows answer to
// Levels, the frame of an entry to entryFrame(), the write to sendCMD with the apply
// ask of the mainline flow, and the shot's answer to armPhotoAck. The PR's own
// mode-list, mode-command switch, lapseX5 half and settingMayGo gate are replaced here
// by their mainline equivalents; what stays from the PR is the interaction model -
// BACK moves the focus, UP/DOWN step the focused row, one press is one action.

function buzz(ms) {
	if (Attention has :vibrate) {
		Attention.vibrate([new Attention.VibeProfile(60, ms)]);
	}
}

// Input events in the watch log, the PR's [in] tell. The Sys.println of the app lands
// in the same file the barrel's log lines reach; no second sink.
function inLog(msg) {
	Sys.println("[in] " + msg);
}

// The Settings page is an app-side id, never a camera mode. The mainline barrel has no
// inSettings() - the PR's barrel did - so the question is asked where the id lives.
function inSettingsUI() {
	var m = BLEBarrel.currentMode;
	return m instanceof Lang.String && m.equals("set");
}

// The mode remembered when the Settings page was opened, so returning from it lands on
// the mode the camera was left in. The PR kept this in its barrel (camMode); here it
// cannot share the name - BLEBarrel.camModeId is the camera's own reported mode, a
// different datum, read nowhere in this file.
var setReturnMode = null;
var setReturnLabel = null;

// The three debounces of this delegate (the tap fallback, the mode-write
// debounce, the settings-write debounce) own no Timer object: an app's Timer
// pool is small (the API documents three by default, host-dependent) and this
// widget shares it with the barrel's one-shot asks and the view's one
// repeating timer - the PR's watch-app budget of four delegate-side timers
// was already over the wall before RemoteView.onShow started its timer, which
// is the "Too Many Timers" crash a widget run takes (the glance session and
// the opened app are one process, one pool). So the delegate books due dates
// in the System.getTimer() domain, and the view's 125 ms tick pumps them
// (RemoteView.onTick -> uiPump.pumpDue). The delegate registers itself here
// at construction; a hidden view simply stops pumping, and a due action
// runs at the next show - never lost while the app lives.
var uiPump = null;

// The id of the mode the watch is showing, kept beside currentMode (which is a frame in
// this app, not an id). The echo gate is armed with the id, never the frame.
var currentModeId = "DefaultV";

// The mode wheel and the Mode menu answer the chain, not a hand-written list: the rows
// of the level in force, [label, id] pairs in the order of the table, plus the
// Settings entry on the levels that have option rows. The ucd2 sentinel row of the
// replacing level stays where the table put it (its selection arms the envelope).
function modeList() {
	var out = [];
	var rows = Levels.rowsMain(BLEBarrel.menuLevel);
	var i = 0;
	while (i < rows.size()) {
		out.add([rows[i][Levels.RLB], rows[i][Levels.RID]]);
		i += 1;
	}
	if (BLEBarrel.menuLevel >= 2) {
		out.add(["Settings", "set"]);
	}
	return out;
}

// Settings writes cross only once the camera is settled: the barrel's one rule
// (its device method names it) - the echo of a mode write, or that hold's end;
// the camera answers 400 while it is still switching. This copy once asked the
// echo alone, and the wrist reproduction of 13 nov. named what that costs: a
// mode rewrite aimed at a mode the camera already holds gets an ack but no
// echo, so the echo-only gate stays shut for the whole session and the user's
// settings write never crosses (runs 5/6, the 18MP->72MP that never arrived).
// Same two datums, same rule as the barrel, no stricter copy.
function settingMayGo() {
	if (BLEBarrel.modeReqId == null) { return true; }
	return Sys.getTimer() >= BLEBarrel.modeHoldUntil;
}

class RemoteDelegate extends Ui.BehaviorDelegate {
	hidden var dev;
	hidden var dueSend = null;   // due dates, System.getTimer() domain - see pumpDue, no Timer objects
	hidden var pendingSend = false;
	hidden var dueSet = null;
	hidden var dueTap = null;
	hidden var startKeyAt = null;   // time of the last START key press (onKeyPressed), null = none pending
	hidden var tapPending = false;
	hidden var pendingSetFrames = null;
	hidden var pendingSetKey = null;
	hidden var settingHeld = false;   // this write's hold has been printed once (trace hygiene)
	// One datum of the pose below: the row this session already posed and could
	// not apply (a doc row, no frame) or has no frame to write (the sentinel of
	// a replacing level). Asked a second time it answers the same absence, and
	// the pump would print that refusal every 125 ms.
	hidden var poseHeld = null;

	function initialize(device) {
		BehaviorDelegate.initialize();
		dev = device;
		// No Timer.Timer() here, deliberately: see the uiPump note above.
		uiPump = self;
	}

	// Connect IQ turns a screen tap into the SELECT behaviour first and only calls onTap when
	// onSelect returns false. A START press always reaches onKeyPressed (KEY_ENTER) before
	// onSelect, a tap never does. So onSelect without a fresh START key press is a tap: hand it
	// to onTap (which knows where the finger was). If no onTap follows, the fallback
	// deadline runs START on the next pump, so a press is never lost.
	function onSelect() {
		var key = startKeyAt != null && Sys.getTimer() - startKeyAt < 2000;
		inLog("select key=" + key);
		startKeyAt = null;
		if (!key) {
			tapPending = true;
			dueTap = Sys.getTimer() + 150;
			return false;
		}
		return runStart();
	}

	function onTapTimeout() as Void {
		if (tapPending) { tapPending = false; inLog("fallback START (no tap followed)"); runStart(); }
	}

	// START (or a tap outside the rows): one press, one action, no menus. The rungs are
	// this app's verified capture flow, not the PR's: the mode frame was written at the
	// selection (flushMode), so the press only ever sends the start, the stop, or the
	// capture pair (cmdApply then the capture frame), and the capture pair arms its
	// answer (armPhotoAck). The PR's timed-photo half (lapseX5, the PR's own START /
	// STOP_TIMELAPSE pair) is not taken: this app runs interval and starlapse on the
	// 0x03 / 0x04 pair the bench verified, so a recording ends with cmdStopRec like any
	// other recording.
	function runStart() {
		var s = uiState(dev);
		inLog("START state=" + s + " mode=" + currentModeId + " focus=" + Settings.focus);
		if (s == UI_SEARCHING) {
			// A press during an open scan reaches nothing: the transport answers it
			// at its scanning guard (barrel transmit). Truth of the comment as the
			// bench of 12 nov. proved it - the barrel does NOT rescan on its own
			// after an exhausted round; that state is NOT_FOUND below, and its
			// press is the retry.
			return true;
		}
		if (s == UI_NOT_FOUND) {
			// "Retry now" is true here: the frame is sent, the transport finds no
			// device and restarts the scan (barrel transmit, the device-null leg).
			// The empty frame reaches no bond - transmit returns at that leg.
			dev.sendCMD(new [0]b);
			return true;
		}
		if (s == UI_RECORDING) {
			BLEBarrel.recState = BLEBarrel.stateStopping;
			dev.sendCMD(BLEBarrel.cmdStopRec);
			buzz(80);
			Ui.requestUpdate();
			return true;
		}
		if (s == UI_STARTING || s == UI_STOPPING || s == UI_BUSY) {
			// Camera never confirmed: drop back to ready so the next press retries.
			BLEBarrel.recState = BLEBarrel.stateStopRec;
			BLEBarrel.mMessage = BLEBarrel.currentLabel + "\n" + BLEBarrel.startMessage;
			Ui.requestUpdate();
			return true;
		}
		// Settings page: START runs the focused action (Exit, Power off), never the shutter
		if (inSettingsUI()) {
			var rows = Settings.rows("set");
			if (Settings.focus > 0 && Settings.focus <= rows.size()) {
				var k = rows[Settings.focus - 1][3];
				if (k == :exit) { Sys.exit(); }
				if (k == :power) { confirmPowerOff(dev); }
			}
			return true;
		}
		// READY: start recording / take the shot
		dueSend = null;   // a pending mode write is flushed now, not later
		flushMode();
		BLEBarrel.recState = BLEBarrel.stateStarting;
		if (BLEBarrel.photoCaptureMode) {
			var captureFrame = BLEBarrel.cmdSetPhoto;
			if (BLEBarrel.photoBurstMode) {
				captureFrame = BLEBarrel.cmdSetPhotoBurst;
			}
			Sys.println("[cap] " + currentModeId + " burst=" + BLEBarrel.photoBurstMode.toString());
			dev.sendCMD(BLEBarrel.cmdApply);
			dev.sendCMD(captureFrame);
			dev.armPhotoAck();
		} else {
			Sys.println("[start] " + currentModeId);
			dev.sendCMD(BLEBarrel.cmdStartRec);
		}
		buzz(150);
		Ui.requestUpdate();
		return true;
	}

	// Touch: tap / hold a settings row to focus it; tap elsewhere = START. Swipes arrive as
	// onPreviousPage / onNextPage, so swiping up / down changes the focused value.
	function onTap(evt) {
		tapPending = false;
		dueTap = null;   // the tap answered itself: no fallback
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
		if (i == Settings.focus && i > 0 && inSettingsUI()) {
			var k = Settings.rows("set")[i - 1][3];
			if (k == :exit || k == :power) { return runStart(); }
		}
		Settings.focus = i;
		buzz(20);
		Ui.requestUpdate();
		return true;
	}

	// START key timestamp for the tap discrimination (see onSelect).
	function onKeyPressed(evt) {
		if (evt.getKey() == Ui.KEY_ENTER) { startKeyAt = Sys.getTimer(); }
		return false;
	}

	// BACK: move the focus Mode -> setting rows -> Mode; in a mode without settings it exits.
	// Long-press BACK belongs to the OS: "Exit app" is in the hold-UP menu.
	function onBack() {
		var n = Settings.rows(currentModeId).size();
		if (uiState(dev) != UI_READY || n == 0) { return false; }
		Settings.focus = (Settings.focus + 1) % (n + 1);
		buzz(20);
		Ui.requestUpdate();
		return true;
	}

	// UP / DOWN in ready state: change the focused row (the mode, or a setting).
	hidden function stepFocused(dir) {
		if (Settings.focus == 0) { stepMode(dir); return; }
		var rows = Settings.rows(currentModeId);
		if (Settings.focus > rows.size()) { Settings.focus = 0; stepMode(dir); return; }
		var row = rows[Settings.focus - 1];
		if (row[3] == :exit || row[3] == :power) { return; }
		pendingSetFrames = Settings.step(currentModeId, row, dir);
		pendingSetKey = Settings.key(currentModeId, row);
		settingHeld = false;   // this write's deferral, when it comes, is named once
		dueSet = Sys.getTimer() + 800;
		Ui.requestUpdate();
	}

	function flushSetting() as Void {
		if (pendingSetFrames == null) { return; }
		if (!settingMayGo()) {
			// the camera is still switching modes: the pump re-enters this
			// function 300 ms later (a due date, never a Timer object). The
			// wait was once silent - the 13 nov. reproduction searched a whole
			// session for a write that never crossed; one line, once per armed
			// write, names the wait from now on.
			if (!settingHeld) {
				settingHeld = true;
				Sys.println("[set] " + pendingSetKey + " held, a mode write is still in its window");
			}
			dueSet = Sys.getTimer() + 300;
			return;
		}
		var frames = pendingSetFrames;
		pendingSetFrames = null;
		var i = 0;
		while (i < frames.size()) {
			dev.sendCMD(frames[i]);
			i += 1;
		}
		// the last frame's answer decides the row's ok / refused mark (the PR's
		// sendSettingX5 discipline, on this app's armWriteAck witness)
		dev.armWriteAck(pendingSetKey);
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
		var i = 0;
		while (i < items.size()) {
			if (items[i][0].equals(BLEBarrel.currentLabel)) { idx = i; break; }
			i += 1;
		}
		idx = (idx + dir + items.size()) % items.size();
		applyMode(dev, items[idx][1], items[idx][0], false);
		BLEBarrel.modeHoldUntil = Sys.getTimer() + 3800;   // browsing: don't let late camera echoes move the cursor
		pendingSend = true;
		dueSend = Sys.getTimer() + 800;
		Ui.requestUpdate();
	}

	function flushMode() as Void {
		if (pendingSend) {
			pendingSend = false;
			sendCurrentMode(dev);
		}
	}

	// The one pump of the three debounces, entered from the view's single
	// repeating timer (RemoteView.onTick calls this through uiPump). Writes
	// first, so a START fallback that becomes due in the same window acts on
	// a settled state - the same order the PR's three one-shot timers reached
	// their callbacks, without owning three Timer objects.
	function pumpDue() as Void {
		// The pose first: it is a due of the same kind as the three below (the
		// screen's own pair of data became incoherent), and it owns no frame of
		// its own - it arms the mode write through pendingSend/dueSend below.
		poseMode();
		var now = Sys.getTimer();
		if (dueSend != null && now >= dueSend) {
			dueSend = null;
			flushMode();
		}
		if (dueSet != null && now >= dueSet) {
			dueSet = null;
			flushSetting();
		}
		if (dueTap != null && now >= dueTap) {
			dueTap = null;
			onTapTimeout();
		}
	}

	// The pose of the mode when the screen's two data no longer name one row of
	// the level in force. The rule and its order live in one place,
	// Levels.poseFor: the mode this camera last CONFIRMED holding (the barrel
	// kept it under the name at that echo), else the first row of the level -
	// the normal video of that line. This is the screen's truth, not a guess
	// about the camera: the X5 never names its mode at a connect (the 0x2017
	// push is the periodic ack, a 0x2053 echo only follows OUR write,
	// GET_OPTIONS is cut at octet 20 - the bench of 12 nov. re-reads all three),
	// so no read could fill this screen. Two observations named this rule: the
	// title "Default Video" (open()'s own pose) over the eleven dots of the
	// measured ladder with an empty row list, and that same title over the
	// TIMER/SIZE/EV/LENS rows of the photo row after the camera was
	// power-cycled - the title is the barrel's datum, the rows are this class's,
	// and only a pose applied to both puts them back on one row.
	//
	// The write below is what makes the claim an action: the same pair the
	// wheel's selection sends (the frame, then the apply), armed at the
	// barrel's echo gate by sendCurrentMode. It is booked 3 s after the bond,
	// past the three connect asks (auth 500 ms, cam state 1500 ms, card
	// 2500 ms), so the pose never slips between them. A row this barrel has
	// no frame for is refused by applyMode and changes nothing - the mode the
	// camera holds stays, as the chain's rule says.
	hidden function poseMode() as Void {
		var level = BLEBarrel.menuLevel;
		// A mode belongs to a camera: no bond, no pose. The absence screen
		// (UI_NOT_FOUND) is what the screen shows there, and the pose stays
		// due for the bond that answers it.
		if (dev == null || !dev.hasLink()) { return; }
		// The Settings and resolution legs own the current id while they are on
		// screen; the pose would fight them and it is never due on those pages.
		if (inSettingsUI()) { return; }
		var pose = Levels.poseFor(level, dev.peekKeptModeId(), currentModeId, BLEBarrel.currentLabel);
		if (pose == null) { return; }
		var id = pose[Levels.RID] as Lang.String;
		var label = pose[Levels.RLB] as Lang.String;
		if (poseHeld != null && poseHeld.equals(id)) { return; }
		Sys.println("[pose] level=" + level.toString() + " title=" + BLEBarrel.currentLabel + " rows=" + currentModeId + " do not name one row, taking " + id);
		applyMode(dev, id, label, false);
		if (pose[Levels.RFAM].equals("x")) {
			// The sentinel row of a replacing level arms the envelope and has no
			// frame to write (the row's family says so) - the pose is over.
			poseHeld = id;
			return;
		}
		if (!currentModeId.equals(id) || !BLEBarrel.currentLabel.equals(label)) {
			// applyMode refused (no frame for that row): the mode the camera
			// holds stays, and so does the name the screen carries for it.
			poseHeld = id;
			Sys.println("[pose] " + id + " refused, the mode stays " + BLEBarrel.currentLabel);
			return;
		}
		BLEBarrel.modeHoldUntil = Sys.getTimer() + 3800;
		pendingSend = true;
		dueSend = Sys.getTimer() + 3000;
	}

	function onMenu() {
		if (uiState(dev) == UI_RECORDING) {
			return true; // don't change mode mid-recording
		}
		var items = modeList();
		var menu = new Ui.Menu2({:title => "Mode"});
		var focus = 0;
		var i = 0;
		while (i < items.size()) {
			var cur = items[i][0].equals(BLEBarrel.currentLabel);
			if (cur) { focus = i; }
			menu.addItem(new Ui.MenuItem(items[i][0], cur ? "current" : null, items[i][1], {}));
			i += 1;
		}
		// The row of the position intent is a permanent option, independent of
		// the level in force (the user's ruling, 13 nov.): it stands in the menu
		// wherever the menu stands. Selecting it keeps the flag and calls
		// Main.gpsSync, which names the flip at [gps]. The subtitle states the
		// user's intent, the same reading the mainline's row gives; the fact of
		// the radio belongs to the [gps] line, never here.
		menu.addItem(new Ui.MenuItem("GPS overlay", BLEBarrel.GPSon ? "on" : "off", "GPSon", {}));
		// the bench axis of the level chain: forcing a model, the same choices as the
		// mainline menu, so the Phase 5 runs keep their forcing entry in the new UI too
		menu.addItem(new Ui.MenuItem("Force model", null, "forceopen", {}));
		menu.addItem(new Ui.MenuItem("Exit app", null, "exit", {}));
		menu.setFocus(focus);
		Ui.pushView(menu, new ModeDelegate(dev), Ui.SLIDE_UP);
		return true;
	}
}

// Select a mode: this app's own selection flow - the row of the chain answers the
// family and the key (one datum, no second list), entryFrame() answers the frame, and
// a row the chain never measured over BLE is refused here and writes nothing. The
// start/stop patches of the reference-app rungs (HDR video, Timelapse, Interval) are
// the mainline's, kept for the levels whose entries ride those rungs.
function applyMode(dev, id, label, send) {
	// Reset start/stop commands; some rungs patch them below (the PR's reset, the same
	// arrays the mainline's selection flow reassigns at its own top).
	BLEBarrel.cmdStartRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x4, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x8, 0x1]b;
	BLEBarrel.cmdStopRec = [0x12, 0, 0, 0, 0x4, 0, 0, 0x5, 0, 0x2, 0xff, 0, 0, 0x80, 0, 0, 0x10, 0x1]b;
	BLEBarrel.recState = BLEBarrel.stateStopRec;

	if (id.equals("set")) {
		// Settings page: the camera keeps its mode (remembered for the return)
		if (!inSettingsUI()) {
			setReturnMode = currentModeId;
			setReturnLabel = BLEBarrel.currentLabel;
		}
		currentModeId = "set";
		BLEBarrel.currentMode = "set";
		BLEBarrel.currentLabel = label;
		BLEBarrel.mMessage = label + "\n" + BLEBarrel.startMessage;
		return;
	}
	if (setReturnMode != null && !id.equals(setReturnMode)) { setReturnMode = null; setReturnLabel = null; }

	if (id.equals("X6Video")) {
		// Arm the UCD2 envelope (the mainline's case: currentMode stays at the "DefaultV"
		// sentinel, the apply block would else hand sendCMD a String).
		BLEBarrel.ucd2Armed = true;
		currentModeId = "DefaultV";
		BLEBarrel.currentMode = "DefaultV";
		BLEBarrel.currentLabel = "X6 Video";
		BLEBarrel.mMessage = BLEBarrel.currentLabel + "\n" + BLEBarrel.startMessage;
		return;
	}

	// GPS photo of the legacy lines (the mainline's measured path, case p0 and case
	// Photo): the fix is written into the photo header before the mode. That header
	// is a frame of the older envelope - at the X5 line the rows carry other ids,
	// and a header of another protocol is refused by the barrel's ceiling - so this
	// only ever runs where it was verified at the bench.
	if ((id.equals("p0") || id.equals("Photo")) && BLEBarrel.GPSon) {
		var ginfo = Position.getInfo();
		if (ginfo != null && ginfo.position != null) {
			var gloc = ginfo.position.toDegrees();
			if (gloc != null && gloc.size() >= 2) {
				BLEBarrel.cmdSetPhoto = dev.photoGpsHeader(gloc[0], gloc[1], ginfo.altitude);
			}
		}
	}

	var row = Levels.rowOfId(BLEBarrel.menuLevel, id);
	var fam = "v";
	var key = id;
	if (row != null) {
		fam = row[Levels.RFAM];
		key = row[Levels.RKEY];
	}
	var frame = entryFrame(id);
	if (frame == null) {
		// A doc row, or an id this barrel has no verified frame for: the entry is shown
		// and refused at its selection, and writes nothing (the chain's rule, kept from
		// the mainline's menu - the mode the camera holds stays).
		Sys.println("[refused] " + id + " writes nothing, the mode stays " + BLEBarrel.currentLabel);
		return;
	}

	var photoFam = fam.equals("p");
	BLEBarrel.videoMode = !photoFam;
	BLEBarrel.photoBurstMode = id.equals("p3") || key.equals("PhotoBurst");
	BLEBarrel.photoCaptureMode = photoFam;
	Sys.println("[vw] " + id + " photoFam=" + photoFam.toString() + " after=" + BLEBarrel.videoMode.toString());

	// The reference-app rungs of the levels below the X5 line: HDR video, Timelapse and
	// Interval ride patched start/stop commands (the mainline's switch, case for case).
	if (id.equals("HDR") || id.equals("HDRVideo")) {
		BLEBarrel.cmdStartRec[17] = 0x03; BLEBarrel.cmdStartRec[7] = 0x04;
		BLEBarrel.cmdStopRec[17] = 0x03; BLEBarrel.cmdStopRec[7] = 0x05;
	} else if (id.equals("TimeLapse")) {
		BLEBarrel.cmdStartRec[7] = 0x16;
		BLEBarrel.cmdStopRec[16] = 0x08; BLEBarrel.cmdStopRec[7] = 0x17;
	} else if (id.equals("BulletTime")) {
		BLEBarrel.cmdStartRec[17] = 0x02; BLEBarrel.cmdStopRec[17] = 0x02;
	} else if (id.equals("PhotoInterval")) {
		BLEBarrel.currentMode = frame;
		BLEBarrel.cmdStartRec[17] = 0x02; BLEBarrel.cmdStartRec[7] = 0x16;
		BLEBarrel.cmdStopRec[17] = 0x02; BLEBarrel.cmdStopRec[16] = 0x08; BLEBarrel.cmdStopRec[7] = 0x17;
		BLEBarrel.currentLabel = label;
		currentModeId = id;
		BLEBarrel.mMessage = label + "\n" + BLEBarrel.startMessage;
		if (send) { sendCurrentMode(dev); }
		return;
	}

	currentModeId = id;
	BLEBarrel.currentMode = frame;
	BLEBarrel.currentLabel = label;
	BLEBarrel.mMessage = label + "\n" + BLEBarrel.startMessage;
	Sys.println("[mode] " + id + " -> " + label + " frame=" + frame.size().toString() + " o");
	if (send) { sendCurrentMode(dev); }
}

// Write the mode the watch settled on: the mainline's verified apply pair (the frame,
// then the state ask), armed at the barrel's echo gate with the id - the gate the
// mainline built in phase 3, fed here as the PR fed its own modeReq.
function sendCurrentMode(dev) {
	if (inSettingsUI()) { return; }
	if (currentModeId.equals("DefaultV")) { return; }
	var m = BLEBarrel.currentMode;
	if (!(m instanceof Lang.ByteArray)) { return; }
	BLEBarrel.modeReqId = currentModeId;
	BLEBarrel.modeHoldUntil = Sys.getTimer() + 3000;
	Sys.println("[apply] " + currentModeId + " frame=" + m.size().toString());
	dev.sendCMD(m);
	dev.sendCMD(BLEBarrel.cmdApply);
}

class ModeDelegate extends Ui.Menu2InputDelegate {
	hidden var dev;

	function initialize(device) {
		Menu2InputDelegate.initialize();
		dev = device;
	}

	function onSelect(item) {
		var id = item.getId() as Lang.String;
		if (id.equals("exit")) { Sys.exit(); }
		if (id.equals("forceopen")) {
			var menu = new Ui.Menu2({:title => "Force model"});
			addMenuLevelItems(menu);
			Ui.pushView(menu, new ForceModelDelegate(), Ui.SLIDE_IMMEDIATE);
			return;
		}
		if (id.equals("GPSon")) {
			BLEBarrel.GPSon = !BLEBarrel.GPSon;
			mainApp.gpsSync();
			item.setSubLabel(BLEBarrel.GPSon ? "on" : "off");
			return;
		}
		applyMode(dev, id, item.getLabel(), true);
		Ui.popView(Ui.SLIDE_DOWN);
		Ui.requestUpdate();
	}
}

// The forcing choices of the level chain (the mainline's addMenuLevelItems list:
// force<model> / forceoff). Same datums the mainline's Menu2Delegate sets: the forcing
// lands at the selection of the choice, where the datum of the run changes.
class ForceModelDelegate extends Ui.Menu2InputDelegate {
	function initialize() {
		Menu2InputDelegate.initialize();
	}

	function onSelect(item) {
		var id = item.getId() as Lang.String;
		if (id.equals("forceoff")) {
			BLEBarrel.testModel = "";
			BLEBarrel.testLevel = -1;
			Sys.println("[force] off, the detected model answers again");
		} else {
			var name = id.substring(5, id.length());
			BLEBarrel.testModel = name;
			BLEBarrel.testLevel = Levels.levelOfName(name);
			Sys.println("[force] " + name + " level=" + BLEBarrel.testLevel.toString());
		}
		bleDevice.noteConfirmedLevel();
		Ui.popView(Ui.SLIDE_IMMEDIATE);
		Ui.popView(Ui.SLIDE_IMMEDIATE);
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
			dev.sendCMD(BLEBarrel.cmdShutdownX5);
			buzz(150);
			toast("Camera powering off");
		}
	}
}
