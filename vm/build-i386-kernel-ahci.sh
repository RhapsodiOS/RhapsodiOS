#!/bin/sh
# Build and stage the i386 kernel plus the EIDE and AHCI boot drivers.

set -eu

script_path=$0
case "$script_path" in
    */*) script_dir_part=${script_path%/*} ;;
    *) script_dir_part=. ;;
esac
script_dir=`CDPATH= cd "$script_dir_part" && pwd -P`
repo_root=`CDPATH= cd "$script_dir/.." && pwd -P`
source_root=${AHCI_SOURCE_ROOT:-$repo_root}
install_dir=${AHCI_INSTALL_DIR:-$repo_root/vm/install}
make_cmd=${AHCI_MAKE:-gnumake}
kernel_dir=$source_root/src/kernel-7
eide_dir=$source_root/src/drivers-i386/ide/drvEIDE
ahci_dir=$source_root/src/drivers-i386/ide/drvAHCI
tests_dir=$ahci_dir/tests
tmp_root=${TMPDIR:-/tmp}/rhapsodios-ahci-build-$$
marker=$tmp_root/build-started
export AHCI_BUILD_STARTED_MARKER=$marker

die()
{
    echo "build-i386-kernel-ahci: $*" >&2
    exit 1
}

cleanup()
{
    case "$tmp_root" in
        */rhapsodios-ahci-build-$$) rm -rf "$tmp_root" ;;
    esac
}

require_dir()
{
    [ -d "$1" ] || die "missing source directory: $1"
}

require_fresh()
{
    artifact=$1
    [ -f "$artifact" ] || die "missing build output: $artifact"
    [ "$artifact" -nt "$marker" ] ||
        die "stale build output (not newer than build start): $artifact"
}

command -v "$make_cmd" >/dev/null 2>&1 ||
    die "required target build tool not found: $make_cmd"
case "$install_dir" in
    */install) ;;
    *) die "staging directory must end in /install: $install_dir" ;;
esac
require_dir "$kernel_dir"
require_dir "$eide_dir"
require_dir "$ahci_dir"
require_dir "$tests_dir"

trap cleanup 0 1 2 3 15
mkdir -p "$tmp_root"
: > "$marker"
# The period filesystems used by the target toolchain have one-second mtimes.
sleep 1

echo "== portable AHCI tests =="
(cd "$tests_dir" && "$make_cmd" clean all check) ||
    die "portable AHCI tests failed"

kernel=$kernel_dir/BUILD/RELEASE_I386/mach_kernel
rm -rf "$kernel_dir/BUILD/RELEASE_I386" \
    "$kernel_dir/BUILD/config.RELEASE_I386" \
    "$kernel_dir/BUILD/config.RELEASE_I386.old"
rm -f "$kernel_dir/conf/RELEASE_I386" "$kernel_dir/conf/RELEASE_I386.old"
echo "== i386 kernel =="
(cd "$kernel_dir/conf" &&
    "$make_cmd" I386 OBJROOT=../BUILD SYMROOT=../BUILD) ||
    die "i386 kernel build failed"
require_fresh "$kernel"

build_driver()
{
    driver_dir=$1
    name=$2
    dst=$tmp_root/$name-dst
    rm -rf "$dst"
    mkdir -p "$dst"
    echo "== i386 $name driver =="
    (cd "$driver_dir" && "$make_cmd" clean &&
        "$make_cmd" RC_ARCHS=i386 INCLUDED_ARCHS=i386 DSTROOT="$dst" install) ||
        die "$name driver build failed"
    require_fresh "$dst/private/Drivers/i386/$name.config/${name}_reloc"
    require_fresh "$dst/private/Drivers/i386/$name.config/Default.table"
}

build_driver "$eide_dir" EIDE
build_driver "$ahci_dir" AHCI

stage_tmp=$tmp_root/install
mkdir -p "$stage_tmp/EIDE.config" "$stage_tmp/AHCI.config"
cp -p "$kernel" "$stage_tmp/mach_kernel"
cp -p "$tmp_root/EIDE-dst/private/Drivers/i386/EIDE.config/EIDE_reloc" \
    "$stage_tmp/EIDE.config/EIDE_reloc"
cp -p "$tmp_root/EIDE-dst/private/Drivers/i386/EIDE.config/Default.table" \
    "$stage_tmp/EIDE.config/Default.table"
cp -p "$tmp_root/AHCI-dst/private/Drivers/i386/AHCI.config/AHCI_reloc" \
    "$stage_tmp/AHCI.config/AHCI_reloc"
cp -p "$tmp_root/AHCI-dst/private/Drivers/i386/AHCI.config/Default.table" \
    "$stage_tmp/AHCI.config/Default.table"

rm -rf "$install_dir"
install_parent=${install_dir%/*}
[ "$install_parent" != "$install_dir" ] || install_parent=.
mkdir -p "$install_parent" "$install_dir"
cp -Rp "$stage_tmp/." "$install_dir/"

echo "staged fresh i386 artifacts in $install_dir"
echo "$install_dir/mach_kernel"
echo "$install_dir/EIDE.config/EIDE_reloc"
echo "$install_dir/EIDE.config/Default.table"
echo "$install_dir/AHCI.config/AHCI_reloc"
echo "$install_dir/AHCI.config/Default.table"
