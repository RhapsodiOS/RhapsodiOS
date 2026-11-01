# Foundation `_NSPrintForDebugger` analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/NSDebug.m`.

## IDA behavior

IDA decompiles `_NSPrintForDebugger` at `0x42570f58` as a guarded object
description helper. It returns fixed diagnostic strings for a null pointer,
an unreadable/non-object pointer, objects without `debugDescription`, an
exception while generating the description, and a nil or empty description.
For a usable object it calls `debugDescription` under the Objective-C
exception handler, retains the returned string in a static global, and returns
its `lossyCString` pointer. The previous static description is released at the
next call. The function therefore keeps the returned C string alive until a
subsequent call.

The pseudocode makes the cache lifetime slightly asymmetric: a null receiver
returns `"<nil>"` before releasing the previous cached description. For a
non-null receiver it releases and clears that description before validation.
The validation requires four readable bytes, then accepts the pointer if
either its first word or the pointer itself is a registered class. The
non-responding diagnostic is exactly
`"<object does not respond to PrintObject method>"`, even though the checked
selector is `debugDescription`. On the normal handler path it stores the
returned object, removes the handler, handles nil and empty strings with
`"<object returns empty description>"`, and retains only a non-empty result
before returning `lossyCString`.

Before messaging a candidate pointer, IDA calls `isReadableAddr` and
`isClass`. The source already has the equivalent static
`NSDebugIsReadableAddress` check in `NSDebug.m`, used by `NSIsFreedObject`; it
checks the readable VM region and the full requested byte span. `NSBundle.m`
also traverses `objc_getClasses()` with `NXInitHashState` and
`NXNextHashState`, the same primitives used by IDA's `isClass`, which returns
whether a pointer exactly matches any registered class. `NSBundle` uses that
iteration to enumerate classes; the source has no reusable class-membership
predicate yet. The readability check and class-table scan can be implemented
in Foundation source without messaging an unvalidated pointer.

IDA's `_isReadableAddr` at `0x4257225c` checks that the address is above the
first page, that `vm_region` reports readable memory containing the full
requested span, and that the region begins no later than the address. The
existing `NSDebugIsReadableAddress` performs the corresponding page, readable
protection, region-start, and end-bound checks. IDA's `_isClass` at
`0x42572208` only enumerates `objc_getClasses()` and compares pointer identity;
it does not dereference the candidate. `NSException.h` already defines the
same `NSHandler2` layout and `_NSAddHandler2`, `_NSRemoveHandler2`, and
`_NSExceptionObjectFromHandler2` routines used by the target's setjmp handler.

## Existing debugger methods

`NSDebug.m` implements `-[NSObject(NSDebuggerExtras) printForDebugger:]` and
`-[NSProxy(NSDebuggerExtras) printForDebugger:]` by writing
`[self description]` to an `NXStream`. They are separate APIs and do not
substitute for this C helper: they do not validate arbitrary pointers, use
`debugDescription`, catch exceptions, or preserve a returned C string.

To implement `_NSPrintForDebugger`, reuse `NSDebugIsReadableAddress`, add the
IDA-confirmed class-table identity check in `NSDebug.m`, and preserve the
diagnostics, handler flow, and static description lifetime. Do not replace
the checks with direct Objective-C messaging on arbitrary pointers.

## Current ABI coverage

`reconstruction/abi/NSDebug.json` records both `printForDebugger:` category
methods but does not claim `_NSPrintForDebugger` in `text_symbols`. The
exact-profile audit on 2026-10-04 reports nine unclaimed exports, including
this one. The implementation belongs in
`NSDebug.m`; the existing category methods are different selectors and do not
satisfy that export.
