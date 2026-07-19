#!/bin/sh
# Simple smoke test for samu (samurai). Builds a tiny project and checks:
#   1. a fresh build runs the command and produces the output
#   2. re-running is a no-op (mtime / .ninja_log work)
#   3. `-t targets` lists the build target
#   4. a failing command makes samu exit non-zero
#
# Build samu first (Windows: nmake -f Makefile.nmake; POSIX: make), then run
# this from anywhere:  sh test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
samu="$here/samu.exe"
[ -e "$samu" ] || samu="$here/samu"
if [ ! -e "$samu" ]; then
	echo "FAIL: samu not built (looked for samu.exe / samu in $here)"
	exit 1
fi

work="$here/_smoketest"
rm -rf "$work"; mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

fail=0
check() {  # check <got> <want> <description>
	if [ "$1" = "$2" ]; then
		echo "  ok   - $3"
	else
		echo "  FAIL - $3 (got [$1] want [$2])"
		fail=1
	fi
}

echo "testing $samu"

# 1. fresh build
cat > "$work/build.ninja" <<'EOF'
rule echo
  command = echo hello-from-samu> $out
build out.txt: echo
EOF
( cd "$work" && "$samu" >/dev/null 2>&1 ); rc=$?
check "$rc" 0 "fresh build exits 0"
got=$(tr -d '\r\n' < "$work/out.txt" 2>/dev/null || true)
check "$got" "hello-from-samu" "output file has expected content"

# 2. no-op re-run
( cd "$work" && "$samu" >/dev/null 2>&1 ); rc=$?
check "$rc" 0 "no-op re-run exits 0"

# 3. -t targets
out=$( cd "$work" && "$samu" -t targets 2>/dev/null | tr -d '\r' )
case "$out" in
	*"out.txt: echo"*) check ok ok "-t targets lists out.txt" ;;
	*)                 check "$out" "out.txt: echo" "-t targets lists out.txt" ;;
esac

# 4. failing command -> non-zero exit
rm -f "$work/.ninja_log" "$work/.ninja_deps"
cat > "$work/build.ninja" <<'EOF'
rule fail
  command = exit 7
build bad: fail
EOF
( cd "$work" && "$samu" >/dev/null 2>&1 ); rc=$?
[ "$rc" -ne 0 ] && r=nonzero || r=zero
check "$r" nonzero "failing command exits non-zero"

echo
if [ "$fail" -eq 0 ]; then
	echo "PASS: all checks passed"
else
	echo "FAIL: one or more checks failed"
fi
exit "$fail"
