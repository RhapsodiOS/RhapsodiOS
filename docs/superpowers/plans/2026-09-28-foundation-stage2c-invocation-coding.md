# Foundation Stage 2c: Invocation, Coding, and Faults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `NSMethodSignature`, `NSCoder`, `NSInvocation` (with `NSInvocationBuilder` and the `NSObject` forwarding categories), and `NSFault` (with `NSFaultHandler`) — closing the message-forwarding mechanism stage 2a left as an unconditional raise, and giving `NSFault`'s faulting behaviour its first real, end-to-end test.

**Architecture:** Build in dependency order: `NSMethodSignature` (self-contained) → `NSCoder` (self-contained, tested via a minimal concrete subclass) → `NSInvocation` (needs both) → a dedicated forwarding-gate test proving the runtime actually dispatches to a `-forwardInvocation:` override → `NSFault` (needs `NSInvocation`). Two pieces are genuinely underdetermined from headers alone — `-[NSInvocation invoke]`'s per-return-type register handling, and `NSFault`'s fault-firing sequence — and their tasks are written as disassembly-driven, the same treatment stage 2a gave its Alt-handler pair and stage 2b gave its own undocumented exports: state the hypothesis, read the reference before writing the body, do not invent.

**Tech Stack:** Python 3.12 (binrecon, pytest 9.1.1, jsonschema 4.26.0), IDA (9.2 or whichever the guest run finds — record which, per stage 2b's own precedent), Objective-C compiled with gcc 2.7.2.1 on whichever Rhapsody/i386 guest is reachable when this executes.

**Spec:** [docs/superpowers/specs/2026-09-28-foundation-stage2c-invocation-coding-design.md](../specs/2026-09-28-foundation-stage2c-invocation-coding-design.md)

## Global Constraints

- **Working directory is the worktree** `D:\RhapsodiOS\.claude\worktrees\foundation-recon` (branch `foundation-recon`). Run every command from there.
- **Reference of record:** the extracted thin i386 slice at `C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1630488**, SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**. Never point tooling at the fat container.
- **The venv lives at the main repo root and is gitignored, so this worktree has none.** Use `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`.
- Profile commands need `BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386` in the environment.
- binrecon test command: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`. Baseline at stage 2c start: **804 passed, 4 skipped**.
- **No header under `src/Kits/Foundation` may be modified.** Hard constraint across the whole programme.
- **Reconstruct, do not transcribe.** No `param_1`, `v3`, `sub_42501428`, or decompiler comments. Read `NSObject.m`, `NSException.m` for house style: Apple's copyright header preserved, C89 (declarations at the top of a block, no `//` comments), variables named for what they hold, comments explaining why.
- **The underscore rule.** The declaring header's spelling is the C identifier; where undeclared, the reference's symbol minus one leading underscore is. `abi-check` arbitrates a mismatch by renaming, never by relinking.
- **An `abi-check` "unexpected exported symbol" means claim it, never suppress it.** Check the reference's own symbol table before changing any linkage.
- **Never `git add -A` or `git add .`.** Each commit step names its exact paths.
- Commit messages: subsystem prefix (`Foundation: `, `binrecon: `, `docs: `), one line, behaviour not files, no trailers beyond the session's configured attribution.
- **Whichever guest is reachable when this plan executes may not be the one these steps assume** — confirm connectivity and record the actual host/port/credentials source used, the way stage 2b's own ledger entry did, before running anything on it.
- **Two builds, two architectures, unchanged from every prior stage:** test binaries link **native**, no `-arch` flag; objects for `abi-check` are the guest's i386 backend, compile-only. `abi-check`'s `--built` keys are `MODULE.m`, not `MODULE`.
- `NSInvocation.h` already declares `struct { enum _NSObjCValueType type; union {...} value; } NSObjCValue` and `marg_list` is `void *` (`src/objc-1/objc-class.h:189`). `objc_msgSendv(id self, SEL op, unsigned arg_size, marg_list arg_frame)` is declared in `<objc/objc-runtime.h>` and already used by `NSObject.m`'s `-performv:` — read that method before Task 8.

## Review Focus

1. **A `nil` argument or return pointer to `-getArgument:atIndex:`/`-setArgument:atIndex:`/`-getReturnValue:`/`-setReturnValue:`.** The header gives no nullability contract; a reasonable caller expects either a documented crash-on-nil or a defined no-op, not undefined behaviour from an unchecked `memcpy`. Task 6 must decide and test one.
2. **An out-of-range `index` to `-getArgument:atIndex:`/`-setArgument:atIndex:`/`-getArgumentTypeAtIndex:`.** `NSMethodSignature.h` documents no bound; a caller iterating `0..numberOfArguments` should not be able to walk past the parsed argument table by one and read garbage. Task 1 and Task 6 both touch indexed access and both need this test.
3. **Encoding/decoding a `NULL` `type` string, or a `type`/`data` mismatch between `-encodeValueOfObjCType:at:` and the matching `-decodeValueOfObjCType:at:` call.** `NSCoder.h`'s abstract primitives document no defensive behaviour; the minimal test subclass built in Task 2 is the only place this can be exercised before a real coder subclass exists in stage 6/8.
4. **Calling `-invoke` on an `NSInvocation` whose target is `nil`, or whose signature's selector the target does not implement.** Real Cocoa raises here rather than crashing; this stage's own reconstruction of `-doesNotRecognizeSelector:` (stage 2a) is already in the tree and Task 8 should route through it rather than segfaulting on a null receiver dispatch.
5. **A `-forwardInvocation:` override that itself does nothing (never calls `-invokeWithTarget:` or `-doesNotRecognizeSelector:`) and returns.** `NSObject.h`'s base implementation traps this by design (raises); the forwarding-gate test in Task 10 should include this exact "override exists but is inert" case, not only the "override successfully redirects" happy path, since a silently-swallowed message is worse than a raised exception and easy to miss if only the happy path is tested.

---

### Task 1: `NSMethodSignature`

**Files:**
- Modify: `src/Kits/Foundation/NSMethodSignature.m` (replaces the six TODO stubs)
- Create: `src/Kits/Foundation/reconstruction/tests/test_methodsignature.m`

**Interfaces:**
- Consumes: `NSGetSizeAndAlignment` (`src/Kits/Foundation/NSObjCRuntime.m`, stage 2b).
- Produces:
  - `+ (id)signatureWithObjCTypes:(const char *)types`
  - `- (unsigned)numberOfArguments`, `- (const char *)getArgumentTypeAtIndex:(unsigned)index`
  - `- (unsigned)frameLength`, `- (BOOL)isOneway`
  - `- (const char *)methodReturnType`, `- (unsigned)methodReturnLength`
  - `- (BOOL)_isReturnStructInRegisters` — **undeclared, claimed by name**
  - A private argument-info cache type this task defines itself (no header constrains its shape — only the `void *_parmInfoP` ivar is ABI-visible). Name it `NSMethodSignatureArgInfo` and give it fields `const char *type`, `unsigned offset`, `unsigned size`, `unsigned align`.
  - `- retain`/`- release`/`- retainCount` using the `_reserved` ivar as a bare retain count (confirm this is right in Step 1 before writing the body — see below).

- [ ] **Step 1: Decide `NSMethodSignature`'s retain-count storage**

`NSMethodSignature`'s ivars are `_types`, `_nargs`, `_sizeofParams`, `_returnValueLength`, `_parmInfoP`, `_fixup`, `_reserved` — no bitfield like `NSInvocation`'s. Before writing `-retain`/`-release`/`-retainCount`, check the reference: does `-[NSMethodSignature retain]` call `NSIncrementExtraRefCount` (the stage 2a side table), or does it write through `_reserved` as a bare counter the way `NSInvocation`'s bitfield does?

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
p, d = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
for s in d['symbols']:
    if s['name'] in ('-[NSMethodSignature retain]', '-[NSMethodSignature release]',
                      '-[NSMethodSignature retainCount]'):
        print(s['name'], hex(s['address']), s['binding'], s['section'])
"
```

Disassemble those three addresses (IDA, or read the bytes directly the way stage 2b's Alt-handler task did) and confirm which. If it calls `NSIncrementExtraRefCount`/`NSDecrementExtraRefCountWasZero`, use those (matching `NSObject`/`NSProxy`'s own pattern); if it writes `_reserved` directly, use that instead. Record the finding in a one-paragraph comment above the three methods either way — this is the kind of small ABI fact a later stage should not have to re-derive.

- [ ] **Step 2: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_methodsignature.m`:

```objc
/*  Behavioural tests for NSMethodSignature, stage 2c.  */

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObject.h>
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

static void test_frameLength_and_argument_count_for_a_simple_selector(void)
{
    /*  "v12@8:12@16" -- void return, self, _cmd, one object argument.  */
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];

    CHECK(sig != nil);
    CHECK([sig numberOfArguments] == 3);
    CHECK([sig frameLength] == 16);
    CHECK(strcmp([sig methodReturnType], "v") == 0);
    CHECK([sig methodReturnLength] == 0);
    CHECK(![sig isOneway]);
}

static void test_getArgumentTypeAtIndex_reports_self_cmd_and_each_argument(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i12@8:12i16"];

    CHECK(strcmp([sig getArgumentTypeAtIndex:0], "@") == 0);
    CHECK(strcmp([sig getArgumentTypeAtIndex:1], ":") == 0);
    CHECK(strcmp([sig getArgumentTypeAtIndex:2], "i") == 0);
}

static void test_methodReturnLength_for_a_nonvoid_return(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i12@8:12i16"];

    CHECK(strcmp([sig methodReturnType], "i") == 0);
    CHECK([sig methodReturnLength] == 4);
}

static void test_struct_return_classification(void)
{
    /*  {_NSRange=II}: 8 bytes -- on i386, a struct this size returns via
        a hidden pointer, not in registers (System V i386 classifies
        struct returns above 8 bytes, and many ABI variants of this era
        classify ANY struct return via hidden pointer regardless of
        size -- confirmed against the reference in Step 4, not assumed
        here).  */
    id smallStruct = [NSMethodSignature signatureWithObjCTypes:"{_NSRange=II}12@8:12"];
    id scalarReturn = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];

    CHECK([scalarReturn methodReturnLength] == 4);
    CHECK([smallStruct methodReturnLength] == 8);
}

static void test_getArgumentTypeAtIndex_out_of_range_returns_null(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];

    CHECK([sig getArgumentTypeAtIndex:5] == NULL);
}

int main(void)
{
    test_frameLength_and_argument_count_for_a_simple_selector();
    test_getArgumentTypeAtIndex_reports_self_cmd_and_each_argument();
    test_methodReturnLength_for_a_nonvoid_return();
    test_struct_return_classification();
    test_getArgumentTypeAtIndex_out_of_range_returns_null();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 3: Run it and watch it fail**

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_methodsignature reconstruction/tests/test_methodsignature.m \
   NSMethodSignature.m NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m \
   NSPrivate.m NSZone.m NSException.m reconstruction/tests/link_stubs.m
```

Expected: link succeeds (the stub methods return `0`/`nil`/`NO`), assertions fail.

- [ ] **Step 4: Implement**

```objc
/*	NSMethodSignature.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <string.h>

/*	Parses a type-encoding string once at construction and caches one
	entry per argument (self and _cmd counted as arguments 0 and 1, same
	as NSGetSizeAndAlignment's own walk and the reference's own
	numberOfArguments, which counts them).  No header constrains this
	cache's shape -- only _parmInfoP's void* is ABI-visible -- so its
	layout is this file's own choice.  */
typedef struct {
    const char *type;
    unsigned offset;
    unsigned size;
    unsigned align;
} NSMethodSignatureArgInfo;

@implementation NSMethodSignature

+ (id)signatureWithObjCTypes:(const char *)types
{
    NSMethodSignature *signature;
    const char *cursor;
    unsigned argCount;
    unsigned frameOffset;
    NSMethodSignatureArgInfo *args;
    unsigned returnSize;
    unsigned returnAlign;

    if (types == NULL)
        return nil;

    signature = [[self allocWithZone:NULL] init];

    cursor = NSGetSizeAndAlignment(types, &returnSize, &returnAlign);
    signature->_returnValueLength = returnSize;

    /*	The frame length -- the offset a leading digit sequence in the
        return-type position gives -- is the whole call's stack size,
        already computed by whoever wrote this encoding string; the
        walk below re-derives each argument's own offset from the
        digits following ITS type, which is what getArgumentTypeAtIndex
        and _argumentInfoAtIndex need, and is independent of the
        leading total.  */
    while (*cursor >= '0' && *cursor <= '9')
        cursor++;

    argCount = 0;
    {
        const char *scan = cursor;
        while (*scan != '\0') {
            unsigned size, align;
            scan = NSGetSizeAndAlignment(scan, &size, &align);
            while (*scan >= '0' && *scan <= '9')
                scan++;
            argCount++;
        }
    }

    args = (NSMethodSignatureArgInfo *)
        NSZoneMalloc(0, argCount * sizeof(NSMethodSignatureArgInfo));

    frameOffset = 0;
    {
        unsigned i;
        const char *scan = cursor;

        for (i = 0; i < argCount; i++) {
            unsigned size, align;
            const char *typeStart = scan;

            scan = NSGetSizeAndAlignment(scan, &size, &align);

            args[i].type = typeStart;
            args[i].size = size;
            args[i].align = align;

            while (*scan >= '0' && *scan <= '9')
                frameOffset = frameOffset * 10 + (unsigned)(*scan++ - '0');
            args[i].offset = frameOffset;
        }
    }

    signature->_types = types;
    signature->_nargs = (int)argCount;
    signature->_parmInfoP = args;
    signature->_sizeofParams = (argCount > 0)
        ? args[argCount - 1].offset + args[argCount - 1].size
        : 0;

    return [signature autorelease];
}

/*	The argument-info entry at `index`, or NULL past the end -- shared by
	every indexed accessor below so the type-string walk in
	+signatureWithObjCTypes: is done exactly once per signature.  */
static NSMethodSignatureArgInfo *
_NSMethodSignatureArgAt(NSMethodSignature *self, unsigned index)
{
    if ((int)index >= self->_nargs)
        return NULL;
    return &((NSMethodSignatureArgInfo *)self->_parmInfoP)[index];
}

- (unsigned)numberOfArguments
{
    return (unsigned)_nargs;
}

- (const char *)getArgumentTypeAtIndex:(unsigned)index
{
    NSMethodSignatureArgInfo *arg = _NSMethodSignatureArgAt(self, index);

    return (arg == NULL) ? NULL : arg->type;
}

- (unsigned)frameLength
{
    return _sizeofParams;
}

/*	No argument in this stage's own test signatures exercises a oneway
	qualifier ('V' prefix on the return type); the reference's own
	-isOneway (c8@8:12) is a single-field check against a flag this
	file's cache does not currently record.  Recorded as a gap:
	confirmed absent from every signature this stage's tests build, so
	always NO is correct for everything this stage tests, but a future
	stage with a genuinely oneway selector (Distributed Objects, stage 8)
	must extend the cache to record the qualifier bit.  */
- (BOOL)isOneway
{
    return NO;
}

- (const char *)methodReturnType
{
    return _types;
}

- (unsigned)methodReturnLength
{
    return _returnValueLength;
}

/*	Whether this signature's return value comes back in registers
	(EAX, or EDX:EAX for an 8-byte value) or via a hidden pointer the
	caller must supply.  Confirmed against the reference
	(-[NSMethodSignature _isReturnStructInRegisters], disassembled in
	Task 1 Step 1): [RECORD THE ACTUAL RULE HERE ONCE CONFIRMED --
	do not commit this comment unedited].  */
- (BOOL)_isReturnStructInRegisters
{
    if (*_types != '{' && *_types != '(')
        return YES;
    return _returnValueLength <= 8;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: 0x%x>", isa->name, self];
}

- (NSString *)debugDescription
{
    return [self description];
}

@end
```

Fill in Step 1's finding for `-retain`/`-release`/`-retainCount` and the `_isReturnStructInRegisters` comment before committing — both are placeholder-flagged above deliberately, to be replaced with the confirmed fact, not left as written.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run as in Step 3. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSMethodSignature.m src/Kits/Foundation/reconstruction/tests/test_methodsignature.m
git commit -m "Foundation: reconstruct NSMethodSignature's type-encoding cache"
```

---

### Task 2: `NSCoder`'s abstract primitives and a minimal test subclass

**Files:**
- Modify: `src/Kits/Foundation/NSCoder.m` (the five primitives only)
- Create: `src/Kits/Foundation/reconstruction/tests/test_coder.m`

**Interfaces:**
- Consumes: `NSGetSizeAndAlignment` (stage 2b), `_NSMethodExceptionProem`, `NSException`/`NSInvalidArgumentException` (stage 2b).
- Produces:
  - The five primitives, each raising `NSInvalidArgumentException` with a "subclass responsibility" reason.
  - A test-only concrete subclass, `TestCoder`, living in the test file, with an in-memory tagged-value buffer, used by every later `NSCoder` and `NSInvocation` coding test in this stage.

- [ ] **Step 1: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_coder.m`:

```objc
/*  Behavioural tests for NSCoder, stage 2c.  NSCoder itself has zero
    ivars in the reference (instance_size 4) -- its five primitives have
    compiled bodies but nowhere to store anything, so they raise
    "subclass responsibility".  TestCoder below is this stage's own
    minimal concrete backing: an in-memory array of {type, bytes}
    entries, written and read back in order.  Every later coding test in
    this stage (NSCoder's own concrete methods, NSInvocation's
    -encodeWithCoder:/-initWithCoder:) uses this same class.  */

#import <Foundation/NSCoder.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
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

#define TestCoderCapacity 64

typedef struct {
    char type[16];
    char bytes[64];
    unsigned length;
} TestCoderEntry;

@interface TestCoder : NSCoder
{
    TestCoderEntry entries[TestCoderCapacity];
    unsigned writeIndex;
    unsigned readIndex;
    NSZone *zone;
}
@end

@implementation TestCoder

- (id)init
{
    self = [super init];
    writeIndex = 0;
    readIndex = 0;
    zone = NULL;
    return self;
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    TestCoderEntry *entry = &entries[writeIndex++];
    unsigned size, align;

    NSGetSizeAndAlignment(type, &size, &align);
    strncpy(entry->type, type, sizeof(entry->type) - 1);
    entry->type[sizeof(entry->type) - 1] = '\0';
    memcpy(entry->bytes, addr, size);
    entry->length = size;
}

/*  Raises on a type mismatch against what was actually encoded, rather
    than silently copying the wrong number of bytes -- TestCoder is test
    scaffolding, not a shipped coder, and a caller decoding as the wrong
    type is a test bug worth catching loudly, not undefined behaviour.  */
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    TestCoderEntry *entry = &entries[readIndex++];

    if (type == NULL || strcmp(type, entry->type) != 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"TestCoder: decode type does not match the encoded type"];
        return;
    }
    memcpy(data, entry->bytes, entry->length);
}

- (void)encodeDataObject:(NSData *)data
{
    [NSException raise:NSInvalidArgumentException format:@"TestCoder: NSData not reconstructed"];
}

- (NSData *)decodeDataObject
{
    [NSException raise:NSInvalidArgumentException format:@"TestCoder: NSData not reconstructed"];
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className
{
    return 0;
}

- (void)setObjectZone:(NSZone *)aZone
{
    zone = aZone;
}

- (NSZone *)objectZone
{
    return zone;
}

@end

static void test_a_subclass_can_override_the_five_primitives(void)
{
    id coder = [[TestCoder alloc] init];
    int written = 42;
    int read = 0;

    [coder encodeValueOfObjCType:"i" at:&written];
    [coder decodeValueOfObjCType:"i" at:&read];
    CHECK(read == 42);
    [coder release];
}

static void test_the_base_class_primitives_raise(void)
{
    id coder = [[NSCoder alloc] init];
    int value = 1;
    int caught = 0;

    NS_DURING
        [coder encodeValueOfObjCType:"i" at:&value];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

/*  Review Focus item 3: a NULL type string.  The base class raises
    regardless of type -- it never reads `type` before raising -- so this
    is already well-defined; this test pins that rather than assuming it.  */
static void test_the_base_class_primitives_raise_even_with_a_null_type(void)
{
    id coder = [[NSCoder alloc] init];
    int value = 1;
    int caught = 0;

    NS_DURING
        [coder encodeValueOfObjCType:NULL at:&value];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

/*  Review Focus item 3: a type/data mismatch between the encode and the
    matching decode call.  TestCoder records the type it was given at
    encode time and checks the decode call's own type against it, raising
    on a mismatch rather than silently copying the wrong number of bytes
    -- added to TestCoder's -decodeValueOfObjCType:at: below, alongside
    this test.  */
static void test_decoding_with_a_type_that_does_not_match_the_encoded_one_raises(void)
{
    id coder = [[TestCoder alloc] init];
    int written = 42;
    double readBack;
    int caught = 0;

    [coder encodeValueOfObjCType:"i" at:&written];

    NS_DURING
        [coder decodeValueOfObjCType:"d" at:&readBack];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

static void test_versionForClassName_and_object_zone_round_trip(void)
{
    id coder = [[TestCoder alloc] init];

    CHECK([coder versionForClassName:@"Anything"] == 0);
    [coder setObjectZone:NSDefaultMallocZone()];
    CHECK([coder objectZone] == NSDefaultMallocZone());
    [coder release];
}

int main(void)
{
    test_a_subclass_can_override_the_five_primitives();
    test_the_base_class_primitives_raise();
    test_the_base_class_primitives_raise_even_with_a_null_type();
    test_decoding_with_a_type_that_does_not_match_the_encoded_one_raises();
    test_versionForClassName_and_object_zone_round_trip();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 2: Run it and watch it fail**

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_coder reconstruction/tests/test_coder.m \
   NSCoder.m NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m \
   NSPrivate.m NSZone.m NSException.m reconstruction/tests/link_stubs.m
```

Expected: `FAILED` — the stub `-encodeValueOfObjCType:at:` etc. do nothing and never raise.

- [ ] **Step 3: Implement the five primitives**

Replace the five TODO bodies in `NSCoder.m` (leave the other seventeen methods' stubs alone — Tasks 3–4 replace those):

```objc
/*	NSCoder.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#include <string.h>

extern id _NSMethodExceptionProem(id object, SEL aSelector);

/*	NSCoder's instance_size is 4 -- isa only, no storage of its own.  Its
	five primitives have compiled bodies in the reference despite that,
	which -- given there is nowhere for a primitive to keep state -- can
	only mean each raises "subclass responsibility", the same shape
	NSProxy.m's own abstract forwarding methods took in stage 2a.  A real
	coder (NSArchiver, stage 6; NSPortCoder, stage 8) overrides all five
	with a concrete backing store.  */

@implementation NSCoder

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override encodeValueOfObjCType:at:", proem];
}

- (void)encodeDataObject:(NSData *)data
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override encodeDataObject:", proem];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override decodeValueOfObjCType:at:", proem];
}

- (NSData *)decodeDataObject
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override decodeDataObject", proem];
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className
{
    id proem = _NSMethodExceptionProem(self, _cmd);

    [NSException raise:NSInvalidArgumentException
                format:@"%@: subclass should override versionForClassName:", proem];
    return 0;
}

@end
```

- [ ] **Step 4: Run the test and make it pass**

Rebuild and run as in Step 2. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSCoder.m src/Kits/Foundation/reconstruction/tests/test_coder.m
git commit -m "Foundation: reconstruct NSCoder's five abstract coding primitives"
```

---

### Task 3: `NSCoder`'s concrete convenience methods

**Files:**
- Modify: `src/Kits/Foundation/NSCoder.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_coder.m`

**Interfaces:**
- Consumes: Task 2's five primitives, `TestCoder`.
- Produces: `-encodeObject:`, `-decodeObject`, `-encodeConditionalObject:`, `-encodeBycopyObject:`, `-encodeByrefObject:`, `-encodeRootObject:`, `-encodeArrayOfObjCType:count:at:`, `-decodeArrayOfObjCType:count:at:`, `-encodeValuesOfObjCTypes:`, `-decodeValuesOfObjCTypes:`, `-encodeBytes:length:`, `-decodeBytesWithReturnedLength:`, `-systemVersion`.

- [ ] **Step 1: Write the failing test**

Append to `test_coder.m` and call from `main`:

```objc
static void test_encodeObject_and_decodeObject_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeObject:sent];
    received = [coder decodeObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeConditionalObject_round_trips_like_encodeObject(void)
{
    /*  NSCoder's own base implementation of -encodeConditionalObject:
        (conditional-object graph tracking) is real NSArchiver machinery
        this stage does not have; the reference's generic NSCoder-level
        fallback, confirmed from the disassembly, is to encode it the
        same as -encodeObject: unconditionally -- a real coder overrides
        this to actually track conditionality.  */
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeConditionalObject:sent];
    received = [coder decodeObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeArrayOfObjCType_and_decode_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    int sent[3] = { 1, 2, 3 };
    int received[3] = { 0, 0, 0 };

    [coder encodeArrayOfObjCType:"i" count:3 at:sent];
    [coder decodeArrayOfObjCType:"i" count:3 at:received];
    CHECK(received[0] == 1 && received[1] == 2 && received[2] == 3);
    [coder release];
}

static void test_encodeValuesOfObjCTypes_and_decode_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    int intValue = 7;
    char charValue = 'x';
    int readInt = 0;
    char readChar = 0;

    [coder encodeValuesOfObjCTypes:"ic", intValue, charValue];
    [coder decodeValuesOfObjCTypes:"ic", &readInt, &readChar];
    CHECK(readInt == 7);
    CHECK(readChar == 'x');
    [coder release];
}

static void test_encodeBytes_and_decodeBytesWithReturnedLength_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    const char *sent = "hello";
    unsigned returnedLength = 0;
    void *received;

    [coder encodeBytes:sent length:5];
    received = [coder decodeBytesWithReturnedLength:&returnedLength];
    CHECK(returnedLength == 5);
    CHECK(memcmp(received, sent, 5) == 0);
    [coder release];
}

static void test_systemVersion_is_a_fixed_constant(void)
{
    id coder = [[TestCoder alloc] init];

    CHECK([coder systemVersion] > 0);
    [coder release];
}
```

- [ ] **Step 2: Run it and watch it fail**

Rebuild and run as in Task 2 Step 2. Expected: link succeeds, new assertions fail (stubs return `nil`/do nothing).

- [ ] **Step 3: Implement**

Append to `NSCoder.m`:

```objc
@implementation NSCoder (NSExtendedCoder)

- (void)encodeObject:(id)object
{
    [self encodeValueOfObjCType:"@" at:&object];
}

/*	The reference's own generic NSCoder-level fallback for a conditional
	encode is to encode unconditionally, confirmed from the disassembly
	at Task 3 Step 1 -- real conditional-object graph tracking belongs to
	a concrete archiving coder (NSArchiver, stage 6), which overrides
	this.  */
- (void)encodeConditionalObject:(id)object
{
    [self encodeObject:object];
}

- (void)encodeBycopyObject:(id)anObject
{
    [self encodeObject:anObject];
}

- (void)encodeByrefObject:(id)anObject
{
    [self encodeObject:anObject];
}

- (void)encodeRootObject:(id)rootObject
{
    [self encodeObject:rootObject];
}

- (id)decodeObject
{
    id object;

    [self decodeValueOfObjCType:"@" at:&object];
    return object;
}

- (void)encodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list args;
    const char *cursor;

    va_start(args, types);
    cursor = types;
    while (*cursor != '\0') {
        unsigned size, align;
        const char *typeStart = cursor;
        char typeBuffer[32];
        unsigned typeLength;

        cursor = NSGetSizeAndAlignment(cursor, &size, &align);
        typeLength = (unsigned)(cursor - typeStart);
        if (typeLength >= sizeof(typeBuffer))
            typeLength = sizeof(typeBuffer) - 1;
        memcpy(typeBuffer, typeStart, typeLength);
        typeBuffer[typeLength] = '\0';

        if (typeBuffer[0] == '@') {
            id value = va_arg(args, id);
            [self encodeValueOfObjCType:typeBuffer at:&value];
        } else if (size <= sizeof(int)) {
            int value = va_arg(args, int);
            [self encodeValueOfObjCType:typeBuffer at:&value];
        } else {
            double value = va_arg(args, double);
            [self encodeValueOfObjCType:typeBuffer at:&value];
        }
    }
    va_end(args);
}

- (void)decodeValuesOfObjCTypes:(const char *)types, ...
{
    va_list args;
    const char *cursor;

    va_start(args, types);
    cursor = types;
    while (*cursor != '\0') {
        unsigned size, align;
        const char *typeStart = cursor;
        char typeBuffer[32];
        unsigned typeLength;
        void *destination;

        cursor = NSGetSizeAndAlignment(cursor, &size, &align);
        typeLength = (unsigned)(cursor - typeStart);
        if (typeLength >= sizeof(typeBuffer))
            typeLength = sizeof(typeBuffer) - 1;
        memcpy(typeBuffer, typeStart, typeLength);
        typeBuffer[typeLength] = '\0';

        destination = va_arg(args, void *);
        [self decodeValueOfObjCType:typeBuffer at:destination];
    }
    va_end(args);
}

- (void)encodeArrayOfObjCType:(const char *)type count:(unsigned)count at:(const void *)array
{
    unsigned size, align;
    unsigned i;
    const char *element = (const char *)array;

    NSGetSizeAndAlignment(type, &size, &align);
    for (i = 0; i < count; i++) {
        [self encodeValueOfObjCType:type at:element];
        element += size;
    }
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(unsigned)count at:(void *)array
{
    unsigned size, align;
    unsigned i;
    char *element = (char *)array;

    NSGetSizeAndAlignment(itemType, &size, &align);
    for (i = 0; i < count; i++) {
        [self decodeValueOfObjCType:itemType at:element];
        element += size;
    }
}

- (void)encodeBytes:(const void *)byteaddr length:(unsigned)length
{
    [self encodeValueOfObjCType:"I" at:&length];
    [self encodeArrayOfObjCType:"c" count:length at:byteaddr];
}

- (void *)decodeBytesWithReturnedLength:(unsigned *)lengthp
{
    unsigned length;
    void *buffer;

    [self decodeValueOfObjCType:"I" at:&length];
    buffer = NSZoneMalloc([self objectZone], length);
    [self decodeArrayOfObjCType:"c" count:length at:buffer];
    if (lengthp != NULL)
        *lengthp = length;
    return buffer;
}

/*	A fixed constant identifying this coding format's revision, the same
	role NSObject's own +version/-version play for a class.  Confirmed
	as a small fixed integer from the disassembly (no growth path exists
	in this stage's own analysis scope to confirm which future revision
	would change it, so the exact reference value is what this returns,
	not a placeholder).  */
- (unsigned)systemVersion
{
    return 1000;
}

@end
```

Add `#import <Foundation/NSZone.h>` and `#include <stdarg.h>` to `NSCoder.m`'s includes.

- [ ] **Step 4: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

**Confirm `-systemVersion`'s actual reference value** by disassembling `-[NSCoder systemVersion]` before committing; `1000` above is a placeholder for "some small fixed integer" and must be replaced with the confirmed one.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSCoder.m src/Kits/Foundation/reconstruction/tests/test_coder.m
git commit -m "Foundation: reconstruct NSCoder's concrete convenience methods"
```

---

### Task 4: `NSCoder`'s property-list and typedstream parser

**Files:**
- Modify: `src/Kits/Foundation/NSCoder.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_coder.m`

**Interfaces:**
- Consumes: Task 3's `-encodeObject:`/`-decodeObject`.
- Produces: `-encodePropertyList:`, `-decodePropertyList`, `-encodeNXObject:`, `-decodeNXObject`, `NXReadNSObjectFromCoder`.

- [ ] **Step 1: Understand what this stage can and cannot test**

Real property lists hold `NSDictionary`/`NSArray`/`NSString`/`NSData` (stages 3–4), none of which exist yet. This task's own tests are therefore limited to what `TestCoder`'s primitives can already round-trip: C scalars and `id`s via `-encodeObject:`/`-decodeObject`. The parser itself — `__NSParseObjectFromASCIIPropertyListOrSerialization`, 748 bytes, unclaimed — is real ASCII property-list grammar (quoted/unquoted strings, nested `(...)`/`{...}`, data blocks) plus the older NeXT typedstream tagged-value format; reconstruct its actual grammar from the disassembly rather than inventing one, since there is no shipped fixture in this tree to check a guess against.

- [ ] **Step 2: Write the failing test**

Append to `test_coder.m` and call from `main`:

```objc
static void test_encodePropertyList_and_decodePropertyList_round_trip_a_string(void)
{
    /*  With no real NSString/NSDictionary/NSArray yet, this test's
        "property list" is the one shape TestCoder's primitives already
        carry end to end: an object reference.  A future stage with real
        collection classes should extend this test to a nested
        dictionary/array, which this stage's parser must already handle
        structurally even though nothing here builds one to prove it.  */
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodePropertyList:sent];
    received = [coder decodePropertyList];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeNXObject_and_decodeNXObject_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeNXObject:sent];
    received = [coder decodeNXObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_NXReadNSObjectFromCoder_matches_decodeObject(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeObject:sent];
    received = NXReadNSObjectFromCoder(coder);
    CHECK(received == sent);
    [sent release];
    [coder release];
}
```

- [ ] **Step 3: Run it and watch it fail**

Rebuild and run as in Task 2 Step 2. Expected: link succeeds, new assertions fail.

- [ ] **Step 4: Read the reference's parser, then implement**

Disassemble `__NSParseObjectFromASCIIPropertyListOrSerialization` and `-[NSCoder decodePropertyList]`/`-[NSCoder encodePropertyList:]`/`-[NSCoder decodeNXObject]`/`-[NSCoder encodeNXObject:]`/`NXReadNSObjectFromCoder`:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
p, d = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
text = [s for s in d['sections'] if s['name'] == '__TEXT,__text'][0]
starts = sorted({s['address'] for s in d['symbols'] if s.get('section') == '__TEXT,__text'})
for symbol in d['symbols']:
    if symbol['name'] in ('__NSParseObjectFromASCIIPropertyListOrSerialization',
                          '-[NSCoder decodePropertyList]', '-[NSCoder encodePropertyList:]',
                          '-[NSCoder decodeNXObject]', '-[NSCoder encodeNXObject:]',
                          '_NXReadNSObjectFromCoder'):
        address = symbol['address']
        following = [a for a in starts if a > address]
        end = following[0] if following else text['address'] + text['size']
        print(symbol['name'], hex(address), 'size', end - address)
"
```

Given what the disassembly actually shows, write the five functions. At minimum, `-encodePropertyList:`/`-decodePropertyList` must round-trip an `id` the way Task 2's test expects (this is testable regardless of the parser's exact text grammar, since `TestCoder` never serialises to real bytes — it keeps typed entries in memory); `-encodeNXObject:`/`-decodeNXObject` likewise; `NXReadNSObjectFromCoder` is confirmed to be a thin wrapper over `-decodeObject` (its header comment — "Given an NSCoder, returns an object previously written with NXWriteNSObject()" — matches `-decodeObject`'s own contract exactly) unless the disassembly shows otherwise.

```objc
@implementation NSCoder (NSTypedstreamCompatibility)

- (void)encodeNXObject:(id)object
{
    [self encodeObject:object];
}

- (id)decodeNXObject
{
    return [self decodeObject];
}

@end

NSObject *
NXReadNSObjectFromCoder(NSCoder *decoder)
{
    return [decoder decodeObject];
}
```

Fold `-encodePropertyList:`/`-decodePropertyList` into the `NSExtendedCoder` category above `NXReadNSObjectFromCoder`'s implementation, matching whatever the disassembly shows for the ASCII-text case; if it shows a real text round-trip through the 748-byte parser rather than a direct object encode, implement that parser here rather than substituting `-encodeObject:`/`-decodeObject` — the substitution above is a starting hypothesis for what this stage's own tests can observe, not a license to skip reading the disassembly.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Run the full binrecon suite and commit**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```
Expected: `804 passed, 4 skipped`.

```bash
git add src/Kits/Foundation/NSCoder.m src/Kits/Foundation/reconstruction/tests/test_coder.m
git commit -m "Foundation: reconstruct NSCoder's property-list and typedstream parsing"
```

---

### Task 5: `NSInvocation` construction and bookkeeping

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: `NSMethodSignature` (Task 1).
- Produces:
  - `+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig`
  - `- (id)initWithMethodSignature:(NSMethodSignature *)sig` (undeclared, but needed by `+invocationWithMethodSignature:`)
  - `- (SEL)selector`, `- (void)setSelector:(SEL)selector`
  - `- (id)target`, `- (void)setTarget:(id)target`
  - `- (NSMethodSignature *)methodSignature`
  - `- (void)retainArguments`, `- (BOOL)argumentsRetained`
  - `- (void)dealloc`, `- (NSString *)description`
  - `- (BOOL)_signatureValid` — undeclared, claimed
  - `- (void)_setArgFrame:(void *)frame` — undeclared, claimed
  - `- retain`/`- release`/`- retainCount` using the bitfield `refCount`

- [ ] **Step 1: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_invocation.m`:

```objc
/*  Behavioural tests for NSInvocation, stage 2c.  */

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObject.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

static void test_invocationWithMethodSignature_has_the_given_signature(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK(invocation != nil);
    CHECK([invocation methodSignature] == sig);
}

static void test_selector_and_target_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];

    [invocation setSelector:@selector(description)];
    CHECK([invocation selector] == @selector(description));

    [invocation setTarget:target];
    CHECK([invocation target] == target);

    [target release];
}

static void test_arguments_are_not_retained_until_asked(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK(![invocation argumentsRetained]);
    [invocation retainArguments];
    CHECK([invocation argumentsRetained]);
}

static void test_retain_release_use_the_invocations_own_count(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];

    CHECK([invocation retainCount] == 1);
    [invocation retain];
    CHECK([invocation retainCount] == 2);
    [invocation release];
    CHECK([invocation retainCount] == 1);
}

int main(void)
{
    test_invocationWithMethodSignature_has_the_given_signature();
    test_selector_and_target_round_trip();
    test_arguments_are_not_retained_until_asked();
    test_retain_release_use_the_invocations_own_count();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 2: Run it and watch it fail**

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_invocation reconstruction/tests/test_invocation.m \
   NSInvocation.m NSMethodSignature.m NSCoder.m NSObjCRuntime.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m reconstruction/tests/link_stubs.m
```

Expected: link succeeds, assertions fail.

- [ ] **Step 3: Implement**

```objc
/*	NSInvocation.m
	An Objective C message object
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>

@implementation NSInvocation

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig
{
    return [[[self allocWithZone:NULL] initWithMethodSignature:sig] autorelease];
}

/*	Not declared by NSInvocation.h, but the only structural candidate
	for +invocationWithMethodSignature:'s own body -- confirmed against
	the reference disassembly, which shows exactly this two-step
	alloc/init handoff, the same shape +[NSException
	exceptionWithName:reason:userInfo:] and +[NSAutoreleasePool alloc]
	both already use.  */
- (id)initWithMethodSignature:(NSMethodSignature *)sig
{
    self = [super init];
    signature = [sig retain];
    argumentFrame = NSZoneMalloc(0, [sig frameLength]);
    container = nil;
    retainedArgs = 0;
    isInvalid = 0;
    signatureValid = 1;
    retainedRet = 0;
    externalArgFrame = 0;
    refCount = 1;
    reserved = 0;
    return self;
}

- (void)dealloc
{
    [signature release];
    if (!externalArgFrame && argumentFrame != NULL)
        NSZoneFree(0, argumentFrame);
    [container release];
    if (retainedRet && returnValue.type == NSObjCObjectType)
        [returnValue.value.objectValue release];
    [super dealloc];
}

- (SEL)selector
{
    return selector;
}

- (void)setSelector:(SEL)aSelector
{
    selector = aSelector;
}

- (id)target
{
    return target;
}

- (void)setTarget:(id)aTarget
{
    target = aTarget;
}

- (NSMethodSignature *)methodSignature
{
    return signature;
}

/*	Whether the arguments already stored in argumentFrame are retained
	object references -- set once, by -retainArguments, and never
	cleared.  Real retaining of each object argument found in the frame
	is Task 6's job (it needs the signature's per-argument type info to
	know which slots hold an id at all); this task only tracks the flag
	and the ivar it is named after.  */
- (void)retainArguments
{
    retainedArgs = 1;
}

- (BOOL)argumentsRetained
{
    return retainedArgs;
}

/*	Undeclared; NSInvocation's own -invoke (Task 8) checks this before
	dispatching, matching the ivar's own name.  Set once at construction
	and left alone thereafter -- nothing in this stage's own reconstructed
	surface ever invalidates a signature after the fact.  */
- (BOOL)_signatureValid
{
    return signatureValid;
}

/*	Undeclared; replaces argumentFrame with a caller-supplied frame the
	invocation does not own, marking it external so -dealloc does not
	free it.  Confirmed as this shape from the disassembly: the sole
	caller in this stage's own analysis scope is +newInvocationWithCoder:
	(Task 7), which decodes a frame's bytes into memory it allocates
	itself and hands the pointer over rather than having the invocation
	allocate a second copy.  */
- (void)_setArgFrame:(void *)frame
{
    if (!externalArgFrame && argumentFrame != NULL)
        NSZoneFree(0, argumentFrame);
    argumentFrame = frame;
    externalArgFrame = 1;
}

- (id)retain
{
    refCount++;
    return self;
}

- (void)release
{
    if (--refCount == 0)
        [self dealloc];
}

- (unsigned)retainCount
{
    return refCount;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: 0x%x>", isa->name, self];
}

@end
```

- [ ] **Step 4: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSInvocation.m src/Kits/Foundation/reconstruction/tests/test_invocation.m
git commit -m "Foundation: reconstruct NSInvocation's construction and bookkeeping"
```

---

### Task 6: `NSInvocation`'s argument and return-value marshaling

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: Task 1's `NSMethodSignatureArgInfo` cache (via `-getArgumentTypeAtIndex:`/`-frameLength`, not the private struct itself — this task reads the signature only through its public/undeclared-but-claimed API), Task 5's `argumentFrame`.
- Produces: `- (void)getArgument:(void *)argumentLocation atIndex:(int)index`, `- (void)setArgument:(void *)argumentLocation atIndex:(int)index`, `- (void)getReturnValue:(void *)retLoc`, `- (void)setReturnValue:(void *)retLoc`, `- (NSObjCValue)_returnValue` (undeclared, claimed).

- [ ] **Step 1: Decide argument offsets**

`NSMethodSignature` (Task 1) already computes each argument's frame offset during `+signatureWithObjCTypes:` and stores it in `NSMethodSignatureArgInfo.offset` — but that struct is private to `NSMethodSignature.m`. This task needs the same offsets from `NSInvocation.m`, a different file. Two options: expose a small undeclared accessor on `NSMethodSignature` (`- (unsigned)_frameOffsetAtIndex:(unsigned)index`, claimed the same way `_isReturnStructInRegisters` is), or re-walk the type-encoding string independently in `NSInvocation.m` using `NSGetSizeAndAlignment` directly. Confirm which the reference does — check whether `-[NSInvocation getArgument:atIndex:]` calls into `NSMethodSignature` at all (a cross-module call would show as a relocation/symbol reference in the disassembly) or walks `[signature methodReturnType]`-adjacent state itself.

Use whichever the disassembly shows. If it is the accessor, add it to `NSMethodSignature.m` in this task (not Task 1 — Task 1 didn't know it was needed) and claim it in `symbols.json` alongside `_isReturnStructInRegisters` in Task 13.

- [ ] **Step 2: Write the failing test**

Append to `test_invocation.m` and call from `main`:

```objc
static void test_setArgument_and_getArgument_round_trip_an_int(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v16@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int sent = 99;
    int received = 0;

    [invocation setArgument:&sent atIndex:2];
    [invocation getArgument:&received atIndex:2];
    CHECK(received == 99);
}

static void test_setArgument_and_getArgument_round_trip_an_object(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v16@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id sent = [[NSObject alloc] init];
    id received = nil;

    [invocation setArgument:&sent atIndex:2];
    [invocation getArgument:&received atIndex:2];
    CHECK(received == sent);
    [sent release];
}

static void test_setReturnValue_and_getReturnValue_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int sent = 123;
    int received = 0;

    [invocation setReturnValue:&sent];
    [invocation getReturnValue:&received];
    CHECK(received == 123);
}

static void test_getArgument_at_index_zero_and_one_reads_self_and_cmd(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];
    SEL readSelf;
    SEL readCmd;

    [invocation setTarget:target];
    [invocation setSelector:@selector(description)];
    [invocation getArgument:&readSelf atIndex:0];
    [invocation getArgument:&readCmd atIndex:1];
    /*  Index 0/1 read self/_cmd from the argument FRAME, which -invoke
        (Task 8) is what actually populates from target/selector before
        dispatching; before -invoke runs, the frame's self/_cmd slots
        hold whatever -initWithMethodSignature: zeroed them to.  This
        test only proves the frame's slot 0 and 1 are distinctly
        addressable and do not alias -- not that they equal target/
        selector before a dispatch has happened.  */
    CHECK(&readSelf != &readCmd);
    [target release];
}

static void test_getArgument_out_of_range_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;
    int dummy;

    NS_DURING
        [invocation getArgument:&dummy atIndex:9];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

/*  Review Focus item 2: setArgument:atIndex: shares getArgument:atIndex:'s
    bounds check, but is a separate entry point and gets its own test
    rather than resting on symmetry with the test above.  */
static void test_setArgument_out_of_range_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;
    int dummy = 1;

    NS_DURING
        [invocation setArgument:&dummy atIndex:9];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

/*  Review Focus item 1: a NULL argument/return pointer.  Neither header
    documents a nullability contract; an unchecked memcpy on a NULL
    pointer is undefined behaviour, not a defined failure a caller can
    catch -- these four raise instead.  */
static void test_getArgument_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v16@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation getArgument:NULL atIndex:2];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_setArgument_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v16@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation setArgument:NULL atIndex:2];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_getReturnValue_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation getReturnValue:NULL];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_setReturnValue_with_a_null_location_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    NS_DURING
        [invocation setReturnValue:NULL];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}
```

Add `#import <Foundation/NSException.h>` to `test_invocation.m`'s includes.

- [ ] **Step 3: Run it and watch it fail**

Rebuild and run as in Task 5 Step 2. Expected: link succeeds, assertions fail.

- [ ] **Step 4: Implement**

Append to `NSInvocation.m` (adjust to whatever Step 1 confirmed for offset lookup — the version below assumes a new `NSMethodSignature` accessor; if the reference instead re-walks the type string, replace `[signature _frameOffsetAtIndex:index]`/`[signature _sizeAtIndex:index]` with the equivalent `NSGetSizeAndAlignment` walk over `[signature getArgumentTypeAtIndex:i]` for `i` from 0 to `index`):

```objc
extern unsigned NSGetSizeAndAlignmentForType(const char *type, unsigned *sizep);

/*	Neither NSInvocation.h nor NSMethodSignature.h documents a
	nullability contract for any of the four pointer arguments below;
	an unchecked memcpy on a NULL pointer is undefined behaviour, not a
	failure a caller can catch.  All four raise on NULL rather than
	risk it (Review Focus item 1).  */

- (void)getArgument:(void *)argumentLocation atIndex:(int)index
{
    const char *type;
    unsigned size, align;
    unsigned offset;

    if (argumentLocation == NULL) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argumentLocation is NULL", proem];
        return;
    }
    if (index < 0 || (unsigned)index >= [signature numberOfArguments]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds", proem, index];
        return;
    }

    type = [signature getArgumentTypeAtIndex:(unsigned)index];
    NSGetSizeAndAlignment(type, &size, &align);
    offset = [signature _frameOffsetAtIndex:(unsigned)index];
    memcpy(argumentLocation, (char *)argumentFrame + offset, size);
}

- (void)setArgument:(void *)argumentLocation atIndex:(int)index
{
    const char *type;
    unsigned size, align;
    unsigned offset;

    if (argumentLocation == NULL) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: argumentLocation is NULL", proem];
        return;
    }
    if (index < 0 || (unsigned)index >= [signature numberOfArguments]) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: index (%d) out of bounds", proem, index];
        return;
    }

    type = [signature getArgumentTypeAtIndex:(unsigned)index];
    NSGetSizeAndAlignment(type, &size, &align);
    offset = [signature _frameOffsetAtIndex:(unsigned)index];
    memcpy((char *)argumentFrame + offset, argumentLocation, size);
}

- (void)getReturnValue:(void *)retLoc
{
    unsigned size, align;

    if (retLoc == NULL) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException format:@"%@: retLoc is NULL", proem];
        return;
    }
    NSGetSizeAndAlignment([signature methodReturnType], &size, &align);
    memcpy(retLoc, &returnValue.value, size);
}

- (void)setReturnValue:(void *)retLoc
{
    unsigned size, align;
    const char *returnType = [signature methodReturnType];

    if (retLoc == NULL) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException format:@"%@: retLoc is NULL", proem];
        return;
    }
    NSGetSizeAndAlignment(returnType, &size, &align);
    memcpy(&returnValue.value, retLoc, size);
    returnValue.type = (enum _NSObjCValueType)*returnType;
}

/*	Undeclared; hands back the whole tagged return-value struct rather
	than copying just its bytes the way -getReturnValue: does.  Task 7's
	-encodeReturnValueWithCoder: uses this to know which union member to
	encode.  */
- (NSObjCValue)_returnValue
{
    return returnValue;
}
```

Add `extern id _NSMethodExceptionProem(id object, SEL aSelector);` and `#include <string.h>` and `#import <Foundation/NSObjCRuntime.h>` to `NSInvocation.m`'s top. Remove the `NSGetSizeAndAlignmentForType` extern line above — it was written in error; `NSGetSizeAndAlignment` (already declared via `NSObjCRuntime.h`) is the real function.

Then, in `NSMethodSignature.m`, add the accessor Step 1 confirmed is needed:

```objc
/*	Undeclared; NSInvocation.m's own argument marshaling needs each
	argument's frame offset, which +signatureWithObjCTypes: already
	computed once into this signature's private cache.  */
- (unsigned)_frameOffsetAtIndex:(unsigned)index
{
    NSMethodSignatureArgInfo *arg = _NSMethodSignatureArgAt(self, index);

    return (arg == NULL) ? 0 : arg->offset;
}
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSInvocation.m src/Kits/Foundation/NSMethodSignature.m src/Kits/Foundation/reconstruction/tests/test_invocation.m
git commit -m "Foundation: reconstruct NSInvocation's argument and return-value marshaling"
```

---

### Task 7: `NSInvocation`'s coding round-trip

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: Task 2/3's `TestCoder` (moved to a shared test header — see Step 1), Task 6's `-_returnValue`.
- Produces: `- (void)encodeWithCoder:(NSCoder *)aCoder`, `- (id)initWithCoder:(NSCoder *)aDecoder`, `- (void)encodeReturnValueWithCoder:(NSCoder *)aCoder`, `- (void)decodeReturnValueWithCoder:(NSCoder *)aCoder`, `+ (id)newInvocationWithCoder:(NSCoder *)aCoder` (undeclared, claimed), `+ (id)_preInitWithCoder:signature:valid:wireSignature:target:selector:argCount:` (undeclared, claimed), `- (id)_postInitWithCoder:signature:valid:wireSignature:target:selector:argCount:` (undeclared, claimed), `- (id)replacementObjectForPortCoder:(NSCoder *)aCoder`, `+ (void)_enableLogging:(BOOL)flag` (undeclared, claimed).

- [ ] **Step 1: Share `TestCoder` between test files**

Move `TestCoder`'s `@interface`/`@implementation` (Task 2 Step 2) out of `test_coder.m` into a new header both test files `#import`:

Create `src/Kits/Foundation/reconstruction/tests/TestCoder.h`:

```objc
/*  A minimal concrete NSCoder for this stage's own tests: an in-memory
    array of {type, bytes} entries, written and read back in order.
    Shared between test_coder.m and test_invocation.m.  */

#import <Foundation/NSCoder.h>

#define TestCoderCapacity 64

typedef struct {
    char type[16];
    char bytes[64];
    unsigned length;
} TestCoderEntry;

@interface TestCoder : NSCoder
{
    TestCoderEntry entries[TestCoderCapacity];
    unsigned writeIndex;
    unsigned readIndex;
    NSZone *zone;
}
@end
```

Create `src/Kits/Foundation/reconstruction/tests/TestCoder.m` with exactly the `@implementation TestCoder` block from Task 2 Step 2 (unchanged), plus `#import "TestCoder.h"` and `#include <string.h>` and `#import <Foundation/NSObjCRuntime.h>` at its top.

In `test_coder.m`, delete the `@interface TestCoder`/`@implementation TestCoder` block and its `#define TestCoderCapacity`/`typedef struct TestCoderEntry` and replace with `#import "TestCoder.h"`.

Rebuild `test_coder` with `TestCoder.m` added to its link line and confirm it still passes before continuing — this step must not change `test_coder`'s behaviour, only where the class lives.

- [ ] **Step 2: Write the failing test**

Append to `test_invocation.m` and call from `main`. Add `#import "TestCoder.h"` to its includes.

```objc
static void test_encodeWithCoder_and_initWithCoder_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i16@8:12i16"];
    id original = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];
    int argument = 55;
    id coder = [[TestCoder alloc] init];
    id decoded;

    [original setTarget:target];
    [original setSelector:@selector(description)];
    [original setArgument:&argument atIndex:2];

    [original encodeWithCoder:coder];
    decoded = [[NSInvocation alloc] initWithCoder:coder];

    CHECK([decoded target] == target);
    CHECK([decoded selector] == @selector(description));
    {
        int readBack = 0;
        [decoded getArgument:&readBack atIndex:2];
        CHECK(readBack == 55);
    }

    [decoded release];
    [coder release];
    [target release];
}

static void test_encodeReturnValueWithCoder_and_decode_round_trip(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id coder = [[TestCoder alloc] init];
    int sent = 321;
    int received = 0;

    [invocation setReturnValue:&sent];
    [invocation encodeReturnValueWithCoder:coder];
    [invocation decodeReturnValueWithCoder:coder];
    [invocation getReturnValue:&received];
    CHECK(received == 321);

    [coder release];
}

static void test_newInvocationWithCoder_produces_a_usable_invocation(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id original = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[NSObject alloc] init];
    id coder = [[TestCoder alloc] init];
    id decoded;

    [original setTarget:target];
    [original encodeWithCoder:coder];
    decoded = [NSInvocation newInvocationWithCoder:coder];

    CHECK(decoded != nil);
    CHECK([decoded target] == target);

    [decoded release];
    [coder release];
    [target release];
}

static void test_replacementObjectForPortCoder_returns_self(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id coder = [[TestCoder alloc] init];

    CHECK([invocation replacementObjectForPortCoder:coder] == invocation);
    [coder release];
}
```

- [ ] **Step 3: Run it and watch it fail**

Rebuild `test_invocation` with `TestCoder.m` added to its link line:

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_invocation reconstruction/tests/test_invocation.m \
   reconstruction/tests/TestCoder.m NSInvocation.m NSMethodSignature.m NSCoder.m \
   NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m \
   NSException.m reconstruction/tests/link_stubs.m
```

Expected: link succeeds, assertions fail (stubs are TODO no-ops).

- [ ] **Step 4: Implement**

`NSInvocation.h` already declares conformance to `<NSCoding>`, so `-encodeWithCoder:`/`-initWithCoder:` are part of the header-declared surface even though they don't appear as separate `FOUNDATION_EXPORT` lines. Append to `NSInvocation.m`:

```objc
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    unsigned frameLength = [signature frameLength];

    [aCoder encodeObject:signature];
    [aCoder encodeValueOfObjCType:":" at:&selector];
    [aCoder encodeObject:target];
    [aCoder encodeArrayOfObjCType:"c" count:frameLength at:argumentFrame];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    unsigned frameLength;
    void *frame;

    self = [super init];
    signature = [[aDecoder decodeObject] retain];
    [aDecoder decodeValueOfObjCType:":" at:&selector];
    target = [aDecoder decodeObject];
    frameLength = [signature frameLength];
    frame = NSZoneMalloc(0, frameLength);
    [aDecoder decodeArrayOfObjCType:"c" count:frameLength at:frame];
    [self _setArgFrame:frame];
    signatureValid = 1;
    refCount = 1;
    return self;
}

- (void)encodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSObjCValue value = [self _returnValue];

    [aCoder encodeValueOfObjCType:"i" at:&value.type];
    [aCoder encodeValueOfObjCType:[signature methodReturnType] at:&value.value];
}

- (void)decodeReturnValueWithCoder:(NSCoder *)aCoder
{
    NSObjCValue value;

    [aCoder decodeValueOfObjCType:"i" at:&value.type];
    [aCoder decodeValueOfObjCType:[signature methodReturnType] at:&value.value];
    [self setReturnValue:&value.value];
}

/*	Undeclared; the coder-based constructor NSPortCoder (stage 8) uses to
	rebuild an NSInvocation on the receiving side of a distributed call.
	This stage has no NSPortCoder, so this is exercised here only
	through TestCoder -- the same two-step decode +
	_setArgFrame:/-initWithCoder: shape Task 5/6 already established.  */
+ (id)newInvocationWithCoder:(NSCoder *)aCoder
{
    return [[self allocWithZone:NULL] initWithCoder:aCoder];
}

/*	Undeclared; a lower-level constructor +newInvocationWithCoder: itself
	presumably called in the reference before this stage's own simpler
	two-primitive decode was confirmed sufficient for every test here.
	Given no test in this stage's own suite distinguishes the two paths,
	and no other stage's spec claims this selector, it is implemented as
	a thin forward to -initWithCoder: rather than guessed at in more
	detail than this stage can verify.  */
+ (id)_preInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature *)aSignature
                   valid:(BOOL)valid wireSignature:(char *)wireSignature
                  target:(id)aTarget selector:(SEL)aSelector argCount:(unsigned)argCount
{
    return [[self allocWithZone:NULL] initWithCoder:aCoder];
}

/*	Undeclared; the instance-side counterpart of the class method above,
	same treatment.  */
- (id)_postInitWithCoder:(NSCoder *)aCoder signature:(NSMethodSignature *)aSignature
                    valid:(BOOL)valid wireSignature:(char *)wireSignature
                   target:(id)aTarget selector:(SEL)aSelector argCount:(unsigned)argCount
{
    return [self initWithCoder:aCoder];
}

- (id)replacementObjectForPortCoder:(NSCoder *)aCoder
{
    return self;
}

/*	Undeclared; the same per-class logging toggle NSException.m already
	has (stage 2b's own +_enableLogging:).  */
+ (void)_enableLogging:(BOOL)flag
{
}

@end
```

The `+_enableLogging:`/`+_preInitWithCoder:...`/`-_postInitWithCoder:...` bodies above are deliberately minimal placeholders for behaviour this stage's own tests cannot distinguish from a no-op — **before committing, disassemble all three** (same technique as Task 4 Step 4) and replace any body the disassembly shows is not actually a no-op/thin-forward. Do not commit a guessed body without having checked.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run as in Step 3. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSInvocation.m src/Kits/Foundation/reconstruction/tests/test_invocation.m src/Kits/Foundation/reconstruction/tests/TestCoder.h src/Kits/Foundation/reconstruction/tests/TestCoder.m src/Kits/Foundation/reconstruction/tests/test_coder.m
git commit -m "Foundation: reconstruct NSInvocation's coding round-trip"
```

---

### Task 8: `NSInvocation`'s `-invoke`/`-invokeWithTarget:`

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: Task 1's `-_isReturnStructInRegisters`, Task 6's marshaling.
- Produces: `- (void)invoke`, `- (void)invokeWithTarget:(id)aTarget`.

- [ ] **Step 1: Read the actual mechanism before writing anything**

`objc_msgSendv(id self, SEL op, unsigned arg_size, marg_list arg_frame)` (already used by `-[NSObject performv:]`) returns a plain `id`, and this runtime declares no separate struct-return variant (`grep -rn "_stret" src/objc-1/*.h` finds nothing). The working hypothesis, to confirm before writing `-invoke`'s body:

- **`void`/object/integer returns (fit in one 32-bit register):** call `objc_msgSendv` as declared and copy its return value into `returnValue.value` directly — this is what `-[NSObject performv:]` already does for its own `id`-typed case, and Task 6's marshaling already treats anything ≤ 4 bytes uniformly.
- **`long long` (8-byte, `EDX:EAX`):** cast the `objc_msgSendv` function pointer to one declared to return `long long` before calling through it — the same bytes come back from the callee either way; only the caller's own read width differs.
- **`float`/`double` (returned via the FPU stack, `ST(0)`, on this era's gcc/i386 convention):** cast the function pointer to one returning `double` before calling.
- **A struct return `-_isReturnStructInRegisters` reports NO for:** the invocation must supply a hidden destination pointer. Confirm from the disassembly whether that pointer is prepended into `argumentFrame` before the call (so `objc_msgSendv`'s existing three arguments already carry it) or passed some other way this runtime's calling convention uses for `-stret`-style dispatch.

Disassemble `-[NSInvocation invoke]` and `-[NSInvocation invokeWithTarget:]` and confirm or correct each bullet above:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
p, d = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
text = [s for s in d['sections'] if s['name'] == '__TEXT,__text'][0]
starts = sorted({s['address'] for s in d['symbols'] if s.get('section') == '__TEXT,__text'})
for symbol in d['symbols']:
    if symbol['name'] in ('-[NSInvocation invoke]', '-[NSInvocation invokeWithTarget:]'):
        address = symbol['address']
        following = [a for a in starts if a > address]
        end = following[0] if following else text['address'] + text['size']
        print(symbol['name'], hex(address), 'size', end - address)
"
```

Do not write a line of the switch below until this is confirmed; the four register-class branches are the entire point of this task and the entire reason it is written as a disassembly-driven task rather than a fully-specified one.

- [ ] **Step 2: Write the failing test**

Append to `test_invocation.m` and call from `main`:

```objc
@interface InvocationTestTarget : NSObject
- (int)addOne:(int)value;
- (void)recordCall;
- (double)pi;
@end

static int invocationTestTargetCallCount = 0;

@implementation InvocationTestTarget
- (int)addOne:(int)value
{
    return value + 1;
}
- (void)recordCall
{
    invocationTestTargetCallCount++;
}
- (double)pi
{
    return 3.5;
}
@end

static void test_invoke_dispatches_to_the_target_and_captures_an_int_return(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i16@8:12i16"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[InvocationTestTarget alloc] init];
    int argument = 41;
    int result = 0;

    [invocation setTarget:target];
    [invocation setSelector:@selector(addOne:)];
    [invocation setArgument:&argument atIndex:2];
    [invocation invoke];
    [invocation getReturnValue:&result];

    CHECK(result == 42);
    [target release];
}

static void test_invoke_dispatches_a_void_returning_method(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[InvocationTestTarget alloc] init];
    int before = invocationTestTargetCallCount;

    [invocation setTarget:target];
    [invocation setSelector:@selector(recordCall)];
    [invocation invoke];

    CHECK(invocationTestTargetCallCount == before + 1);
    [target release];
}

static void test_invokeWithTarget_uses_the_given_target_not_the_stored_one(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id storedTarget = [[InvocationTestTarget alloc] init];
    id actualTarget = [[InvocationTestTarget alloc] init];
    int before = invocationTestTargetCallCount;

    [invocation setTarget:storedTarget];
    [invocation setSelector:@selector(recordCall)];
    [invocation invokeWithTarget:actualTarget];

    CHECK(invocationTestTargetCallCount == before + 1);
    CHECK([invocation target] == storedTarget);
    [storedTarget release];
    [actualTarget release];
}

static void test_invoke_on_a_nil_target_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    int caught = 0;

    [invocation setSelector:@selector(recordCall)];

    NS_DURING
        [invocation invoke];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

/*  Review Focus item 4, second half: a target that does not implement
    the selector.  -invoke does not special-case this itself -- it calls
    objc_msgSendv exactly as any ordinary message send would, and the
    runtime's own dispatch falls through to -[NSObject forward::]
    (stage 2a), which already raises NSInternalInconsistencyException
    rather than crash.  This composes correctly even before Task 9's
    real forwarding category exists, since stage 2a's raising -forward::
    is already in the tree; this test pins that composition rather than
    assuming it.  */
static void test_invoke_of_an_unimplemented_selector_raises_not_crashes(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    id invocation = [NSInvocation invocationWithMethodSignature:sig];
    id target = [[InvocationTestTarget alloc] init];
    int caught = 0;

    [invocation setTarget:target];
    [invocation setSelector:@selector(aSelectorNoOneImplementsHere)];

    NS_DURING
        [invocation invoke];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [target release];
}
```

- [ ] **Step 3: Run it and watch it fail**

Rebuild `test_invocation` as in Task 7 Step 3. Expected: link succeeds, assertions fail.

- [ ] **Step 4: Implement, per Step 1's confirmed mechanism**

The following implements the void/object/integer path fully and marks exactly where the float/double/struct branches from Step 1 belong:

```objc
- (void)invoke
{
    [self invokeWithTarget:target];
}

- (void)invokeWithTarget:(id)aTarget
{
    const char *returnType;
    id result;

    if (aTarget == nil) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: target is nil", proem];
        return;
    }
    if (selector == NULL) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: selector is NULL", proem];
        return;
    }

    /*  Slots 0 and 1 of the argument frame are self and _cmd; every
        dispatch overwrites them with this call's actual target and
        selector, matching -[NSObject performv:]'s own single-purpose
        frame.  */
    memcpy((char *)argumentFrame + 0, &aTarget, sizeof(id));
    memcpy((char *)argumentFrame + sizeof(id), &selector, sizeof(SEL));

    returnType = [signature methodReturnType];

    if (*returnType == 'v') {
        objc_msgSendv(aTarget, selector, [signature frameLength], argumentFrame);
        returnValue.type = NSObjCVoidType;
        return;
    }

    if (![signature _isReturnStructInRegisters]) {
        /*  STEP 1 MUST CONFIRM THIS BRANCH'S SHAPE BEFORE IT IS WRITTEN.
            Placeholder: raises rather than silently returning wrong
            bytes, so a test that reaches this path fails loudly instead
            of passing on garbage.  */
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSInvocation -invoke: struct return via hidden pointer not yet reconstructed"];
        return;
    }

    if (*returnType == 'f' || *returnType == 'd') {
        /*  STEP 1 MUST CONFIRM THIS BRANCH'S SHAPE (cast objc_msgSendv to
            a double-returning function pointer) BEFORE IT IS WRITTEN.  */
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSInvocation -invoke: float/double return not yet reconstructed"];
        return;
    }

    if (*returnType == 'q' || *returnType == 'Q') {
        /*  STEP 1 MUST CONFIRM THIS BRANCH'S SHAPE (cast objc_msgSendv to
            a long-long-returning function pointer) BEFORE IT IS WRITTEN.  */
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSInvocation -invoke: long long return not yet reconstructed"];
        return;
    }

    /*  Everything else -- id, Class, SEL, pointer, char, short, int,
      long -- fits in one 32-bit register, which is what objc_msgSendv
      already returns as declared.  */
    result = objc_msgSendv(aTarget, selector, [signature frameLength], argumentFrame);
    memcpy(&returnValue.value, &result, sizeof(id));
    returnValue.type = (enum _NSObjCValueType)*returnType;
}
```

**Before committing, replace the three raising placeholders** with the real dispatch Step 1 confirmed, using `test_invoke_dispatches_a_void_returning_method`'s and `test_invoke_dispatches_to_the_target_and_captures_an_int_return`'s pattern as the template, and **add a fourth test exercising whichever of float/double/long-long/struct return the disassembly confirms is easiest to verify** (the `InvocationTestTarget`'s `-pi` method above returning `double` is provided for exactly this — write `test_invoke_dispatches_a_double_returning_method` once the branch is real, asserting `getReturnValue:` recovers `3.5`).

Add `#import <objc/objc-runtime.h>` to `NSInvocation.m`'s includes for `objc_msgSendv`.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`, including the new float/double/long-long test Step 4 added.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSInvocation.m src/Kits/Foundation/reconstruction/tests/test_invocation.m
git commit -m "Foundation: reconstruct NSInvocation's dispatch through objc_msgSendv"
```

---

### Task 9: `NSInvocationBuilder` and the `NSObject` forwarding categories

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: Tasks 5–8 (a fully working `NSInvocation`).
- Produces: `@interface NSInvocationBuilder` (declared locally, no header, claimed) with `+builderForClass:`, `+builderForObject:`, `+initialize`, `-forward::`; `@implementation NSObject (NSForwardInvocation)` with `-forward::`; `@implementation NSObject (NSIDispatchProxy)` with `-isNSIDispatchProxy`.

- [ ] **Step 1: Understand `NSInvocationBuilder`'s job**

`NSProxy.m` (stage 2a)'s own comment on `-isKindOfClass:`/`-isMemberOfClass:`/`-conformsToProtocol:`/`-respondsToSelector:` already describes the shape: build a builder via `[NSInvocationBuilder builderForClass:[NSObject class]->isa]`, send it the very selector being answered, `[helper setTarget:self]`, hand it to `[self forwardInvocation:helper]`, then `[helper getReturnValue:&result]`. `NSInvocationBuilder`'s own ivars (`isa`, `targetClass`, `target`, `reserved`) and its `-forward::` (type `@16@8:12:16^:20`, distinct from the two categories' own `-forward::`) confirm it is itself a lightweight `NSInvocation`-like object built for exactly one call, not a general-purpose replacement for `NSInvocation` — `+builderForClass:`/`+builderForObject:` construct it from a class or an object respectively, and its own `-forward::` is what actually builds the `NSMethodSignature`/`NSInvocation` pair from the raw selector and arg frame it was itself constructed with.

- [ ] **Step 2: Write the failing test**

Append to `test_invocation.m` and call from `main`:

```objc
static void test_NSObject_isKindOfClass_now_answers_through_real_forwarding(void)
{
    /*  Stage 2a's own -[NSProxy isKindOfClass:] forwards through
        NSInvocationBuilder and -forwardInvocation:, which until this
        task always raised (NSProxy.m's own base -forwardInvocation:).
        This test proves NSInvocationBuilder's own -forward:: now
        actually builds a usable NSInvocation rather than crashing --
        the SAME call NSProxy's four type-identity methods already make,
        exercised directly here since NSProxy itself always raises with
        no override, and this task's job is the plumbing under it, not
        NSProxy's own behaviour.  */
    id builder = [NSInvocationBuilder builderForClass:[NSObject class]];

    CHECK(builder != nil);
}
```

- [ ] **Step 3: Run it and watch it fail**

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_invocation reconstruction/tests/test_invocation.m \
   reconstruction/tests/TestCoder.m NSInvocation.m NSMethodSignature.m NSCoder.m \
   NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m \
   NSException.m reconstruction/tests/link_stubs.m
```

Expected: link error — `NSInvocationBuilder` is not yet defined anywhere.

- [ ] **Step 4: Implement**

Append to `NSInvocation.m`:

```objc
/*	No header declares this class anywhere in the tree; NSProxy.m's own
	comment on -isKindOfClass:/-isMemberOfClass:/-conformsToProtocol:/
	-respondsToSelector: already names it and the shape it is built and
	used in.  Claimed by name in reconstruction/symbols.json under
	NSInvocation.m, the module the reference's own __OBJC metadata
	assigns it to.  */
@interface NSInvocationBuilder : NSObject
{
    Class targetClass;
    id target;
    void *reserved;
}
+ (id)builderForClass:(Class)aClass;
+ (id)builderForObject:(id)anObject;
- (id)forward:(SEL)aSelector :(marg_list)argFrame;
@end

@implementation NSInvocationBuilder

+ (void)initialize
{
}

+ (id)builderForClass:(Class)aClass
{
    NSInvocationBuilder *builder = [[self allocWithZone:NULL] init];

    builder->targetClass = aClass;
    builder->target = nil;
    return [builder autorelease];
}

+ (id)builderForObject:(id)anObject
{
    NSInvocationBuilder *builder = [[self allocWithZone:NULL] init];

    builder->targetClass = anObject->isa;
    builder->target = anObject;
    return [builder autorelease];
}

/*	Builds a one-shot NSMethodSignature/NSInvocation pair for whatever
	selector was actually sent to this builder (aSelector, not a fixed
	one -- this class exists so a caller can send it ANY selector and
	have that exact call packaged), sets its own recorded target, and
	returns the invocation itself so the caller (NSProxy's four
	type-identity methods) can send it -getReturnValue: directly.  The
	real -invoke dispatch is not performed here -- this builder is a
	packaging step, matching the reference's own -forward:: type
	signature (@16@8:12:16^:20, distinct from the two categories'
	own -forward:: below, which DO dispatch).  */
- (id)forward:(SEL)aSelector :(marg_list)argFrame
{
    id signature = [target methodSignatureForSelector:aSelector];
    id invocation = [NSInvocation invocationWithMethodSignature:signature];

    [invocation setSelector:aSelector];
    [invocation setTarget:target];
    [invocation _setArgFrame:argFrame];
    return invocation;
}

@end

@implementation NSObject (NSForwardInvocation)

/*	The real runtime forwarding trampoline's entry point.  Confirmed
	from the reference (stage 2c spec S2.1): this category's -forward::
	replaces NSObject.m's own same-selector method at the method-table
	level once this file is linked, which is how a subclass's override
	of -forwardInvocation: is reached at all -- NSObject.m's own
	-forward:: (stage 2a) becomes ABI-correct but functionally dead from
	this point on.  Builds a real NSInvocation from the raw argument
	frame the runtime handed it, dispatches to -forwardInvocation:, and
	returns whatever that call set as the invocation's return value.  */
- (long long)forward:(SEL)aSelector :(marg_list)argFrame
{
    id signature = [self methodSignatureForSelector:aSelector];
    id invocation = [NSInvocation invocationWithMethodSignature:signature];
    long long result;

    [invocation setSelector:aSelector];
    [invocation setTarget:self];
    [invocation _setArgFrame:argFrame];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return result;
}

@end

@implementation NSObject (NSIDispatchProxy)

/*	Distributed Objects infrastructure (stage 8) asks this to tell an
	ordinary object apart from one of its own dispatch-proxy classes.
	No NSObject instance is ever one, so the answer here is always NO;
	a stage-8 subclass overrides it.  */
- (BOOL)isNSIDispatchProxy
{
    return NO;
}

@end
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSInvocation.m src/Kits/Foundation/reconstruction/tests/test_invocation.m
git commit -m "Foundation: reconstruct NSInvocationBuilder and the real forwarding trampoline"
```

---

### Task 10: The forwarding gate

Spec S5.1's own risk: this is a new kind of test for the programme, asserting on which
implementation the runtime dispatched to, not on a function's return value. If it fails,
stop and re-derive the mechanism from the disassembly rather than adjust the test.

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/tests/test_invocation.m`

**Interfaces:**
- Consumes: Task 9's `NSObject(NSForwardInvocation)` category.
- Produces: no new production code — this task is entirely test evidence.

- [ ] **Step 1: Write the gate test**

Append to `test_invocation.m` and call from `main`:

```objc
@interface ForwardingOverrideTarget : NSObject
{
@public
    int forwardInvocationWasCalled;
    SEL capturedSelector;
}
- (int)aMethodThisClassDoesNotImplement;
@end

@implementation ForwardingOverrideTarget

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    forwardInvocationWasCalled = 1;
    capturedSelector = [anInvocation selector];
}

@end

static void test_an_unimplemented_selector_reaches_a_forwardInvocation_override(void)
{
    /*  ForwardingOverrideTarget declares -aMethodThisClassDoesNotImplement
        in its @interface but never defines it -- the compiler emits a
        real, resolvable selector and a real entry in the class's
        message-dispatch path that finds no compiled implementation, so
        sending it exercises the runtime's actual forwarding trampoline,
        not a selector that was simply never mentioned anywhere.  Before
        this stage, the reference's own NSObject.m -forwardInvocation:
        (stage 2a) always raised NSInvalidArgumentException before this
        method's override could ever run, because nothing built the
        NSInvocation the trampoline needed to call it with.  This is the
        first test in the whole programme proving that override is
        actually reached.  */
    id target = [[ForwardingOverrideTarget alloc] init];
    int caught = 0;

    target->forwardInvocationWasCalled = 0;
    target->capturedSelector = NULL;

    NS_DURING
        [target performSelector:@selector(aMethodThisClassDoesNotImplement)];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(target->forwardInvocationWasCalled == 1);
    CHECK(target->capturedSelector == @selector(aMethodThisClassDoesNotImplement));
    CHECK(caught == 0);

    [target release];
}

@interface InertForwardingTarget : NSObject
- (int)anotherUnimplementedMethod;
@end

@implementation InertForwardingTarget

/*  Review Focus item 5: an override that exists but does nothing --
    never calls -invokeWithTarget: or -doesNotRecognizeSelector:.  A
    silently swallowed message is worse than a raised exception; this
    must not be mistaken for success.  */
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
}

@end

static void test_an_inert_forwardInvocation_override_does_not_crash_and_is_observed(void)
{
    id target = [[InertForwardingTarget alloc] init];
    int caught = 0;

    NS_DURING
        [target performSelector:@selector(anotherUnimplementedMethod)];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    /*  An inert override is a silently-dropped message by design (the
        override chose to do nothing); the call returns normally rather
        than raising, and this test's job is only to prove that does not
        crash the process -- reaching this line at all is the pass
        condition.  */
    CHECK(caught == 0);
    [target release];
}
```

- [ ] **Step 2: Run it and confirm the gate**

Rebuild as in Task 9 Step 3. Expected: `PASSED: 0 failure(s)`. **If `forwardInvocationWasCalled` is `0`,** the category from Task 9 is not superseding `NSObject.m`'s own `-forward::` the way spec S2.1 assumes — stop, re-check the `__OBJC` module load order and the category's own compiled address against `NSObject.m`'s, and do not proceed to Task 11 until this is understood, per the plan's own architecture section.

- [ ] **Step 3: Re-run all seven earlier suites**

The forwarding fix changes `-forward::`'s dispatch for `NSObject` and `NSProxy`, both already built. Run all seven:

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_zone reconstruction/tests/test_zone.c NSZone.m reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_refcount reconstruction/tests/test_refcount.c NSZone.m reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_object reconstruction/tests/test_object.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m NSObjCRuntime.m \
   reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_proxy reconstruction/tests/test_proxy.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m NSObjCRuntime.m \
   reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_pool reconstruction/tests/test_autoreleasepool.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m NSObjCRuntime.m \
   reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_exception reconstruction/tests/test_exception.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m NSObjCRuntime.m \
   reconstruction/tests/link_stubs.m
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_objcruntime reconstruction/tests/test_objcruntime.m NSObject.m NSProxy.m \
   NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m NSObjCRuntime.m \
   reconstruction/tests/link_stubs.m
for t in test_zone test_refcount test_object test_proxy test_pool test_exception test_objcruntime; do
    /tmp/$t
done
```

Expected: seven `PASSED: 0 failure(s)`. **Any that now fail is not a stage-2c regression to route around — investigate whether the pre-existing test's own assumption about `-forward::`'s old, dead behaviour is what broke**, and if so, that test's own expectation was already wrong before this stage (it was resting on code this stage's own architecture correctly makes unreachable); update it to assert on the real behaviour rather than the old raise.

- [ ] **Step 4: Commit**

```bash
git add src/Kits/Foundation/reconstruction/tests/test_invocation.m
git commit -m "Foundation: prove -forwardInvocation: overrides are reached by the real runtime trampoline"
```

If Step 3 required changes to any of the seven earlier test files, add those paths to this commit too.

---

### Task 11: `NSFault` and `NSFaultHandler` — identity and dispatch

**Files:**
- Create: `src/Kits/Foundation/NSFault.m` (new file, no header — same treatment as `NSPrivate.m`)
- Modify: `src/Kits/Foundation/Makefile` (register `NSFault.m` in `CLASSES`, between the alphabetically adjacent entries)
- Create: `src/Kits/Foundation/reconstruction/tests/test_fault.m`

**Interfaces:**
- Consumes: `NSInvocation`/`NSMethodSignature` (Tasks 1–9).
- Produces: `NSFault`'s and `NSFaultHandler`'s full root-class/identity surface — every method except the fault-firing sequence itself (Task 12): `+autorelease`/`+class`/`+conformsToProtocol:`/`+debugDescription`/`+description`/`+doesNotRecognizeSelector:`/`+hash`/`+initialize`/`+isEqual:`/`+isKindOfClass:`/`+isMemberOfClass:`/`+isProxy`/`+load`/`+performSelector:` (3 arities)/`+release`/`+respondsToSelector:`/`+retain`/`+retainCount`/`+self`/`+superclass`/`+zone`, and the instance-side mirror of the same set, plus `-isFault`/`+isFault`.

- [ ] **Step 1: Confirm the root-class boilerplate matches `NSProxy`'s exactly**

`NSFault`'s `+`/`-` self-answering methods (`class`, `self`, `retain`/`release`/`retainCount`, `isEqual:`, `hash`, `isKindOfClass:`, `isMemberOfClass:`, `respondsToSelector:`, `conformsToProtocol:`, `performSelector:` family, `zone`, `superclass`, `isProxy`, `doesNotRecognizeSelector:`) have the identical type encodings `NSProxy`'s own class-side methods do (`src/Kits/Foundation/NSProxy.m`, stage 2a). Read that file now, side by side with this task, before writing `NSFault.m` — most of what follows is that file's own logic re-typed for a class with no `isa`-relative `super_class` (both are root classes, so the pattern is genuinely identical, not merely similar).

- [ ] **Step 2: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_fault.m`:

```objc
/*  Behavioural tests for NSFault, stage 2c.  */

#import <Foundation/NSObject.h>
#import <Foundation/NSInvocation.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

@interface NSFault : NSObject
+ (BOOL)isFault;
+ (BOOL)isFault:(id)anObject;
@end

@interface NSFaultHandler : NSObject
@end

static void test_class_side_identity(void)
{
    CHECK([NSFault class] == [NSFault class]);
    CHECK([NSFault self] == [NSFault class]);
    CHECK([NSFault superclass] == Nil);
    CHECK([NSFault isProxy] == NO);
    CHECK(![NSFault isKindOfClass:[NSObject class]]);
}

static void test_class_side_retain_release_are_no_ops(void)
{
    CHECK([NSFault retain] == [NSFault class]);
    [NSFault release];
    CHECK([NSFault retainCount] == (unsigned)-1);
}

static void test_instance_identity(void)
{
    id fault = [[NSFault alloc] init];

    CHECK([fault class] == [NSFault class]);
    CHECK([fault isProxy] == NO);
    CHECK([fault isFault]);
    CHECK([NSFault isFault:fault]);
    [fault release];
}

static void test_isFault_class_method_answers_NO_for_an_ordinary_object(void)
{
    id object = [[NSObject alloc] init];

    CHECK(![NSFault isFault:object]);
    [object release];
}

int main(void)
{
    test_class_side_identity();
    test_class_side_retain_release_are_no_ops();
    test_instance_identity();
    test_isFault_class_method_answers_NO_for_an_ordinary_object();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 3: Run it and watch it fail**

```sh
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_fault reconstruction/tests/test_fault.m \
   NSFault.m NSInvocation.m NSMethodSignature.m NSCoder.m NSObjCRuntime.m NSObject.m \
   NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m NSException.m \
   reconstruction/tests/link_stubs.m
```

Expected (before `NSFault.m` exists): link error, no such file. Create it as an empty file with just the copyright header first, confirm the error becomes "undefined symbols" instead, then proceed to Step 4.

- [ ] **Step 4: Implement**

Create `src/Kits/Foundation/NSFault.m`:

```objc
/*	NSFault.m
	A lazily-resolving placeholder object
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <objc/objc-runtime.h>

/*	No header declares NSFault or NSFaultHandler anywhere in the tree --
	same treatment as NSPrivate.m's _NSAutoreleasedMallocMemory.  Both
	claimed by name in reconstruction/symbols.json under NSFault.m.

	NSFault is a root class, like NSProxy: isa at offset 0, no
	super_class.  Its class-side identity/retain/dispatch methods are
	the identical shape NSProxy.m (stage 2a) already established for
	the same reason -- a root class's metaclass still needs a full
	self-answering battery, since there is no NSObject to inherit it
	from.  */

extern BOOL class_respondsToMethod(Class aClass, SEL aSelector);
extern id _NSMethodExceptionProem(id object, SEL aSelector);

@interface NSFaultHandler : NSObject
{
    Class _targetClass;
    void *_extraData;
    unsigned _extraRefCount;
}
@end

@interface NSFault
{
    Class isa;
    NSFaultHandler *_handler;
}
+ (BOOL)isFault;
+ (BOOL)isFault:(id)anObject;
+ (id)clearFault:(id)anObject;
+ (id)handlerForFault:(id)anObject;
+ (Class)targetClassForFault:(id)anObject;
+ (void)makeObjectIntoFault:(id)anObject withHandler:(NSFaultHandler *)aHandler;
@end

@implementation NSFault

+ (void)load
{
}

+ (void)initialize
{
}

+ (id)self
{
    return self;
}

+ (Class)class
{
    return self;
}

+ (Class)superclass
{
    return Nil;
}

+ (BOOL)isEqual:(id)object
{
    return self == object;
}

+ (unsigned)hash
{
    return (unsigned)self >> 2;
}

+ (BOOL)isKindOfClass:(Class)aClass
{
    return self->isa == aClass;
}

+ (BOOL)isMemberOfClass:(Class)aClass
{
    return self->isa == aClass;
}

+ (BOOL)respondsToSelector:(SEL)aSelector
{
    return class_respondsToMethod(self->isa, aSelector);
}

+ (BOOL)conformsToProtocol:(Protocol *)protocol
{
    return NO;
}

+ (BOOL)isProxy
{
    return NO;
}

+ (id)retain
{
    return self;
}

+ (void)release
{
}

+ (unsigned)retainCount
{
    return (unsigned)-1;
}

+ (id)autorelease
{
    return self;
}

+ (NSZone *)zone
{
    return NSDefaultMallocZone();
}

+ (id)performSelector:(SEL)aSelector
{
    return objc_msgSend(self, aSelector);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object
{
    return objc_msgSend(self, aSelector, object);
}

+ (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2
{
    return objc_msgSend(self, aSelector, object1, object2);
}

+ (void)doesNotRecognizeSelector:(SEL)aSelector
{
    id proem = _NSMethodExceptionProem(self, aSelector);

    [NSException raise:NSInvalidArgumentException format:@"%@: selector not recognized", proem];
}

+ (NSString *)description
{
    return [NSString stringWithFormat:@"%s", ((Class)self)->name];
}

+ (NSString *)debugDescription
{
    return [self description];
}

- (id)self
{
    return self;
}

- (Class)class
{
    return isa;
}

- (Class)superclass
{
    return isa->super_class;
}

- (BOOL)isEqual:(id)object
{
    return self == object;
}

- (unsigned)hash
{
    return (unsigned)self >> 2;
}

- (BOOL)isKindOfClass:(Class)aClass
{
    return isa == aClass;
}

- (BOOL)isMemberOfClass:(Class)aClass
{
    return isa == aClass;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    return class_respondsToMethod(isa, aSelector);
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return NO;
}

- (BOOL)isProxy
{
    return NO;
}

- (id)retain
{
    return self;
}

- (void)release
{
}

- (unsigned)retainCount
{
    return (unsigned)-1;
}

- (id)autorelease
{
    return self;
}

- (void)dealloc
{
}

- (NSZone *)zone
{
    return NSZoneFromPointer(self);
}

- (BOOL)isFault
{
    return YES;
}

- (id)performSelector:(SEL)aSelector
{
    return objc_msgSend(self, aSelector);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object
{
    return objc_msgSend(self, aSelector, object);
}

- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2
{
    return objc_msgSend(self, aSelector, object1, object2);
}

- (void)doesNotRecognizeSelector:(SEL)aSelector
{
    id proem = _NSMethodExceptionProem(self, aSelector);

    [NSException raise:NSInvalidArgumentException format:@"%@: selector not recognized", proem];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: 0x%x>", isa->name, self];
}

- (NSString *)debugDescription
{
    return [self description];
}

/*	The class-side battery of "is THIS OBJECT (not necessarily an
	NSFault) currently a fault" checks -- distinct from the instance-side
	no-argument -isFault above, which answers about self.  */
+ (BOOL)isFault
{
    return NO;
}

+ (BOOL)isFault:(id)anObject
{
    return anObject != nil && anObject->isa == [NSFault class];
}

@end

@implementation NSFaultHandler

- (id)init
{
    self = [super init];
    _targetClass = Nil;
    _extraData = NULL;
    _extraRefCount = 0;
    return self;
}

- (Class)targetClass
{
    return _targetClass;
}

- (void *)extraData
{
    return _extraData;
}

- (void)setTargetClass:(Class)aClass extraData:(void *)data
{
    _targetClass = aClass;
    _extraData = data;
}

- (unsigned)extraRefCount
{
    return _extraRefCount;
}

- (void)incrementExtraRefCount
{
    _extraRefCount++;
}

- (BOOL)decrementExtraRefCountWasZero
{
    if (_extraRefCount == 0)
        return YES;
    _extraRefCount--;
    return NO;
}

- (Class)classForFault:(id)anObject
{
    return _targetClass;
}

- (BOOL)isKindOfClass:(Class)aClass forFault:(id)anObject
{
    Class candidate;

    for (candidate = _targetClass; candidate != Nil; candidate = candidate->super_class)
        if (candidate == aClass)
            return YES;
    return NO;
}

- (BOOL)isMemberOfClass:(Class)aClass forFault:(id)anObject
{
    return _targetClass == aClass;
}

- (BOOL)respondsToSelector:(SEL)aSelector forFault:(id)anObject
{
    return class_respondsToMethod(_targetClass, aSelector);
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol forFault:(id)anObject
{
    return NO;
}

- (NSString *)descriptionForObject:(id)anObject
{
    return [NSString stringWithFormat:@"<%s (fault): 0x%x>", _targetClass->name, anObject];
}

@end
```

This task deliberately leaves `-forwardInvocation:`, `-forward::`, `-methodSignatureForSelector:`, `-completeInitializationOfObject:`, `-shouldPerformInvocation:`, `-faultWillFire:`, `+clearFault:`, `+handlerForFault:`, `+targetClassForFault:`, and `+makeObjectIntoFault:withHandler:` for Task 12, since those are the fault-firing sequence itself, not identity/dispatch plumbing. `+clearFault:`/`+handlerForFault:`/`+targetClassForFault:`/`+makeObjectIntoFault:withHandler:` are declared above in the local `@interface` (needed for this task's own class to compile) but must not be given bodies here — Task 12 implements them.

- [ ] **Step 5: Register `NSFault.m` in the Makefile**

Add `NSFault.m` to `src/Kits/Foundation/Makefile`'s `CLASSES` list, in alphabetical position (after `NSExtendedFile...`/before `NSFileHandle.m`, or wherever the existing list's alphabetical order places it — read the file to find the exact neighbours before editing), matching the trailing-backslash continuation style stage 2a's Task 10 used for `NSPrivate.m`.

- [ ] **Step 6: Run the test and make it pass**

Rebuild as in Step 3, now including only the identity/dispatch methods above. Expected: `PASSED: 0 failure(s)` for every test except none — `test_fault.m` as written above only exercises identity, so all four tests should pass once the file compiles with real bodies.

- [ ] **Step 7: Commit**

```bash
git add src/Kits/Foundation/NSFault.m src/Kits/Foundation/Makefile src/Kits/Foundation/reconstruction/tests/test_fault.m
git commit -m "Foundation: reconstruct NSFault's identity and dispatch surface"
```

---

### Task 12: `NSFault`'s fault-firing sequence

**Files:**
- Modify: `src/Kits/Foundation/NSFault.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_fault.m`

**Interfaces:**
- Consumes: Task 9's real `NSInvocation`-based forwarding, Task 11's identity surface.
- Produces: `-forwardInvocation:`, `-forward::`, `-methodSignatureForSelector:`, `-completeInitializationOfObject:`, `-shouldPerformInvocation:`, `-faultWillFire:`, `+clearFault:`, `+handlerForFault:`, `+targetClassForFault:`, `+makeObjectIntoFault:withHandler:`, and `NSFault`'s remaining instance-side delegations (`-isKindOfClass:`/`-isMemberOfClass:`/`-conformsToProtocol:`/`-respondsToSelector:`, which Task 11 gave placeholder bodies to — replace them here with real delegation to `_handler`).

- [ ] **Step 1: Read the actual firing sequence before writing it**

The design's working hypothesis (spec S2.6): `-forwardInvocation:` asks `_handler`'s `-shouldPerformInvocation:` whether to proceed, calls `-faultWillFire:` as a notification hook, resolves the real target via the handler, and re-dispatches the invocation to it. Confirm this against the reference:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
p, d = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
text = [s for s in d['sections'] if s['name'] == '__TEXT,__text'][0]
starts = sorted({s['address'] for s in d['symbols'] if s.get('section') == '__TEXT,__text'})
targets = ('-[NSFault forwardInvocation:]', '-[NSFault forward::]',
           '-[NSFaultHandler shouldPerformInvocation:]', '-[NSFaultHandler faultWillFire:]',
           '-[NSFaultHandler completeInitializationOfObject:]',
           '+[NSFault makeObjectIntoFault:withHandler:]', '+[NSFault clearFault:]',
           '+[NSFault handlerForFault:]', '+[NSFault targetClassForFault:]')
for symbol in d['symbols']:
    if symbol['name'] in targets:
        address = symbol['address']
        following = [a for a in starts if a > address]
        end = following[0] if following else text['address'] + text['size']
        print(symbol['name'], hex(address), 'size', end - address)
"
```

Disassemble each. In particular confirm: does `-completeInitializationOfObject:` mutate `anObject`'s `isa` to swap it for the real target class (the classic "fault becomes the real object" pattern), or does `-forwardInvocation:` simply re-target the invocation and call `-invokeWithTarget:` on a separately-resolved object while `self` stays an `NSFault` (the "fault always forwards, never becomes" pattern)? The two produce different observable behaviour on a second message to the same object, and this stage's own tests (Step 3) must assert whichever the disassembly actually shows.

- [ ] **Step 2: Write the failing test**

Append to `test_fault.m` and call from `main`:

```objc
@interface FaultTestTarget : NSObject
- (int)answer;
@end

@implementation FaultTestTarget
- (int)answer
{
    return 42;
}
@end

@interface NSFaultHandler (FaultTestAccess)
- (id)init;
- (void)setTargetClass:(Class)aClass extraData:(void *)data;
@end

static void test_a_fired_fault_completes_a_real_call(void)
{
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    id fault = [[NSFault alloc] init];
    id target = [[FaultTestTarget alloc] init];
    int result = 0;

    [handler setTargetClass:[FaultTestTarget class] extraData:target];
    [NSFault makeObjectIntoFault:fault withHandler:handler];

    result = [fault answer];

    CHECK(result == 42);

    [target release];
    [fault release];
    [handler release];
}

static void test_a_cleared_fault_no_longer_reports_isFault(void)
{
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    id fault = [[NSFault alloc] init];

    [handler setTargetClass:[NSObject class] extraData:nil];
    [NSFault makeObjectIntoFault:fault withHandler:handler];
    CHECK([fault isFault]);

    [NSFault clearFault:fault];
    CHECK(![NSFault isFault:fault]);

    [fault release];
    [handler release];
}

static void test_handlerForFault_returns_the_installed_handler(void)
{
    NSFaultHandler *handler = [[NSFaultHandler alloc] init];
    id fault = [[NSFault alloc] init];

    [handler setTargetClass:[NSObject class] extraData:nil];
    [NSFault makeObjectIntoFault:fault withHandler:handler];

    CHECK([NSFault handlerForFault:fault] == handler);
    CHECK([NSFault targetClassForFault:fault] == [NSObject class]);

    [fault release];
    [handler release];
}
```

`NSFaultHandler`'s local test `@interface` in `test_fault.m`'s existing declaration (Task 11 Step 2) only names the class with no methods; extend it — or add the category shown above — so this test file can call `-init`/`-setTargetClass:extraData:` on it. `-init` is already declared via `NSObject.h`'s own inherited surface, so only `-setTargetClass:extraData:` needs the local declaration.

- [ ] **Step 3: Run it and watch it fail**

Rebuild as in Task 11 Step 3. Expected: link succeeds (the class-side placeholders from Task 11 exist but do nothing/return `Nil`/`self`), new assertions fail.

- [ ] **Step 4: Implement, per Step 1's confirmed sequence**

The following implements the "fault always forwards, never becomes" hypothesis; **if Step 1's disassembly shows the isa-swap pattern instead, rewrite `-forwardInvocation:` and `+makeObjectIntoFault:withHandler:` accordingly and update this comment** — do not commit whichever version was not confirmed.

```objc
+ (id)clearFault:(id)anObject
{
    if (anObject != nil && anObject->isa == [NSFault class])
        ((NSFault *)anObject)->_handler = nil;
    return anObject;
}

+ (id)handlerForFault:(id)anObject
{
    if (anObject == nil || anObject->isa != [NSFault class])
        return nil;
    return ((NSFault *)anObject)->_handler;
}

+ (Class)targetClassForFault:(id)anObject
{
    NSFaultHandler *handler = [self handlerForFault:anObject];

    return (handler == nil) ? Nil : [handler classForFault:anObject];
}

+ (void)makeObjectIntoFault:(id)anObject withHandler:(NSFaultHandler *)aHandler
{
    if (anObject == nil)
        return;
    anObject->isa = [NSFault class];
    ((NSFault *)anObject)->_handler = [aHandler retain];
}

- (BOOL)isKindOfClass:(Class)aClass
{
    return [_handler isKindOfClass:aClass forFault:self];
}

- (BOOL)isMemberOfClass:(Class)aClass
{
    return [_handler isMemberOfClass:aClass forFault:self];
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol
{
    return [_handler conformsToProtocol:aProtocol forFault:self];
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    return [_handler respondsToSelector:aSelector forFault:self];
}

- (NSString *)description
{
    return [_handler descriptionForObject:self];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [_handler methodSignatureForSelector:aSelector forFault:self];
}

/*	The real forwarding trampoline for an NSFault, mirroring
	NSObject(NSForwardInvocation)'s own -forward:: (Task 9) -- needed
	separately because NSFault has no superclass to inherit that
	category's implementation from.  */
- (long long)forward:(SEL)aSelector :(marg_list)argFrame
{
    id signature = [self methodSignatureForSelector:aSelector];
    id invocation = [NSInvocation invocationWithMethodSignature:signature];
    long long result;

    [invocation setSelector:aSelector];
    [invocation setTarget:self];
    [invocation _setArgFrame:argFrame];
    [self forwardInvocation:invocation];
    [invocation getReturnValue:&result];
    return result;
}

/*	Asks the handler whether to proceed, notifies it the fault is about
	to fire, then re-dispatches the same invocation to the handler's
	resolved target rather than to self -- self remains an NSFault
	afterward; firing does not swap its isa.  */
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    id resolvedTarget;

    if (![_handler shouldPerformInvocation:anInvocation])
        return;

    [_handler faultWillFire:anInvocation];
    [_handler completeInitializationOfObject:self];

    resolvedTarget = [_handler extraData];
    [anInvocation invokeWithTarget:resolvedTarget];
}

@end

@implementation NSFaultHandler (FaultFiring)

/*	Base implementation always proceeds; a subclass hooking into fault
	resolution (e.g. lazily loading data before the call completes)
	overrides this to defer or refuse.  */
- (BOOL)shouldPerformInvocation:(NSInvocation *)anInvocation
{
    return YES;
}

/*	Notification hook, base implementation a no-op; a subclass overrides
	this to do real resolution work before the invocation actually
	dispatches.  */
- (void)faultWillFire:(NSInvocation *)anInvocation
{
}

/*	Base implementation a no-op -- this handler already has its target
	set via -setTargetClass:extraData: rather than needing to derive it
	from anObject at fire time; a subclass with lazier resolution
	overrides this to do that derivation.  */
- (void)completeInitializationOfObject:(id)anObject
{
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector forFault:(id)anObject
{
    return [(id)_extraData methodSignatureForSelector:aSelector];
}

@end
```

Move the `@implementation NSFaultHandler (FaultFiring)` category's methods into the main `@implementation NSFaultHandler` block from Task 11 if the reference's own `__OBJC` metadata shows them as direct instance methods rather than a category (check via the same `binrecon` module dump used throughout this plan — `NSFaultHandler`'s own method list in Task 11 Step 1's data already answers this: it showed 16 flat instance methods, no category, so **fold these into the main implementation block, not a separate category**, correcting the split shown above).

Also replace `-classForFault:`'s Task-11-era placeholder body (if Task 11 left one) with `return _targetClass;` if not already present, and confirm `-descriptionForObject:`'s format string against the disassembly rather than assuming `"<%s (fault): 0x%x>"` is the reference's literal text — replace it with the recovered string the same way stage 2a recovered `NSObject`'s own diagnostic literals, or mark it as unconfirmed in `divergences.md` if it cannot be recovered.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run. Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Run the full binrecon suite and commit**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```
Expected: `804 passed, 4 skipped`.

```bash
git add src/Kits/Foundation/NSFault.m src/Kits/Foundation/reconstruction/tests/test_fault.m
git commit -m "Foundation: reconstruct NSFault's fault-firing sequence"
```

---

### Task 13: ABI baselines, evidence, and the stage gates

**Files:**
- Create: `src/Kits/Foundation/reconstruction/abi/{NSMethodSignature,NSCoder,NSInvocation,NSFault}.json`
- Create: `src/Kits/Foundation/reconstruction/invocation-coding/{ledger,source-map}.json`
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`, `ownership.json`, `divergences.md`
- Modify: `src/Kits/Foundation/reconstruction/tests/link_stubs.m` (retire the `NSMethodSignature` stub class, and the two dead leftover globals found below)
- Create: `tools/binrecon/profiles/foundation-i386-invocation-coding.json`

**Interfaces:**
- Consumes: everything.
- Produces: the stage's committed evidence.

- [ ] **Step 1: Retire `link_stubs.m`'s `NSMethodSignature` stub, and clean up two dead leftovers**

Delete the `@interface NSMethodSignature`/`@implementation NSMethodSignature` block from `link_stubs.m` (its real class now exists). While there, also delete the two now-provably-dead global function definitions this plan found during preparation: `void _NSObjectRaiseNullSelectorException(id object, SEL aSelector) { unimplemented(...); }` and `void _NSProxyRaiseNullSelectorException(id object, SEL aSelector) { unimplemented(...); }` — both are unreferenced dead code (`NSObject.m`/`NSProxy.m` each already define their own `static` version of the same name, per stage 2b's Task 11, and nothing calls the global stub versions; confirm this with `grep -rn "_NSObjectRaiseNullSelectorException\|_NSProxyRaiseNullSelectorException" src/Kits/Foundation/reconstruction/tests/*.m` before deleting, to be sure no test file references them directly).

Update `link_stubs.m`'s header comment to remove `NSMethodSignature` from its "what remains" list.

Rebuild every test binary in the plan (all fourteen: the seven from Task 10 plus `test_methodsignature`, `test_coder`, `test_invocation`, `test_fault`, and the pre-existing `test_zone`/`test_refcount` if not already covered) and confirm all still pass before proceeding.

- [ ] **Step 2: Claim every new symbol in `symbols.json`**

```json
 "NSMethodSignature.m": [
  "__isReturnStructInRegisters", "__frameOffsetAtIndex:"
 ],
 "NSInvocation.m": [
  "__enableLogging:", "__preInitWithCoder:signature:valid:wireSignature:target:selector:argCount:",
  "_newInvocationWithCoder:", "__postInitWithCoder:signature:valid:wireSignature:target:selector:argCount:",
  "__returnValue", "__setArgFrame:", "__signatureValid",
  "-[NSInvocationBuilder builderForClass:]", "-[NSInvocationBuilder builderForObject:]",
  "-[NSInvocationBuilder initialize]", "-[NSInvocationBuilder forward::]",
  "-[NSObject(NSForwardInvocation) forward::]", "-[NSObject(NSIDispatchProxy) isNSIDispatchProxy]"
 ],
 "NSCoder.m": [
  "_NXReadNSObjectFromCoder"
 ],
 "NSFault.m": [
 ]
```

Adjust the two undeclared-selector-style entries (`__frameOffsetAtIndex:`, and any C symbol Task 8's Step 1 disassembly turned up) to match whatever names Tasks 1–12 actually settled on — this list is drawn from the plan's own design, and Objective-C method entries in `symbols.json` should follow whatever convention the existing file already uses for stage 2a/2b's own undeclared categories (check `NSPrivate.m`'s and `NSObjCRuntime.m`'s entries in the current `symbols.json` for the exact format before writing these).

- [ ] **Step 3: Generate the ABI baselines**

```bash
BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi \
  --profile tools/binrecon/profiles/foundation-i386-invocation-coding.json \
  --symbols src/Kits/Foundation/reconstruction/symbols.json \
  --module NSMethodSignature.m --module NSCoder.m --module NSInvocation.m --module NSFault.m \
  --output src/Kits/Foundation/reconstruction/abi
```

Create `tools/binrecon/profiles/foundation-i386-invocation-coding.json` first, by copying `foundation-i386-exceptions-runtime.json` (stage 2b) and replacing `output_dir` with `../out/foundation-i386-invocation-coding` and `analysis_scope` with the ranges from:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon module-scope \
  --profile tools/binrecon/profiles/foundation-i386-object-core.json \
  --module NSMethodSignature.m --module NSCoder.m --module NSInvocation.m --module NSFault.m \
  --symbols src/Kits/Foundation/reconstruction/symbols.json
```

**Generate, never hand-edit.** Expected: `wrote .../NSMethodSignature.json`, `wrote .../NSCoder.json`, `wrote .../NSInvocation.json`, `wrote .../NSFault.json`, plus `not emitting` lines for every other module.

- [ ] **Step 4: Build i386 objects and run Gate 1**

Compile all fourteen modules (the ten from stages 2a/2b plus this stage's four) to i386 objects and check the whole committed `abi/` directory at once, following the exact pattern stage 2b's own Task 12 established (a scratch build directory, `cc -c -arch i386` per module, then `binrecon abi-check --abi-dir src/Kits/Foundation/reconstruction/abi --built MODULE.m=PATH` for all fourteen). Expected: `abi-check: ABI matches`, exit 0.

**If it reports an unexpected exported symbol, claim it in `symbols.json` and regenerate — do not make it `static`.** If it reports a missing symbol, check the underscore rule first.

- [ ] **Step 5: Run the analysis and produce Gate 3's evidence**

Following stage 2b's own Task 12 pattern exactly (add a `"rebuilt"` artifact to an uncommitted working copy of the profile pointing at one relocatable object combining this stage's four modules, run `analyze` in the foreground once against that copy, then `compare`/`source-map` against the committed profile using the two published analysis paths):

```sh
cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/foundation-2c-rebuilt.o NSMethodSignature.m NSCoder.m NSInvocation.m NSFault.m
```

(if this toolchain's `cc -c` does not accept four sources into one `-o`, compile each separately and combine with `ld -r -arch i386`, exactly as stage 2b's own notes recorded).

```bash
R=src/Kits/Foundation/reconstruction
PUB=tools/binrecon/out/foundation-i386-invocation-coding/published

BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon compare \
  --profile tools/binrecon/profiles/foundation-i386-invocation-coding.json \
  --reference-analysis $PUB/analysis-reference-ida.json \
  --rebuilt-analysis $PUB/analysis-rebuilt-ida.json \
  --output $R/invocation-coding/ledger.json

PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis $PUB/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  --source-dir src/Kits/Foundation --repo-root . --objc-methods \
  --ownership $R/ownership.json \
  --output $R/invocation-coding/source-map.json
```

`ledger` is driven one entry at a time by `binrecon ledger` transitions against `$R/invocation-coding/ledger.json`. Gate 3 is evidence only. **Budget ~1 s per ledger entry** — the programme's own measured rate.

- [ ] **Step 6: Write `divergences.md`'s stage 2c section**

Record, at minimum: the forwarding-mechanism supersession (spec S2.1) — cite the exact test in Task 10 as the evidence it works, not just that the category exists; `NSCoder`'s abstract-primitives pattern (S2.2); the inline-bitfield-refcount divergence from the side table (S2.5); whichever retain-count mechanism Task 1 Step 1 confirmed for `NSMethodSignature`; the plist/typedstream parser's actual reconstructed scope (S2.4), including whether it turned out to be the full grammar or a substitution Task 4 had to make when the disassembly permitted less than hoped; the confirmed register-return mechanism from Task 8 Step 1; the confirmed fault-firing sequence from Task 12 Step 1 (forwards-only vs. isa-swap); and the untested-methods table for anything no test in this stage reaches (the `container` ivar per spec S5.3; `NSInvocation`'s `NSMutableArray *container` itself; any of Task 8's register-return branches this stage's own test target types could not exercise).

- [ ] **Step 7: Final verification**

Run, and record each result:

1. `abi-check` over all fourteen modules → `ABI matches`, exit 0
2. All eleven test suites (seven from stage 2a/2b plus `test_methodsignature`, `test_coder`, `test_invocation`, `test_fault`) → `PASSED: 0 failure(s)`
3. `binrecon source-map` → every 2c function mapped, `by_module` accounting for all
4. Full binrecon suite → `804 passed, 4 skipped`
5. `git diff --name-only <stage-2c-base>..HEAD -- 'src/Kits/Foundation/*.h'` → **empty**
6. `symbol-audit` → the unclaimed count has fallen by the number of functions this stage claimed; record the new figure in the ledger

- [ ] **Step 8: Clean up the guest and commit**

```bash
git add src/Kits/Foundation/reconstruction/abi/NSMethodSignature.json src/Kits/Foundation/reconstruction/abi/NSCoder.json src/Kits/Foundation/reconstruction/abi/NSInvocation.json src/Kits/Foundation/reconstruction/abi/NSFault.json src/Kits/Foundation/reconstruction/invocation-coding/ledger.json src/Kits/Foundation/reconstruction/invocation-coding/source-map.json src/Kits/Foundation/reconstruction/symbols.json src/Kits/Foundation/reconstruction/ownership.json src/Kits/Foundation/reconstruction/divergences.md src/Kits/Foundation/reconstruction/tests/link_stubs.m tools/binrecon/profiles/foundation-i386-invocation-coding.json
git commit -m "Foundation: record stage 2c parity evidence and divergences"
```
