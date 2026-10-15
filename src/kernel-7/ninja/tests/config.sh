#!/bin/sh
set -eu
suite=$1
work=$2
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
here=`CDPATH= cd "\`dirname "$0"\`/../.." && pwd`
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
mkdir -p "$work"
copy_tree()
{
    mkdir "$work/tree"
    (cd "$here" && tar cf - bsd conf driverkit ipc kern kernserv mach mach_debug machdep mon src uxkern vm ninja build.ninja build-debug.ninja) |
        (cd "$work/tree" && tar xf -)
}
case "$suite" in
syntax)
    cd "$here"
    for config in RELEASE DEBUG; do
        manifest=build.ninja
        test "$config" != DEBUG || manifest=build-debug.ninja
        "${SAMU-samu}" -f "$manifest" configured > "$work/$config-config.log" 2>&1
        "${SAMU-samu}" -f "$manifest" -t commands "BUILD.ninja/${config}_I386/mach_kernel" > "$work/$config-commands"
        cp "BUILD.ninja/${config}_I386/Makefile" "$work/$config-reference"
        echo 'IDENT += -DUNEXPECTED' >> "$work/$config-reference"
        if awk -v config="${config}_I386" -v outdir="BUILD.ninja/${config}_I386" -v srcdir="`pwd`" -f ninja/check-config.awk "$work/$config-reference" "$work/$config-commands" > "$work/$config.log" 2>&1; then
            echo "FAIL: accepted unsupported $config assignment" >&2; exit 1
        fi
        grep 'unsupported configuration assignment' "$work/$config.log" >/dev/null
    done
    ;;
diagnostics)
    echo 'OBJS=$(UNKNOWN)' > "$work/reference"
    echo 'ld -static' > "$work/commands"
    (
        echo prefix
        if awk -v config=DEBUG_I386 -f "$here/ninja/check-config.awk" "$work/reference" "$work/commands"; then
            echo 'FAIL: accepted unknown variable'; exit 1
        fi
        echo suffix
    ) > "$work/diagnostic.log" 2>&1
    grep '^prefix$' "$work/diagnostic.log" >/dev/null
    grep 'unsupported configuration variable UNKNOWN' "$work/diagnostic.log" >/dev/null
    grep '^suffix$' "$work/diagnostic.log" >/dev/null
    ;;
selection)
    mkdir "$work/config"
    (cd "$here/conf" && /bin/csh -f tools/doconf/doconf.csh -c -cpu i386 -d "$work/config" RELEASE DEBUG) > "$work/config.log" 2>&1
    grep '^LIBDRIVER=libDriver_kern.o$' "$work/config/RELEASE_I386/Makefile" >/dev/null
    grep '^LIBDRIVER=libDriver_kern_g.o$' "$work/config/DEBUG_I386/Makefile" >/dev/null || {
        echo 'FAIL: DEBUG_I386 does not select libDriver_kern_g.o' >&2
        exit 1
    }
    for config in RELEASE DEBUG; do
        grep '^CCONFIGFLAGS=-g -O3 -fno-omit-frame-pointer$' "$work/config/${config}_I386/Makefile" >/dev/null
    done
    grep -- '-DDEBUG' "$work/config/DEBUG_I386/Makefile" >/dev/null
    grep '#define.*XPR_DEBUG.*1' "$work/config/DEBUG_I386/xpr_debug.h" >/dev/null
    grep '#define.*DIAGNOSTIC.*1' "$work/config/DEBUG_I386/diagnostic.h" >/dev/null
    ;;
prepare)
    test -f "$here/build.ninja" || { echo 'FAIL: build.ninja is missing' >&2; exit 1; }
    copy_tree
    cd "$work/tree"
    rm -rf BUILD.ninja
    "${SAMU-samu}" -f build.ninja configured > "$work/first.log" 2>&1
    test -s BUILD.ninja/RELEASE_I386/meta_features.h
    cp BUILD.ninja/RELEASE_I386/prepared "$work/prepared"
    "${SAMU-samu}" -f build.ninja configured > "$work/second.log" 2>&1
    cmp "$work/prepared" BUILD.ninja/RELEASE_I386/prepared
    rm BUILD.ninja/RELEASE_I386/meta_features.h
    "${SAMU-samu}" -f build.ninja configured > "$work/recover.log" 2>&1
    test -s BUILD.ninja/RELEASE_I386/meta_features.h
    touch conf/MASTER.local
    if "${SAMU-samu}" -f build.ninja configured > "$work/override.log" 2>&1; then
        echo 'FAIL: accepted MASTER.local' >&2; exit 1
    fi
    rm conf/MASTER.local
    "${SAMU-samu}" -f build-debug.ninja configured > "$work/debug.log" 2>&1
    test -s BUILD.ninja/DEBUG_I386/meta_features.h
    test -f BUILD.ninja/DEBUG_I386/.ninja_log
    test -f BUILD.ninja/RELEASE_I386/.ninja_log
    rm BUILD.ninja/DEBUG_I386/prepared
    if CONFIG_DIR="$work/missing-tools" "${SAMU-samu}" -f build-debug.ninja configured > "$work/tool-failure.log" 2>&1; then
        echo 'FAIL: accepted missing config tool' >&2; exit 1
    fi
    test ! -f BUILD.ninja/DEBUG_I386/prepared
    "${SAMU-samu}" -f build-debug.ninja configured > "$work/tool-recovery.log" 2>&1
    ;;
compare)
    test -f "$here/ninja/check-config.sh" || { echo 'FAIL: configuration comparator is missing' >&2; exit 1; }
    cd "$here"
    test -f BUILD.ninja/RELEASE_I386/Makefile || "${SAMU-samu}" -f build.ninja configured
    test -f BUILD.ninja/DEBUG_I386/Makefile || "${SAMU-samu}" -f build-debug.ninja configured
    /bin/sh ninja/check-config.sh RELEASE BUILD.ninja/RELEASE_I386 build.ninja > "$work/release.log" 2>&1
    /bin/sh ninja/check-config.sh DEBUG BUILD.ninja/DEBUG_I386 build-debug.ninja > "$work/debug.log" 2>&1
    copy_tree
    cd "$work/tree"
    mkdir "$work/bin" "$work/original"
    for tool in cc ld; do
        cat > "$work/bin/$tool" <<EOF
#!/bin/sh
echo $tool >> "\$CHECK_LOG"
exec /usr/bin/$tool "\$@"
EOF
        chmod +x "$work/bin/$tool"
    done
    export CHECK_LOG="$work/compiler-linker-invocations"
    export PATH="$work/bin:$PATH"
    for file in sources.ninja kernel.ninja i386.ninja debug.ninja; do
        cp "ninja/$file" "$work/original/$file"
    done
    mismatch()
    {
        label=$1
        manifest=$2
        config=$3
        : > "$CHECK_LOG"
        if "${SAMU-samu}" -j 4 -f "$manifest" > "$work/$label.log" 2>&1; then
            echo "FAIL: accepted $label" >&2; exit 1
        fi
        grep "${config}_I386" "$work/$label.log" >/dev/null
        test ! -s "$CHECK_LOG" || { echo "FAIL: compiled before rejecting $label" >&2; exit 1; }
    }
    sleep 1
    sed 's/link_objects = \$libc_objects \$kernel_objects/link_objects = $kernel_objects $libc_objects/' "$work/original/kernel.ninja" > ninja/kernel.ninja
    mismatch link-order build.ninja RELEASE
    cp "$work/original/kernel.ninja" ninja/kernel.ninja
    sed 's/cflags = -g -O3/cflags = -g -O1/' "$work/original/i386.ninja" > ninja/i386.ninja
    mismatch compile-flags build.ninja RELEASE
    cp "$work/original/i386.ninja" ninja/i386.ninja
    sed 's/ -DDEBUG/ -DDEBUG -DUNEXPECTED/' "$work/original/debug.ninja" > ninja/debug.ninja
    mismatch define build-debug.ninja DEBUG
    cp "$work/original/debug.ninja" ninja/debug.ninja
    sed 's/libDriver_kern_g.o/libDriver_kern.o/' "$work/original/debug.ninja" > ninja/debug.ninja
    mismatch debug-library build-debug.ninja DEBUG
    cp "$work/original/debug.ninja" ninja/debug.ninja
    : > BUILD.ninja/RELEASE_I386/PCemulatePROT.o
    awk '/^build \$outdir\/PCemulatePROT.o:/ {skip=1} skip && /^$/ {skip=0; next} !skip {print}' "$work/original/sources.ninja" > ninja/sources.ninja
    mismatch missing-source build.ninja RELEASE
    cp "$work/original/sources.ninja" ninja/sources.ninja
    sed 's/^build objects: phony \$/build objects: phony $outdir\/extra.o $/' "$work/original/sources.ninja" > ninja/sources.ninja
    cat >> ninja/sources.ninja <<'EOF'
build $outdir/extra.o: cc bsd/libkern/locc.c || $outdir/validated
  source = ../../bsd/libkern/locc.c
  object = extra.o
  flags = $cflags
EOF
    mismatch extra-source build.ninja RELEASE
    cp "$work/original/sources.ninja" ninja/sources.ninja
    cp conf/MASTER.i386 "$work/original/MASTER.i386"
    sleep 1
    sed 's/-g -O3/-g -O1/' "$work/original/MASTER.i386" > conf/MASTER.i386
    mismatch master-change build.ninja RELEASE
    cp "$work/original/MASTER.i386" conf/MASTER.i386
    cp conf/files "$work/original/files"
    sleep 1
    sed '/^bsd\/libkern\/locc.c/d' "$work/original/files" > conf/files
    mismatch files-change build.ninja RELEASE
    cp "$work/original/files" conf/files
    touch conf/MASTER.local
    mismatch local-override build.ninja RELEASE
    rm conf/MASTER.local
    "${SAMU-samu}" -f build.ninja configured > "$work/restored.log" 2>&1
    /bin/sh ninja/check-config.sh RELEASE BUILD.ninja/RELEASE_I386 build.ninja >> "$work/restored.log" 2>&1
    ;;
*) echo "unknown suite: $suite" >&2; exit 1 ;;
esac
echo "PASS: $suite"
