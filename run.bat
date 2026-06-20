@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo               ISL Semantic Converter Setup and Launcher
echo =====================================================================
echo.

REM 1. Check Node.js installation
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js is not installed or not in your PATH.
    echo Please install Node.js from https://nodejs.org/ to run the frontend.
    echo.
    pause
    exit /b 1
)

REM 2. Check Python installation
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in your PATH.
    echo Please install Python 3.x to run the backend.
    echo.
    pause
    exit /b 1
)

echo [1/4] Checking Frontend dependencies...
cd frontend
if not exist node_modules (
    echo node_modules folder not found. Installing dependencies...
    call npm install
) else (
    echo Frontend dependencies are already installed.
)
cd ..
echo.

echo [2/4] Checking Backend virtual environment...
cd backend
if not exist venv (
    echo Virtual environment 'venv' not found. Creating virtual environment...
    python -m venv venv
    if !errorlevel! neq 0 (
        echo [ERROR] Failed to create virtual environment.
        cd ..
        pause
        exit /b 1
    )
)

echo Activating virtual environment and installing backend dependencies...
call venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt

echo Checking for spaCy 'en_core_web_sm' model...
python -c "import spacy; spacy.load('en_core_web_sm')" >nul 2>&1
if !errorlevel! neq 0 (
    echo Downloading spaCy 'en_core_web_sm' model...
    python -m spacy download en_core_web_sm
) else (
    echo spaCy model 'en_core_web_sm' is already installed.
)
cd ..
echo.

echo [3/4] Cleaning up any existing processes on ports 8000 and 5173...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":8000" ^| findstr "LISTENING"') do (
    echo Terminating duplicate backend process %%a...
    taskkill /f /pid %%a >nul 2>&1
)
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":5173" ^| findstr "LISTENING"') do (
    echo Terminating duplicate frontend process %%a...
    taskkill /f /pid %%a >nul 2>&1
)
echo.

echo [4/4] Starting services in this terminal...
echo Press Ctrl+C in this terminal to stop both servers at once.
echo.

REM Spawn background task to open the browser after a short delay
start "" cmd /c "timeout /t 3 /nobreak >nul && start http://localhost:5173"

REM Start both services concurrently in the current terminal window
call npx -y concurrently -k -n "backend,frontend" -c "blue,green" "cd backend && call venv\Scripts\activate && uvicorn main:app --reload --port 8000" "cd frontend && npm run dev"
