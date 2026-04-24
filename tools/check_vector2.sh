#!/system/bin/sh
MAN=/data/adb/modules/zygisk_vector/manager.apk
echo "=== manager.apk package name ==="
# Extract AndroidManifest.xml package from apk via grep (dumb but works without aapt)
unzip -p "$MAN" AndroidManifest.xml 2>/dev/null | strings | grep -iE 'lsposed|manager' | head -20
echo
echo "=== installed packages matching manager.apk size/hash ==="
MD5=$(md5sum "$MAN" | awk '{print $1}')
echo "manager.apk md5=$MD5"
echo
echo "=== all installed pkg with lsp/manager in dir ==="
pm list packages -f | grep -iE 'lsp|vector|manager' | head
echo
echo "=== is lsposed manager hidden? ==="
# Vector hides manager under random uid. Try "dumpsys package" for activities with lsposed tag
dumpsys package r 2>/dev/null | grep -iE 'LSPosedManager|manager\.ui\.' | head -5
echo
echo "=== process holding notification 'Vector' ==="
dumpsys notification 2>/dev/null | grep -iE 'vector|lsposed|lspd|manager' | head -20
echo
echo "=== action.sh content (Vector install logic) ==="
head -50 /data/adb/modules/zygisk_vector/action.sh 2>/dev/null
