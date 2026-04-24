#!/system/bin/sh
logcat -c
echo ">>> 15s: pulsa RECIENTES 3 veces <<<"
timeout 15 logcat -v time -s SystemUI:V StatusBar:V Recents:V RecentsImpl:V ActivityTaskManager:V ShellTaskOrganizer:V *:S > /data/local/tmp/rec.log 2>&1
echo --- grep recents/taskstack/showrecent ---
grep -iE 'recent|showRecent|toggleRecent|openRecent|KEYCODE_APP_SWITCH|app_switch' /data/local/tmp/rec.log | head -40
