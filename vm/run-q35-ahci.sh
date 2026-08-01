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
    echo "usage: $0 [--dry-run] SOURCE_ROOT_IMAGE vm/work/IMAGE [ISO] [SECOND_DISK]" >&2
    exit 2
}

canonical()
{
    "$python" -c 'import os,sys; print(os.path.realpath(sys.argv[1]).replace(os.sep, "/"))' "$1"
}

[ "${1:-}" = "--dry-run" ] && { dry_run=1; shift; }
[ $# -ge 2 ] && [ $# -le 4 ] || usage

command -v "$python" >/dev/null 2>&1 || die "python3 is required for path and QMP handling"
source_image=`canonical "$1"`
work_image=`canonical "$2"`
iso_image=
second_disk=
[ $# -ge 3 ] && iso_image=`canonical "$3"`
[ $# -ge 4 ] && second_disk=`canonical "$4"`
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
    echo "$qemu $*"
    [ "${AHCI_DEBUG:-0}" = 1 ] && echo "AHCI QEMU trace: $trace_log"
    exit 0
fi

command -v "$qemu" >/dev/null 2>&1 || die "QEMU not found: $qemu"
work_parent=${work_image%/*}
[ "$work_parent" != "$work_image" ] || work_parent=.
mkdir -p "$work_parent" "$logs_dir"
copy_tmp=$work_image.copying.$$
trap 'rm -f "$copy_tmp"' 0 1 2 3 15
cp -p "$source_image" "$copy_tmp" || die "could not copy source root image"
mv -f "$copy_tmp" "$work_image" || die "could not install working image"

# The Rhapsody boot loader accepts kernel/root arguments at its VGA boot
# prompt. Send the same keystrokes used by vm/qemu-shot.py over QMP.
"$python" - "$qmp_port" "$keys_delay" "$boot_keys" <<'PY' &
import json
import socket
import sys
import time

port = int(sys.argv[1])
delay = float(sys.argv[2])
text = sys.argv[3]
mapping = {c: [c] for c in "abcdefghijklmnopqrstuvwxyz0123456789"}
mapping.update({"-": ["minus"], "_": ["shift", "minus"],
                "=": ["equal"], " ": ["spc"], "\n": ["ret"]})
deadline = time.time() + 30
sock = None
while time.time() < deadline:
    try:
        sock = socket.create_connection(("127.0.0.1", port), 1)
        break
    except OSError:
        time.sleep(.1)
if sock is None:
    raise SystemExit("could not connect to QEMU QMP")
stream = sock.makefile("rwb", buffering=0)
stream.readline()
stream.write(b'{"execute":"qmp_capabilities"}\n')
stream.readline()
time.sleep(delay)
for char in text:
    for code in mapping[char]:
        command = {"execute": "send-key", "arguments": {"keys": [
            {"type": "qcode", "data": code}]}}
        stream.write(json.dumps(command).encode("ascii") + b"\n")
        stream.readline()
        time.sleep(.05)
sock.close()
PY
keys_pid=$!

set +e
"$qemu" "$@"
status=$?
set -e
kill "$keys_pid" >/dev/null 2>&1 || true
wait "$keys_pid" >/dev/null 2>&1 || true
exit "$status"
