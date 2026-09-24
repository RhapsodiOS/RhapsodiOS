CC = cc
# Plain -ansi/-pedantic break Rhapsody System headers (__inline, u_int32_t).
CFLAGS = -Wall -O

d = $(DSTROOT)
p = rbuild

OBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o architecture.o products.o macho.o toolchain.o apk.o vendor.o kernel.o runner.o main.o

TESTS = tests/test_products tests/test_macho tests/test_architecture tests/test_strutil tests/test_package tests/test_manifest tests/test_builder tests/test_exec tests/test_pkginfo tests/test_toolchain tests/test_apk tests/test_kernel tests/test_runner tests/test_vendor

.PHONY: all clean install installhdrs installsrc test trace-test

all: rbuild

rbuild: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS)

.c.o:
	$(CC) $(CFLAGS) -c -o $@ $<

# Unit tests: each test binary links ONLY the module objects it needs, so a
# test can be built as soon as its modules exist (incremental TDD). As a
# module grows new dependencies, extend the matching object list below.
test: rbuild $(TESTS)
	@fail=0; for t in $(TESTS); do echo "== $$t =="; ./$$t || fail=1; done; \
		[ $$fail -eq 0 ] && echo "ALL TESTS PASSED" || (echo "TESTS FAILED"; exit 1)
	MAKE=$(MAKE) sh tests/bootstrap-resume.sh
	MAKE=$(MAKE) sh tests/bootstrap-closure.sh
	MAKE=$(MAKE) sh tests/bootstrap-runtime-manifest.sh
	MAKE=$(MAKE) sh tests/buildpackage-toolchain.sh

test_products_OBJS = products.o macho.o architecture.o strutil.o
test_macho_OBJS = macho.o
test_architecture_OBJS = architecture.o

test_strutil_OBJS = strutil.o
test_package_OBJS = strutil.o package.o architecture.o
test_manifest_OBJS = strutil.o manifest.o
test_builder_OBJS = strutil.o package.o exec.o toolchain.o pkginfo.o builder.o architecture.o products.o macho.o apk.o vendor.o
test_exec_OBJS = strutil.o exec.o
test_pkginfo_OBJS = strutil.o package.o exec.o toolchain.o apk.o pkginfo.o products.o macho.o architecture.o
test_toolchain_OBJS = strutil.o toolchain.o
test_apk_OBJS = strutil.o exec.o toolchain.o tests/apk_test.o products.o macho.o architecture.o
test_kernel_OBJS = strutil.o kernel.o
test_runner_OBJS = strutil.o package.o manifest.o exec.o pkginfo.o builder.o architecture.o products.o macho.o toolchain.o apk.o vendor.o kernel.o tests/runner_test.o
test_vendor_OBJS = strutil.o exec.o toolchain.o apk.o products.o macho.o architecture.o vendor.o

tests/apk_test.o: apk.c apk.h
	$(CC) $(CFLAGS) -DRBUILD_APK_TESTING -c -o $@ apk.c

tests/runner_test.o: runner.c runner.h
	$(CC) $(CFLAGS) -DRBUILD_RUNNER_TESTING -c -o $@ runner.c

tests/test_products: tests/test_products.c $(test_products_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_products.c $(test_products_OBJS)

tests/test_macho: tests/test_macho.c $(test_macho_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_macho.c $(test_macho_OBJS)

tests/test_architecture: tests/test_architecture.c $(test_architecture_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_architecture.c $(test_architecture_OBJS)

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
tests/test_pkginfo: tests/test_pkginfo.c $(test_pkginfo_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_pkginfo.c $(test_pkginfo_OBJS)
tests/test_toolchain: tests/test_toolchain.c $(test_toolchain_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_toolchain.c $(test_toolchain_OBJS)
tests/test_apk: tests/test_apk.c $(test_apk_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_apk.c $(test_apk_OBJS)
tests/test_kernel: tests/test_kernel.c $(test_kernel_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_kernel.c $(test_kernel_OBJS)

tests/test_vendor: tests/test_vendor.c $(test_vendor_OBJS)
	$(CC) $(CFLAGS) -I. -o $@ tests/test_vendor.c $(test_vendor_OBJS)

tests/test_runner: tests/test_runner.c $(test_runner_OBJS)
	$(CC) $(CFLAGS) -DRBUILD_RUNNER_TESTING -I. -o $@ tests/test_runner.c $(test_runner_OBJS)

# rbuild APK dry-run: universal probes and thin RC_*
trace-test: rbuild
	sh tests/trace/run.sh

install: rbuild
	install -d $(d)/usr/bin
	install -c -m 755 rbuild $(d)/usr/bin/rbuild

installhdrs:

installsrc:
	gnutar --exclude=CVS --exclude=.git --exclude=.hg -cf - . | gnutar -C $(SRCROOT) -xf -

clean:
	$(RM) $(OBJS) rbuild $(TESTS) tests/*.o
	find . -name \*~ -print0 | xargs -0 $(RM)
