@echo off
REM Build backend into a single exe using PyInstaller (Windows)
cd /d %~dp0\..
cd backend
if not exist venv (
  python -m venv venv
  call venv\Scripts\activate
  pip install -r requirements.txt
) else (
  call venv\Scripts\activate
)
pip install pyinstaller
pyinstaller --onefile --name backend_exe app\main.py
REM Copy produced exe to electron-app/resources/backend (create folder if needed)
if not exist ..\electron-app\resources mkdir ..\electron-app\resources
if not exist ..\electron-app\resources\backend mkdir ..\electron-app\resources\backend
copy dist\backend_exe.exe ..\electron-app\resources\backend\backend.exe
echo Backend exe created and copied.
pause
