@echo off
setlocal
cd /d "%~dp0"

if not exist "hecnet.exe" (
  echo start-hecnet: hecnet.exe not found in %CD%
  exit /b 1
)
if not exist "bridge.conf" (
  echo start-hecnet: bridge.conf not found.
  echo Copy bridge.conf.example to bridge.conf and set the NPF device via ethlist.exe
  exit /b 1
)

echo Starting hecnet ^(leave this window open^)...
echo Bridge config: %CD%\bridge.conf
hecnet.exe
set ERR=%ERRORLEVEL%
echo hecnet exited with code %ERR%
exit /b %ERR%
