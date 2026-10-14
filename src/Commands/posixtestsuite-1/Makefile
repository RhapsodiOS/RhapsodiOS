# RhapsodiOS project Makefile for the Open POSIX Test Suite 1.5.2. The
# upstream tree in posixtestsuite/ is unmodified; tests are compiled on the
# machine that runs them, by ./run. GNU make 3.74: pattern rules only, no
# $(call), no target-specific variables.
CC     = cc
CFLAGS = -O -Wall $(RC_CFLAGS)
DEST   = $(DSTROOT)/usr/local/posixtestsuite

all: ptimeout

ptimeout: ptimeout.c
	$(CC) $(CFLAGS) -o $@ ptimeout.c

install: all
	mkdir -p $(DEST)
	rm -rf $(DEST)/posixtestsuite
	cp -R posixtestsuite $(DEST)/
	install -c -m 755 run ptimeout $(DEST)/
	install -c -m 644 baseline README $(DEST)/

# Each line is one shell; make runs sh -e, so statuses are caught with ||.
check-ptimeout: ptimeout
	rc=0; ./ptimeout 5 sh -c 'exit 3' || rc=$$?; test $$rc = 3
	rc=0; ./ptimeout 5 sh -c 'kill -SEGV $$$$' || rc=$$?; test $$rc = 139
	rc=0; ./ptimeout 2 sh -c 'trap "" 14; while :; do :; done' || rc=$$?; test $$rc = 124
	./ptimeout 5 sh -c 'sleep 77 & exit 0'; sleep 1; test `ps -ax | grep -c ':[0-9][0-9] sleep 77'` = 0
	rc=0; ./ptimeout 5 /nonexistent 2>/dev/null || rc=$$?; test $$rc = 127
	rc=0; ./ptimeout 0 true 2>/dev/null || rc=$$?; test $$rc = 127
	@echo ptimeout: ok

# The fixtures in t/ cover every result; each must appear exactly once.
# shcore's .sh test runs its build-only binary by path, as upstream's do.
check-run: ptimeout
	rc=0; sh ./run -r t -b /dev/null -t 3 -d /tmp/posixcheck conformance >Report.out || rc=$$?; test $$rc = 0
	grep '^POSIX conformance/interfaces/pass/1-1 PASS$$' Report/results
	grep '^POSIX conformance/interfaces/fail/1-1 FAIL$$' Report/results
	grep '^POSIX conformance/interfaces/unres/1-1 UNRESOLVED$$' Report/results
	grep '^POSIX conformance/interfaces/unsup/1-1 UNSUPPORTED$$' Report/results
	grep '^POSIX conformance/interfaces/untested/1-1 UNTESTED$$' Report/results
	grep '^POSIX conformance/interfaces/exit7/1-1 EXIT=7$$' Report/results
	grep '^POSIX conformance/interfaces/nobuild/1-1 BUILD-FAIL$$' Report/results
	grep '^POSIX conformance/interfaces/nolink/1-1 LINK-FAIL$$' Report/results
	grep '^POSIX conformance/interfaces/buildonly/1-buildonly BUILD-ONLY$$' Report/results
	grep '^POSIX conformance/interfaces/nomain/1-1 BUILD-ONLY$$' Report/results
	grep '^POSIX conformance/interfaces/segv/1-1 SIGNAL=11$$' Report/results
	grep '^POSIX conformance/interfaces/alarmhang/1-1 HUNG$$' Report/results
	grep '^POSIX conformance/interfaces/orphan/1-1 PASS$$' Report/results
	grep '^POSIX conformance/interfaces/killgrp/1-1 SIGNAL=9$$' Report/results
	grep '^POSIX conformance/interfaces/stdin/1-1 PASS$$' Report/results
	grep '^POSIX conformance/interfaces/shpass/1-1 PASS$$' Report/results
	grep '^POSIX conformance/interfaces/shcore/1-1 PASS$$' Report/results
	grep '^POSIX conformance/interfaces/shcore/1-core-buildonly BUILD-ONLY$$' Report/results
	test `grep -c '^POSIX ' Report/results` = 18
	test `ps -ax | grep -c ':[0-9][0-9] sleep 77'` = 0
	test -f Report/log/conformance/interfaces/nobuild/1-1.log
	test ! -d /tmp/posixcheck
	@echo run: ok

# Variants of t/baseline.ok exercise each kind of comparison.
B    = /tmp/posixcheck.base
RUNT = sh ./run -r t -t 3 -d /tmp/posixcheck
check-baseline: ptimeout
	rc=0; $(RUNT) -b t/baseline.ok >Report.out || rc=$$?; test $$rc = 0
	test `grep -c ' -> ' Report/summary` = 0
	test `sed -n '/^== new/,$$p' Report/summary | grep -c '^  '` = 0
	grep '^  1 HUNG$$' Report/summary
	grep '^  1 nobuild$$' Report/summary
	grep '^  1 nolink$$' Report/summary
	sed 's|/fail/1-1 FAIL$$|/fail/1-1 PASS|' t/baseline.ok >$(B)
	rc=0; $(RUNT) -b $(B) >Report.out || rc=$$?; test $$rc = 1
	sed -n '/^== regressions/,/^== improvements/p' Report/summary | grep '^  conformance/interfaces/fail/1-1 PASS -> FAIL$$'
	sed 's|/pass/1-1 PASS$$|/pass/1-1 FAIL|' t/baseline.ok >$(B)
	rc=0; $(RUNT) -b $(B) >Report.out || rc=$$?; test $$rc = 0
	sed -n '/^== improvements/,/^== changes/p' Report/summary | grep '^  conformance/interfaces/pass/1-1 FAIL -> PASS$$'
	(sed 's|/fail/1-1 FAIL$$|/fail/1-1 FLAKY|' t/baseline.ok; echo) >$(B)
	rc=0; $(RUNT) -b $(B) >Report.out || rc=$$?; test $$rc = 0
	test `grep -c '/fail/1-1' Report/summary` = 0
	test `sed -n '/^== new/,$$p' Report/summary | grep -c '^  '` = 0
	grep -v '/pass/1-1 ' t/baseline.ok >$(B)
	rc=0; $(RUNT) -b $(B) >Report.out || rc=$$?; test $$rc = 0
	sed -n '/^== new/,$$p' Report/summary | grep '^  conformance/interfaces/pass/1-1 PASS$$'
	rm -rf $(B) Report; rc=0; $(RUNT) -b $(B) >Report.out 2>/dev/null || rc=$$?; test $$rc = 2
	test ! -d Report
	rc=0; $(RUNT) -u -b $(B) >Report.out || rc=$$?; test $$rc = 0
	cmp $(B) t/baseline.ok
	rm -f $(B)
	@echo baseline: ok

check: check-ptimeout check-run check-baseline

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -rf Report Report.out ptimeout

.PHONY: all check check-ptimeout check-run check-baseline install installhdrs installsrc clean
