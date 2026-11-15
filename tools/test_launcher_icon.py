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

from PIL import Image

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


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_mc(*parts):
    with open(os.path.join(repo_root(), *parts), encoding="utf-8-sig") as fh:
        return fh.read()


def stateicon_body(src):
    """The text of stateIcon, from its definition to the next function."""
    start = src.index("function stateIcon")
    return src[start:src.index("\n\tfunction ", start + 1)]


class TestFollowsTheApp(unittest.TestCase):
    """A guard, not a discovery: the icon must not drift from the code it copies.

    Same stance as the CHARACTERISED group in test_golden.py - it is green now, and
    it exists to turn red when the app's drawing changes and this generator is left
    behind. A picture that silently stops matching the mark on the watch face is the
    failure this whole tool is here to avoid.
    """

    def test_geometry_literals_exist_in_modeicons(self):
        body = stateicon_body(read_mc("OneR remote", "source", "ModeIcons.mc"))
        for coeff in g.GEOMETRY:
            self.assertIn(str(coeff), body,
                          "stateIcon ne dessine plus avec %s" % coeff)

    def test_palette_literals_exist_in_remoteview(self):
        body = read_mc("OneR remote", "source", "RemoteView.mc")
        for name, value in g.PALETTE.items():
            self.assertIn("0x%06X" % value, body,
                          "%s ne correspond plus a la palette de RemoteView.mc" % name)


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
        ]
        for (x, y), want in probes:
            self.assertEqual(px(im, x, y), want, "probe (%d,%d)" % (x, y))

    def test_output_is_square_at_the_requested_size(self):
        for size in (512, 65):
            im, _ = rendered_tile(size=size)
            self.assertEqual(im.size, (size, size))

    def test_background_is_transparent(self):
        # The shipped mark is a disc, not a square: outside it there must be nothing.
        # The icon that preceded this one was RGBA for exactly that reason.
        im, L = rendered_tile()
        self.assertEqual(im.mode, "RGBA")
        edge = L["ring_r"] + L["ring_pen"] / 2 + 6   # past the disc edge AND the
        # resize filter's ~3 px tail: inside that tail the edge is legitimately soft,
        # which is the point of the mask; beyond it, there must be nothing.
        for x, y in ((4, 4), (im.size[0] - 5, 4), (4, im.size[1] - 5),
                     (im.size[0] - 5, im.size[1] - 5),
                     (L["cx"] - edge, L["cy"]),       # just outside the disc, left
                     (L["cx"], L["cy"] + edge)):      # just outside the disc, below
            self.assertEqual(im.getpixel((int(round(x)), int(round(y))))[3], 0,
                             "coin/extérieur non transparent (%d,%d)" % (x, y))

    def test_disc_and_glyph_are_opaque(self):
        im, L = rendered_tile()
        s = L["s"]
        for x, y in ((L["cx"], L["cy"] + L["ring_r"] * 0.60),   # disc, clear of the glyph
                     (L["cx"], L["cy"] - L["ring_r"]),          # ring itself
                     (L["cx"] - s * 0.35, L["cy"] + s * 1.35)):  # camera body
            self.assertEqual(im.getpixel((int(round(x)), int(round(y))))[3], 255,
                             "partie pleine translucide (%d,%d)" % (x, y))


class TestShippedFiles(unittest.TestCase):
    """The two PNGs the apps actually ship, and nothing else."""

    SHIPPED = [os.path.join("OneR remote", "resources", "images", "icon.png"),
               os.path.join("OneR remote DF", "resources", "drawables", "launcher_icon.png")]

    def test_shipped_icons_are_identical(self):
        # The widget and the data field cannot carry two different marks.
        blobs = [open(os.path.join(repo_root(), p), "rb").read() for p in self.SHIPPED]
        self.assertEqual(blobs[0], blobs[1], "les deux icones livrees different")

    def test_shipped_icon_is_the_generated_one(self):
        # Compare decoded pictures, not PNG bytes: PNG bytes depend on the Pillow
        # version, the pixels do not.
        want = g.tile()
        for p in self.SHIPPED:
            with Image.open(os.path.join(repo_root(), p)) as im:
                self.assertEqual(im.size, want.size, "%s n'est pas au bon format" % p)
                # No convert(): alpha is part of what is shipped.
                self.assertEqual(list(im.getdata()), list(want.getdata()),
                                 "%s n'est pas l'icone generee" % p)


if __name__ == "__main__":
    unittest.main(verbosity=2)
