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
