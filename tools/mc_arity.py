#!/usr/bin/env python3
"""Controle d'arithmetique des appels: un appel d'une fonction declaree dans le
meme fichier ne doit ni donner plus ni donner moins d'arguments que sa
declaration. C'est la classe exacte de 'Too Many Arguments Error' que le
simulateur Garmin signale sans dire ou.

Usage: python3 tools/mc_arity.py [fichier.mc ...]   (defaut: tous les .mc du depot)

Limites annoncees: ne connait pas les methodes heritees de Toybox (controle
separe: tools/mc_check.py), et ne suit pas les method(:sym) au-dela du premier
appel. Un appel a travers un objet est compte s'il porte le nom d'une fonction
declaree dans le fichier (les methodes homonymes d'un barrel ne sont pas vues).
"""
import re
import sys
import os

STR = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
FUN = re.compile(r"\bfunction\s+(\w+)\s*\(([^)]*)\)\s*(?:as\b[^;{]*)?\{")
CALL = re.compile(r"(\w+)\s*\(")


def scrub(src: str) -> str:
    """Vide chaines, octets et commentaires, en gardant les positions."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append('""' if j >= n else src[i:j + 1])
            i = j + 1
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def arity(src: str):
    """[nom, params, ligne] des fonctions declarees."""
    got = []
    for m in FUN.finditer(src):
        params = [p.strip() for p in m.group(2).split(",") if p.strip()]
        got.append((m.group(1), len(params), src[:m.start()].count("\n") + 1))
    return got


def args_at(code: str, open_paren: int):
    """Nombre d'arguments de l'appel dont la parenthese ouvrante est a open_paren.
    Renvoie (nb, fin) ou (None, fin) si l'appel a une syntaxe particuliere."""
    depth = {"(": 0, "[": 0, "{": 0}
    CLOSE = {")": "(", "]": "[", "}": "{"}
    i = open_paren
    commas = 0
    empty = True
    while i < len(code):
        c = code[i]
        if c in "([{":
            depth[c] += 1
        elif c in ")]}":
            op = CLOSE[c]
            depth[op] -= 1
            if c == ")" and depth["("] == 0:
                return (commas + 1 if not empty else 0), i
            if depth["("] < 0:
                return None, i
        elif c == ",":
            if depth["["] == 0 and depth["{"] == 0 and depth["("] == 1:
                commas += 1
                empty = False
        elif c == ":" and depth["{"] > 0:
            pass
        elif not c.isspace():
            empty = False
        i += 1
    return None, i


def line_of(src, pos):
    return src[:pos].count("\n") + 1


def check(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    code = scrub(raw)
    code = STR.sub('""', code)
    decl = {}
    for name, nb, ln in arity(code):
        decl.setdefault(name, []).append((nb, ln))
    errs = []
    for m in CALL.finditer(code):
        name = m.group(1)
        if name not in decl:
            continue
        before = code[:m.start()].rstrip()
        if before.endswith("."):           # appel de methode d'un objet
            continue
        if re.search(r"\bfunction\s*$", before):
            continue                        # declaration
        if re.search(r"\bmethod\s*\(:\s*$", before):
            continue                        # reference de methode
        nb, _ = args_at(code, m.end() - 1)
        if nb is None:
            continue
        for want, ln in decl[name]:
            if nb < want:
                errs.append("trop peu: '%s' appelle ligne %d avec %d argument(s), "
                            "declare %d ligne %d" % (name, line_of(raw, m.start()), nb, want, ln))
            elif nb > want:
                errs.append("TROP: '%s' appelle ligne %d avec %d argument(s), "
                            "declare %d ligne %d" % (name, line_of(raw, m.start()), nb, want, ln))
    return errs


def main(argv):
    files = []
    if len(argv) > 1:
        files = argv[1:]
    else:
        for root, dirs, fs in os.walk("."):
            if ".git" in root:
                continue
            for f in fs:
                if f.endswith(".mc"):
                    files.append(os.path.join(root, f))
    bad = 0
    for p in sorted(files):
        errs = check(p)
        print("== %s" % p)
        if not errs:
            print("   arithmetique des appels: propre")
        else:
            bad += 1
            for e in dict.fromkeys(errs):
                print("   " + e)
    print("\nfichiers signales: %d / %d" % (bad, len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
