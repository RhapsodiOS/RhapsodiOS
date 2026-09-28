#!/bin/sh
# Collect evidence after a driverLoader boot test.
echo "== driverLoader"; ls -l /usr/sbin/driverLoader /usr/lib/libDriver.A.dylib 2>&1
echo "== Active Drivers"; grep '"Active Drivers"' /usr/Devices/System.config/Instance0.table
echo "== bpf"; ls -l /dev/ | grep bpf
echo "== ttyd"; ls -l /dev/ | grep ttyd
echo "== pdservd"; ps -axww | grep pdservd | grep -v grep
echo "== Devices"; ls /usr/Devices/
echo "=== boot check done ==="
