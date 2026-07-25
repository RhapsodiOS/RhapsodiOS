#!/bin/sh
LOG=/build/repo/bootstrap-retry.log
for pkg in cc-1 cctools-2 objc4-1 Libc-1 Libsystem-2 bootstrap_cmds-1 system_cmds-2; do
	echo "########## $pkg ##########"
	line=`grep -n "build of \"$pkg\" failed" "$LOG" | head -1 | cut -d: -f1`
	if [ -z "$line" ]; then echo "(ok or missing)"; echo; continue; fi
	start=`expr $line - 14`
	[ "$start" -lt 1 ] && start=1
	sed -n "${start},${line}p" "$LOG"
	echo
done
echo "=== hostfix markers ==="
grep 'mv-fallback\|installed /usr/lib\|indr installed\|Device busy\|Permission denied\|maptable\|syscall_sw\|-lc' "$LOG" | head -30
