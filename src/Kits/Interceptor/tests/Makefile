CC ?= cc
FRAMEWORK_ROOT ?=
OBJROOT ?= BUILD/obj
SYMROOT ?= BUILD/sym
TESTS = abi

.PHONY: all $(TESTS)
all: $(TESTS)

abi: $(SYMROOT)/abi
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/abi

$(SYMROOT)/abi: abi.m test_support.m test_support.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ abi.m test_support.m -framework Foundation
