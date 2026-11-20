using Toybox.Test;
using Toybox.WatchUi as Ui;
using Toybox.Application;
using Toybox.System as Sys;
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
// The grip this vector holds on the delegate's state was the pseudo-mode
// "set" - it kept every runStart leg at an answer of true with no frame on
// the wire. The pseudo-mode fell (settings-push, 17 nov. 2026); the state
// now walked through is the UI_STARTING leg: the fallback press cancels the
// unconfirmed start (that leg sends no frame). The KEY press that follows is
// consumed and deferred (the bench of 18 nov. moved the decision to the
// release, and this vector sends none) - the vector holds the tap/key
// distinction alone, false from the tap, true from the key. The assertions
// do not move.
(:test)
function tapIsNotStartButKeyIs(logger) {
	var dev = uiLink();
	BLEBarrel.recState = BLEBarrel.stateStarting;
	var d = new RemoteDelegate(dev);
	var tap = d.onSelect();
	d.onTapTimeout();     // fallback path (no onTap followed): runs START once, harmless here
	d.onKeyPressed(new Ui.KeyEvent(Ui.KEY_ENTER, Ui.PRESS_TYPE_ACTION));
	var key = d.onSelect();
	logger.debug("tap=" + tap + " key=" + key);
	return tap == false && key == true;
}

// The threshold of the long press (the user's design A of 17 nov. 2026): the
// rule is a pure function, and these two vectors are its bench - at the
// threshold the gesture belongs to the settings page, just under it it belongs
// to START. Everything else (the arm in onKeyPressed, the cancellation by the
// release, the pump leg) only carries this answer.
(:test)
function holdAtThresholdFires(logger) {
	return holdingDue(1000, 1000 + 700) == true;
}
(:test)
function holdJustUnderThresholdDoesNotFire(logger) {
	return holdingDue(1000, 1000 + 699) == false;
}

// Where the short press is decided. The bench of 18 nov. 2026 (marq + epix
// sims, the author's own runs) named the defect the port had assumed away:
// the base view receives the SELECT of a key press at the key DOWN, a few ms
// after onKeyPressed, and that moment says nothing of the press length - the
// old leg shot the shutter there, so a long press "demarre directement un
// enregistrement" and its threshold leg could never ring (it also read the
// startKeyAt stamp, which the SELECT clears). The venue the delegate answers
// at now: the SELECT of a key press consumes and decides nothing; the release
// under the threshold is what decides. The observable is the UI_STARTING leg
// (the same shape the tap vector above chose): an unconfirmed start, which a
// deciding press cancels and a deferred one leaves standing. No link needed,
// no frame promised. The threshold itself stays held by the two vectors
// above; this one holds the venues.
(:test)
function startPressWaitsForTheRelease(logger) {
	var dev = uiLink();
	BLEBarrel.recState = BLEBarrel.stateStarting;
	var d = new RemoteDelegate(dev);
	d.onKeyPressed(new Ui.KeyEvent(Ui.KEY_ENTER, Ui.PRESS_TYPE_ACTION));
	var sel = d.onSelect();
	var deferred = BLEBarrel.recState == BLEBarrel.stateStarting;
	d.onKeyReleased(new Ui.KeyEvent(Ui.KEY_ENTER, Ui.PRESS_TYPE_UP));
	var decided = BLEBarrel.recState == BLEBarrel.stateStopRec;
	logger.debug("sel=" + sel + " deferred=" + deferred + " decided=" + decided);
	return sel == true && deferred && decided;
}

// The pushed page's id round trip, held as a vector because only a real bench
// could see it: the user's epix sim run of 18 nov. 2026 ended with
//   Error: Unhandled Exception / UnexpectedTypeException: Expected Number,
//   given null / onSelect() at RemoteDelegate.mc:906
// ("la selection de la valeur fait crasher l'app"). buildSettingsMenu hands
// each row the id "r" + its slot and SettingsPageDelegate.onSelect reads that
// id back; String.substring takes an END index as its second argument, not a
// length, so every two-character id ("r0"..."r9", the whole page under ten
// rows) parsed to an empty string, toNumber answered null, and fams[null]
// threw. The suite never saw it because stepRow was always reached directly,
// never through a MenuItem's id. This vector is the bench's own walk: build a
// real page, hand every real item to a real SettingsPageDelegate, and the row
// its id names must be the row that moves. Red before the fix is the
// exception itself - it ends the vector as an error, the same shape as the
// "Too Many Timers" note above: not catchable, only preventable.
(:test)
function settingsPageSelectStepsTheRowItsIdNames(logger) {
	BLEBarrel.menuLevel = 2;
	currentModeId = "p3";   // two option rows (burst, timer) over the two "set" rows
	var fams = [];
	var menu = buildSettingsMenu(fams);
	var dev = uiLink();
	var pump = new RemoteDelegate(dev);
	var page = new SettingsPageDelegate(pump, dev, fams);
	var ok = true;
	var steps = 0;
	var i = 0;
	while (i < 40) {
		var it = menu.getItem(i);
		if (it == null) { break; }
		var fam = fams[i][0];
		var row = fams[i][1];
		if (row[3] == :power) { i++; continue; }   // the confirmation path, not a step
		var before = Settings.label(fam, row);
		page.onSelect(it);
		var after = Settings.label(fam, row);
		logger.debug("row" + i.toString() + " " + fam + ":" + row[0] + " " + before + " -> " + after);
		ok = ok && !after.equals(before) && !after.equals("–");
		steps += 1;
		i++;
	}
	// p3 answers two option rows and "set" one stepping row (power is skipped):
	// three steps through three real ids, and no fourth item on the walk.
	return ok && steps == 3;
}

// The same bench, minutes later: "les valeurs selectionnees ne semblent pas
// etre transmises a la camera" - on the epix the touch path to a row is fine,
// the page reached by the long press is not. The page had booked its write on
// the base page's deferred leg (stepRow's +800 ms date, rung by the base
// view's 125 ms tick) - and the base view's tick stops the moment another
// view is pushed: View.onHide is documented "when a new View object is pushed
// on top of the current one", and RemoteView.onHide stops its timer there.
// The date can only ring after a return, and on this generation the app will
// not trust what the platform does to a covered widget-loop base: a menu
// pushed above it that has always reached the camera - the Mode menu -
// answers its write AT THE SELECTION (applyMode), and that precedent is what
// this vector asks the settings page for. The witness is the barrel's own:
// armWriteAck books x5WriteName at the wire, and freshLink left it the empty
// string. Red before the fix: still "".
(:test)
function settingsPageWriteCrossesAtTheSelect(logger) {
	BLEBarrel.menuLevel = 2;
	currentModeId = "p3";
	var fams = [];
	var menu = buildSettingsMenu(fams);
	var dev = uiLink();   // the link reset leaves x5WriteName = ""
	var pump = new RemoteDelegate(dev);
	var page = new SettingsPageDelegate(pump, dev, fams);
	page.onSelect(menu.getItem(0));   // the burst row of the mode, r0
	var witnessed = BLEBarrel.x5WriteName;
	logger.debug("witness=" + show(witnessed));
	return witnessed != null && witnessed.equals("p3:burst");
}

// The page's BACK, same decision of 17 nov. as ever - pure: the system's one
// pop to the base, nothing else the user can feel. What belongs to this
// delegate alone is one last try at a write its guard held: flushSetting's
// retry is booked on the pump this page covers (the note above), so a write
// stepped while a mode change still holds its window would otherwise sit
// booked behind a page that leaves. The vector books both halves: after a
// select under a closed window the barrel has the witness, and the gesture
// answers false - the page never consumes BACK.
(:test)
function settingsPageBackStaysPureAndRetriesTheHeldWrite(logger) {
	BLEBarrel.menuLevel = 2;
	currentModeId = "p3";
	var fams = [];
	var menu = buildSettingsMenu(fams);
	var dev = uiLink();
	var pump = new RemoteDelegate(dev);
	var page = new SettingsPageDelegate(pump, dev, fams);
	// A select while the mode window is open is held - the guard is the
	// same rule the base page obeys, and the hold is the vector's setup,
	// not its want: the write must not have crossed yet.
	BLEBarrel.modeReqId = "x";
	BLEBarrel.modeHoldUntil = Sys.getTimer() + 5000;
	page.onSelect(menu.getItem(0));
	var held = BLEBarrel.x5WriteName == null || BLEBarrel.x5WriteName.equals("");
	// The window closes; the page's BACK is next. The page is pushed for real
	// first - the overridden Menu2 onBack owns the pop its doc promises the
	// default would have done, and the vector's world must end as it began.
	// The gesture answers the held write once more; it is the system's pop,
	// consumed by nothing (the pop itself is the bench's half, as ever).
	BLEBarrel.modeReqId = null;
	BLEBarrel.modeHoldUntil = 0;
	Ui.pushView(menu, page, Ui.SLIDE_IMMEDIATE);
	page.onBack();
	var witnessed = BLEBarrel.x5WriteName;
	logger.debug("held=" + held + " witness=" + show(witnessed));
	return held && witnessed != null && witnessed.equals("p3:burst");
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

// The store's own report, seen in the ERA viewer on 20 nov. 2026 (one
// occurrence on 19 nov., Forerunner 970 fw 19.23, app 1.0.0, fre):
//   Error: Invalid Value / RemoteDelegate.stepMode:441 <- stepFocused:330 <-
//   onNextPage:428
// The chain is the customer's walk, not ours: a camera whose name the model
// table does not answer falls to level 0 at the scan (the barrel's default
// before any prefix branch), the level-0 menu is empty by decision (the CdC
// note at the model chain, BLEBarrel:4050 - "level 0, whose menu is empty"),
// and the wheel's rotation at :441 is a modulo by that empty size - the
// Invalid Value. No unit route leads to READY (the note above), and
// onPreviousPage/onNextPage stand behind it, so this vector names the wheel
// itself; stepMode stands public for it, the same way stepRow and pumpDue
// stand public for their venues. Red before the guard is the error itself -
// this runtime refusal is not catchable, only preventable, like the two
// precedents above. Green: the wheel does not move, and it books nothing.
(:test)
function modeWheelAtLevelZeroStaysPut(logger) {
	var dev = uiLink();
	BLEBarrel.menuLevel = 0;   // the level an unnamed prefix falls to
	var emptyMenu = modeList().size() == 0;   // the fact the wheel must respect
	var d = new RemoteDelegate(dev);
	d.stepMode(1);
	d.stepMode(-1);
	var labelHolds = BLEBarrel.currentLabel.equals("Default Video");
	var modeHolds = BLEBarrel.currentMode.equals("DefaultV");
	var nothingBooked = BLEBarrel.modeHoldUntil == 0;   // freshLink's before-value
	logger.debug("emptyMenu=" + emptyMenu + " label=" + labelHolds +
		" mode=" + modeHolds + " booked=" + nothingBooked);
	return emptyMenu && labelHolds && modeHolds && nothingBooked;
}
