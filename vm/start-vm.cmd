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

rem RTC must be strictly after filesystem time (fs_time epoch 894585442 =
rem 1998-05-07T23:57:22Z) and within 2 days of it, or inittodr() in
rem src/kernel-7/bsd/kern/kern_time.c prints a clock warning at boot.
rem 1998-05-08T12:00:00 is 12 hours after fs_time, staying inside that
rem window while tolerating up to 12 hours of negative timezone skew in
rem how QEMU interprets the RTC base. Keep this in sync with RTC_BASE in
rem vm/qemu-shot.py.
qemu-system-i386 -M pc -cpu pentium -accel tcg -m 128 -k en-us ^
  -nodefaults -vga cirrus ^
  -drive file=work\test.img,format=raw,if=ide,index=0,media=disk ^
  -netdev user,id=n0 -device ne2k_pci,netdev=n0 ^
  -serial null -serial stdio ^
  -rtc base=1998-05-08T12:00:00 ^
  -boot order=c %TRACEARGS%

echo.
exit /b %ERRORLEVEL%
