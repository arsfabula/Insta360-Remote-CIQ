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

// The one rule of the long press (the user's design A, decision of 17 nov.
// 2026): at 700 ms the press belongs to the settings page, under it the press
// belongs to START. The rule is this pure function, and the suite holds it:
// holdAtThresholdFires / holdJustUnderThresholdDoesNotFire for the threshold,
// startPressWaitsForTheRelease for the venues. Everything else here (the arm
// at the key DOWN, the release that decides under the threshold, the pump's
// leg that pages at it, the key down's SELECT that only consumes) carries
// this answer - no Timer object per gesture, the same System.getTimer()
// domain as the three debounces below. The venues are dated by the bench of
// 18 nov. 2026: the base view delivers a key press's SELECT at the key DOWN
// (see onSelect), so no decision may be taken there.
const LONG_PRESS_MS = 700;
function holdingDue(startAt as Lang.Number, now as Lang.Number) as Lang.Boolean {
	return now - startAt >= LONG_PRESS_MS;
}

// The Settings page is no longer an id at all (the user's decision of 17 nov.
// 2026, design B): it is a view pushed above the base, and the pushed view
// answers its rows through the Settings module with the family each row belongs
// to - the mode id for the option rows, "set" for sound and power. The
// pseudo-mode "set", its inSettingsUI() question and the setReturnMode
// accounting of the PR (its barrel kept the return mode as camMode; here that
// name is the camera's own reported mode, a different datum) all fall with it:
// the base view never leaves its mode, so there is nothing to remember.

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

// The mode wheel and the Mode menu answer the chain, not a hand-written list: the
// rows of the level in force, [label, id] pairs in the order of the table. The ucd2
// sentinel row of the replacing level stays where the table put it (its selection
// arms the envelope). The "Settings" entry of the levels that had option rows fell
// with the pseudo-mode it named (17 nov. 2026): the wheel and the menu only ever
// name modes again, the one action that reaches the settings page is the long
// gesture and the gear, both calling openSettingsPage.
function modeList() {
	var out = [];
	var rows = Levels.rowsMain(BLEBarrel.menuLevel);
	var i = 0;
	while (i < rows.size()) {
		out.add([rows[i][Levels.RLB], rows[i][Levels.RID]]);
		i += 1;
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
	// The press in progress of START (the user's design A, 17 nov. 2026, its
	// venues corrected by the bench of 18 nov.): the key down arms this stamp;
	// the release under the threshold (onKeyReleased, it decides) or the view's
	// tick at the threshold (pumpDue, it pages) is what answers. No due date is
	// booked and no flag is kept: the tick asks holdingDue of this stamp every
	// 125 ms, so the rule stays the only comparison in the file.
	hidden var heldStartAt = null;
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

	// Connect IQ turns a screen tap into the SELECT behaviour first and only calls
	// onTap when onSelect returns false. A START press always reaches onKeyPressed
	// (KEY_ENTER) before onSelect, a tap never does. So onSelect without a fresh
	// START key press is a tap: hand it to onTap (which knows where the finger
	// was). If no onTap follows, the fallback deadline runs START on the next
	// pump, so a tap is never lost.
	function onSelect() {
		var key = startKeyAt != null && Sys.getTimer() - startKeyAt < 2000;
		inLog("select key=" + key);
		startKeyAt = null;
		if (!key) {
			tapPending = true;
			dueTap = Sys.getTimer() + 150;
			return false;
		}
		// The SELECT of a key press consumes and decides nothing. The bench of
		// 18 nov. 2026 (marq + epix sims, the author's runs: "ca demarre
		// directement un enregistrement") named what this port had assumed
		// away: the base view delivers this callback at the key DOWN, a few ms
		// after onKeyPressed, and that moment says nothing of the press length.
		// The decision belongs to the venues that know the length: the release
		// under the threshold (onKeyReleased, it shoots) and the tick at the
		// threshold (pumpDue, it pages). A host that never delivers the release
		// is answered by the leg too - at the threshold, as a long press - and
		// the [in] key up line of onKeyReleased names such a host at the bench.
		// The tap fallback above keeps its own deadline: a tap has no release
		// to wait for.
		return true;
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

	// Touch: a tap on a base-page row focuses it (the modern touch way, kept by
	// the user's decision 5 of 17 nov. 2026, validated at the epix bench); a tap
	// on the gear pushes the settings page; a tap elsewhere is START. Swipes
	// arrive as onPreviousPage / onNextPage, so swiping up / down changes the
	// focused value.
	function onTap(evt) {
		tapPending = false;
		dueTap = null;   // the tap answered itself: no fallback
		if (gearTapped(evt)) { openSettingsPage(); return true; }
		if (focusRowAt(evt)) { return true; }
		return runStart();
	}

	// A long press at the screen is the settings page, the same single action as
	// a long press on the START key (the user's decision 2 of 17 nov. 2026,
	// "boutons comme tactiles" - one gesture, one action, on both generations).
	// The per-row focus this entry used to answer gave way to the gesture; the
	// tap still focuses a row, above.
	function onHold(evt) {
		openSettingsPage();
		return true;
	}

	// The gear's target is the circle the view published for the icon it drew
	// this frame (RemoteView.drawSettingsCue writes gearHit, and a frame that draws
	// no gear publishes no target): the area of the entry follows the drawn
	// affordance, at whatever angle the icon stands - it moves with decision 6
	// and the target needs no second edit.
	hidden function gearTapped(evt) {
		if (gearHit == null) { return false; }
		var xy = evt.getCoordinates();
		var dx = xy[0] - gearHit[0];
		var dy = xy[1] - gearHit[1];
		return dx * dx + dy * dy <= gearHit[2] * gearHit[2];
	}

	hidden function focusRowAt(evt) {
		if (uiState(dev) != UI_READY || Settings.hitYs == null) { return false; }
		var xy = evt.getCoordinates();
		var i = Settings.rowAt(xy[0], xy[1]);
		inLog("tap " + xy[0] + "," + xy[1] + " -> entry " + i);
		if (i < 0) { return false; }
		Settings.focus = i;
		buzz(20);
		Ui.requestUpdate();
		return true;
	}

	// START key timestamp for the tap discrimination (see onSelect). The same
	// instant arms the press in progress (heldStartAt): the release below or
	// the view's tick will decide its length - the press owns no Timer.
	function onKeyPressed(evt) {
		if (evt.getKey() == Ui.KEY_ENTER) {
			startKeyAt = Sys.getTimer();
			heldStartAt = startKeyAt;
		}
		return false;
	}

	// The release of START: under the threshold it is where a short press
	// decides. A release at or after the threshold says nothing more - the tick
	// has already booked the press as long, and what it pages, it does not
	// undo. Whether every host delivers this callback is design risk 1, unknown
	// #1 of the bench, still open on real hardware: the [in] key up line below
	// names the hosts that answer it, and where none answers, the threshold
	// leg of pumpDue is what answers.
	function onKeyReleased(evt) {
		if (evt.getKey() != Ui.KEY_ENTER) { return false; }
		var now = Sys.getTimer();
		inLog("key up ENTER held=" + (heldStartAt != null ? (now - heldStartAt).toString() : "none") + "ms");
		if (heldStartAt == null) { return false; }
		if (holdingDue(heldStartAt, now)) { return false; }
		heldStartAt = null;
		runStart();
		return false;
	}

	// BACK: never overloaded (the user's ruling, 17 nov. 2026 evening — "le back
	// doit etre propre et servir uniquement a sortir de l'app"). This class owns
	// no onBack anymore: from the base view the system answers the gesture by
	// its own standard mechanism, and on the widget-loop devices that mechanism
	// is the only clean exit there is - System.exit() is a firmware no-op (the
	// SDK's own table names the forty such products), the base view of a true
	// widget may not be popped, and Garmin's engineers on its forum name no
	// other way ("a clean exit always requires the user to press BACK at the
	// top level"). On a glance device the same unclaimed BACK is what the
	// glance list answers. The exit ladder of that same morning lived exactly
	// one commit in this file's history: the user's benches judged it twice -
	// it hid the one pure exit, and on that generation the values it climbed
	// toward were out of the app's reach anyway, the SDK being formal ("will
	// never receive either the up/down button or up/down swipe events" on the
	// base view). Reaching a setting moves, by the same ruling the same day,
	// to a pushed view where every key does answer. Long-press BACK stays the
	// OS's; the menu a hold-UP opens is the Mode menu of onMenu, it carries no
	// exit row.

	// UP / DOWN in ready state: change the focused row (the mode, or a setting).
	hidden function stepFocused(dir) {
		if (Settings.focus == 0) { stepMode(dir); return; }
		var rows = Settings.rows(currentModeId);
		if (Settings.focus > rows.size()) { Settings.focus = 0; stepMode(dir); return; }
		var row = rows[Settings.focus - 1];
		if (row[3] == :power) { return; }
		stepRow(currentModeId, row, dir);
	}

	// One setting step, one leg: the base page above and the pushed settings
	// page (SettingsPageDelegate, through the live delegate uiPump) write
	// identically here - the frames built, the deferred write booked, the pump
	// and its mode-change guard answering (the user's design B of 17 nov.
	// 2026: "l'écriture différée et sa attente de changement de mode sont
	// gardées telles quelles"). The family id names the row's family to the
	// module: the current mode's id for its option rows, "set" for the page's
	// sound and power rows - the pseudo-mode passed "set" everywhere by
	// construction, and the page must not lose that distinction quietly.
	// Public, like pumpDue: the pushed page's delegate reaches it through
	// uiPump, the same way RemoteView reaches the pump (hidden would ask the
	// compiler a class-vs-file visibility question this file never tests).
	function stepRow(id, row, dir) {
		pendingSetFrames = Settings.step(id, row, dir);
		pendingSetKey = Settings.key(id, row);
		settingHeld = false;   // this write's deferral, when it comes, is named once
		dueSet = Sys.getTimer() + 800;
		Ui.requestUpdate();
	}

	// The one action of every settings entry - long press START (the pump's
	// threshold leg), long press at the screen (onHold), tap of
	// the gear (onTap): push the settings page above the base (the user's
	// decisions 2 and 3 of 17 nov. 2026). It is this class's method rather
	// than the file-level function the plan first named: the page writes
	// through this instance's deferred-write state (the stepRow note above),
	// and the live instance is already what every caller here reaches (the
	// uiPump note). One gesture named, one action, on both generations.
	function openSettingsPage() {
		var fams = [];
		var menu = buildSettingsMenu(fams);
		menu.setFocus(0);
		Ui.pushView(menu, new SettingsPageDelegate(self, dev, fams), Ui.SLIDE_UP);
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
		// The crossing gets its own line: the bench of 18 nov. judged a
		// setting only from the camera's silence. One line per write, at the
		// moment the frames go to the transport, the same [set] prefix as the
		// held leg - together they name every write's fate at the bench.
		Sys.println("[set] " + pendingSetKey + " sent x" + frames.size().toString());
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
		// The long-press leg, last of the four: at the threshold the press belongs
		// to the page. A release under the threshold has already disarmed the stamp
		// and decided; the key down's SELECT owns nothing here. Where a host never
		// delivers the release, this leg is also where a short press lands, as a
		// long one - the [in] key up line of onKeyReleased is what names such a
		// host at the bench.
		if (heldStartAt != null && holdingDue(heldStartAt, now)) {
			inLog("long press " + (now - heldStartAt).toString() + " ms: settings page");
			heldStartAt = null;
			openSettingsPage();
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
		// No "Exit app" row here anymore (decision of 17 nov. 2026): on the
		// widget-loop devices Sys.exit() is the firmware's no-op, and leaving
		// stands in BACK alone on both generations - BACK is never overloaded.
		menu.setFocus(focus);
		Ui.pushView(menu, new ModeDelegate(dev), Ui.SLIDE_UP);
		return true;
	}

	// Le geste de l'indicateur d'action (regle de l'utilisateur, 16 nov.) :
	// les montres sans comportement menu - Venu 4, Venu X1, vivoactive 6,
	// Approach S72 - ne connaissent que celui-la, et c'est le geste qu'elles
	// montrent a l'ecran hors application, donc deja connu de l'utilisateur.
	// Le delegue ne remplace pas onMenu, il s'y range : un seul menu, deux
	// gestes. La vue active l'indicateur (RemoteView.onShow) ; sur les cinq
	// boutons le systeme n'appelle pas ce geste ici, onMenu reste la voie.
	function onActionMenu() {
		return onMenu();
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
		if (id.equals("forceopen")) {
			// CdC item 159, the ceiling of a visit of the axis — the same rule the
			// mainline's entry of the same name answers (InputDelegate :657-668): a
			// fresh opening of the forcing submenu is a fresh ceiling, the way a
			// fresh bond is one. Without this site the ported app carries the defect
			// the sim bench named on 15 nov.: the only reset of the counter lived in
			// the MenuLevel entry, an entry this UI does not carry, so a forced run
			// died for good at the tenth write ([hook] refused) and no choice could
			// re-arm it before an app restart. The entry that opens the submenu of
			// the axis in this UI is the one below — it ends one visit and takes the
			// counter of the forcing back; the print answers at the site that decides
			// it (criterion 14 of 11.3), never by the absence of a count.
			BLEBarrel.hookSent = 0;
			Sys.println("[hook] reset sent=0");
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
// force<model> / forceother / forceoff). Same datums the mainline's Menu2Delegate sets: the forcing
// lands at the selection of the choice, where the datum of the run changes.
class ForceModelDelegate extends Ui.Menu2InputDelegate {
	function initialize() {
		Menu2InputDelegate.initialize();
	}

	function onSelect(item) {
		var id = item.getId() as Lang.String;
		// What a forcing choice answers is the same datum the generated route answers at
		// its own selection (InputDelegate :604-641): the pair (testModel, testLevel)
		// the chain clears at the next link, the level and the model in force for the
		// run, the envelope that follows the model, the radio that follows the position
		// axis, and the confirmation kept under the name on air. This site set only the
		// pair, and called noteConfirmedLevel() without arguments — a latent crash
		// since the weld of 60304c7, named at the sim bench of 15-nov-2026: a line
		// "[force] X6 level=3" followed by "Not Enough Arguments" and the app's death.
		// The entry is the one the user reaches (the "Force model" item of the main
		// menu), so it answers the question the user asked.
		var forcedModel = "";
		var forcedLevel = -1;
		if (id.equals("forceoff")) {
			// "off" answers again by the model the bond named: the choice names it,
			// and the level answers the chain at the index of that name, so off can
			// never disagree with a detection.
			forcedModel = BLEBarrel.detectedModel;
			forcedLevel = Levels.levelOfName(forcedModel);
		} else if (id.equals("forceother")) {
			// "Other" names no model of the table: the level 0 base, the app of
			// start, stop and state alone. The level is dictated here, the datum
			// the mainline's selecteur of the same choice dictates (the user's
			// ruling of 16 nov. 2026) — the substring below would hand a name the
			// chain does not answer, so this branch stands before it.
			forcedModel = "Other";
			forcedLevel = 0;
		} else {
			forcedModel = id.substring(5, id.length());
			forcedLevel = Levels.levelOfName(forcedModel);
		}
		if (forcedLevel != -1) {
			BLEBarrel.testLevel = forcedLevel;
			BLEBarrel.testModel = forcedModel;
			BLEBarrel.menuLevel = forcedLevel;
			BLEBarrel.capModel = forcedModel;
			if (forcedLevel == 3) {
				// The UCD2 envelope, the state a real X6 connection arms at the bond.
				BLEBarrel.ucd2Armed = true;
				BLEBarrel.x5Armed = false;
			} else {
				BLEBarrel.ucd2Armed = false;
				// The arming of the X5 follows the model of the matrix in force, not its
				// level: the prefix chain of the barrel arms the X5 protocol for the X5
				// only (BLEBarrel.mc:2040), and leaves it disarmed for the models of the
				// older envelope and of the X4 line, so the arming follows the model the
				// way a connection does, and never the level of a gate.
				BLEBarrel.x5Armed = forcedModel.equals("X5");
			}
			// The position axis re-asks its decision at the site that changes the
			// family in force (Main.gpsSync, item 8 of the integration).
			mainApp.gpsSync();
			// The user's confirmation of a model and level, kept by the name on air
			// beside the chain's answer (item 7 of the integration) — the call the
			// crash left without arguments; the body of noteConfirmedLevel guards the
			// absent name itself.
			bleDevice.noteConfirmedLevel(BLEBarrel.deviceName, forcedLevel);
			// The choice that names the camera the user owns - "off", or a model equal
			// to the one the bond named - sends no frame of another protocol over this
			// bond, so the ceiling of the axis never applies and the forcing answers
			// disarmed: the same rule the generated route of the submenu already
			// answers at InputDelegate :646-657, now in the words the barrel owns
			// (clearForcing, :3190). Without it this site left the pair set to the
			// detected model:
			// hookForced() stayed true for an ordinary run, the ceiling counted that
			// run's writes, and past the ceiling every write of the user's own camera
			// was refused with "[hook] refused" - found by the named review of
			// 15-nov-2026. This is the third difference between these two sites found
			// the hard way (52e2549, 05f6e7b, this one); naming the rule once is where
			// the drift ends. The line below names the state in force for the rest of
			// the selection, never an absence (criterion 14 of 11.3).
			if (forcedModel.equals(BLEBarrel.detectedModel)) {
				// The clearing is answered by the class that owns the forcing
				// machinery (BleDevice, the single instance of the run), the way
				// this delegate already asks the link its other questions.
				bleDevice.clearForcing();
			}
			Sys.println("[force] " + forcedModel + " level=" + forcedLevel.toString()
				+ " forced=" + (!BLEBarrel.testModel.equals("")).toString()
				+ " sent=" + BLEBarrel.hookSent.toString());
		} else {
			// A name the chain does not answer: no model in force, no envelope
			// forced - the datum named once, in the barrel's link class.
			bleDevice.clearForcing();
			Sys.println("[force] off, the detected model answers again");
		}
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

// The settings page's rows, one page for both generations and both families
// (the user's decision 3 of 17 nov. 2026, design B): the current mode's
// option rows first, then the sound and power family - a title of the row's
// label, a sublabel of its current value, the row's id "r<n>" being its index
// in fams and in the menu. fams collects the [family id, row] pair of every
// drawn row: the page names the family per row to the Settings module, the
// distinction the pseudo-mode got for free (it was "set", so every row it
// drew answered "set") and that a pushed page could quietly lose - mode rows
// must step through the mode's id, the sound and power rows through "set".
// The Settings module keeps both families in rows(); only the host moved.
function buildSettingsMenu(fams) {
	var menu = new Ui.Menu2({:title => "Settings"});
	var fam = currentModeId;
	var rows = Settings.rows(fam);
	var i = 0;
	while (i < rows.size()) {
		menu.addItem(new Ui.MenuItem(rows[i][1], Settings.label(fam, rows[i]), "r" + fams.size(), {}));
		fams.add([fam, rows[i]]);
		i += 1;
	}
	fam = "set";
	rows = Settings.rows(fam);
	i = 0;
	while (i < rows.size()) {
		menu.addItem(new Ui.MenuItem(rows[i][1], Settings.label(fam, rows[i]), "r" + fams.size(), {}));
		fams.add([fam, rows[i]]);
		i += 1;
	}
	return menu;
}

// The pushed settings page's answers (the ModeDelegate and PowerOffDelegate
// precedent: a Menu2 and its delegate, pushed and answered from this file).
// UP / DOWN belong to the menu's own focus, as in every menu of this app -
// that is what the pushed view escapes the base view's restriction for (the
// SDK on the widget-loop base view: "will never receive either the up/down
// button or up/down swipe events"; "Any views pushed on top... will not have
// these input restrictions"). START steps the chosen row once, and the row
// stays on screen focused with its new value: the design's "r'ouvre la page à
// la ligne choisie" is answered by rewriting the row's sublabel in place -
// this SDK's WatchUi owns no replaceView / popAndPushView (read in its 9.3.0
// symbol table, 17 nov.), and this file already names the in-place rewriting
// of a changed row (the GPSon row of the Mode menu, item.setSubLabel). Same
// page, same row focused, new value: BACK stays one pop to the base, the pure
// exit of the user's decision 1 of 17 nov. 2026 is never re-asked. The write
// answers on the page's own ground - the base page's deferred leg cannot ring
// here: its due dates belong to the base view's 125 ms tick, and that tick
// stops while a view is pushed on top (View.onHide is documented "when a new
// View object is pushed on top of the current one", RemoteView.onHide stops
// the timer there - the bench of 18 nov. eve named it: "les valeurs
// selectionnees ne semblent pas etre transmises a la camera", while the touch
// path on the base screen crossed fine). The pushed menu that has always
// reached the camera answers at the selection - applyMode in ModeDelegate -
// and that is the precedent the page follows: step, flush at once, and
// onBack gives one last try at a write the mode-window guard held before the
// page leaves. The :power row answers the same
// confirmation as ever (confirmPowerOff) - it left the base page with the
// Exit rows of that morning, this is where it stands now.
class SettingsPageDelegate extends Ui.Menu2InputDelegate {
	hidden var pump;
	hidden var dev;
	hidden var fams;

	function initialize(pumpRef, device, famsArr) {
		Menu2InputDelegate.initialize();
		pump = pumpRef;
		dev = device;
		fams = famsArr;
	}

	function onSelect(item) {
		var id = item.getId() as Lang.String;
		// The id is "r" + the slot in fams (buildSettingsMenu). Read it back
		// with substring's real signature - (startIndex, END index): the bench
		// of 18 nov. 2026 (epix sim) crashed here reading it as a length,
		// "r0".substring(1, 1) -> "" -> toNumber null -> fams[null]. The
		// file's own precedent for the end form is addMenuLevelItems' forced-
		// model leg (substring(5, id.length())). The [set] line names the row
		// the page answers; the bench of 18 nov. already read it once: no such
		// line ever appeared between the page opening and a deliberate START -
		// the pushed menu does NOT take the release of the press that opened
		// it (design risk 1 / unknown #1, answered negative on both hosts).
		Sys.println("[set] page select id=" + id);
		var idx = id.substring(1, id.length()).toNumber();
		var fam = fams[idx][0];
		var row = fams[idx][1];
		if (row[3] == :power) { confirmPowerOff(dev); return; }
		pump.stepRow(fam, row, 1);
		// And the write crosses here, at the select - not on a due date behind
		// this page (the header above names why). stepRow keeps its bookkeeping
		// for the shared rules it holds; flushSetting is asked at once, its
		// mode-window guard included: a write the guard holds stays booked,
		// named once by the [set] held line, and onBack below tries it again
		// before the page leaves.
		pump.flushSetting();
		// The row arrays are literals of the static table (rows() hands the same
		// shape on every call): the stale one this page was built with carries
		// the same key and choices, and the value lives in the module under that
		// key - the fresh label therefore reads true, at once.
		item.setSubLabel(Settings.label(fam, row));
	}

	// The page's BACK is the pure pop of decision 1 (17 nov. 2026) - one
	// gesture, one return, nothing the user can feel added. Menu2 says it
	// plainly: "If this method is not overridden, it will pop the active
	// view" - so the override owns the pop, and takes it exactly as the Mode
	// menu's precedent takes its own (Ui.popView, SLIDE_DOWN, the same slide
	// the system would have). What belongs here is the write's last chance:
	// flushSetting's retry is a due date on a pump this page covers, so a
	// write held by the mode-window guard would otherwise sit booked behind a
	// page that leaves. Where the guard still holds at the pop, the write
	// stays booked and the base pump takes it back over (the [set] held line
	// named it once already).
	function onBack() {
		pump.flushSetting();
		Ui.popView(Ui.SLIDE_DOWN);
	}
}
