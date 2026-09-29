CC ?= cc
FRAMEWORK_ROOT ?=
OBJROOT ?= BUILD/obj
SYMROOT ?= BUILD/sym
TESTS = abi bitmap shape copy ipc rect framebuffer palette screen

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

ipc: $(SYMROOT)/ipc
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/ipc

rect: $(SYMROOT)/rect
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/rect

framebuffer: $(SYMROOT)/framebuffer
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/framebuffer

palette: $(SYMROOT)/palette
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/palette

screen: $(SYMROOT)/screen
	@test -n "$(FRAMEWORK_ROOT)" || { echo "FRAMEWORK_ROOT must select a version-A Interceptor.framework" >&2; exit 2; }
	FRAMEWORK_ROOT="$(FRAMEWORK_ROOT)" $(SYMROOT)/screen

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

$(SYMROOT)/ipc: ipc.c test_support.m test_support.h ../Interceptor_types.h ../Private/InterceptorIPC.h ../InterceptorIPC.c
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -DINTERCEPTOR_IPC_TEST_TRANSPORT -I.. -I../../../objc-1 -o $@ ipc.c ../InterceptorIPC.c test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/rect: rect.m test_support.m test_support.h ../Private/NSInterceptedRect.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ rect.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/framebuffer: framebuffer.m test_support.m test_support.h ../NSFramebuffer.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ framebuffer.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/palette: palette.m test_support.m test_support.h ../NSDirectPalette.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ palette.m test_support.m -framework AppKit -framework Foundation

$(SYMROOT)/screen: screen.m test_support.m test_support.h ../NSDirectScreen.h
	@mkdir -p $(OBJROOT) $(SYMROOT)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. -I../../../objc-1 -o $@ screen.m test_support.m -framework AppKit -framework Foundation
