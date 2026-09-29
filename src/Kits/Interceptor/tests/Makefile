CC ?= cc
FRAMEWORK_ROOT ?=
OBJROOT ?= BUILD/obj
SYMROOT ?= BUILD/sym
TESTS = abi bitmap shape copy

.PHONY: all $(TESTS)
all: $(TESTS)

abi: $(SYMROOT)/abi
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/abi

bitmap: $(SYMROOT)/bitmap
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/bitmap

shape: $(SYMROOT)/shape
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/shape

copy: $(SYMROOT)/copy
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/copy

$(SYMROOT)/abi: abi.m test_support.m test_support.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ abi.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/bitmap: bitmap.m test_support.m test_support.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ bitmap.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/shape: shape.m test_support.m test_support.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ shape.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/copy: copy.c test_support.m test_support.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ copy.c test_support.m -framework AppKit -framework Foundation
