#!/bin/sh
# Move pscp basename drops into /build/source/src/ then run retry.
set -e
for d in rbuild-1 cc-1 cctools-2 objc4-1 Csu-1; do
	if [ -d /build/source/$d ]; then
		rm -rf /build/source/src/$d 2>/dev/null || true
		mv /build/source/$d /build/source/src/$d
	fi
done
# bootstrap_cmds may land as Commands/bootstrap_cmds under RemoteRoot
if [ -d /build/source/Commands/bootstrap_cmds ]; then
	mkdir -p /build/source/src/Commands
	rm -rf /build/source/src/Commands/bootstrap_cmds 2>/dev/null || true
	# Prefer merging over the tree already under src/
	if [ -d /build/source/src/Commands ]; then
		# copy updated files over existing (HFS-safe)
		(cd /build/source/Commands && tar cf - bootstrap_cmds) |
			(cd /build/source/src/Commands && tar xf -)
		rm -rf /build/source/Commands
	else
		mv /build/source/Commands /build/source/src/Commands
	fi
fi
for m in RetryManifest RetryManifest.phase1 RetryManifest.phase2 BootstrapManifest; do
	if [ -f /build/source/$m ]; then
		mv /build/source/$m /build/source/src/$m
	fi
done
exec sh /build/source/src/rbuild-1/retry-failed.sh
