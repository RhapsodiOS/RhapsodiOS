@echo off
setlocal
cd /d "%~dp0"

echo Launching QEMU...
echo.

qemu-system-i386 -M pc -cpu pentium -accel tcg -m 128 -k en-us -vga cirrus -hda rhapsody.vmdk -net nic,model=ne2k_pci -net user -boot order=c

echo.
exit /b %ERRORLEVEL%