#!/bin/sh
# Build the i386 bus drivers on the Rhapsody guest; stage artifacts.
# Usage: build-i386-bus-drivers.sh drvPCIBus [drvPCMCIABus ...]
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/build/tools/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin

if [ $# -eq 0 ]; then
	echo "usage: $0 drvPCIBus [drvPCMCIABus ...]" >&2
	exit 1
fi

if [ -x /usr/bin/gnumake ] && [ ! -x /usr/local/bin/make ]; then
	mkdir -p /usr/local/bin
	ln -sf /usr/bin/gnumake /usr/local/bin/make
fi

OUT=/build/out/i386
mkdir -p "$OUT"

for driver in "$@"; do
	D=/build/source/src/drivers-i386/bus/$driver
	if [ ! -f "$D/Makefile" ]; then
		echo "missing $D/Makefile" >&2
		exit 1
	fi

	# Strip CR from makefiles under this tree (Windows sync).
	find "$D" -type f \( -name Makefile -o -name 'Makefile.*' -o -name '*.make' \) -print |
	while read f; do
		tr -d '\r' < "$f" > /tmp/rhap_cr && mv /tmp/rhap_cr "$f"
	done

	echo "=== build $driver ==="
	cd "$D"
	rm -rf "/tmp/$driver-dst"
	mkdir -p "/tmp/$driver-dst"
	gnumake clean 2>/dev/null || true
	gnumake DSTROOT="/tmp/$driver-dst" install 2>&1 | tee "$OUT/$driver-build.log"

	mkdir -p "$OUT/$driver"
	find "/tmp/$driver-dst" -type d -name '*.config' -print > /tmp/found
	if [ ! -s /tmp/found ]; then
		echo "no .config produced for $driver" >&2
		find "/tmp/$driver-dst" | head -80 >&2
		exit 1
	fi
	while read d; do
		echo "found $d"
		cp -rp "$d" "$OUT/$driver/"
	done < /tmp/found
done

echo "=== artifacts ==="
find "$OUT" -name '*_reloc' -print | sort
echo "=== build-i386-bus-drivers done ==="
