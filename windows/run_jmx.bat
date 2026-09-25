@echo off
rem ============================================================================
rem  run_jmx.bat - wrapper to run Invoke-JmxScenario.ps1 from Command Prompt
rem  (runs regardless of the PowerShell execution policy)
rem  usage: run_jmx.bat -JmxFile C:\work\OrdersApi.jmx
rem  NOTE: this file is intentionally ASCII only (cmd.exe reads .bat files in the ANSI code page).
rem ============================================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-JmxScenario.ps1" %*
exit /b %ERRORLEVEL%
