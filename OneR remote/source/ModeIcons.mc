using Toybox.Graphics as Gfx;
using Toybox.Math;
using BLEBarrel;

// Mode icons drawn with primitives so they scale to any screen. The X5 modes follow the
// camera's own on-screen glyphs (solid shapes with cut-outs); s = icon half-size in pixels,
// (x, y) = centre. Cut-outs use the background colour (black).
module ModeIcons {

	// The camera's icons are two-tone: main glyph in the full colour, secondary parts (rings,
	// back frames, small stars, badges) in a dimmer shade of it.
	function shade(c) {
		var r = ((c >> 16) & 0xff) * 55 / 100;
		var g = ((c >> 8) & 0xff) * 55 / 100;
		var b = (c & 0xff) * 55 / 100;
		return (r << 16) | (g << 8) | b;
	}

	function kindFor(label) {
		if (label == null) { return :video; }
		if (label.equals("Settings")) { return :settings; }
		if (label.find("Star") != null || label.find("Night") != null) { return :star; }
		if (label.find("Burst") != null) { return :burst; }
		if (label.find("Interval") != null) { return :interval; }
		if (label.find("Photo HDR") != null) { return :photoHdr; }
		if (label.find("Photo") != null) { return :photo; }
		if (label.find("Pure") != null) { return :pure; }
		if (label.find("Loop") != null) { return :loop; }
		if (label.find("Road") != null) { return :road; }
		if (label.find("TimeShift") != null) { return :timeshift; }
		if (label.find("HDR") != null) { return :videoHdr; }
		if (label.find("Timelapse") != null || label.find("TimeLapse") != null) { return :timelapse; }
		if (label.find("Bullet") != null) { return :bullet; }
		return :video;
	}

	// Resolution tag for legacy video modes ("5.7K", "8K", "4K"), else null.
	function resTag(label) {
		if (label == null) { return null; }
		var i = label.find(" / ");
		if (i != null && label.find("K") != null) { return label.substring(0, i); }
		return null;
	}

	function draw(dc, x, y, s, label, color) {
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.setPenWidth(5);
		var k = kindFor(label);
		if (k == :settings) { gear(dc, x, y, s * 0.95, color); return; }
		if (k == :video || k == :videoHdr || k == :pure || k == :loop) {
			videoCam(dc, x, y, s, color, (k == :videoHdr) ? "HDR" : resTag(label));
			// glyph on the body (body centre is left of x)
			var bx = x - s * 0.3;
			dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
			if (k == :pure) {
				sparkle(dc, bx, y, s * 0.4);
			} else if (k == :loop) {
				dc.setPenWidth((s * 0.13).toNumber() + 1);
				dc.drawArc(bx, y, s * 0.32, Gfx.ARC_COUNTER_CLOCKWISE, 20, 160);
				dc.drawArc(bx, y, s * 0.32, Gfx.ARC_COUNTER_CLOCKWISE, 200, 340);
				arrowHead(dc, bx + s * 0.32, y - s * 0.05, s * 0.16, 1);
				arrowHead(dc, bx - s * 0.32, y + s * 0.05, s * 0.16, -1);
			}
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		} else if (k == :photo || k == :photoHdr) {
			photoCam(dc, x, y, s, color, k == :photoHdr ? "HDR" : null);
		} else if (k == :burst) {
			// two outlined frames behind a solid picture with a mountain cut-out
			dc.setPenWidth((s * 0.1).toNumber() + 1);
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			dc.drawRoundedRectangle(x - s * 0.55, y - s * 0.95, s * 1.5, s * 1.2, s * 0.15);
			dc.drawRoundedRectangle(x - s * 0.75, y - s * 0.75, s * 1.5, s * 1.2, s * 0.15);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			dc.fillRoundedRectangle(x - s * 0.95, y - s * 0.5, s * 1.5, s * 1.2, s * 0.15);
			dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
			dc.fillPolygon([[x - s * 0.78, y + s * 0.5], [x - s * 0.4, y - s * 0.05], [x - s * 0.15, y + s * 0.25],
				[x + s * 0.05, y + s * 0.05], [x + s * 0.38, y + s * 0.5]]);
			dc.fillCircle(x + s * 0.15, y - s * 0.22, s * 0.11);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		} else if (k == :interval) {
			// clock with a three-quarter ring
			dc.setPenWidth((s * 0.14).toNumber() + 1);
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			dc.drawArc(x, y, s * 0.95, Gfx.ARC_CLOCKWISE, 100, 170);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			clock(dc, x, y, s * 0.62, color);
		} else if (k == :timelapse) {
			// clock in a dashed ring
			clock(dc, x, y, s * 0.7, color);
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			dashRing(dc, x, y, s, 12, 18);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		} else if (k == :timeshift) {
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			dashRing(dc, x, y, s, 10, 22);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			runner(dc, x, y, s * 0.6);
		} else if (k == :bullet) {
			// subject with an orbit ring and an arrowhead
			dc.fillCircle(x, y, s * 0.28);
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			dc.setPenWidth((s * 0.12).toNumber() + 1);
			var pts = [];
			for (var a = 120; a <= 420; a += 15) {
				var t = Math.toRadians(a);
				pts.add([x + Math.cos(t) * s, y - Math.sin(t) * s * 0.55]);
			}
			for (var i = 0; i < pts.size() - 1; i++) {
				dc.drawLine(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
			}
			var e = pts[pts.size() - 1];
			dc.fillPolygon([[e[0] + s * 0.05, e[1] - s * 0.3], [e[0] - s * 0.32, e[1] - s * 0.02], [e[0] + s * 0.14, e[1] + s * 0.14]]);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		} else if (k == :road) {
			car(dc, x, y, s, color);
		} else if (k == :star) {
			sparkle(dc, x - s * 0.2, y + s * 0.15, s * 0.85);
			dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
			sparkle(dc, x + s * 0.6, y - s * 0.6, s * 0.38);
			sparkle(dc, x + s * 0.65, y + s * 0.65, s * 0.25);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		}
		dc.setPenWidth(1);
	}

	// Solid camcorder: body + lens wedge. A tag (legacy "4K"/"HDR") is cut out of the body.
	function videoCam(dc, x, y, s, color, tag) {
		var bw = s * 1.45;
		dc.fillRoundedRectangle(x - s * 1.05, y - s * 0.6, bw, s * 1.2, s * 0.22);
		dc.fillPolygon([[x + s * 0.48, y], [x + s * 1.05, y - s * 0.5], [x + s * 1.05, y + s * 0.5]]);
		if (tag != null) {
			dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
			dc.drawText(x - s * 1.05 + bw / 2, y, Gfx.FONT_XTINY, tag, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		}
	}

	// Solid camera with a lens ring cut out; a tag (e.g. "HDR") replaces the lens.
	function photoCam(dc, x, y, s, color, tag) {
		dc.fillRoundedRectangle(x - s, y - s * 0.5, s * 2, s * 1.25, s * 0.22);
		dc.fillRoundedRectangle(x - s * 0.4, y - s * 0.75, s * 0.8, s * 0.35, s * 0.1);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		if (tag != null) {
			dc.drawText(x, y + s * 0.12, Gfx.FONT_XTINY, tag, Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
		} else {
			dc.fillCircle(x, y + s * 0.12, s * 0.45);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			dc.fillCircle(x, y + s * 0.12, s * 0.28);
		}
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
	}

	function clock(dc, x, y, r, color) {
		dc.setPenWidth((r * 0.16).toNumber() + 1);
		dc.drawCircle(x, y, r);
		dc.drawLine(x, y, x, y - r * 0.6);
		dc.drawLine(x, y, x + r * 0.45, y + r * 0.2);
	}

	// n dashes of `len` degrees around radius s
	function dashRing(dc, x, y, s, n, len) {
		dc.setPenWidth((s * 0.12).toNumber() + 1);
		var step = 360 / n;
		for (var a = 0; a < 360; a += step) {
			dc.drawArc(x, y, s, Gfx.ARC_COUNTER_CLOCKWISE, a, a + len);
		}
	}

	// Four-point sparkle (concave star) of radius r
	function sparkle(dc, x, y, r) {
		var w = r * 0.22;
		dc.fillPolygon([[x, y - r], [x + w, y - w], [x + r, y], [x + w, y + w],
			[x, y + r], [x - w, y + w], [x - r, y], [x - w, y - w]]);
	}

	function runner(dc, x, y, r) {
		dc.setPenWidth((r * 0.22).toNumber() + 1);
		dc.fillCircle(x + r * 0.25, y - r * 0.75, r * 0.2);
		dc.drawLine(x + r * 0.1, y - r * 0.45, x - r * 0.15, y + r * 0.15);       // torso
		dc.drawLine(x - r * 0.15, y + r * 0.15, x + r * 0.35, y + r * 0.45);      // front leg
		dc.drawLine(x + r * 0.35, y + r * 0.45, x + r * 0.3, y + r * 0.85);
		dc.drawLine(x - r * 0.15, y + r * 0.15, x - r * 0.55, y + r * 0.7);       // back leg
		dc.drawLine(x + r * 0.05, y - r * 0.3, x + r * 0.5, y - r * 0.1);         // arms
		dc.drawLine(x + r * 0.05, y - r * 0.3, x - r * 0.45, y - r * 0.2);
	}

	function car(dc, x, y, s, color) {
		// body, roof, wheels; a small camera badge at the lower right
		dc.fillRoundedRectangle(x - s * 1.0, y - s * 0.15, s * 1.8, s * 0.65, s * 0.2);
		dc.fillPolygon([[x - s * 0.7, y - s * 0.15], [x - s * 0.45, y - s * 0.65], [x + s * 0.25, y - s * 0.65], [x + s * 0.5, y - s * 0.15]]);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillPolygon([[x - s * 0.55, y - s * 0.2], [x - s * 0.38, y - s * 0.52], [x + s * 0.18, y - s * 0.52], [x + s * 0.35, y - s * 0.2]]);
		dc.fillCircle(x - s * 0.6, y + s * 0.5, s * 0.26);
		dc.fillCircle(x + s * 0.4, y + s * 0.5, s * 0.26);
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.fillCircle(x - s * 0.6, y + s * 0.5, s * 0.17);
		dc.fillCircle(x + s * 0.4, y + s * 0.5, s * 0.17);
		// camera badge
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillRoundedRectangle(x + s * 0.45, y + s * 0.05, s * 0.75, s * 0.6, s * 0.12);
		dc.setColor(shade(color), Gfx.COLOR_TRANSPARENT);
		dc.fillRoundedRectangle(x + s * 0.55, y + s * 0.15, s * 0.55, s * 0.4, s * 0.08);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillCircle(x + s * 0.82, y + s * 0.35, s * 0.11);
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
	}

	// State icons: :cam (X5 silhouette with signal arcs), :camOff (struck through), :busy (hourglass)
	function stateIcon(dc, x, y, s, kind, color) {
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		if (kind == :busy) {
			dc.setPenWidth((s * 0.12).toNumber() + 1);
			dc.drawLine(x - s * 0.6, y - s, x + s * 0.6, y - s);
			dc.drawLine(x - s * 0.6, y + s, x + s * 0.6, y + s);
			dc.fillPolygon([[x - s * 0.5, y - s * 0.85], [x + s * 0.5, y - s * 0.85], [x, y - s * 0.05]]);
			dc.drawLine(x - s * 0.5, y + s * 0.85, x, y + s * 0.05);
			dc.drawLine(x + s * 0.5, y + s * 0.85, x, y + s * 0.05);
			dc.fillPolygon([[x - s * 0.3, y + s * 0.85], [x + s * 0.3, y + s * 0.85], [x, y + s * 0.5]]);
			dc.setPenWidth(1);
			return;
		}
		// X5 body: tall rounded slab, lens near the top
		var bx = (kind == :cam) ? x - s * 0.35 : x;
		dc.fillRoundedRectangle(bx - s * 0.42, y - s * 1.0, s * 0.84, s * 2.0, s * 0.3);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillCircle(bx, y - s * 0.5, s * 0.3);
		dc.fillRoundedRectangle(bx - s * 0.26, y + s * 0.05, s * 0.52, s * 0.62, s * 0.08);   // screen
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.fillCircle(bx, y - s * 0.5, s * 0.17);
		if (kind == :cam) {
			dc.setPenWidth((s * 0.11).toNumber() + 1);
			dc.drawArc(bx, y - s * 0.5, s * 0.75, Gfx.ARC_COUNTER_CLOCKWISE, -40, 40);
			dc.drawArc(bx, y - s * 0.5, s * 1.1, Gfx.ARC_COUNTER_CLOCKWISE, -35, 35);
		} else {
			dc.setPenWidth((s * 0.13).toNumber() + 1);
			dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
			dc.drawLine(x - s * 0.85, y + s * 0.95, x + s * 0.85, y - s * 0.95);
			dc.setPenWidth((s * 0.08).toNumber() + 1);
			dc.setColor(color, Gfx.COLOR_TRANSPARENT);
			dc.drawLine(x - s * 0.8, y + s * 0.9, x + s * 0.8, y - s * 0.9);
		}
		dc.setPenWidth(1);
	}

	// small filled triangle pointing up (dir 1) or down (dir -1) at (x, y)
	function arrowHead(dc, x, y, h, dir) {
		dc.fillPolygon([[x - h, y + dir * h * 0.3], [x + h, y + dir * h * 0.3], [x, y - dir * h]]);
	}

	// Solid gear, `ro` = tooth tip radius (the Settings page icon and the BACK cue)
	function gear(dc, px, py, ro, color) {
		var ri = ro * 0.74;
		var pts = [];
		var teeth = 8;
		for (var t = 0; t < teeth * 4; t++) {
			var ang = Math.PI * 2 * t / (teeth * 4) + Math.PI / (teeth * 4);
			var rad = (t % 4 == 1 || t % 4 == 2) ? ro : ri;
			pts.add([px + Math.cos(ang) * rad, py - Math.sin(ang) * rad]);
		}
		dc.setColor(color, Gfx.COLOR_TRANSPARENT);
		dc.fillPolygon(pts);
		dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
		dc.fillCircle(px, py, ro * 0.34);
	}
}
