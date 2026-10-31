#!/bin/sh
# Run on the native CPU; the final package must contain both slices.
set -e
root=$1
work=$2
archs=${3-'i386 ppc'}
test -n "$root" && test -n "$work"
mkdir -p "$work"
BLKID_FILE="$work/blkid.tab"
export BLKID_FILE
for tool in mke2fs e2fsck dumpe2fs debugfs tune2fs; do
    test -x "$root/sbin/$tool" || { echo "FAIL missing tool: $tool"; exit 1; }
    case "$tool" in
        tune2fs) "$root/sbin/$tool" > "$work/$tool.version" 2>&1 || test $? = 1 ;;
        *) "$root/sbin/$tool" -V > "$work/$tool.version" 2>&1 ;;
    esac
    grep '1.35' "$work/$tool.version" > /dev/null
    lipo -info "$root/sbin/$tool" > "$work/$tool.slices"
    sed -e 's/.*architecture: //' -e 's/.*are: //' "$work/$tool.slices" > "$work/$tool.archs"
    for arch in $archs; do
        case "$arch" in
            i386) egrep '(^| )i[3-6]86( |$)' "$work/$tool.archs" > /dev/null ;;
            ppc) egrep '(^| )ppc( |$)' "$work/$tool.archs" > /dev/null ;;
            *) echo "FAIL unsupported architecture: $arch"; exit 1 ;;
        esac
    done
    test -s "$root/usr/share/man/man8/$tool.8"
done
for forbidden in sbin/fsck sbin/resize2fs sbin/badblocks usr/lib usr/include usr/bin bin; do
    test ! -e "$root/$forbidden" || { echo "FAIL forbidden payload: $forbidden"; exit 1; }
done
test -s "$root/usr/share/licenses/ext2fs/COPYING"
test -s "$root/usr/share/licenses/ext2fs/LIBRARY-NOTICES"
# The aggregate also carries the already existing mount Tool.
(cd "$root" && find . ! -type d) > "$work/payload"
while read file; do
    case "$file" in
        ./sbin/mke2fs|./sbin/e2fsck|./sbin/dumpe2fs|./sbin/debugfs|./sbin/tune2fs|./sbin/mount_ext2fs|./sbin/newfs_ext2fs|./sbin/fsck_ext2fs|./usr/filesystems/ext2fs.fs/ext2fs.util) ;;
        ./usr/share/man/man8/mke2fs.8|./usr/share/man/man8/e2fsck.8|./usr/share/man/man8/dumpe2fs.8|./usr/share/man/man8/debugfs.8|./usr/share/man/man8/tune2fs.8|./usr/share/man/man8/mount_ext2fs.8|./usr/share/man/man8/newfs_ext2fs.8|./usr/share/man/man8/fsck_ext2fs.8|./usr/share/man/man8/ext2fs.util.8) ;;
        ./usr/share/licenses/ext2fs/COPYING|./usr/share/licenses/ext2fs/LIBRARY-NOTICES|./usr/share/licenses/ext2fs/NETBSD-NOTICES) ;;
        ./.PKGINFO) ;; # rbuild's package-control record, not an installed file
        *) echo "FAIL unexpected payload: $file"; exit 1 ;;
    esac
done < "$work/payload"
test ! -e "$work/default.img"
dd if=/dev/null of="$work/default.img" bs=1024 seek=8192
"$root/sbin/mke2fs" -F -L Task6 "$work/default.img"
"$root/sbin/dumpe2fs" -h "$work/default.img" > "$work/default.super" 2>&1
grep 'Filesystem volume name: *Task6' "$work/default.super" > /dev/null
grep 'Inode size:[[:space:]]*128' "$work/default.super" > /dev/null
grep 'Filesystem features: *filetype sparse_super$' "$work/default.super" > /dev/null
"$root/sbin/e2fsck" -fn "$work/default.img"
# Explicit size must still permit an initially empty regular-file image.
test ! -e "$work/explicit.img"
: > "$work/explicit.img"
"$root/sbin/mke2fs" -F -L Explicit "$work/explicit.img" 8192
"$root/sbin/e2fsck" -fn "$work/explicit.img"
echo 'PASS native tools, slices, profile, and clean image'
