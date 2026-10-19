#!/bin/sh
# Exercise the interfaces affected by the C89/Rhapsody port.
set -eu
here=`cd "\`dirname "$0"\`/.." && pwd`
samu=${SAMU-"$here/samurai/samu"}
work=${TMPDIR-/tmp}/samurai-port-$$
(umask 077 && mkdir "$work")
trap 'rm -rf "$work"' 0
trap 'exit 1' 1 2 3 15
cd "$work"

cat > build.ninja <<'EOF'
rule copy
  command = cat input.h > $out; echo built >> runs; echo '$out: input.h' > $out.d
  depfile = $out.d
  deps = gcc
build output: copy
EOF
echo first > input.h
"$samu"
cmp input.h output
test "`wc -l < runs | tr -d ' '`" = 1
test -s .ninja_deps
"$samu"
test "`wc -l < runs | tr -d ' '`" = 1
sleep 1
echo second > input.h
"$samu"
cmp input.h output
test "`wc -l < runs | tr -d ' '`" = 2
"$samu"
test "`wc -l < runs | tr -d ' '`" = 2
echo 'PASS: dependency log, header rebuild and no-op restart'

sed 's/echo built/echo changed/' build.ninja > changed.ninja
"$samu" -f changed.ninja
test "`tail -1 runs`" = changed
echo 'PASS: command hash invalidates old output'

cat > parallel.sh <<'EOF'
touch "$1.started"
i=0
while test ! -f "$2.started"; do
  i=`expr "$i" + 1`
  test "$i" -lt 5 || exit 1
  sleep 1
done
echo "$1 stdout"
echo "$1 stderr" >&2
touch "$1"
EOF
cat > parallel.ninja <<'EOF'
rule pair
  command = sh parallel.sh $out $peer
build left: pair
  peer = right
build right: pair
  peer = left
EOF
NINJA_STATUS='[%e %o %f/%t] ' "$samu" -j 2 -f parallel.ninja > parallel.log 2>&1
test -f left && test -f right
for line in 'left stdout' 'left stderr' 'right stdout' 'right stderr'; do
  grep "$line" parallel.log > /dev/null
done
echo 'PASS: parallel jobs, captured output and elapsed-time status'

cat > fail.ninja <<'EOF'
rule fail
  command = exit 7
build failed: fail
EOF
if "$samu" -f fail.ninja > fail.log 2>&1; then
  echo 'FAIL: failing command returned success' >&2
  exit 1
fi
echo 'PASS: command failure returns nonzero'

cat > signal.ninja <<'EOF'
rule wait
  command = echo started > signal.started; exec sleep 20
build waiting: wait
EOF
"$samu" -f signal.ninja > signal.log 2>&1 &
pid=$!
i=0
while test ! -f signal.started; do
  i=`expr "$i" + 1`
  if test "$i" -ge 10; then
    kill -TERM "$pid" 2>/dev/null || :
    wait "$pid" 2>/dev/null || :
    echo 'FAIL: signal test job did not start' >&2
    exit 1
  fi
  sleep 1
done
kill -TERM "$pid"
if wait "$pid"; then
  echo 'FAIL: interrupted build returned success' >&2
  exit 1
fi
grep 'received signal' signal.log > /dev/null
echo 'PASS: signal pipe interrupts active jobs'
"$samu" -t targets > targets
grep '^output: copy$' targets > /dev/null
echo 'PASS: targets tool'
