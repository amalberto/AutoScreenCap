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

# Log a fichero para diagnosticar (el tap.log se sobreescribe en cada arranque).
$script:LogPath = Join-Path $env:TEMP 'autoscreencap_tap.log'
"=== tap.ps1 start $(Get-Date -Format o) ===" | Set-Content -Path $script:LogPath

function Write-TapLog {
    param([string] $Msg)
    $ts = Get-Date -Format 'HH:mm:ss.fff'
    Add-Content -Path $script:LogPath -Value "$ts  $Msg"
}

function Invoke-AdbCapture {
    # Ejecuta adb con args y devuelve [bytes stdout, string stderr, int exitCode]
    param(
        [string]   $Adb,
        [string[]] $ArgList
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Adb
    foreach ($a in $ArgList) { [void]$psi.ArgumentList.Add($a) }
    $psi.UseShellExecute         = $false
    $psi.RedirectStandardOutput  = $true
    $psi.RedirectStandardError   = $true
    $psi.CreateNoWindow          = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $ms   = New-Object System.IO.MemoryStream
    $proc.StandardOutput.BaseStream.CopyTo($ms)
    $err  = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return [pscustomobject]@{
        Bytes    = $ms.ToArray()
        Stderr   = $err
        ExitCode = $proc.ExitCode
    }
}

function Get-PhoneScreencap {
    param([string] $Adb)
    $res = Invoke-AdbCapture -Adb $Adb -ArgList @('exec-out','screencap','-p')
    Write-TapLog ("screencap bytes={0} exit={1} stderrLen={2}" -f `
        $res.Bytes.Length, $res.ExitCode, $res.Stderr.Length)
    if ($res.Bytes.Length -lt 1024) {
        throw ("screencap {0}B exit={1} stderr=[{2}]" -f `
            $res.Bytes.Length, $res.ExitCode, $res.Stderr.Trim())
    }
    $ms = New-Object System.IO.MemoryStream(,$res.Bytes)
    return [System.Drawing.Image]::FromStream($ms)
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
    $cmd = "input tap $X $Y"
    Write-TapLog "TAP -> $cmd"
    $res = Invoke-AdbCapture -Adb $Adb -ArgList @('shell','su','-c',$cmd)
    $stdout = [System.Text.Encoding]::UTF8.GetString($res.Bytes).Trim()
    Write-TapLog ("  exit={0} stdout=[{1}] stderr=[{2}]" -f `
        $res.ExitCode, $stdout, $res.Stderr.Trim())
}

function Invoke-PhoneBack {
    param([string] $Adb)
    Write-TapLog "BACK"
    $res = Invoke-AdbCapture -Adb $Adb -ArgList @('shell','su','-c','input keyevent KEYCODE_BACK')
    $stdout = [System.Text.Encoding]::UTF8.GetString($res.Bytes).Trim()
    Write-TapLog ("  exit={0} stdout=[{1}] stderr=[{2}]" -f `
        $res.ExitCode, $stdout, $res.Stderr.Trim())
}

# -------- UI --------
$form = New-Object System.Windows.Forms.Form
$form.Text           = 'AutoScreenCap · Remote Tap Helper'
$form.StartPosition  = 'Manual'
$form.KeyPreview     = $true
# Ventana alta para que el screenshot del movil (aspect ~9:20) entre sin
# escalarse demasiado. Se dimensiona al 85% del alto de la pantalla y se
# centra horizontalmente en el monitor primario.
try {
    $screen  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $height  = [int]($screen.Height * 0.9)
    $width   = [int]($height * 0.55)  # ~ proporcion 9:20 + panel inferior
    if ($width -lt 500) { $width = 500 }
    $form.Size     = New-Object System.Drawing.Size($width, $height)
    $form.Location = New-Object System.Drawing.Point(
        [int]($screen.X + ($screen.Width  - $width)  / 2),
        [int]($screen.Y + ($screen.Height - $height) / 2))
} catch {
    $form.Size = New-Object System.Drawing.Size(600, 1000)
}
$form.MinimumSize = New-Object System.Drawing.Size(360, 600)

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
    Write-TapLog ("MouseDown button={0} at {1},{2}" -f $e.Button, $e.X, $e.Y)
    $coords = Convert-ClickToPhoneCoords -Pic $picture -Img $script:currentImage `
        -ClickX $e.X -ClickY $e.Y
    if ($coords -eq $null) {
        Write-TapLog "  click fuera de la imagen (currentImage null? $($script:currentImage -eq $null))"
        $lblStatus.Text = 'Click fuera de la imagen'
        return
    }
    Write-TapLog ("  -> phone coords {0},{1}" -f $coords.X, $coords.Y)
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
