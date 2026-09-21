#!/bin/sh
# Build the i386 booter (boot-2) with rbuild and stage boot2 as /build/out/i386/boot.
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH
DST=/build/out/booter-rbuild
rm -rf "$DST"; mkdir -p "$DST" /build/out/i386

echo "=== boot-2 via rbuild (i386) start `date` ==="
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    /build/src/boot-2 /build/repo "$DST"
echo "BOOT_RC=$?"

echo "=== apk contents ==="
for a in "$DST"/*.apk
do
	[ -f "$a" ] || continue
	echo "--- $a ---"
	gzip -dc "$a" | gnutar tf - | grep -i "standalone" | head -20
done

boot=`find "$DST" -name boot -type f 2>/dev/null | head -1`
if [ -n "$boot" ] && [ -f "$boot" ]; then
	cp "$boot" /build/out/i386/boot
	ls -l /build/out/i386/boot
fi
echo "=== booter done `date` ==="
