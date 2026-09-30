@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo  GitHub 一键发布向导 —— GitHub API 通道
echo  适用于 github.com 连不通、但 api.github.com 可用的网络
echo  会自动: 识别账号 - 检查网络 - 创建仓库 - 设置 Topics - 同步提交历史
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-github-api.ps1" -RepoDir "%~dp0"
echo.
pause
