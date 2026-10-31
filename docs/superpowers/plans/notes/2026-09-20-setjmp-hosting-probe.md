# Stage 2b Task 1: setjmp/longjmp hosting probe

## RESULT: hosted

The guest hosts the `_setjmp`/`_longjmp` handler-stack pattern that `NSException.h`'s
`NS_DURING`/`NS_HANDLER` macros assume. All three probe scenarios passed with zero
failures: a raise several frames deep transfers to the handler and preserves the
payload; normal completion pops the handler without transferring; and a nested
inner raise is caught by the inner handler with the outer surviving intact.

## Guest environment

- `uname -a`:
  `Rhapsody rhap1 5.3 Kernel Release 5.3: Fri Sep 18 12:06:49 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386 Copyright (c) 1988-1995,1997-1999 Apple Computer, Inc. All Rights Reserved.  i386`
- `cc -v`:
  `Reading specs from /usr/libexec/i386/2.7.2.1/specs`
  `Apple Computer, Inc. version cc-771.4, based on gcc version 2.7.2.1`

## Box substitution (differs from the plan's assumption)

The plan was written against the native ppc Rhapsody 5.6 box at `10.10.0.241`, which is
unreachable (network-layer: the gateway answers "Destination host unreachable"). This
probe was run instead on the project's i386 QEMU guest ("hfsle", kernel built 2026-09-18
from kernel-154.5.1-7), reached over the host's SSH forward at `127.0.0.1:2121`, with
sources staged at `/tmp/f2b/` (this box has no `/build/source/src/Kits` convention).

Consequence, favourable to the stage: the guest is **natively i386**, so the
test-binary builds and the `abi-check` `-arch i386` object builds are the same
architecture. The plan's "two different builds" constraint still holds for linkage
(test binaries are linked; abi objects are compiled with `-c`), but every compile is
i386, matching the reference of record (`Foundation-i386`). The Task 12 `-arch i386`
flag is accepted by this cc and is a no-op here.

## `_NSSETJMP` resolves to `_setjmp`; `_longjmp` is mandatory

`NSException.h` defines `_NSSETJMP(B, S)` as `_setjmp((B))` on this platform (not
`__svr4__`, `__WIN32__` or `__hpux__`). `_setjmp`/`_longjmp` do not save or restore the
signal mask, and pairing `_setjmp` with `longjmp` (or `setjmp` with `_longjmp`) is
undefined. Every raise path in this stage therefore uses `_longjmp` exclusively. The
probe used `_setjmp`/`_longjmp` throughout, which is the pairing the reconstructed code
will use.

## Exact build and run line (reused verbatim by Tasks 7-10)

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_<name> <test-source> <module-sources...> /tmp/f2b/link_stubs.m
```

For the C probe itself (throwaway, run from the directory holding the probe source):

```sh
cc -o /tmp/probe_setjmp probe_setjmp.c
/tmp/probe_setjmp
```

## Probe source

The probe below was compiled verbatim. It simulates the `NSHandler2` chain exactly as
the macros use it: an automatic handler record whose `_state` is a `jmp_buf`, `_others`
as the chain link, `_exception` written by the raiser before transferring.

```c
/*  Does _setjmp/_longjmp unwind the way NSException.h's NS_DURING /
    NS_HANDLER macros assume on this guest?  */

#include <setjmp.h>
#include <stdio.h>

typedef struct _ProbeHandler {
    jmp_buf _state;
    void *_exception;
    void *_others;
    void *_thread;
    void *_reserved1;
} ProbeHandler;

static ProbeHandler *probeStack = 0;
static int failures = 0;

static void ProbeAdd(ProbeHandler *handler)
{
    handler->_exception = 0;
    handler->_others = (void *)probeStack;
    probeStack = handler;
}

static void ProbeRemove(ProbeHandler *handler)
{
    probeStack = (ProbeHandler *)handler->_others;
}

static void ProbeRaise(void *payload)
{
    ProbeHandler *handler = probeStack;

    if (handler == 0) {
        printf("FAIL raise with no handler\n");
        failures++;
        return;
    }
    probeStack = (ProbeHandler *)handler->_others;
    handler->_exception = payload;
    _longjmp(handler->_state, 1);
}

/*  A nested call, so the raise happens several frames below the handler.  */
static void deep(int depth)
{
    if (depth > 0) {
        deep(depth - 1);
        return;
    }
    ProbeRaise((void *)0x5EED);
}

int main(void)
{
    ProbeHandler outer;
    ProbeHandler inner;
    int reached;

    /*  1. A raise several frames deep lands in the handler.  */
    reached = 0;
    ProbeAdd(&outer);
    if (!_setjmp(outer._state)) {
        deep(8);
        printf("FAIL raise did not transfer\n");
        failures++;
    } else {
        reached = 1;
        if (outer._exception != (void *)0x5EED) {
            printf("FAIL payload not preserved\n");
            failures++;
        }
    }
    if (!reached) { printf("FAIL handler body not entered\n"); failures++; }
    if (probeStack != 0) { printf("FAIL stack not popped by raise\n"); failures++; }

    /*  2. Normal completion pops without transferring.  */
    ProbeAdd(&outer);
    if (!_setjmp(outer._state)) {
        ProbeRemove(&outer);
    } else {
        printf("FAIL normal path took the handler branch\n");
        failures++;
    }
    if (probeStack != 0) { printf("FAIL stack not empty after normal path\n"); failures++; }

    /*  3. Nesting: the inner handler catches, the outer survives.  */
    ProbeAdd(&outer);
    if (!_setjmp(outer._state)) {
        ProbeAdd(&inner);
        if (!_setjmp(inner._state)) {
            ProbeRaise((void *)0xBEEF);
            printf("FAIL inner raise did not transfer\n");
            failures++;
        } else {
            if (inner._exception != (void *)0xBEEF) {
                printf("FAIL inner payload wrong\n");
                failures++;
            }
        }
        if (probeStack != &outer) {
            printf("FAIL outer handler not restored after inner catch\n");
            failures++;
        }
        ProbeRemove(&outer);
    } else {
        printf("FAIL inner raise escaped to outer\n");
        failures++;
    }
    if (probeStack != 0) { printf("FAIL stack not empty at end\n"); failures++; }

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

## Observed output

```
BUILD-OK
PASSED: 0 failure(s)
run-status=0
```
