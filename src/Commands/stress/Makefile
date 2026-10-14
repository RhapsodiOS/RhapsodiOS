# RhapsodiOS project Makefile for the system stress suite. rbuild runs
# `make install` with DSTROOT and RC_CFLAGS. Objects are built next to their
# sources because rbuild copies the source tree. GNU make 3.74: pattern rules
# only, no $(call), no target-specific variables.
LIBOBJS = lib/rng.o lib/pattern.o lib/report.o lib/main.o lib/sysinfo.o
CC      = cc
CFLAGS  = -O -Wall $(RC_CFLAGS) -Ilib
TMAIN   = lib/stress-tmain

all: lib/libstress.a

lib/libstress.a: $(LIBOBJS)
	rm -f $@
	ar cr $@ $(LIBOBJS)
	ranlib $@

lib/%.o: lib/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

lib/t_lib: lib/t_lib.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ lib/t_lib.o lib/libstress.a

$(TMAIN): lib/t_main.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ lib/t_main.o lib/libstress.a

# Each line is one shell; a failed test or grep stops make before "ok".
# make runs sh -e, so exit statuses are caught with ||.
check: lib/t_lib $(TMAIN)
	lib/t_lib
	rc=0; $(TMAIN) -n 2 pass >lib/t.out || rc=$$?; test $$rc = 0
	grep '^STRESS tmain pass PASS iters=.* procs=2 .*ops=.*maxlat=.*seed=' lib/t.out
	rc=0; $(TMAIN) fail >lib/t.out || rc=$$?; test $$rc = 1
	grep 'STRESS tmain fail FAIL reason=planned seed=' lib/t.out
	rc=0; $(TMAIN) crash >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL signal=11 worker=' lib/t.out
	rc=0; $(TMAIN) -t 5 hang >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason=timeout secs=5' lib/t.out
	sleep 2; test `ps -ax | grep -c '[s]tress-tmain'` = 0
	rc=0; $(TMAIN) unsup >lib/t.out || rc=$$?; test $$rc = 0
	grep 'STRESS tmain unsup UNSUP reason="msync: ENOSYS"' lib/t.out
	rc=0; $(TMAIN) data >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL what=buf off=0x11 want=' lib/t.out
	$(TMAIN) -s 42 pass >/dev/null 2>lib/t.err; head -1 lib/t.err | grep '^stress-tmain: seed=42$$'
	$(TMAIN) -s 42 pass >/dev/null 2>lib/t.err; head -1 lib/t.err | grep '^stress-tmain: seed=42$$'
	rc=0; $(TMAIN) bogus 2>/dev/null || rc=$$?; test $$rc = 2
	rc=0; $(TMAIN) -t 60 forkbomb >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason="fork: EAGAIN"' lib/t.out
	sleep 2; test `ps -ax | grep -c '[s]tress-tmain'` = 0
	@echo t_main: ok

install: all

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -f lib/*.o lib/libstress.a lib/t_lib $(TMAIN) lib/t.out lib/t.err

.PHONY: all check install installhdrs installsrc clean
