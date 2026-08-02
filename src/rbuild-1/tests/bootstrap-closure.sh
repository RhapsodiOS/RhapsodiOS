#!/bin/sh

# BootstrapManifest is executable build policy: keep its package closure and
# the order of early target-header providers testable without building world.

set -u

test_dir=`dirname "$0"`
rbuild_dir=`cd "$test_dir/.." && pwd`
src_dir=`cd "$rbuild_dir/.." && pwd`
manifest="$src_dir/BootstrapManifest"

tmp_base=${TMPDIR-/tmp}/rbuild-bootstrap-closure-$$
tmp=$tmp_base
n=0
while ! (umask 077 && mkdir "$tmp") 2>/dev/null; do
    n=`expr "$n" + 1`
    tmp=$tmp_base-$n
    if test "$n" -ge 100; then
        echo "bootstrap-closure: cannot create temporary directory" >&2
        exit 1
    fi
done
trap 'rm -rf "$tmp"' 0 1 2 3 15
mkdir "$tmp/repo"
mkdir "$tmp/populated"

fail=0
say_fail()
{
    echo "bootstrap-closure: FAIL: $*" >&2
    fail=1
}

if test ! -x "$rbuild_dir/rbuild"; then
    echo "bootstrap-closure: rbuild is not built" >&2
    exit 1
fi

# A missing run exercises rbuild's real project scanner for every manifest
# row.  The repository is intentionally empty so every scanned row is named.
if ! (cd "$src_dir" && "$rbuild_dir/rbuild" missing BootstrapManifest \
        "$tmp/repo") >"$tmp/scan" 2>"$tmp/scan.err"; then
    cat "$tmp/scan.err" >&2
    exit 1
fi

awk -v error_file="$tmp/manifest.err" '
    /^[ \t]*#/ || NF == 0 { next }
    NF != 3 || $1 != "dir" || ($3 != "headers" && $3 != "all") {
        print "bootstrap-closure: invalid three-column row at line " NR > error_file
        bad = 1
    }
    { print $2, $3 }
    END { exit bad }
' "$manifest" >"$tmp/entries" || {
    test ! -f "$tmp/manifest.err" || cat "$tmp/manifest.err" >&2
    fail=1
}

: >"$tmp/provided"
: >"$tmp/artifacts"
entry_number=0
while read source target; do
    test -n "$source" || continue
    entry_number=`expr "$entry_number" + 1`
    control="$src_dir/$source/dpkg/control"
    if test ! -f "$control"; then
        say_fail "manifest source has no dpkg/control: $source"
        continue
    fi
    if ! awk -v source="$source" '
        $1 == "must" && $(NF - 1) == "dir" && $NF == source { found = 1 }
        END { exit !found }
    ' "$tmp/scan"; then
        say_fail "rbuild did not scan manifest source: $source"
    fi
    package=`awk '$1 == "Package:" { print $2; exit }' "$control"`
    if test -z "$package"; then
        say_fail "source has no Package field: $source"
        continue
    fi
    if test "$target" = all; then
        echo "$package" >>"$tmp/provided"
    fi
    if test "$target" = headers; then
        echo "$package-hdrs" >>"$tmp/provided"
    elif test "$source" = Libc-1 && test "$target" = all; then
        # Libc's all recipe is the one intentional exception: it packages
        # the headers consumed by the remaining bootstrap projects.
        echo "$package-hdrs" >>"$tmp/provided"
    fi

    scan_artifact=`sed -n "${entry_number}p" "$tmp/scan" | awk '{ print $3 }'`
    if test -z "$scan_artifact"; then
        continue
    fi
    if test "$target" = headers; then
        case "$scan_artifact" in
        "$package-hdrs"-*)
            suffix=`echo "$scan_artifact" | sed "s/^$package-hdrs//"`
            ;;
        *)
            suffix=`echo "$scan_artifact" | sed "s/^$package//"`
            ;;
        esac
        artifact="$package-hdrs$suffix"
    else
        artifact=$scan_artifact
    fi
    : >"$tmp/populated/$artifact"
    echo "$source $target $artifact" >>"$tmp/artifacts"
done <"$tmp/entries"

# A populated repository must satisfy each row with the artifact for that
# row's target.  In particular, a headers row is not satisfied by (and does
# not require) the base package.
if ! (cd "$src_dir" && "$rbuild_dir/rbuild" missing BootstrapManifest \
        "$tmp/populated") >"$tmp/populated.scan" \
        2>"$tmp/populated.err"; then
    cat "$tmp/populated.err" >&2
    say_fail "cannot scan populated bootstrap repository"
elif test -s "$tmp/populated.scan"; then
    cat "$tmp/populated.scan" >&2
    say_fail "target-correct bootstrap artifacts are reported missing"
fi
header_artifact=`awk '$1 == "architecture-1" && $2 == "headers" {
    print $3; exit
}' "$tmp/artifacts"`
if test -z "$header_artifact"; then
    say_fail "cannot identify architecture header artifact"
else
    rm -f "$tmp/populated/$header_artifact"
    if ! (cd "$src_dir" && "$rbuild_dir/rbuild" missing BootstrapManifest \
            "$tmp/populated") >"$tmp/one-missing.scan" \
            2>"$tmp/one-missing.err"; then
        cat "$tmp/one-missing.err" >&2
        say_fail "cannot rescan bootstrap repository"
    elif test `wc -l <"$tmp/one-missing.scan"` -ne 1 ||
            ! grep 'using dir architecture-1$' "$tmp/one-missing.scan" \
                >/dev/null 2>&1; then
        cat "$tmp/one-missing.scan" >&2
        say_fail "removing one header artifact does not report only its source"
    fi
fi

# Keep a small synthetic mapping independent of the real package names.  A
# legacy two-column row retains the historical all-target meaning.
mkdir -p "$tmp/header-src/dpkg" "$tmp/base-src/dpkg" "$tmp/synthetic-repo"
printf 'Package: sample-header\nVersion: 1\n' >"$tmp/header-src/dpkg/control"
printf 'Package: sample-base\nVersion: 1\n' >"$tmp/base-src/dpkg/control"
printf 'dir %s headers\ndir %s\n' "$tmp/header-src" "$tmp/base-src" \
    >"$tmp/synthetic.manifest"
: >"$tmp/synthetic-repo/sample-header-hdrs-1.apk"
: >"$tmp/synthetic-repo/sample-base-1.apk"
if ! "$rbuild_dir/rbuild" missing "$tmp/synthetic.manifest" \
        "$tmp/synthetic-repo" >"$tmp/synthetic.scan" \
        2>"$tmp/synthetic.err"; then
    cat "$tmp/synthetic.err" >&2
    say_fail "cannot scan synthetic target mapping"
elif test -s "$tmp/synthetic.scan"; then
    cat "$tmp/synthetic.scan" >&2
    say_fail "synthetic target-correct artifacts are reported missing"
fi
rm -f "$tmp/synthetic-repo/sample-header-hdrs-1.apk"
if ! "$rbuild_dir/rbuild" missing "$tmp/synthetic.manifest" \
        "$tmp/synthetic-repo" >"$tmp/synthetic-one.scan" \
        2>"$tmp/synthetic-one.err"; then
    cat "$tmp/synthetic-one.err" >&2
    say_fail "cannot rescan synthetic target mapping"
elif test `wc -l <"$tmp/synthetic-one.scan"` -ne 1 ||
        ! grep "using dir $tmp/header-src\$" "$tmp/synthetic-one.scan" \
            >/dev/null 2>&1; then
    cat "$tmp/synthetic-one.scan" >&2
    say_fail "synthetic header removal reports the wrong source"
fi
printf 'dir %s objects\n' "$tmp/base-src" >"$tmp/unsupported.manifest"
if "$rbuild_dir/rbuild" missing "$tmp/unsupported.manifest" \
        "$tmp/synthetic-repo" >"$tmp/unsupported.scan" \
        2>"$tmp/unsupported.err"; then
    say_fail "unsupported missing target succeeds"
elif ! grep 'unsupported manifest target "objects"' \
        "$tmp/unsupported.err" >/dev/null 2>&1; then
    cat "$tmp/unsupported.err" >&2
    say_fail "unsupported missing target has no clear error"
fi

sed -n '/static const char \*basedeps\[\] = {/,/};/p' \
    "$rbuild_dir/builder.c" |
    sed '1d;$d;s/[",]/ /g' |
    awk '{ for (i = 1; i <= NF; i++) if ($i != "0") print $i }' \
    >"$tmp/required"
for header in architecture-hdrs kernel-hdrs libc-hdrs objc4-hdrs \
        libstreams-hdrs driverkit-hdrs cctools-hdrs; do
    echo "$header" >>"$tmp/required"
done

sort -u "$tmp/provided" >"$tmp/provided.sorted"
sort -u "$tmp/required" >"$tmp/required.sorted"
while read dependency; do
    if ! grep -q "^$dependency$" "$tmp/provided.sorted"; then
        say_fail "BootstrapManifest does not provide $dependency"
    fi
done <"$tmp/required.sorted"

# Header-only framework staging must not compile pb_makefiles' host helpers:
# the target sysroot deliberately has no libc headers at this point.
make_cmd=${MAKE-make}
mkdir -p "$tmp/pb.sym/pb_makefiles.build/derived_src" \
    "$tmp/pb-all.sym/pb_makefiles.build/derived_src"
pb_header_rc=0
(cd "$src_dir/pb_makefiles-1" && "$make_cmd" -n \
        OBJROOT="$tmp/pb.obj" SYMROOT="$tmp/pb.sym" \
        DSTROOT="$tmp/pb.hdr" installhdrs) >"$tmp/pb-header.trace" 2>&1 || \
    pb_header_rc=$?
if grep 'clonehdrs\.c' "$tmp/pb-header.trace" >/dev/null 2>&1; then
    say_fail "pb_makefiles-1 installhdrs compiles target-independent helpers"
elif test "$pb_header_rc" -ne 0; then
    cat "$tmp/pb-header.trace" >&2
    say_fail "cannot trace pb_makefiles-1 installhdrs"
fi
echo 'print-cfiles: ; @echo $(CFILES)' >"$tmp/print-cfiles.make"
if ! (cd "$src_dir/pb_makefiles-1" && "$make_cmd" -s \
        -f Makefile -f "$tmp/print-cfiles.make" DFILES= DDFILES= \
        print-cfiles) >"$tmp/pb-all.trace" 2>&1; then
    cat "$tmp/pb-all.trace" >&2
    say_fail "cannot inspect pb_makefiles-1 normal CFILES"
elif ! grep 'clonehdrs\.c' "$tmp/pb-all.trace" >/dev/null 2>&1; then
    say_fail "pb_makefiles-1 normal install no longer builds its helpers"
fi
pb_multi_rc=0
(cd "$src_dir/pb_makefiles-1" && "$make_cmd" -pn \
        OBJROOT="$tmp/pb-all.obj" SYMROOT="$tmp/pb-all.sym" \
        DSTROOT="$tmp/pb-all.dst" DFILES= DDFILES= \
        install installhdrs) >"$tmp/pb-multi.db" 2>&1 || pb_multi_rc=$?
if test "$pb_multi_rc" -eq 2; then
    cat "$tmp/pb-multi.db" >&2
    say_fail "cannot inspect pb_makefiles-1 multi-goal CFILES"
elif ! grep '^CFILES = .*clonehdrs\.c' "$tmp/pb-multi.db" >/dev/null 2>&1; then
    say_fail "pb_makefiles-1 multi-goal build incorrectly drops its helpers"
fi

# The bootstrap profile names GNU make, so the installhdrs graph and its host
# tool makefiles must parse without NeXT make extensions.
for make_dir in kernel-7 kernel-7/src kernel-7/src/MAKEDEV \
        kernel-7/conf/tools kernel-7/conf/tools/doconf \
        kernel-7/conf/tools/newvers; do
    make_rc=0
    (cd "$src_dir/$make_dir" && "$make_cmd" -q -f Makefile installhdrs) \
        >"$tmp/kernel-make.out" 2>"$tmp/kernel-make.err" || make_rc=$?
    if test "$make_rc" -eq 2; then
        cat "$tmp/kernel-make.err" >&2
        say_fail "GNU make cannot parse $make_dir/Makefile"
    fi
done

# A second makefile replaces recipes but is parsed after the historical one,
# so a bare make still exposes the original file's selected default target.
echo 'all: ; @echo DEFAULT=all' >"$tmp/default-goal.make"
echo 'install: ; @echo DEFAULT=install' >>"$tmp/default-goal.make"
echo 'installhdrs: ; @echo DEFAULT=installhdrs' >>"$tmp/default-goal.make"
mkdir -p "$tmp/default.obj" "$tmp/default.sym" "$tmp/default.dst"
for make_spec in \
        'kernel-7 Makefile' \
        'kernel-7/src Makefile' \
        'kernel-7/src/MAKEDEV Makefile' \
        'kernel-7/conf/tools Makefile' \
        'kernel-7/conf/tools/doconf Makefile' \
        'kernel-7/conf/tools/newvers Makefile' \
        'kernel-7 MakeInc.simple'; do
    set -- $make_spec
    if ! (cd "$src_dir/$1" && "$make_cmd" -s -f "$2" \
            -f "$tmp/default-goal.make" SUBDIR= \
            OBJROOT="$tmp/default.obj" SYMROOT="$tmp/default.sym" \
            DSTROOT="$tmp/default.dst" TYPES=) \
            >"$tmp/default-goal.out" 2>"$tmp/default-goal.err"; then
        cat "$tmp/default-goal.err" >&2
        say_fail "cannot inspect default goal for $1/$2"
    elif ! grep '^DEFAULT=all$' "$tmp/default-goal.out" >/dev/null 2>&1; then
        say_fail "$1/$2 does not default to all"
    fi
done

position()
{
    awk -v source="$1" -v target="$2" \
        '$1 == source && $2 == target { print NR; exit }' "$tmp/entries"
}

assert_before()
{
    before=`position "$1" "$2"`
    after=`position "$3" "$4"`
    if test -z "$before"; then
        say_fail "missing ordered entry: $1 ($2)"
    elif test -z "$after"; then
        say_fail "missing ordered entry: $3 ($4)"
    elif test "$before" -ge "$after"; then
        say_fail "$1 ($2) must precede $3 ($4)"
    fi
}

assert_before bison-1 all cc-1 all
assert_before pb_makefiles-1 headers kernel-7 headers
assert_before project_makefiles-1 headers kernel-7 headers

for provider in architecture-1 kernel-7 Libstreams-1 objc4-1 driverkit-3 \
        cctools-2; do
    assert_before "$provider" headers Libc-1 all
done

if test "$fail" -ne 0; then
    exit 1
fi
echo "bootstrap closure: PASS"
