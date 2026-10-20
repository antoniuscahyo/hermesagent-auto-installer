@echo off
REM ===========================================================================
REM  Hermes Agent - Windows installer launcher
REM  Double-click file ini. Semua konfigurasi ada di install-hermes.ps1 ($CFG).
REM ===========================================================================
setlocal
cd /d "%~dp0"

echo.
echo  Menjalankan installer Hermes Agent...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-hermes.ps1"
set RC=%ERRORLEVEL%

echo.
if not "%RC%"=="0" (
    echo  [x] Installer berhenti dengan kode %RC%.
    echo      Baca pesan error di atas. Log ada di %%LOCALAPPDATA%%\hermes\logs\install-win-*.log
) else (
    echo  [OK] Selesai. Tutup jendela ini, buka PowerShell baru, lalu jalankan: hermes
)
echo.
pause
endlocal
