#!/bin/sh
# Stronger detach for stage-1 (Rhapsody nohup can be flaky over SSH).
export PATH=/build/bin:/usr/bin:/bin:/usr/local/bin:/sbin:/usr/sbin
SRC="${1:-/build/src}"
REPO="${2:-/build/repo}"
BUILT="${3:-/build/repo}"
TIME_ARG="$4"

if [ -n "$TIME_ARG" ]; then date "$TIME_ARG" || true; fi

# Free leftover chroot roots from aborted runs
rm -rf /private/tmp/roots/*.roots 2>/dev/null || true
mkdir -p /private/tmp/roots "$REPO" "$BUILT"

chmod a+x /tmp/_run-stage1-kernel.sh /tmp/_install-ln.sh /tmp/_fix-crt1.sh 2>/dev/null

# Double-detach: nohup + background + close stdio
rm -f /tmp/stage1-kernel.pid /tmp/stage1-nohup.out /tmp/stage1-kernel.log
# Rhapsody sh wants signal numbers (1=HUP), not names.
/bin/sh -c "trap '' 1; nohup /tmp/_run-stage1-kernel.sh '$SRC' '$REPO' '$BUILT' </dev/null >/tmp/stage1-nohup.out 2>&1 & echo \$! > /tmp/stage1-kernel.pid"
sleep 2
echo "started pid=$(cat /tmp/stage1-kernel.pid)"
ps -p "$(cat /tmp/stage1-kernel.pid)" 2>&1 | head -3
sleep 5
wc -l /tmp/stage1-kernel.log 2>/dev/null
tr -d '\000' < /tmp/stage1-kernel.log 2>/dev/null | tail -15
