@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo This checkout is not configured. Run SETUP.cmd and complete docs\INSTALLATION.md first.
    call tools\show_launcher_error.cmd
    exit /b 1
)
".venv\Scripts\python.exe" -u tools\launch.py %*
set "FTLVR_EXIT=%errorlevel%"
if not "%FTLVR_EXIT%"=="0" call tools\show_launcher_error.cmd
exit /b %FTLVR_EXIT%
