import sys, os, re, random
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tools'))
import insta360_ucd2 as u
txt = open(os.path.join(os.environ['TEMP'], 'opencode', 'x6', 'trailer.txt'), encoding='utf-8').read()
ms = re.search(r'const ucd2TrailStartHex = "([0-9a-f]{2048})"', txt, re.S)
mx = re.search(r'const ucd2TrailStopXor = \[(.*?)\]b;', txt, re.S)
assert ms and mx, "could not find ucd2TrailStartHex / ucd2TrailStopXor"
S = bytes.fromhex(ms.group(1))
X = tuple(int(y, 16) for y in re.findall(r'0x([0-9a-fA-F]{2})', mx.group(1)))
assert len(S) == 256 * 4
assert len(X) == 4
random.seed(3)
ok = True
for _ in range(200):
    seq = random.randrange(256)
    s = u.build_file_command(seq, u.CMD_START_CAPTURE, 1)
    p = u.build_file_command(seq, u.CMD_STOP_CAPTURE, 1)
    st = bytes(S[seq * 4:seq * 4 + 4])
    ok &= st == s[-4:]
    ok &= bytes(st[i] ^ X[i] for i in range(4)) == p[-4:]
print("start seq0 :", bytes(S[0:4]).hex(), "ok:", bytes(S[0:4]).hex() == "5b4d4b5a")
print("start 0x24 :", bytes(S[0x24 * 4:0x24 * 4 + 4]).hex(), "ok:", bytes(S[0x24 * 4:0x24 * 4 + 4]).hex() == "8472946e")
print("stop  seq0 :", bytes(bytes(S[0:4])[i] ^ X[i] for i in range(4)).hex(), "ok:", bytes(bytes(S[0:4])[i] ^ X[i] for i in range(4)).hex() == "45fa0bf1")
print("ALL MATCH" if ok else "MISMATCH")