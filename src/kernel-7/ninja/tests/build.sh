#!/bin/sh
set -eu
suite=$1
work=$2
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
here=`CDPATH= cd "\`dirname "$0"\`/../.." && /bin/pwd`
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
mkdir -p "$work"
work=`CDPATH= cd "$work" && /bin/pwd`
case "$work/" in "$here/"*) echo 'scratch directory must be outside the source tree' >&2; exit 1 ;; esac
cp -Rp "$here" "$work/tree"
here=$work/tree
cd "$here"
case "$suite" in
recovery|recovery-assym|recovery-version-write|recovery-version-retry)
    cd "$work/tree"
    mkdir "$work/bin"
    cat > "$work/bin/awk" <<'EOF'
#!/bin/sh
case "$*" in
*genassym.awk*)
    echo '#broken' > assym.h
    touch -r "$REF_HEADER" assym.h genassym.s
    exit 17
    ;;
esac
exec /usr/bin/awk "$@"
EOF
    chmod +x "$work/bin/awk"
    cp -p conf/tools/newvers/newvers.csh "$work/newvers.original"
    for config in RELEASE DEBUG; do
        manifest=build.ninja
        test "$config" != DEBUG || manifest=build-debug.ninja
        outdir=BUILD.ninja/${config}_I386
        "${SAMU-samu}" -f "$manifest" > "$work/$config-initial.log" 2>&1
        if test "$suite" = recovery || test "$suite" = recovery-assym; then
            cp -p "$outdir/assym.h" "$work/$config-reference.h"
            export REF_HEADER="$work/$config-reference.h"
            rm "$outdir/assym.h"
            if PATH="$work/bin:$PATH" "${SAMU-samu}" -f "$manifest" "$outdir/assym.h" > "$work/$config-assym-failure.log" 2>&1; then
                echo 'FAIL: ignored assembly generator failure' >&2; exit 1
            fi
            "${SAMU-samu}" -f "$manifest" "$outdir/assym.h" > "$work/$config-assym-retry.log" 2>&1
            cmp "$REF_HEADER" "$outdir/assym.h"
            grep 'ASSYM' "$work/$config-assym-retry.log" >/dev/null
        fi
        if test "$suite" = recovery || test "$suite" = recovery-version-write; then
            rm "$outdir/vers.c"
            mkdir "$outdir/vers.c"
            rm "$outdir/vers.suffix"
            if "${SAMU-samu}" -f "$manifest" "$outdir/vers.c" > "$work/$config-version-write.log" 2>&1; then
                echo 'FAIL: ignored version output write failure' >&2; exit 1
            fi
            grep 'cannot create vers.c' "$work/$config-version-write.log" >/dev/null
            rmdir "$outdir/vers.c"
            "${SAMU-samu}" -f "$manifest" "$outdir/vers.c" > "$work/$config-version-write-retry.log" 2>&1
            grep 'char version\[\]' "$outdir/vers.c" >/dev/null
        fi
        if test "$suite" = recovery || test "$suite" = recovery-version-retry; then
            cp -p "$outdir/vers.c" "$work/$config-reference.c"
            cp -p "$outdir/vers.suffix" "$work/$config-reference.suffix"
            export REF_VERSION="$work/$config-reference.c"
            export REF_SUFFIX="$work/$config-reference.suffix"
            cat > conf/tools/newvers/newvers.csh <<'EOF'
echo broken > vers.c
echo broken > vers.suffix
touch -r "$REF_VERSION" vers.c
touch -r "$REF_SUFFIX" vers.suffix
kill -KILL $$
EOF
            touch -r "$work/newvers.original" conf/tools/newvers/newvers.csh
            rm "$outdir/vers.c"
            status=0
            "${SAMU-samu}" -f "$manifest" "$outdir/vers.c" > "$work/$config-version-interrupted.log" 2>&1 || status=$?
            cp -p "$work/newvers.original" conf/tools/newvers/newvers.csh
            test "$status" -ne 0
            "${SAMU-samu}" -f "$manifest" "$outdir/vers.c" > "$work/$config-version-interrupted-retry.log" 2>&1
            grep 'char version\[\]' "$outdir/vers.c" >/dev/null
            grep 'VERSION' "$work/$config-version-interrupted-retry.log" >/dev/null
            cmp "$REF_SUFFIX" "$outdir/vers.suffix"
        fi
        "${SAMU-samu}" -f "$manifest" > "$work/$config-final.log" 2>&1
        "${SAMU-samu}" -f "$manifest" > "$work/$config-idle.log" 2>&1
        if grep -E 'CC |ASSYM |VERSION |MIG |LD |STRIP ' "$work/$config-idle.log"; then
            echo "FAIL: recovery did not settle for $config" >&2; exit 1
        fi
    done
    ;;
strip-idle)
    cd "$here"
    for config in RELEASE DEBUG; do
        manifest=build.ninja
        test "$config" != DEBUG || manifest=build-debug.ninja
        test -s "BUILD.ninja/${config}_I386/mach_kernel.sys"
        touch "BUILD.ninja/${config}_I386/mach_kernel.sys"
        "${SAMU-samu}" -f "$manifest" > "$work/$config-first.log" 2>&1
        "${SAMU-samu}" -f "$manifest" > "$work/$config-second.log" 2>&1
        if grep 'STRIP' "$work/$config-second.log"; then
            echo "FAIL: repeated strip for $config" >&2; exit 1
        fi
    done
    ;;
nfs-frames)
    cat > "$work/nfs-frames.c" <<'EOF'
int initial_sp;
#define __asm__
#define volatile(x) (sp = initial_sp)
int
EOF
    awk '/^backtrace\(int \*where, int size\)/ {copy=1} copy {print} copy && /^}/ {exit}' "$here/bsd/nfs/nfs_socket.c" >> "$work/nfs-frames.c"
    cat >> "$work/nfs-frames.c" <<'EOF'
int main(void)
{
    static int current[2], caller[2];
    int result[2] = {0, 0x76543210};
    int count;
    current[0] = (int)caller;
    caller[0] = 0;
    caller[1] = 0x12345678;
    initial_sp = (int)current;
    count = backtrace(result, sizeof(result));
    return !(count == 1 && result[0] == 0x12345678 && result[1] == 0x76543210);
}
EOF
    /usr/bin/cc -O "$work/nfs-frames.c" -o "$work/nfs-frames"
    (cd "$work" && ./nfs-frames)
    ;;
diagnostic)
    cd "$here"
    "${SAMU-samu}" -f build-debug.ninja -j 2 BUILD.ninja/DEBUG_I386/nfs_socket.o > "$work/diagnostic.log" 2>&1
    test -s BUILD.ninja/DEBUG_I386/nfs_socket.o
    ;;
objects)
    cd "$here"
    "${SAMU-samu}" -f build.ninja -j 4 objects > "$work/release.log" 2>&1
    "${SAMU-samu}" -f build-debug.ninja -j 4 objects > "$work/debug.log" 2>&1
    for config in RELEASE DEBUG; do
        test -s "BUILD.ninja/${config}_I386/start.o"
        test -s "BUILD.ninja/${config}_I386/ioconf.o"
        test -s "BUILD.ninja/${config}_I386/assym.h"
        test -s "BUILD.ninja/${config}_I386/mach/mach_interface.h"
    done
    ;;
link)
    cd "$here"
    "${SAMU-samu}" -f build.ninja -t query BUILD.ninja/RELEASE_I386/mach_kernel > "$work/query.log" 2>&1
    "${SAMU-samu}" -f build.ninja -j 4 > "$work/release.log" 2>&1
    "${SAMU-samu}" -f build-debug.ninja -j 4 > "$work/debug.log" 2>&1
    for config in RELEASE DEBUG; do
        test -s "BUILD.ninja/${config}_I386/mach_kernel.sys"
        test -s "BUILD.ninja/${config}_I386/mach_kernel"
        nm "BUILD.ninja/${config}_I386/mach_kernel.sys" | grep ' _start$' >/dev/null
        otool -hv "BUILD.ninja/${config}_I386/mach_kernel" > "$work/$config.header"
    done
    ;;
acceptance|incremental|concurrent)
    cd "$work/tree"
    rm -rf BUILD.ninja
    mkdir "$work/libraries" "$work/bin" "$work/original"
    for lib in libDriver_kern.o libDriver_kern_g.o libkobjc.o pexperti386.o; do
        cp "/usr/local/lib/$lib" "$work/libraries/$lib"
    done
    cp ninja/kernel.ninja "$work/original/kernel.ninja"
    sed "s|library_dir = .*|library_dir = $work/libraries|" "$work/original/kernel.ninja" > ninja/kernel.ninja
    cp conf/Makefile.template "$work/original/Makefile.template"
    sed "s|^LIBDRIVER_SOURCE=.*|LIBDRIVER_SOURCE=$work/libraries|;s|^LIBOBJC_SOURCE=.*|LIBOBJC_SOURCE=$work/libraries|;s|^LIBPEXPERT_SOURCE=.*|LIBPEXPERT_SOURCE=$work/libraries|" "$work/original/Makefile.template" > conf/Makefile.template
    find_tool()
    {
        tool_name=$1
        saved_ifs=$IFS
        IFS=:
        for directory in $PATH; do
            if test -x "$directory/$tool_name"; then
                IFS=$saved_ifs
                echo "$directory/$tool_name"
                return 0
            fi
        done
        IFS=$saved_ifs
        return 1
    }
    for tool in cc ld strip; do
        real=`find_tool "$tool"` || exit 1
        cat > "$work/bin/$tool" <<EOF
#!/bin/sh
echo '$tool' "\$@" >> "\$CHECK_LOG"
exec '$real' "\$@"
EOF
        chmod +x "$work/bin/$tool"
    done
    real_mig=`find_tool mig` || exit 1
    cat > "$work/bin/mig" <<EOF
#!/bin/sh
echo mig "\$@" >> "\$CHECK_LOG"
if test -n "\${MIG_FAIL_SECOND-}"; then
    case "\$*" in
    */mach/mach.defs)
        echo call >> "\$MIG_FAIL_SECOND"
        if test "\`wc -l < "\$MIG_FAIL_SECOND"\`" -eq 2; then exit 17; fi
        ;;
    esac
fi
exec '$real_mig' "\$@"
EOF
    chmod +x "$work/bin/mig"
    export CHECK_LOG="$work/tool-invocations"
    export PATH="$work/bin:$PATH"
    : > "$CHECK_LOG"
    "${SAMU-samu}" -v -j 2 -f build.ninja > "$work/clean-release.log" 2>&1 &
    release_pid=$!
    "${SAMU-samu}" -v -j 2 -f build-debug.ninja > "$work/clean-debug.log" 2>&1 &
    debug_pid=$!
    release_status=0; wait "$release_pid" || release_status=$?
    debug_status=0; wait "$debug_pid" || debug_status=$?
    if test "$release_status" -ne 0 || test "$debug_status" -ne 0; then
        echo "FAIL: concurrent build statuses $release_status/$debug_status" >&2
        exit 1
    fi
    cp "$CHECK_LOG" "$work/clean-invocations"
    for config in RELEASE DEBUG; do
        test -s "BUILD.ninja/${config}_I386/mach_kernel"
        test -f "BUILD.ninja/${config}_I386/.ninja_log"
        grep "${config}_I386" "BUILD.ninja/${config}_I386/vers.c" >/dev/null
    done
    both()
    {
        label=$1
        : > "$CHECK_LOG"
        "${SAMU-samu}" -j 4 -f build.ninja > "$work/$label-release.log" 2>&1
        "${SAMU-samu}" -j 4 -f build-debug.ninja > "$work/$label-debug.log" 2>&1
        cp "$CHECK_LOG" "$work/$label-invocations"
    }
    idle()
    {
        both "$1"
        test ! -s "$CHECK_LOG" || { echo "FAIL: non-idle build $1" >&2; exit 1; }
    }
    idle initial-idle
    if test "$suite" != concurrent; then
        sleep 1
        echo '/* dependency test */' >> bsd/libkern/locc.c
        both source
        grep 'locc.c' "$CHECK_LOG" >/dev/null
        test "`grep -c '^ld ' "$CHECK_LOG"`" -eq 2
        if grep 'PCemulatePROT.c' "$CHECK_LOG"; then echo 'FAIL: rebuilt unrelated object' >&2; exit 1; fi
        idle source-idle
        sleep 1
        echo '/* dependency test */' >> bsd/dev/random/xoodyak.h
        both header
        grep 'xoodyak.c' "$CHECK_LOG" >/dev/null
        grep 'randomdev.c' "$CHECK_LOG" >/dev/null
        test "`grep -c '^ld ' "$CHECK_LOG"`" -eq 2
        idle header-idle
        sleep 1
        echo '/* dependency test */' >> mach/std_types.defs
        both mig-include
        grep '^mig ' "$CHECK_LOG" >/dev/null
        test "`grep -c '^ld ' "$CHECK_LOG"`" -eq 2
        idle mig-idle
        rm BUILD.ninja/RELEASE_I386/mach/mach_interface.h
        export MIG_FAIL_SECOND="$work/mig-call-count"
        if "${SAMU-samu}" -f build.ninja BUILD.ninja/RELEASE_I386/mach/mach_interface.h > "$work/mig-failure.log" 2>&1; then
            echo 'FAIL: ignored MIG failure' >&2; exit 1
        fi
        test ! -f BUILD.ninja/RELEASE_I386/mach/mach.stamp
        unset MIG_FAIL_SECOND
        both missing-output-recovery
        test -s BUILD.ninja/RELEASE_I386/mach/mach_interface.h
        idle recovery-idle
        cp BUILD.ninja/RELEASE_I386/vers.c "$work/version.before"
        cp "$work/libraries/pexperti386.o" "$work/original/pexperti386.o"
        sleep 1
        cp "$work/original/pexperti386.o" "$work/libraries/pexperti386.o"
        both library
        test "`grep -c '^ld ' "$CHECK_LOG"`" -eq 2
        if cmp "$work/version.before" BUILD.ninja/RELEASE_I386/vers.c >/dev/null 2>&1; then echo 'FAIL: stale library version' >&2; exit 1; fi
        idle library-idle
        cp BUILD.ninja/RELEASE_I386/vers.c "$work/version.before"
        cp ninja/kernel.ninja "$work/original/link-recipe.ninja"
        sleep 1
        sed 's/&& chmod 755 \$out$/\&\& chmod 755 $out \&\& :/' "$work/original/link-recipe.ninja" > ninja/kernel.ninja
        both link-recipe
        test "`grep -c '^ld ' "$CHECK_LOG"`" -eq 2
        if cmp "$work/version.before" BUILD.ninja/RELEASE_I386/vers.c >/dev/null 2>&1; then echo 'FAIL: stale link-recipe version' >&2; exit 1; fi
        idle link-recipe-idle
    fi
    cp BUILD.ninja/RELEASE_I386/mach_kernel "$work/release.before-clean"
    cp BUILD.ninja/DEBUG_I386/mach_kernel "$work/debug.before-clean"
    "${SAMU-samu}" -f build.ninja -t clean > "$work/clean.log" 2>&1
    cmp "$work/debug.before-clean" BUILD.ninja/DEBUG_I386/mach_kernel
    test ! -f BUILD.ninja/RELEASE_I386/mach_kernel
    ;;
*) echo "unknown suite: $suite" >&2; exit 1 ;;
esac
echo "PASS: $suite"
