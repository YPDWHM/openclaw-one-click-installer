@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%install-openclaw.ps1"

if not exist "%PS1%" (
  echo 找不到安装脚本：%PS1%
  echo 请确认 uninstall-openclaw.bat 和 install-openclaw.ps1 在同一目录下。
  pause
  exit /b 1
)

echo 进入交互式卸载...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Uninstall

set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
  echo 卸载流程执行完成。
) else (
  echo 卸载流程失败，错误码：%EXIT_CODE%
  echo 建议把窗口截图给维护者排查。
)
pause
exit /b %EXIT_CODE%
