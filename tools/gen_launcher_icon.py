"""Launcher icon for the Insta360 remote, drawn from the app's own geometry.

Run: python tools/gen_launcher_icon.py --out <path>
     [--kind cam|camOff|busy] [--ring red|green]
     [--glyph-color blue|green|red] [--arcs-color blue|green|red] [--size 512]

The mark on the watch's screen is not an image, it is code: `ModeIcons.stateIcon`
(BLE Barrel/../OneR remote/source/ModeIcons.mc:209-243) draws the X5 silhouette and
its signal waves with primitives. This tool redraws that same mark, with the same
coefficients and the same pen widths, into a PNG the resource compiler can ship as a
launcher icon, so the icon in the picker and the icon on the ready face are the same
mark instead of a screenshot of an old screen.

Two deliberate departures from the screen, both decided with the user on 15 nov. and
written in the design (see .opencode/plan/launcher-icon-design.md):

  * the signal waves are GREEN (C_GREEN, the colour of the "ready" ring) while the
    camera body stays BLUE; on screen stateIcon draws the waves in the body colour,
    and its two-tone rule (ModeIcons.mc:10-11) would dim the blue instead. The screen
    is unchanged - only this PNG parts from it, and both colours are flags.
  * the ring around it is not drawn by stateIcon at all: it is the launcher-icon
    border, sized in fractions of the image, and its colour is a flag.

Needs Pillow. Nothing here reaches the watch: no Monkey C, nothing in the build.
"""

import argparse
import sys

from PIL import Image, ImageDraw

SS = 4                      # supersampled rendering, then LANCZOS down to the size asked
N = 512                     # default source size; the resource compiler scales it down

# Palette literals, verbatim from RemoteView.mc:33-36.
C_BLUE = 0x3FA9F5           # the colour the app gives :cam when the camera is connected
C_GREEN = 0x3DDC84          # the colour of the "ready" ring
C_RED = 0xFF3B30            # the colour of the "recording" ring
BLACK = 0x000000
WHITE = 0xFFFFFF

PALETTE = {"C_BLUE": C_BLUE, "C_GREEN": C_GREEN, "C_RED": C_RED,
           "BLACK": BLACK, "WHITE": WHITE}
BY_NAME = {"blue": C_BLUE, "green": C_GREEN, "red": C_RED}

# Every coefficient this module draws with, exactly as it is written in stateIcon.
# test_launcher_icon.py refuses any of them that has left ModeIcons.mc.
GEOMETRY = [0.35, 0.42, 1.0, 0.84, 2.0, 0.3, 0.5, 0.26, 0.05, 0.52, 0.62, 0.08,
            0.17, 0.75, 1.1, 0.11, 40, 35,
            0.12, 0.6, 0.85, 0.13, 0.95, 0.8, 0.9, 0.5]

# The ring is not drawn by stateIcon: it is the launcher-icon border, sized in
# fractions of the image. Its colour is a flag, its geometry is not.
RING_R = 0.44
RING_PEN = 0.075


def rgb(value):
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def layout(size):
    """Geometry in pixels of the image that gets written out (not the supersampled one).

    `lens_x`/`lens_y` describe the shipped `:cam` composition: stateIcon shifts that
    body left to leave room for its waves, and the lens is the centre the waves open
    around. Other kinds place their own features; see state_icon().

    `ring_r` is the centre line of the ring band, `ring_pen` its width: a point at
    that radius is solidly inside the ring, which is what the probes aim at.
    """
    cx = cy = size / 2.0
    s = size * 0.28                                   # half-size of the glyph
    ring_r, ring_pen = size * RING_R, size * RING_PEN
    return {"cx": cx, "cy": cy, "s": s, "ring_r": ring_r, "ring_pen": ring_pen,
            "lens_x": cx - 0.35 * s, "lens_y": cy - 0.5 * s}


def _pen(s, factor):
    return int(s * factor) + 1                       # stateIcon: setPenWidth((s*k)+1)


def _circle(d, x, y, r, color):
    d.ellipse([x - r, y - r, x + r, y + r], fill=rgb(color))


def _rrect(d, x, y, w, h, r, color):
    d.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=rgb(color))


def _seg(d, x0, y0, x1, y1, color, width):
    d.line([x0, y0, x1, y1], fill=rgb(color), width=width)


def _arc(d, x, y, r, a0, a1, color, width):
    """dc.drawArc(x, y, r, ARC_COUNTER_CLOCKWISE, a0, a1).

    Garmin measures degrees with 0 at 3 o'clock and 90 at 12 o'clock; PIL measures
    with 0 at 3 o'clock and 90 at 6 o'clock. The same sector (-40..40 about the +x
    axis) falls out of both, which is what the wave-left/wave-right probes prove.
    """
    d.arc([x - r, y - r, x + r, y + r], start=a0, end=a1, fill=rgb(color), width=width)


def state_icon(d, cx, cy, s, kind, glyph_color, arcs_color):
    """Port of ModeIcons.stateIcon: (cx, cy) = centre, s = half-size."""
    if kind == "busy":
        w = _pen(s, 0.12)
        _seg(d, cx - s * 0.6, cy - s, cx + s * 0.6, cy - s, glyph_color, w)
        _seg(d, cx - s * 0.6, cy + s, cx + s * 0.6, cy + s, glyph_color, w)
        d.polygon([(cx - s * 0.5, cy - s * 0.85), (cx + s * 0.5, cy - s * 0.85),
                   (cx, cy - s * 0.05)], fill=rgb(glyph_color))
        _seg(d, cx - s * 0.5, cy + s * 0.85, cx, cy + s * 0.05, glyph_color, w)
        _seg(d, cx + s * 0.5, cy + s * 0.85, cx, cy + s * 0.05, glyph_color, w)
        d.polygon([(cx - s * 0.3, cy + s * 0.85), (cx + s * 0.3, cy + s * 0.85),
                   (cx, cy + s * 0.5)], fill=rgb(glyph_color))
        return

    bx = cx - s * 0.35 if kind == "cam" else cx      # X5 body: tall rounded slab
    _rrect(d, bx - s * 0.42, cy - s * 1.0, s * 0.84, s * 2.0, s * 0.3, glyph_color)
    _circle(d, bx, cy - s * 0.5, s * 0.3, BLACK)     # lens, cut out
    _rrect(d, bx - s * 0.26, cy + s * 0.05, s * 0.52, s * 0.62, s * 0.08, BLACK)   # screen
    _circle(d, bx, cy - s * 0.5, s * 0.17, glyph_color)

    if kind == "cam":
        w = _pen(s, 0.11)
        _arc(d, bx, cy - s * 0.5, s * 0.75, -40, 40, arcs_color, w)
        _arc(d, bx, cy - s * 0.5, s * 1.1, -35, 35, arcs_color, w)
    else:                                            # :camOff - struck through
        w = _pen(s, 0.13)
        _seg(d, cx - s * 0.85, cy + s * 0.95, cx + s * 0.85, cy - s * 0.95, BLACK, w)
        _seg(d, cx - s * 0.8, cy + s * 0.9, cx + s * 0.8, cy - s * 0.9, glyph_color,
             _pen(s, 0.08))


def tile(kind="cam", ring="red", size=N, glyph_color=C_BLUE, arcs_color=C_GREEN,
         ring_color=None, disc=WHITE):
    """The finished icon: the mark on a disc, inside the ring, on nothing.

    Outside the disc the tile is transparent, not black: the mark IS a disc and the
    watch composites it over whatever is behind it (the user's ruling, 15 nov. -
    the icon this one replaces was RGBA for the same reason). The alpha comes from
    a supersampled mask of the disc resized exactly like the picture, so the disc
    keeps a soft edge without a colour halo: interpolating the old black background
    against the white disc would leave one.
    """
    ring_color = ring_color if ring_color is not None else (
        C_RED if ring == "red" else C_GREEN)
    m = size * SS
    L = layout(m)
    im = Image.new("RGB", (m, m), rgb(disc))   # never seen outside the mask
    d = ImageDraw.Draw(im)
    ring_r, ring_pen = m * RING_R, m * RING_PEN
    # PIL paints a thick outline INWARD from the path, so the path goes at the outer
    # edge and the band ends up straddling ring_r, the radius layout() advertises.
    # The disc reaches that same outer edge: ring OUT, disc UNDER.
    edge = ring_r + ring_pen / 2
    d.ellipse([L["cx"] - edge, L["cy"] - edge, L["cx"] + edge, L["cy"] + edge],
              fill=rgb(disc))
    path = edge
    d.ellipse([L["cx"] - path, L["cy"] - path, L["cx"] + path, L["cy"] + path],
              outline=rgb(ring_color), width=int(ring_pen))
    state_icon(d, L["cx"], L["cy"], L["s"], kind, glyph_color, arcs_color)
    mask = Image.new("L", (m, m), 0)
    ImageDraw.Draw(mask).ellipse([L["cx"] - edge, L["cy"] - edge,
                                  L["cx"] + edge, L["cy"] + edge], fill=255)
    im = im.resize((size, size), Image.LANCZOS)
    im.putalpha(mask.resize((size, size), Image.LANCZOS))
    return im


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, help="PNG to write")
    ap.add_argument("--kind", default="cam", choices=["cam", "camOff", "busy"])
    ap.add_argument("--ring", default="red", choices=["red", "green"])
    ap.add_argument("--glyph-color", default="blue", choices=sorted(BY_NAME))
    ap.add_argument("--arcs-color", default="green", choices=sorted(BY_NAME))
    ap.add_argument("--size", type=int, default=N)
    a = ap.parse_args(argv)
    ring_color = C_RED if a.ring == "red" else C_GREEN
    im = tile(kind=a.kind, ring=a.ring, size=a.size,
              glyph_color=BY_NAME[a.glyph_color], arcs_color=BY_NAME[a.arcs_color],
              ring_color=ring_color)
    im.save(a.out)
    print("%s %dx%d kind=%s ring=%s glyph=%s arcs=%s"
          % (a.out, im.size[0], im.size[1], a.kind, a.ring, a.glyph_color, a.arcs_color))
    return 0


if __name__ == "__main__":
    sys.exit(main())
