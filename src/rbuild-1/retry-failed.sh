#!/bin/sh
# Apply host fixes, rebuild rbuild, re-run native bootstrap for failed pkgs.
# Phase 1 builds cc+cctools so indr exists; phase 2 installs indr; phase 3 rest.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin
export CONFIG_DIR=/build/tools/usr/local/bin
export BUILDIT_DIR=/big/roots

SRC=/build/source/src
REPO=/build/repo
LOG=/build/repo/bootstrap-retry.log

if [ -d /build/source/rbuild-1 ]; then
	rm -rf /build/source/src/rbuild-1 2>/dev/null || true
	mv /build/source/rbuild-1 /build/source/src/rbuild-1
fi
if [ -f /build/source/RetryManifest ]; then
	mv /build/source/RetryManifest /build/source/src/RetryManifest
fi
if [ -f /build/source/RetryManifest.phase1 ]; then
	mv /build/source/RetryManifest.phase1 /build/source/src/RetryManifest.phase1
fi
if [ -f /build/source/RetryManifest.phase2 ]; then
	mv /build/source/RetryManifest.phase2 /build/source/src/RetryManifest.phase2
fi

echo "=== rebuild rbuild ==="
cd /build/source/src/rbuild-1
find . -type f \( -name '*.c' -o -name '*.h' -o -name Makefile -o -name '*.sh' \) -print |
while read f; do tr -d '\r' < "$f" > /tmp/rb_cr && mv /tmp/rb_cr "$f"; done
make clean || true
make
make install DSTROOT=/tmp/rbuild-dst
cp /tmp/rbuild-dst/usr/bin/rbuild /usr/local/bin/rbuild
chmod 755 /usr/local/bin/rbuild

echo "=== host fixes ==="
sh /build/source/src/rbuild-1/host-fixes.sh

cd "$SRC"
for mf in RetryManifest RetryManifest.phase1 RetryManifest.phase2; do
	[ -f "$mf" ] && tr -d '\r' < "$mf" > /tmp/rmf && mv /tmp/rmf "$mf"
done

for pair in \
  basic_cmds-1:Commands/basic_cmds \
  bootstrap_cmds-1:Commands/bootstrap_cmds \
  developer_cmds-1:Commands/developer_cmds \
  file_cmds-1:Commands/file_cmds \
  shell_cmds-2:Commands/shell_cmds \
  system_cmds-2:Commands/system_cmds \
  text_cmds-1:Commands/text_cmds \
  zsh-1:Commands/zsh
do
	name=`echo "$pair" | cut -d: -f1`
	tgt=`echo "$pair" | cut -d: -f2`
	if [ -d "$tgt" ]; then rm -f "$name"; /bin/ln -s "$tgt" "$name"; fi
done
[ -x /usr/bin/gnumake ] && /bin/ln -sf /usr/bin/gnumake /usr/local/bin/make

mkdir -p "$BUILDIT_DIR" "$REPO"

# Remove apks AND stale HFS build roots for packages we are retrying.
# HFS cannot rename-over existing files (rsync "Device busy"), so roots
# must be wiped before rsync clones sources again.
# Note: rm -rf on large HFS trees often exits non-zero with
# "fts_read: No such file or directory" even when cleanup mostly worked;
# do not abort the retry on that.
for pat in cc- cctools- csu- objc4- libc- libsystem- bootstrap-cmds- \
	system-cmds- zsh-; do
	rm -f "$REPO"/${pat}*.apk 2>/dev/null || true
	rm -rf "$BUILDIT_DIR"/${pat}*.roots 2>/dev/null || true
done
# Second pass for stubborn leftovers
for d in "$BUILDIT_DIR"/cc-*.roots "$BUILDIT_DIR"/cctools-*.roots \
	"$BUILDIT_DIR"/csu-*.roots "$BUILDIT_DIR"/objc4-*.roots \
	"$BUILDIT_DIR"/libc-*.roots "$BUILDIT_DIR"/libsystem-*.roots \
	"$BUILDIT_DIR"/bootstrap-cmds-*.roots "$BUILDIT_DIR"/system-cmds-*.roots \
	"$BUILDIT_DIR"/zsh-*.roots; do
	[ -e "$d" ] || continue
	rm -rf "$d" 2>/dev/null || true
done

: > "$LOG"
install_indr() {
	echo "=== install cctools tools from *.NEW ===" | tee -a "$LOG"
	for tool in indr nmedit strip lipo libtool nm size strings segedit; do
		found=`find /big/roots/cctools-*.roots -name "${tool}.NEW" -type f 2>/dev/null | head -1`
		if [ -z "$found" ] && [ "$tool" = indr ]; then
			found=`find /big/roots/cctools-*.roots -path '*/usr/local/bin/indr' -type f 2>/dev/null | head -1`
		fi
		if [ -n "$found" ]; then
			rm -f /usr/local/bin/$tool
			cp -p "$found" /usr/local/bin/$tool
			chmod 755 /usr/local/bin/$tool
			echo "$tool installed from $found" | tee -a "$LOG"
		else
			echo "WARNING: $tool.NEW not found after cctools" | tee -a "$LOG"
		fi
	done
	ls -l /usr/local/bin/indr /usr/local/bin/nmedit 2>&1 | tee -a "$LOG"
}

echo "=== phase1: cc + cctools ===" | tee -a "$LOG"
echo "BUILDIT_DIR=$BUILDIT_DIR PATH=$PATH" | tee -a "$LOG"
rbuild bootstrap RetryManifest.phase1 "$REPO" "$REPO" 2>&1 | tee -a "$LOG"
install_indr

echo "=== phase2: remaining failed packages ===" | tee -a "$LOG"
rbuild bootstrap RetryManifest.phase2 "$REPO" "$REPO" 2>&1 | tee -a "$LOG"
ec=$?
echo "=== retry finished exit=$ec ===" | tee -a "$LOG"
echo "APKs:" | tee -a "$LOG"
ls "$REPO"/*.apk 2>/dev/null | tee -a "$LOG"
ls "$REPO"/*.apk 2>/dev/null | wc -l | tee -a "$LOG"
exit $ec
