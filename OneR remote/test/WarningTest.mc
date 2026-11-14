using StartWarning;

// The countdown half of the unit suite: the start-warning decision of the
// design of 14 nov. (start-warning-design.md). The module is pure on purpose
// - values in as arguments, values out - so every branch of the countdown is
// reachable here without an app context. The property key itself, the menu
// open that writes, and the BACK that must not write are proven on the bench
// (Task 3); what lives here is the arithmetic those scenes will show.

// The absent key is the default user: the warning shows, and opening the menu
// writes nothing - the countdown starts only when the user picks it.
(:test)
function warningAbsentAlwaysShowsAndWritesNothing(logger) {
	var show = StartWarning.shouldShow(null);
	var write = StartWarning.openWrite(null);
	logger.debug("absent show=" + show.toString() + " openWrite=" + (write == null ? "none" : write.toString()));
	return show && write == null;
}

// Any positive value still presents the warning; 0 is the end of it.
(:test)
function warningShowsAtAnyPositive(logger) {
	var a = StartWarning.shouldShow(4);
	var b = StartWarning.shouldShow(1);
	var c = StartWarning.shouldShow(0);
	logger.debug("show 4=" + a.toString() + " 1=" + b.toString() + " 0=" + c.toString());
	return a && b && !c;
}

// The menu open is the only counter: N becomes N-1, and the reading at 1
// writes 0 (the last presentation announces its own end).
(:test)
function warningMenuOpenCountsDown(logger) {
	var a = StartWarning.openWrite(4);
	var b = StartWarning.openWrite(2);
	var c = StartWarning.openWrite(1);
	logger.debug("open 4->" + a.toString() + " 2->" + b.toString() + " 1->" + c.toString());
	return a == 3 && b == 1 && c == 0;
}

// The user ruled "N commence a 4" (14 nov.): the visible countdown then
// starts at the promised 3 on the next menu read.
(:test)
function warningPickStartsAtFour(logger) {
	var v = StartWarning.pickValue();
	logger.debug("pick=" + v.toString());
	return v == 4;
}

// The third menu row is the promise itself, number included: the literal 3
// while nothing counts, the remaining count while one runs, the sentence of
// the end at the last presentation. Singular "time" for one.
(:test)
function warningRowLabelsMatchPromise(logger) {
	var a = StartWarning.rowLabel(null);
	var b = StartWarning.rowLabel(4);
	var c = StartWarning.rowLabel(2);
	var d = StartWarning.rowLabel(1);
	logger.debug("labels: " + a + " | " + b + " | " + c + " | " + d);
	return a.equals("The warning will display 3 more times")
		&& b.equals("The warning will display 3 more times")
		&& c.equals("The warning will display 1 more time")
		&& d.equals("The warning will not display again");
}

// The store answers absence with null - both runtimes: the device (the first
// "lvl.<name>" reads of the bench, 12 nov.) and the simulator (the smoke of
// Task 2 printed "[warn] store answered none" from the real app store). What
// that smoke actually faulted was the entry class invoking a module function -
// the second sighting of the ucd2DiagFrame shape - and the decision now rides
// StartWarning.Gate for that reason; see the note in the module. These two
// vectors hold what the unit can hold: absence reads as null, a value is
// carried through a write and a re-read intact.
class PropsSilent {
	function getProperty(id) { return null; }
	function setProperty(id, v) { }
}
class PropsHolding {
	var store = {};
	function initialize() { store["warnFadeLeft"] = 4; }
	function getProperty(id) { return store[id]; }
	function setProperty(id, v) { store[id] = v; }
}
(:test)
function warningKeyReadOfSilentStoreIsNull(logger) {
	var a = StartWarning.readLeft(new PropsSilent());
	logger.debug("silent read=" + (a == null ? "null" : a.toString()));
	return a == null;
}

// A value that is there comes back unchanged and survives a write-then-read:
// this round-trip is exactly the countdown crossing a restart.
(:test)
function warningKeyCarriesValueThroughAStore(logger) {
	var h = new PropsHolding();
	var v = StartWarning.readLeft(h);
	var ok = StartWarning.writeLeft(h, 2);
	var after = StartWarning.readLeft(h);
	logger.debug("held=" + v.toString() + " written=" + ok.toString() + " after=" + after.toString());
	return v == 4 && ok && after == 2;
}
