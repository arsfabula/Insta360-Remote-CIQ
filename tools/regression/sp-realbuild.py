import subprocess, sys, os, re
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

MONKEY = r'C:\Users\greg\AppData\Roaming\Garmin\ConnectIQ\Sdks\connectiq-sdk-win-9.3.0-2026-10-20-95888f262\bin\monkeyc.bat'
KEY = r'C:\Users\greg\Documents\Default Project\Insta360 Remote\developer_key'
APP = r'C:\Users\greg\git\Insta360-Remote-CIQ V1.0.0\OneR remote'
OUTD = r'C:\Users\greg\git\Insta360-Remote-CIQ-Build\sp-test'
os.makedirs(OUTD, exist_ok=True)

for dev in ('marqexpedition', 'epix2pro51mm'):
    out = os.path.join(OUTD, 'sp-real-%s.prg' % dev)
    r = subprocess.run([MONKEY, '-f', 'monkey.jungle;barrels.jungle', '-d', dev, '-y', KEY, '-o', out],
                       cwd=APP, capture_output=True, text=True)
    lines = (r.stdout + r.stderr).splitlines()
    warn = [l for l in lines if re.search(r'WARNING|ERROR', l, re.I)]
    print('BUILD %s EXIT=%d size=%d' % (dev, r.returncode, os.path.getsize(out) if os.path.exists(out) else -1))
    for l in warn[:10]: print('   ', l)
