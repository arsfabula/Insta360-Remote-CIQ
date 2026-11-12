using Toybox.WatchUi;
using Toybox.Application;
using Toybox.Graphics as Gfx;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.BluetoothLowEnergy;
using Toybox.Math;
using Toybox.Lang;
using Toybox.Attention;
using BLEBarrel;

// High-level UI state, derived from the BLE module's globals.
enum {
	UI_SEARCHING,
	UI_NOT_FOUND,
	UI_READY,
	UI_STARTING,
	UI_RECORDING,
	UI_STOPPING,
	UI_BUSY
}

const C_BG = 0x000000;
const C_TEXT = 0xFFFFFF;
const C_DIM = 0xBFBFBF;
const C_MUTED = 0x8C8C8C;
const C_FOCUS_BG = 0x3A2A08;  // amber pill behind the focused settings row
const C_AMBER_DIM = 0x6B4A00;
const C_FAINT = 0x2A2A2A;
const C_BLUE = 0x3FA9F5;
const C_GREEN = 0x3DDC84;
const C_AMBER = 0xFFB020;
const C_RED = 0xFF3B30;
const C_BATT = 0x00E5FF;  // battery widget (bright cyan)
const C_CARD = 0xFF4FE0;  // storage widget (bright magenta)
const C_TOAST_BG = 0x8A1C14;  // toast pill (dark red, white text)

// Layout tokens for the two-column screens (fractions of the screen radius r, or pixels)
const L_ROW = 0.15;     // row pitch in the right column
const L_TITLE = 0.20;   // title band height
const L_PAD = 10;       // inner padding (also the pill's horizontal padding)
const L_GAP = 12;       // gap between a LABEL and its value
const T_TITLE_CAPS = true;  // mode / state titles in capitals

function uiState(dev) {
	// The state of this app is driven by the barrel: a message starting with "Scan" is the
	// barrel's own search (it rescans on its own, there is no not-found screen to answer),
	// a message starting with "Busy" is the camera's Busy answer. The record machine of the
	// barrel answers the rest, exactly as the old ViewData read it. dev stays in the
	// signature as the PR's call-site shape; nothing in this body reads it.
	var m = BLEBarrel.mMessage;
	if (m != null && m.length() >= 4 && m.substring(0, 4).equals("Scan")) { return UI_SEARCHING; }
	if (m != null && m.length() >= 4 && m.substring(0, 4).equals("Busy")) { return UI_BUSY; }
	var r = BLEBarrel.recState;
	if (r == BLEBarrel.stateStartRec) { return UI_RECORDING; }
	if (r == BLEBarrel.stateStarting) { return UI_STARTING; }
	if (r == BLEBarrel.stateStopping) { return UI_STOPPING; }
	return UI_READY;
}

// True when the link dropped while recording (e.g. underwater): the camera keeps going.
var recLinkLost = false;

// Short message drawn by RemoteView at the bottom of the screen, over the camera name.
// Not WatchUi.showToast: the native toast swallows the next button press (it only dismisses
// itself), so START to stop a recording right after "Highlight added" was lost. This one takes
// no input; every press acts at once.
const TOAST_MS = 3000;
var toastMsg = null;
var toastUntil = 0;

function toast(msg) {
	toastMsg = msg;
	toastUntil = System.getTimer() + TOAST_MS;
	WatchUi.requestUpdate();
}

function toastActive() {
	return toastMsg != null && System.getTimer() < toastUntil;
}

// [[intensity, ms], ...]
function vibe(pattern) {
	if (Attention has :vibrate) {
		var p = [];
		for (var i = 0; i < pattern.size(); i++) {
			p.add(new Attention.VibeProfile(pattern[i][0], pattern[i][1]));
		}
		Attention.vibrate(p);
	}
}

function cameraName() {
	var n = BLEBarrel.deviceName;
	if (n == null || n.equals("n/a")) { return "Insta360"; }
	return n;
}

class RemoteView extends WatchUi.View {
	hidden var dev;
	hidden var timer;
	hidden var tick = 0;
	hidden var lostTicks = 0;
	hidden var prevState = null;
	hidden var stateTicks = 0;

	function initialize(device) {
		View.initialize();
		dev = device;
		timer = new Timer.Timer();
	}

	function onShow() {
		timer.start(method(:onTick), 125, true);
	}

	function onHide() {
		timer.stop();
	}

	hidden var lastAuth = -1;
	hidden var lastPower = null;  // null unknown, true USB, false battery
	hidden var lastLow = false;
	hidden var lastCard = null;

	function onTick() as Void {
		tick++;
		if (toastMsg != null && !toastActive()) { toastMsg = null; WatchUi.requestUpdate(); }
		mainApp.gpsSync();
		var s = uiState(dev);
		onTransition(s);
		var r = dev.photoResultTaken();
		if (r != null) {
			if (r == :ok) {
				var t = System.getClockTime();
				toast("Photo " + t.hour.format("%02d") + ":" + t.min.format("%02d") + ":" + t.sec.format("%02d"));
			} else {
				toast(r == :noShot ? "No photo taken" : "Photo rejected");
			}
			vibe(r == :ok ? [[100, 120]] : [[80, 300]]);
		}
		// X5 status pushes (0x2003 power, 0x2004 low battery, 0x2006 card): announce changes.
		// The mainline barrel decodes these into its own fields, read through the peek accessors.
		var pw = dev.peekBatteryArrived() ? (dev.peekBatteryPowerType() == 1) : null;
		if (pw != null && pw != lastPower) {
			toast(pw ? "Camera charging" : "Camera on battery"); // pushed only on plug / unplug
			lastPower = pw;
		}
		var sr = dev.settingResultTaken();
		if (sr == :rejected) { toast("Setting rejected"); vibe([[80, 300]]); }
		if (dev.peekBatteryLow() && !lastLow) { toast("Camera battery low"); vibe([[80, 300], [0, 150], [80, 300]]); }
		lastLow = dev.peekBatteryLow();
		var cd = dev.peekStorageState();
		if (cd != null && cd != lastCard) {
			if (cd == 1) { toast("No SD card"); vibe([[80, 300]]); }
			else if (cd == 2) { toast("SD card full"); vibe([[80, 300]]); }
			else if (cd >= 3) { toast("SD card error"); vibe([[80, 300]]); }
			else if (lastCard != null) { toast("SD card OK"); }
			lastCard = cd;
		}
		// Animate while searching or in transition; otherwise redraw once a second.
		if (s == UI_SEARCHING || s == UI_STARTING || s == UI_STOPPING || (s == UI_RECORDING && tick % 4 == 0) || tick % 8 == 0) {
			WatchUi.requestUpdate();
		}
	}

	// State-change side effects: native toasts + vibes on connect/disconnect,
	// and a timeout so a start/stop the camera never confirms can't hang the UI.
	hidden function onTransition(s) {
		if (s != prevState) {
			var was = prevState;
			prevState = s;
			stateTicks = 0;
			if (s == UI_READY) { recLinkLost = false; }
			if (was == null) { return; }
			var linked = (s == UI_READY || s == UI_RECORDING || s == UI_BUSY);
			var wasLinked = (was == UI_READY || was == UI_RECORDING || was == UI_BUSY ||
				was == UI_STARTING || was == UI_STOPPING);
			if (linked && (was == UI_SEARCHING || was == UI_NOT_FOUND)) {
				toast("Connected");
				vibe([[50, 60], [0, 80], [50, 60]]);
			} else if (!linked && wasLinked && (s == UI_SEARCHING || s == UI_NOT_FOUND)) {
				if (was == UI_RECORDING || recLinkLost) {
					recLinkLost = true;
					toast("Link lost");
				} else {
					toast("Link lost");
				}
				vibe([[80, 300]]);
			} else if (s == UI_RECORDING && was == UI_STARTING) {
				vibe([[100, 200]]);
			} else if (s == UI_READY && was == UI_STOPPING) {
				recLinkLost = false;
				vibe([[100, 120], [0, 100], [100, 120]]);
			}
			return;
		}
		stateTicks++;
		// photos are processed in-camera before the reply: allow 20 s, otherwise 6 s
		// a pending photo waits for the camera's own answer (it arrives when the file is saved);
		// 60 s is only a safety net
		// Every mode waits for the camera. On the X5 we also ask it what it is doing every 2 s,
		// so a missing ack never leaves the watch guessing. 60 s only guards a dead link.
		var limit = BLEBarrel.menuLevel >= 2 ? 480 : 48;
		if ((s == UI_STARTING || s == UI_STOPPING) && stateTicks >= limit) {
			// 6 s without confirmation from the camera
			BLEBarrel.recState = (s == UI_STARTING) ? BLEBarrel.stateStopRec : BLEBarrel.stateStartRec;
			toast("No response");
			vibe([[80, 300]]);
		}
	}

	function onUpdate(dc) {
		var w = dc.getWidth();
		var h = dc.getHeight();
		var cx = w / 2;
		var cy = h / 2;
		var r = (w < h ? w : h) / 2;
		var s = uiState(dev);

		if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
		dc.setColor(C_BG, C_BG);
		dc.clear();

		drawRing(dc, cx, cy, r - 10, s);
		if (s != UI_SEARCHING) { drawWidgets(dc, cx, cy, r - 10); }
		if (BLEBarrel.GPSon && BLEBarrel.menuLevel < 2) { drawGps(dc, cx, cy, r - 10); }

		var inner = r - 28; // usable radius inside the ring
		var rr = r - 10;    // ring radius

		// Every state uses the same two columns: an icon on the left, a title and LABEL value rows
		// on the right. Only the ready state has focusable settings rows.
		var hero = :mode;        // :mode (current mode icon), :cam, :camOff, :busy
		var heroColor = C_TEXT;
		var title = BLEBarrel.currentLabel;
		var titleColor = C_TEXT;
		var timer = false;       // title is the recording timer (number font)
		var info = [];           // [label, value, colour] rows (not focusable)
		var startCue = null;     // colour of the START dot at 2 o'clock, null = no action
		var setRows = null;      // ready state: focusable settings rows
		var stillRec = recLinkLost ? ["", "camera still recording", C_RED] : null;
		switch (s) {
			case UI_SEARCHING:
				hero = :cam; heroColor = C_BLUE;
			title = "Searching";
			info.add(["", "Wake the camera", C_DIM]);
				if (stillRec != null) { info.add(stillRec); }
				break;
			case UI_NOT_FOUND:
				hero = :camOff; heroColor = C_MUTED;
				title = "No camera";
				info.add(["START", "Retry now", C_TEXT]);
				info.add(["", "retrying\u2026", C_MUTED]);
				if (stillRec != null) { info.add(stillRec); }
				startCue = C_TEXT;
				break;
			case UI_STARTING:
				heroColor = C_AMBER; titleColor = C_AMBER;
			title = BLEBarrel.videoMode ? "Starting" : "Shooting";
				info.add(["", BLEBarrel.currentLabel, C_DIM]);
				break;
			case UI_STOPPING:
				heroColor = C_AMBER; titleColor = C_AMBER;
				title = "Stopping";
				info.add(["", BLEBarrel.currentLabel, C_DIM]);
				break;
			case UI_BUSY:
				hero = :busy; heroColor = C_AMBER; titleColor = C_AMBER;
				title = "Camera busy";
				info.add(["START", "Retry", C_TEXT]);
				info.add(["", "or wait", C_MUTED]);
				startCue = C_TEXT;
				break;
			case UI_RECORDING:
				heroColor = C_RED; titleColor = C_RED;
				title = elapsed(); timer = true;
				info.add(["", BLEBarrel.currentLabel, C_DIM]);
				startCue = C_TEXT;
				break;
			default:
			startCue = inSettingsUI() ? null : (BLEBarrel.videoMode ? C_RED : C_TEXT);
			setRows = Settings.rows(currentModeId);
			Settings.clampFocus(currentModeId);
		}

		// Bottom: camera name along the ring (muted placeholder until we know which camera)
		var known = !(s == UI_NOT_FOUND || s == UI_SEARCHING);
		var dots = (s == UI_READY);

		// Icon + column as one group, centred in the free width between the mode dots and the
		// ring. Ready screens use fixed slots measured over all modes (see readyColW): the
		// content changes, the positions do not.
		var rows = [];
		var titleFocused = false;
		if (dots) {
			var id = currentModeId;
			for (var i = 0; i < setRows.size(); i++) {
				var focused = Settings.focus == i + 1;
				var c = focused ? C_AMBER : ((setRows[i][3] == :exit || setRows[i][3] == :power || Settings.isAcked(id, setRows[i])) ? C_TEXT : C_DIM);
				rows.add([setRows[i][1], Settings.label(id, setRows[i]), c, focused, setRows[i][2]]);
			}
			titleFocused = Settings.focus == 0;
			titleColor = titleFocused ? C_AMBER : C_TEXT;
		} else {
			for (var i = 0; i < info.size(); i++) { rows.add([info[i][0], info[i][1], info[i][2], false, null]); }
		}
		var isz = (r * 0.165).toNumber();
		var iconW = isz * 2.1;
		var gap = r * 0.12;
		var areaL = cx - r * (dots ? 0.76 : 0.84);
		var areaR = cx + r * 0.86;
		var colMax = areaR - areaL - iconW - gap;
		// the title sits above centre where the round screen is narrower; keep it clear of the
		// shutter cue (~0.68 r right of centre)
		titleMax = (cx + r * 0.62) - (areaL + iconW + gap) - L_PAD;
		// ready screens: one fixed column width (widest mode) so nothing moves between modes
		var colW = dots ? readyColW(dc, r, colMax) : columnWidth(dc, r, title, timer, rows, colMax);
		var left0 = (areaL + areaR) / 2 - (iconW + gap + colW) / 2;
		if (left0 > areaL) { titleMax -= (left0 - areaL); }
		var left = (areaL + areaR) / 2 - (iconW + gap + colW) / 2;
		if (left < areaL) { left = areaL; }
		var ix = left + iconW / 2;
		// camera name on the group's vertical axis
		drawNameArc(dc, cx, cy, rr, known ? cameraName() : "Insta360", known ? C_DIM : C_MUTED, dots,
			left + (iconW + gap + colW) / 2);
		var x0 = left + iconW + gap - L_PAD;
		if (hero == :mode) {
			ModeIcons.draw(dc, ix, cy, isz, BLEBarrel.currentLabel, heroColor);
		} else {
			ModeIcons.stateIcon(dc, ix, cy, isz, hero, heroColor);
		}
		if (dots) {
			drawModeDots(dc, cx, cy, rr);
			if (setRows.size() > 0) { drawBackCue(dc, cx, cy, rr); }
		}
		drawColumn(dc, x0, cy, x0 + L_PAD + colMax, r, title, titleColor, titleFocused, timer, rows, dots,
			dots ? readyRows : rows.size());
		if (s == UI_RECORDING) {
			drawKeyGlyph(dc, cx, cy, rr, 180, :flag);    // UP = highlight
			drawKeyGlyph(dc, cx, cy, rr, 209, :target);  // DOWN = Track That
		}
		if (startCue != null) {
			drawStartCue(dc, cx, cy, rr, startCue, s == UI_RECORDING);
		}
		if (toastActive()) { drawToast(dc, cx, cy, rr); }
	}

	// Toast pill in the free band above the camera name: the title, the START cue, the name and the top arcs
	// stay visible.
	hidden function drawToast(dc, cx, cy, rr) {
		var f = (nameFont != null) ? nameFont : Gfx.FONT_XTINY;
		var tw = dc.getTextWidthInPixels(toastMsg, f);
		var th = dc.getFontHeight(f);
		var y = cy + rr * 0.58;   // between the last settings row and the camera name
		var w = tw + 2 * L_PAD + 8;
		var h = th + 8;
		var maxW = 2 * Math.sqrt(rr * rr - (y + h / 2 - cy) * (y + h / 2 - cy)) - 8;
		if (w > maxW) { w = maxW; }
		dc.setColor(C_TOAST_BG, Gfx.COLOR_TRANSPARENT);
		dc.fillRoundedRectangle(cx - w / 2, y - h / 2, w, h, h / 2);
		dc.setColor(C_TEXT, Gfx.COLOR_TRANSPARENT);
		dc.drawText(cx, y, f, toastMsg, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
	}


	// Small glyph beside a side button (UP 180°, DOWN 209°) while recording.
	hidden function drawKeyGlyph(dc, cx, cy, rr, deg, kind) {
		var a = Math.toRadians(deg);
		var px = cx + Math.cos(a) * (rr - 30);
		var py = cy - Math.sin(a) * (rr - 30);
		var k = rr * 0.055;
		dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
		if (kind == :flag) {
			dc.setPenWidth(3);
			dc.drawLine(px - k * 0.6, py + k, px - k * 0.6, py - k);
			dc.fillPolygon([[px - k * 0.6, py - k], [px + k * 0.9, py - k * 0.5], [px - k * 0.6, py]]);
		} else {
			dc.setPenWidth(3);
			dc.drawCircle(px, py, k * 0.85);
			dc.fillCircle(px, py, k * 0.3);
			dc.drawLine(px - k * 1.2, py, px - k * 0.55, py);
			dc.drawLine(px + k * 0.55, py, px + k * 1.2, py);
			dc.drawLine(px, py - k * 1.2, px, py - k * 0.55);
			dc.drawLine(px, py + k * 0.55, px, py + k * 1.2);
		}
		dc.setPenWidth(1);
	}


	// Title lines: one word per row (bottom-aligned: the title grows upwards, the rows stay put).
	hidden function titleLines(dc, title, timer, maxW) {
		fontsReady(dc);
		if (timer) {
			var tfs = [Gfx.FONT_NUMBER_MEDIUM, Gfx.FONT_NUMBER_MILD, Gfx.FONT_MEDIUM];
			for (var i = 0; i < tfs.size(); i++) {
				if (dc.getTextWidthInPixels(title, tfs[i]) <= maxW || i == tfs.size() - 1) { return [tfs[i], [title]]; }
			}
		}
		// one word per row, the largest size where every word fits
		var t = T_TITLE_CAPS ? title.toUpper() : title;
		var words = [];
		var rest = t;
		var sp = rest.find(" ");
		while (sp != null) {
			if (sp > 0) { words.add(rest.substring(0, sp)); }
			rest = rest.substring(sp + 1, rest.length());
			sp = rest.find(" ");
		}
		if (rest.length() > 0) { words.add(rest); }
		for (var i = 0; i < titleFonts.size(); i++) {
			var ok = true;
			for (var k = 0; k < words.size(); k++) {
				if (dc.getTextWidthInPixels(words[k], titleFonts[i]) > maxW) { ok = false; break; }
			}
			if (ok) { return [titleFonts[i], words]; }
		}
		return [titleFonts[titleFonts.size() - 1], words];
	}

	hidden function fontsReady(dc) {
		if (colFonts == null) {
			colFonts = scaledFonts(dc, [Gfx.FONT_SMALL, Gfx.FONT_TINY, Gfx.FONT_XTINY], 0.9);
			labelFont = scaledFonts(dc, [Gfx.FONT_XTINY], 0.72)[0];
			titleFonts = scaledFonts(dc, [Gfx.FONT_MEDIUM, Gfx.FONT_SMALL, Gfx.FONT_TINY], (T_TITLE_CAPS ? 0.92 : 1.0) * 0.85);
		}
	}

	// Widest line of the column: title lines and LABEL + widest value of each row.
	hidden function columnWidth(dc, r, title, timer, rows, maxW) {
		var tl = titleLines(dc, title, timer, titleMax - L_PAD);
		var w = 0;
		for (var i = 0; i < tl[1].size(); i++) {
			var x = dc.getTextWidthInPixels(tl[1][i], tl[0]);
			if (x > w) { w = x; }
		}
		var lw = 0;
		for (var i = 0; i < rows.size(); i++) {
			var x = dc.getTextWidthInPixels(rows[i][0], labelFont);
			if (x > lw) { lw = x; }
		}
		for (var i = 0; i < rows.size(); i++) {
			var vals = (rows[i][4] != null) ? rows[i][4] : [rows[i][1]];
			var vw = 0;
			for (var k = 0; k < vals.size(); k++) {
				var x = dc.getTextWidthInPixels(vals[k], colFonts[1]);
				if (x > vw) { vw = x; }
			}
			var x = (rows[i][0].length() > 0 ? lw + L_GAP : 0) + vw;
			if (x > w) { w = x; }
		}
		return (w < maxW) ? w : maxW;
	}

	// The one right-column component every screen uses.
	//   title      big, bottom-aligned, one or two lines (number font for the recording timer)
	//   rows       [LABEL, value, value colour, focused, all choices or null]: label as a small
	//              superscript in C_MUTED, values aligned; a row without a label starts at the edge
	//   hits       record the row centres for touch focus (settings only)
	hidden function drawColumn(dc, x0, ym, xMax, r, title, titleColor, titleFocused, timer, rows, hits, nLayout) {
		fontsReady(dc);
		var lf = labelFont;
		var vf = colFonts[1];
		var jv = Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER;
		var tl = titleLines(dc, title, timer, titleMax);
		var tf = tl[0];
		var lines = tl[1];
		var lineH = dc.getFontHeight(tf) * (timer ? 0.9 : 0.86);
		var rowH = r * L_ROW;
		var titleH = lines.size() * lineH + r * 0.03;
		// centre the block on ym, counting a one-line title (so rows do not jump for two lines)
		var oneH = lineH + r * 0.03;
		// fixed slots: the title's bottom and the first row do not depend on this screen's content
		var top = ym - (oneH + nLayout * rowH) / 2;
		var titleBottom = top + oneH;
		var y0 = titleBottom - titleH + lineH / 2;   // first title line centre

		if (hits) {
			// the title's tap area is its full drawn height (one or more lines), not one row
			Settings.hitX0 = x0; Settings.hitH = rowH;
			Settings.hitYs = [titleBottom - titleH / 2]; Settings.hitHs = [titleH];
		}
		if (titleFocused) {
			var tw = 0;
			for (var i = 0; i < lines.size(); i++) {
				var w = dc.getTextWidthInPixels(lines[i], tf);
				if (w > tw) { tw = w; }
			}
			dc.setColor(C_FOCUS_BG, Gfx.COLOR_TRANSPARENT);
			var ph = lines.size() * lineH + 4;
			dc.fillRoundedRectangle(x0, y0 - lineH / 2 - 2, tw + 2 * L_PAD, ph, lines.size() > 1 ? 14 : ph / 2);
		}
		dc.setColor(titleColor, Gfx.COLOR_TRANSPARENT);
		for (var i = 0; i < lines.size(); i++) {
			dc.drawText(x0 + L_PAD, y0 + i * lineH, tf, lines[i], jv);
		}
		var y = titleBottom + rowH / 2;

		var lw = 0;
		for (var i = 0; i < rows.size(); i++) {
			var w = dc.getTextWidthInPixels(rows[i][0], lf);
			if (w > lw) { lw = w; }
		}
		var vx = x0 + L_PAD + lw + L_GAP;
		for (var i = 0; i < rows.size(); i++) {
			var label = rows[i][0];
			var v = rows[i][1];
			var focused = rows[i][3];
			var x = (label.length() > 0) ? vx : x0 + L_PAD;
			var f = vf;
			if (x + dc.getTextWidthInPixels(v, f) > xMax) { f = colFonts[2]; }
			if (hits) { Settings.hitYs.add(y); Settings.hitHs.add(rowH); }
			if (focused) { pill(dc, x0, y, x - x0 + dc.getTextWidthInPixels(v, f) + L_PAD, rowH - 4); }
			if (label.length() > 0) {
				// superscript: the label's top aligned with the value's top
				var ly = y - (dc.getFontHeight(f) - dc.getFontHeight(lf)) / 2 + 2;
				dc.setColor(focused ? C_AMBER : C_MUTED, Gfx.COLOR_TRANSPARENT);
				dc.drawText(x0 + L_PAD, ly, lf, label, jv);
			}
			dc.setColor(rows[i][2], Gfx.COLOR_TRANSPARENT);
			dc.drawText(x, y, f, v, jv);
			y += rowH;
		}
	}

	// Vector fonts at `scale` of each system font's size (matched by text width); system fonts
	// where vector fonts are unavailable.
	hidden var colFonts = null;
	hidden var labelFont = null;
	hidden var titleFonts = null;
	hidden var titleMax = 0;
	hidden var readyW = null;
	hidden var readyRows = 1;

	// Widest column over every mode (title words + every choice of every row), and the most rows
	// any mode has. Measured once: the ready layout is the same for every mode.
	hidden function readyColW(dc, r, colMax) {
		if (readyW != null) { return readyW; }
		var w = 0;
		var items = modeList();
		for (var m = 0; m < items.size(); m++) {
			var srows = Settings.rows(items[m][1]);
			var rows = [];
			for (var i = 0; i < srows.size(); i++) { rows.add([srows[i][1], srows[i][2][0], 0, false, srows[i][2]]); }
			if (srows.size() > readyRows) { readyRows = srows.size(); }
			var x = columnWidth(dc, r, items[m][0], false, rows, colMax);
			if (x > w) { w = x; }
		}
		readyW = w;
		return w;
	}
	hidden function scaledFonts(dc, sys, scale) {
		if (!(Gfx has :getVectorFont)) { return sys; }
		var out = [];
		var probe = "Photo Interval 72MP";
		for (var i = 0; i < sys.size(); i++) {
			var target = dc.getTextWidthInPixels(probe, sys[i]) * scale;
			var lo = 8; var hi = 80; var best = null;
			while (lo <= hi) {
				var mid = (lo + hi) / 2;
				var vf = Gfx.getVectorFont({:face => ["RobotoCondensedBold", "RobotoCondensedRegular"], :size => mid});
				if (vf == null) { break; }
				if (dc.getTextWidthInPixels(probe, vf) <= target) { best = vf; lo = mid + 1; } else { hi = mid - 1; }
			}
			out.add(best != null ? best : sys[i]);
		}
		return out;
	}

	hidden function pill(dc, x, y, w, h) {
		dc.setColor(C_FOCUS_BG, Gfx.COLOR_TRANSPARENT);
		dc.fillRoundedRectangle(x, y - h / 2, w, h, h / 2);
	}


	// START button sits at 2 o'clock: mark it on the ring (filled square = stop, dot = go).
	hidden function drawStartCue(dc, cx, cy, rr, color, isStop) {
		var a = Math.toRadians(30);
		var px = cx + Math.cos(a) * (rr - 26);
		var py = cy - Math.sin(a) * (rr - 26);
		var k = rr * 0.05;
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		if (isStop) {
			dc.fillRectangle(px - k, py - k, 2 * k, 2 * k);
		} else {
			dc.fillCircle(px, py, k);
		}
	}

	// Camera name set along the bottom of the ring, upright. With the mode dots and the gear on
	// screen it sits on the icon + text group's vertical axis, kept clear of the last dot and the gear.
	hidden var nameFont = null;
	hidden function drawNameArc(dc, cx, cy, rr, text, color, withDots, gx) {
		var rad = rr - 28;
		// centred under the icon + text group: the angle whose x on the arc is the group centre
		var dx = (gx - cx) / rad;
		if (dx > 0.9) { dx = 0.9; } else if (dx < -0.9) { dx = -0.9; }
		var deg = 270.0 + Math.toDegrees(Math.asin(dx));
		if (withDots) {
			// stay clear of the mode dots and the gear
			var n = modeList().size();
			var step = n > 12 ? 6.0 : 8.0;
			var lastDot = 194.5 + (n - 1) / 2.0 * step + 3;
			if (deg < lastDot + 22) { deg = lastDot + 22; }
			if (deg > 324 - 22) { deg = 324 - 22; }
		}
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		if (dc has :drawRadialText) {
			if (nameFont == null && (Gfx has :getVectorFont)) {
				nameFont = Gfx.getVectorFont({:face => ["RobotoCondensedBold", "RobotoCondensedRegular"], :size => 26});
			}
			if (nameFont != null) {
				dc.drawRadialText(cx, cy, nameFont, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER,
					deg, rad, Gfx.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
				return;
			}
		}
		var a = Math.toRadians(deg);
		dc.drawText(cx + Math.cos(a) * rad, cy - Math.sin(a) * rad, Gfx.FONT_XTINY, text,
			Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
	}

	// Gear beside the BACK button (about 330°): BACK moves the settings focus. Amber while a
	// settings row has the focus.
	hidden function drawBackCue(dc, cx, cy, rr) {
		var a = Math.toRadians(-30);
		var px = cx + Math.cos(a) * (rr - 30);
		var py = cy - Math.sin(a) * (rr - 30);
		ModeIcons.gear(dc, px, py, rr * 0.065, Settings.focus > 0 ? C_AMBER : C_DIM);
	}

	// Page-indicator dots along the left edge, centred between UP (180°) and DOWN (209°):
	// one per mode, current one filled. UP moves up the column, DOWN moves down.
	hidden function drawModeDots(dc, cx, cy, rr) {
		var items = modeList();
		var n = items.size();
		if (n < 2) { return; }
		var cur = 0;
		for (var i = 0; i < n; i++) {
			if (items[i][0].equals(BLEBarrel.currentLabel)) { cur = i; break; }
		}
		var step = n > 12 ? 6.0 : 8.0;      // degrees between dots
		var mid = 194.5;
		var rad = rr - 26;
		for (var i = 0; i < n; i++) {
			var a = Math.toRadians(mid - ((n - 1) / 2.0 - i) * step);
			var px = cx + Math.cos(a) * rad;
			var py = cy - Math.sin(a) * rad;
			if (i == cur) {
				dc.setColor(C_AMBER, Gfx.COLOR_TRANSPARENT);
				dc.fillCircle(px, py, rr * 0.03);
			} else {
				dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
				dc.fillCircle(px, py, rr * 0.018);
			}
		}
	}


	// Draw text centred at y using the first font that fits the circle's chord at that height.
	// If even the smallest font is too wide, trim with an ellipsis.
	hidden function fitText(dc, cx, cy, rad, y, text, fonts, color) {
		if (text == null || text.length() == 0) { return; }
		var font = fonts[fonts.size() - 1];
		var maxW = 0;
		for (var i = 0; i < fonts.size(); i++) {
			var hh = dc.getFontHeight(fonts[i]) / 2;
			var dy = (y - cy).abs() + hh;
			maxW = (dy >= rad) ? 0 : (2 * Math.sqrt(rad * rad - dy * dy) - 8).toNumber();
			font = fonts[i];
			if (dc.getTextWidthInPixels(text, font) <= maxW) { break; }
		}
		var t = text;
		while (t.length() > 1 && dc.getTextWidthInPixels(t, font) > maxW) {
			t = t.substring(0, t.length() - 2) + "…";
		}
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.drawText(cx, y, font, t, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
	}

	hidden function drawRing(dc, cx, cy, rr, s) {
		dc.setPenWidth(4);
		dc.setColor(C_FAINT, Gfx.COLOR_TRANSPARENT);
		dc.drawCircle(cx, cy, rr);

		if (s == UI_SEARCHING) {
			var a = 90 - (tick * 12) % 360;
			dc.setColor(C_BLUE, Gfx.COLOR_TRANSPARENT);
			dc.drawArc(cx, cy, rr, Gfx.ARC_CLOCKWISE, a, a - 70);
		} else if (s == UI_NOT_FOUND) {
			dc.setColor(C_AMBER_DIM, Gfx.COLOR_TRANSPARENT);
			dc.drawCircle(cx, cy, rr);
		} else if (s == UI_READY) {
			dc.setColor(C_GREEN, Gfx.COLOR_TRANSPARENT);
			dc.drawCircle(cx, cy, rr);
		} else if (s == UI_RECORDING) {
			// pulsing width, so "recording" never depends on red vs green alone
			dc.setPenWidth((tick / 4) % 2 == 0 ? 8 : 4);
			dc.setColor(C_RED, Gfx.COLOR_TRANSPARENT);
			dc.drawCircle(cx, cy, rr);
		} else if (s == UI_BUSY) {
			dc.setColor(C_AMBER, Gfx.COLOR_TRANSPARENT); // static: a stuck camera must not look like progress
			dc.drawCircle(cx, cy, rr);
		} else if (s == UI_STARTING || s == UI_STOPPING) {
			var b = 90 - (tick * 20) % 360;
			dc.setColor(C_AMBER, Gfx.COLOR_TRANSPARENT);
			dc.drawArc(cx, cy, rr, Gfx.ARC_CLOCKWISE, b, b - 120);
		}
		dc.setPenWidth(1);
	}

	// Outer widget ring, top half: battery arc on the upper right (85..50 deg),
	// card / remaining arc on the upper left (95..130 deg). Track + fill + small value label.
	hidden function drawWidgets(dc, cx, cy, rr) {
		var gr = rr - 17;
		// battery
		// Over Connect IQ the level never arrives (cut at 20 bytes); the power source and the
		// low-battery alarm do. Show the level when known, else USB / BAT / LOW.
		var b = dev.peekBatteryLevel();
		var bc = C_BATT;
		var bt = "--";
		if (b != null) {
			if (b <= 15) { bc = C_RED; } else if (b <= 30) { bc = C_AMBER; }
			bt = b + "%";
		}
		var pwKnown = dev.peekBatteryArrived();
		if (pwKnown) {
			if (dev.peekBatteryPowerType() == 1) { bc = C_GREEN; if (b == null) { bt = "USB"; } }
			else if (b == null) { bt = "BAT"; }
		}
		if (dev.peekBatteryLow() && !(pwKnown && dev.peekBatteryPowerType() == 1)) {
			bc = C_RED;
			if (b == null) { bt = "LOW"; }
		}
		var bf = (b != null) ? b / 100.0 : ((bc == C_RED) ? 0.1 : null);
		gauge(dc, cx, cy, gr, 85, 50, bf, bc);
		label(dc, cx, cy, gr - 20, 67, bt, bc, :battery, bf == null ? 0.0 : bf);

		// storage: only when the camera ever reported it (its replies are cut at 20 bytes over Connect IQ)
		var card = dev.peekStorageState();
		var freeB = dev.peekStorageFreeBytes();
		if (card == null && freeB == null) {
			return;
		}
		var frac = null;
		var sc = C_CARD;
		var txt = "--";
		if (card != null && card != 0) {
			sc = C_RED;
			txt = (card == 1) ? "NO SD" : (card == 2) ? "FULL" : "SD ERR";
			frac = 0.0;
		} else if (freeB != null) {
			// the total never crosses the 20-octet ceiling: no fraction, the free figure answers for itself
			txt = ((freeB as Lang.Number).toFloat() / 1073741824.0).format("%.1f") + "G";
		} else if (card == 0) {
			txt = "SD";   // card present and writable; sizes do not reach the watch
		}
		if (frac != null && frac < 0.1) { sc = C_AMBER; }
		gauge(dc, cx, cy, gr, 95, 130, frac, sc);
		label(dc, cx, cy, gr - 20, 113, txt, sc, :card, 0.0);
	}

	// Arc from a0 towards a1 (degrees, either direction); fill = fraction or null for unknown.
	hidden function gauge(dc, cx, cy, gr, a0, a1, fill, color) {
		var dir = (a1 < a0) ? Gfx.ARC_CLOCKWISE : Gfx.ARC_COUNTER_CLOCKWISE;
		dc.setPenWidth(8);
		dc.setColor(C_FAINT, Gfx.COLOR_TRANSPARENT);
		dc.drawArc(cx, cy, gr, dir, a0, a1);
		if (fill != null && fill > 0.01) {
			if (fill > 1.0) { fill = 1.0; }
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			dc.drawArc(cx, cy, gr, dir, a0, a0 + (a1 - a0) * fill);
		}
		dc.setPenWidth(1);
	}

	// Value with a small leading glyph (battery or SD card), set along the ring's curve.
	// Text runs clockwise (left to right across the top); the glyph leads at the higher angle.
	hidden var arcFont = null;

	hidden function label(dc, cx, cy, rad, deg, text, color, glyph, level) {
		var gw = 20;
		var gap = 6;
		var radial = (dc has :drawRadialText);
		if (radial && arcFont == null) {
			// the vector face exists only from API 4.1: on a target without it the arc answers
			// with the system font, the same fallback the size ladder of arcFontSafe uses.
			arcFont = (Gfx has :getVectorFont) ? Gfx.getVectorFont({:face => ["RobotoCondensedBold", "RobotoCondensedRegular"], :size => 26}) : null;
			if (arcFont == null) { radial = false; }
		}
		var f = radial ? arcFont : Gfx.FONT_XTINY;
		var tw = dc.getTextWidthInPixels(text, f);
		var k = 180.0 / (Math.PI * rad);                // degrees per pixel at this radius
		var span = (gw + gap + tw) * k;
		var gDeg = deg + span / 2 - (gw / 2.0) * k;
		var tDeg = deg - span / 2 + (tw / 2.0) * k;

		// glyph drawn in local (u along the text, v outward) coordinates, rotated onto the curve
		var ga = Math.toRadians(gDeg);
		var gx = cx + Math.cos(ga) * rad;
		var gy = cy - Math.sin(ga) * rad;
		var tu = [Math.sin(ga), Math.cos(ga)];    // reading direction
		var tv = [Math.cos(ga), -Math.sin(ga)];   // outward
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.setPenWidth(2);
		if (glyph == :battery) {
			outline(dc, gx, gy, tu, tv, [[-9, -5], [6, -5], [6, 5], [-9, 5]]);
			dc.fillPolygon(xf(gx, gy, tu, tv, [[6, -2], [9, -2], [9, 2], [6, 2]]));
			var fw = 11.0 * level;
			if (fw > 0.5) { dc.fillPolygon(xf(gx, gy, tu, tv, [[-7, -3], [-7 + fw, -3], [-7 + fw, 3], [-7, 3]])); }
			if (dev.peekBatteryPowerType() == 1) {
				dc.setColor(C_BG, Gfx.COLOR_TRANSPARENT);
				dc.fillPolygon(xf(gx, gy, tu, tv, [[0, 4], [-3, -1], [0, -1], [-1, -4], [3, 1], [0, 1]]));
			}
		} else {
			outline(dc, gx, gy, tu, tv, [[-5, -7], [-5, 7], [2, 7], [5, 4], [5, -7]]);
		}
		dc.setPenWidth(1);
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);

		if (radial) {
			dc.drawRadialText(cx, cy, f, text, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER,
				tDeg, rad, Gfx.RADIAL_TEXT_DIRECTION_CLOCKWISE);
		} else {
			var ta = Math.toRadians(tDeg);
			dc.drawText(cx + Math.cos(ta) * rad, cy - Math.sin(ta) * rad, f, text,
				Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
		}
	}

	hidden function xf(x, y, tu, tv, pts) {
		var out = [];
		for (var i = 0; i < pts.size(); i++) {
			var u = pts[i][0]; var w = pts[i][1];
			out.add([x + u * tu[0] + w * tv[0], y + u * tu[1] + w * tv[1]]);
		}
		return out;
	}

	hidden function outline(dc, x, y, tu, tv, pts) {
		var p = xf(x, y, tu, tv, pts);
		for (var i = 0; i < p.size(); i++) {
			var q = p[(i + 1) % p.size()];
			dc.drawLine(p[i][0], p[i][1], q[0], q[1]);
		}
	}

	hidden function drawGps(dc, cx, cy, rr) {
		var q = BLEBarrel.GPSaccuracy;
		var c = C_DIM;
		if (q == Position.QUALITY_POOR) { c = C_AMBER; }
		else if (q == Position.QUALITY_USABLE || q == Position.QUALITY_GOOD) { c = C_GREEN; }
		dc.setColor(c, Gfx.COLOR_TRANSPARENT);
		dc.drawText(cx, cy + rr * 0.78, Gfx.FONT_XTINY, "GPS", Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
	}

	hidden function elapsed() {
		var secs = Time.now().subtract(BLEBarrel.startRecTime).value();
		var hh = secs / 3600;
		var mm = (secs % 3600) / 60;
		var ss = secs % 60;
		if (hh > 0) {
			return hh + ":" + mm.format("%02d") + ":" + ss.format("%02d");
		}
		return mm.format("%02d") + ":" + ss.format("%02d");
	}
}
