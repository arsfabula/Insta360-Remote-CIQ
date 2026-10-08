import sys, os, re, random
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tools'))
import insta360_ucd2 as u
txt = open(os.path.join(os.environ['TEMP'], 'opencode', 'x6', 'trailer.txt'), encoding='utf-8').read()
mstart = re.search(r'const ucd2TrailStart = \[(.*?)\]b;', txt, re.S)
mstop  = re.search(r'const ucd2TrailStop  = \[(.*?)\]b;', txt, re.S) or re.search(r'const ucd2TrailStop = \[(.*?)\]b;', txt, re.S)
def parse(m):
    vals = [int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{2})', m.group(1))]
    assert len(vals) == 256 * 4
    return vals
S, P = parse(mstart), parse(mstop)
random.seed(3)
ok = True
for _ in range(200):
    seq = random.randrange(256)
    s = u.build_file_command(seq, u.CMD_START_CAPTURE, 1)
    p = u.build_file_command(seq, u.CMD_STOP_CAPTURE, 1)
    ok &= bytes(S[seq * 4:seq * 4 + 4]) == s[-4:]
    ok &= bytes(P[seq * 4:seq * 4 + 4]) == p[-4:]
print("start seq0 :", bytes(S[0:4]).hex(), "ok:", bytes(S[0:4]).hex() == "5b4d4b5a")
print("start 0x24 :", bytes(S[0x24 * 4:0x24 * 4 + 4]).hex(), "ok:", bytes(S[0x24 * 4:0x24 * 4 + 4]).hex() == "8472946e")
print("stop  seq0 :", bytes(P[0:4]).hex(), "ok:", bytes(P[0:4]).hex() == "45fa0bf1")
print("ALL MATCH" if ok else "MISMATCH")