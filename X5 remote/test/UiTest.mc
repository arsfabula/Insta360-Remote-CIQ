using Toybox.Test;
using Toybox.WatchUi as Ui;
using BLEBarrel;

// EV stops at its ends: one more press past +4.0 / -4.0 keeps the end value.
(:test)
function evStopsAtEnds(logger) {
	BLEBarrel.deviceName = "X5 1ABCDE";
	Settings.vals = {}; Settings.acked = {};
	var row = Settings.ev(7);
	var n = row[2].size();
	for (var i = 0; i < n + 3; i++) { Settings.step("v0", row, 1); }
	var top = Settings.label("v0", row);
	for (var i = 0; i < 2 * n; i++) { Settings.step("v0", row, -1); }
	var bottom = Settings.label("v0", row);
	logger.debug("top=" + top + " bottom=" + bottom);
	return top.equals("+4.0") && bottom.equals("-4.0");
}

// Other rows keep wrapping (lens: 360° -> Front -> 360°).
(:test)
function otherRowsStillWrap(logger) {
	Settings.vals = {}; Settings.acked = {};
	var row = Settings.lens();
	Settings.step("v0", row, 1);   // start index 0 -> Front
	Settings.step("v0", row, 1);   // wraps -> 360°
	var l = Settings.label("v0", row);
	logger.debug("lens=" + l);
	return l.equals("360°");
}

// A tap reaches onSelect first (no START key before it): onSelect must decline it so onTap,
// which knows the position, can focus the row. A real START press (onKeyPressed KEY_ENTER
// first) is handled by onSelect.
(:test)
function tapIsNotStartButKeyIs(logger) {
	BLEBarrel.deviceName = "X5 1ABCDE";
	BLEBarrel.currentMode = "set"; BLEBarrel.currentLabel = "Settings";
	BLEBarrel.recState = BLEBarrel.stateStopRec;
	Settings.focus = 1;   // SOUND: START does nothing here, so the test has no side effects
	var d = new RemoteDelegate(new BLEBarrel.BleDevice());
	var tap = d.onSelect();
	d.onTapTimeout();     // fallback path (no onTap followed): runs START once, harmless here
	d.onKeyPressed(new Ui.KeyEvent(Ui.KEY_ENTER, Ui.PRESS_TYPE_ACTION));
	var key = d.onSelect();
	logger.debug("tap=" + tap + " key=" + key);
	return tap == false && key == true;
}

// Real watch: tapping anywhere on a two-line title (PHOTO / BURST) must focus the title, not
// fall through to START. The title's tap area is its full drawn height, rows keep theirs.
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
