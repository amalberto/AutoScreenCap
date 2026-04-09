# AutoScreenCap

**Desbloqueo automático del teléfono para sesiones remotas de AnyDesk** — Una app Android que detecta sesiones activas de captura de pantalla de AnyDesk y desbloquea automáticamente el dispositivo ingresando tu PIN.

> **⚠️ AVISO IMPORTANTE: USO EXCLUSIVO EN DISPOSITIVOS PERSONALES**
>
> Esta aplicación está diseñada **únicamente** para ser utilizada en dispositivos Android de tu **propiedad personal**. Está pensada para facilitar el acceso remoto a tu propio teléfono cuando no puedes desbloquearlo físicamente.
>
> **Descargo de responsabilidad:** El autor no se hace responsable por el uso indebido, no autorizado o ilegal de este software. Utilizar esta herramienta en dispositivos ajenos sin el consentimiento explícito del propietario puede constituir un delito según las leyes de tu jurisdicción. Al usar este software, aceptas toda la responsabilidad derivada de su uso. **Úsalo bajo tu propio riesgo.**

---

## Problema

Cuando te conectas a tu teléfono Android de forma remota mediante AnyDesk, si el teléfono está bloqueado y la pantalla apagada, no puedes interactuar con él. Necesitas que alguien lo desbloquee físicamente — lo cual anula el propósito del acceso remoto.

## Solución

AutoScreenCap ejecuta un servicio en primer plano (foreground service) que verifica cada 3 segundos. Cuando detecta una sesión activa de captura de pantalla de AnyDesk (`media_projection`) y el dispositivo está bloqueado, automáticamente:

1. **Enciende la pantalla** (`KEYEVENT_WAKEUP`)
2. **Desliza hacia arriba** para mostrar el teclado PIN
3. **Ingresa tu PIN** mediante eventos de teclado
4. **Verifica** que el desbloqueo fue exitoso (reintenta una vez si falla)

## Requisitos

- **Android 8.0+** (API 26)
- **Acceso root** (se recomienda Magisk) — necesario para comandos `su` que simulan entrada táctil y consultan servicios del sistema
- **AnyDesk** instalado y configurado para acceso remoto
- La app debe tener **permiso de Superusuario** otorgado en Magisk Manager

## Configuración

### 1. Configura tu PIN

Edita `UnlockService.java` y actualiza el método `performUnlock()` con los keycodes de tu PIN:

```java
// Cada dígito corresponde a un keycode de Android:
// 0=KEYCODE_0(7), 1=KEYCODE_1(8), 2=KEYCODE_2(9), 3=KEYCODE_3(10),
// 4=KEYCODE_4(11), 5=KEYCODE_5(12), 6=KEYCODE_6(13), 7=KEYCODE_7(14),
// 8=KEYCODE_8(15), 9=KEYCODE_9(16)
//
// Ejemplo para PIN "1836":
execRoot("input keyevent 8; input keyevent 15; input keyevent 10; input keyevent 13; input keyevent 66");
```

También puede que necesites ajustar las **coordenadas del deslizamiento** según la pantalla de bloqueo de tu dispositivo:
```java
execRoot("input swipe 540 1800 540 800"); // Desliza desde (540,1800) hasta (540,800)
```

### 2. Compilar

```bash
# Configura JAVA_HOME apuntando a JDK 17
export JAVA_HOME="/ruta/a/jdk-17"

# Compila el APK de debug
./gradlew assembleDebug
```

El APK se generará en `app/build/outputs/apk/debug/app-debug.apk`.

### 3. Instalar

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 4. Otorgar permisos

1. **Abre la app** — iniciará automáticamente el servicio de monitoreo
2. **Otorga permiso de notificaciones** cuando se solicite (Android 13+)
3. **Otorga acceso de Superusuario** en Magisk cuando se pida (o preapruébalo en Magisk Manager)

### 5. (Opcional) Otorgar permiso de notificaciones por ADB

Si el diálogo de permiso no aparece:
```bash
adb shell pm grant com.autoscreencap android.permission.POST_NOTIFICATIONS
```

## Cómo funciona

```
┌──────────────────────────────────────────────┐
│          UnlockService (Primer plano)         │
│                                               │
│  Cada 3s:                                     │
│  ┌──────────────────────────────────────┐     │
│  │ 1. dumpsys media_projection          │     │
│  │    → ¿Contiene "anydesk"?            │     │
│  │                                      │     │
│  │ 2. KeyguardManager.isDeviceLocked()  │     │
│  │    → ¿Dispositivo bloqueado?         │     │
│  │                                      │     │
│  │ 3. Ambos true → performUnlock()      │     │
│  │    despertar → deslizar → PIN → ok   │     │
│  └──────────────────────────────────────┘     │
│                                               │
│  Flags:                                       │
│  • unlockInProgress — evita ejecuciones       │
│    paralelas                                  │
│  • alreadyUnlocked — evita spam cuando ya     │
│    está desbloqueado                          │
└──────────────────────────────────────────────┘
```

### Método de detección

- **Sesión AnyDesk**: Se detecta mediante `dumpsys media_projection` — AnyDesk usa la API `MediaProjection` para captura de pantalla, que solo aparece en el dump durante sesiones activas
- **Estado de bloqueo**: `KeyguardManager.isDeviceLocked()` — confiable en todas las versiones de Android
- **Hilo de polling**: Un hilo en segundo plano evita bloquear el looper principal durante la ejecución de comandos `su`

### Inicio automático al encender

Un `BootReceiver` escucha `BOOT_COMPLETED` y `QUICKBOOT_POWERON` para iniciar el servicio automáticamente después de reiniciar el dispositivo.

## Estructura del proyecto

```
app/src/main/
├── AndroidManifest.xml          # Permisos, servicio, receptor
├── java/com/autoscreencap/
│   ├── MainActivity.java        # UI simple con botones iniciar/detener/probar
│   ├── UnlockService.java       # Servicio principal — polling + lógica de desbloqueo
│   └── BootReceiver.java        # Inicio automático al arrancar
└── res/
    ├── drawable/                 # Vectores del ícono adaptativo
    ├── mipmap-hdpi/             # Ícono del launcher
    └── values/strings.xml        # Nombre de la app
```

## Personalización

### Cambiar intervalo de polling

En `UnlockService.java`:
```java
private static final long POLL_INTERVAL_MS = 3000; // 3 segundos
```

### Soportar otras apps de escritorio remoto

Modifica la detección en `isAnyDeskSessionActive()`:
```java
// Detectar cualquier app usando MediaProjection (no solo AnyDesk)
return !output.contains("null");

// O detectar una app específica
return output.toLowerCase().contains("teamviewer");
```

### Usar patrón o contraseña en lugar de PIN

Reemplaza la secuencia de keyevents en `performUnlock()` con gestos `input swipe` para desbloqueo por patrón, o `input text "contraseña"` para contraseñas de texto.

## Solución de problemas

### El servicio no detecta AnyDesk

- Asegúrate de que AutoScreenCap tiene **permiso de Superusuario** en Magisk Manager
- Verifica manualmente: `su -c "dumpsys media_projection"` debería mostrar AnyDesk cuando esté conectado

### El desbloqueo falla

- Revisa el log: `su -c "cat /data/data/com.autoscreencap/files/autoscreencap.log"`
- Verifica que las coordenadas del deslizamiento correspondan a la resolución de tu pantalla
- Verifica que los keycodes del PIN sean correctos

### El servicio se detiene después de un tiempo

- Asegúrate de que la optimización de batería esté **desactivada** para AutoScreenCap
- El servicio usa `START_STICKY` y una notificación en primer plano para persistir

## Licencia

Licencia MIT — ver [LICENSE](LICENSE).
