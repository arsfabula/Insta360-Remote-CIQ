#!/bin/sh
# Wait until the Garmin watch is in MTP mode (091e:507f) and libmtp can open it.
# After plug-in the watch sits 20-60 s as 091e:0003 (or briefly off the bus) before MTP comes up,
# so a one-shot check gives false "not connected". Usage: tools/watch-wait.sh [timeout_s]
T=${1:-120}; i=0
pkill -f 'Garmin Express' 2>/dev/null
while [ $i -lt $T ]; do
  pid=$(ioreg -p IOUSB -l -w0 | grep -B40 '"idVendor" = 2334' | grep '"idProduct"' | tail -1 | awk '{print $NF}')
  if [ "$pid" = "20607" ] && mtp-detect 2>/dev/null | grep -q 'PID=507f'; then echo "watch ready after ${i}s"; exit 0; fi
  [ $((i % 10)) -eq 0 ] && echo "waiting: usb product=${pid:-none} (${i}s)"
  sleep 2; i=$((i+2))
done
echo "watch NOT in MTP mode after ${T}s (last usb product=${pid:-none})"; exit 1
