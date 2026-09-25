@echo off
rem ============================================================================
rem  openapi2jmx.bat - wrapper to run OpenApi2Jmx.ps1 from Command Prompt
rem  (runs regardless of the PowerShell execution policy)
rem  usage: openapi2jmx.bat -InputFile C:\work\openapi.json -OutputFile C:\work\OrdersApi.jmx
rem  NOTE: this file is intentionally ASCII only (cmd.exe reads .bat files in the ANSI code page).
rem ============================================================================
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OpenApi2Jmx.ps1" %*
exit /b %ERRORLEVEL%
