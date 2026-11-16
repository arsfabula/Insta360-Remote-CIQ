"""Outil de caviardage des captures magasin : remplace la ligne de nom de camera
(modele + numero de serie) en bas d'une capture par un texte neutre.

Pourquoi un outil et pas une retouche a la main : les captures seront refaites a
chaque publication, et le numero de serie de la camera du banc ne doit pas sortir.

Ce qu'il fait, sans rien presumer d'ecrit dans le code de l'appli :
  1. cherche dans la bande du bas les pixels clairs et neutres (le texte de l'app
     est gris clair ou blanc sur fond noir ; l'anneau rouge/vert est ecarte par
     le filtre de neutralite) ;
  2. regroupe les glyphes en lignes : chaque ligne garde une tendance (droite ou
     inflexion), donc un texte legerement incline ou courbe le long de l'anneau
     reste une seule ligne ;
  3. prend la ligne la plus basse de l'image : c'est la ligne de nom (les
     libelles de l'app, "GPS" par exemple, sont toujours au-dessus) ;
  4. efface cette ligne avec le fond local, et redessine le nouveau texte a la
     meme taille, a la meme couleur, glyphe par glyphe sur la courbe mesuree.

usage :
  # montres rondes (fenix, instinct...) : detection seule
  python tools/redact_serial.py "docs/Screenshots/Main.png" ^
         --text "X5 R3M073" --font bahnschrift --backup "C:\\originaux"

  # formats rectangulaires (Edge) : la ligne est plus haut, band plus bas
  python tools/redact_serial.py "docs/Screenshots/edge.png" --band 0.70

  # image deja retouchee une fois : redessiner aux vraies mesures de l'original
  python tools/redact_serial.py "docs/Screenshots/settngs.png" ^
         --line "188,400,284,424" --cap 17 --color "174,174,174" --font bahnschrift

Les fichiers sont modifies en place ; --backup copie d'abord les originaux.
--font force la police d'une serie entiere (la police choisie par les mesures
differerait selon que l'ecran est rond, donc condense, ou rectangulaire).
"""
import argparse
import math
import os
import shutil
import sys
from collections import deque

from PIL import Image, ImageDraw, ImageFont

MIN_GLYPH_H = 8
MAX_GLYPH_H = 30


def light_neutral_points(im, y0, y1):
    px = im.load()
    w, _ = im.size
    pts = set()
    for y in range(y0, y1):
        for x in range(0, w):
            r, g, b = px[x, y][:3]
            if min(r, g, b) > 100 and (max(r, g, b) - min(r, g, b)) < 40:
                pts.add((x, y))
    return pts


def components(pts):
    seen, comps = set(), []
    for p in pts:
        if p in seen:
            continue
        q, comp = deque([p]), []
        seen.add(p)
        while q:
            x, y = q.popleft()
            comp.append((x, y))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (x + dx, y + dy)
                    if n in pts and n not in seen:
                        seen.add(n)
                        q.append(n)
        comps.append(comp)
    return comps


def glyph(cx, cy, comp):
    xs = [p[0] for p in comp]
    ys = [p[1] for p in comp]
    return {"x0": min(xs), "y0": min(ys), "x1": max(xs), "y1": max(ys),
            "cx": cx, "cy": cy, "h": max(ys) - min(ys) + 1, "pts": comp}


def lin_trend(points):
    """Tendance (a, b) d'une suite de points : y ~ a*x + b (moindres carres)."""
    n = len(points)
    if n == 1:
        return 0.0, points[0][1]
    sx = sum(p[0] for p in points)
    sy = sum(p[1] for p in points)
    sxx = sum(p[0] * p[0] for p in points)
    sxy = sum(p[0] * p[1] for p in points)
    d = n * sxx - sx * sx
    if abs(d) < 1e-9:
        return 0.0, sy / n
    a = (n * sxy - sx * sy) / d
    return a, (sy - a * sx) / n


def group_lines(glyphs):
    """Regroupe par lignes en toleruant l'inclinaison : un glyphe rejoint la ligne
    dont la tendance passe a +/- 9 px de son centre, et dont le bord droit est a
    moins de 26 px a sa gauche. Sinon il ouvre sa propre ligne."""
    glyphs = sorted(glyphs, key=lambda g: g["cx"])
    lines = []
    for g in glyphs:
        best, dist = None, None
        for line in lines:
            a, b = lin_trend([(g2["cx"], g2["cy"]) for g2 in line])
            d = abs(g["cy"] - (a * g["cx"] + b))
            # ne jamais souder deux etiquettes empilees : la tolerance verticale
            # reste sous la hauteur d'un glyphe (sur Edge, "GPS" et le nom de
            # camera se touchent et formaient une seule ligne fantome)
            if d > min(14, 0.8 * max(g2["h"] for g2 in line)):
                continue
            gap = g["x0"] - max(q["x1"] for q in line)
            if gap > 26:
                continue
            if dist is None or d < dist:
                best, dist = line, d
        if best is None:
            lines.append([g])
        else:
            best.append(g)
    return lines


def name_line(lines):
    """La ligne de texte la plus basse de l'image, si elle ressemble a du texte."""
    ok = [l for l in lines
          if len(l) >= 4 and 40 <= max(g["x1"] for g in l) - min(g["x0"] for g in l) <= 360]
    if not ok:
        return None
    ok.sort(key=lambda l: -sum(g["cy"] for g in l) / len(l))
    return ok[0]


def sample_colour(im, line):
    rs = gs = bs = n = 0
    px = im.load()
    for g in line:
        for (x, y) in g["pts"]:
            r, g_, b = px[x, y][:3]
            rs, gs, bs, n = rs + r, gs + g_, bs + b, n + 1
    return (rs // n, gs // n, bs // n)


def background_colour(im, bbox):
    """Median des pixels sombres autour de la ligne (le fond de l'ecran)."""
    x0, y0, x1, y1 = bbox
    px = im.load()
    vals = []
    for y in range(max(0, y0 - 4), min(im.size[1], y1 + 5)):
        for x in range(max(0, x0 - 4), min(im.size[0], x1 + 5)):
            r, g, b = px[x, y][:3]
            if max(r, g, b) < 90:
                vals.append((r, g, b))
    if not vals:
        return (0, 0, 0)
    vals.sort()
    return vals[len(vals) // 2]


def fit_parab(points):
    """A*u^2 + B*u + C avec u = x - x_moyen (centré : systeme bien conditionne,
    meme quand les abscisses sont a x~250). Retourne (A, B, C, x_moyen) ou None."""
    n = len(points)
    if n < 3:
        return None
    xm = sum(p[0] for p in points) / float(n)
    us = [p[0] - xm for p in points]
    uy = [(u, p[1]) for u, p in zip(us, points)]
    su = sum(u for u, y in uy)
    sy = sum(y for u, y in uy)
    su2 = sum(u * u for u, y in uy)
    su3 = sum(u ** 3 for u, y in uy)
    su4 = sum(u ** 4 for u, y in uy)
    suy = sum(u * y for u, y in uy)
    su2y = sum(u * u * y for u, y in uy)
    m = [[su4, su3, su2], [su3, su2, su], [su2, su, float(n)]]
    v = [su2y, suy, sy]

    def det(k):
        r = [row[:] for row in m]
        for i in range(3):
            r[i][k] = v[i]
        return (r[0][0] * (r[1][1] * r[2][2] - r[1][2] * r[2][1])
                - r[0][1] * (r[1][0] * r[2][2] - r[1][2] * r[2][0])
                + r[0][2] * (r[1][0] * r[2][1] - r[1][1] * r[2][0]))

    d = det(2)
    if abs(d) < 1e-6:
        return None
    return det(0) / d, det(1) / d, det(2) / d, xm


CANDIDATE_FONTS = [
    (r"C:\Windows\Fonts\bahnschrift.ttf", [700, 75]),  # DIN gras, condense (ronds)
    (r"C:\Windows\Fonts\segoeui.ttf", None),           # Segoe UI normal
    (r"C:\Windows\Fonts\segoeuis.ttf", None),          # Segoe UI semibold
    (r"C:\Windows\Fonts\arialnb.ttf", None),
]


def probe_font(path, variant, text, size):
    """Metriques d'une police a une taille donnee : hauteur de capitale, largeur
    rendue du texte, densite d'encre (pixels marques / surface de l'emprise)."""
    f = ImageFont.truetype(path, size)
    if variant:
        try:
            f.set_variation_by_axes(variant)
        except Exception:
            pass
    xb = f.getbbox("X")
    cap = xb[3] - xb[1]
    tb = f.getbbox(text)
    strip = Image.new("L", (tb[2] - tb[0] + 40, tb[3] - tb[1] + 40), 0)
    d = ImageDraw.Draw(strip)
    d.text((20 - tb[0], 20 - tb[1]), text, font=f, fill=255)
    bb = strip.getbbox() or (0, 0, 1, 1)
    px = strip.load()
    ink = sum(1 for y in range(bb[1], bb[3]) for x in range(bb[0], bb[2]) if px[x, y] > 60)
    return f, cap, (bb[2] - bb[0]), ink / float((bb[2] - bb[0]) * (bb[3] - bb[1]))


def pick_font(text, cap_target, width_target, ink_target, only=None):
    """Parmi les polices disponibles, celle qui reproduit le mieux ce qui a ete
    MESURE sur la ligne d'origine : hauteur de capitale, largeur totale et
    densite d'encre. La largeur est ce qui distingue la police condensee des
    montres rondes de la police ordinaire des formats rectangulaires (Edge) :
    mesure du 16 nov. — ratio largeur/capitale ~5.6 sur fenix 8, ~7.7 sur Edge.
    La taille est toujours choisie pour coller a la hauteur de l'originale.
    `only` (sous-chaine de nom de police) force le choix : une serie de captures
    doit rester dans la meme police, celle deja employee sur les autres images."""
    best, best_score = None, None
    for path, variant in CANDIDATE_FONTS:
        if not os.path.exists(path):
            continue
        if only and only not in os.path.basename(path).lower():
            continue
        probe = max(8, cap_target * 3)
        f, cap0, _, _ = probe_font(path, variant, text, probe)
        if cap0 < 1:
            continue
        size = max(8, int(round(cap_target * probe / float(cap0))))
        f, cap, w_rendue, ink_frac = probe_font(path, variant, text, size)
        if abs(cap - cap_target) > 1:
            size = max(8, size + (cap_target - cap))
            f, cap, w_rendue, ink_frac = probe_font(path, variant, text, size)
        score = abs(w_rendue - width_target) / float(max(width_target, 20))
        if w_rendue > width_target + 14:
            score += (w_rendue - width_target - 14) / float(max(width_target, 20))
        if ink_target is not None:
            score += abs(ink_frac - ink_target) * 2.0
        if best_score is None or score < best_score:
            best, best_score = (f, size, w_rendue, ink_frac, path, variant), score
    if best is None:
        return ImageFont.load_default(), cap_target
    print("   police: %s %s taille=%d (largeur %.0f vs %d demandes, %s, score %.3f)" % (
        os.path.basename(best[4]), best[5] or "", best[1], best[2], width_target,
        ("encre %.2f vs %.2f" % (best[3], ink_target)) if ink_target is not None else "encre non mesuree",
        best_score))
    return best[0], best[1]


def redraw(base, slope, layer, font, text, colour, x_left, x_right, glyph_h, track):
    """Pose le texte glyphe par glyphe le long de la ligne mesuree : base(x) donne
    l'ordonnee de la ligne de baseline, slope(x) sa pente, inclinee ou inflchie
    comme sur l'original."""
    chars = list(text)

    def widths_of(f):
        out_w = []
        for c in chars:
            # getlength donne l'avance reelle du glyphe (la largeur d'encre de
            # getbbox ferait du mot vide une largeur de 'O' — l'espace vu sur
            # les premieres captures)
            out_w.append(max(2, int(round(f.getlength(c)))))
        return out_w

    widths = widths_of(font)
    total = sum(widths) + track * (len(chars) - 1)
    if total > (x_right - x_left) + 14 and hasattr(font, "font_variant"):
        # trop large pour l'empreinte de l'originale : retrecir jusqu'a ce qu'elle tienne
        for _ in range(6):
            font = font.font_variant(size=max(8, int(font.size * (x_right - x_left + 14) / total)))
            widths = widths_of(font)
            total = sum(widths) + track * (len(chars) - 1)
            if total <= (x_right - x_left) + 14:
                break
    if total > (x_right - x_left):
        # texte plus large que l'original : on garde la meme marge droite, il
        # deborde a gauche, comme le ferait l'appli avec un nom plus long
        x = x_right - total
    else:
        x = x_left + (x_right - x_left - total) / 2.0
    b0 = font.getbbox("X")
    for c, w in zip(chars, widths):
        mid = x + w / 2.0
        if c != " ":
            img = Image.new("RGBA", (w + 12, glyph_h + 14), (0, 0, 0, 0))
            d = ImageDraw.Draw(img)
            b = font.getbbox(c)
            d.text((6 - b[0], 7 - b[1]), c, font=font, fill=colour + (255,))
            img = img.rotate(-math.degrees(math.atan(slope(mid))),
                             resample=Image.BICUBIC, expand=True)
            ybase = base(mid)
            layer.paste(img, (int(mid - img.size[0] / 2),
                              int(ybase - img.size[1] / 2.0)), img)
        x += w + track


def process(path, text, backup, band=0.78, font_filter=None, line_geom=None, cap=None, color=None):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    if backup:
        os.makedirs(backup, exist_ok=True)
        shutil.copy2(path, os.path.join(backup, os.path.basename(path)))
    # 1. detecter la ligne du bas — toujours, c'est ce qu'il faut effacer,
    #    meme quand la geometrie de dessin sera dictee ensuite (--line)
    band_pts = light_neutral_points(im, int(h * band), h)
    glyphs = []
    for c in components(band_pts):
        cx = sum(p[0] for p in c) / len(c)
        cy = sum(p[1] for p in c) / len(c)
        g = glyph(cx, cy, c)
        if MIN_GLYPH_H <= g["h"] <= MAX_GLYPH_H and (g["x1"] - g["x0"]) <= 60:
            glyphs.append(g)
    lines = group_lines(glyphs)
    line = name_line(lines)
    if not line and not line_geom:
        for l in sorted(lines, key=lambda l: -sum(g["cy"] for g in l) / len(l)):
            print("  ligne refusee: bbox=(%d,%d,%d,%d) glyphes=%d" % (
                min(g["x0"] for g in l), min(g["y0"] for g in l),
                max(g["x1"] for g in l), max(g["y1"] for g in l), len(l)))
        print(path, "-> aucune ligne de nom trouvee, laisse telle quelle")
        return False
    erase_box = None
    colour_d, ink_target, med_h = None, None, None
    if line:
        line.sort(key=lambda g: g["x0"])
        erase_box = (min(g["x0"] for g in line), min(g["y0"] for g in line),
                     max(g["x1"] for g in line), max(g["y1"] for g in line))
        hs = sorted(g["h"] for g in line)
        med_h = hs[len(hs) // 2]  # mediane : les paires soudees fausseraient le max
        colour_d = sample_colour(im, line)
        for l in lines:
            print("  ligne detectee: bbox=(%d,%d,%d,%d) glyphes=%d" % (
                min(g["x0"] for g in l), min(g["y0"] for g in l),
                max(g["x1"] for g in l), max(g["y1"] for g in l), len(l)))

    if line_geom:
        # trace de dessin dicte : image deja retravaillee une fois, ou mise en page
        # serree (le petit format Edge superpose son etiquette "GPS" et le nom)
        draw_bbox = tuple(int(v) for v in line_geom)
        glyph_h = cap or med_h or (draw_bbox[3] - draw_bbox[1] + 1)
        if color:
            colour = tuple(int(v) for v in color.split(","))
        else:
            colour = colour_d or (175, 175, 175)
        curved, la, lb = False, 0.0, (draw_bbox[1] + draw_bbox[3]) / 2.0
        print("%s -> ligne dictee: draw=%s efface=%s hauteur=%d couleur=%s" % (
            os.path.basename(path), draw_bbox, erase_box, glyph_h, colour))
    else:
        draw_bbox = erase_box
        glyph_h = med_h
        colour = colour_d
        centroids = [(g["cx"], g["cy"]) for g in line]
        la, lb = lin_trend(centroids)
        line_res = max(abs(cy - (la * cx + lb)) for cx, cy in centroids)
        fit = fit_parab(centroids)
        curved = False
        if fit is not None:
            A, B, C, xm = fit
            qres = max(abs(cy - (A * (cx - xm) ** 2 + B * (cx - xm) + C)) for cx, cy in centroids)
            span = draw_bbox[2] - draw_bbox[0]
            # la parabole n'est gardee que si elle courbe reellement la ligne
            # (>=1.5 px sur la portee) et si elle colle mieux que la droite
            curved = abs(A) * span * span >= 1.5 and qres < line_res - 0.5 and qres <= 3.0
        Wd = erase_box[2] - erase_box[0] + 1
        ink_target = sum(len(g["pts"]) for g in line) / float(Wd * med_h)
        print("%s -> ligne de nom: bbox=%s hauteur=%d couleur=%s %s" % (
            os.path.basename(path), erase_box, glyph_h, colour,
            ("courbe A=%.5f res=%.1f (droite res=%.1f)" % (A, qres, line_res)) if curved
            else ("droite inclinee pente=%.3f res=%.1f" % (la, line_res))))

    bg = background_colour(im, erase_box or draw_bbox)
    out = im.copy()
    d = ImageDraw.Draw(out)
    if erase_box:
        d.rectangle((erase_box[0] - 2, erase_box[1] - 2, erase_box[2] + 2, erase_box[3] + 2), fill=bg)
    elif line_geom:
        d.rectangle((draw_bbox[0] - 2, draw_bbox[1] - 2, draw_bbox[2] + 2, draw_bbox[3] + 2), fill=bg)
    W = draw_bbox[2] - draw_bbox[0] + 1
    font, fsize = pick_font(text, glyph_h, W, ink_target, only=font_filter)
    layer = out.convert("RGBA")
    track = 2
    if curved:
        def base(x):
            return A * (x - xm) ** 2 + B * (x - xm) + C

        def slope(x):
            return 2 * A * (x - xm) + B
    else:
        def base(x):
            return la * x + lb

        def slope(x):
            return la
    redraw(base, slope, layer, font, text, colour, draw_bbox[0], draw_bbox[2], glyph_h, track)
    out = layer.convert("RGB")
    out.save(path)
    print("   ecrit: %s (taille police %d)" % (path, fsize))
    return True


def main():
    ap = argparse.ArgumentParser(description="caviarde le numero de serie des captures magasin")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--text", default="X5 R3M073", help="texte a poser a la place de la ligne de nom")
    ap.add_argument("--backup", default=None, help="repertoire ou copier les originaux")
    ap.add_argument("--band", type=float, default=0.78,
                    help="fraction de hauteur ou commence la recherche (0.78 rond, 0.70 Edge)")
    ap.add_argument("--font", default=None,
                    help="forcer la police (sous-chaine, ex: bahnschrift) pour garder la cohérence d'une série")
    ap.add_argument("--line", default=None,
                    help="géométrie de dessin dictée x0,y0,x1,y1 (image déjà retouchée, ou mise en page serrée)")
    ap.add_argument("--cap", type=int, default=None, help="hauteur de capitale dictée (px)")
    ap.add_argument("--color", default=None, help="couleur dictée r,g,b")
    a = ap.parse_args()
    n = 0
    for p in a.images:
        line_geom = [int(v) for v in a.line.split(",")] if a.line else None
        if process(p, a.text, a.backup, a.band, a.font, line_geom, a.cap, a.color):
            n += 1
    print("%d image(s) traitee(s) sur %d" % (n, len(a.images)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
