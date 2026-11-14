using Toybox.Lang;

// The start-warning countdown, pure. The property key, the reads and the
// writes live with the callers (RemoteView.onUpdate asks the decision once,
// at the first draw of a cold start - see the note there for why not
// Main.onStart; the warning menu writes at its open); this module only turns
// the value it was handed into what to show, what to write, and how the
// menu's promise line reads.
// The numbers are the design of 14 nov. (start-warning-design.md): the
// countdown counts only menu reads, never time and never a BACK exit, and
// choosing it writes 4 so the visible countdown starts at the promised 3.
module StartWarning {

	// The one key the warning owns. Absent is the default state, and both
	// runtimes answer absence with null (the bench's first "lvl.<name>" reads
	// on the device, 12 nov.; the sim's own answer, "[warn] store answered
	// none", at the smoke of Task 2). The reads and writes below are defense
	// and one place for the key, nothing more mystical than that.
	const KEY = "warnFadeLeft";

	// Who may call the functions below: any class scope - the delegate's menu
	// branch and the view's first draw do, the shape the bench proved for
	// Settings and Levels calls. The entry class may not: Main.onStart calling
	// a source-module function faults "Illegal Access (Out of Bounds)", stack
	// one entry deep, with the callee absent from it - the second sighting of
	// the shape the ucd2DiagFrame note in Main.onStart describes (the first
	// version of the warning decision faulted there, 14 nov.; a Gate class
	// instantiated from onStart faulted the same way).

	// The property read, on any object that answers the AppBase shape. A
	// refusal to answer is the absence: null.
	function readLeft(app) {
		try {
			return app.getProperty(KEY);
		} catch (ex) {
			return null;
		}
	}

	// The property write. A store that refuses is named by the answer, never
	// swallowed: the caller logs it.
	function writeLeft(app, value) as Lang.Boolean {
		try {
			app.setProperty(KEY, value);
			return true;
		} catch (ex) {
			return false;
		}
	}

	function shouldShow(left) as Lang.Boolean {
		return left == null || left > 0;
	}

	// Value to store when the warning menu opens. One less - the reading
	// itself is spent. While no countdown runs the open SEEDS the promise its
	// title is making: pickValue()-1. The wrist bench of 14 nov. evening is
	// what settled this: with the old "absent opens write nothing" rule a
	// fresh install never moved off "3 more display" no matter how many times
	// the menu was opened - a promise that never counts down is a lie, and
	// the user named it ("le countdown ne décrémente pas"). Seeding makes the
	// promised sequence exact from a first install: 3, 2, 1, the end message,
	// silence. BACK still writes nothing: opening this menu is the only write.
	function openWrite(left) {
		if (left == null) { return pickValue() - 1; }
		return left - 1;
	}

	function pickValue() as Lang.Number {
		return 4;
	}

	// The third menu row, the promise in its own words. left is the value
	// read BEFORE this open's write: what will follow this reading is left-1.
	// The copy was re-dictated by the user on 14 nov. after the 51 mm bench
	// showed the first sentence cut at the bottom of the menu. The \n is his
	// split point ("scinder apres display"), the evening he prescribed the
	// sentence as the menu title - two balanced lines, the system's own wrap
	// left to agree with it. Whether the title prints the break is the next
	// bench read; the words are pinned here either way.
	function rowLabel(left) as Lang.String {
		if (left == null) {
			return "3 more display\nof this warning";
		}
		var n = left - 1;
		if (n <= 0) {
			return "No more display\nof this warning";
		}
		if (n == 1) {
			return "1 more display\nof this warning";
		}
		return n + " more display\nof this warning";
	}
}
