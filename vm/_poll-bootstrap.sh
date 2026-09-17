#!/bin/sh
echo "=== status ==="
grep -E 'already have|must build|rbuild: build of|EXIT:' /tmp/bootstrap-rerun.log
echo "=== repo ==="
ls /build/repo | sort
echo "=== procs ==="
ps ax | grep -E 'run-bootstrap|rbuild bootstrap' | grep -v grep
echo "=== logtail ==="
tail -6 /tmp/bootstrap-rerun.log
wc -l /tmp/bootstrap-rerun.log
