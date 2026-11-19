"""Sorte des produits du manifest d'une app ConnectIQ, avec le motif en base de donnees.

usage: python drop_products.py [--apply] <manifest> <id> [<id> ...]

Le script ne touche que les lignes <iq:product id="..."/> qui portent exactement un
des ids donnes ; il imprime ce qu'il retire et ce qu'il garde a cote (les variantes
voisines), pour que le controle reste lisible.
"""
import re
import sys

USAGE = __doc__


def main(argv):
    apply_ = '--apply' in argv
    argv = [a for a in argv if a != '--apply']
    if len(argv) < 2:
        print(USAGE)
        return 2
    path, ids = argv[0], set(argv[1:])
    lines = open(path, encoding='utf-8').read().split('\n')
    pat = re.compile(r'<iq:product id="([^"]+)"')
    kept, dropped = [], []
    for i, line in enumerate(lines, 1):
        m = pat.search(line)
        if m and m.group(1) in ids:
            dropped.append((i, m.group(1)))
        else:
            kept.append(line)
    before = sum(1 for l in lines if pat.search(l))
    print('produits avant: %d, retires: %d, apres: %d' % (before, len(dropped), before - len(dropped)))
    for i, d in dropped:
        print('  ligne %d: %s' % (i, d))
    missing = ids - set(d for _, d in dropped)
    if missing:
        print('  ABSENTS du manifest (non touches): %s' % ', '.join(sorted(missing)))
    if apply_:
        open(path, 'w', encoding='utf-8', newline='').write('\n'.join(kept))
        print('APPLIQUE dans %s' % path)
    else:
        print('a sec (relancer avec --apply)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
