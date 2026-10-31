#!/bin/sh
# Arm a driverLoader boot test on the i386 guest, then reboot.
# MODE=baseline keeps Apple's driverLoader; MODE=rebuilt installs ours and
# its libDriver.A.dylib from the unpacked driverkit apk in /build/dlr/x.
# Either way BPF and PortServer are appended to "Active Drivers" so that
# 0300_Devices' `driverLoader a` loads them.

MODE=${MODE:-baseline}
T=/usr/Devices/System.config/Instance0.table
X=/build/dlr/x

if [ "$MODE" = rebuilt ]; then
	for f in $X/usr/sbin/driverLoader $X/usr/lib/libDriver.A.dylib; do
		if [ ! -f $f ]; then echo "missing $f"; exit 1; fi
	done
	cp /usr/sbin/driverLoader /usr/sbin/driverLoader.apple
	cp $X/usr/sbin/driverLoader /usr/sbin/driverLoader
	chmod 555 /usr/sbin/driverLoader
	cp $X/usr/lib/libDriver.A.dylib /usr/lib/libDriver.A.dylib
	chmod 555 /usr/lib/libDriver.A.dylib
fi
if grep 'BPF PortServer' $T > /dev/null; then
	:
else
	sed 's/^"Active Drivers" = "\(.*\)";/"Active Drivers" = "\1 BPF PortServer";/' $T > /tmp/i0 || exit 1
	cp /tmp/i0 $T || exit 1
fi
grep '"Active Drivers"' $T
ls -l /usr/sbin/driverLoader
echo "=== armed $MODE; rebooting ==="
/sbin/reboot
