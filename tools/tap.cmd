@echo off
REM Launcher para tap.ps1. Doble-click este .cmd en vez del .ps1 directamente.
REM - Usa pwsh (PowerShell 7) si esta en PATH, si no cae a powershell.exe 5.1.
REM - ExecutionPolicy Bypass evita el bloqueo habitual con .ps1 no firmados.
REM - NoExit deja la ventana abierta si tap.ps1 aborta con error, para leerlo.
setlocal
set "SCRIPT=%~dp0tap.ps1"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    start "" pwsh  -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT%" %*
) else (
    start "" powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT%" %*
)
endlocal
