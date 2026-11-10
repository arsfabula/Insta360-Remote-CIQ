#!/bin/sh
# Render each UI state in the CIQ simulator and screenshot it: tools/preview.sh <outdir>
set -e
cd "$(dirname "$0")/.."
OUT=${1:-/tmp/ciq-preview}; mkdir -p "$OUT"
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")/bin"
for st in ${STATES:-UI_SEARCHING UI_NOT_FOUND UI_READY UI_RECORDING UI_BUSY}; do
  printf 'var demoState = %s;
var demoName = "X5 1ABCDE";
var demoLabel = "%s";
var demoToast = %s;
var demoFocus = %s;
var demoSet = %s;
var demoAcked = %s;
' "$st" "${LABEL:-Photo Interval}" "${TOAST:-null}" "${FOCUS:-null}" "${SET:-null}" "${ACKED:-null}" > source-demo/Demo.mc
  # a failed build must stop here: otherwise the simulator silently shows the previous demo.prg
  rm -f bin/demo.prg
  if ! monkeyc -f demo.jungle -d descentmk351mm -y "${CIQ_KEY:-$HOME/.config/connectiq/developer_key.der}" -o bin/demo.prg -l 0 > "$OUT/build.log" 2>&1; then
    grep -v '^WARNING' "$OUT/build.log" >&2; exit 1
  fi
  pkill -f monkeydo || true
  pkill -f "ConnectIQ.app/Contents/MacOS/simulator" || true; sleep 1
  open -a "$SDK/ConnectIQ.app"; sleep 6
  ("$SDK/monkeydo" bin/demo.prg descentmk351mm >/dev/null 2>&1 &)
  sleep 6
  sleep 1
  screencapture -x -o -l"$(tools/winid)" "$OUT/$st.png"
done
pkill -f monkeydo || true
echo "$OUT"
