#!/bin/sh
# Stage-0 native bootstrap of build-base seed packages (host-arch only).
# Rebuilds rbuild, applies host-fixes, wipes repo apks + BUILDIT roots, then
# runs `rbuild bootstrap`.
set -e
export PATH=/build/bin:/usr/local/bin:/build/tools/usr/local/bin:/build/tools/usr/bin:/bin:/usr/bin:/sbin:/usr/sbin
export CONFIG_DIR=/build/tools/usr/local/bin
# Keep build roots off the small root filesystem
export BUILDIT_DIR=/big/roots

SRC=/build/source/src
REPO=/build/repo
LOG=/build/repo/bootstrap.log

mkdir -p "$REPO" "$BUILDIT_DIR" /build/built
cd "$SRC" || exit 1

# Prefer freshly synced tree under src/; drop stale basename-dropped copy.
if [ -d /build/source/rbuild-1 ] && [ ! -f /build/source/src/rbuild-1/host-fixes.sh ]; then
	rm -rf /build/source/src/rbuild-1
	mv /build/source/rbuild-1 /build/source/src/rbuild-1
elif [ -d /build/source/rbuild-1 ]; then
	rm -rf /build/source/rbuild-1
fi
if [ -f /build/source/BootstrapManifest ]; then
	mv /build/source/BootstrapManifest /build/source/src/BootstrapManifest
fi

echo "=== rebuild rbuild ===" | tee "$LOG"
cd /build/source/src/rbuild-1
find . -type f \( -name '*.c' -o -name '*.h' -o -name Makefile -o -name '*.sh' \) -print |
while read f; do tr -d '\r' < "$f" > /tmp/rb_cr && mv /tmp/rb_cr "$f"; done
make clean || true
make
make install DSTROOT=/tmp/rbuild-dst
cp /tmp/rbuild-dst/usr/bin/rbuild /usr/local/bin/rbuild
chmod 755 /usr/local/bin/rbuild

echo "=== host fixes ===" | tee -a "$LOG"
sh /build/source/src/rbuild-1/host-fixes.sh 2>&1 | tee -a "$LOG"

cd "$SRC"
tr -d '\r' < BootstrapManifest > /tmp/bmf && mv /tmp/bmf BootstrapManifest

for pair in \
  basic_cmds-1:Commands/basic_cmds \
  bootstrap_cmds-1:Commands/bootstrap_cmds \
  developer_cmds-1:Commands/developer_cmds \
  file_cmds-1:Commands/file_cmds \
  shell_cmds-2:Commands/shell_cmds \
  system_cmds-2:Commands/system_cmds \
  text_cmds-1:Commands/text_cmds \
  tcsh-1:Commands/tcsh \
  zsh-1:Commands/zsh
do
	name=`echo "$pair" | cut -d: -f1`
	tgt=`echo "$pair" | cut -d: -f2`
	if [ -d "$tgt" ]; then
		rm -f "$name"
		ln -s "$tgt" "$name"
	else
		echo "WARNING: missing $tgt for $name" | tee -a "$LOG"
	fi
done

if [ -x /usr/bin/gnumake ]; then
	mkdir -p /usr/local/bin
	ln -sf /usr/bin/gnumake /usr/local/bin/make
fi

echo "=== rbuild bootstrap starting ===" | tee -a "$LOG"
which rbuild | tee -a "$LOG"
echo "BUILDIT_DIR=$BUILDIT_DIR" | tee -a "$LOG"

echo "Removing existing .apk under $REPO (keeping .deb)" | tee -a "$LOG"
rm -f "$REPO"/*.apk
# HFS rm -rf often exits non-zero with fts_read noise; do not abort.
rm -rf "$BUILDIT_DIR"/* 2>/dev/null || true
mkdir -p "$BUILDIT_DIR"

rbuild bootstrap BootstrapManifest "$REPO" "$REPO" 2>&1 | tee -a "$LOG"
ec=$?
echo "=== rbuild bootstrap finished exit=$ec ===" | tee -a "$LOG"
echo "APKs:" | tee -a "$LOG"
ls "$REPO"/*.apk 2>/dev/null | tee -a "$LOG"
ls "$REPO"/*.apk 2>/dev/null | wc -l | tee -a "$LOG"
exit $ec
