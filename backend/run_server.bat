@echo off
title SmartQueue RS — Backend + ngrok Tunnel
color 0A

echo ============================================================
echo   SmartQueue RS — Starting Backend + ngrok Tunnel
echo   Public URL: https://unsubversively-subvitreous-braelyn.ngrok-free.dev
echo ============================================================
echo.

:: Activate virtual environment
call venv\Scripts\activate

:: Start ngrok tunnel in background
echo [1/2] Starting ngrok tunnel...
start "ngrok - SmartQueue Tunnel" cmd /k "ngrok tunnel --label edge=unsubversively-subvitreous-braelyn.ngrok-free.dev http://localhost:8100"

:: Wait a moment for ngrok to initialize
timeout /t 3 /nobreak > nul

:: Start backend server
echo [2/2] Starting FastAPI backend on port 8100...
echo.
echo Backend  : http://localhost:8100
echo Public   : https://unsubversively-subvitreous-braelyn.ngrok-free.dev
echo API Docs : https://unsubversively-subvitreous-braelyn.ngrok-free.dev/docs
echo.
echo Press Ctrl+C to stop the backend server.
echo.

uvicorn app.main:app --host 0.0.0.0 --port 8100 --reload
