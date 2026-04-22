package com.autoscreencap;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action) ||
            Intent.ACTION_BOOT_COMPLETED.equals(action) ||
            "android.intent.action.QUICKBOOT_POWERON".equals(action)) {
            Log.i("AutoScreenCap", "Boot broadcast " + action + " — starting UnlockService");
            Intent serviceIntent = new Intent(context, UnlockService.class);
            context.startForegroundService(serviceIntent);
        }
    }
}
