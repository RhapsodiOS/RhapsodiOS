#!/bin/sh
set -eu
work=$1
seeds=$2
case "$work" in /*) ;; *) echo 'scratch directory must be absolute' >&2; exit 1 ;; esac
case "$seeds" in /*) ;; *) echo 'kernel seed directory must be absolute' >&2; exit 1 ;; esac
test ! -e "$work" || { echo "scratch directory exists: $work" >&2; exit 1; }
here=`CDPATH= cd "\`dirname "$0"\`/../.." && /bin/pwd`
test -f "$here/build-universal.ninja" || { echo 'FAIL: universal entry manifest is missing' >&2; exit 1; }
mkdir -p "$work"
work=`CDPATH= cd "$work" && /bin/pwd`
case "$work/" in "$here/"*) echo 'scratch directory must be outside the source tree' >&2; exit 1 ;; esac
mkdir -p "$work/tree/ninja"
cp "$here/build-universal.ninja" "$here/build-universal-debug.ninja" "$work/tree/"
cp "$here/ninja/universal.ninja" "$work/tree/ninja/"
cp -Rp "$seeds" "$work/input"
cd "$work/tree"
# Use thin Mach-O inputs with small child graphs to isolate coordination.
cat > fixture.sh <<'EOF'
#!/bin/sh
set -eu
test ! -f "../fail-$1_$2" || exit 17
out=BUILD.ninja/$1_$2
mkdir -p "$out"
for file in mach_kernel mach_kernel.sys; do
    if ! cmp -s "../input/$1_$2/$file" "$out/$file"; then
        cp "../input/$1_$2/$file" "$out/$file"
    fi
done
EOF
for config in RELEASE DEBUG; do
    for arch in I386 PPC; do
        case "$config:$arch" in
        RELEASE:I386) manifest=build.ninja ;;
        DEBUG:I386) manifest=build-debug.ninja ;;
        RELEASE:PPC) manifest=build-ppc.ninja ;;
        DEBUG:PPC) manifest=build-ppc-debug.ninja ;;
        esac
        cat > "$manifest" <<EOF
builddir = BUILD.ninja/${config}_$arch
rule fixture
  command = /bin/sh fixture.sh $config $arch
  description = SLICE $config $arch
  restat = 1
build BUILD.ninja/${config}_$arch/mach_kernel BUILD.ninja/${config}_$arch/mach_kernel.sys: fixture ../input/${config}_$arch/mach_kernel ../input/${config}_$arch/mach_kernel.sys fixture.sh
EOF
    done
done
run()
{
    "${SAMU-samu}" -j 2 -f "$manifest" > "$work/$1.log" 2>&1
}
verify()
{
    for file in mach_kernel mach_kernel.sys; do
        lipo -info "BUILD.ninja/${config}_UNIVERSAL/$file" > "$work/$config-$file-info.log"
        for arch in i386 ppc; do
            suffix=I386
            test "$arch" != ppc || suffix=PPC
            rm -f "$work/extracted"
            lipo -thin "$arch" "BUILD.ninja/${config}_UNIVERSAL/$file" -output "$work/extracted"
            cmp "$work/extracted" "BUILD.ninja/${config}_$suffix/$file"
        done
    done
}
idle()
{
    run "$1"
    if grep -E 'SLICE |LIPO ' "$work/$1.log"; then
        echo 'FAIL: repeated universal work' >&2; exit 1
    fi
}
for config in RELEASE DEBUG; do
    manifest=build-universal.ninja
    test "$config" != DEBUG || manifest=build-universal-debug.ninja
    run "$config-build"
    verify
    idle "$config-idle"
done
cp BUILD.ninja/DEBUG_UNIVERSAL/mach_kernel "$work/debug-before"
config=RELEASE
manifest=build-universal.ninja
sleep 1
echo 'universal dependency test' >> "$work/input/RELEASE_I386/mach_kernel"
run changed-slice
grep 'SLICE RELEASE I386' "$work/changed-slice.log" >/dev/null
grep 'LIPO ' "$work/changed-slice.log" >/dev/null
if grep 'LIPO .*mach_kernel.sys' "$work/changed-slice.log"; then
    echo 'FAIL: repackaged unchanged unstripped slices' >&2; exit 1
fi
if grep 'SLICE RELEASE PPC' "$work/changed-slice.log"; then
    echo 'FAIL: rebuilt unchanged PPC slice' >&2; exit 1
fi
verify
cmp "$work/debug-before" BUILD.ninja/DEBUG_UNIVERSAL/mach_kernel
config=DEBUG
manifest=build-universal-debug.ninja
touch "$work/fail-DEBUG_PPC"
sleep 1
touch "$work/input/DEBUG_PPC/mach_kernel"
if "${SAMU-samu}" -j 2 -f "$manifest" > "$work/child-failure.log" 2>&1; then
    echo 'FAIL: ignored child failure' >&2; exit 1
fi
if grep 'LIPO ' "$work/child-failure.log"; then echo 'FAIL: packaged failed slices' >&2; exit 1; fi
cmp "$work/debug-before" BUILD.ninja/DEBUG_UNIVERSAL/mach_kernel
rm "$work/fail-DEBUG_PPC"
run child-retry
verify
config=RELEASE
manifest=build-universal.ninja
cp BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel "$work/release-before"
cp BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel.sys "$work/release-sys-before"
sleep 1
echo 'invalid Mach-O input' > "$work/input/RELEASE_PPC/mach_kernel"
if "${SAMU-samu}" -j 2 -f "$manifest" > "$work/lipo-failure.log" 2>&1; then
    echo 'FAIL: ignored lipo failure' >&2; exit 1
fi
cmp "$work/release-before" BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel
cmp "$work/release-sys-before" BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel.sys
sleep 1
cp "$seeds/RELEASE_PPC/mach_kernel" "$work/input/RELEASE_PPC/mach_kernel"
run lipo-retry
verify
rm BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel.sys
run missing-universal
verify
rm BUILD.ninja/RELEASE_PPC/mach_kernel
run missing-slice
verify
idle recovery-idle
mkdir -p "$work/bin"
UNIVERSAL_TEST_LIPO=`which lipo`
export UNIVERSAL_TEST_LIPO
# Exercise the input-timestamp preservation used by the in-tree lipo.
cat > "$work/bin/lipo" <<'EOF'
#!/bin/sh
set -e
"$UNIVERSAL_TEST_LIPO" "$@"
if test "$1" = -create; then touch -r "$5" "$3"; fi
EOF
chmod +x "$work/bin/lipo"
PATH="$work/bin:$PATH"
export PATH
rm BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel
run backdated-lipo
idle backdated-idle
"${SAMU-samu}" -f "$manifest" -t clean > "$work/clean.log" 2>&1
test ! -e BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel
test ! -e BUILD.ninja/RELEASE_UNIVERSAL/mach_kernel.sys
for config in RELEASE DEBUG; do
    for arch in I386 PPC; do
        test -s "BUILD.ninja/${config}_$arch/mach_kernel"
        test -s "BUILD.ninja/${config}_$arch/mach_kernel.sys"
    done
done
cmp "$work/debug-before" BUILD.ninja/DEBUG_UNIVERSAL/mach_kernel
echo 'PASS: universal kernel packaging and coordination'
