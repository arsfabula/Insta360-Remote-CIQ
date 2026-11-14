using Toybox.Lang;

// The start-warning countdown, pure. The property key, the reads and the
// writes live with the caller (Main reads the decision at onStart, the
// warning menu writes at its open); this module only turns the value it was
// handed into what to show, what to write, and how the third menu row reads.
// The numbers are the design of 14 nov. (start-warning-design.md): the
// countdown counts only menu reads, never time and never a BACK exit, and
// choosing it writes 4 so the visible countdown starts at the promised 3.
module StartWarning {

	function shouldShow(left) as Lang.Boolean {
		return left == null || left > 0;
	}

	// Value to store when the warning menu opens: null (write nothing) while
	// no countdown runs, one less otherwise - the reading itself is spent.
	function openWrite(left) {
		if (left == null) { return null; }
		return left - 1;
	}

	function pickValue() as Lang.Number {
		return 4;
	}

	// The third menu row, the promise in its own words. left is the value
	// read BEFORE this open's write: what will follow this reading is left-1.
	function rowLabel(left) as Lang.String {
		if (left == null) {
			return "The warning will display 3 more times";
		}
		var n = left - 1;
		if (n <= 0) {
			return "The warning will not display again";
		}
		if (n == 1) {
			return "The warning will display 1 more time";
		}
		return "The warning will display " + n + " more times";
	}
}
