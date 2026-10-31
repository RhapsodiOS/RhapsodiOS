#!/bin/sh
# Universal rbuild of driverkit-3 (with driverLoader) in the private tree
# /build/dlr, then split driverLoader into thin slices for binrecon.
# Rhapsody's /bin/sh is a 1999 Bourne shell: keep it plain.

B=/build/dlr
PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH
TC=/build/src/rbuild-1/toolchains/gcc-darwin-universal.conf

# A private repo holds a freshly built kernload when the shared one is stale.
REPO=/build/repo
if [ -d $B/repo ]; then REPO=$B/repo; fi

rm -rf $B/out $B/x $B/driverLoader.i386 $B/driverLoader.ppc
mkdir -p $B/out $B/state $B/x
echo "======== rbuild buildpackage driverkit-3 (universal, repo $REPO) ========"
rbuild buildpackage --state $B/state --toolchain $TC \
	$B/src/driverkit-3 $REPO $B/out > $B/rbuild.log 2>&1
rc=$?
tail -40 $B/rbuild.log
echo "RBUILD_RC=$rc"
if [ $rc != 0 ]; then
	echo "FAILED: rbuild; the build root is under /private/tmp/roots/"
	exit 1
fi

APK=
for f in $B/out/driverkit-[0-9]*-universal.apk; do
	if [ -f "$f" ]; then APK=$f; fi
done
if [ -z "$APK" ]; then
	echo "FAILED: no driverkit universal apk in $B/out"
	ls -l $B/out
	exit 1
fi
cp $APK $B/driverkit-universal.apk
(cd $B/x && gzip -dc $APK | tar xf -) || exit 1
DL=$B/x/usr/sbin/driverLoader
for f in $DL $B/x/usr/share/man/man8/driverLoader.8 $B/x/usr/lib/libDriver.A.dylib; do
	if [ ! -f $f ]; then
		echo "FAILED: apk lacks $f"
		exit 1
	fi
done
lipo -info $DL
lipo -thin i386 -output $B/driverLoader.i386 $DL || exit 1
lipo -thin ppc -output $B/driverLoader.ppc $DL || exit 1
ls -l $DL $B/x/usr/share/man/man8/driverLoader.8 $B/driverLoader.i386 $B/driverLoader.ppc
echo "=== driverloader build done: $APK ==="
