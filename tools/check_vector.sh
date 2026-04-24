#!/system/bin/sh
echo '=== ps all lspd/vector ==='
ps -ef | grep -iE 'lspd|vector|daemon.apk' | grep -v grep
echo
echo '=== /dev/socket lspd ==='
ls -la /dev/socket/ 2>/dev/null | grep -iE 'lspd|lspos|dispatch'
echo
ZPID=$(pidof zygote64)
echo "zygote64 pid=$ZPID"
echo '=== zygote64 maps lspd/vector/zygisk ==='
cat /proc/$ZPID/maps 2>/dev/null | grep -iE 'zygisk|vector|lspd|riru' | awk '{print $NF}' | sort -u
echo
SSPID=$(pidof system_server)
echo "system_server pid=$SSPID"
echo '=== system_server maps lspd ==='
cat /proc/$SSPID/maps 2>/dev/null | grep -iE 'zygisk|vector|lspd' | awk '{print $NF}' | sort -u
echo
echo '=== modules config ==='
sqlite3 /data/adb/lspd/config/modules_config.db 'SELECT mid,module_pkg_name,enabled,apk_path FROM modules;' 2>&1
echo
echo '=== scope ==='
sqlite3 /data/adb/lspd/config/modules_config.db 'SELECT * FROM scope;' 2>&1
echo
echo '=== manager.apk aapt ==='
pm install-existing org.lsposed.manager 2>&1
pm list packages | grep -iE 'lspose|Posed|Vector'
echo
echo '=== package info for manager.apk ==='
PKG=$(cat /data/adb/modules/zygisk_vector/module.prop | head -3)
echo "$PKG"
