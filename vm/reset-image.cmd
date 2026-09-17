@echo off
setlocal
cd /d "%~dp0"

if not exist golden.img (
    echo ERROR: golden.img missing. Run: qemu-img convert -O raw rhapsody.vmdk golden.img
    exit /b 1
)

if not exist work mkdir work
if exist work\test.img del work\test.img

echo Recreating work\test.img from golden.img ...
qemu-img convert -O raw golden.img work\test.img
if errorlevel 1 exit /b 1

echo Done.
exit /b 0
