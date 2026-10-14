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
	install -m 755 run ptimeout $(DEST)/
	install -m 644 baseline README $(DEST)/

# Each line is one shell; make runs sh -e, so statuses are caught with ||.
check-ptimeout: ptimeout
	rc=0; ./ptimeout 5 sh -c 'exit 3' || rc=$$?; test $$rc = 3
	rc=0; ./ptimeout 5 sh -c 'kill -SEGV $$$$' || rc=$$?; test $$rc = 139
	rc=0; ./ptimeout 2 sh -c 'trap "" 14; while :; do :; done' || rc=$$?; test $$rc = 124
	./ptimeout 5 sh -c 'sleep 77 & exit 0'; sleep 1; test `ps -ax | grep -c ':[0-9][0-9] sleep 77'` = 0
	rc=0; ./ptimeout 5 /nonexistent 2>/dev/null || rc=$$?; test $$rc = 127
	rc=0; ./ptimeout 0 true 2>/dev/null || rc=$$?; test $$rc = 127
	@echo ptimeout: ok

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -rf Report ptimeout

.PHONY: all check-ptimeout install installhdrs installsrc clean
