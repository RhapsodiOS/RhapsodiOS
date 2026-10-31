#!/bin/sh
# Regression test for sh -e (errexit).  Usage: errexit.sh [shell]
# Each "ok" case must run to the end and print "ok"; each "exit" case
# must stop with a non-zero status before printing "bad".

SH=${1-/bin/sh}
fail=0

ok() {
	out=`"$SH" -c "$1" 2>&1`
	if [ "$out" = ok ]; then
		echo "PASS ok:   $1"
	else
		echo "FAIL ok:   $1  (got: $out)"
		fail=1
	fi
}

stops() {
	out=`"$SH" -c "$1" 2>&1`
	status=$?
	if [ $status != 0 -a "$out" = "" ]; then
		echo "PASS exit: $1"
	else
		echo "FAIL exit: $1  (status $status, got: $out)"
		fail=1
	fi
}

ok 'set -e; false && true; echo ok'
ok 'set -e; true; false && true; echo ok'
ok 'set -e; if true; then false && true; fi; echo ok'
ok 'set -e; { false && true; }; echo ok'
ok 'set -e; for i in 1; do false && true; done; echo ok'
ok 'set -e; i=0; while test $i = 0; do i=1; false && true; done; echo ok'
ok 'set -e; case x in x) false && true;; esac; echo ok'
ok 'set -e; f() { false && true; }; if f; then :; fi; echo ok'
ok 'set -e; false || true; echo ok'
ok 'set -e; if false; true; then echo ok; fi'
ok 'set -e; while false; do :; done; echo ok'
ok 'set -e; ! true; echo ok'

stops 'set -e; false; echo bad'
stops 'set -e; true && false; echo bad'
stops 'set -e; false || false; echo bad'
stops 'set -e; true | false; echo bad'
stops 'set -e; (false); echo bad'
stops 'set -e; { false; echo bad; }'
stops 'set -e; if true; then false; fi; echo bad'
stops 'set -e; for i in 1; do false; done; echo bad'
stops 'set -e; case x in x) false;; esac; echo bad'
stops 'set -e; f() { false; echo bad; }; f'

exit $fail
