"""Rend transparent le fond des captures magasin (le fond gris pose par-dessus
le disque de l'ecran), sans toucher au contenu de l'ecran.

Pourquoi une inondation depuis les bords et pas une clef de couleur : la ligne
de nom de l'appli est elle-meme grise (174,174,174) et le fond pose est gris
(127,127,127) — une clef de couleur globale mangerait le texte. Seule la zone
de fond, continuee depuis les bords de l'image, est retiree.

L'arete du disque est anti-aliasee (pixels melange fond/ecran) : elle recoit un
alpha progressif selon sa distance a la couleur de fond, pour que le rendu soit
propre sur n'importe quel fond de page du magasin.

usage :
  python tools/transparent_background.py "docs/Screenshots/Main.png" ^
         "docs/Screenshots/Connecting.png" ...
"""
import sys
from collections import deque

from PIL import Image

TOL_STRICT = 32   # identique au fond -> totalement transparent
TOL_FEATHER = 90  # pixels de melange en bord de disque -> alpha progressif


def dist_to(px, colour):
    r, g, b = px[:3]
    return max(abs(r - colour[0]), abs(g - colour[1]), abs(b - colour[2]))


def background_colour(px, w, h):
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    base = corners[0][:3]
    for c in corners[1:]:
        if dist_to(c, base) > 8:
            return None  # les quatre coins ne se ressemblent pas : pas de fond unique
    return base


def make_transparent(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    bg = background_colour(px, w, h)
    if bg is None:
        print("%s : les quatre coins ne sont pas du meme fond, laisse telle quelle" % path)
        return False
    near = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not near[y][x] and dist_to(px[x, y], bg) <= TOL_STRICT:
                near[y][x] = True
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not near[y][x] and dist_to(px[x, y], bg) <= TOL_STRICT:
                near[y][x] = True
                q.append((x, y))
    filled = 0
    while q:
        x, y = q.popleft()
        filled += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not near[ny][nx] and dist_to(px[nx, ny], bg) <= TOL_STRICT:
                near[ny][nx] = True
                q.append((nx, ny))
    # feather : tout pixel a portee du fond, colle a une zone retirees, recoit un
    # alpha proportionnel a sa difference avec le fond (127 -> 0 % transparent...)
    feathered = 0
    frontier = set()
    for y in range(h):
        for x in range(w):
            if near[y][x]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not near[ny][nx]:
                        frontier.add((nx, ny))
    for (x, y) in frontier:
        d = dist_to(px[x, y], bg)
        if d < TOL_FEATHER:
            r, g, b, _ = px[x, y]
            alpha = int(255 * (d - TOL_STRICT) / float(TOL_FEATHER - TOL_STRICT)) if d > TOL_STRICT else 0
            px[x, y] = (r, g, b, alpha)
            feathered += 1
    for y in range(h):
        for x in range(w):
            if near[y][x]:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
    # ilots : un petit groupement opaque entoure de fond n'appartient pas a
    # l'ecran (tache laissee par la pose du fond gris). L'ecran forme toujours
    # un seul grand groupe connexe ; tout ce qui est minuscule a cote est retire.
    island = [[-1] * w for _ in range(h)]
    islands, dropped = 0, 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or island[y][x] >= 0:
                continue
            q2 = deque([(x, y)])
            island[y][x] = islands
            members = []
            while q2:
                cx0, cy0 = q2.popleft()
                members.append((cx0, cy0))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx0 + dx, cy0 + dy
                    if 0 <= nx < w and 0 <= ny < h and island[ny][nx] < 0 and px[nx, ny][3] > 0:
                        island[ny][nx] = islands
                        q2.append((nx, ny))
            if len(members) < max(64, int(w * h * 0.02)):
                for (mx, my) in members:
                    r, g, b, _ = px[mx, my]
                    px[mx, my] = (r, g, b, 0)
                    dropped += 1
            islands += 1
    im.save(path)
    print("%s : fond %s, %d px transparents, %d px adoucis, %d px d'ilots retires -> enregistre" % (
        path, bg, filled, feathered, dropped))
    return True


def main():
    n = 0
    for p in sys.argv[1:]:
        if make_transparent(p):
            n += 1
    print("%d image(s) traitee(s) sur %d" % (n, len(sys.argv) - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
