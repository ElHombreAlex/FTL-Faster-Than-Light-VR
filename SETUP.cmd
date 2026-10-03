@echo off
setlocal
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" goto environment
if defined FTLVR_PYTHON goto configured_python
where py >nul 2>nul
if not errorlevel 1 (
    py -3 -u tools\setup_environment.py %*
    goto result
)
for /f "delims=" %%P in ('where python 2^>nul') do if /i not "%%P"=="%LOCALAPPDATA%\Microsoft\WindowsApps\python.exe" if not defined FTLVR_PYTHON set "FTLVR_PYTHON=%%P"
if defined FTLVR_PYTHON goto configured_python
echo Python was not found. Install Python 3.10 or newer from python.org, including its launcher.
echo The Microsoft Store alias is not a Python installation.
echo See docs\INSTALLATION.md. No game files have been changed.
call tools\show_launcher_error.cmd
exit /b 1

:environment
".venv\Scripts\python.exe" -u tools\setup_environment.py %*
goto result

:configured_python
if not exist "%FTLVR_PYTHON%" (
    echo FTLVR_PYTHON does not point to a Python executable.
    call tools\show_launcher_error.cmd
    exit /b 1
)
"%FTLVR_PYTHON%" -u tools\setup_environment.py %*

:result
set "FTLVR_EXIT=%errorlevel%"
if not "%FTLVR_EXIT%"=="0" call tools\show_launcher_error.cmd
exit /b %FTLVR_EXIT%
