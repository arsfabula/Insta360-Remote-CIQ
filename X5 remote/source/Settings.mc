using Toybox.Lang;
using BLEBarrel;

// Per-mode shooting settings for the X5. Only values confirmed on a camera screen are listed
// (docs/x5-protocol.md §5). BACK moves the focus Mode -> row 1 -> ... -> Mode; UP/DOWN change the
// focused value. The camera's replies with current values are longer than 20 bytes, so the
// watch cannot read them: a value is shown once the watch has set it ("–" before), dim until the
// camera acks it.
module Settings {
	var focus = 0;      // 0 = mode row, n = settings row n
	var vals = {};      // value key -> index into the row's choices
	var acked = {};     // value key -> true once the camera answered 200
	var hitX0 = 0;      // touch areas of the drawn column (set by the view)
	var hitYs = null;   // row centre y: [title, row 1, ...]
	var hitHs = null;   // row height for each entry (the title is taller, and can be two lines)
	var hitH = 0;

	// Index of the entry under a tap (0 = title, n = settings row n), -1 = none.
	function rowAt(x, y) {
		if (hitYs == null || x < hitX0) { return -1; }
		for (var i = 0; i < hitYs.size(); i++) {
			var h = (hitHs != null && i < hitHs.size()) ? hitHs[i] : hitH;
			if ((y - hitYs[i]).abs() <= h / 2) { return i; }
		}
		return -1;
	}

	// row: [key, field name, value labels, kind, mode, values, option type, start index]
	//   kind :opt   SET_PHOTOGRAPHY_OPTIONS(function mode, option type, value)
	//        :ev    same, value is EV x 10 sent as zig-zag sint32
	//        :lapse SET_TIMELAPSE_OPTIONS(timelapse mode) interval in ms
	//        :dur   SET_TIMELAPSE_OPTIONS(timelapse mode) duration in s
	//        :burst two options: 44 shots, 51 seconds (values are [shots, s])
	//        :lens  SET_ACTIVE_SENSOR
	//        :mute  SET_OPTIONS option 14 (camera mute), values 0 / 1
	//        :power START asks, then SET_SHUTDOWN
	//        :exit  START exits the app
	function timer(fm) { return ["timer", "TIMER", ["Off", "3s", "5s", "10s", "15s"], :opt, fm, [0, 3, 5, 10, 15], 26, 0]; }
	function size(fm) { return ["size", "SIZE", ["72MP", "18MP"], :opt, fm, [11, 12], 40, 0]; }
	function lens() { return ["lens", "LENS", ["360°", "Front"], :lens, 0, [3, 1], 0, 0]; }

	function ev(fm) {
		var labels = [];
		var values = [];
		for (var e = -40; e <= 40; e += 1) {
			// the camera's steps: whole stops and thirds (-4, -3.7, -3.3, -3, ...)
			var r = (e < 0 ? -e : e) % 10;
			if (r != 0 && r != 3 && r != 7) { continue; }
			values.add(e);
			var s = (e > 0) ? "+" : ((e < 0) ? "-" : "±");
			var a = (e < 0) ? -e : e;
			labels.add(s + (a / 10) + "." + (a % 10));
		}
		return ["ev", "EV", labels, :ev, fm, values, 7, 12];   // start at 0
	}

	// Resolution row from parallel label / value lists (option 31 values confirmed per mode).
	function res(fm, labels, values, start) { return ["res", "RES", labels, :opt, fm, values, 31, start]; }

	// 8K / 5.7K+ / 5.7K / 4K at every frame rate the camera accepts (Video, Loop, Road)
	function resFull(fm) {
		return res(fm,
			["8K30", "8K25", "8K24", "5.7K+30", "5.7K+25", "5.7K+24", "5.7K60", "5.7K50", "5.7K30", "5.7K25", "5.7K24",
			 "4K120", "4K100", "4K60", "4K50", "4K48", "4K30", "4K25", "4K24"],
			[167, 166, 165, 317, 318, 319, 252, 251, 10, 19, 20, 348, 250, 11, 12, 208, 0, 98, 97], 6);
	}

	function rows(id) {
		if (!BLEBarrel.isX5() || !(id instanceof Lang.String)) { return []; }
		if (id.equals("p0")) { return [timer(6), size(6), ev(6), lens()]; }
		if (id.equals("p2")) {
			return [["every", "EVERY", ["3s", "5s", "10s", "30s", "60s", "120s"], :lapse, 2,
				[3000, 5000, 10000, 30000, 60000, 120000], 0, 0], size(3)];
		}
		if (id.equals("p3")) {
			return [["burst", "BURST", ["3P/1s", "5P/1s", "10P/1s", "15P/1s", "15P/3s", "15P/6s", "15P/10s"], :burst, 5,
				[[3, 1], [5, 1], [10, 1], [15, 1], [15, 3], [15, 6], [15, 10]], 0, 3], timer(5)];
		}
		if (id.equals("p7")) {
			return [["dur", "TIME", ["∞", "3m", "5m", "10m", "15m", "30m", "1h", "2h", "3h", "5h", "10h"], :dur, 5,
				[0, 180, 300, 600, 900, 1800, 3600, 7200, 10800, 18000, 36000], 0, 0], timer(18)];
		}
		if (id.equals("v0")) {
			return [resFull(7), ev(7), lens()];
		}
		if (id.equals("v2")) {
			return [res(2, ["11K30", "8K30", "5.7K30"], [306, 167, 10], 2),
				["every", "EVERY", ["0.5s", "1s", "2s", "5s", "10s", "30s", "60s", "120s"], :lapse, 1,
				[500, 1000, 2000, 5000, 10000, 30000, 60000, 120000], 0, 2]];
		}
		if (id.equals("v4")) {
			return [res(12, ["8K30", "5.7K30"], [167, 10], 0),
				["speed", "SPEED", ["Auto", "10×", "15×", "20×", "30×", "60×"], :opt, 12,
				[0, 10, 15, 20, 30, 60], 37, 0]];
		}
		if (id.equals("v6")) {
			return [resFull(17), ["len", "LENGTH", ["1m", "3m", "5m", "10m", "15m", "20m", "25m", "30m", "∞"], :opt, 17,
				[60, 180, 300, 600, 900, 1200, 1500, 1800, 0], 29, 1], lens()];
		}
		if (id.equals("v11")) {   // PureVideo
			return [res(27, ["8K30", "8K25", "8K24", "5.7K30", "5.7K25", "5.7K24", "4K30", "4K25", "4K24"],
				[167, 166, 165, 10, 19, 20, 0, 98, 97], 3)];
		}
		if (id.equals("v14")) { return [resFull(63)]; }                                   // Road
		if (id.equals("v1")) { return [res(4, ["5.7K120", "3K240"], [307, 262], 0)]; }   // Bullet Time
		if (id.equals("set")) {
			// Watch page. SOUND = camera option MUTE (14), verified on the camera. The LED (120) and
			// beep (121) options are not stored by firmware 1.13.21, so there is no LIGHT row.
			// Power off = SET_SHUTDOWN (219), after a confirmation. Power-on needs the wake beacon
			// (docs/x5-protocol.md §6), which a Connect IQ app cannot send.
			return [["mute", "SOUND", ["On", "Off"], :mute, 0, [0, 1], 14, 0],
				["power", "", ["Power off camera"], :power, 0, [0], 0, 0],
				["exit", "", ["Exit app"], :exit, 0, [0], 0, 0]];
		}
		return [];
	}

	function key(id, row) { return (row[3] == :lens || row[3] == :mute) ? row[0] : id + ":" + row[0]; }

	function label(id, row) {
		if (row[3] == :exit || row[3] == :power) { return row[2][0]; }
		var i = vals[key(id, row)];
		return (i == null) ? "–" : row[2][i];
	}

	function isAcked(id, row) { return acked[key(id, row)] == true; }

	// Step the focused row's value; returns the frames to send (in order).
	// From the unknown state the first press moves one step from the camera's default.
	// Lists wrap at both ends, except EV, which stops at its ends.
	function step(id, row, dir) {
		var k = key(id, row);
		var n = row[2].size();
		var i = vals[k];
		if (i == null) { i = row[7]; }
		if (row[3] == :ev) {
			// EV stops at -4.0 / +4.0: wrapping would jump 8 stops with one press
			i += dir;
			if (i < 0) { i = 0; } else if (i > n - 1) { i = n - 1; }
		} else {
			i = (i + dir + n) % n;
		}
		vals[k] = i;
		acked[k] = false;
		return frames(row, row[5][i]);
	}

	function frames(row, v) {
		var kind = row[3];
		if (kind == :lens) { return [BLEBarrel.setSensorX5(v)]; }
		if (kind == :mute) { return [BLEBarrel.frameX5(0x07, [0x08, 0x0e, 0x12, 0x02, 0x70, v]b)]; }   // SET_OPTIONS MUTE
		if (kind == :lapse) { return [BLEBarrel.setLapseX5(row[4], v)]; }
		if (kind == :dur) { return [BLEBarrel.setLapseDurX5(row[4], v)]; }
		if (kind == :burst) {
			return [BLEBarrel.setPhotoOptX5(row[4], 44, v[0]), BLEBarrel.setPhotoOptX5(row[4], 51, v[1])];
		}
		if (kind == :ev) { v = (v >= 0) ? 2 * v : -2 * v - 1; }   // zig-zag sint32
		return [BLEBarrel.setPhotoOptX5(row[4], row[6], v)];
	}

	function clampFocus(id) {
		if (focus > rows(id).size()) { focus = 0; }
	}
}
