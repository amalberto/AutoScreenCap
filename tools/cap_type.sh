#!/system/bin/sh
logcat -c
echo ">>> 15s: escribe varias letras desde AnyDesk o pulsa en pantalla <<<"
timeout 15 logcat -v time PowerManagerService:* *:S > /data/local/tmp/pm.log 2>&1
echo --- anydesk-related ---
grep -iE 'anydesk|wake-up|user activity|gotosleep' /data/local/tmp/pm.log | head -60
