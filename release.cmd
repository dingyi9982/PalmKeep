@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\release.ps1"
set "PALMKEEP_EXIT_CODE=%ERRORLEVEL%"
if not "%PALMKEEP_EXIT_CODE%"=="0" (
  echo.
  echo Release failed. Review the message above.
) else (
  echo.
  echo Release completed. The package is in the release directory.
)
pause
exit /b %PALMKEEP_EXIT_CODE%
