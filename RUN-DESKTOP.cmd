@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run SETUP.cmd and complete docs\INSTALLATION.md first.
    exit /b 1
)
".venv\Scripts\python.exe" tools\setup_environment.py --check --desktop
if errorlevel 1 exit /b 1
".venv\Scripts\python.exe" tools\launch.py --desktop
exit /b
