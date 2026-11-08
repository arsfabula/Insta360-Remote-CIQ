#!/usr/bin/env python3
"""CRC-32 de l'enveloppe UCD2, et preuve d'equivalence du portage Monkey C.

Algorithme (verifie ici sur les 5 golden frames de UCD2-PROTOCOL.md §7, dont la
GET_OPTIONS capturee sur camera reelle) :

    poly 0x04C11DB7, init 0xffffffff, pas de xor final
    chaque octet d'entree est XOR dans l'octet BAS de l'etat 32 bits,
    puis 32 pas MSB-first (quatre séries de huit) avec xor du poly
    le resultat est ecrit little-endian a `crcAt = 12 + declared`
    l'etat couvre tout ce qui precede le trailer, octet 7 (sequence) compris

Ce n'est PAS zlib.crc32, et ce n'est pas non plus le CRC-32/MPEG-2 classe.

Le portage Monkey C (`_mc_crc`) est la transcription fidele du code ecrit dans
FramingProbe.mc / BLEBarrel.mc : etat tenu dans 4 octets, valeurs masquees a
0xff a chaque etape (un Number Monkey C est signe 32 bits et `c << 1` au-dela
du bit 30 tourne en Float, ce qui leve Illegal Access). Cette comparaison sur
entrees aleatoires est la preuve que le portage est correct, puisque le Monkey
C ne peut pas s'executer ici.
"""
import random
import sys

POLY = 0x04C11DB7
GOLD = {
    "START seq=0x00": "55434432010c0400090000000400020100008000005b4d4b5a",
    "STOP  seq=0x00": "55434432010c04000900000005000201000080000045fa0bf1",
    "START seq=0x24": "55434432010c0424090000000400020100008000008472946e",
    "STOP  seq=0x24": "55434432010c0424090000000500020100008000009ac5d4c5",
    "GET_OPTIONS (camera)": "55434432010c04100f0000000800020100008000000830"
                            "080f080b7c008e7c",
}


def crc_ref(data: bytes) -> int:
    """Version canonique, celle qui reproduit les golden frames."""
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(32):
            crc = ((crc << 1) ^ POLY) & 0xFFFFFFFF if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
    return crc


def _mc_crc(data):
    """Transcription exacte du portage Monkey C (etat dans 4 octets)."""
    s = [0xFF, 0xFF, 0xFF, 0xFF]
    for byte in data:
        s[3] ^= byte & 0xFF
        for _ in range(32):
            carry = (s[0] & 0x80) != 0
            s[0] = ((s[0] << 1) | ((s[1] & 0x80) >> 7)) & 0xFF
            s[1] = ((s[1] << 1) | ((s[2] & 0x80) >> 7)) & 0xFF
            s[2] = ((s[2] << 1) | ((s[3] & 0x80) >> 7)) & 0xFF
            s[3] = (s[3] << 1) & 0xFF
            if carry:
                s[0] ^= 0x04
                s[1] ^= 0xC1
                s[2] ^= 0x1D
                s[3] ^= 0xB7
    return (s[0] << 24) | (s[1] << 16) | (s[2] << 8) | s[3]


def main() -> int:
    bad = 0
    print("=== golden frames (UCD2-PROTOCOL.md §7) ===")
    for name, hexs in GOLD.items():
        f = bytes.fromhex(hexs)
        span = f[:-4]
        wire = f[-4:]
        want = int.from_bytes(wire, "little")
        ref, mc = crc_ref(span), _mc_crc(span)
        ok = ref == want and mc == want
        bad += 0 if ok else 1
        print("%-22s declare=%3d crcAt=%2d wire=%s  ref=%08x mc=%08x  %s"
              % (name, int.from_bytes(f[8:12], "little"), len(f) - 4,
                 wire.hex(" ").upper(), ref, mc, "OK" if ok else "ECHEC"))

    print("\n=== equivalence ref vs portage MC (2000 entrees aleatoires) ===")
    rng = random.Random(20261104)
    for _ in range(2000):
        n = rng.randint(0, 120)
        d = bytes(rng.randrange(256) for _ in range(n))
        if crc_ref(d) != _mc_crc(d):
            bad += 1
            print("DIVERGENCE sur", d.hex())
            break
    else:
        print("2000/2000 identiques")

    print("\n=== frames construites par la sonde (verif du CRC pose) ===")
    for name, hexs in (("GET_OPTIONS x6 code 8", "55434432010c04100f0000000800020100008000000830080f080b"),
                       ("code 66 x6", "55434432010c04110a0000004200020500008000000803"),
                       ("code 4 start x6", "55434432010c041209000000040002010000800000")):
        f = bytes.fromhex(hexs)
        c = crc_ref(f)
        le = c.to_bytes(4, "little")
        print("%-20s + trailer %s  ->  %s" % (name, le.hex(" ").upper(), (f + le).hex(" ").upper()))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
