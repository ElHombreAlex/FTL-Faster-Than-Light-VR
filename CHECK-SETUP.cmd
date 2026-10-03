@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Run SETUP.cmd first. This check does not install or launch anything.
    call tools\show_launcher_error.cmd
    exit /b 1
)
".venv\Scripts\python.exe" -u tools\setup_environment.py --check %*
set "FTLVR_EXIT=%errorlevel%"
if not "%FTLVR_EXIT%"=="0" call tools\show_launcher_error.cmd
exit /b %FTLVR_EXIT%
