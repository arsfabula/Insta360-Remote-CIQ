import argparse
import asyncio
import sys

# le pilote de reference x5_ble.py (bleak); ajuster si l outils est ailleurs
OUTILS = "/media/greg/media/kDrive/Documents/Default Project/Insta360 Remote/outils"
sys.path.insert(0, OUTILS)
import x5_ble as ble


async def run(camera, args):
    frame = await camera.request(8, bytes.fromhex("0a020b14"), wait=8.0,
                                 label="GET_OPTIONS battery+storage")
    if frame:
        print("REPONSE code=%s declare=%s body=%s"
              % (frame["code"], frame["total"], bytes(frame["body"]).hex()), flush=True)
    else:
        print("aucune reponse GET_OPTIONS", flush=True)
    print("=== ECOUTE 90 s : branche puis debranche le chargeur ===", flush=True)
    await camera.drain(90.0)
    print("=== BILAN %d trame(s) ===" % len(camera.frames), flush=True)
    for f in camera.frames:
        print("code=%-6d seq=%-8d declare=%-4d body=%s"
              % (f["code"], f["seq"], f["total"], bytes(f["body"]).hex()[:140]), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--address", required=True)
    ap.add_argument("--scan-timeout", type=float, default=8.0)
    ap.add_argument("--mtu", type=int, default=20)
    return asyncio.run(ble.with_camera(ap.parse_args(), run))


if __name__ == "__main__":
    sys.exit(main())
