@echo off
title ngrok — SmartQueue RS Tunnel
color 0B

echo ============================================================
echo   ngrok Tunnel — SmartQueue RS
echo   Static URL: https://unsubversively-subvitreous-braelyn.ngrok-free.dev
echo ============================================================
echo.
echo Tunnel akan aktif selama jendela ini terbuka.
echo Tutup jendela ini untuk menghentikan tunnel.
echo.

ngrok start smartqueue-backend
