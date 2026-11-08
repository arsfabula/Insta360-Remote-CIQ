#!/usr/bin/env python3
"""Inventorier les commandes BLE utilisees par l'app montre officielle Insta360.

Cible: insta360-epixpro51.prg (app Garmin CIQ officielle Insta360, v4.27.2).

Ce que fait ce script:
  1. parse la section Data proprement (sentinelles 0x01 string_def,
     0x03 container, 0xc1/0xc2 class_def) a partir de data+4 (le dump de base
     s'arretait sur le magic 0xda7ababe);
  2. construit la table des symboles -> def (champ de classe, string, container);
  3. decode la table de registre des commandes: la classe dont le module est
     `sym=38` contient des champs "Module <petit int>" (le code) suivis de
     "Class <def>" (le message protobuf de la commande), en paires;
  4. retrouve le nom du message de chaque commande via la classe module de
     chaque def (module_id ou parent->module) dont la string_def est "Xxx {";
  5. croise avec tools/apk_extract/message_code_map.txt (codes du APK) quand
     l'identifiant existe;
  6. liste les sites d'appel: methodes du P-code qui poussent un code de
     commande (spush <sym module> dont le champ vaut <code>).

Ne modifie pas la cible. Sortie: stdout (ou --out).

Portee reelle (verifiee seance 2026-11-05, PROTOCOL_APK.md 15.23): le point 3
est une lecture non confirmee. Dans out/prg/uses.txt les lignes "code NNN" de la
classe @data+0x44ed sont bien le propre enum PHONE_COMMAND_* de l'app (les
valeurs correspondent aux codes vus sur le fil), mais les attributions
"senders:" ne sont pas utilisables. Pour savoir ce que l'app envoie vraiment, et
avec quel corps de message, utiliser tools/prg_cmd_payloads.py (21 sites, 14
codes).

Usage:
    python tools/prg_commands.py <file.prg> [--codes 3,7,8] [--calls] [--out DIR]
"""

import argparse
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prg_dump
import prg_disasm


class DataSections:
    """Section Data parsee: strings, class_defs, containers + index de symboles."""

    def __init__(self, content):
        self.content = content
        self.strings = {}       # data offset (debut string_def) -> str
        self.str_at = {}        # data offset -> string (alias)
        self.classes = {}       # data offset -> class dict (+ 'offset')
        self.containers = {}    # data offset -> bytes
        self.entries = []       # (kind, start, end)
        self.sym_fields = {}    # symbol -> list of (class_offset, field)
        self.walk()
        for off, cls in self.classes.items():
            for f in cls["fields"]:
                self.sym_fields.setdefault(f["symbol"], []).append((off, f))

    def walk(self):
        pos = 0  # le contenu passe deja le magic (0xda7ababe) + la taille
        c = self.content
        n = len(c)
        while pos < n:
            b = c[pos]
            if b == 0x00:
                pos += 1
                continue
            if b == 0x01:
                if pos + 3 > n:
                    break
                ln = struct.unpack(">H", c[pos + 1:pos + 3])[0]
                end = pos + 3 + ln
                if end > n:
                    break
                raw = c[pos + 3:end]
                s = raw.split(b"\x00")[0].decode("utf-8", "replace")
                self.strings[pos] = s
                self.str_at[pos] = s
                self.entries.append(("string", pos, end))
                pos = end
                continue
            if b == 0x03:
                if pos + 5 > n:
                    break
                ln = struct.unpack(">I", c[pos + 1:pos + 5])[0]
                end = pos + 5 + ln
                if end > n:
                    break
                self.containers[pos] = c[pos + 5:end]
                self.entries.append(("container", pos, end))
                pos = end
                continue
            if b in (0xC1, 0xC2):
                cls, npos = prg_dump.parse_class_def(c, pos)
                if cls is None:
                    break
                cls["offset"] = pos
                cls["field_size"] = 9 if cls["is_v2"] else 8
                self.classes[pos] = cls
                self.entries.append(("class", pos, npos))
                pos = npos
                continue
            self.entries.append(("stop", pos, pos))
            break

    def string_of(self, value):
        return self.strings.get(value)

    def module_class_of(self, cls):
        """Classe module qui definit cls (module_id) ou, a defaut, son parent module."""
        mid = cls.get("module_id")
        if isinstance(mid, int) and mid in self.sym_fields:
            for off, f in self.sym_fields[mid]:
                if f["type_name"] in ("Module", "Class") and f["value"] in self.classes:
                    m = self.classes[f["value"]]
                    if m["offset"] != cls["offset"]:
                        return m
        return None

    def message_name(self, cls):
        """Nom du message protobuf d'une class_def: string_def 'Xxx {' de sa module."""
        m = self.module_class_of(cls)
        if m is None:
            return None
        for f in m["fields"]:
            if f["type_name"] == "String":
                s = self.string_of(f["value"])
                if s:
                    return s
        return None


def find_registry(dm):
    """Retourne la class_def qui sert de registre code -> message (module sym=38...).

    Indice: une classe dont le module_id pointe vers un module contenant de
    nombreux champs 'Module' de petite valeur (< 0x200) et des champs 'Class'.
    """
    best = None
    for off, cls in dm.classes.items():
        codes = [f for f in cls["fields"]
                 if f["type_name"] == "Module" and f["value"] < 0x200]
        msgs = [f for f in cls["fields"]
                if f["type_name"] == "Class" and f["value"] in dm.classes]
        score = len(codes) + len(msgs)
        if codes and msgs and len(codes) >= 10 and (best is None or score > best[1]):
            best = (off, score)
    return best


def build_code_table(dm, reg_off):
    """Liste ordonnee de (code, class_offset|None, champ) a partir du registre."""
    cls = dm.classes[reg_off]
    rows = []
    for f in cls["fields"]:
        if f["type_name"] == "Module" and f["value"] < 0x200:
            rows.append({"code": f["value"], "sym": f["symbol"], "cls": None})
        elif f["type_name"] == "Class" and f["value"] in dm.classes:
            rows.append({"code": None, "sym": f["symbol"], "cls": f["value"]})
    return rows


def load_apk_map(path):
    """message_code_map.txt: lignes 'id NAME' ou 'NAME id' -> dict id -> [NAMES]."""
    ids = {}
    if not os.path.exists(path):
        return ids
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.search(r"(PHONE_COMMAND_\w+|[A-Z][A-Z0-9_]{3,})\D*?\b(\d{1,3})\b", line)
            if not m:
                m = re.search(r"\b(\d{1,3})\D*?(PHONE_COMMAND_\w+|[A-Z][A-Z0-9_]{3,})", line)
                if not m:
                    continue
                num, name = m.group(1), m.group(2)
            else:
                name, num = m.group(1), m.group(2)
            ids.setdefault(int(num), []).append(name)
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("--map", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "apk_extract", "message_code_map.txt"))
    ap.add_argument("--codes", help="filtrer sur une liste de codes, ex 3,7,8")
    ap.add_argument("--calls", action="store_true", help="ajouter l'analyse des sites d'appel")
    ap.add_argument("--out", help="repertoire de sortie")
    args = ap.parse_args()

    data = open(args.prg, "rb").read()
    start, sections = prg_dump.parse_sections(data)
    sec = {name: (body_off, ln) for _, name, ln, body_off, _ in sections}
    d_off, d_len = sec["Data"]
    c_off, c_len = sec["Code"]
    dm = DataSections(data[d_off:d_off + d_len])
    print("=== %s ===" % args.prg)
    print("data: %d class_defs, %d string_defs, %d containers" %
          (len(dm.classes), len(dm.strings), len(dm.containers)))

    reg = find_registry(dm)
    if not reg:
        print("registre de commandes introuvable")
        return 1
    reg_off, _score = reg
    rows = build_code_table(dm, reg_off)
    print("registre: class @data+0x%x  (%d entrees)" % (reg_off, len(rows)))

    # appairage: les entrees Module/Class du registre sont en fait des champs
    # separes; on les garde cote a cote tel quel, le nom du message vient de la
    # class 'Class' qui suit.
    apk = load_apk_map(args.map)
    want = None
    if args.codes:
        want = {int(x) for x in re.findall(r"\d+", args.codes)}

    by_class = {}
    cls_sym = {}     # symbol -> class offset (champs 'Class' de tout le programme)
    for off, cls in dm.classes.items():
        for f in cls["fields"]:
            if f["type_name"] in ("Class", "Module") and f["value"] in dm.classes:
                cls_sym[f["symbol"]] = f["value"]

    codes = [r for r in rows if r["code"] is not None]
    msgs = [r for r in rows if r["cls"] is not None]
    out = []
    out.append("--- codes declares par le registre (data+0x%x) ---" % reg_off)
    for r in codes:
        apk_names = ", ".join(sorted(set(apk.get(r["code"], []))))
        out.append("  code %3d (0x%02x)  sym=%-5d %s" % (
            r["code"], r["code"], r["sym"], ("[apk: %s]" % apk_names) if apk_names else ""))
    out.append("--- classes message declarees par le registre ---")
    for r in msgs:
        cls = dm.classes[r["cls"]]
        name = dm.message_name(cls)
        by_class.setdefault(r["cls"], []).append({"sym": r["sym"], "name": name})
        out.append("  sym=%-5d -> class @data+0x%04x  module=%s parent=%s  nom=%s" % (
            r["sym"], r["cls"], cls.get("module_id"), cls.get("parent_module_id"),
            name or "?"))
    print("\n".join(out))

    # tentative d'appairage code <-> message: un code N (sym S) et une classe
    # dont le module est designe par un symbol proche, ou dont le module porte
    # une string 'Xxx {' dont le nom matche le nom APK du code.
    print("--- appairage code -> nom de message (via noms APK / strings) ---")
    name2code = {}
    for c, names in apk.items():
        for n in names:
            name2code.setdefault(n.replace("PHONE_COMMAND_", ""), []).append(c)
    for r in msgs:
        cls = dm.classes[r["cls"]]
        name = dm.message_name(cls)
        if not name:
            continue
        base = name.rstrip(" {")
        cands = set()
        for n, cs in name2code.items():
            if base and (base.upper() == n or base.upper() in n or n in base.upper()):
                cands.update(cs)
        if cands:
            print("  class @data+0x%04x nom=%-24s codes APK candidats: %s" % (
                r["cls"], base, sorted(cands)))

    if args.calls:
        # reuse le desassembleur existant pour lister les methodes
        methods = prg_disasm.find_methods(dm) if hasattr(prg_disasm, "find_methods") else None
        print("--- analyse des sites d'appel: --calls (implementation a venir) ---")
        print("(voir tools/prg_disasm.py pour le listing brut du P-code)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
