@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run SETUP.cmd first. This check does not install or launch anything.
    exit /b 1
)
".venv\Scripts\python.exe" tools\setup_environment.py --check %*
exit /b
