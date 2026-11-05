@echo off
setlocal
cd /d "%~dp0"

set "PY="
if exist ".venv\Scripts\python.exe" set "PY=.venv\Scripts\python.exe"
if not defined PY if exist "D:\Project of console\Consloe\.venv\Scripts\python.exe" set "PY=D:\Project of console\Consloe\.venv\Scripts\python.exe"
if not defined PY where python >nul 2>&1 && set "PY=python"

if not defined PY (
    echo Gamepad virtual environment not found.
    echo Create it with:
    echo   python -m venv .venv
    echo   .venv\Scripts\python.exe -m pip install -r requirements.txt
    pause
    exit /b 1
)

"%PY%" server.py
pause
PY