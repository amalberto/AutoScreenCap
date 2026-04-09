# AutoScreenCap

**Automatic phone unlock for AnyDesk remote sessions** — An Android app that detects active AnyDesk screen-sharing sessions and automatically unlocks the device by entering your PIN.

## Problem

When you connect to your Android phone remotely via AnyDesk, if the phone is locked and the screen is off, you can't interact with it. You need someone to physically unlock it first — defeating the purpose of remote access.

## Solution

AutoScreenCap runs a lightweight foreground service that polls every 3 seconds. When it detects an active AnyDesk screen capture session (`media_projection`) and the device is locked, it automatically:

1. **Wakes the screen** (`KEYEVENT_WAKEUP`)
2. **Swipes up** to reveal the PIN pad
3. **Enters your PIN** via key events
4. **Verifies** the unlock succeeded (retries once if needed)

## Requirements

- **Android 8.0+** (API 26)
- **Root access** (Magisk recommended) — needed for `su` commands to simulate input and query system services
- **AnyDesk** installed and configured for remote access
- The app must be **granted Superuser permission** in Magisk Manager

## Setup

### 1. Configure your PIN

Edit `UnlockService.java` and update the `performUnlock()` method with your PIN keycodes:

```java
// Each digit maps to an Android keycode:
// 0=KEYCODE_0(7), 1=KEYCODE_1(8), 2=KEYCODE_2(9), 3=KEYCODE_3(10),
// 4=KEYCODE_4(11), 5=KEYCODE_5(12), 6=KEYCODE_6(13), 7=KEYCODE_7(14),
// 8=KEYCODE_8(15), 9=KEYCODE_9(16)
//
// Example for PIN "1836":
execRoot("input keyevent 8; input keyevent 15; input keyevent 10; input keyevent 13; input keyevent 66");
```

You may also need to adjust the **swipe coordinates** for your device's lock screen:
```java
execRoot("input swipe 540 1800 540 800"); // Swipe up from (540,1800) to (540,800)
```

### 2. Build

```bash
# Set JAVA_HOME to JDK 17
export JAVA_HOME="/path/to/jdk-17"

# Build debug APK
./gradlew assembleDebug
```

The APK will be at `app/build/outputs/apk/debug/app-debug.apk`.

### 3. Install

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 4. Grant permissions

1. **Open the app** — it will auto-start the monitoring service
2. **Grant notification permission** when prompted (Android 13+)
3. **Grant Superuser access** in Magisk when prompted (or pre-approve in Magisk Manager)

### 5. (Optional) Grant notification permission via ADB

If the permission dialog doesn't appear:
```bash
adb shell pm grant com.autoscreencap android.permission.POST_NOTIFICATIONS
```

## How It Works

```
┌─────────────────────────────────────────────┐
│           UnlockService (Foreground)         │
│                                              │
│  Every 3s:                                   │
│  ┌─────────────────────────────────────┐     │
│  │ 1. dumpsys media_projection         │     │
│  │    → Contains "anydesk"?            │     │
│  │                                     │     │
│  │ 2. KeyguardManager.isDeviceLocked() │     │
│  │    → Device locked?                 │     │
│  │                                     │     │
│  │ 3. Both true → performUnlock()      │     │
│  │    wake → swipe → PIN → verify      │     │
│  └─────────────────────────────────────┘     │
│                                              │
│  Flags:                                      │
│  • unlockInProgress — prevents parallel runs │
│  • alreadyUnlocked — prevents spam when open │
└─────────────────────────────────────────────┘
```

### Detection Method

- **AnyDesk session**: Detected via `dumpsys media_projection` — AnyDesk uses `MediaProjection` API for screen capture, which only appears in the dump during active sessions
- **Lock state**: `KeyguardManager.isDeviceLocked()` — reliable across Android versions
- **Polling thread**: Background thread avoids blocking the main looper during `su` command execution

### Auto-start on Boot

A `BootReceiver` listens for `BOOT_COMPLETED` and `QUICKBOOT_POWERON` to automatically start the service after reboot.

## Project Structure

```
app/src/main/
├── AndroidManifest.xml          # Permissions, service, receiver declarations
├── java/com/autoscreencap/
│   ├── MainActivity.java        # Simple UI with start/stop/test buttons
│   ├── UnlockService.java       # Core service — polling + unlock logic
│   └── BootReceiver.java        # Auto-start on boot
└── res/
    ├── drawable/                 # Adaptive icon vectors
    ├── mipmap-hdpi/             # Launcher icon
    └── values/strings.xml        # App name
```

## Customization

### Change polling interval

In `UnlockService.java`:
```java
private static final long POLL_INTERVAL_MS = 3000; // 3 seconds
```

### Support other remote desktop apps

Change the detection in `isAnyDeskSessionActive()`:
```java
// Detect any app using MediaProjection (not just AnyDesk)
return !output.contains("null");

// Or detect a specific app
return output.toLowerCase().contains("teamviewer");
```

### Use a pattern/password instead of PIN

Replace the keyevent sequence in `performUnlock()` with appropriate `input swipe` gestures for pattern unlock, or `input text "password"` for text passwords.

## Troubleshooting

### Service doesn't detect AnyDesk

- Ensure AutoScreenCap has **Superuser permission** in Magisk Manager
- Verify manually: `su -c "dumpsys media_projection"` should show AnyDesk when connected

### Unlock fails

- Check the log: `su -c "cat /data/data/com.autoscreencap/files/autoscreencap.log"`
- Verify swipe coordinates match your screen resolution
- Verify PIN keycodes are correct

### Service stops after a while

- Ensure battery optimization is **disabled** for AutoScreenCap
- The service uses `START_STICKY` and a foreground notification to persist

## License

MIT License — see [LICENSE](LICENSE).
