"""Classes d'appareils du manifest, lues dans la table du SDK - pas les familles
marketing, ce qui change reellement pour cette app : niveau d'API, ecran, et type
d'application heberge avec son budget memoire.

usage: python tools/device_matrix.py [--manifest <path>] [--sdk <path>] [--full]

Pourquoi ces trois criteres : deux appareils qui concordent sur les trois courent
le meme code sur le meme canevas - un seul essai sur l'un tient pour l'autre.
La table du SDK est la source (devices.xml dans monkeybrains.jar) : elle est ce
que le compilateur lui-meme consulte pour refuser un appareil.

Le piege ou je suis tombe (15 nov. 2026, a ne pas refaire) : <app_types> d'un
appareil moderne ne contient PAS d'entree "widget" - fenix 8, descent mk3, FR 265
et consorts hebergent les widgets comme des glances (<app id="glance">). L'absence
de "widget" dans cette table n'est donc pas une capacite manquante : c'est
l'hebergement normal. Ne retirer "widget" que sur les anciens appareils (fr55,
instinct2, fenix6...) et lire le budget comme le chiffre que le compilateur
appliquera : c'est lui qui a fait la difference entre « impossible » et « normal ».
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

SDK_DEFAULT = (r"C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks"
               r"\connectiq-sdk-win-9.3.0-2026-10-20-95888f262")
MANIFEST_DEFAULT = r"C:\Users\greg\git\int-x5\OneR remote\manifest.xml"

# L'image que notre app produit, mesuree au compilateur (15 nov. 2026) : 35 292 o
# sur les appareils a hebergement glance, 129 721 o sur les widgets API 3.x. Le
# chiffre n'est pas le meme selon la generation - c'est la table qui le dit.
IMAGE_GUESS = {'3': 129721, '4': 35292, '5': 35292}


def sdk_devices_xml(sdk):
    with zipfile.ZipFile(sdk + r"\bin\monkeybrains.jar") as z:
        return z.read("com/garmin/monkeybrains/devices/devices.xml")


def manifest_products(path):
    return [m.group(1) for m in
            re.finditer(r'<iq:product id="([^"]+)"', open(path, encoding="utf-8").read())]


def parse_devices(xml_bytes):
    out = {}
    for dev in ET.fromstring(xml_bytes).iter("device"):
        ident = dev.get("id")
        if not ident:
            continue
        disp = dev.find("display")
        res = dev.find(".//resolution")
        bpp = dev.find(".//bpp")
        apps = {a.get("id"): int(a.get("memory_limit"))
                for a in dev.findall(".//app_types/app") if a.get("memory_limit")}
        api = (dev.get("grouping") or "").replace("API level ", "")
        # le type d'application que le compilateur choisira pour une app "widget" :
        # widget si l'appareil le declare, sinon la glance qui l'héberge
        kind, budget = ("widget", apps.get("widget")) if "widget" in apps else ("glance", apps.get("glance"))
        out[ident] = {
            "shape": dev.get("family"),
            "api": api,
            "kind": kind,
            "budget": budget,
            "shape_kind": disp.get("shape") if disp is not None else None,
            "touch": (disp.get("id") == "TOUCH") if disp is not None else False,
            "res": "%sx%s" % (res.get("width"), res.get("height")) if res is not None else "?",
            "bpp": bpp.text.strip() if bpp is not None and bpp.text else "?",
            "name": dev.get("name"),
        }
    return out


def main(argv):
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--manifest", default=MANIFEST_DEFAULT)
    ap.add_argument("--sdk", default=SDK_DEFAULT)
    ap.add_argument("--full", action="store_true")
    args, rest = ap.parse_known_args(argv)

    products = manifest_products(args.manifest)
    devices = parse_devices(sdk_devices_xml(args.sdk))
    unknown = [p for p in products if p not in devices]
    print("manifest: %d produits ; absents de la table de ce SDK: %s"
          % (len(products), ", ".join(unknown) if unknown else "aucun"))

    groups = {}
    for p in products:
        d = devices.get(p)
        if d is None:
            continue
        key = (d["api"], d["shape"], d["res"], d["bpp"], d["kind"], bool(d["touch"]))
        groups.setdefault(key, []).append((p, d))

    print("%d produits classables en %d classes (api, ecran, bpp, hebergement, tactile)\n"
          % (len(products) - len(unknown), len(groups)))
    hdr = ("api    ecran             bpp  heberge  budget   tactile  nb  representatives")
    print(hdr)
    print("-" * len(hdr))
    tight = []
    for key in sorted(groups, key=lambda k: (k[0] or "", k[1] or "")):
        api, shape, res, bpp, kind, touch = key
        members = groups[key]
        budget = members[0][1]["budget"]
        names = ", ".join(p for p, _ in members[:3]) + (" (+%d)" % (len(members) - 3) if len(members) > 3 else "")
        guess = IMAGE_GUESS.get((api or "").split(".")[0], 0)
        fits = "?" if not budget or not guess else ("tient" if budget >= guess else "NE TIENT PAS")
        if fits == "NE TIENT PAS":
            tight.append((key, members, budget, guess))
        print("%-6s %-17s %-4s %-8s %-8s %-8s %2d  %s"
              % (api, "%s %s" % (shape, res), bpp, kind,
                 budget, touch, len(members), names))
        if args.full:
            for p, d in members:
                print("        %-26s %s" % (p, d["name"]))

    print("\n--- classes ou l'image depasse le budget (a verifier au compilateur, pas ici) ---")
    for (api, shape, res, bpp, kind, touch), members, budget, guess in tight:
        print("  api %s %s %s heberge=%s budget=%s image~%s : %s"
              % (api, shape, res, kind, budget, guess, ", ".join(p for p, _ in members)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
