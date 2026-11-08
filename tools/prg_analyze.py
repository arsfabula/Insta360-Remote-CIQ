#!/usr/bin/env python3
"""Analyse statique complete d'un .prg Garmin CIQ (app montre officielle Insta360).

Outil central de l'inventaire des commandes BLE: il recolle les morceaux
laissés en vrac par prg_dump.py (sections/Data) et prg_disasm.py (P-code).

Ce qu'il apporte de plus:
  * table des symboles: (module_id, symbol) -> champ de class_def  -> c'est
    ainsi que le P-code designe une constante de module:  getmv <module> <sym>
  * les constantes de module `Module flags=5 value=<petit int>` sont des codes
    de commande; les `Class flags=5 value=<offset Data>` sont les classes de
    message protobuf associees;
  * nom de chaque classe de message: sa methode name() (symbole 8388712) est
    le seul endroit qui news la string_def "Xxx {";
  * champs de chaque message: la methode 8388712 news aussi
    "     <champ>: " pour chaque champ renseigne;
  * listing par methode avec annotations (getmv/getsv/spush/news resolus).

Usage:
    python tools/prg_analyze.py <file.prg> <mode> [options]

Modes:
    registry            table des codes de commande + classes message
    uses [--code N]     sites d'appel (getmv) de chaque constante de module
    method <addr>       listing d'une methode (addr = code+0x… ou classe data+0x…)
    cls <off>           champs + methodes + champs protobuf d'une class_def
    msgs                fiche complete de chaque classe de message
    grep <motif>        methodes dont le listing contient <motif>

Ne modifie jamais la cible.
"""

import argparse
import bisect
import collections
import glob
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prg_dump
import prg_disasm

NAME_METHOD = 8388712        # identifiant API « print »: le toString genere
DESCRIPTOR_METHOD = 8388702  # identifiant API « initialize »: le constructeur
VALUE_GET = 8389629          # « getValue »
VALUE_SET = 8390426          # « setValue »


def u4(b):
    return struct.unpack(">I", b)[0]


def load_api_db(path):
    """api.db du SDK Connect IQ: `identifiant <espace> symbole` (une ligne par
    identifiant predefini). Les symboles >= 8388608 (0x800000) de la section Code
    et des class_defs designent ces identifiants: c'est la seule clef qui permette
    de nommer les methodes d'un .prg distribue (la section Symbols est retiree).

    Retourne {symbole: nom}.
    """
    db = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                db[int(parts[1])] = parts[0]
    return db


class Prg:
    """Un .prg charge + sections Data/Code parsees + index de symboles."""

    def __init__(self, path, api_db=None):
        self.path = path
        self.api = load_api_db(api_db) if api_db else {}
        self.raw = open(path, "rb").read()
        start, sections = prg_dump.parse_sections(self.raw)
        self.sections = sections
        dsec = [s for s in sections if s[1] == "Data"][0]
        csec = [s for s in sections if s[1] == "Code"][0]
        self.data = self.raw[dsec[3]:dsec[4]]
        self.code = self.raw[csec[3]:csec[4]]
        self.data_off = dsec[3]
        self.code_off = csec[3]
        strings, classes, arrays, containers, entries = prg_dump.parse_data_section(self.data)
        self.strings = strings
        self.str_by_name = {}
        for off, s in strings.items():
            self.str_by_name.setdefault(s, []).append(off)
        self.classes = {}
        for off, cls in classes:
            cls["offset"] = off
            self.classes[off] = cls
        self.arrays = arrays
        self.containers = containers
        self.entries = entries
        # module_id -> class_def (une class_def declare un module_id unique)
        self.by_module = {}
        for off, cls in self.classes.items():
            mid = cls.get("module_id")
            if isinstance(mid, int) and mid not in self.by_module:
                self.by_module[mid] = off
        # symbol -> [(class_off, field)]
        self.sym_fields = collections.defaultdict(list)
        for off, cls in self.classes.items():
            for f in cls["fields"]:
                self.sym_fields[f["symbol"]].append((off, f))
        self._build_methods()

    # ---------------------------------------------------------------- methodes
    def _build_methods(self):
        """table des points d'entree de methodes, triee, + index par classe."""
        self.methods = {}
        self.methods_by_class = collections.defaultdict(list)
        for off, cls in self.classes.items():
            for f in cls["fields"]:
                if f["type_name"] != "Method":
                    continue
                pc = f["value"] & 0x0FFFFFFF
                if f["value"] == 0x10000000:
                    continue  # pas de corps (herite de la classe mere)
                self.methods[pc] = (off, f["symbol"], f["flags"])
                self.methods_by_class[off].append((f["symbol"], f["flags"], pc))
        self.method_pcs = sorted(self.methods)

    def method_end(self, pc):
        i = bisect.bisect_right(self.method_pcs, pc)
        return self.method_pcs[i] if i < len(self.method_pcs) else len(self.code)

    def method_at(self, pc):
        i = bisect.bisect_right(self.method_pcs, pc) - 1
        if i < 0:
            return None
        p = self.method_pcs[i]
        return (p,) + self.methods[p]

    # ------------------------------------------------------------------ noms
    def class_name(self, off):
        """Nom du message d'une class_def: string_def 'Xxx {' newssee par name()."""
        for sym, flags, pc in self.methods_by_class.get(off, ()):
            if sym != NAME_METHOD:
                continue
            for _, mn, arg, _ in self.disasm(pc, self.method_end(pc)):
                if mn == "news" and isinstance(arg, int) and arg in self.strings:
                    s = self.strings[arg]
                    if s.endswith(" {"):
                        return s[:-2].strip()
        return None

    def message_fields(self, off):
        """Champs protobuf d'une classe message, dans l'ordre du name()."""
        out = []
        for sym, flags, pc in self.methods_by_class.get(off, ()):
            if sym != NAME_METHOD:
                continue
            for _, mn, arg, _ in self.disasm(pc, self.method_end(pc)):
                if mn == "news" and isinstance(arg, int):
                    s = self.strings.get(arg, "")
                    m = re.match(r"^\s+([a-z_0-9]+):\s*$", s)
                    if m and m.group(1) not in out:
                        out.append(m.group(1))
        return out

    def field_name(self, sym):
        """Nom d'un champ de classe (best effort: sa string d'annotation)."""
        return None

    # --------------------------------------------------------------- resolution
    def resolve_module_sym(self, mod, sym):
        """(module_id, symbol) -> (class_off, field) si connu."""
        coff = self.by_module.get(mod)
        if coff is None:
            return None
        for off, f in self.sym_fields[sym]:
            if off == coff:
                return (coff, f)
        return None

    def resolve_sym(self, sym, near_class=None):
        """Symbole simple -> (class_off, field) en preferant la classe courante."""
        cands = self.sym_fields.get(sym) or []
        if not cands:
            return None
        if near_class is not None:
            for off, f in cands:
                if off == near_class:
                    return (off, f)
        return cands[0]

    def describe_module_sym(self, mod, sym):
        """(module_id, symbol) -> description lisible + champ trouve eventuellement."""
        r = self.resolve_module_sym(mod, sym)
        modname = self.api.get(mod) or ("module %d" % mod)
        name = self.api.get(sym)
        if r:
            coff, f = r
            if f["type_name"] in ("Module", "Class") and f["value"] in self.classes:
                return "%s.%s -> message %s" % (modname, name or "sym%d" % sym,
                                                self.class_name(f["value"]) or "?"), f
            if f["type_name"] in ("Module", "Class") and f["value"] in self.by_module:
                return "%s.%s -> sous-module %d" % (modname, name or "sym%d" % sym, f["value"]), f
            return ("%s.%s -> champ %s=%#x" % (modname, name or "sym%d" % sym,
                                               f["type_name"], f["value"])), f
        if name:
            return "%s.%s" % (modname, name), None
        return None, None

    # -------------------------------------------------------------- desassemblage
    def disasm(self, start, end=None):
        """(pc, mnemonique, arg, annotation) — lineaire, borne = start..end."""
        end = end if end is not None else self.method_end(start)
        out = []
        pc = start
        cls_off = self.methods.get(start, (None,))[0]
        while pc < end:
            op = self.code[pc]
            if op not in prg_disasm.OPCODES:
                out.append((pc, "?%02x" % op, None, ""))
                pc += 1
                continue
            mn, size, fmt = prg_disasm.OPCODES[op]
            if pc + size > end:
                out.append((pc, mn, None, "TRONQUE"))
                break
            raw = self.code[pc + 1:pc + size]
            ann = ""
            arg = None
            if fmt == "u1":
                arg = raw[0]
            elif fmt == "u2":
                arg = struct.unpack(">H", raw)[0]
            elif fmt == "u3":
                arg = int.from_bytes(raw, "big")
            elif fmt == "u4":
                arg = u4(raw)
            elif fmt == "u8":
                arg = int.from_bytes(raw, "big")
            elif fmt == "u4u4":
                arg = (u4(raw[:4]), u4(raw[4:]))
            elif fmt == "u1u4":
                arg = (raw[0], u4(raw[1:]))
            elif fmt == "u2rel":
                arg = struct.unpack(">H", raw)[0]

            if mn in ("getmv",) and isinstance(arg, tuple):
                mod, sym = arg
                desc, f = self.describe_module_sym(mod, sym)
                ann = "  ; %s" % desc if desc else "  ; module %d sym %d" % (mod, sym)
            elif mn in ("getsv", "putsv", "getselfv", "spush", "putselfv") and isinstance(arg, int):
                r = self.resolve_sym(arg, cls_off)
                if r:
                    coff, f = r
                    if f["type_name"] in ("Module", "Class") and f["value"] in self.classes:
                        ann = "  ; champ sym %d -> message %s" % (arg, self.class_name(f["value"]))
                    else:
                        ann = "  ; champ sym %d (%s=%#x)" % (arg, f["type_name"], f["value"])
                elif arg in self.api:
                    ann = "  ; %s" % self.api[arg]
            elif mn == "news" and isinstance(arg, int):
                s = self.strings.get(arg)
                ann = "  ; %r" % s if s is not None else ""
            elif mn in ("apush", "bapush", "hpush") and isinstance(arg, int):
                s = self.strings.get(arg)
                ann = "  ; data+%#x %r" % (arg, s) if s is not None else "  ; data+%#x" % arg
            elif mn in ("invoke", "invokevirtual", "invokestatic", "invokedirect",
                        "invokeinterface", "invokemz") and isinstance(arg, int):
                ann = ""
            elif mn in ("bt", "bf", "goto", "jsr") and isinstance(arg, int):
                ann = "  -> code+%#x" % (start + arg if arg < 0x1000000 else arg)
            out.append((pc, mn, arg, ann))
            pc += size
        return out

    def listing(self, start, end=None):
        lines = []
        for pc, mn, arg, ann in self.disasm(start, end):
            if isinstance(arg, tuple):
                a = "%d %d" % arg
            elif arg is None:
                a = ""
            else:
                a = str(arg)
            lines.append("  %05x: %-11s %-12s%s" % (pc, mn, a, ann))
        return lines

    # ----------------------------------------------------------- registre module
    def registry_candidates(self, min_consts=10):
        """class_def qui declarent beaucoup de constantes de module."""
        out = []
        for off, cls in self.classes.items():
            consts = [f for f in cls["fields"] if f["type_name"] == "Module"]
            msgs = [f for f in cls["fields"] if f["type_name"] == "Class"
                    and f["value"] in self.classes]
            if len(msgs) >= min_consts or len(consts) >= min_consts:
                out.append((off, cls, consts, msgs))
        out.sort(key=lambda t: -(len(t[2]) + len(t[3])))
        return out

    def load_apk_map(self, path):
        ids = {}
        if not os.path.exists(path):
            return ids
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = re.search(r"(PHONE_COMMAND_\w+|[A-Z][A-Z0-9_]{3,})\D{0,4}?(\d{1,3})\b", line)
                if m:
                    ids.setdefault(int(m.group(2)), set()).add(m.group(1))
                    continue
                m = re.search(r"\b(\d{1,3})\D{0,4}?(PHONE_COMMAND_\w+|[A-Z][A-Z0-9_]{3,})", line)
                if m:
                    ids.setdefault(int(m.group(1)), set()).add(m.group(2))
        return {k: sorted(v) for k, v in ids.items()}


# ----------------------------------------------------------------------- modes
def cmd_registry(p, args):
    apk = p.load_apk_map(args.map)
    for off, cls, consts, msgs in p.registry_candidates():
        print("=== class_def @data+%#05x  module=%s parent=%s  (%d constantes, %d classes message)"
              % (off, cls.get("module_id"), cls.get("parent_module_id"), len(consts), len(msgs)))
        for f in consts:
            code = f["value"]
            used = sum(len(v) for k, v in p.module_sym_uses.items()
                       if k == (cls.get("module_id"), f["symbol"])) if hasattr(p, "module_sym_uses") else None
            names = ", ".join(apk.get(code, []))
            print("  code %3d (0x%02x)  sym=%-5d %s" % (code, code, f["symbol"],
                                                        ("[apk: %s]" % names) if names else ""))
        for f in msgs:
            print("  message sym=%-5d -> class @data+%#05x  nom=%s"
                  % (f["symbol"], f["value"], p.class_name(f["value"]) or "?"))
    return 0


def build_callgraph(p):
    """Graphe d'appel inter-methodes d'une meme classe.

    Le P-code Garmin appelle une methode de la classe courante en empilant son
    indice de symbole (`getselfv <sym>` / `spush <sym>` / `getsv <sym>`) puis
    `invoke`/`invokemz`. On relie donc chaque site vers le symbole qui, dans la
    classe englobante, designe un champ Method.
    """
    callers = collections.defaultdict(list)   # code+entree appelee -> [(pc, appelee)]
    for i, pc in enumerate(p.method_pcs):
        end = p.method_pcs[i + 1] if i + 1 < len(p.method_pcs) else len(p.code)
        cls_off, sym_self, flags = p.methods[pc]
        own = {s: f for s, fl, q in p.methods_by_class.get(cls_off, ())
               for f in p.classes[cls_off]["fields"]
               if f["type_name"] == "Method" and f["symbol"] == s}
        for q, mn, arg, ann in p.disasm(pc, end):
            if mn not in ("getselfv", "spush", "getsv") or not isinstance(arg, int):
                continue
            if arg in own:
                # methode de la classe englobante (slot virtuel surcharge): sans ambiguite
                cands = [(cls_off, own[arg])]
            else:
                cands = [(o, f) for o, f in p.sym_fields.get(arg, ())
                         if f["type_name"] == "Method"]
            for coff, f in cands:
                if f["value"] == 0x10000000 or arg >= 0x800000:
                    continue
                callers[f["value"] & 0x0FFFFFFF].append((q, pc, mn, coff != cls_off))
    p.callers = callers
    return callers


def cmd_callers(p, args):
    """Qui appelle la methode situee a l'adresse donnee (remonte l'arbre d'appel)."""
    build_callgraph(p)
    todo = [(int(a, 0), 0) for a in args.args]
    seen = set()
    while todo:
        pc, depth = todo.pop(0)
        if pc in seen:
            continue
        seen.add(pc)
        cls_off, sym, flags = p.methods[pc]
        print("%scode+%#06x  class @data+%#05x  meth %s(%d) flags=%d  [%s]"
              % ("    " * depth, pc, cls_off, p.api.get(sym, str(sym)), sym, flags,
                 p.class_name(cls_off) or "?"))
        for q, caller, mn, amb in p.callers.get(pc, ()):
            print("%s    appelee depuis code+%#06x  (%s de class @data+%#05x, meth %s)%s"
                  % ("    " * depth, q, mn, p.methods[caller][0],
                     p.api.get(p.methods[caller][1], p.methods[caller][1]),
                     "  [symbole partage]" if amb else ""))
            for r, m2, arg2, ann2 in p.disasm(caller):
                if r < q - 60 or r > q + 10:
                    continue
                a2 = "%d %d" % arg2 if isinstance(arg2, tuple) else ("" if arg2 is None else str(arg2))
                print("%s      %05x: %-11s %-12s%s" % ("    " * depth, r, m2, a2, ann2))
            todo.append((caller, depth + 1))
    return 0


def cmd_body(p, args):
    """Listing d'une methode, puis de tout ce qu'elle appelle en amont."""
    for a in args.args:
        pc = int(a, 0)
        m = p.methods.get(pc) or p.method_at(pc)
        pc = m[0]
        cls_off, sym, flags = p.methods[pc]
        print("=== methode code+%#06x  class @data+%#05x  meth %s(%d) ===" % (pc, cls_off, p.api.get(sym, str(sym)), sym))
        print("\n".join(p.listing(pc)))
    return 0


def build_uses(p):
    """Tous les getmv du programme: (module, sym) -> [(pc, methode, classe)]."""
    uses = collections.defaultdict(list)
    for i, pc in enumerate(p.method_pcs):
        end = p.method_pcs[i + 1] if i + 1 < len(p.method_pcs) else len(p.code)
        for q, mn, arg, ann in p.disasm(pc, end):
            if mn == "getmv" and isinstance(arg, tuple):
                uses[arg].append((q, pc))
    p.module_sym_uses = uses
    return uses


def cmd_uses(p, args):
    """Sites d'appel des constantes de module d'une classe (defaut: registre 38)."""
    build_uses(p)
    apk = p.load_apk_map(args.map)
    only = {int(x, 0) for x in args.args} if args.args else None
    for off, cls, consts, msgs in p.registry_candidates():
        mod = cls.get("module_id")
        print("=== class_def @data+%#05x module=%s ===" % (off, mod))
        for f in consts + msgs:
            key = (mod, f["symbol"])
            sites = p.module_sym_uses.get(key, [])
            if f["type_name"] == "Module":
                label = "code %3d (0x%02x)" % (f["value"], f["value"])
                extra = ", ".join(apk.get(f["value"], []))
            else:
                label = "message %-30s" % (p.class_name(f["value"]) or "?")
                extra = "class @data+%#05x" % f["value"]
            if only is not None and f["type_name"] == "Module" and f["value"] not in only:
                continue
            if only is not None and f["type_name"] != "Module":
                continue
            mark = "UTILISE %2dx" % len(sites) if sites else "   -----   "
            print("  %s  %-34s sym=%-5d %s" % (mark, label, f["symbol"], extra))
            for q, mstart in sites:
                m = p.methods[mstart]
                print("        code+%#06x  (methode %s de class @data+%#05x)"
                      % (q, m[1], m[0]))
    return 0


def cmd_cls(p, args):
    for a in args.args:
        off = int(a, 0)
        cls = p.classes.get(off)
        if cls is None:
            print("class_def introuvable @data+%s" % a)
            continue
        print("=== class_def @data+%#05x module=%s parent=%s nom=%s"
              % (off, cls.get("module_id"), cls.get("parent_module_id"),
                 p.class_name(off) or "?"))
        print("  champs protobuf: %s" % ", ".join(p.message_fields(off)))
        for f in cls["fields"]:
            print("  sym=%-8d %-8s flags=%d value=%#x" % (f["symbol"], f["type_name"], f["flags"], f["value"]))
        for sym, flags, pc in p.methods_by_class.get(off, ()):
            print("--- methode sym=%d flags=%d @code+%#x ---" % (sym, flags, pc))
            print("\n".join(p.listing(pc)))
    return 0


def cmd_method(p, args):
    for a in args.args:
        pc = int(a, 0)
        if pc not in p.methods:
            m = p.method_at(pc)
            if m:
                pc = m[0]
        print("=== methode @code+%#x %s ===" % (pc, p.methods.get(pc)))
        print("\n".join(p.listing(pc)))
    return 0


def cmd_grep(p, args):
    pat = re.compile(args.args[0])
    build_uses(p)
    for i, pc in enumerate(p.method_pcs):
        end = p.method_pcs[i + 1] if i + 1 < len(p.method_pcs) else len(p.code)
        hits = [l for l in p.listing(pc, end) if pat.search(l)]
        if hits:
            cls_off, sym, flags = p.methods[pc]
            print("### methode @code+%#05x class @data+%#05x nom=%s sym=%d  (%d hits)"
                  % (pc, cls_off, p.class_name(cls_off) or "?", sym, len(hits)))
            for h in hits[:40]:
                print(h)
    return 0


def cmd_msgs(p, args):
    build_uses(p)
    rows = []
    for off, cls in sorted(p.classes.items()):
        nm = p.class_name(off)
        if not nm:
            continue
        flds = p.message_fields(off)
        # qui instancie cette classe ?
        inst = []
        for mod, sym in p.module_sym_uses:
            r = p.resolve_module_sym(mod, sym)
            if r and r[1]["type_name"] == "Class" and r[1]["value"] == off:
                inst.extend(p.module_sym_uses[(mod, sym)])
        rows.append((off, nm, flds, len(inst)))
    for off, nm, flds, n in rows:
        print("class @data+%#05x  %-30s instanciée %dx  champs: %s" % (off, nm, n, ", ".join(flds)))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg")
    ap.add_argument("mode", nargs="?", default="registry")
    ap.add_argument("--map", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "apk_extract", "message_code_map.txt"))
    ap.add_argument("--api-db", default=None,
                    help="api.db du SDK (defaut: premier SDK trouve dans ~/.Garmin/ConnectIQ/Sdks)")
    ap.add_argument("args", nargs="*")
    args = ap.parse_args()
    db = args.api_db
    if db is None:
        root = os.path.expanduser("~/.Garmin/ConnectIQ/Sdks")
        cands = sorted(glob.glob(os.path.join(root, "*", "bin", "api.db")))
        db = cands[-1] if cands else None
    p = Prg(args.prg, db)
    print("# api.db: %s (%d identifiants)" % (db, len(p.api)))
    if args.mode == "registry":
        return cmd_registry(p, args)
    if args.mode == "uses":
        return cmd_uses(p, args)
    if args.mode == "cls":
        return cmd_cls(p, args)
    if args.mode == "method":
        return cmd_method(p, args)
    if args.mode == "grep":
        return cmd_grep(p, args)
    if args.mode == "msgs":
        return cmd_msgs(p, args)
    if args.mode == "callers":
        return cmd_callers(p, args)
    if args.mode == "body":
        return cmd_body(p, args)
    print("mode inconnu: %s" % args.mode)
    return 1


if __name__ == "__main__":
    sys.exit(main())
