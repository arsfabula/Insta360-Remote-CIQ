"""Pixel tests for the launcher-icon generator.

Run: python tools/test_launcher_icon.py

The launcher icon is a picture, so the tests probe pictures: a coordinate computed
from the same coefficients the app draws with (`ModeIcons.stateIcon`) and the exact
colour expected there. A probe that lands on the wrong colour means the geometry or
the palette moved, which is exactly what must not happen silently - the icon on the
watch and the icon on the watch face are supposed to be the same mark.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gen_launcher_icon as g  # noqa: E402

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
# The palette in the generator is the .mc integer literals (the palette guard reads
# those literals back out of RemoteView.mc); a picture is compared as RGB.
C_BLUE = g.rgb(g.C_BLUE)
C_GREEN = g.rgb(g.C_GREEN)
C_RED = g.rgb(g.C_RED)


def rendered_tile(kind="cam", ring="red", size=512):
    """The shipped tile plus its layout, so a test can aim at real features."""
    return g.tile(kind=kind, ring=ring, size=size), g.layout(size)


def px(im, x, y):
    return im.getpixel((int(round(x)), int(round(y))))[:3]


class TestShippedIcon(unittest.TestCase):
    def test_probes_of_the_shipped_icon(self):
        im, L = rendered_tile()                      # tile(kind="cam", ring="red", size=512)
        s = L["s"]
        bx = L["cx"] - s * 0.35                      # body shifted left, as stateIcon does
        lx, ly = L["lens_x"], L["lens_y"]           # generator puts lens_y at cy - s * 0.5
        probes = [
            ((bx, ly + s * 1.35), C_BLUE),                            # body, below the screen
            ((lx, ly), C_BLUE),                                       # lens centre dot
            ((lx + s * 0.25, ly), BLACK),                             # lens cut-out ring
            ((lx + s * 1.05, ly), C_GREEN),                           # signal wave, right
            ((lx - s * 0.62, ly), WHITE),                             # no wave left of the body
            ((L["cx"], L["cy"] - L["ring_r"]), C_RED),                # ring
            ((L["cx"] - L["ring_r"] * 0.60, L["cy"] - L["ring_r"] * 0.60), WHITE),  # disc inside
            ((4, 4), BLACK),                                          # outer corner
        ]
        for (x, y), want in probes:
            self.assertEqual(px(im, x, y), want, "probe (%d,%d)" % (x, y))

    def test_output_is_square_at_the_requested_size(self):
        for size in (512, 65):
            im, _ = rendered_tile(size=size)
            self.assertEqual(im.size, (size, size))

    def test_icon_is_opaque(self):
        # A tile with transparent areas reads as a hole in the watch's picker.
        im, _ = rendered_tile()
        self.assertEqual(im.mode, "RGB")


if __name__ == "__main__":
    unittest.main(verbosity=2)
