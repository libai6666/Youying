@echo off
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\dev.ps1" %*
exit /b %errorlevel%
