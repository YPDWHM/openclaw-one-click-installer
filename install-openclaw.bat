@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%install-openclaw.ps1"
set "LOCAL_CONFIG=%SCRIPT_DIR%installer-config.local.json"

if not exist "%PS1%" (
  echo 找不到安装脚本：%PS1%
  pause
  exit /b 1
)

if exist "%LOCAL_CONFIG%" (
  echo 检测到 installer-config.local.json，按预设配置安装...
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -ConfigPath "%LOCAL_CONFIG%"
) else (
  echo 未检测到 installer-config.local.json，进入交互式安装...
  powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
)

set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
  echo 安装流程执行完成。
) else (
  echo 安装流程失败，错误码：%EXIT_CODE%
  echo 建议把窗口截图给维护者排查。
)
pause
exit /b %EXIT_CODE%
