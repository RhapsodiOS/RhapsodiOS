#!/bin/sh
set -eu
suite=$1
work=$2
case "$suite" in prepare|compare|build|incremental) ;; *) echo 'expected prepare, compare, build or incremental' >&2; exit 1 ;; esac
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
here=`CDPATH= cd "\`dirname "$0"\`/../.." && /bin/pwd`
test -f "$here/build-ppc.ninja" || { echo 'FAIL: PPC entry manifest is missing' >&2; exit 1; }
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
mkdir -p "$work"
work=`CDPATH= cd "$work" && /bin/pwd`
case "$work/" in "$here/"*) echo 'scratch directory must be outside the source tree' >&2; exit 1 ;; esac
cp -Rp "$here" "$work/tree"
cd "$work/tree"
for config in RELEASE DEBUG; do
    manifest=build-ppc.ninja
    test "$config" != DEBUG || manifest=build-ppc-debug.ninja
    outdir=BUILD.ninja/${config}_PPC
    "${SAMU-samu}" -f "$manifest" configured > "$work/$config-prepare.log" 2>&1
    test -s "$outdir/meta_features.h"
    grep '^CCONFIGFLAGS=-g -O2$' "$outdir/Makefile" >/dev/null
    grep '^LIBDRIVER=libDriver_kern.o$' "$outdir/Makefile" >/dev/null
    grep '^LIBPEXPERT=pexpertpowermac.o$' "$outdir/Makefile" >/dev/null
    if test "$suite" != prepare; then
        /bin/sh ninja/check-config.sh "$config" "$outdir" "$manifest" ppc > "$work/$config-compare.log" 2>&1
    fi
    if test "$suite" = build || test "$suite" = incremental; then
        if test "$suite" = incremental; then
            # Refresh MIG's absolute dependencies for this copied source tree.
            for dir in mach mach_debug kernserv driverkit; do
                rm -f "$outdir/$dir/"*.stamp
            done
        fi
        "${SAMU-samu}" -v -j 2 -f "$manifest" > "$work/$config-build.log" 2>&1
        test -s "$outdir/mach_kernel"
        test -s "$outdir/mach_kernel.sys"
        otool -hv "$outdir/mach_kernel" > "$work/$config-header.log"
        grep PPC "$work/$config-header.log" >/dev/null
        nm "$outdir/mach_kernel.sys" | grep ' start$' >/dev/null
        "${SAMU-samu}" -f "$manifest" > "$work/$config-idle.log" 2>&1
        if grep -E 'CC |ASSYM |VERSION |MIG |LD |STRIP |corrupt build log' "$work/$config-idle.log"; then
            echo "FAIL: repeated PPC work for $config" >&2; exit 1
        fi
    fi
done
if test "$suite" = compare; then
    cp ninja/ppc.ninja "$work/ppc.original"
    sed 's/-mcpu=604/-mcpu=603/' "$work/ppc.original" > ninja/ppc.ninja
    if /bin/sh ninja/check-config.sh RELEASE BUILD.ninja/RELEASE_PPC build-ppc.ninja ppc > "$work/changed-cpu.log" 2>&1; then
        echo 'FAIL: accepted changed PPC compiler settings' >&2; exit 1
    fi
    grep 'compiler/source mismatch' "$work/changed-cpu.log" >/dev/null
    cp "$work/ppc.original" ninja/ppc.ninja
    touch conf/MASTER.ppc.local
    if "${SAMU-samu}" -f build-ppc.ninja configured > "$work/local-override.log" 2>&1; then
        echo 'FAIL: accepted PPC local override' >&2; exit 1
    fi
    grep 'unsupported local configuration' "$work/local-override.log" >/dev/null
fi
if test "$suite" = incremental; then
    both()
    {
        label=$1
        "${SAMU-samu}" -j 2 -f build-ppc.ninja > "$work/$label-release.log" 2>&1
        "${SAMU-samu}" -j 2 -f build-ppc-debug.ninja > "$work/$label-debug.log" 2>&1
    }
    idle()
    {
        both "$1"
        if grep -E 'CC |ASSYM |VERSION |MIG |LD |STRIP |corrupt build log' "$work/$1-release.log" "$work/$1-debug.log"; then
            echo "FAIL: repeated PPC work for $1" >&2; exit 1
        fi
    }
    for input in bsd/libkern/locc.c bsd/dev/random/xoodyak.h mach/std_types.defs; do
        sleep 1
        echo '/* dependency test */' >> "$input"
        case "$input" in
        *.c) label=source; expected='CC .*locc.o' ;;
        *.h) label=header; expected='CC .*xoodyak.o' ;;
        *.defs) label=mig; expected='MIG mach' ;;
        esac
        both "$label"
        for config in release debug; do
            grep "$expected" "$work/$label-$config.log" >/dev/null
            grep 'LD ' "$work/$label-$config.log" >/dev/null
            if grep 'CC .*APM.o' "$work/$label-$config.log"; then
                echo 'FAIL: rebuilt unrelated PPC object' >&2; exit 1
            fi
        done
        idle "$label-idle"
    done
    mkdir "$work/bin"
    cat > "$work/bin/mig" <<'EOF'
#!/bin/sh
exit 17
EOF
    chmod +x "$work/bin/mig"
    for config in RELEASE DEBUG; do
        manifest=build-ppc.ninja
        test "$config" != DEBUG || manifest=build-ppc-debug.ninja
        outdir=BUILD.ninja/${config}_PPC
        rm "$outdir/mach/mach_interface.h"
        if PATH="$work/bin:$PATH" "${SAMU-samu}" -f "$manifest" "$outdir/mach/mach_interface.h" > "$work/$config-mig-failure.log" 2>&1; then
            echo 'FAIL: ignored PPC MIG failure' >&2; exit 1
        fi
        test ! -f "$outdir/mach/mach.stamp"
        "${SAMU-samu}" -j 2 -f "$manifest" > "$work/$config-mig-retry.log" 2>&1
        test -s "$outdir/mach/mach_interface.h"
        grep 'MIG mach' "$work/$config-mig-retry.log" >/dev/null
    done
    idle recovery-idle
    cp BUILD.ninja/DEBUG_PPC/mach_kernel "$work/debug-before-clean"
    "${SAMU-samu}" -f build-ppc.ninja -t clean > "$work/clean.log" 2>&1
    test ! -e BUILD.ninja/RELEASE_PPC/mach_kernel
    cmp "$work/debug-before-clean" BUILD.ninja/DEBUG_PPC/mach_kernel
fi
echo "PASS: PPC $suite"
