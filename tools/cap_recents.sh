#!/system/bin/sh
echo ">>> 12s: pulsa RECIENTES 3 veces (fisico y/o desde AnyDesk) <<<"
timeout 12 getevent -lq 2>/dev/null | grep -E 'KEY_APPSELECT|KEY_HOMEPAGE|KEY_BACK|KEY_VOLUMEUP' | head -20
echo "--- fin ---"
