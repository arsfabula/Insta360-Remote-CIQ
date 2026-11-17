using Toybox.Test;
using Toybox.WatchUi as Ui;
using Toybox.Application;
using BLEBarrel;

// The UI half of the unit suite: PR #2's UiTest vectors (pr2-ref, green at
// 18/18 there) against this app's ported pages. The Settings module kept its
// names in the port, so the row vectors run verbatim; the one vector that
// drives the capture delegate is the PR's own flow - the tap/START
// distinction the port carried - reached through this app's state symbols.

// Settings rows exist at the X5-like levels; every vector here names one of
// those levels before asking the page for its rows.
function uiLink() {
	var d = freshLink();
	BLEBarrel.menuLevel = 2;
	BLEBarrel.mMessage = "Start";
	return d;
}

// EV stops at its ends: one more press past +4.0 / -4.0 keeps the end value.
// (PR vector, verbatim.)
(:test)
function evStopsAtEnds(logger) {
	uiLink();
	Settings.vals = {};
	Settings.acked = {};
	var row = Settings.ev(7);
	var n = row[2].size();
	for (var i = 0; i < n + 3; i++) {
		Settings.step("v0", row, 1);
	}
	var top = Settings.label("v0", row);
	for (var i = 0; i < 2 * n; i++) {
		Settings.step("v0", row, -1);
	}
	var bottom = Settings.label("v0", row);
	logger.debug("top=" + top + " bottom=" + bottom);
	return top.equals("+4.0") && bottom.equals("-4.0");
}

// Other rows keep wrapping (lens: 360° -> Front -> 360°). (PR vector,
// verbatim.)
(:test)
function otherRowsStillWrap(logger) {
	uiLink();
	Settings.vals = {};
	Settings.acked = {};
	var row = Settings.lens();
	Settings.step("v0", row, 1);   // start index 0 -> Front
	Settings.step("v0", row, 1);   // wraps -> 360°
	var l = Settings.label("v0", row);
	logger.debug("lens=" + l);
	return l.equals("360°");
}

// A tap reaches onSelect first (no START key before it): onSelect must
// decline it so onTap, which knows the position, can focus the row. A real
// START press (onKeyPressed KEY_ENTER first) is handled by onSelect. (PR
// vector; the same contract as the delegate ported it.)
(:test)
function tapIsNotStartButKeyIs(logger) {
	var dev = uiLink();
	BLEBarrel.currentMode = "set";
	BLEBarrel.currentLabel = "Settings";
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	Settings.focus = 1;   // SOUND: START does nothing here, so the test has no side effects
	var d = new RemoteDelegate(dev);
	var tap = d.onSelect();
	d.onTapTimeout();     // fallback path (no onTap followed): runs START once, harmless here
	d.onKeyPressed(new Ui.KeyEvent(Ui.KEY_ENTER, Ui.PRESS_TYPE_ACTION));
	var key = d.onSelect();
	logger.debug("tap=" + tap + " key=" + key);
	return tap == false && key == true;
}

// The crash the user's own simulator run named, held as a vector. At the moment
// a link becomes writable, the link books three delayed asks (the authorization
// probe at 500 ms, the camera state at 1500 ms, the card at 2500 ms) and the
// opened app's view then starts its 125 ms tick. One process, one timer pool:
// Toybox.Timer documents it - "The number of available timers (default 3) ...
// An error will occur if too many timers are set" - and a widget pays that
// budget once for the glance session and the opened app together. Four starts is
// the "Too Many Timers" the opened widget took at RemoteView.onShow, while the
// same startup passed in the older shape of this app, which owned no view timer
// and sat exactly at the ceiling. So this vector arms the link's schedule the
// way the link's ready site does now (armLinkAsks, where the service walk found
// the characteristic) and then drives the very line the crash named.
// Green means the link's asks and the view's tick fit one pool; against a barrel
// that keeps a Timer object per ask, this is the vector that takes the crash.
// The refusal of the host is not a catchable Lang exception: a probe of the same
// shape on this target (descentmk351mm, 9.1.0) ended the run with
//    Error: Too Many Timers Error / Failed invoking <symbol>
// exactly as the widget session does. So nothing here catches it - the vector is
// green only while the count fits.
(:test)
function startupWithLinkAsksArmed(logger) {
	var dev = uiLink();
	dev.scheduleAuthProbe();
	dev.scheduleCamStatusAsk();
	dev.scheduleStorageAsk();
	var alarm = BLEBarrel.linkAlarm;
	if (alarm == null) {
		logger.debug("the link booked no alarm: its schedule is not armed");
		return false;
	}
	var app = Application.getApp();
	var pair = app.getInitialView();
	if (pair == null || pair.size() != 2) {
		logger.debug("getInitialView answered nothing");
		return false;
	}
	try {
		// onShow directly, not pushView: this is the line of the crash report
		// (RemoteView.onShow, timer.start of the tick) and the pool is what is
		// under test, so the call is made once, by name, with the asks armed.
		pair[0].onShow();
		Ui.requestUpdate();
		pair[0].onHide();
	} catch (e) {
		logger.debug("the view could not start its tick over the armed link: " + e);
		return false;
	}
	// One object carried all three asks; no second Timer was made on the way.
	var single = BLEBarrel.linkAlarm == alarm;
	logger.debug("asks=" + BLEBarrel.authProbeDue.toString() + "/" + BLEBarrel.x5StatusDue.toString() +
		"/" + BLEBarrel.x5StorageAskDue.toString() + " one alarm object=" + single);
	return single;
}

// The schedule of the link keeps the nearest date and one object. The five
// delayed actions of the link (auth probe, state ask, card ask, write retry,
// start delay) live in dates, not Timer objects; the alarm is armed for the
// nearest of them, and taking one date down leaves the others booked.
(:test)
function linkScheduleKeepsNearestDate(logger) {
	var dev = uiLink();
	dev.scheduleAuthProbe();
	dev.scheduleCamStatusAsk();
	dev.scheduleStorageAsk();
	var nearest = dev.earliestAskDue();
	var bookedAuth = BLEBarrel.authProbeDue != null;
	var bookedState = BLEBarrel.x5StatusDue != null;
	var bookedCard = BLEBarrel.x5StorageAskDue != null;
	// The link's ask delays are 500 / 1500 / 2500 ms, so the probe is
	// the nearest date and the alarm must be armed for it.
	var nearestIsProbe = nearest == BLEBarrel.authProbeDue;
	// Taking one date down leaves the others booked: the state ask is dropped,
	// the probe stays the nearest date and the card ask stays booked behind it.
	dev.cancelStatusTimer();
	var stateGone = BLEBarrel.x5StatusDue == null;
	var nearestStillProbe = dev.earliestAskDue() == BLEBarrel.authProbeDue;
	var cardStillBooked = BLEBarrel.x5StorageAskDue != null && BLEBarrel.x5StorageAskDue > BLEBarrel.authProbeDue;
	// A nearer booking wins the alarm: a start delay booked one millisecond out
	// is what the alarm is armed for from then on.
	dev.armStartDelay(1);
	var nearerWins = dev.earliestAskDue() == dev.startDelayDue;
	logger.debug("auth=" + bookedAuth + " state=" + bookedState + " card=" + bookedCard +
		" nearest=probe " + nearestIsProbe + " state dropped=" + stateGone +
		" probe still nearest=" + nearestStillProbe + " card kept=" + cardStillBooked +
		" nearer wins=" + nearerWins);
	return bookedAuth && bookedState && bookedCard && nearestIsProbe && stateGone &&
		nearestStillProbe && cardStillBooked && nearerWins;
}

// The authorization edge the port had lost: the PR's screen named it, and the
// port carried lastAuth without the code that read it. The datum is the camera's
// own answer of the authorization probe - the field 1 mark 0x08 then the status,
// the octets applyAuthProbe reads at 17-18 of a frame declared 20 - pushed
// through that parser and then watched from the screen's side. The screen names
// two edges: the camera asking its user (status 1) and the link opening after an
// ask (1 -> 0). Nothing else is an edge: "no answer yet" (-1) is not one, a
// status seen twice is not one, and 3..6 (a client already connected) is
// remembered without a word, exactly as the port draws it. Routing that answer
// by sequence is the protocol half's own territory; the question here is what
// the app makes of an answered status.
(:test)
function authSurfaceNamesTheCameraEdges(logger) {
	var dev = uiLink();
	var view = new RemoteView(dev);
	var quiet = view.noteAuth();           // no answer yet: -1
	var askAgain0 = view.noteAuth();
	dev.applyAuthProbe(frame(20, 0x27, 0x00, 0x41, [0x08, 0x01]b));
	var ask = view.noteAuth();
	var repeat = view.noteAuth();          // same status a second time
	dev.applyAuthProbe(frame(20, 0x27, 0x00, 0x41, [0x08, 0x00]b));
	var open = view.noteAuth();
	dev.applyAuthProbe(frame(20, 0x27, 0x00, 0x41, [0x08, 0x03]b));
	var client = view.noteAuth();
	dev.applyAuthProbe(frame(20, 0x27, 0x00, 0x41, [0x08, 0x01]b));
	var askAgain = view.noteAuth();
	logger.debug("quiet=" + quiet + " ask=" + ask + " repeat=" + repeat + " open=" + open +
		" client=" + client + " thenAskAgain=" + askAgain + " status=" + dev.peekAuthStatus().toString());
	return quiet == :none && askAgain0 == :none && ask == :ask && repeat == :none &&
		open == :allowed && client == :none && askAgain == :ask;
}

// Real watch: tapping anywhere on a two-line title (PHOTO / BURST) must
// focus the title, not fall through to START. The title's tap area is its
// full drawn height, rows keep theirs. (PR vector, verbatim.)
(:test)
function titleTapAreaCoversAllLines(logger) {
	Settings.hitX0 = 100;
	Settings.hitYs = [80, 140, 174];   // title centre, row 1, row 2
	Settings.hitHs = [90, 34, 34];     // two-line title is 90 px tall
	var top = Settings.rowAt(150, 40);      // upper title line
	var bottom = Settings.rowAt(150, 120);  // lower title line
	var row1 = Settings.rowAt(150, 140);
	var miss = Settings.rowAt(150, 230);
	var left = Settings.rowAt(50, 80);      // icon column
	logger.debug("top=" + top + " bottom=" + bottom + " row1=" + row1 + " miss=" + miss + " left=" + left);
	return top == 0 && bottom == 0 && row1 == 1 && miss == -1 && left == -1;
}

// Startup smoke (the PR had no equivalent - it is the vector the first launch
// of the ported UI was missing, and the user's sim crash named it): the very
// line Main.getInitialView answers, then the pair pushed through the real
// view pipeline. The rest of the suite drives modules and delegates directly
// and never instantiates the view; this one constructs it, shows it, lays it
// out and draws its first frames. If the ported screen faults on startup,
// this names the line in the sim log.
(:test)
function startupUiSmoke(logger) {
	uiLink();   // the X5-shaped state a real bond leaves: level 2, "Start"
	var app = Application.getApp();
	var pair = app.getInitialView();
	if (pair == null || pair.size() != 2) {
		logger.debug("getInitialView answered nothing");
		return false;
	}
	var view = pair[0];
	var del = pair[1];
	try {
		// No processEvents on this target (verified absent from api.mir):
		// pushView runs the constructors and the show half of the lifecycle
		// synchronously; the draw half is driven by the sim and would end the
		// run as an error if it faults - either way the vector names it.
		Ui.pushView(view, del, Ui.SLIDE_IMMEDIATE);
		Ui.requestUpdate();
	} catch (e) {
		logger.debug("startup smoke exception: " + e);
		return false;
	}
	Ui.popView(Ui.SLIDE_IMMEDIATE);
	logger.debug("first frames crossed");
	return true;
}

// The screen tells the truth about an absent camera (bench of 12 nov., the 5th
// session): after the X5 was switched off and a scan round exhausted itself,
// the watch showed a READY screen - "Default Video", green ring, the X5 serial
// at the bottom (deviceName is kept across opens) - while no camera existed.
// The cause is a fact the view never read: uiState answered READY as a
// fallthrough, and the NOT_FOUND screen the view draws was unreachable. The
// absence is the barrel's own datum (device is nulled at the link teardown),
// read after the record states so a link lost mid-recording keeps the
// recording screen; NOT_FOUND's START press stays an answer (runStart sends,
// the transport's device-null leg restarts the scan).
(:test)
function screenTruthNamesTheAbsentCamera(logger) {
	uiLink();                            // a bond-shaped state: level 2, "Start", stopped
	var ok = true;
	var dev = new BLEBarrel.BleDevice(); // the app's single instance shape: no device yet
	ok = ok && !dev.hasLink();
	ok = ok && uiState(dev) == UI_NOT_FOUND;
	ok = ok && uiState(dev) != UI_READY;
	ok = ok && uiState(null) == UI_NOT_FOUND;      // no view object: the same absence
	BLEBarrel.mMessage = "Scanning...\n64";
	ok = ok && uiState(dev) == UI_SEARCHING;      // the search still answers first
	BLEBarrel.mMessage = BLEBarrel.currentLabel + "\n" + BLEBarrel.startMessage;
	// The order, named without posing a link: the record states answer BEFORE the
	// absence, so a link lost mid-recording keeps the recording screen (and its
	// "camera still recording" note) instead of claiming "no camera".
	BLEBarrel.recState = BLEBarrel.stateStartRec;
	ok = ok && uiState(dev) == UI_RECORDING;
	BLEBarrel.recState = BLEBarrel.stateStarting;
	ok = ok && uiState(dev) == UI_STARTING;
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	ok = ok && uiState(dev) == UI_NOT_FOUND;
	// The present leg (a link answers READY) has no unit route: no API builds a
	// BluetoothLowEnergy.Device, and a (:test)-annotated class method is taken
	// as a test case by the runner (it calls it with a logger, and the symbol
	// is not found). Only the class poses that fact, at its connected branch;
	// it is proven at the bench of 12 nov.: with the X5 bonded, uiState answered
	// READY all through the measured ladder (modes applied, echoes confirmed).
	logger.debug("truth crossed");
	return ok;
}
