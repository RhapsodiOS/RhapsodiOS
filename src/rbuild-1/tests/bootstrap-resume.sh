#!/bin/sh
set -e

test_make=${MAKE:-gnumake}
tmp_base=${TMPDIR-/tmp}/rb-resume-$$
base=$tmp_base
n=0
while ! (umask 077 && mkdir "$base") 2>/dev/null; do
    n=`expr "$n" + 1`
    base=$tmp_base-$n
    if test "$n" -ge 100; then
        echo "bootstrap-resume: cannot create temporary directory" >&2
        exit 1
    fi
done
test -d "$base"
trap 'rm -rf "$base"' 0 1 2 15
BUILDIT_DIR=$base/build-roots
export BUILDIT_DIR
mkdir "$BUILDIT_DIR"
"$test_make" rbuild
rbuild=`pwd`/rbuild
src=$base/foo
repo=$base/repo
root=$base/root
state=$base/state
profile=$base/toolchain.conf

mkdir -p "$src/dpkg" "$repo" "$base/base/usr/bin" \
    "$base/hdr/System/Headers"
cat > "$src/dpkg/control" <<'EOF'
Package: foo
Maintainer: Test <test@example.invalid>
Version: 1.0
Architecture: universal-apple-rhapsody
Description: resume fixture
Build-Depends:
EOF
cat > "$src/Makefile" <<'EOF'
MAKEFILEDIR = source-selected

installhdrs:
	test "$(MAKEFILEDIR)" = source-selected
	mkdir -p $(DSTROOT)/System/Headers
	: > $(DSTROOT)/System/Headers/foo.h

install:
	test "$(MAKEFILEDIR)" = source-selected
	mkdir -p $(DSTROOT)/usr/bin
	: > $(DSTROOT)/usr/bin/foo
	mkdir -p $(OBJROOT)/fixture
	: > $(OBJROOT)/fixture/dynamic_obj
EOF
cat > "$base/base/.PKGINFO" <<'EOF'
pkgname = foo
pkgver = 1.0
arch = ppc-apple-rhapsody
EOF
cat > "$base/hdr/.PKGINFO" <<'EOF'
pkgname = foo-hdrs
pkgver = 1.0
arch = ppc-apple-rhapsody
EOF
: > "$base/base/usr/bin/foo"
: > "$base/hdr/System/Headers/foo.h"
(cd "$base/base" && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > "$repo/foo-1.0-ppc.apk"
(cd "$base/hdr" && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > "$repo/foo-hdrs-1.0-ppc.apk"
echo "dir $src all" > "$base/Manifest"

write_profile() {
    cpp=$1
    ready=$2
    dest=$3
    if test -z "$ready"; then
        ready='@SYSROOT@/runtime-not-installed'
    fi
    if test -z "$dest"; then
        dest=$profile
    fi
    cat > "$dest" <<EOF
profile=test-gcc
build_cc=/usr/bin/cc
target_cc=/usr/bin/cc
target_arch=ppc
target_ar=/usr/bin/ar
target_ranlib=/usr/bin/ranlib
make=/bin/make
make_flags=MAKEFILEDIR=@SYSROOT@/System/Developer/Makefiles/project MAKEFILEPATH=@SYSROOT@/System/Developer/Makefiles
shell=/bin/sh
tar=/usr/bin/gnutar
archive_create=/bin/pax
archive_create_flags=-w -x ustar
gzip=/usr/bin/gzip
rsync=/usr/bin/rsync
path=/usr/bin:/bin:/usr/sbin:/sbin
arch_flags=-arch ppc
cpp_flags=$cpp
ld_flags=-Wl,-syslibroot,@SYSROOT@
ld_flags_ready=$ready
ln=/bin/ln
EOF
}

write_profile '-nostdinc -I@SYSROOT@/System/Headers'
# Standalone buildpackage retains its legacy target vocabulary. Exercise both
# the logged and unlogged paths and prove these requests reach the builder.
legacy_dst=$base/legacy-dst
dry_buildroot=$BUILDIT_DIR/foo-1.0.roots/foo-1.0.broot
case "$dry_buildroot" in
    "$base"/*) ;;
    *) echo 'bootstrap-resume: build root escaped fixture'; exit 1 ;;
esac
mkdir "$legacy_dst"
rm -rf "$dry_buildroot"
mkdir -p "$dry_buildroot/var/adm"
echo sentinel-package > "$dry_buildroot/var/adm/package-list"
package_list_sum=`cksum "$dry_buildroot/var/adm/package-list"`
./rbuild -n buildpackage --dir --target objs "$src" "$repo" "$legacy_dst" \
    > "$base/legacy-objs.out" 2>&1
grep 'building foo-1.0' "$base/legacy-objs.out" > /dev/null
./rbuild -n buildpackage --state "$base/legacy-state" --dir --target local \
    "$src" "$repo" "$legacy_dst" > "$base/legacy-local.out" 2>&1
grep 'building foo-1.0' "$base/legacy-local.out" > /dev/null
./rbuild -n buildpackage --dir --target binary "$src" "$repo" "$legacy_dst" \
    > "$base/legacy-binary.out" 2>&1
grep 'building foo-1.0' "$base/legacy-binary.out" > /dev/null
test ! -e "$base/legacy-state"
test "$package_list_sum" = "`cksum "$dry_buildroot/var/adm/package-list"`"
test "`cat "$dry_buildroot/var/adm/package-list"`" = sentinel-package
rm -rf "$dry_buildroot"

# Output repositories are write boundaries. Relative and broad-container
# descendants are valid; live protected trees and symlink routes are not.
mkdir "$base/relative-repo"
(cd "$base" && "$rbuild" -n buildpackage --dir --target local \
    "$src" "$repo" relative-repo > relative-output.out 2>&1)
grep 'building foo-1.0' "$base/relative-output.out" > /dev/null
./rbuild -n buildpackage --dir --target local "$src" "$repo" \
    /var/tmp/rbuild-output > "$base/container-output.out" 2>&1
grep 'building foo-1.0' "$base/container-output.out" > /dev/null
test ! -e /usr/rbuild-task4-output
if ./rbuild buildpackage --dir --target local "$src" "$repo" \
    /usr/rbuild-task4-output > "$base/protected-output.out" 2>&1; then
    echo 'bootstrap-resume: protected output repository accepted'
    exit 1
fi
test ! -e /usr/rbuild-task4-output
ln -s /usr "$base/output-parent"
if ./rbuild -n buildpackage --dir --target local "$src" "$repo" \
    "$base/output-parent/rbuild-output" > "$base/symlink-output.out" 2>&1; then
    echo 'bootstrap-resume: symlinked protected output accepted'
    exit 1
fi

# Exact live roots remain protected, but dedicated descendants are valid.
for safe_pair in '/var/tmp/rbuild-root /var/tmp/rbuild-state' \
    '/Users/admin/build/root /Users/admin/build/state' \
    '/Developer/rbuild/root /Developer/rbuild/state'; do
    set -- $safe_pair
    ./rbuild -n bootstrap --sysroot "$1" --toolchain "$profile" \
        --state "$2" "$base/Manifest" "$repo" "$repo" \
        > "$base/safe-descendant.out" 2>&1
done
for protected_root in /var /Users /Developer; do
    if ./rbuild -n bootstrap --sysroot "$protected_root" \
        --toolchain "$profile" --state "$state" "$base/Manifest" \
        "$repo" "$repo" > "$base/protected-root.out" 2>&1; then
        echo "bootstrap-resume: exact protected root accepted: $protected_root"
        exit 1
    fi
done
if ./rbuild -n bootstrap --sysroot /usr/rbuild-root \
    --toolchain "$profile" --state "$state" "$base/Manifest" \
    "$repo" "$repo" > "$base/protected-descendant.out" 2>&1; then
    echo 'bootstrap-resume: protected /usr descendant accepted'
    exit 1
fi
ln -s /usr "$base/protected-parent"
if ./rbuild -n bootstrap --sysroot "$base/protected-parent/rbuild-root" \
    --toolchain "$profile" --state "$state" "$base/Manifest" \
    "$repo" "$repo" > "$base/protected-resolved.out" 2>&1; then
    echo 'bootstrap-resume: symlinked protected descendant accepted'
    exit 1
fi
for unsafe_root in / /tmp/.. /tmp//../.; do
    if ./rbuild bootstrap --sysroot "$unsafe_root" --toolchain "$profile" \
        --state "$state" "$base/Manifest" "$repo" "$repo" \
        > "$base/unsafe.out" 2>&1; then
        echo "bootstrap-resume: unsafe root accepted: $unsafe_root"
        exit 1
    fi
done
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state / "$base/Manifest" "$repo" "$repo" \
    > "$base/unsafe-state.out" 2>&1; then
    echo 'bootstrap-resume: unsafe state accepted'
    exit 1
fi
ln -s /usr "$base/root-link"
if ./rbuild bootstrap --sysroot "$base/root-link" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo" \
    > "$base/unsafe-link.out" 2>&1; then
    echo 'bootstrap-resume: symlink root accepted'
    exit 1
fi
mkdir "$base/real-parent"
ln -s "$base/real-parent" "$base/parent-link"
mkdir "$base/dry-repo"
printf dry-broken > "$base/dry-repo/foo-1.0-ppc.apk"
dry_sum=`cksum "$base/dry-repo/foo-1.0-ppc.apk"`
./rbuild -n bootstrap --sysroot "$base/parent-link/dry-root" \
    --toolchain "$profile" --state "$base/parent-link/dry-state" \
    "$base/Manifest" "$base/dry-repo" "$base/dry-repo" \
    > "$base/dry-run.out" 2>&1
test ! -e "$base/real-parent/dry-root"
test ! -e "$base/real-parent/dry-state"
test "$dry_sum" = "`cksum "$base/dry-repo/foo-1.0-ppc.apk"`"
test ! -e "$base/dry-repo/foo-1.0-ppc.apk.invalid"
grep '/usr/bin/rsync' "$base/dry-run.out" > /dev/null
echo "dir $src ../invalid" > "$base/BadTargetManifest"
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/BadTargetManifest" "$repo" "$repo" \
    > "$base/bad-target.out" 2>&1; then
    echo 'bootstrap-resume: unsafe target accepted'
    exit 1
fi
mkdir -p "$base/badpkg/dpkg"
cat > "$base/badpkg/dpkg/control" <<'EOF'
Package: ../../escape
Version: 1.0
Description: unsafe identity
EOF
if ./rbuild -n buildpackage --dir --target local "$base/badpkg" \
    "$repo" "$repo" > "$base/bad-standalone.out" 2>&1; then
    echo 'bootstrap-resume: unsafe standalone package identity accepted'
    exit 1
fi
if ./rbuild buildpackage --state "$base/bad-state" --dir --target local \
    "$base/badpkg" "$repo" "$repo" > "$base/bad-state.out" 2>&1; then
    echo 'bootstrap-resume: unsafe logged package identity accepted'
    exit 1
fi
test ! -e "$base/bad-state"
cat > "$base/badpkg/dpkg/control" <<'EOF'
Package: safe-name
Version: ../../escape
Description: unsafe standalone version
EOF
if ./rbuild -n buildpackage --dir --target local "$base/badpkg" \
    "$repo" "$repo" > "$base/bad-version.out" 2>&1; then
    echo 'bootstrap-resume: unsafe standalone version accepted'
    exit 1
fi
cat > "$base/badpkg/dpkg/control" <<'EOF'
Package: ../../escape
Version: 1.0
Description: unsafe identity
EOF
echo "dir $base/badpkg all" > "$base/BadPackageManifest"
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/BadPackageManifest" "$repo" "$repo" \
    > "$base/bad-package.out" 2>&1; then
    echo 'bootstrap-resume: unsafe package identity accepted'
    exit 1
fi
test ! -e "$base/escape.apk"
mkdir -p "$state/projects"
echo untouched > "$base/temp-victim"
ln -s "$base/temp-victim" "$state/projects/foo-1.0-ppc-all.done.tmp"
ln -s "$base/temp-victim" "$state/projects/foo-1.0-ppc-all.done"
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo" \
    > "$base/state-symlink.out" 2>&1; then
    echo 'bootstrap-resume: symlink state record accepted'
    exit 1
fi
grep 'unsafe state record' "$base/state-symlink.out" > /dev/null
test "`cat "$base/temp-victim"`" = untouched
rm "$state/projects/foo-1.0-ppc-all.done"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$root/usr/bin/foo"
test -f "$root/System/Headers/foo.h"
test -f "$state/projects/foo-1.0-ppc-all.done"
test "`cat "$base/temp-victim"`" = untouched
test -L "$state/projects/foo-1.0-ppc-all.done.tmp"

# Generic world validation must honor PATH rather than hardcoded host tools.
mkdir "$base/wrappers"
cat > "$base/wrappers/tar" <<EOF
#!/bin/sh
echo tar >> "$base/wrapper.log"
exec /usr/bin/gnutar "\$@"
EOF
cat > "$base/wrappers/gzip" <<EOF
#!/bin/sh
echo gzip >> "$base/wrapper.log"
exec /usr/bin/gzip "\$@"
EOF
chmod +x "$base/wrappers/tar" "$base/wrappers/gzip"
mkdir -p "$base/world-source/dpkg"
sed 's/universal-apple-rhapsody/ppc-apple-rhapsody/' "$src/dpkg/control" > "$base/world-source/dpkg/control"
echo "dir $base/world-source all" > "$base/WorldManifest"
PATH="$base/wrappers:$PATH" ./rbuild buildall "$base/WorldManifest" "$repo" "$repo"
grep '^tar$' "$base/wrapper.log" > /dev/null
grep '^gzip$' "$base/wrapper.log" > /dev/null

# Symlink APKs are invalid artifacts, even when their targets are valid. The
# exact link is quarantined and rebuilt without modifying its target.
cp "$repo/foo-1.0-ppc.apk" "$base/outside.apk"
outside_sum=`cksum "$base/outside.apk"`
rm "$repo/foo-1.0-ppc.apk"
ln -s "$base/outside.apk" "$repo/foo-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test ! -L "$repo/foo-1.0-ppc.apk"
test -f "$repo/foo-1.0-ppc.apk"
test -f "$repo/foo-1.0-ppc.apk.invalid"
mkdir "$base/metadata"
(cd "$base/metadata" && /usr/bin/gzip -dc "$repo/foo-1.0-ppc.apk" | /usr/bin/gnutar -xf -)
grep '^arch = ppc-apple-rhapsody$' "$base/metadata/.PKGINFO" > /dev/null
grep '^Architecture: universal-apple-rhapsody$' "$src/dpkg/control" > /dev/null
grep 'symlink' "$repo/foo-1.0-ppc.apk.invalid" > /dev/null
if grep 'MAKEFILEDIR=' "$state/logs/foo-1.0-ppc-all.log" > /dev/null; then
    echo 'bootstrap-resume: MAKEFILEDIR command-line override escaped'
    exit 1
fi
grep "MAKEFILEPATH=$root/System/Developer/Makefiles" \
    "$state/logs/foo-1.0-ppc-all.log" > /dev/null
test "$outside_sum" = "`cksum "$base/outside.apk"`"
rm "$repo/foo-1.0-ppc.apk.invalid" "$repo/foo-1.0-ppc.apk"
ln -s "$base/missing-outside.apk" "$repo/foo-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test ! -L "$repo/foo-1.0-ppc.apk"
test -f "$repo/foo-1.0-ppc.apk"
test ! -e "$base/missing-outside.apk"
rm "$repo/foo-1.0-ppc.apk.invalid"

cp "$state/projects/foo-1.0-ppc-all.done" "$base/done.saved"
sed 's/^companions=.*/companions=invalid/' "$base/done.saved" > "$state/projects/foo-1.0-ppc-all.done"
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo" \
    > "$base/corrupt.out" 2>&1; then
    echo 'bootstrap-resume: corrupt state unexpectedly succeeded'
    exit 1
fi
grep 'corrupt state record' "$base/corrupt.out" > /dev/null
mv "$base/done.saved" "$state/projects/foo-1.0-ppc-all.done"

base_time=`perl -e 'print((stat($ARGV[0]))[9])' "$repo/foo-1.0-ppc.apk"`
hdr_time=`perl -e 'print((stat($ARGV[0]))[9])' "$repo/foo-hdrs-1.0-ppc.apk"`
base_sum=`cksum "$repo/foo-1.0-ppc.apk"`
hdr_sum=`cksum "$repo/foo-hdrs-1.0-ppc.apk"`
rm -rf "$root"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$root/usr/bin/foo"
test -f "$root/System/Headers/foo.h"
test "$base_time" = "`perl -e 'print((stat($ARGV[0]))[9])' "$repo/foo-1.0-ppc.apk"`"
test "$hdr_time" = "`perl -e 'print((stat($ARGV[0]))[9])' "$repo/foo-hdrs-1.0-ppc.apk"`"
test "$base_sum" = "`cksum "$repo/foo-1.0-ppc.apk"`"
test "$hdr_sum" = "`cksum "$repo/foo-hdrs-1.0-ppc.apk"`"

printf broken > "$repo/foo-hdrs-1.0-ppc.apk"
rm -rf "$root"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$repo/foo-hdrs-1.0-ppc.apk.invalid"
test -f "$root/usr/bin/foo"
test -f "$root/System/Headers/foo.h"
find "$root/usr/local/lib/objs" -name dynamic_obj -type f | grep . > /dev/null
grep 'companions=hdr,obj' "$state/projects/foo-1.0-ppc-all.done" > /dev/null
grep 'System/Headers' "$state/logs/foo-1.0-ppc-all.log" > /dev/null
grep '^command:' "$state/logs/foo-1.0-ppc-all.log" > /dev/null
grep '^status: exited successfully' "$state/logs/foo-1.0-ppc-all.log" > /dev/null

rm "$repo/foo-hdrs-1.0-ppc.apk"
rm -rf "$root"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$root/System/Headers/foo.h"
test -f "$repo/foo-hdrs-1.0-ppc.apk"

rm "$repo/foo-obj-1.0-ppc.apk"
rm -rf "$root"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
find "$root/usr/local/lib/objs" -name dynamic_obj -type f | grep . > /dev/null
test -f "$repo/foo-obj-1.0-ppc.apk"

make_wrong_apk() {
    wrong_name=$1
    wrong_version=$2
    wrong_arch=$3
    wrong_output=$4
    rm -rf "$base/wrong"
    mkdir -p "$base/wrong"
    cat > "$base/wrong/.PKGINFO" <<EOF
pkgname = $wrong_name
pkgver = $wrong_version
arch = $wrong_arch
EOF
    (cd "$base/wrong" && /usr/bin/gnutar --posix -cf - .) | \
        /usr/bin/gzip -9 > "$wrong_output"
}

make_wrong_apk unrelated 1.0 ppc-apple-rhapsody "$repo/foo-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$repo/foo-1.0-ppc.apk.invalid"

rm -f "$repo/foo-hdrs-1.0-ppc.apk.invalid"
make_wrong_apk foo-hdrs 9.9 ppc-apple-rhapsody "$repo/foo-hdrs-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$repo/foo-hdrs-1.0-ppc.apk.invalid"

rm -f "$repo/foo-hdrs-1.0-ppc.apk.invalid"
make_wrong_apk foo 1.0 ppc-apple-rhapsody "$repo/foo-hdrs-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$repo/foo-hdrs-1.0-ppc.apk.invalid"

make_wrong_apk foo-obj 1.0 wrong-architecture "$repo/foo-obj-1.0-ppc.apk"
./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo"
test -f "$repo/foo-obj-1.0-ppc.apk.invalid"

./rbuild buildpackage --state "$state" --dir --target all \
    "$base/world-source" "$repo" "$repo"
test -f "$state/logs/foo-1.0-ppc-all.log"
./rbuild buildall --state "$state" "$base/WorldManifest" "$repo" "$repo"

headers_base=$base/headers-case
headers_repo=$headers_base/repo
headers_root=$headers_base/root
headers_state=$headers_base/state
rm -rf "$headers_base"
mkdir -p "$headers_repo" "$headers_base/base/usr/bin" \
    "$headers_base/hdr/System/Headers" \
    "$headers_base/obj/usr/local/lib/objs"
cp "$base/base/.PKGINFO" "$headers_base/base/.PKGINFO"
cp "$base/hdr/.PKGINFO" "$headers_base/hdr/.PKGINFO"
cat > "$headers_base/obj/.PKGINFO" <<'EOF'
pkgname = foo-obj
pkgver = 1.0
arch = ppc-apple-rhapsody
EOF
: > "$headers_base/base/usr/bin/stale-base"
: > "$headers_base/hdr/System/Headers/foo.h"
: > "$headers_base/obj/usr/local/lib/objs/stale-obj"
(cd "$headers_base/base" && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > "$headers_repo/foo-1.0-ppc.apk"
(cd "$headers_base/hdr" && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > "$headers_repo/foo-hdrs-1.0-ppc.apk"
(cd "$headers_base/obj" && /usr/bin/gnutar --posix -cf - .) | /usr/bin/gzip -9 > "$headers_repo/foo-obj-1.0-ppc.apk"
echo "dir $src headers" > "$headers_base/Manifest"
./rbuild bootstrap --sysroot "$headers_root" --toolchain "$profile" \
    --state "$headers_state" "$headers_base/Manifest" \
    "$headers_repo" "$headers_repo"
test -f "$headers_root/System/Headers/foo.h"
test ! -f "$headers_root/usr/bin/stale-base"
test ! -f "$headers_root/usr/local/lib/objs/stale-obj"

printf broken > "$headers_repo/foo-1.0-ppc.apk"
rm -rf "$headers_root"
./rbuild bootstrap --sysroot "$headers_root" --toolchain "$profile" \
    --state "$headers_state" "$headers_base/Manifest" \
    "$headers_repo" "$headers_repo"
test -f "$headers_root/System/Headers/foo.h"
test ! -f "$headers_repo/foo-1.0-ppc.apk.invalid"
test "`cat "$headers_repo/foo-1.0-ppc.apk"`" = broken

echo "dir $base/world-source headers" > "$headers_base/WorldManifest"
./rbuild buildall "$headers_base/WorldManifest" "$headers_repo" "$headers_repo"
test "`cat "$headers_repo/foo-1.0-ppc.apk"`" = broken
test ! -f "$headers_repo/foo-1.0-ppc.apk.invalid"

world_base=$base/world-case
mkdir -p "$world_base/repo"
cp "$repo/foo-1.0-ppc.apk" "$world_base/repo/foo-1.0-ppc.apk"
cp "$repo/foo-hdrs-1.0-ppc.apk" "$world_base/repo/foo-hdrs-1.0-ppc.apk"
cp "$repo/foo-obj-1.0-ppc.apk" "$world_base/repo/foo-obj-1.0-ppc.apk"
printf broken > "$world_base/repo/foo-1.0-ppc.apk"
echo "dir $base/world-source all" > "$world_base/Manifest"
if ./rbuild buildall "$world_base/Manifest" "$world_base/repo" \
    "$world_base/repo" > "$world_base/build.out" 2>&1; then
    echo 'bootstrap-resume: corrupt world artifact unexpectedly succeeded'
    exit 1
fi
test -f "$world_base/repo/foo-1.0-ppc.apk.invalid"

# Existing completion records must attest the current architecture policy.
# Exercise both target paths with valid cached artifacts: a stale state must
# force a rebuild, then its replacement must permit an unchanged replay.
check_policy_migration() {
    policy_target=$1
    policy_manifest=$2
    policy_repo=$3
    policy_root=$4
    policy_state=$5
    policy_record=$policy_state/projects/foo-1.0-ppc-$policy_target.done
    policy_saved=$base/policy-$policy_target.saved
    cp "$policy_record" "$policy_saved"
    grep '^format=3$' "$policy_saved" > /dev/null
    grep '^architecture_policy=1$' "$policy_saved" > /dev/null
    grep '^effective_architecture=ppc-apple-rhapsody$' "$policy_saved" > /dev/null
    for policy_case in format2 legacy no-policy no-architecture no-markers wrong-policy wrong-architecture stale-hash; do
        case "$policy_case" in
        format2)
            sed '/^architecture_policy=/d; /^effective_architecture=/d; s/^format=3$/format=2/; s/^entry_fingerprint=.*/entry_fingerprint=00000000/' "$policy_saved" > "$policy_record"
            ;;
        legacy)
            sed '/^format=/d; /^companions=/d; /^architecture_policy=/d; /^effective_architecture=/d; s/^entry_fingerprint=.*/entry_fingerprint=00000000/' "$policy_saved" > "$policy_record"
            ;;
        no-policy)
            sed '/^architecture_policy=/d' "$policy_saved" > "$policy_record"
            ;;
        no-architecture)
            sed '/^effective_architecture=/d' "$policy_saved" > "$policy_record"
            ;;
        no-markers)
            sed '/^architecture_policy=/d; /^effective_architecture=/d' "$policy_saved" > "$policy_record"
            ;;
        wrong-policy)
            sed 's/^architecture_policy=.*/architecture_policy=0/' "$policy_saved" > "$policy_record"
            ;;
        wrong-architecture)
            sed 's/^effective_architecture=.*/effective_architecture=i386-apple-rhapsody/' "$policy_saved" > "$policy_record"
            ;;
        stale-hash)
            sed 's/^architecture_policy=.*/architecture_policy=0/; s/^entry_fingerprint=.*/entry_fingerprint=00000000/' "$policy_saved" > "$policy_record"
            ;;
        esac
        ./rbuild bootstrap --sysroot "$policy_root" --toolchain "$profile"             --state "$policy_state" "$policy_manifest" "$policy_repo" "$policy_repo"             > "$base/policy-rebuild.out" 2>&1
        grep 'must build foo-1.0-ppc.apk' "$base/policy-rebuild.out" > /dev/null
        grep '^format=3$' "$policy_record" > /dev/null
        grep '^architecture_policy=1$' "$policy_record" > /dev/null
        grep '^effective_architecture=ppc-apple-rhapsody$' "$policy_record" > /dev/null
        ./rbuild bootstrap --sysroot "$policy_root" --toolchain "$profile"             --state "$policy_state" "$policy_manifest" "$policy_repo" "$policy_repo"             > "$base/policy-replay.out" 2>&1
        if grep 'must build' "$base/policy-replay.out" > /dev/null; then
            echo "bootstrap-resume: unchanged $policy_target state rebuilt"
            exit 1
        fi
    done

    # Named optional markers may appear in either order.
    sed '/^architecture_policy=/d; /^effective_architecture=/d' "$policy_saved" > "$policy_record"
    echo effective_architecture=ppc-apple-rhapsody >> "$policy_record"
    echo architecture_policy=1 >> "$policy_record"
    ./rbuild bootstrap --sysroot "$policy_root" --toolchain "$profile"         --state "$policy_state" "$policy_manifest" "$policy_repo" "$policy_repo"         > "$base/policy-reordered.out" 2>&1
    if grep 'must build' "$base/policy-reordered.out" > /dev/null; then
        echo 'bootstrap-resume: reordered policy markers rebuilt'
        exit 1
    fi

    # Staleness does not excuse corrupt mandatory data or a changed toolchain.
    for policy_error in entry-hash tool-hash bad-source bad-companions duplicate-marker; do
        case "$policy_error" in
        entry-hash)
            sed 's/^entry_fingerprint=.*/entry_fingerprint=00000000/' "$policy_saved" > "$policy_record"
            policy_diagnostic='toolchain state mismatch; use -Fresh'
            ;;
        tool-hash)
            sed 's/^toolchain_fingerprint=.*/toolchain_fingerprint=00000000/; s/^architecture_policy=.*/architecture_policy=0/' "$policy_saved" > "$policy_record"
            policy_diagnostic='toolchain state mismatch; use -Fresh'
            ;;
        bad-source)
            sed 's/^source=.*/source=incorrect/; s/^architecture_policy=.*/architecture_policy=0/' "$policy_saved" > "$policy_record"
            policy_diagnostic='corrupt state record'
            ;;
        bad-companions)
            sed 's/^companions=.*/companions=incorrect/; /^architecture_policy=/d' "$policy_saved" > "$policy_record"
            policy_diagnostic='corrupt state record'
            ;;
        duplicate-marker)
            cat "$policy_saved" > "$policy_record"
            echo architecture_policy=1 >> "$policy_record"
            policy_diagnostic='corrupt state record'
            ;;
        esac
        if ./rbuild bootstrap --sysroot "$policy_root" --toolchain "$profile"             --state "$policy_state" "$policy_manifest" "$policy_repo" "$policy_repo"             > "$base/policy-error.out" 2>&1; then
            echo "bootstrap-resume: invalid $policy_error state succeeded"
            exit 1
        fi
        grep "$policy_diagnostic" "$base/policy-error.out" > /dev/null
    done
    cp "$policy_saved" "$policy_record"
}
check_policy_migration all "$base/Manifest" "$repo" "$root" "$state"
check_policy_migration headers "$headers_base/Manifest" "$headers_repo" "$headers_root" "$headers_state"

univ=$base/universal
univ_root=$univ/root
univ_state=$univ/state
univ_repo=$univ/repo
univ_profile=$univ/toolchain.conf
mkdir -p "$univ/rt/dpkg" "$univ/later/dpkg" "$univ_repo" "$univ_root"
for pkg in rt later; do
    cat > "$univ/$pkg/dpkg/control" <<EOF
Package: $pkg
Maintainer: Test <test@example.invalid>
Version: 1.0
Architecture: universal-apple-rhapsody
Description: universal $pkg fixture
Build-Depends:
EOF
    cp "$src/Makefile" "$univ/$pkg/Makefile"
done
echo "dir $univ/rt all" > "$univ/BootstrapRuntimeManifest"
echo "dir $univ/later all" > "$univ/Manifest"
write_profile '-nostdinc -I@SYSROOT@/System/Headers' '@SYSROOT@/System' "$univ_profile"
: > "$univ_root/System"

if ./rbuild bootstrap-universal --sysroot "$univ_root" --toolchain "$univ_profile" \
    --state "$univ_state" "$univ/Manifest" "$univ_repo" "$univ_repo" \
    > "$univ/missing-indr.out" 2>&1; then
    echo 'bootstrap-resume: missing indr accepted'
    exit 1
fi
grep 'rbuild:' "$univ/missing-indr.out" > /dev/null
grep "$univ_root/usr/local/bin/indr" "$univ/missing-indr.out" > /dev/null

mkdir -p "$univ_root/usr/local/bin"
cat > "$univ_root/usr/local/bin/indr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$univ_root/usr/local/bin/indr"

./rbuild -n bootstrap-universal --sysroot "$univ_root" --toolchain "$univ_profile" \
    --state "$univ_state" "$univ/Manifest" "$univ_repo" "$univ_repo" \
    > "$univ/dry.out" 2>&1
if awk '
    /must build rt-1.0-universal.apk using dir / { if (!r) r = NR }
    /must build later-1.0-universal.apk using dir / { if (!f) f = NR }
    END { exit (r && f && r < f) ? 0 : 1 }
' "$univ/dry.out"; then
    :
else
    echo 'bootstrap-resume: dry-run did not list runtime source before full-manifest source'
    exit 1
fi

rm -f "$univ_root/System"
./rbuild bootstrap --sysroot "$univ_root" --toolchain "$univ_profile" \
    --state "$univ_state" "$univ/Manifest" "$univ_repo" "$univ_repo"
grep '^effective_architecture=ppc-apple-rhapsody$' \
    "$univ_state/projects/later-1.0-ppc-all.done" > /dev/null
test -f "$univ_repo/later-1.0-ppc.apk"
make_wrong_apk rt 1.0 universal-apple-rhapsody "$univ_repo/rt-1.0-universal.apk"

./rbuild bootstrap-universal --sysroot "$univ_root" --toolchain "$univ_profile" \
    --state "$univ_state" "$univ/Manifest" "$univ_repo" "$univ_repo" \
    > "$univ/live.out" 2>&1 || :
grep 'must build later-1.0-universal.apk' "$univ/live.out" > /dev/null

write_profile '-nostdinc -DCHANGED -I@SYSROOT@/System/Headers'
if ./rbuild bootstrap --sysroot "$root" --toolchain "$profile" \
    --state "$state" "$base/Manifest" "$repo" "$repo" \
    > "$base/mismatch.out" 2>&1; then
    echo 'bootstrap-resume: changed profile unexpectedly succeeded'
    exit 1
fi
grep 'toolchain state mismatch; use -Fresh' "$base/mismatch.out"
echo 'bootstrap-resume: PASS'
