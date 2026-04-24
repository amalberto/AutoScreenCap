#!/system/bin/sh
echo "=== start ==="
date +%s.%N
logcat -c 2>/dev/null
timeout 20 getevent -lq 2>/dev/null | grep -E "KEY_POWER|KEY_SLEEP|KEY_WAKEUP" > /data/local/tmp/kev.log &
PK=$!
timeout 20 logcat -v time PhoneWindowManager:* PowerManagerService:* InputReader:* InputDispatcher:* WindowManager:I *:S > /data/local/tmp/klog.log 2>/dev/null &
PL=$!
wait $PK
kill $PL 2>/dev/null
wait $PL 2>/dev/null
echo "=== kernel events (getevent KEY_POWER/SLEEP/WAKEUP) ==="
cat /data/local/tmp/kev.log
echo "=== logcat POWER-related ==="
grep -iE "power|keycode_power|interceptkey|longpress|gotosleep|wakeup" /data/local/tmp/klog.log | head -60
