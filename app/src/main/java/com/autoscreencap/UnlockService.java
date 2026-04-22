package com.autoscreencap;

import android.app.KeyguardManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class UnlockService extends Service {

    private static final String TAG = "AutoScreenCap";
    private static final String CHANNEL_ID = "autoscreencap_channel";
    private static final long POLL_INTERVAL_MS = 10000;
    private static final String LOG_FILE = "/data/local/tmp/autoscreencap.log";

    // PIN keycodes: digit 0=7, 1=8, 2=9, 3=10, 4=11, 5=12, 6=13, 7=14, 8=15, 9=16
    // Change this to match YOUR PIN. Example below is for PIN "1836":
    private static final String PIN_KEYEVENTS = "input keyevent 8; input keyevent 15; input keyevent 10; input keyevent 13; input keyevent 66";

    // --- Watchdog de sesion AnyDesk huerfana ---
    // Cuando la conexion remota cae de forma abrupta, el servidor AnyDesk en
    // Android mantiene el MediaProjection sostenido y el siguiente intento de
    // reconexion nunca prospera. Este watchdog detecta ese estado comparando
    // la proyeccion activa con el reparto de estados TCP de la UID de AnyDesk.
    //
    // Heuristica:
    //   - Una sesion AnyDesk sana mantiene >=1 conexion ESTABLISHED "extra"
    //     ademas de la conexion permanente al relay (net.anydesk.com:7070),
    //     y NUNCA tiene sockets en CLOSE_WAIT / FIN_WAIT / LAST_ACK.
    //   - Una sesion huerfana se caracteriza por:
    //         a) sockets en CLOSE_WAIT/FIN_WAIT1/FIN_WAIT2/LAST_ACK (codigos
    //            TCP 04, 05, 08, 09 en /proc/net/tcp), que son la huella que
    //            deja el peer remoto al cerrar mientras el servidor no lo ha
    //            hecho, o bien
    //         b) <=1 conexion ESTABLISHED (es decir, solo el relay keepalive
    //            sin ninguna sesion de datos encima).
    //
    // Si cualquiera de esas condiciones se mantiene WATCHDOG_STUCK_THRESHOLD
    // ciclos consecutivos, se asume sesion huerfana y se hace force-stop +
    // relaunch de AnyDesk para liberar el MediaProjection.
    private static final String ANYDESK_PKG = "com.anydesk.anydeskandroid";
    private static final long WATCHDOG_INTERVAL_MS = 10_000;
    private static final int WATCHDOG_STUCK_THRESHOLD = 2; // 2 * 10s = 20s
    private static final long WATCHDOG_RESET_COOLDOWN_MS = 60_000;

    // Codigos de estado TCP segun net/tcp_states.h
    private static final int TCP_ESTABLISHED = 0x01;
    private static final int TCP_FIN_WAIT1   = 0x04;
    private static final int TCP_FIN_WAIT2   = 0x05;
    private static final int TCP_CLOSE_WAIT  = 0x08;
    private static final int TCP_LAST_ACK    = 0x09;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean polling = false;
    private volatile boolean alreadyUnlocked = false;
    private volatile boolean unlockInProgress = false;
    private Context deviceCtx;

    private volatile int anyDeskUid = -1;
    private int watchdogStuckCount = 0;
    private long lastWatchdogResetAt = 0L;

    private final Runnable pollRunnable = new Runnable() {
        @Override
        public void run() {
            if (!polling) return;
            // Run checks on background thread to avoid blocking main looper with su commands
            new Thread(() -> {
                try {
                    checkAndUnlock();
                } catch (Exception e) {
                    Log.e(TAG, "Poll error", e);
                }
            }, "PollCheck").start();
            handler.postDelayed(this, POLL_INTERVAL_MS);
        }
    };

    private final Runnable watchdogRunnable = new Runnable() {
        @Override
        public void run() {
            if (!polling) return;
            new Thread(() -> {
                try {
                    checkAnyDeskSessionHealth();
                } catch (Exception e) {
                    log("Watchdog error: " + e.getMessage());
                }
            }, "AnyDeskWatchdog").start();
            handler.postDelayed(this, WATCHDOG_INTERVAL_MS);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        // Use device-protected storage so log() works before the user unlocks
        // (credential-protected storage is unavailable until first unlock).
        deviceCtx = createDeviceProtectedStorageContext();
        boolean unlocked = isUserUnlocked();
        log("UnlockService created (userUnlocked=" + unlocked + ")");
        createNotificationChannel();
        startPolling();
        if (!unlocked) {
            scheduleFirstBootUnlock();
        }
    }

    /**
     * When the service starts during Direct Boot (pre first-unlock), trigger the
     * PIN unlock sequence unconditionally once. This is required because AnyDesk
     * (and its MediaProjection pipe) can only read the screen after the user
     * is unlocked; before that, polling dumpsys media_projection finds nothing
     * and the service would sit idle forever on a headless boot.
     */
    private void scheduleFirstBootUnlock() {
        // Delay to give SystemUI time to draw the Keyguard and be ready to
        // receive key events. 8s is conservative but reliable on cold boot.
        final long delayMs = 8000;
        log("First-boot pre-unlock scheduled in " + delayMs + "ms");
        handler.postDelayed(() -> new Thread(() -> {
            try {
                if (isUserUnlocked()) {
                    log("First-boot unlock skipped (already unlocked)");
                    return;
                }
                if (unlockInProgress) {
                    log("First-boot unlock skipped (unlock in progress)");
                    return;
                }
                log("First-boot unlock: performing unconditional unlock");
                unlockInProgress = true;
                performUnlock();
            } catch (Exception e) {
                log("First-boot unlock error: " + e.getMessage());
                unlockInProgress = false;
            }
        }, "FirstBootUnlock").start(), delayMs);
    }

    private boolean isUserUnlocked() {
        try {
            android.os.UserManager um = (android.os.UserManager) getSystemService(Context.USER_SERVICE);
            return um != null && um.isUserUnlocked();
        } catch (Exception e) {
            return false;
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Notification notification = new Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("AutoScreenCap")
                .setContentText("Monitoring AnyDesk connections")
                .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setOngoing(true)
                .build();
        startForeground(1, notification);
        log("UnlockService started foreground");
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        polling = false;
        handler.removeCallbacksAndMessages(null);
        Log.i(TAG, "UnlockService destroyed");
    }

    private void createNotificationChannel() {
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "AutoScreenCap Service",
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Keeps unlock service running");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }

    private void startPolling() {
        polling = true;
        handler.postDelayed(pollRunnable, POLL_INTERVAL_MS);
        handler.postDelayed(watchdogRunnable, WATCHDOG_INTERVAL_MS);
        log("Polling started (unlock every " + POLL_INTERVAL_MS + "ms, watchdog every "
                + WATCHDOG_INTERVAL_MS + "ms)");
    }

    private void checkAndUnlock() {
        boolean anyDeskActive = isAnyDeskSessionActive();
        boolean locked = isDeviceLocked();

        if (!anyDeskActive) {
            if (alreadyUnlocked) {
                alreadyUnlocked = false;
            }
            return;
        }

        // AnyDesk is active
        if (!locked) {
            // Device is unlocked - set flag so we don't spam unlock
            alreadyUnlocked = true;
            return;
        }

        // AnyDesk active + device locked
        if (unlockInProgress) {
            return;
        }

        log("AnyDesk active + locked -> UNLOCKING");
        unlockInProgress = true;
        performUnlock();
    }

    private boolean isScreenOn() {
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        return pm != null && pm.isInteractive();
    }

    private boolean isDeviceLocked() {
        try {
            KeyguardManager km = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
            boolean locked = km != null && km.isDeviceLocked();
            Log.d(TAG, "isDeviceLocked(KeyguardManager): " + locked);
            return locked;
        } catch (Exception e) {
            Log.e(TAG, "isDeviceLocked check failed", e);
            return true;
        }
    }

    private boolean isAnyDeskSessionActive() {
        try {
            String output = execRoot("dumpsys media_projection");
            return output.toLowerCase().contains("anydesk");
        } catch (Exception e) {
            log("AnyDesk check EXCEPTION: " + e.getMessage());
            return false;
        }
    }

    private void performUnlock() {
        new Thread(() -> {
            try {
                // Wake screen
                execRoot("input keyevent 224");
                Thread.sleep(300);

                // Swipe up to reveal PIN pad
                execRoot("input swipe 540 1800 540 800");
                Thread.sleep(600);

                // Enter PIN digits as keycodes (0=7, 1=8, 2=9, ..., 9=16) then Enter(66)
                // TODO: Change this to your own PIN keycodes
                execRoot(PIN_KEYEVENTS);

                log("Unlock sequence completed");

                // Verify
                Thread.sleep(1000);
                if (!isDeviceLocked()) {
                    log("Device unlocked successfully!");
                } else {
                    log("Still locked, retrying...");
                    Thread.sleep(300);
                    execRoot("input swipe 540 1800 540 800");
                    Thread.sleep(600);
                    execRoot(PIN_KEYEVENTS);
                    Thread.sleep(1000);
                    log(isDeviceLocked() ? "Retry failed" : "Retry succeeded");
                }
            } catch (Exception e) {
                log("Unlock failed: " + e.getMessage());
            } finally {
                unlockInProgress = false;
            }
        }, "UnlockThread").start();
    }

    /**
     * Detecta sesiones de AnyDesk que quedaron huerfanas despues de una
     * desconexion abrupta del cliente. Ver comentario de la seccion
     * "Watchdog" en la cabecera de la clase para la heuristica completa.
     */
    private void checkAnyDeskSessionHealth() {
        boolean projectionHeld;
        try {
            projectionHeld = isAnyDeskSessionActive();
        } catch (Exception e) {
            return;
        }
        if (!projectionHeld) {
            if (watchdogStuckCount != 0) {
                watchdogStuckCount = 0;
            }
            return;
        }

        int uid = getAnyDeskUid();
        if (uid < 0) {
            // Sin UID no podemos inspeccionar /proc/net/tcp de forma fiable.
            return;
        }

        int[] states = countTcpStatesForUid(uid);
        int established = states[TCP_ESTABLISHED];
        int halfClosed = states[TCP_FIN_WAIT1] + states[TCP_FIN_WAIT2]
                + states[TCP_CLOSE_WAIT] + states[TCP_LAST_ACK];

        // Condiciones de "sesion huerfana":
        //  - hay sockets a medio cerrar (el peer remoto se fue), o
        //  - solo queda el keepalive del relay (<=1 ESTABLISHED).
        boolean stuck = (halfClosed > 0) || (established <= 1);

        if (!stuck) {
            if (watchdogStuckCount != 0) {
                log("Watchdog: AnyDesk sesion OK (est=" + established
                        + ", halfClosed=" + halfClosed + ")");
                watchdogStuckCount = 0;
            }
            return;
        }

        watchdogStuckCount++;
        log("Watchdog: projection held + sospecha (est=" + established
                + ", halfClosed=" + halfClosed + ") ("
                + watchdogStuckCount + "/" + WATCHDOG_STUCK_THRESHOLD + ")");

        if (watchdogStuckCount < WATCHDOG_STUCK_THRESHOLD) {
            return;
        }

        long now = System.currentTimeMillis();
        if (now - lastWatchdogResetAt < WATCHDOG_RESET_COOLDOWN_MS) {
            log("Watchdog: reset suprimido por cooldown");
            return;
        }

        log("Watchdog: sesion AnyDesk huerfana confirmada -> reiniciando app");
        resetAnyDeskSession();
        watchdogStuckCount = 0;
        lastWatchdogResetAt = now;
    }

    private int getAnyDeskUid() {
        int cached = anyDeskUid;
        if (cached >= 0) return cached;
        try {
            android.content.pm.ApplicationInfo ai = getPackageManager()
                    .getApplicationInfo(ANYDESK_PKG, 0);
            anyDeskUid = ai.uid;
            return anyDeskUid;
        } catch (Exception e) {
            return -1;
        }
    }

    /**
     * Devuelve un histograma de estados TCP (indice = codigo de estado hex)
     * para la UID dada, combinando /proc/net/tcp y /proc/net/tcp6. El array
     * tiene tamanio 16, suficiente para los 11 estados TCP (01..0B).
     */
    private int[] countTcpStatesForUid(int uid) {
        int[] counts = new int[16];
        tallyTcpStatesForUid("/proc/net/tcp", uid, counts);
        tallyTcpStatesForUid("/proc/net/tcp6", uid, counts);
        return counts;
    }

    private void tallyTcpStatesForUid(String path, int uid, int[] counts) {
        BufferedReader br = null;
        try {
            br = new BufferedReader(new java.io.FileReader(path));
            tallyFromReader(br, uid, counts);
        } catch (Exception e) {
            // Algunas ROMs restringen /proc/net/tcp a procesos ajenos.
            // Fallback: leer via su.
            try {
                String out = execRoot("cat " + path);
                tallyFromReader(new BufferedReader(new java.io.StringReader(out)),
                        uid, counts);
            } catch (Exception ignored) {}
        } finally {
            if (br != null) try { br.close(); } catch (Exception ignored) {}
        }
    }

    private void tallyFromReader(BufferedReader br, int uid, int[] counts)
            throws Exception {
        String line;
        boolean header = true;
        while ((line = br.readLine()) != null) {
            if (header) { header = false; continue; }
            // sl local rem st tx:rx tr:tm_when retrnsmt uid ...
            String[] parts = line.trim().split("\\s+");
            if (parts.length < 8) continue;
            int rowUid;
            try { rowUid = Integer.parseInt(parts[7]); }
            catch (NumberFormatException e) { continue; }
            if (rowUid != uid) continue;
            int st;
            try { st = Integer.parseInt(parts[3], 16); }
            catch (NumberFormatException e) { continue; }
            if (st >= 0 && st < counts.length) counts[st]++;
        }
    }

    private void resetAnyDeskSession() {
        try {
            execRoot("am force-stop " + ANYDESK_PKG);
            Thread.sleep(1500);
            // monkey lanza la activity por defecto aunque la app no se este ejecutando
            execRoot("monkey -p " + ANYDESK_PKG + " -c android.intent.category.LAUNCHER 1");
            log("AnyDesk force-stop + relaunch ejecutados");
        } catch (Exception e) {
            log("resetAnyDeskSession fallo: " + e.getMessage());
        }
    }

    private String execRoot(String command) throws Exception {
        Process process = Runtime.getRuntime().exec(new String[]{"su", "-c", command});
        BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
        BufferedReader errReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            sb.append(line).append("\n");
        }
        StringBuilder errSb = new StringBuilder();
        while ((line = errReader.readLine()) != null) {
            errSb.append(line).append("\n");
        }
        int exitCode = process.waitFor();
        if (errSb.length() > 0 || exitCode != 0) {
            log("execRoot [" + command + "] exit=" + exitCode + " stderr=[" + errSb.toString().trim() + "]");
        }
        return sb.toString();
    }

    private void log(String msg) {
        Log.i(TAG, msg);
        try {
            String ts = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date());
            // Write to device-protected storage so logging works pre-unlock
            Context ctx = (deviceCtx != null) ? deviceCtx : this;
            File logFile = new File(ctx.getFilesDir(), "autoscreencap.log");
            FileWriter fw = new FileWriter(logFile, true);
            fw.write(ts + " " + msg + "\n");
            fw.close();
        } catch (Exception ignored) {}
    }
}
