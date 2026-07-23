CC = cc
CFLAGS = -ansi -pedantic -Wall -O

d = $(DSTROOT)
p = rbuild

OBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o main.o

TESTS = tests/test_strutil tests/test_package tests/test_manifest tests/test_builder

.PHONY: all clean install installhdrs installsrc test trace-test

all: rbuild

rbuild: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# Unit tests: each test binary links the module objects (except main.o).
LIBOBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o

test: $(TESTS)
	@fail=0; for t in $(TESTS); do echo "== $$t =="; ./$$t || fail=1; done; \
		[ $$fail -eq 0 ] && echo "ALL TESTS PASSED" || (echo "TESTS FAILED"; exit 1)

tests/test_strutil: tests/test_strutil.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_strutil.c $(LIBOBJS)
tests/test_package: tests/test_package.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_package.c $(LIBOBJS)
tests/test_manifest: tests/test_manifest.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_manifest.c $(LIBOBJS)
tests/test_builder: tests/test_builder.c $(LIBOBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_builder.c $(LIBOBJS)

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
