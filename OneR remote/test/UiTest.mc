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
