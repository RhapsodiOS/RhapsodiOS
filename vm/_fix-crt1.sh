#!/bin/sh
# Rebuild /lib/crt1.o when Csu's non-dyld crt1 has overwritten the host copy.
# Host /usr/lib/dyld cannot be -r merged ("indirect symbol table entry past
# the end"); a minimal MH_DYLINKER stub with install name /usr/lib/dyld is
# enough for ld to emit LC_LOAD_DYLINKER on new executables.
set -e
SRC="${1:-/build/src/Csu-1}"
WORK=/tmp/crt1-repair-$$
rm -rf "$WORK"
mkdir -p "$WORK/stub" "$WORK/crt"
cd "$WORK/stub"
cat > stub.s <<'EOF'
	.text
	.align 2
	.globl _start
_start:
	blr
EOF
as -arch ppc -o stub.o stub.s
ld -arch ppc -dylinker -dylinker_install_name /usr/lib/dyld -o dyld.stub stub.o

cd "$WORK/crt"
cc -dynamic -DCRT1 -arch ppc -c -o dstart.o "$SRC/start.s"
cc -dynamic -DCRT1 -O -g -Wall -arch ppc -c -o xcrt1.o "$SRC/crt.c"
cc -dynamic -DCRT1 -arch ppc -c -o ddyld.o "$SRC/dyld.s"
cc -dynamic -O -g -Wall -arch ppc -c -o dinit_shlibs.o "$SRC/init_shlibs.c"
cc -O -arch ppc "$WORK/stub/dyld.stub" \
  -r -dynamic -nostdlib -keep_private_externs \
  dstart.o xcrt1.o ddyld.o dinit_shlibs.o \
  -o icrt1.o
/usr/local/bin/indr -arch all "$SRC/indr_list" icrt1.o crt1.o
cp -p /lib/crt1.o /lib/crt1.o.prev 2>/dev/null || true
cp -p crt1.o /lib/crt1.o
chmod 444 /lib/crt1.o

echo 'int main(){return 0;}' > "$WORK/t.c"
cc -arch ppc -o "$WORK/t" "$WORK/t.c"
otool -l "$WORK/t" | grep -q LC_LOAD_DYLINKER
"$WORK/t"
echo "fix-crt1: ok (installed /lib/crt1.o)"
rm -rf "$WORK"
