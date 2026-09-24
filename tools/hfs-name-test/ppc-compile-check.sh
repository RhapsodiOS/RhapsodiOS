#!/bin/sh
# Compile the HFS sources that differ from BASE-REV with the real ppc kernel
# flags on the build box, once as they are at BASE-REV and once as they are in
# the working tree, and compare the two builds' warnings and undefined symbols.
#
# Usage (from anywhere in the repository):
#   tools/hfs-name-test/ppc-compile-check.sh BASE-REV
#
# Needs Python, RHAP_VM_DIR in a worktree (see box-run.ps1), a finished ppc
# kernel build on the box (its chroot under /private/tmp/roots supplies the
# other kernel headers and meta_features.h) and no rbuild running there.
# Exits non-zero if a file fails to compile or its warnings differ from
# BASE-REV's.  Differences in nm -u are reported, not failed.
set -e
[ $# -eq 1 ] || { echo "usage: $0 BASE-REV" >&2; exit 2; }
base=$1
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
hfs=src/kernel-7/bsd/hfs
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

changed=$(git -C "$root" diff --name-only "$base" -- "$hfs" | sed "s|^$hfs/||")
[ -n "$changed" ] || { echo "nothing under $hfs differs from $base"; exit 0; }
sources=$(echo "$changed" | grep '\.c$' || true)

# The working tree's hfs directory, and BASE-REV's copies of the changed files.
# They hold Mac Roman bytes, so both go to the box as uuencoded tars.  Archiving
# a subtree leaves out the root .gitattributes (eol=lf), so a global
# core.autocrlf=true would turn the base files' line endings into CRLF.
mkdir "$work/new"
cp -R "$root/$hfs" "$work/new/hfs"
(cd "$work" && tar --format=ustar -cf new.tar new)	# relative: GNU tar reads "C:/..." as host:path
git -C "$root" -c core.autocrlf=false archive --format=tar --prefix=base/hfs/ "$base:$hfs" $changed > "$work/base.tar"

uu() {
	python -c '
import binascii, sys
data = open(sys.argv[1], "rb").read()
sys.stdout.write("begin 644 %s\n" % sys.argv[2])
for i in range(0, len(data), 45):
    sys.stdout.write(binascii.b2a_uu(data[i:i + 45], backtick=True).decode("ascii"))
sys.stdout.write("`\nend\n")' "$1" "$2"
}

{
	cat <<'EOF'
set -u
if ps -axww | grep -v grep | grep rbuild >/dev/null; then
	echo "an rbuild is running on the box; try again when it has finished"
	exit 1
fi
R=
for r in /private/tmp/roots/kernel-*.roots/kernel-*.root; do
	if [ -f "$r${r%.root}.obj/RELEASE_PPC/meta_features.h" ]; then R=$r; fi
done
if [ -z "$R" ]; then echo "no finished ppc kernel build under /private/tmp/roots"; exit 1; fi
K=${R%.root}
O=$R$K.obj/RELEASE_PPC
W=/build/hfs-ppc-check-$$
mkdir -p $W && cd $W || exit 1
EOF
	echo "cat > new.uu <<'@@HFSPPCCHECK@@'"
	uu "$work/new.tar" new.tar
	echo "@@HFSPPCCHECK@@"
	echo "cat > base.uu <<'@@HFSPPCCHECK@@'"
	uu "$work/base.tar" base.tar
	echo "@@HFSPPCCHECK@@"
	echo "SOURCES='$(echo $sources)'"
	cat <<'EOF'
if ! (uudecode new.uu && uudecode base.uu && tar -xf new.tar && cp -R new base && tar -xf base.tar); then
	echo "could not unpack the sources on the box"; cd /; rm -rf $W; exit 1
fi
status=0
for f in $SOURCES; do
	b=`basename $f .c`
	for v in base new; do
		if ! cc -static -nostdinc -nostdlib -traditional-cpp -fno-builtin -c -g -O2 -MD \
			-imacros $O/meta_features.h -I$O -I$R$K -I$R$K/bsd -I$R$K/bsd/include \
			-I$R$K/machdep -I$R$K/bsd/netat -I$R$K/bsd/netat/h -I$R$K/bsd/netat/at \
			-I$R/System/Library/Frameworks/System.framework/PrivateHeaders \
			-I$R/System/Library/Frameworks/System.framework/Headers \
			-I$R/System/Library/Frameworks/System.framework/Headers/bsd \
			-DNEXT -DTIMEZONE="0" -DPST="0" -DINET -DMACH -DNO_DIRECT_RPC -DNETAT -DDEBUG \
			-DARCH_PRIVATE -D_KERNEL -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DKERNEL_BUILD \
			-D__APPLE__ -DNeXT -D_NEXT_SOURCE -arch ppc -I$R$K/bsd/include -finline \
			-fno-keep-inline-functions -force_cpusubtype_ALL -fwritable-strings -fno-common \
			-msoft-float -mcpu=604 -Dppc -DPPC -Wall -Wno-four-char-constants -fpascal-strings \
			$W/$v/hfs/$f -o $W/$v/$b.o > $W/$v/$b.warn 2>&1; then
			echo "$v/$f: compile FAILED"; cat $W/$v/$b.warn; status=1
		fi
		sed -e "s|$W/$v/hfs/||g" -e 's/:[0-9][0-9]*:/:/' $W/$v/$b.warn > $W/$v/$b.norm
		nm -u $W/$v/$b.o > $W/$v/$b.undef 2>/dev/null || true
	done
	echo "== $f: `grep -c warning $W/new/$b.warn` warning(s)"
	if cmp -s $W/base/$b.norm $W/new/$b.norm; then
		echo "   warnings: same as base"
	else
		echo "   warnings differ from base:"; diff $W/base/$b.norm $W/new/$b.norm; status=1
	fi
	if cmp -s $W/base/$b.undef $W/new/$b.undef; then
		echo "   nm -u: same as base"
	else
		echo "   nm -u differs from base:"; diff $W/base/$b.undef $W/new/$b.undef
	fi
done
cd /; rm -rf $W
exit $status
EOF
} > "$work/box.sh"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/box-run.ps1")" -ScriptFile "$(cygpath -w "$work/box.sh")"
