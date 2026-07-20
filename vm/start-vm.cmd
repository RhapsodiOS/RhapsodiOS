@echo off
setlocal
cd /d "%~dp0"

if not exist "qemu.exe" (
  echo start-vm: qemu.exe not found in %CD%
  exit /b 1
)
if not exist "rhapsody.vmdk" (
  echo start-vm: rhapsody.vmdk not found in %CD%
  exit /b 1
)
if not exist "pc-bios" (
  echo start-vm: pc-bios directory not found in %CD%
  exit /b 1
)

echo Starting Rhapsody QEMU ^(ne2k_pci + UDP socket 5001-^>5000^)...
echo Ensure start-hecnet.cmd is already running.
echo.

qemu -L pc-bios -m 512 ^
  -k en-us ^
  -rhapsodymouse ^
  -hda rhapsody.vmdk ^
  -net nic,model=ne2k_pci,vlan=5 ^
  -net socket,udp=0.0.0.0:5001,remote=127.0.0.1:5000 ^
  -boot c

exit /b %ERRORLEVEL%
