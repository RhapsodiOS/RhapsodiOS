CC = cc
CFLAGS = -ansi -pedantic -Wall -O

d = $(DSTROOT)
p = rbuild

OBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o main.o

TESTS = tests/test_strutil tests/test_package tests/test_manifest tests/test_builder tests/test_exec

.PHONY: all clean install installhdrs installsrc test trace-test

all: rbuild

rbuild: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# Unit tests: each test binary links ONLY the module objects it needs, so a
# test can be built as soon as its modules exist (incremental TDD). As a
# module grows new dependencies, extend the matching object list below.
test: $(TESTS)
	@fail=0; for t in $(TESTS); do echo "== $$t =="; ./$$t || fail=1; done; \
		[ $$fail -eq 0 ] && echo "ALL TESTS PASSED" || (echo "TESTS FAILED"; exit 1)

test_strutil_OBJS = strutil.o
test_package_OBJS = strutil.o package.o
test_manifest_OBJS = strutil.o manifest.o
test_builder_OBJS = strutil.o package.o builder.o
test_exec_OBJS = strutil.o exec.o

tests/test_strutil: tests/test_strutil.c $(test_strutil_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_strutil.c $(test_strutil_OBJS)
tests/test_package: tests/test_package.c $(test_package_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_package.c $(test_package_OBJS)
tests/test_manifest: tests/test_manifest.c $(test_manifest_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_manifest.c $(test_manifest_OBJS)
tests/test_builder: tests/test_builder.c $(test_builder_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_builder.c $(test_builder_OBJS)
tests/test_exec: tests/test_exec.c $(test_exec_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_exec.c $(test_exec_OBJS)

trace-test: rbuild
	sh tests/trace/run.sh

install: rbuild
	install -d $(d)/usr/bin
	install -c -m 755 rbuild $(d)/usr/bin/rbuild

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	$(RM) $(OBJS) rbuild $(TESTS) tests/*.o
	find . -name \*~ -print0 | xargs -0 $(RM)
