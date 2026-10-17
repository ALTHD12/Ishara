@echo off
REM ============================================================
REM  Ishara backend launcher  (FastAPI + MediaPipe, port 8765)
REM
REM    run.bat            start backend
REM    run.bat debug      start with per-stage latency logging
REM    run.bat nousb      start without the adb USB tunnel (Wi-Fi only)
REM
REM  Python: uses backend\venv. Override with  set ISL_PYTHON=C:\path\python.exe
REM ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0backend"

if not defined ISL_PYTHON set "ISL_PYTHON=%~dp0backend\venv\Scripts\python.exe"

if not exist "%ISL_PYTHON%" (
    echo [ERROR] Python not found at "%ISL_PYTHON%".
    goto :venvhelp
)

"%ISL_PYTHON%" -c "import fastapi, uvicorn, mediapipe, cv2, tensorflow, spacy" >nul 2>&1
if !errorlevel! neq 0 (
    echo [ERROR] "%ISL_PYTHON%" cannot import the backend packages,
    echo         or the Python it was created from no longer exists.
    goto :venvhelp
)

:args
if /i "%~1"=="debug" set "ISL_DEBUG_TIMING=1"
if /i "%~1"=="nousb" set "ISL_ADB_TUNNEL=0"
shift
if not "%~1"=="" goto :args

REM Free the port if a previous backend is still running
for /f "tokens=5" %%a in ('netstat -aon ^| findstr /r /c:":8765 .*LISTENING"') do (
    echo Stopping previous process on port 8765 [PID %%a]
    taskkill /f /pid %%a >nul 2>&1
)

set PYTHONUNBUFFERED=1
"%ISL_PYTHON%" main.py
exit /b %errorlevel%

:venvhelp
echo.
echo   Recreate the venv (Python 3.10-3.13 with TensorFlow wheels):
echo     cd backend
echo     py -3.12 -m venv venv
echo     venv\Scripts\python -m pip install -r requirements.txt
echo     venv\Scripts\python -m spacy download en_core_web_sm
echo   or point ISL_PYTHON at a working interpreter.
echo.
pause
exit /b 1
