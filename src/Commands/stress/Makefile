# RhapsodiOS project Makefile for the system stress suite. rbuild runs
# `make install` with DSTROOT and RC_CFLAGS. Objects are built next to their
# sources because rbuild copies the source tree. GNU make 3.74: pattern rules
# only, no $(call), no target-specific variables.
LIBOBJS = lib/rng.o lib/pattern.o lib/report.o lib/main.o lib/sysinfo.o lib/io.o
CC      = cc
CFLAGS  = -O -Wall $(RC_CFLAGS) -Ilib
TMAIN   = lib/stress-tmain
VMBIN   = vm/stress-vm
MMAPBIN = mmap/stress-mmap
FSBIN   = fs/stress-fs
PROCBIN = proc/stress-proc
CHILDBIN = proc/stress-exec-child
NETBIN = net/stress-net
IPCBIN = ipc/stress-ipc
IPCNAMES = ipc/stress-ipc-names

all: lib/libstress.a $(VMBIN) $(MMAPBIN) $(FSBIN) $(PROCBIN) $(CHILDBIN) $(NETBIN) $(IPCBIN)

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

proc/%.o: proc/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(PROCBIN): proc/proc.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ proc/proc.o lib/libstress.a

$(CHILDBIN): proc/child.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ proc/child.o lib/libstress.a

net/%.o: net/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(NETBIN): net/net.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ net/net.o lib/libstress.a

ipc/%.o: ipc/%.c lib/stress.h
	$(CC) $(CFLAGS) -c $< -o $@

$(IPCBIN): ipc/ipc.o lib/libstress.a
	$(CC) $(CFLAGS) -o $@ ipc/ipc.o lib/libstress.a

$(IPCNAMES): ipc/names.o
	$(CC) $(CFLAGS) -o $@ ipc/names.o

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
	grep 'STRESS tmain fail FAIL reason=planned worker=[0-9]* iter=0 seed=' lib/t.out
	rm -f /tmp/stress.tmain.hook
	rc=0; $(TMAIN) hook >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason=planned worker=' lib/t.out
	test -f /tmp/stress.tmain.hook
	rm -f /tmp/stress.tmain.hook
	rc=0; $(TMAIN) crash >lib/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL signal=11 worker=' lib/t.out
	rc=0; $(TMAIN) -n 3 -t 20 crashwait >lib/t.out || rc=$$?; test $$rc = 1
	grep 'STRESS tmain crashwait FAIL signal=11 worker=0 seed=' lib/t.out
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
	mkdir -p fs/rw; rc=0; (cd fs && ./stress-fs -n 1 -i 1 -d rw) >fs/t.out || rc=$$?; rm -rf fs/rw; test $$rc = 0; test `grep -c '^STRESS fs fill ' fs/t.out` = 0
	rc=0; $(FSBIN) -d /nonexistent rw >fs/t.out || rc=$$?; test $$rc = 1
	grep 'FAIL reason="mkdir: ENOENT"' fs/t.out
	rc=0; $(FSBIN) -x -i 5 rw append >fs/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS fs [a-z]* FAIL .*off=0x' fs/t.out` = 2
	@echo fs: ok

# signal is the dyld regression: a copy of stress-proc pointed (same-length
# path) at the 1998 dyld must die with exit 68; skipped if that dyld is absent.
check-proc: $(PROCBIN) $(CHILDBIN)
	rc=0; $(PROCBIN) -n 2 -i 50 >proc/t.out || rc=$$?; test $$rc = 0
	test `grep -c '^STRESS proc \(fork\|exec\|signal\|stack\|pipe\) PASS ' proc/t.out` = 5
	rc=0; $(PROCBIN) -x -i 5 fork exec stack pipe >proc/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS proc [a-z]* FAIL ' proc/t.out` = 4
	test `grep -c '^STRESS proc \(stack\|pipe\) FAIL .*off=0x' proc/t.out` = 2
	if test -f /usr/lib/dyld.cctools-266; then \
		cp /usr/lib/dyld.cctools-266 /tmp/dyldOLD1; chmod 555 /tmp/dyldOLD1; \
		perl -pe 's|/usr/lib/dyld|/tmp/dyldOLD1|' $(PROCBIN) >proc/stress-proc.old; chmod 755 proc/stress-proc.old; \
		rc=0; proc/stress-proc.old -n 1 -i 50 signal >proc/t.out || rc=$$?; \
		rm -f /tmp/dyldOLD1 proc/stress-proc.old; \
		test $$rc = 1; grep '^STRESS proc signal FAIL exit=68 ' proc/t.out; \
	else echo "check-proc: no /usr/lib/dyld.cctools-266, dyld regression skipped"; fi
	@echo proc: ok

# fdpass is PASS or UNSUP; the -x run needs tcp, udp and unix to FAIL with an offset.
check-net: $(NETBIN)
	rc=0; $(NETBIN) -n 4 -i 50 -d /tmp >net/t.out || rc=$$?; test $$rc = 0
	test `grep -c '^STRESS net \(tcp\|udp\|unix\|select\|accept\) PASS ' net/t.out` = 5
	grep '^STRESS net fdpass \(PASS\|UNSUP\) ' net/t.out
	rc=0; $(NETBIN) -x -i 5 -d /tmp tcp udp unix >net/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS net [a-z]* FAIL .*off=0x' net/t.out` = 3
	@echo net: ok

# sysv must be UNSUP, the rest PASS or UNSUP; -x makes msg, ool and rights
# FAIL (msg and ool at an offset). After each run no "stress." name may stay
# registered in mach_init (it drops one when its port dies, so allow 5 s).
NONAMES = n=x; for t in 1 2 3 4 5 6; do n=`$(IPCNAMES)`; test "$$n" = 0 && break; sleep 1; done; test "$$n" = 0

check-ipc: $(IPCBIN) $(IPCNAMES)
	rc=0; $(IPCBIN) -n 2 -i 50 >ipc/t.out || rc=$$?; test $$rc = 0
	test `grep -c '^STRESS ipc \(msg\|ool\|rights\|deadname\|bootstrap\) \(PASS\|UNSUP\) ' ipc/t.out` = 5
	grep '^STRESS ipc sysv UNSUP reason="semget: ENOSYS"' ipc/t.out
	$(NONAMES)
	rc=0; $(IPCBIN) -x -i 5 msg ool rights >ipc/t.out || rc=$$?; test $$rc = 1
	test `grep -c '^STRESS ipc [a-z]* FAIL ' ipc/t.out` = 3
	test `grep -c '^STRESS ipc \(msg\|ool\) FAIL .*off=0x' ipc/t.out` = 2
	$(NONAMES)
	@echo ipc: ok

# run exercises the whole chain on the vm category only.
check-run: $(VMBIN)
	touch /tmp/stress.junk.1
	rc=0; sh ./run -d /tmp 1 vm >/dev/null || rc=$$?; test $$rc = 0
	test ! -f /tmp/stress.junk.1
	grep '^vm PASS=[0-9]* FAIL=0 ' Report/summary
	@echo run: ok

STRESSDIR = $(DSTROOT)/usr/local/stress

install: all
	for d in vm mmap fs proc net Report; do install -d -m 755 $(STRESSDIR)/$$d; done
	install -m 755 $(VMBIN) vm/runtests $(STRESSDIR)/vm
	install -m 755 $(MMAPBIN) mmap/runtests $(STRESSDIR)/mmap
	install -m 755 $(FSBIN) fs/runtests $(STRESSDIR)/fs
	install -m 755 $(PROCBIN) $(CHILDBIN) proc/runtests $(STRESSDIR)/proc
	install -m 755 $(NETBIN) net/runtests $(STRESSDIR)/net
	install -m 755 run $(STRESSDIR)
	install -m 644 README $(STRESSDIR)

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	rm -f lib/*.o lib/libstress.a lib/t_lib $(TMAIN) lib/t.out lib/t.err vm/*.o $(VMBIN) vm/t.out mmap/*.o $(MMAPBIN) mmap/t.out fs/*.o $(FSBIN) fs/t.out proc/*.o $(PROCBIN) $(CHILDBIN) proc/t.out proc/stress-proc.old net/*.o $(NETBIN) net/t.out ipc/*.o $(IPCBIN) $(IPCNAMES) ipc/t.out

.PHONY: all check check-vm check-mmap check-fs check-proc check-net check-ipc check-run install installhdrs installsrc clean
