@echo off
setlocal
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" tools\setup_environment.py %*
    exit /b
)
where py >nul 2>nul
if not errorlevel 1 (
    py -3 tools\setup_environment.py %*
    exit /b
)
where python >nul 2>nul
if not errorlevel 1 (
    python tools\setup_environment.py %*
    exit /b
)
echo Python was not found. Install Python 3.10 or newer from python.org, including its launcher.
echo See docs\INSTALLATION.md. No game files have been changed.
exit /b 1
