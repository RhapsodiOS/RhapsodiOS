#!/bin/sh
# buildpackage must extract dependency APKs with the toolchain profile's tar.
#
# Rhapsody's /bin/tar exits nonzero on an archive whose symlinks precede their
# targets (file-cmds ships usr/bin/cpio -> ../../bin/pax), which rbuild then
# reports as "unable to find dependency". The profile names pax-gnutar.sh for
# exactly this reason, so buildpackage has to accept and use a toolchain.
set -e

test_make=${MAKE:-gnumake}
tmp_base=${TMPDIR-/tmp}/rb-bptc-$$
base=$tmp_base
n=0
while ! (umask 077 && mkdir "$base") 2>/dev/null; do
    n=`expr "$n" + 1`
    base=$tmp_base-$n
    if test "$n" -ge 100; then
        echo "buildpackage-toolchain: cannot create temporary directory" >&2
        exit 1
    fi
done
test -d "$base"
trap 'rm -rf "$base"' 0 1 2 15
BUILDIT_DIR=$base/build-roots
export BUILDIT_DIR
mkdir "$BUILDIT_DIR"
"$test_make" rbuild

src=$base/bar
repo=$base/repo
dst=$base/dst
profile=$base/toolchain.conf
tarlog=$base/tar-used.log
tarshim=$base/tar-shim.sh

mkdir -p "$src/apk" "$repo" "$dst" "$base/dep/usr/bin"

# The dependency APK. Its symlink precedes its target in the archive, which is
# the shape that makes Rhapsody's /bin/tar fail.
cat > "$base/dep/.PKGINFO" <<'EOF'
pkgname = dep
pkgver = 1.0
arch = ppc-apple-rhapsody
EOF
: > "$base/dep/usr/bin/dep-real"
(cd "$base/dep" && ln -s dep-real usr/bin/dep-link)
(cd "$base/dep" && /usr/bin/gnutar --posix -cf - . ) | /usr/bin/gzip -9 \
    > "$repo/dep-1.0-ppc.apk"

cat > "$src/apk/pkginfo" <<'EOF'
pkgname = bar
pkgver = 1.0
pkgdesc = toolchain fixture
maintainer = Test <test@example.invalid>
license = unknown
makedepends = dep
arch = ppc-apple-rhapsody
EOF
cat > "$src/Makefile" <<'EOF'
installhdrs:
	mkdir -p $(DSTROOT)/System/Headers
	: > $(DSTROOT)/System/Headers/bar.h

install:
	mkdir -p $(DSTROOT)/usr/bin
	: > $(DSTROOT)/usr/bin/bar
EOF

# A tar the test can observe. It records that it ran, then does the real work.
cat > "$tarshim" <<EOF
#!/bin/sh
echo "tar-shim \$*" >> "$tarlog"
exec /usr/bin/gnutar "\$@"
EOF
chmod +x "$tarshim"

cat > "$profile" <<EOF
profile=test-gcc
build_cc=/usr/bin/cc
target_cc=/usr/bin/cc
target_arch=ppc
target_ar=/usr/bin/ar
target_ranlib=/usr/bin/ranlib
make=/bin/make
make_flags=MAKEFILEDIR=@SYSROOT@/System/Developer/Makefiles/project MAKEFILEPATH=@SYSROOT@/System/Developer/Makefiles
shell=/bin/sh
tar=$tarshim
archive_create=/bin/pax
archive_create_flags=-w -x ustar
gzip=/usr/bin/gzip
rsync=/usr/bin/rsync
path=/usr/bin:/bin:/usr/sbin:/sbin
arch_flags=-arch ppc
cpp_flags=-nostdinc
ld_flags=-Wl,-syslibroot,@SYSROOT@
ln=/bin/ln
EOF

# The fixture chroot holds only the dependency, so the build stops at the
# compiler probe. Everything under test happens before that, so the exit
# status is not the assertion; the three checks below are.
./rbuild buildpackage --toolchain "$profile" --arch ppc --dir \
    "$src" "$repo" "$dst" > "$base/build.out" 2>&1 || :

fail() {
    echo "buildpackage-toolchain: $1" >&2
    cat "$base/build.out" >&2
    exit 1
}

# 1. The dependency resolved. Before buildpackage honored a toolchain this
#    reported "unable to find dependency" for any APK bare tar choked on.
grep 'unable to find dependency' "$base/build.out" > /dev/null &&
    fail "dependency resolution failed"
grep 'installing .*dep-1.0-ppc.apk' "$base/build.out" > /dev/null ||
    fail "dependency was never installed into the build root"

# 2. The profile's tar, not a bare "tar", did the extracting.
test -s "$tarlog" || fail "profile tar was never used"

# 3. The run got past makeroot to the compiler probe, so the checks above
#    describe a real dependency install rather than an early abort.
grep 'toolchain probe' "$base/build.out" > /dev/null ||
    fail "did not reach the toolchain probe"

echo "buildpackage-toolchain: ok"
