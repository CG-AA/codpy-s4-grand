@echo off
rem ============================================================
rem  codpy-s4 Doctor launcher
rem  Double-click this file. It runs doctor.ps1 with the
rem  execution policy bypassed and keeps the window open.
rem  If Group Policy blocks running .ps1 files, it falls back
rem  to piping the script through PowerShell's stdin.
rem
rem  Pass-through flags (examples):
rem    doctor.bat -DiagnoseOnly       check only, change nothing
rem    doctor.bat -Fix               apply every fix without asking
rem    doctor.bat -IncludeBuild      also run the PlatformIO build
rem    doctor.bat -PatchRenderPort   auto-fix fractal\render.py port
rem ============================================================
setlocal enabledelayedexpansion
title codpy-s4 Doctor

echo(
echo   codpy-s4 Doctor - environment checkup
echo   Checks uv, Python, git, venvs, USB driver and ESP32 connectivity.
echo   Expect ONE UAC prompt only if a USB-serial driver needs installing.
echo(

set "PS=powershell"
where pwsh >nul 2>&1 && set "PS=pwsh"

set "SCRIPT=%~dp0doctor.ps1"
set "CODPY_DOCTOR_HOME=%~dp0"
set "CODPY_DOCTOR_FLAG=%TEMP%\codpy_doctor_started.flag"
if exist "%CODPY_DOCTOR_FLAG%" del /q "%CODPY_DOCTOR_FLAG%" >nul 2>&1

rem --- primary: run the .ps1 directly with policy bypassed ---
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

rem --- fallback: if the script never started (GPO blocked -File), pipe via stdin ---
if not exist "%CODPY_DOCTOR_FLAG%" (
    echo(
    echo [doctor] direct launch was blocked; retrying via stdin ^(Group Policy fallback^)...
    type "%SCRIPT%" | "%PS%" -NoProfile -ExecutionPolicy Bypass -Command -
    set "RC=!ERRORLEVEL!"
)
if exist "%CODPY_DOCTOR_FLAG%" del /q "%CODPY_DOCTOR_FLAG%" >nul 2>&1

echo(
echo [doctor] finished with exit code !RC!.
echo If anything still fails, share the newest log under doctor\logs\ with a TA.
echo Tip: CLOSE and REOPEN your terminal afterwards so PATH changes take effect.
echo(
pause
endlocal
