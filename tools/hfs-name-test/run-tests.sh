#!/bin/sh
# Build and run mangle_test.c on the build box, against the real ConvertUTF.c
# and the functions extract.py takes from UnicodeWrappers.c.
#
# Usage (from anywhere in the repository): tools/hfs-name-test/run-tests.sh
# Needs Python and, in a worktree, RHAP_VM_DIR (see box-run.ps1).
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
u=$root/src/kernel-7/bsd/hfs/hfscommon/Unicode
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python "$here/extract.py" "$u/UnicodeWrappers.c" > "$work/extracted.c"
{
	echo 'T=/build/hfs-name-test-$$'
	echo 'mkdir -p $T && cd $T || exit 1'
	for f in "$u/ConvertUTF.c" "$u/ConvertUTF.h" "$work/extracted.c" "$here/mangle_test.c"; do
		echo "cat > $(basename "$f") <<'@@HFSNAMETEST@@'"
		cat "$f"
		echo '@@HFSNAMETEST@@'
	done
	echo 'cc -Wall -o mangle_test mangle_test.c ConvertUTF.c && ./mangle_test; status=$?'
	echo 'cd /; rm -rf $T; exit $status'
} > "$work/box.sh"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$here/box-run.ps1")" -ScriptFile "$(cygpath -w "$work/box.sh")"
