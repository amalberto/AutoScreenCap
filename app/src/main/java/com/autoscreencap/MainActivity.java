package com.autoscreencap;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.Manifest;

public class MainActivity extends Activity {

    private static final String TAG = "AutoScreenCap";
    private static final int NOTIF_PERM_REQUEST = 100;
    private TextView statusText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(48, 48, 48, 48);

        TextView title = new TextView(this);
        title.setText("AutoScreenCap — AnyDesk Auto-Unlock");
        title.setTextSize(20);
        layout.addView(title);

        statusText = new TextView(this);
        statusText.setPadding(0, 24, 0, 24);
        statusText.setTextSize(14);
        layout.addView(statusText);

        Button startBtn = new Button(this);
        startBtn.setText("Iniciar Servicio");
        startBtn.setOnClickListener(v -> startUnlockService());
        layout.addView(startBtn);

        Button stopBtn = new Button(this);
        stopBtn.setText("Detener Servicio");
        stopBtn.setOnClickListener(v -> {
            stopService(new Intent(this, UnlockService.class));
            updateStatus("Servicio detenido");
        });
        layout.addView(stopBtn);

        Button testBtn = new Button(this);
        testBtn.setText("Test: Unlock Now");
        testBtn.setOnClickListener(v -> {
            new Thread(() -> {
                try {
                    // TODO: Change PIN keycodes to match your PIN (see UnlockService.java)
                    Runtime.getRuntime().exec(new String[]{"su", "-c",
                        "input keyevent 224; sleep 0.3; input swipe 540 1800 540 800; sleep 0.5; " +
                        "input keyevent 8; sleep 0.08; input keyevent 15; sleep 0.08; " +
                        "input keyevent 10; sleep 0.08; input keyevent 13; sleep 0.08; input keyevent 66"
                    }).waitFor();
                    runOnUiThread(() -> updateStatus("Test unlock ejecutado"));
                } catch (Exception e) {
                    runOnUiThread(() -> updateStatus("Error: " + e.getMessage()));
                }
            }).start();
        });
        layout.addView(testBtn);

        setContentView(layout);

        // Request notification permission on Android 13+
        if (Build.VERSION.SDK_INT >= 33) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, NOTIF_PERM_REQUEST);
            }
        }

        // Auto-start service
        startUnlockService();
    }

    private void startUnlockService() {
        Intent intent = new Intent(this, UnlockService.class);
        startForegroundService(intent);
        updateStatus("Servicio iniciado — monitoreando conexiones AnyDesk.\n" +
                "Cuando AnyDesk se conecte y la pantalla esté bloqueada,\n" +
                "se desbloqueará automáticamente con PIN.");
    }

    private void updateStatus(String text) {
        if (statusText != null) {
            statusText.setText(text);
        }
        Log.i(TAG, text);
    }
}
