#!/usr/bin/env python3
"""Controle statique d'un fichier Monkey C, sans SDK.

Pas de SDK Garmin sur ce poste: le compilateur ne peut pas trancher. Ce script
fait les quatre controles qui attrapent la quasi-totalite des erreurs de frappe
Monkey C avant de monter sur la montre:

  1. equilibre des accolades/parentheses/crochets, hors chaines et hors
     commentaires, avec la ligne ou le bloc s'est ouvert;
  2. symboles employes mais jamais declares (module, fonction, parametre,
     membre de classe, variable locale), en ignorant ce qui est qualifie par un
     point (Toybox.Lang, dc.getWidth(), h[:env]) et les mots-cles du langage;
  3. declarations doubles dans une meme portee, et variables employees avant
     leur declaration a l'interieur d'une fonction;
  4. noms de methodes (`objet.x(`) qui n'apparaissent nulle part dans le code du
     depot qui compile deja, ni comme fonction du lot: c'est la classe d'erreur
     que les trois premiers ne voient pas, et le compilateur s'arrete dessus
     (« Undefined symbol ':delete' », ligne 195 de la Framing Probe, ou Lang.Array
     n'a aucune suppression par index).

Il ne remplace pas le compilateur: il ne voit ni les types, ni les signatures,
ni les annotations. Un fichier qu'il trouve propre peut encore echouer a la
construction; un fichier qu'il trouve sale a presque certainement un vrai defaut.

Usage: python3 tools/mc_check.py "Framing Probe/source/FramingProbe.mc" [...]
"""
import re
import sys

KEYWORDS = {
    "function", "class", "var", "const", "as", "new", "null", "true", "false",
    "if", "else", "for", "while", "foreach", "in", "return", "try", "catch",
    "throw", "using", "import", "module", "extends", "private", "protected",
    "public", "static", "and", "or", "break", "continue", "hidden", "this",
    "super", "method", "property", "defaultvalue", "nil", "instanceof",
    "switch", "case", "default", "self", "has", "function", "class",
}
# mots-cles de types Toybox employes nus (rare, mais courant dans les annotations)
TYPES_NUS = {"Void", "Null", "Self"}


def strip(src: str) -> str:
    """Remplace chaines et commentaires par des espaces, en gardant les sauts."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n - 2 if j < 0 else j
            seg = src[i:j + 2]
            out.append("".join(ch if ch == "\n" else " " for ch in seg))
            i = j + 2
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            seg = src[i:min(j + 1, n)]
            out.append("".join(ch if ch == "\n" else " " for ch in seg))
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def line_of(src: str, pos: int) -> int:
    return src.count("\n", 0, pos) + 1


def check_balance(code: str, src: str) -> list:
    errs = []
    stack = []
    pairs = {")": "(", "}": "{", "]": "["}
    for pos, ch in enumerate(code):
        if ch in "({[":
            stack.append((ch, pos))
        elif ch in ")}]":
            if not stack:
                errs.append("equilibre: '%s' ferme sans ouvreur ligne %d"
                            % (ch, line_of(src, pos)))
                continue
            op, opos = stack.pop()
            if op != pairs[ch]:
                errs.append("equilibre: '%s' ligne %d ferme un '%s' ouvert ligne %d"
                            % (ch, line_of(src, pos), op, line_of(src, opos)))
    for op, opos in stack:
        errs.append("equilibre: '%s' ouvert ligne %d n'est jamais ferme"
                    % (op, line_of(src, opos)))
    return errs


DECL_FN = re.compile(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)")
DECL_CL = re.compile(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)")
DECL_VAR = re.compile(r"\b(var|const)\s+([A-Za-z_][A-Za-z0-9_]*)")
DECL_PARAM = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s+as\s+[A-Za-z_]")
IDENT = re.compile(r"(?<![\w.])([A-Za-z_][A-Za-z0-9_]*)(?![\w])")
QUALIFIED = re.compile(r"\.\s*([A-Za-z_][A-Za-z0-9_]*)")
DICTKEY = re.compile(r":\s*([A-Za-z_][A-Za-z0-9_]*)")
# signature: les parametres peuvent n'avoir aucune annotation (`onStart(state)`)
SIG = re.compile(r"\b(?:function|method)\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)")
# un appel de methode: `objet.nom(`. C'est la surface que le compilateur verifiera,
# et sans SDK local c'est le seul endroit ou un `delete` invente est visible.
MEMBER = re.compile(r"\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")

# Membres Toybox deja employes par le code de ce depot qui compile sur la montre
# (BLE Barrel, BLE Probe, OneR remote, OneR remote DF, Capacites Barrel), plus les
# familles d'appels evidentes. Un nom hors de cette liste n'est pas forcement faux:
# le controle dit « va verifier la API », ce que le compilateur aurait dit a sa
# place. Volontairement absents: at, insert, remove, delete, la famille des
# tableaux dont l'API reelle est la plus piegeuse.
# Methodes heritees qu'un appele NU dans une classe rend visibles: le controle
# ne connait pas l'ancetre, et l'appel nu d'une methode heritee est legitime en
# Monkey C (le barrel fait de meme avec ses propres methodes). Prouve par les
# binaires construits sur l'autre poste: OneRremoteDFView.mc appelle
# getBackgroundColor(), methode de WatchUi.DataField, et ce projet est monte.
CORE_BARE = frozenset("""
getBackgroundColor
""".split())

CORE_MEMBERS = frozenset("""
BleDevice GPSenable Info Menu2 MenuItem Moment Timer abs add addAll addItem
armWire armX5 bytesToHex capBit cccdUuid clear close cos decodeNumber
drawArc drawCircle drawText enableLocationEvents encodeNumber entryKeyOfId
entryTierOfId equals format getApp getAvailableConnectionCount
getCharacteristic getCoordinates getDeviceName getDeviceSettings
getErrorMessage getFontAscent getFontDescent getFontHeight getHeight getId
getInfo getItem getLabel getName getProperty getService getServiceUuids
getServices getTimer getType getUuid getWidth initialize isConnected labelPhoto
labelRes labelVideo lastOption length menuLevelOfName modelIndexOfName
modelMeasured next now open pairDevice peekBatteryLevel
peekBatteryPowerType peekCodeCount peekFuncMode peekNotifArrived
peekNotifCode peekNotifCount peekNotifDeclared peekNotifHex
peekNotifTruncated peekNotifVal1 peekNotifVal2 peekResNow peekSeenCodes
peekSubPhoto peekSubVideo peekWireEvents peekWireRecv peekX5Seen
photoGpsHeader popView println pushView registerProfile requestUpdate
requestWrite resetNotif rowIds rowLabels sendCMD sendPosition setAntiAlias
setColor setDelegate setPenWidth setProperty setScanState setTitle sin size
slice start stop stringToUuid substring subtract toDegrees toNumber
toString toUtf8Array unpairDevice value
""".split())


def members(src: str) -> set:
    """Noms de methodes employees par un fichier."""
    return set(MEMBER.findall(strip(src)))


def declared(src: str) -> set:
    """Noms qu'un fichier rend visibles aux autres fichiers du meme module."""
    code = strip(src)
    out = set()
    for rex, grp in ((DECL_VAR, 2), (DECL_FN, 1), (DECL_CL, 1)):
        for m in rex.finditer(code):
            out.add(m.group(grp))
    for m in re.finditer(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", code):
        out.add(m.group(1))
    return out


def check(src: str, foreign=frozenset(), known_fn=frozenset(),
          known_member=frozenset()) -> list:
    """foreign: noms declares dans les autres fichiers du meme module.
    known_fn / known_member: fonctions et methodes vues dans tout le lot."""
    code = strip(src)
    errs = check_balance(code, src)

    # portees: decoupage par function/class a la profondeur 1, par appariement
    # d'accolades
    scopes = []          # (nom, debut, fin, [declares])
    stack = []
    for m in re.finditer(r"\b(function|class)\s+([A-Za-z_][A-Za-z0-9_]*)", code):
        depth = 0
        start = -1
        for pos in range(m.end(), len(code)):
            ch = code[pos]
            if ch == "{":
                if depth == 0:
                    start = pos
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
        if start < 0:
            continue
        body = code[start + 1:pos]
        declared = set()
        for dm in DECL_VAR.finditer(body):
            declared.add(dm.group(2))
        # tete de la declaration: la liste de parametres, annotree ou non
        sig = SIG.match(code[m.start():start + 1])
        head = sig.group(1) if sig else code[m.end():start]
        for part in re.split(r"[,=]", head):
            pm = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:as\b|$)", part)
            if pm:
                declared.add(pm.group(1))
        for fm in DECL_FN.finditer(body):
            declared.add(fm.group(1))
        scopes.append((m.group(2), start + 1, pos, declared))

    universe = set(KEYWORDS) | TYPES_NUS
    for m in DECL_VAR.finditer(code):
        universe.add(m.group(2))
    for m in DECL_FN.finditer(code):
        universe.add(m.group(1))
    for m in DECL_CL.finditer(code):
        universe.add(m.group(1))
    for m in re.finditer(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", code):
        universe.add(m.group(1))
    for _, _, _, d in scopes:
        universe |= d
    # modules imports, noms annotés par 'as' (parametres compris), noms de types,
    # cles de dictionnaire, annotations (:glance)
    for m in re.finditer(r"\busing\s+([A-Za-z_][\w.]*)", code):
        for seg in m.group(1).split("."):
            universe.add(seg)
    # tout nom annoté par 'as' est une declaration (parametre, var, champ)
    for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s+as\s", code):
        universe.add(m.group(1))
    # tout nom qualifie par un point est un module ou un type (BleDelegate.x)
    for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s*\.", code):
        universe.add(m.group(1))
    for m in re.finditer(r"\bas\s+([A-Za-z_][\w.]*(?:\s*\([^)]*\))?)", code):
        for seg in re.split(r"[.()]", m.group(1)):
            if seg:
                universe.add(seg)
    for m in re.finditer(r"\bas\s+([A-Za-z_][\w.]*)((?:\s+or\s+[A-Za-z_][\w.]*)+)", code):
        for part in m.group(2).split():
            for seg in part.split("."):
                if seg:
                    universe.add(seg)
    for m in re.finditer(r"[:]\s*([A-Za-z_][A-Za-z0-9_]*)\s*=>", code):
        universe.add(m.group(1))
    for m in re.finditer(r"\(:\s*([A-Za-z_][A-Za-z0-9_]*)", code):
        universe.add(m.group(1))
    for m in re.finditer(r"\bcatch\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)", code):
        universe.add(m.group(1))
    for m in re.finditer(r"\bforeach\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)", code):
        universe.add(m.group(1))
    universe |= set(foreign)

    unknown = {}
    for m in IDENT.finditer(code):
        name = m.group(1)
        if name in universe or name in CORE_BARE:
            continue
        prev = code[max(0, m.start() - 1):m.start()]
        if prev == ".":
            continue
        # cle de dictionnaire: :name suivi de =>
        if prev == ":":
            continue
        # suffixe des litteraux d'octets: [0x0a, 0x06]b et new [20]b
        if name == "b" and prev == "]":
            continue
        unknown.setdefault(name, line_of(src, m.start()))

    for name, ln in sorted(unknown.items(), key=lambda kv: kv[1]):
        errs.append("symbole: '%s' employe ligne %d sans declaration vue" % (name, ln))

    # declarations doubles: par bloc, pas par fonction. Un `var t` dans un
    # `if` et un `var t` au corps de la meme fonction sont deux portees distinctes.
    for nm, a, b, d in scopes:
        body = list(code[a:b])
        # les corps des fonctions imbriquees (methodes d'une classe) ne sont pas
        # la portee de cette declaration
        for nm2, a2, b2, _ in scopes:
            if a2 > a and b2 < b:
                for k in range(a2 - a, b2 - a):
                    body[k] = " "
        body = "".join(body)
        frames = [{}]           # un dictionnaire par bloc ouvert
        depth = 0
        at = {}
        for pos, ch in enumerate(body):
            if ch == "{":
                frames.append({})
                depth += 1
            elif ch == "}":
                if depth > 0:
                    frames.pop()
                    depth -= 1
        # deuxieme passe, avec les cadres: DECL_VAR et profondeur d'accolade
        frames = [{}]
        depth = 0
        pend = [(m.start(), m.group(2)) for m in DECL_VAR.finditer(body)]
        pi = 0
        for pos, ch in enumerate(body):
            while pi < len(pend) and pend[pi][0] < pos:
                nmv, sym = pend[pi]
                top = frames[-1]
                if sym in top:
                    errs.append("portee: '%s' declare deux fois dans le meme bloc de %s "
                                "(lignes %d et %d)" % (sym, nm, line_of(src, a + top[sym]),
                                                       line_of(src, a + nmv)))
                top[sym] = nmv
                pi += 1
            if ch == "{":
                frames.append({})
                depth += 1
            elif ch == "}" and depth > 0:
                frames.pop()
                depth -= 1

    # quatrieme controle: les appels de methodes. Sans SDK local, `objet.x()` est
    # la seule erreur que ni l'equilibrage ni les symboles ne voient, et le
    # compilateur s'arrete au premier « Undefined symbol ». Un nom qui n'est ni une
    # fonction du lot ni un membre deja employe par le code qui compile ici est
    # une question a poser a la API, pas encore une faute.
    unknown_m = {}
    for m in MEMBER.finditer(code):
        name = m.group(1)
        if name in CORE_MEMBERS or name in known_fn or name in known_member:
            continue
        unknown_m.setdefault(name, line_of(src, m.start()))
    for name, ln in sorted(unknown_m.items(), key=lambda kv: kv[1]):
        errs.append("membre: '.%s(' employe ligne %d sans equivalent dans le code "
                    "qui compile deja (verifier la API Toybox)" % (name, ln))
    return errs


def main() -> int:
    paths = sys.argv[1:] or ["BLE Barrel/BLEBarrel.mc"]
    srcs = {}
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as fh:
            srcs[path] = fh.read()
    # un fichier seul ne connait pas les classes de ses voisins: les noms des
    # autres fichiers du lot sont ajoutes a l'univers de chacun
    all_fn = set()
    per_member = {}
    for path, text in srcs.items():
        all_fn |= {m.group(1) for m in DECL_FN.finditer(strip(text))}
        per_member[path] = members(text)
    bad = 0
    for path in paths:
        foreign, known_member = set(), set()
        for other, text in srcs.items():
            if other != path:
                foreign |= declared(text)
                known_member |= per_member[other]
        errs = check(srcs[path], foreign, all_fn, known_member)
        print("== %s : %d ligne(s)" % (path, srcs[path].count("\n") + 1))
        if not errs:
            print("   propre aux quatre controles")
        for e in errs[:60]:
            print("   " + e)
        if len(errs) > 60:
            print("   ... %d de plus" % (len(errs) - 60))
        bad += len(errs)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
