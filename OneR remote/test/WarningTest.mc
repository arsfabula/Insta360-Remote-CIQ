using StartWarning;

// The countdown half of the unit suite: the start-warning decision of the
// design of 14 nov. (start-warning-design.md). The module is pure on purpose
// - values in as arguments, values out - so every branch of the countdown is
// reachable here without an app context. The property key itself, the menu
// open that writes, and the BACK that must not write are proven on the bench
// (Task 3); what lives here is the arithmetic those scenes will show.

// The absent key is the default user: the warning shows, and the FIRST menu
// open seeds the countdown its title promises. The old rule (absent opens
// write nothing, the countdown starts only when the row is picked) failed the
// wrist bench of 14 nov. evening: on a fresh install the user opened the menu
// several times and the title never moved off "3 more display" - the promise
// never counts down because nothing was ever seeded. Seeding pickValue()-1
// makes the promised sequence exact from a first install: 3, 2, 1, the end
// message, silence. BACK still writes nothing; only this open writes.
(:test)
function warningAbsentOpenSeedsThePromise(logger) {
	var show = StartWarning.shouldShow(null);
	var write = StartWarning.openWrite(null);
	logger.debug("absent show=" + show.toString() + " openWrite=" + (write == null ? "none" : write.toString()));
	return show && write != null && write == 3;
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

// The third menu row is the promise itself, number included (copy re-dictated
// by the user on 14 nov. after the 51 mm bench showed the long sentence cut).
// The \n is part of the copy as the user prescribed it that evening ("est-ce
// que le titre supporte le \n pour scinder apres display") - the split point
// is his, after the word "display", two balanced lines for the menu title.
// Singular "display" for one.
(:test)
function warningRowLabelsMatchPromise(logger) {
	var a = StartWarning.rowLabel(null);
	var b = StartWarning.rowLabel(4);
	var c = StartWarning.rowLabel(2);
	var d = StartWarning.rowLabel(1);
	logger.debug("labels: " + a + " | " + b + " | " + c + " | " + d);
	return a.equals("3 more display\nof this warning")
		&& b.equals("3 more display\nof this warning")
		&& c.equals("1 more display\nof this warning")
		&& d.equals("No more display\nof this warning");
}

// The store answers absence with null - both runtimes: the device (the first
// "lvl.<name>" reads of the bench, 12 nov.) and the simulator (instrumented
// as "[warn] store answered none" at Task 2's smoke, from the real app store;
// that instrumentation was temporary and is gone from the shipped code). What
// the smoke actually faulted was the ENTRY CLASS invoking a module function -
// the second sighting of the ucd2DiagFrame shape - and the decision was fixed
// by moving it to the view's first draw, class scope, no Gate class anywhere.
// These two vectors hold what the unit can hold: absence reads as null, a value is
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
