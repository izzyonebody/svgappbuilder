@echo off
cd /d %~dp0\..
cd electron-app
npm install
REM Build React and hybrid Electron production
npm run build
REM Package with electron-builder (requires electron-builder configured in package.json)
npm run dist
echo Electron build/dist complete. Check electron-app\dist
pause
