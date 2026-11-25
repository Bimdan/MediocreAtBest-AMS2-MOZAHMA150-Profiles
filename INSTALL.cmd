@echo off
setlocal
pushd "%~dp0" || (
  echo ERROR: Could not open the extracted folder.
  pause
  exit /b 1
)
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" (
  echo ERROR: Windows PowerShell is required.
  pause
  popd
  exit /b 1
)
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tools\SetupEngine.ps1" -Interactive
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" (echo There was a problem. Please read the message above.)
pause
popd
exit /b %RESULT%
