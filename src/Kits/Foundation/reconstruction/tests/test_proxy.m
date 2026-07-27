/*  Behavioural tests for NSProxy, stage 2a.  NSProxy is a root class whose
    purpose is to forward; a concrete subclass supplies the forwarding.  */

#import <Foundation/NSProxy.h>
#import <Foundation/NSObject.h>
#import <objc/objc-runtime.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  link_stubs.m's raise-capture mechanism (see its own comment): a test
    arms NSTestExpectingRaise and calls setjmp(NSTestRaiseEnv) around a call
    expected to end in [NSException raise:format:]; when armed, the stub
    longjmp()s back with the raised format string copied into
    NSTestRaiseMessage instead of aborting the whole binary.  Declared
    extern here rather than in a header per this task's header freeze --
    link_stubs.m supplies the storage.  */
extern jmp_buf NSTestRaiseEnv;
extern int NSTestExpectingRaise;
extern char NSTestRaiseMessage[256];

/*  raiseWasCaught() is the reusable half of that pattern: call it with a
    no-argument function that performs the message send under test (the
    receiver and any arguments are passed via the file-scope statics below,
    since C89 has no closures).  Returns 1 if action() ended in a captured
    raise, 0 if it returned normally -- the latter is itself a failure for
    every call site below, all of which expect an unconditional raise.  */
static int raiseWasCaught(void (*action)(void))
{
    int caught;

    NSTestExpectingRaise = 1;
    if (setjmp(NSTestRaiseEnv) == 0) {
        action();
        caught = 0;
    } else {
        caught = 1;
    }
    NSTestExpectingRaise = 0;
    return caught;
}

static id sProxyUnderTest;

/*  Garbage, non-nil arguments throughout: -forwardInvocation:,
    -methodSignatureForSelector:, and -forward:: all raise without ever
    reading self, the selector, or the invocation/argFrame argument
    (confirmed from the disassembly, see NSProxy.m's comments above each).
    Passing values that would crash on dereference is the point -- it is
    what "ignoring its arguments" actually forces a wrong stub-like
    implementation to prove, rather than merely asserting it in a comment.  */
static void invoke_forwardInvocation_with_garbage(void)
{
    [sProxyUnderTest forwardInvocation:(NSInvocation *)0x1];
}

static void invoke_methodSignatureForSelector_with_garbage(void)
{
    [sProxyUnderTest methodSignatureForSelector:(SEL)0x1];
}

static void invoke_forward_with_garbage(void)
{
    [sProxyUnderTest forward:@selector(self) :(marg_list)0x1];
}

static void invoke_isKindOfClass(void)
{
    [sProxyUnderTest isKindOfClass:[NSProxy class]];
}

static void invoke_isMemberOfClass(void)
{
    [sProxyUnderTest isMemberOfClass:[NSProxy class]];
}

static void invoke_conformsToProtocol(void)
{
    [sProxyUnderTest conformsToProtocol:(Protocol *)0x1];
}

static void invoke_respondsToSelector(void)
{
    [sProxyUnderTest respondsToSelector:@selector(self)];
}

/*  The brief gives this as `CHECK([NSProxy superclass] == nil)`.  The
    reference disagrees, for the same reason test_object.m's
    test_class_introspection_on_the_class_object already documents for
    NSObject: NSProxy's ABI has no class-side +superclass (confirmed
    against abi/NSProxy.json's 20 class methods -- unlike NSObject, which
    defines one explicitly), so `[NSProxy superclass]` falls through the
    metaclass chain to NSProxy's own -superclass (isa->super_class), with
    self bound to the NSProxy class object itself.  A root metaclass's
    super_class is tied back to its class (objc-class.m:708,
    _class_install_relationships, the same mechanism cited there), so that
    read returns NSProxy, not nil.  Confirmed on the guest directly:
    `[NSProxy superclass] == [NSProxy class]` is true.  Per this task's
    brief, the reference wins and the test changes: `[NSProxy class]
    superclass` (an actual instance's -superclass, unaffected by the
    tie-down) is nil, which is what a root class's ivar/instance_size
    contract in abi/NSProxy.json (superclass: null) actually describes;
    `[NSProxy superclass]` sent to the class object itself is a different,
    non-nil question.  */
static void test_proxy_is_a_root_class(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy superclass] == nil);
    CHECK([NSProxy superclass] == [NSProxy class]);
    [proxy dealloc];
}

static void test_alloc_produces_an_instance(void)
{
    id proxy = [NSProxy alloc];

    CHECK(proxy != nil);
    CHECK([proxy class] == [NSProxy class]);
    [proxy dealloc];
}

static void test_proxy_reports_its_own_class(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy self] == proxy);
    [proxy dealloc];
}

static void test_retain_count_starts_at_one(void)
{
    id proxy = [NSProxy alloc];

    CHECK([proxy retainCount] == 1);
    [proxy dealloc];
}

/*  The class object itself is not a proxy; only its instances are -- the
    one YES/NO answer that differs from NSObject's (see NSProxy.m's comment
    above +isProxy/-isProxy, confirmed from the disassembly: +isProxy is
    `xor eax,eax`, -isProxy is `mov eax,1`).  A wrong implementation that
    answered the same on both sides would pass every other test in this
    file, which is exactly why this needs its own case.  */
static void test_isProxy_class_instance_asymmetry(void)
{
    id proxy = [NSProxy alloc];

    CHECK([NSProxy isProxy] == NO);
    CHECK([proxy isProxy] == YES);
    [proxy dealloc];
}

static void test_forwardInvocation_raises_unconditionally(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_forwardInvocation_with_garbage));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy forwardInvocation:] called!") == 0);
    [proxy dealloc];
}

static void test_methodSignatureForSelector_raises_unconditionally(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_methodSignatureForSelector_with_garbage));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy methodSignatureForSelector:] called!") == 0);
    [proxy dealloc];
}

/*  +initialize (see NSProxy.m's comment above it) patches -[NSProxy
    forward::]'s installed method_imp to -[NSObject forward::]'s, once, the
    first time any message is ever sent to NSProxy or an instance -- which
    by this point in the suite has already happened (test_alloc_produces_
    an_instance's [NSProxy alloc], among others).  [NSProxy class] here is
    just belt-and-braces self-documentation, not what actually triggers it.
    A missing or no-op patch would leave -forward:: raising with NSProxy's
    own compiled text ("*** -[NSProxy forward::] not overridden!"); the
    correct, patched behaviour raises with NSObject's instead ("*** forward::
    implementation not overridden", NSObject.m).  Also exercises the
    "ignores its arguments" half of the requirement: forward:: is sent with
    a garbage argFrame that neither body ever reads.  */
static void test_forward_colon_colon_runs_nsobjects_patched_body(void)
{
    id proxy;

    [NSProxy class];
    proxy = [NSProxy alloc];
    sProxyUnderTest = proxy;

    CHECK(raiseWasCaught(invoke_forward_with_garbage));
    CHECK(strcmp(NSTestRaiseMessage, "*** forward:: implementation not overridden") == 0);

    [proxy dealloc];
}

/*  -isKindOfClass:/-isMemberOfClass:/-conformsToProtocol:/
    -respondsToSelector: do not answer directly from isa the way NSObject's
    do (see NSProxy.m's comment above -isKindOfClass:) -- they route through
    -forwardInvocation:, which always raises.  A wrong-but-plausible
    implementation that answered YES/NO directly from isa would pass every
    other test in this file; asserting each of these four actually raises,
    with -forwardInvocation:'s own message text, is what catches that.  */
static void test_isKindOfClass_routes_through_forwarding(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_isKindOfClass));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy forwardInvocation:] called!") == 0);
    [proxy dealloc];
}

static void test_isMemberOfClass_routes_through_forwarding(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_isMemberOfClass));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy forwardInvocation:] called!") == 0);
    [proxy dealloc];
}

static void test_conformsToProtocol_routes_through_forwarding(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_conformsToProtocol));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy forwardInvocation:] called!") == 0);
    [proxy dealloc];
}

static void test_respondsToSelector_routes_through_forwarding(void)
{
    id proxy = [NSProxy alloc];

    sProxyUnderTest = proxy;
    CHECK(raiseWasCaught(invoke_respondsToSelector));
    CHECK(strcmp(NSTestRaiseMessage, "*** -[NSProxy forwardInvocation:] called!") == 0);
    [proxy dealloc];
}

int main(void)
{
    test_proxy_is_a_root_class();
    test_alloc_produces_an_instance();
    test_proxy_reports_its_own_class();
    test_retain_count_starts_at_one();
    test_isProxy_class_instance_asymmetry();
    test_forwardInvocation_raises_unconditionally();
    test_methodSignatureForSelector_raises_unconditionally();
    test_forward_colon_colon_runs_nsobjects_patched_body();
    test_isKindOfClass_routes_through_forwarding();
    test_isMemberOfClass_routes_through_forwarding();
    test_conformsToProtocol_routes_through_forwarding();
    test_respondsToSelector_routes_through_forwarding();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
