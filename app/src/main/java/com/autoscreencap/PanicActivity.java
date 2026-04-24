package com.autoscreencap;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Activity-trigger para soft-reboot remoto via AnyDesk movil->movil.
 *
 * El cliente AnyDesk Android tiene un campo "Enviar texto" con un boton ▶
 * que inyecta el texto como keystrokes al foreground del servidor. Como
 * AnyDesk no sincroniza portapapeles de forma fiable en esa direccion,
 * usamos ese canal: el usuario abre esta activity desde el launcher (icono
 * "Panic"), AnyDesk focusea automaticamente el EditText visible, pulsa ▶
 * con el texto "!!REBOOT!!", y el TextWatcher dispara el soft-reboot.
 *
 * Zero-permiso, zero-root-extra. El reboot final sigue siendo via `su -c`
 * "setprop ctl.restart zygote" como en UnlockService.triggerSoftReboot.
 */
public class PanicActivity extends Activity {

    private static final String TAG = "AutoScreenCap";
    private static final String PANIC_TOKEN = "!!REBOOT!!";

    private EditText field;
    private TextView status;
    private volatile boolean fired = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Mantener la pantalla encendida y sobre el keyguard para que AnyDesk
        // pueda interactuar aun con el dispositivo bloqueado.
        getWindow().addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(48, 96, 48, 48);
        root.setBackgroundColor(Color.BLACK);

        TextView title = new TextView(this);
        title.setText("PANIC — Soft Reboot");
        title.setTextSize(22);
        title.setTextColor(Color.RED);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView hint = new TextView(this);
        hint.setText("Envia '" + PANIC_TOKEN + "' con el boton \u25B6 de AnyDesk para reiniciar el zygote.");
        hint.setTextSize(14);
        hint.setTextColor(Color.LTGRAY);
        hint.setPadding(0, 24, 0, 24);
        root.addView(hint);

        field = new EditText(this);
        field.setHint("...");
        field.setTextSize(18);
        field.setTextColor(Color.WHITE);
        field.setHintTextColor(Color.DKGRAY);
        field.setSingleLine(false);
        field.setMinLines(3);
        field.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
        field.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                if (fired) return;
                if (s == null) return;
                if (s.toString().contains(PANIC_TOKEN)) {
                    fired = true;
                    onTokenDetected();
                }
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        root.addView(field);

        status = new TextView(this);
        status.setTextSize(14);
        status.setTextColor(Color.GRAY);
        status.setPadding(0, 24, 0, 0);
        root.addView(status);

        setContentView(root);
        field.requestFocus();
        // Forzar mostrar teclado (no necesario para AnyDesk pero ayuda al
        // uso manual de fallback).
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE);
    }

    private void onTokenDetected() {
        log("PanicActivity: token '" + PANIC_TOKEN + "' detectado -> soft reboot");
        status.setTextColor(Color.YELLOW);
        status.setText("Token detectado. Reiniciando zygote...");
        Toast.makeText(this, "PANIC: soft-reboot en curso", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            try {
                Process p = Runtime.getRuntime().exec(new String[]{"su", "-c", "setprop ctl.restart zygote"});
                p.waitFor();
            } catch (Exception e) {
                log("PanicActivity: triggerSoftReboot fallo: " + e.getMessage());
            }
        }, "PanicReboot").start();
    }

    private void log(String msg) {
        String line = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(new Date()) + " " + msg;
        Log.i(TAG, msg);
        try {
            File logFile = new File(createDeviceProtectedStorageContext().getFilesDir(), "autoscreencap.log");
            try (FileWriter fw = new FileWriter(logFile, true)) {
                fw.write(line + "\n");
            }
        } catch (Exception ignored) {}
    }
}
