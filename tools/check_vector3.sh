#!/system/bin/sh
echo '=== lspd daemon uptime/status ==='
ps -ef | grep -i lspd | grep -v grep
echo
echo '=== action: launch Vector manager ==='
MANAGER_PACKAGE_NAME="org.lsposed.manager"
INJECTED_PACKAGE_NAME="com.android.shell"
am start -c "${MANAGER_PACKAGE_NAME}.LAUNCH_MANAGER" "${INJECTED_PACKAGE_NAME}/.BugreportWarningActivity" 2>&1
echo
echo '=== service.sh (what runs at boot) ==='
cat /data/adb/modules/zygisk_vector/service.sh 2>/dev/null
echo
echo '=== post-fs-data.sh ==='
cat /data/adb/modules/zygisk_vector/post-fs-data.sh 2>/dev/null
echo
echo '=== magisk module list ==='
magisk --list 2>&1 || ls /data/adb/modules
