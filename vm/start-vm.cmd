@echo off
setlocal
cd /d "%~dp0"

if not exist work\test.img (
    echo ERROR: work\test.img missing. Run reset-image.cmd first.
    exit /b 1
)

set TRACEARGS=
if /i "%~1"=="-trace" (
    if not exist logs mkdir logs
    set TRACEARGS=-trace enable=ide_* -trace enable=pci_cfg_* -d int -D logs\qemu-trace.log
    echo Tracing enabled -^> logs\qemu-trace.log
)

echo Launching QEMU. Kernel serial output ^(COM2^) appears in this window.
echo.

rem RTC must be within 2 days after filesystem time (1998-05-07) to avoid kernel warning.
qemu-system-i386 -M pc -cpu pentium -accel tcg -m 128 -k en-us ^
  -nodefaults -vga cirrus ^
  -drive file=work\test.img,format=raw,if=ide,index=0,media=disk ^
  -netdev user,id=n0 -device ne2k_pci,netdev=n0 ^
  -serial null -serial stdio ^
  -rtc base=1998-05-08 ^
  -boot order=c %TRACEARGS%

echo.
exit /b %ERRORLEVEL%
