@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo  GitHub 一键发布向导 —— git push 通道
echo  （若 push 卡住/超时，请改用 publish-github-api.cmd）
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-github.ps1" -RepoDir "%~dp0"
echo.
pause
