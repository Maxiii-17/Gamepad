@echo off
setlocal
cd /d "%~dp0"

set "PY=%~dp0.venv\Scripts\python.exe"
if exist "%PY%" goto run

set "PY=E:\Consloe\.venv\Scripts\python.exe"
if exist "%PY%" goto run

set "PY=python"

:run
"%PY%" "%~dp0server.py" %*
pause
