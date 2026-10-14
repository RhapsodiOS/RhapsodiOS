# RhapsodiOS project Makefile for the system stress suite. rbuild runs
# `make install` with DSTROOT and RC_CFLAGS. Objects are built next to their
# sources because rbuild copies the source tree. GNU make 3.74: pattern rules
# only, no $(call), no target-specific variables.
LIBOBJS = lib/rng.o lib/pattern.o lib/report.o lib/main.o lib/sysinfo.o
CC      = cc
CFLAGS  = -O -Wall $(RC_CFLAGS) -Ilib
TMAIN   = lib/stress-tmain
VMBIN   = vm/stress-vm
MMAPBIN = mmap/stress-mmap
FSBIN   = fs/stress-fs

all: lib/libstress.a $(VMBIN) $(MMAPBIN) $(FSBIN)

lib/libstress.a: $(LIBOBJS)
	rm -f $@
	ar cr $@ $(LIBOBJS)
	ranlib $@

lib/%.o: lib/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

vm/%.o: vm/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(VMBIN): vm/vm.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ vm/vm.o lib/libstress.a

mmap/%.o: mmap/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(MMAPBIN): mmap/mmap.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ mmap/mmap.o lib/libstress.a

fs/%.o: fs/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(FSBIN): fs/fs.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ fs/fs.o lib/libstress.a

lib/t_lib: lib/t_lib.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ lib/t_lib.o lib/libstress.a

$(TMAIN): lib/t_main.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ lib/t_main.o lib/libstress.a

# Each line is one shell; a failed test or grep stops make before "ok".
# make runs sh -e, so exit statuses are caught with ||. The SIGTERM line's
# own shell has "stress-tmain" in its arguments, so its ps grep matches only
# commands that start with lib/stress-tmain.
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
	$(TMAIN) -t 600 hang >/dev/null 2>&1 & sleep 3; kill -TERM $$!; sleep 2; test `ps -ax | grep -c '[0-9] lib/[s]tress-tmain'` = 0
	rc=0; $(TMAIN) unsup >lib/t.out || rc=$$?; test $$rc = 0
	grep 'STRESS tmain unsup UNSUP reason="msync: ENOSYS"' lib/t.out
	rc=0; $(TMAIN) data >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL what=buf off=0x11 want=' lib/t.out
	$(TMAIN) -s 42 pass >/dev/null 2>lib/t.err; head -1 lib/t.err | grep '^stress-tmain: seed=42$$'
	$(TMAIN) -s 42 pass >/dev/null 2>lib/t.err; head -1 lib/t.err | grep '^stress-tmain: seed=42$$'
	rc=0; $(TMAIN) -t 60 forkbomb >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason="fork: EAGAIN"' lib/t.out
	sleep 2; test `ps -ax | grep -c '[s]tress-tmain'` = 0
	rc=0; $(TMAIN) bogus 2>/dev/null || rc=$$?; test $$rc = 2
	@echo t_main: ok

# The first run needs 4 PASS lines and wire PASS or UNSUP; the -x run needs
# each test to FAIL with the corrupted offset.
check-vm: $(VMBIN)
	rc=0; $(VMBIN) -n 2 -m 8m -i 1 >vm/t.out || rc=$$?; test $$rc = 0
	grep '^STRESS vm pressure PASS ' vm/t.out
	grep '^STRESS vm cow PASS ' vm/t.out
	grep '^STRESS vm machvm PASS ' vm/t.out
	grep '^STRESS vm brk PASS ' vm/t.out
	grep '^STRESS vm wire \(PASS\|UNSUP\) ' vm/t.out
	rc=0; $(VMBIN) -x -n 1 -m 4m -i 1 pressure cow machvm brk >vm/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS vm [a-z]* FAIL .*off=0x' vm/t.out` = 4
	@echo vm: ok

# anon and sync are PASS or UNSUP (this kernel refuses MAP_ANON); the -x run needs each test to FAIL with the offset.
check-mmap: $(MMAPBIN)
	rc=0; $(MMAPBIN) -n 3 -i 2 -d /tmp >mmap/t.out || rc=$$?; test $$rc = 0
	grep '^STRESS mmap shared PASS ' mmap/t.out
	grep '^STRESS mmap mixed PASS ' mmap/t.out
	grep '^STRESS mmap private PASS ' mmap/t.out
	grep '^STRESS mmap trunc PASS ' mmap/t.out
	grep '^STRESS mmap anon \(PASS\|UNSUP\) ' mmap/t.out
	grep '^STRESS mmap sync \(PASS\|UNSUP\) ' mmap/t.out
	rc=0; $(MMAPBIN) -x -i 1 -d /tmp shared mixed private >mmap/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS mmap [a-z]* FAIL .*off=0x' mmap/t.out` = 3
	@echo mmap: ok

# fill only runs when STRESS_FILL_DIR names a scratch file system (1 GB takes ~20 min on the dev guest);
# the -x run
# needs rw and append to FAIL with an offset.
check-fs: $(FSBIN)
	rc=0; $(FSBIN) -n 3 -i 20 -d /tmp rw append tree fsync >fs/t.out || rc=$$?; test $$rc = 0
	grep '^STRESS fs rw PASS ' fs/t.out
	grep '^STRESS fs append PASS ' fs/t.out
	grep '^STRESS fs tree PASS ' fs/t.out
	grep '^STRESS fs fsync PASS ' fs/t.out
	if test -n "$$STRESS_FILL_DIR"; then rc=0; $(FSBIN) -t 3000 -d $$STRESS_FILL_DIR fill >fs/t.out || rc=$$?; test $$rc = 0; grep '^STRESS fs fill PASS ' fs/t.out; fi
	rc=0; $(FSBIN) -d /nonexistent rw >fs/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason="mkdir: ENOENT"' fs/t.out
	rc=0; $(FSBIN) -x -i 5 rw append >fs/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS fs [a-z]* FAIL .*off=0x' fs/t.out` = 2
	@echo fs: ok

install: all

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -f lib/*.o lib/libstress.a lib/t_lib $(TMAIN) lib/t.out lib/t.err vm/*.o $(VMBIN) vm/t.out mmap/*.o $(MMAPBIN) mmap/t.out fs/*.o $(FSBIN) fs/t.out

.PHONY: all check check-vm check-mmap check-fs install installhdrs installsrc clean
