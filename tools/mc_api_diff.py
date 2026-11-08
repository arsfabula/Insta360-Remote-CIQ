#!/usr/bin/env python3
"""Compare la surface Toybox d'un fichier avec celle des projets deja montres sur
la montre, et verifier deux choses:

1. un appel, ou le nombre d'arguments d'un appel, qui n'apparait nulle part
   ailleurs est le candidat exact d'un 'Too Many Arguments Error' du simulateur;
2. un callback herite (onStart, onUpdate, onScanResults, ...) doit se declarer
   avec le nombre de parametres que le framework transmet. Le simulateur ne nomme
   jamais le symbole fautif: il designe la premiere ligne du callback.

Usage: python3 tools/mc_api_diff.py <fichier.mc> [references.mc ...]
       python3 tools/mc_api_diff.py --tous      (chaque .mc du depot, corrigé par
                                                 les autres, pour le bilan complet)
"""
import re
import sys
import os

NEST = re.compile(r"\.(\w+)\s*\(")
MOD = re.compile(r"\b(BluetoothLowEnergy|Positioning|Activity|Application|WatchUi|System|Communications|Memory|Time|Graphics|Profiling)\s*\.\s*(\w+)\s*\(")


def scrub(src):
    src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*[\s\S]*?\*/", "", src)
    return src


def count_args(code, i):
    """i = index de la parenthese ouvrante."""
    depth = 0
    commas = 0
    empty = True
    j = i
    pairs = {")": "(", "]": "[", "}": "{"}
    while j < len(code):
        c = code[j]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if c == ")" and depth == 0:
                return commas + 1 if not empty else 0
            if depth < 0:
                return None
        elif c == "," and depth == 1:
            commas += 1
            empty = False
        elif not c.isspace():
            empty = False
        j += 1
    return None


def calls(path):
    code = scrub(open(path, encoding="utf-8", errors="replace").read())
    out = {}
    for m in NEST.finditer(code):
        nb = count_args(code, m.end() - 1)
        if nb is None:
            continue
        out.setdefault(m.group(1), set()).add(nb)
    for m in MOD.finditer(code):
        nb = count_args(code, m.end() - 1)
        if nb is None:
            continue
        out.setdefault(m.group(2), set()).add(nb)
    return out


DECL = re.compile(r"\bfunction\s+(\w+)\s*\(([^)]*)\)")

# Noms que le framework Garmin appelle lui-meme: un callback herite DOIT se
# declarer avec le nombre de parametres transmis, sinon le simulateur plante avec
# 'Too Many Arguments Error' en designant la premiere ligne du callback, sans
# jamais nommer le symbole. Un nom hors de cette liste qui differe des references
# est un constructeur local, pas un callback: le signaler serait du bruit.
CALLBACKS = frozenset("""
initialize onStart onStop getInitialView onStartCommand stopActivity onNewPassword
onUnlock onGlobalUpdate onPartialUpdate onProgressCancel onUpdate onShow onHide
onLayout onPolicy onSettings onHiddenOnBackButton onMenu onSelect onBackButton
onConfirm onApply onKey onNextPage onPreviousPage onShowPage onOrientationChange
setScanResults setDeviceName passService passCharacteristic passDescriptor
pairDevice connectDevice disconnectDevice deviceUnavailable setConnectionState
setDeviceType setDeviceNotPairable onScanResults onConnectedStateChanged
onCharacteristicChanged onCharacteristicWrite onDescriptorWrite onScanStateChange
onProfileRegister onMtuChange onConnectionPriorityChanged onPairingRequest
onPairingAttempted onPairingStatusChanged onReceiveData onSentData
""".split())


def declared(path):
    """[nom, nombre de parametres] pour chaque fonction declaree du fichier."""
    code = scrub(open(path, encoding="utf-8", errors="replace").read())
    out = {}
    for m in DECL.finditer(code):
        params = [p.strip() for p in m.group(2).split(",") if p.strip()]
        out.setdefault(m.group(1), set()).add(len(params))
    return out


def main(argv):
    if len(argv) < 3:
        if len(argv) == 2 and argv[1] == "--tous":
            allmc = [os.path.join(r, f) for r, d, fs in os.walk(".") for f in fs
                     if f.endswith(".mc") and ".git" not in r]
            for target in sorted(allmc):
                refs = [p for p in allmc if p != target and "conflict" not in p]
                argv = [argv[0], target] + refs
                main(argv)
                print()
            return 0
        print(__doc__)
        return 2
    target = argv[1]
    refs = argv[2:]
    if not refs:
        refs = [os.path.join(r, f) for r, d, fs in os.walk(".") for f in fs
                if f.endswith(".mc") and os.path.join(r, f) != target]
    t = calls(target)
    mine = declared(target)
    known = {}
    known_decl = {}
    for p in refs:
        for name, arity in calls(p).items():
            known.setdefault(name, set()).update(arity)
        for name, nb in declared(p).items():
            known_decl.setdefault(name, set()).update(nb)
    own = set()
    for name, nb in mine.items():
        if name in known_decl:
            continue
        own.add(name)
    print("== %s" % target)
    print("   references: %d fichier(s)" % len(refs))
    unseen = []
    for name, arity in sorted(t.items()):
        if name in own:
            continue
        if name not in known:
            unseen.append("   appel: '%s' employe avec %s argument(s) - jamais vu dans les references"
                          % (name, "/".join(str(a) for a in sorted(arity))))
        elif not arity <= known[name]:
            unseen.append("   appel: '%s' employe avec %s argument(s) - les references ne font que %s"
                          % (name, "/".join(str(a) for a in sorted(arity)),
                             "/".join(str(a) for a in sorted(known[name]))))
    for name, nb in sorted(mine.items()):
        if name not in CALLBACKS or name not in known_decl:
            continue
        if not nb <= known_decl[name]:
            unseen.append("   callback herite: '%s' declare %s parametre(s) - les projets montres "
                          "le declarent avec %s (le framework appelle avec ce nombre: "
                          "'Too Many Arguments Error')"
                          % (name, "/".join(str(a) for a in sorted(nb)),
                             "/".join(str(a) for a in sorted(known_decl[name]))))
    if unseen:
        print("\n".join(unseen))
    else:
        print("   chaque appel et chaque callback herite se retrouvent dans les references, "
              "avec le meme nombre d'arguments")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
