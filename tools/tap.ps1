<#
.SYNOPSIS
    Visor + tap remoto para pantallas "protegidas" de Android.

.DESCRIPTION
    Muestra un screenshot en vivo del telefono y convierte cada clic (izquierdo,
    derecho, medio) en un comando inyectado via ADB + su, que por venir de shell
    lleva POLICY_FLAG_TRUSTED y es aceptado por dialogos del sistema que
    descartan los taps inyectados por AnyDesk (permisos runtime, install
    unknown apps, credential confirm, etc.).

    - Click izquierdo:  input tap   X Y
    - Click derecho:    input keyevent KEYCODE_BACK   (sin tap)
    - Rueda / medio:    refresca la captura (equivalente al boton)
    - Boton "Refrescar": vuelve a capturar inmediatamente.
    - Auto-refresco:    por defecto cada 1500 ms (ajustable con -RefreshMs).

.PARAMETER AdbPath
    Ruta al ejecutable adb. Por defecto usa el del Paquete SDK Minimal.

.PARAMETER RefreshMs
    Intervalo de auto-refresco en ms. 0 = desactivado.

.EXAMPLE
    .\tap.ps1
    Lanza la ventana con auto-refresco cada 1500 ms.

.EXAMPLE
    .\tap.ps1 -RefreshMs 0
    Ventana sin auto-refresco (refrescar manualmente con la rueda o el boton).

.NOTES
    Requiere: ADB disponible, root (Magisk) en el dispositivo, y autorizacion
    persistente del ADB key (ya configurada en /product/etc/security/adb_keys).
#>

[CmdletBinding()]
param(
    [string] $AdbPath   = 'D:\Paquete_SDK_ANDROID_MINIMAL\platform-tools\adb.exe',
    [int]    $RefreshMs = 1500
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $AdbPath)) {
    throw "No encuentro adb en '$AdbPath'. Pasa -AdbPath."
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-PhoneScreencap {
    param([string] $Adb)
    # adb exec-out screencap -p sale en stdout binario puro (PNG).
    # Lo capturamos como bytes para no corromperlo con la codificacion de PS.
    $tmp = [System.IO.Path]::GetTempFileName() + '.png'
    try {
        & $Adb exec-out screencap -p | Set-Content -Path $tmp -Encoding Byte
        if ((Get-Item $tmp).Length -lt 1024) {
            throw "screencap devolvio un fichero de 0 bytes. Esta el movil conectado?"
        }
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        return [System.Drawing.Image]::FromStream($ms)
    } finally {
        if (Test-Path $tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
}

function Invoke-PhoneTap {
    param(
        [string] $Adb,
        [int]    $X,
        [int]    $Y
    )
    # input tap ejecutado bajo su -> lleva POLICY_FLAG_TRUSTED, asi que los
    # dialogos protegidos de Android 12+ lo aceptan (a diferencia de los taps
    # inyectados por AnyDesk Control Plugin).
    & $Adb shell "su -c `"input tap $X $Y`""
}

function Invoke-PhoneBack {
    param([string] $Adb)
    & $Adb shell "su -c `"input keyevent KEYCODE_BACK`""
}

# -------- UI --------
$form = New-Object System.Windows.Forms.Form
$form.Text           = 'AutoScreenCap · Remote Tap Helper'
$form.StartPosition  = 'CenterScreen'
$form.KeyPreview     = $true

$picture = New-Object System.Windows.Forms.PictureBox
$picture.SizeMode = 'Zoom'
$picture.Dock     = 'Fill'

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock   = 'Bottom'
$panel.Height = 40

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refrescar (F5)'
$btnRefresh.Left = 8
$btnRefresh.Top  = 8
$btnRefresh.Width = 140

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = 'BACK'
$btnBack.Left = 156
$btnBack.Top  = 8
$btnBack.Width = 80

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Left = 250
$lblStatus.Top  = 12
$lblStatus.Width = 800
$lblStatus.Text  = 'Listo'

$panel.Controls.AddRange(@($btnRefresh, $btnBack, $lblStatus))
$form.Controls.Add($picture)
$form.Controls.Add($panel)

$script:currentImage = $null

function Update-Screencap {
    $lblStatus.Text = 'Capturando...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $img = Get-PhoneScreencap -Adb $AdbPath
        if ($script:currentImage -ne $null) {
            $old = $script:currentImage
            $script:currentImage = $img
            $picture.Image = $img
            $old.Dispose()
        } else {
            $script:currentImage = $img
            $picture.Image = $img
        }
        $lblStatus.Text = ("{0}x{1} - {2:HH:mm:ss}" -f $img.Width, $img.Height, (Get-Date))
    } catch {
        $lblStatus.Text = "Error: $($_.Exception.Message)"
    }
}

function Convert-ClickToPhoneCoords {
    param(
        [System.Windows.Forms.PictureBox] $Pic,
        [System.Drawing.Image]            $Img,
        [int] $ClickX,
        [int] $ClickY
    )
    # PictureBox con SizeMode=Zoom: la imagen se encaja manteniendo aspecto.
    if ($Img -eq $null) { return $null }
    $cw = $Pic.ClientSize.Width
    $ch = $Pic.ClientSize.Height
    $iw = $Img.Width
    $ih = $Img.Height
    $ratio  = [Math]::Min($cw / $iw, $ch / $ih)
    $drawnW = $iw * $ratio
    $drawnH = $ih * $ratio
    $offX   = ($cw - $drawnW) / 2.0
    $offY   = ($ch - $drawnH) / 2.0
    $relX = $ClickX - $offX
    $relY = $ClickY - $offY
    if ($relX -lt 0 -or $relY -lt 0 -or $relX -gt $drawnW -or $relY -gt $drawnH) {
        return $null
    }
    return @{
        X = [int]($relX / $ratio)
        Y = [int]($relY / $ratio)
    }
}

$picture.Add_MouseDown({
    param($s, $e)
    $coords = Convert-ClickToPhoneCoords -Pic $picture -Img $script:currentImage `
        -ClickX $e.X -ClickY $e.Y
    if ($coords -eq $null) {
        $lblStatus.Text = 'Click fuera de la imagen'
        return
    }
    switch ($e.Button) {
        'Left' {
            $lblStatus.Text = "Tap $($coords.X),$($coords.Y)..."
            [System.Windows.Forms.Application]::DoEvents()
            Invoke-PhoneTap -Adb $AdbPath -X $coords.X -Y $coords.Y | Out-Null
            Start-Sleep -Milliseconds 400
            Update-Screencap
        }
        'Right' {
            $lblStatus.Text = 'BACK'
            [System.Windows.Forms.Application]::DoEvents()
            Invoke-PhoneBack -Adb $AdbPath | Out-Null
            Start-Sleep -Milliseconds 400
            Update-Screencap
        }
        'Middle' {
            Update-Screencap
        }
    }
})

$btnRefresh.Add_Click({ Update-Screencap })
$btnBack.Add_Click({
    Invoke-PhoneBack -Adb $AdbPath | Out-Null
    Start-Sleep -Milliseconds 400
    Update-Screencap
})

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq 'F5') { Update-Screencap; $e.Handled = $true }
})

if ($RefreshMs -gt 0) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $RefreshMs
    $timer.Add_Tick({ Update-Screencap })
    $form.Add_Shown({ Update-Screencap; $timer.Start() })
    $form.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
} else {
    $form.Add_Shown({ Update-Screencap })
}

[void] $form.ShowDialog()
if ($script:currentImage -ne $null) { $script:currentImage.Dispose() }
