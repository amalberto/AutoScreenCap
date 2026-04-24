#!/system/bin/sh
logcat -c
echo ">>> 15s: pulsa RECIENTES 3 veces <<<"
timeout 15 logcat -v time ActivityTaskManager:I ActivityManager:I WindowManager:I *:S > /data/local/tmp/rec.log 2>&1
echo --- head of lines ---
head -80 /data/local/tmp/rec.log
echo --- grep recents/launcher/overview/quickstep ---
grep -iE 'recent|launcher|overview|quickstep|taskview|cts' /data/local/tmp/rec.log | head -40
