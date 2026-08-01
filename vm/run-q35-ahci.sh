#!/bin/sh
# Copy a Rhapsody root image, then boot the copy from ICH9 AHCI port 0.
# The boot prompt receives "mach_kernel rootdev=hd0a -v" over QMP. COM2 is
# recorded in vm/logs/ahci-serial.log. Set AHCI_DEBUG=1 for QEMU's AHCI trace
# in vm/logs/ahci-qemu.log; tracing is intentionally disabled by default.
# SOURCE_ROOT_IMAGE is only copied. Every writable disk must live in vm/work.

set -eu

script_path=$0
case "$script_path" in
    */*) script_dir_part=${script_path%/*} ;;
    *) script_dir_part=. ;;
esac
script_dir=`CDPATH= cd "$script_dir_part" && pwd -P`
repo_root=`CDPATH= cd "$script_dir/.." && pwd -P`
work_root=$repo_root/vm/work
logs_dir=$repo_root/vm/logs
serial_log=$logs_dir/ahci-serial.log
trace_log=$logs_dir/ahci-qemu.log
qemu=${AHCI_QEMU:-qemu-system-i386}
python=${AHCI_PYTHON:-python3}
qmp_port=${AHCI_QMP_PORT:-4445}
keys_delay=${AHCI_BOOT_KEYS_DELAY:-3}
boot_keys='mach_kernel rootdev=hd0a -v
'
dry_run=0

die()
{
    echo "run-q35-ahci: $*" >&2
    exit 1
}

usage()
{
    echo "usage: $0 [--dry-run] [--iso PATH] [--second-disk PATH] SOURCE_ROOT_IMAGE vm/work/IMAGE" >&2
    exit 2
}

canonical()
{
    "$python" -c 'import os,sys; print(os.path.realpath(sys.argv[1]).replace(os.sep, "/"))' "$1"
}

iso_arg=
second_arg=
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            dry_run=1
            shift
            ;;
        --iso)
            [ $# -ge 2 ] || usage
            iso_arg=$2
            shift 2
            ;;
        --second-disk)
            [ $# -ge 2 ] || usage
            second_arg=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ $# -eq 2 ] || usage

command -v "$python" >/dev/null 2>&1 || die "python3 is required for path and QMP handling"
source_image=`canonical "$1"`
work_image=`canonical "$2"`
iso_image=
second_disk=
[ -z "$iso_arg" ] || iso_image=`canonical "$iso_arg"`
[ -z "$second_arg" ] || second_disk=`canonical "$second_arg"`
work_root=`canonical "$work_root"`

[ -f "$source_image" ] || die "source root image not found: $source_image"
[ "$source_image" != "$work_image" ] || die "source and working images must be distinct"
case "$work_image" in
    "$work_root"/*) ;;
    *) die "working image must be under vm/work: $work_image" ;;
esac
[ -z "$iso_image" ] || [ -f "$iso_image" ] || die "ISO not found: $iso_image"
if [ -n "$second_disk" ]; then
    [ -f "$second_disk" ] || die "second disk not found: $second_disk"
    [ "$second_disk" != "$source_image" ] &&
        [ "$second_disk" != "$work_image" ] ||
        die "second disk must be distinct from source and working images"
    case "$second_disk" in
        "$work_root"/*) ;;
        *) die "second disk must be disposable and under vm/work: $second_disk" ;;
    esac
fi

set -- -M q35 -cpu pentium -accel tcg -m 128 -k en-us -nodefaults \
    -vga cirrus -drive "if=none,id=ahci-root,format=raw,file=$work_image" \
    -device ide-hd,drive=ahci-root,bus=ide.0 \
    -serial null -serial "file:$serial_log" \
    -rtc base=1998-05-08T12:00:00 -boot order=c \
    -qmp "tcp:127.0.0.1:$qmp_port,server=on,wait=off"

if [ -n "$second_disk" ]; then
    set -- "$@" -drive "if=none,id=ahci-second,format=raw,file=$second_disk" \
        -device ide-hd,drive=ahci-second,bus=ide.1
fi
if [ -n "$iso_image" ]; then
    set -- "$@" -drive "if=none,id=ahci-cd,media=cdrom,readonly=on,file=$iso_image" \
        -device ide-cd,drive=ahci-cd,bus=ide.2
fi
if [ "${AHCI_DEBUG:-0}" = 1 ]; then
    set -- "$@" -trace "enable=ahci_*,file=$trace_log"
fi

echo "source image (read-only input): $source_image"
echo "disposable working image: $work_image"
echo "serial log: $serial_log"
echo "boot prompt keys: mach_kernel rootdev=hd0a -v"
if [ "$dry_run" -eq 1 ]; then
    echo "copy: $source_image -> $work_image"
    echo "QEMU argv (one argument per line):"
    printf '  %s\n' "$qemu" "$@"
    [ "${AHCI_DEBUG:-0}" = 1 ] && echo "AHCI QEMU trace: $trace_log"
    exit 0
fi

command -v "$qemu" >/dev/null 2>&1 || die "QEMU not found: $qemu"
work_parent=${work_image%/*}
[ "$work_parent" != "$work_image" ] || work_parent=.
mkdir -p "$work_parent" "$logs_dir"
copy_tmp=$work_image.copying.$$
qemu_pid=
keys_pid=
qemu_status_file=$work_image.qemu-status.$$
cleanup()
{
    [ -z "$keys_pid" ] || kill "$keys_pid" >/dev/null 2>&1 || true
    [ -z "$qemu_pid" ] || kill "$qemu_pid" >/dev/null 2>&1 || true
    rm -f "$copy_tmp" "$qemu_status_file" "$qemu_status_file.tmp"
}
trap cleanup 0 1 2 3 15
cp -p "$source_image" "$copy_tmp" || die "could not copy source root image"
mv -f "$copy_tmp" "$work_image" || die "could not install working image"

# The Rhapsody boot loader accepts kernel/root arguments at its VGA boot
# prompt. Send the same keystrokes used by vm/qemu-shot.py over QMP.
# A wrapper records QEMU's real exit before it terminates. This makes an early
# emulator/configuration failure distinguishable from the QMP helper's later
# inability to connect, without relying on kill -0 behavior for zombie children.
(
    qemu_child=
    stop_qemu_child()
    {
        [ -z "$qemu_child" ] || kill "$qemu_child" >/dev/null 2>&1 || true
        [ -z "$qemu_child" ] || wait "$qemu_child" >/dev/null 2>&1 || true
        exit 143
    }
    trap stop_qemu_child 1 2 3 15
    "$qemu" "$@" &
    qemu_child=$!
    set +e
    wait "$qemu_child"
    child_status=$?
    set -e
    qemu_child=
    printf '%s\n' "$child_status" > "$qemu_status_file.tmp"
    mv -f "$qemu_status_file.tmp" "$qemu_status_file"
    exit "$child_status"
) &
qemu_pid=$!
"$python" "$script_dir/ahci_qmp_sendkeys.py" \
    127.0.0.1 "$qmp_port" "$keys_delay" "$boot_keys" &
keys_pid=$!

set +e
wait "$keys_pid"
keys_status=$?
set -e
keys_pid=
if [ "$keys_status" -ne 0 ]; then
    # Give an already-failing QEMU wrapper time to publish its status. The
    # helper normally waits up to 30 seconds, so this path only adds a bounded
    # delay to an error and never to a successful launch.
    if [ ! -f "$qemu_status_file" ]; then
        sleep 1
    fi
    if [ -f "$qemu_status_file" ]; then
        qemu_status=
        read qemu_status < "$qemu_status_file" || qemu_status=
        wait "$qemu_pid" >/dev/null 2>&1 || true
        qemu_pid=
        if [ -n "$qemu_status" ] && [ "$qemu_status" -ne 0 ]; then
            echo "run-q35-ahci: QEMU exited before boot-key injection (exit $qemu_status)" >&2
            exit "$qemu_status"
        fi
        echo "run-q35-ahci: boot-key injection failed (exit $keys_status)" >&2
        exit "$keys_status"
    fi
    echo "run-q35-ahci: boot-key injection failed (exit $keys_status)" >&2
    kill "$qemu_pid" >/dev/null 2>&1 || true
    wait "$qemu_pid" >/dev/null 2>&1 || true
    qemu_pid=
    exit "$keys_status"
fi

set +e
wait "$qemu_pid"
qemu_status=$?
set -e
qemu_pid=
exit "$qemu_status"
