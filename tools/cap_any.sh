#!/system/bin/sh
echo ">>> 12s: pulsa RECIENTES 3 veces desde AnyDesk (o fisico) <<<"
timeout 12 getevent -lq 2>/dev/null > /data/local/tmp/ev.log
echo --- unique EV_KEY lines ---
grep EV_KEY /data/local/tmp/ev.log | sort -u | head -20
echo --- first 40 lines ---
head -40 /data/local/tmp/ev.log
