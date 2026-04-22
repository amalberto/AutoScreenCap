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

AutoScreenCap ejecuta un servicio en primer plano (foreground service) que verifica cada 10 segundos. Cuando detecta una sesión activa de captura de pantalla de AnyDesk (`media_projection`) y el dispositivo está bloqueado, automáticamente:

1. **Enciende la pantalla** (`KEYEVENT_WAKEUP`)
2. **Desliza hacia arriba** para mostrar el teclado PIN
3. **Ingresa tu PIN** mediante eventos de teclado
4. **Verifica** que el desbloqueo fue exitoso (reintenta una vez si falla)

Además soporta **Direct Boot**: el servicio arranca incluso antes del primer desbloqueo tras un reinicio (cuando `/data` aún está cifrado y el usuario no ha ingresado el PIN), y en ese caso **ejecuta un unlock incondicional** 8 segundos después del arranque para dejar el teléfono listo para conexiones AnyDesk sin intervención física.

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

Un `BootReceiver` marcado como `directBootAware` escucha los broadcasts `LOCKED_BOOT_COMPLETED` (entregado **antes** del primer unlock), `BOOT_COMPLETED` y `QUICKBOOT_POWERON` para iniciar el servicio automáticamente después de reiniciar el dispositivo.

El mismo receptor escucha además `MY_PACKAGE_REPLACED`, que Android envía exclusivamente al paquete propio tras un `adb install -r` / update de la app. Así, el servicio se relanza inmediatamente tras una reinstalación en caliente sin tener que reiniciar el teléfono ni abrir la `MainActivity`.

### Direct Boot y unlock incondicional al arrancar

Tanto `<application>`, `<service .UnlockService>` como `<receiver .BootReceiver>` declaran `android:directBootAware="true"`, lo que permite que el servicio arranque en la fase cifrada del boot (antes de que el usuario haya desbloqueado nunca el teléfono tras encenderlo).

Cuando `UnlockService.onCreate()` detecta `UserManager.isUserUnlocked() == false`, programa un `performUnlock()` incondicional 8 segundos después (para dar tiempo a SystemUI a dibujar el Keyguard). Esto es necesario porque antes del primer unlock AnyDesk no puede capturar la pantalla, por lo que el polling normal de `dumpsys media_projection` no detectaría nada y el servicio se quedaría esperando indefinidamente.

Para que el log funcione en esa fase, el servicio escribe en **device-protected storage** (`/data/user_de/0/<pkg>/files/`) en lugar del `credential-protected` habitual (`/data/data/<pkg>/files/`), que no está disponible hasta el primer unlock.

> **Nota sobre ADB:** para que `adb shell input text <PIN>` funcione antes del primer unlock también hay que asegurarse de que la clave pública de ADB esté en una ruta que adbd pueda leer en esa fase (p. ej. reemplazando el archivo destino del symlink `/adb_keys` en la partición `product`). Este paso depende del dispositivo y queda fuera del alcance de esta app.

### Watchdog de sesiones huérfanas de AnyDesk

Cuando la conexión remota cae de forma abrupta (pérdida de red del cliente, cierre forzado, etc.), el servidor AnyDesk de Android a veces **no libera** el `MediaProjection` ni cierra la sesión. El resultado visible: el dispositivo parece seguir "conectado" y el siguiente intento de reconexión se queda colgado indefinidamente.

Para detectar y recuperar esa situación, `UnlockService` lanza un watchdog independiente del polling de desbloqueo:

- Cada `WATCHDOG_INTERVAL_MS` (10 s por defecto) comprueba si AnyDesk figura en `dumpsys media_projection`.
- Si es así, resuelve la UID del paquete (`com.anydesk.anydeskandroid`) y construye un histograma de estados TCP leyendo `/proc/net/tcp` y `/proc/net/tcp6` (con fallback a `su cat` por si la ROM restringe la lectura a procesos ajenos).
- Se considera **sesión huérfana** si, con `MediaProjection` sostenido, se da cualquiera de estos dos patrones:
  1. Hay **sockets en CLOSE_WAIT / FIN_WAIT1 / FIN_WAIT2 / LAST_ACK** para la UID de AnyDesk — la huella que deja el peer remoto al cerrar mientras el servidor no ha terminado de finalizar el socket.
  2. Hay **≤1 conexión ESTABLISHED** — es decir, solo el keepalive permanente al relay (`net.anydesk.com:7070`), sin ninguna conexión de datos encima.
- Cuando cualquiera de las dos condiciones persiste `WATCHDOG_STUCK_THRESHOLD` ciclos seguidos (por defecto 2, es decir ≈20 s), ejecuta:

    ```bash
    am force-stop com.anydesk.anydeskandroid
    monkey -p com.anydesk.anydeskandroid -c android.intent.category.LAUNCHER 1
    ```

  Esto libera el `MediaProjection` colgado y relanza AnyDesk, dejándolo listo para aceptar la siguiente conexión.

- Tras cada reset se aplica un cooldown de `WATCHDOG_RESET_COOLDOWN_MS` (60 s) para evitar bucles de reinicio si la causa raíz persistiera.

Los parámetros están en `UnlockService.java` como constantes (`WATCHDOG_INTERVAL_MS`, `WATCHDOG_STUCK_THRESHOLD`, `WATCHDOG_RESET_COOLDOWN_MS`). Cada ciclo del watchdog escribe una línea en el log con el desglose de estados TCP observados (`est=`, `halfClosed=`), facilitando el diagnóstico si alguna vez no se dispara.

### Panic button: triple volume-up → soft reboot

Como red de seguridad manual para cuando el watchdog automático no acierta (o simplemente quieres resolver el cuelgue al instante sin esperar la ventana de 20 s), el servicio escucha un patrón físico en el teclado del dispositivo: **tres pulsaciones consecutivas de la tecla Volumen+ en menos de 1.5 s** disparan un soft reboot reiniciando el zygote.

- Se lee `/dev/input` directamente con `getevent -lq` bajo `su`, en un hilo dedicado. Por eso funciona:
  - Con la **pantalla apagada**.
  - Con el **Keyguard visible** (antes de desbloquear con PIN).
  - Con **cualquier app en primer plano** (AnyDesk, launcher, vídeo a pantalla completa, etc.).
  - Sin depender de un `AccessibilityService` (que Android 13+ filtra y que se desactiva solo tras algunos updates).
- Pulsaciones únicas o dobles se ignoran: no interfieren con el control de volumen normal.
- Al detectar el triple pulso, se ejecuta:

    ```bash
    setprop ctl.restart zygote
    ```

  Eso hace que `init` derribe `zygote` → `system_server` → SystemUI → todas las apps de usuario (AnyDesk, este servicio, cualquier `MediaProjection` colgada) en unos pocos segundos. El kernel **no** se reinicia, por lo que ADB sigue disponible durante toda la operación y el `BootReceiver` de esta app relanza `UnlockService` (con su `scheduleFirstBootUnlock()`) tan pronto como Android vuelve.
- Tras cada disparo se aplica un cooldown de 10 s (`TRIPLE_UP_COOLDOWN_MS`) para evitar reinicios en cadena por rebotes del botón.

Los parámetros (`TRIPLE_UP_WINDOW_MS`, `TRIPLE_UP_COUNT`, `TRIPLE_UP_COOLDOWN_MS`) son ajustables como constantes en `UnlockService.java`.

### Diálogos protegidos del sistema (permisos, install unknown apps, credentials)

Desde Android 12, ciertos diálogos del sistema (permisos runtime, diálogos de "Instalar apps desconocidas", confirmación de credenciales, etc.) se marcan como **trusted overlays** y el `InputDispatcher` **descarta los taps inyectados** desde apps normales — incluida AnyDesk y su Control Plugin. El resultado: ves la pantalla pero AnyDesk no puede pulsar los botones ("Permitir"/"Denegar") y la sesión parece quedarse congelada.

El único path de inyección que esos diálogos sí aceptan es el que viene por **shell root**, porque `input tap X Y` ejecutado desde `su` genera eventos con `POLICY_FLAG_TRUSTED`.

Para resolverlo desde Windows sin depender de AnyDesk para los toques, esta herramienta incluye un pequeño helper:

```powershell
.\tools\tap.ps1
```

Abre una ventana que muestra en vivo (auto-refresco cada 1.5 s) el screenshot del teléfono vía `adb exec-out screencap -p`. Cada clic se traduce en:

- **Botón izquierdo** → `adb shell "su -c 'input tap X Y'"` (toque inyectado a través del path trusted).
- **Botón derecho** → `adb shell "su -c 'input keyevent KEYCODE_BACK'"`.
- **Rueda / medio / F5 / botón "Refrescar"** → fuerza una captura inmediata.

Uso típico: cuando AnyDesk no puede clicar un diálogo, abres `tap.ps1` en paralelo, resuelves el diálogo con 1–2 clics, y vuelves a AnyDesk para continuar.

Parámetros:

```powershell
.\tools\tap.ps1 -AdbPath 'C:\ruta\adb.exe' -RefreshMs 1500
```

`-RefreshMs 0` desactiva el auto-refresco (útil si la red es lenta).

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
private static final long POLL_INTERVAL_MS = 10000; // 10 segundos
```

> **Nota:** Esta herramienta está diseñada para el caso de uso específico de AnyDesk + PIN en un dispositivo personal. No se ofrece soporte ni documentación para adaptar esta herramienta a dispositivos de terceros o a escenarios no personales.

## Solución de problemas

### El servicio no detecta AnyDesk

- Asegúrate de que AutoScreenCap tiene **permiso de Superusuario** en Magisk Manager
- Verifica manualmente: `su -c "dumpsys media_projection"` debería mostrar AnyDesk cuando esté conectado

### El desbloqueo falla

- Revisa el log (post-unlock): `su -c "cat /data/data/com.autoscreencap/files/autoscreencap.log"`
- Revisa el log (pre-unlock / Direct Boot): `su -c "cat /data/user_de/0/com.autoscreencap/files/autoscreencap.log"`
- Verifica que las coordenadas del deslizamiento correspondan a la resolución de tu pantalla
- Verifica que los keycodes del PIN sean correctos

### Tras reiniciar, el teléfono no se auto-desbloquea

- Comprueba que el servicio arrancó pre-unlock: `adb shell "su -c 'dumpsys activity services com.autoscreencap'"` debe listar `UnlockService`
- Comprueba que `adb shell input text` funciona antes del primer unlock (requiere clave pública ADB accesible pre-unlock)
- Si el delay de 8s no es suficiente en tu dispositivo (SystemUI tarda más), auméntalo en `scheduleFirstBootUnlock()`

### El servicio se detiene después de un tiempo

- Asegúrate de que la optimización de batería esté **desactivada** para AutoScreenCap
- El servicio usa `START_STICKY` y una notificación en primer plano para persistir

## Licencia

Licencia MIT — ver [LICENSE](LICENSE).
