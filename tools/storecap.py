"""Atelier de captures magasin : capture l'ecran rendu par le simulateur Connect IQ
et le monte dans le boitier de l'appareil du SDK.

Ce que fait le script :
  1. retrouve la fenetre du processus `simulator` (EnumWindows par PID) ;
  2. capture SA zone de cliente (ClientToScreen + capture d'ecran) ;
  3. en deduit l'echelle : la zone de cliente est l'image d'appareil du SDK
     agrandie (fenix847mm.png = 713x921, ecran 454x454 a (134,221)) ;
  4. ecrit l'ecran brut (454x454, deja carre, contenu rond sur fond de l'app) et
     l'appareil monte (713x921, ecran vivant sous le boitier).

usage : python storecap.py <sortie-prefixe>
ecrit <prefixe>-screen.png et <prefixe>-device.png.
"""
import ctypes
import io
import json
import sys
from ctypes import wintypes

from PIL import Image, ImageGrab

user32 = ctypes.windll.user32
DEVICES = r"C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Devices"

EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)


def exe_name(pid):
    """Nom de l'executable du processus (pur ctypes, pas de dependance externe).
    OpenProcess et QueryFullProcessImageNameW sont exports par kernel32, pas advapi32."""
    k32 = ctypes.windll.kernel32
    h = k32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return ""
    buf = ctypes.create_unicode_buffer(1024)
    size = wintypes.DWORD(len(buf))
    ok = k32.QueryFullProcessImageNameW(ctypes.c_void_p(h), 0, buf, ctypes.byref(size))
    k32.CloseHandle(ctypes.c_void_p(h))
    return buf.value.rsplit("\\", 1)[-1].lower() if ok else ""


def sim_windows():
    """Fenetres (hwnd, aire, rect) du processus du simulateur, par nom d'executable."""
    found = []

    def cb(hwnd, lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if exe_name(pid.value) not in ("simulator.exe", "simulator"):
            return True
        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        area = (r.right - r.left) * (r.bottom - r.top)
        if area > 10000:
            found.append((hwnd, area, (r.left, r.top, r.right, r.bottom)))
        return True

    user32.EnumWindows(EnumWindowsProc(cb), 0)
    found.sort(key=lambda t: -t[1])
    return found


def client_rect(hwnd):
    r = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(r))
    ptl, ptr = wintypes.POINT(0, 0), wintypes.POINT(r.right, r.bottom)
    user32.ClientToScreen(hwnd, ctypes.byref(ptl))
    user32.ClientToScreen(hwnd, ctypes.byref(ptr))
    return ptl.x, ptl.y, ptr.x, ptr.y


def anchors_of(frame, want=1400):
    """Points de controle du boitier : pixels opaques et a fort gradient (vis, bee,
    marquages). Le simulateur dessine ces pixels tels quels par-dessus l'ecran : ils
    disent ou se trouve vraiment le rendu dans la capture."""
    rgba = frame.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    strong = []
    y = 8
    while y < h - 8 and len(strong) < want * 40:
        x = 8
        while x < w - 8:
            if px[x, y][3] > 250:
                r, g, b = px[x, y][:3]
                r2, g2, b2 = px[x + 6, y][:3]
                d = abs(r - r2) + abs(g - g2) + abs(b - b2)
                if d > 90:
                    strong.append((x, y, r, g, b))
            x += 7
        y += 7
    step = max(1, len(strong) // want)
    return strong[::step]


def calib_offset(frame, shot, span=140, coarse=5):
    """Decalage (dx,dy) du rendu dans la capture, par concordance des points de
    controle du boitier. Retourne (dx, dy, score)."""
    spx = shot.convert("RGB").load()
    pts = anchors_of(frame)
    if not pts:
        return 0, 0, 0.0

    def score(dx, dy):
        good = 0
        for (x, y, r, g, b) in pts:
            cx, cy = x + dx, y + dy
            if cx < 0 or cy < 0 or cx >= shot.size[0] or cy >= shot.size[1]:
                continue
            r2, g2, b2 = spx[cx, cy]
            if abs(r - r2) + abs(g - g2) + abs(b - b2) < 40:
                good += 1
        return good / float(len(pts))

    best, bx, by = 0.0, 0, 0
    for dy in range(-span, span + 1, coarse):
        for dx in range(-span, span + 1, coarse):
            s = score(dx, dy)
            if s > best:
                best, bx, by = s, dx, dy
    for dy in range(by - coarse, by + coarse + 1):
        for dx in range(bx - coarse, bx + coarse + 1):
            s = score(dx, dy)
            if s > best:
                best, bx, by = s, dx, dy
    return bx, by, best


def main():
    prefix = sys.argv[1] if len(sys.argv) > 1 else "capture"
    dev = sys.argv[2] if len(sys.argv) > 2 else "fenix847mm"
    geom = json.load(io.open(DEVICES + "\\" + dev + "\\simulator.json", encoding="utf-8"))["display"]
    loc = geom["location"]
    frame_name = json.load(io.open(DEVICES + "\\" + dev + "\\simulator.json", encoding="utf-8"))["image"]
    frame = Image.open(DEVICES + "\\" + dev + "\\" + frame_name).convert("RGBA")
    print("boitier", frame_name, frame.size, "ecran", loc)

    wins = sim_windows()
    if not wins:
        print("AUCUNE FENETRE de simulateur trouvee")
        return 1
    hwnd, _, wr = wins[0]
    cl = client_rect(hwnd)
    print("fenetre", wr, "cliente", cl)
    shot = ImageGrab.grab(bbox=cl, all_screens=True)
    print("capture cliente:", shot.size)
    shot.save(prefix + "-client.png")

    sx = (cl[2] - cl[0]) / float(frame.size[0])
    sy = (cl[3] - cl[1]) / float(frame.size[1])
    print("echelle estimee: %.3f x %.3f" % (sx, sy))
    dx, dy, sc = calib_offset(frame, shot)
    print("calibrage du rendu: dx=%d dy=%d score=%.2f" % (dx, dy, sc))
    if sc < 0.5:
        print("ATTENTION: le boitier de la capture ne ressemble pas a celui du SDK - "
              "l'appareil demande n'est peut-etre pas celui qui tourne")
    ox, oy = int(loc["x"] * sx) + dx, int(loc["y"] * sy) + dy
    box = (ox, oy, ox + int(loc["width"] * sx), oy + int(loc["height"] * sy))
    screen = shot.crop(box).resize((loc["width"], loc["height"]), Image.LANCZOS)
    screen.save(prefix + "-screen.png")

    # L'ecran se place SOUS le boitier : le trou de l'image d'appareil (alpha) fait
    # office de masque, les coins du bee restent visibles.
    base = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    base.paste(screen.convert("RGBA"), (loc["x"], loc["y"]))
    mounted = Image.alpha_composite(base, frame)
    mounted.save(prefix + "-device.png")
    print("ecrit:", prefix + "-screen.png", screen.size, "et", prefix + "-device.png", mounted.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
