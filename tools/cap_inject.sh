#!/system/bin/sh
logcat -c
# Dispara 3 APP_SWITCH con 400ms entre medias (similar a 3 clicks humanos)
(sleep 1; input keyevent KEYCODE_APP_SWITCH; sleep 0.4; input keyevent KEYCODE_APP_SWITCH; sleep 0.4; input keyevent KEYCODE_APP_SWITCH) &
timeout 6 logcat -v time *:I 2>/dev/null > /data/local/tmp/inj.log
echo --- unique tags ---
awk -F'[IWEDV]/' 'NF>=2{print $2}' /data/local/tmp/inj.log | awk '{print $1}' | sort -u | head -20
echo --- any APP_SWITCH/recents/overview/quickstep ---
grep -iE 'app_switch|APP_SWITCH|recents|overview|quickstep|switchTo|TaskView' /data/local/tmp/inj.log | head -30
echo --- top 5 by freq ---
awk '{print $4}' /data/local/tmp/inj.log | sort | uniq -c | sort -rn | head -5
