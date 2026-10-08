#!/bin/sh
# Separate configure caches, generators, objects, and staging for each CPU.
set -e
source=$1
objects=$2
destination=$3
archs=$4
test -n "$source" && test -n "$objects" && test -n "$destination"
source=`cd "$source" && pwd`
# Ordered patches also update configure.in; retain the matching generated script.
touch -r "$source/configure.in" "$source/configure"
mkdir -p "$objects" "$destination"
objects=`cd "$objects" && pwd`
destination=`cd "$destination" && pwd`
case "$archs" in 'i386'|'ppc'|'i386 ppc'|'ppc i386') ;; *) echo 'Unsupported RC_ARCHS' >&2; exit 1 ;; esac
build=`/bin/sh "$source/config.guess"`
case "$build" in i386-apple-rhapsody*) build_cpu=i386; build_opts=-m386 ;; powerpc-apple-rhapsody*) build_cpu=ppc; build_opts= ;; *) echo 'Native Rhapsody build machine required' >&2; exit 1 ;; esac
CC=${CC-cc}
BUILD_CC=${BUILD_CC-cc}
export CC BUILD_CC
for arch in $archs; do
    case "$arch" in i386) host=i386-apple-rhapsody; big=no; cpu_opts=-m386 ;; ppc) host=powerpc-apple-rhapsody; big=yes; cpu_opts= ;; esac
    obj="$objects/$arch"
    stage="$objects/stage-$arch"
    # Every invocation reconfigures; no stale generated files survive a patch.
    rm -rf "$obj" "$stage"
    mkdir -p "$obj" "$stage/sbin" "$stage/usr/share/man/man8"
    cd "$obj"
    cat > config.cache <<EOF
ac_cv_prog_cc_cross=yes
ac_cv_sizeof_short=2
ac_cv_sizeof_int=4
ac_cv_sizeof_long=4
ac_cv_sizeof_long_long=8
ac_cv_c_bigendian=$big
ac_cv_header_mntent_h=no
EOF
    CFLAGS="-O2 -traditional-cpp -arch $arch $cpu_opts"
    CPPFLAGS="-D__Rhapsody__ -I$source/../ext2_tools/include ${EXT2_CPPFLAGS-}"
    export CFLAGS CPPFLAGS
    /bin/sh "$source/configure" --build="$build" --host="$host" \
        --cache-file=config.cache --prefix=/usr --sbindir=/sbin \
        --mandir=/usr/share/man --with-ldopts="-arch $arch" \
        --disable-nls --disable-dll-shlibs --disable-elf-shlibs \
        --disable-bsd-shlibs --disable-profile --disable-evms \
        --disable-imager --disable-resizer --disable-fsck --enable-debugfs
    /bin/gnumake -C util subst BUILD_CC="$BUILD_CC" \
        BUILD_CFLAGS="-O2 -traditional-cpp -arch $build_cpu $build_opts" BUILD_LDFLAGS="-arch $build_cpu"
    /bin/gnumake libs BUILD_CC="$BUILD_CC" \
        BUILD_CFLAGS="-O2 -traditional-cpp -arch $build_cpu $build_opts" BUILD_LDFLAGS="-arch $build_cpu"
    /bin/gnumake -C e2fsck e2fsck e2fsck.8
    /bin/gnumake -C debugfs debugfs debugfs.8
    /bin/gnumake -C misc mke2fs tune2fs dumpe2fs mke2fs.8 tune2fs.8 dumpe2fs.8
    for tool in mke2fs tune2fs dumpe2fs; do
        cp "misc/$tool" "$stage/sbin/$tool"
        cp "misc/$tool.8" "$stage/usr/share/man/man8/$tool.8"
    done
    for tool in e2fsck debugfs; do
        cp "$tool/$tool" "$stage/sbin/$tool"
        cp "$tool/$tool.8" "$stage/usr/share/man/man8/$tool.8"
    done
    chmod 755 "$stage"/sbin/*
    chmod 644 "$stage"/usr/share/man/man8/*
    mkdir -p "$stage/usr/share/licenses/ext2fs"
    cp "$source/COPYING" "$stage/usr/share/licenses/ext2fs/COPYING"
    cp "$source/../LIBRARY-NOTICES" "$stage/usr/share/licenses/ext2fs/LIBRARY-NOTICES"
    chmod 644 "$stage"/usr/share/licenses/ext2fs/*
    # Ordinary rbuild removes its chroot after packaging; record live products.
    echo "ext2fs build=$build target=$host objects=$obj stage=$stage"
    egrep '^(CC|CFLAGS|CPPFLAGS|LDFLAGS|LDOPTS) = ' "$obj/MCONFIG"
    egrep '^ac_cv_(sizeof_(short|int|long|long_long)|c_bigendian|prog_cc_cross)=' "$obj/config.cache"
    lipo -info "$obj/util/subst"
    for tool in mke2fs e2fsck dumpe2fs debugfs tune2fs; do
        lipo -info "$stage/sbin/$tool"
    done
done
# Publish only after every requested thin build has succeeded.
mkdir -p "$destination/sbin" "$destination/usr/share/man/man8" \
    "$destination/usr/share/licenses/ext2fs"
for tool in mke2fs e2fsck dumpe2fs debugfs tune2fs; do
    inputs=
    for arch in $archs; do inputs="$inputs $objects/stage-$arch/sbin/$tool"; done
    lipo -create $inputs -output "$destination/sbin/$tool"
    chmod 755 "$destination/sbin/$tool"
    cp "$objects/stage-$arch/usr/share/man/man8/$tool.8" "$destination/usr/share/man/man8/$tool.8"
    chmod 644 "$destination/usr/share/man/man8/$tool.8"
done
cp "$source/COPYING" "$destination/usr/share/licenses/ext2fs/COPYING"
cp "$source/../LIBRARY-NOTICES" "$destination/usr/share/licenses/ext2fs/LIBRARY-NOTICES"
chmod 644 "$destination"/usr/share/licenses/ext2fs/*
