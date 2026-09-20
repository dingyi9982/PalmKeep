@echo off
chcp 65001 >nul
set "PALMVAULT_VERSION="
set /p "PALMVAULT_VERSION=请输入发布版本号（首次发布输入 1.0.0）："
if "%PALMVAULT_VERSION%"=="" (
  echo 未输入版本号，已取消。
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\release.ps1" -VersionName "%PALMVAULT_VERSION%"
if errorlevel 1 (
  echo.
  echo 发布失败，请根据上方信息处理。
) else (
  echo.
  echo 发布完成，安装包位于 release 目录。
)
pause
