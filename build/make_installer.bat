@echo off
REM Top level script: builds backend exe then packages Electron app
cd /d %~dp0
call build_backend.bat
call build_electron.bat
echo Packaging complete. The installer (NSIS) will be in electron-app\dist
pause
