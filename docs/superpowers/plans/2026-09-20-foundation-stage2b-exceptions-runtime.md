# Foundation Stage 2b: Exceptions and Runtime — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct Rhapsody's exception machinery and Objective-C runtime helpers — `NSException`, `NSAssertionHandler`, the `setjmp`-based handler stack, and the introspection and logging functions — so that stage 2a's raise paths stop asserting against aborting stubs and start asserting real behaviour.

**Architecture:** A `setjmp` hosting gate runs first and decides whether raise/unwind can be tested at all. `NSObjCRuntime.m`'s introspection functions land next, because the exception diagnostics are built out of them. The handler stack follows, then `NSException` and `NSAssertionHandler` on top of it. The stage closes by retiring the `link_stubs.m` stubs it made real — one symbol at a time — and re-running all five stage 2a suites against the real modules.

**Tech Stack:** Python 3.12 (binrecon, pytest 9.1.1, jsonschema 4.26.0), IDA Professional 9.2, Objective-C compiled with gcc 2.7.2.1 on a native ppc Rhapsody 5.6 guest cross-compiling i386.

## Global Constraints

- Spec of record: [docs/superpowers/specs/2026-09-20-foundation-stage2b-exceptions-runtime-design.md](../specs/2026-09-20-foundation-stage2b-exceptions-runtime-design.md). Programme spec: [2026-07-26-foundation-i386-reconstruction-design.md](../specs/2026-07-26-foundation-i386-reconstruction-design.md).
- **Working directory is the worktree** `D:\RhapsodiOS\.claude\worktrees\foundation-recon` (branch `foundation-recon`). Run every command from there.
- **Reference of record:** the extracted thin i386 slice at `C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1630488**, SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**. Never point tooling at the fat container.
- **The venv lives at the main repo root and is gitignored, so this worktree has none.** Use `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`, which resolves `binrecon` to the worktree's copy.
- Profile commands need `BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386` in the environment; the profile's `reference.path` is `${BINRECON_REFERENCE}`.
- binrecon test command: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`
- **The full binrecon suite takes ~1 minute** (baseline at stage 2b start: **804 passed, 4 skipped**). Run the focused file during red/green; run the full suite once before committing.
- **Known flake:** the angr subprocess tests (`tools/binrecon/tests/test_angr_adapter.py`, and an angr pipeline test in `tools/binrecon/tests/test_cli.py`) time out under load and pass standalone. If one fails, rerun it alone, confirm, and say so — do not report it as a regression.
- **No header under `src/Kits/Foundation` may be modified.** Hard constraint across the whole programme. If reconstruction appears to need a header change, stop and report.
- **Reconstruct, do not transcribe.** No `param_1`, `v3`, `sub_42501428`, or decompiler comments in committed source. Read `src/Kits/Foundation/NSObject.m` and `NSAutoreleasePool.m` for the house style: Apple's copyright header preserved, C89 (declarations at the top of a block, no `//` comments), working variables named for what they hold, comments explaining why.
- **The underscore rule (spec §3.3).** The declaring header's spelling **is** the C identifier — `NSException.h` declares `_NSAddHandler2`, so the function is named `_NSAddHandler2` and the i386 symbol is `__NSAddHandler2`. Where no header declares the function, the reference's symbol minus one leading underscore is the C identifier. `abi-check` arbitrates. **A mismatch is fixed by renaming the function, never by changing its linkage.** Stage 2a shipped the mirror-image bug; see `divergences.md`'s Gate 1 section.
- **An `abi-check` "unexpected exported symbol" means the symbol needs CLAIMING in `symbols.json`, not suppressing.** Check the reference's own symbol table before changing any linkage.
- **Never `git add -A` or `git add .`** — this repo tracks `__pycache__`, and `tools/binrecon/out/` is gitignored evidence. Each commit step names its exact paths; use those.
- Commit messages: start with the subsystem (`Foundation: `, `binrecon: `, `docs: `), one line, describe behaviour not files, no trailers or metadata beyond the session's configured attribution line.
- Do not add Foundation to `src/Manifest` or build it as a framework — still deferred.

### Guest access

- Native ppc Rhapsody 5.6 at `10.10.0.241`, `cc-783.1` / gcc 2.7.2.1.
- The harness config `vm/vm.conf` is **untracked and exists only in the MAIN worktree** at `/d/RhapsodiOS/vm/vm.conf`. It contains a password. Reference that path directly — do **not** copy it into this worktree, where it is not gitignored and could be committed by accident.
- Reach the guest with `"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@10.10.0.241` and `pscp.exe`, reading `Host`/`User`/`Password` out of that file. **Set `MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL='*'`** before invoking plink, or MSYS rewrites a leading `/bin/sh` argument into a Windows path.
- **The guest login shell is tcsh.** Bash-style `2>&1` silently kills a command with no output. Put the command in a `.sh` file, `pscp` it over, and run `sh /tmp/yourfile.sh`.
- Sync sources to an **isolated** directory: `pscp -r src/Kits/Foundation root@10.10.0.241:/build/source/src/Kits/Foundation-2b`. `pscp -r DIR dest` nests one level, so sources land at `/build/source/src/Kits/Foundation-2b/Foundation/*` — which is what makes the load-bearing `-I..` resolve `<Foundation/...>`. **`/build/source/src/Kits/Foundation` is shared with other sessions; do not touch it.** Remove your directory when the stage ends.
- **Two different builds, two different architectures — this is not optional.**
  - **Test binaries are linked and run, so they build NATIVE (ppc):**
    `cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/test_x <sources>`
    with **no `-arch` flag**. The guest has no i386 `crt1.o`, no i386 `libcc_dynamic.a` and no i386 System framework, so **no i386 executable can be linked there at all**.
  - **Objects for `abi-check` are compiled, never linked, and are i386:**
    `cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/abi2b/NSx.o NSx.m`
- **`abi-check` `--built` keys are `MODULE.m`, not `MODULE`** — e.g. `--built NSException.m=/path/NSException.o`.
- **`binrecon abi` cannot emit a document for `NSZone.m`** — the reference has no such module. Never pass `--module NSZone.m`.
- **The current link lines for stage 2a's suites** (they change in Task 11):
  - `test_zone`, `test_refcount`: `<test>.c NSZone.m reconstruction/tests/link_stubs.m`
  - `test_object`, `test_proxy`, `test_pool`: `<test>.m NSObject.m NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m reconstruction/tests/link_stubs.m`

---

### Task 1: Prove `setjmp`/`longjmp` can host the handler stack

Spec §2.4 and §3.4 step 1 — the stage's go/no-go gate. It decides whether any of Tasks 7–10 can be behaviourally tested. **It runs before any reconstruction.**

**Files:**
- Create: `docs/superpowers/plans/notes/2026-09-20-setjmp-hosting-probe.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a recorded verdict, plus the exact compile-and-link line Tasks 7–10 reuse verbatim.

- [ ] **Step 1: Understand what is actually at risk**

`NSException.h` defines the handler macros in terms of `_NSSETJMP`:

```c
#define _NSSETJMP(B, S)	_setjmp((B))
```

Rhapsody is not `__svr4__`, `__WIN32__` or `__hpux__`, so this platform gets **`_setjmp`**, not `setjmp`. `_setjmp`/`_longjmp` do **not** save or restore the signal mask; `setjmp`/`longjmp` on some platforms do. **Mixing them is undefined.** Every raise path in this stage must therefore use `_longjmp`, never `longjmp`. This probe confirms that pairing works on the guest before anything depends on it.

The second risk is `NS_DURING`'s structure. The macro declares `NSHandler2 _localHandler;` as an automatic in the enclosing block and hands `&_localHandler` to `_NSAddHandler2`. If the compiler reuses that stack slot, or if `_longjmp` unwinds past it, the handler the stack points at is dead memory.

- [ ] **Step 2: Write the probe**

Create these in your isolated guest directory (throwaway — not in the repo).

`probe_setjmp.c`:

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

- [ ] **Step 3: Build and run it on the guest**

Write `/tmp/probe.sh` and `pscp` it over:

```sh
#!/bin/sh
cd /build/source/src/Kits/Foundation-2b/Foundation || exit 1
cc -o /tmp/probe_setjmp probe_setjmp.c
echo "build status=$?"
/tmp/probe_setjmp
echo "run status=$?"
```

Run: `plink ... 'sh /tmp/probe.sh'`
Expected: `PASSED: 0 failure(s)` and `run status=0`.

- [ ] **Step 4: Record the verdict**

Create `docs/superpowers/plans/notes/2026-09-20-setjmp-hosting-probe.md`. It must state, in this order: the verdict (`## RESULT: hosted` or `## RESULT: not hosted`); the guest's `uname -a` and `cc -v`; that `_NSSETJMP` resolves to `_setjmp` on this platform and therefore **`_longjmp` is mandatory**; the exact build line used; and the probe source inline so the result is reproducible from the tree.

If the probe **fails**, stop and report. Do not continue to Task 2. The stage narrows to ABI-only and the spec's §5.1 fallback applies.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/notes/2026-09-20-setjmp-hosting-probe.md
git commit -m "Foundation: record whether the guest hosts the exception handler stack"
```

---

### Task 2: Class and selector name conversion

**Files:**
- Modify: `src/Kits/Foundation/NSObjCRuntime.m` (replaces the `NSStringFromSelector`/`NSSelectorFromString`/`NSClassFromString`/`NSStringFromClass` TODO stubs)
- Create: `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `NSString *NSStringFromSelector(SEL aSelector)`
  - `SEL NSSelectorFromString(NSString *aSelectorName)`
  - `Class NSClassFromString(NSString *aClassName)`
  - `NSString *NSStringFromClass(Class aClass)`
  - `const char *_NSObjCRuntimeStringBytes(NSString *string)` — **file-static**, not exported. Later tasks in this module reuse it.
  - `NSString *_NSObjCRuntimeStringWithCString(const char *bytes)` — **file-static**, not exported.

- [ ] **Step 1: Understand the substitution these four need**

All four cross the `NSString` boundary, and `NSString` is stage 3. Spec §3.2 settles the approach: this stage uses the `NXConstantString` layout the compiler already emits for `@"..."` literals.

This project's Objective-C frontend (`src/cc-1/cc/objc/NXConstStr.h`) lays a literal out as:

```c
struct { Class isa; char *c_string; unsigned int len; };
```

Reading a string therefore means casting to that shape. Building one means allocating that shape and pointing `isa` at `_NSConstantStringClassReference`, the same symbol the compiler references. That produces an object layout-compatible with a real literal, which is exactly what stage 3 will replace with genuine `NSString` instances. `link_stubs.m` already reads literals this way (`NSTestCaptureRaiseMessage`), so the technique is established in the tree.

- [ ] **Step 2: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`:

```objc
/*  Behavioural tests for NSObjCRuntime, stage 2b.  */

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>
#import <objc/objc-runtime.h>
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

/*  Reads an NSString the way this stage builds one: stage 2b has no real
    NSString, so both literals and the strings these functions return are
    NXConstantString-shaped records (see NSObjCRuntime.m's own comment).  */
static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

#define CHECK_STRING(actual, expected) \
    do { \
        const char *bytes = TestStringBytes(actual); \
        if (bytes == NULL || strcmp(bytes, (expected)) != 0) { \
            printf("FAIL %s:%d expected \"%s\", got \"%s\"\n", \
                   __FILE__, __LINE__, (expected), bytes ? bytes : "(null)"); \
            failures++; \
        } \
    } while (0)

static void test_NSStringFromClass_gives_the_class_name(void)
{
    CHECK_STRING(NSStringFromClass([NSObject class]), "NSObject");
}

static void test_NSStringFromClass_of_Nil_is_nil(void)
{
    CHECK(NSStringFromClass(Nil) == nil);
}

static void test_NSClassFromString_finds_a_registered_class(void)
{
    CHECK(NSClassFromString(@"NSObject") == [NSObject class]);
}

static void test_NSClassFromString_of_an_unknown_name_is_Nil(void)
{
    CHECK(NSClassFromString(@"NSNoSuchClassExistsHere") == Nil);
}

static void test_NSStringFromSelector_gives_the_selector_name(void)
{
    CHECK_STRING(NSStringFromSelector(@selector(description)), "description");
    CHECK_STRING(NSStringFromSelector(@selector(isEqual:)), "isEqual:");
}

static void test_NSSelectorFromString_round_trips(void)
{
    SEL selector = NSSelectorFromString(@"isEqual:");

    CHECK(selector == @selector(isEqual:));
    CHECK_STRING(NSStringFromSelector(selector), "isEqual:");
}

static void test_NSSelectorFromString_registers_an_unseen_name(void)
{
    SEL selector = NSSelectorFromString(@"aSelectorNoOneHasUsedYet:");

    CHECK(selector != NULL);
    CHECK_STRING(NSStringFromSelector(selector), "aSelectorNoOneHasUsedYet:");
}

static void test_conversions_of_nil_are_safe(void)
{
    CHECK(NSClassFromString(nil) == Nil);
    CHECK(NSSelectorFromString(nil) == NULL);
    CHECK(NSStringFromSelector(NULL) == nil);
}

int main(void)
{
    test_NSStringFromClass_gives_the_class_name();
    test_NSStringFromClass_of_Nil_is_nil();
    test_NSClassFromString_finds_a_registered_class();
    test_NSClassFromString_of_an_unknown_name_is_Nil();
    test_NSStringFromSelector_gives_the_selector_name();
    test_NSSelectorFromString_round_trips();
    test_NSSelectorFromString_registers_an_unseen_name();
    test_conversions_of_nil_are_safe();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 3: Run it and watch it fail**

Sync and build on the guest:

```sh
cd /build/source/src/Kits/Foundation-2b/Foundation
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_objcruntime reconstruction/tests/test_objcruntime.m \
   NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m \
   reconstruction/tests/link_stubs.m
/tmp/test_objcruntime
```

Expected: `FAILED` with several failures — the stubs return `nil`/`NULL`/`Nil`.

- [ ] **Step 4: Implement**

Replace the four TODO stubs in `src/Kits/Foundation/NSObjCRuntime.m`. Keep the existing file header and `#import`s; add `#import <objc/objc-runtime.h>` and `#include <string.h>`, and `#import <Foundation/NSZone.h>` for `NSZoneMalloc`.

```objc
/*	Stage 2b has no NSString: NSString.m is stage 3.  What it does have is
	the layout the compiler already emits for every `@"..."` literal --
	this project's Objective-C frontend (src/cc-1/cc/objc/NXConstStr.h)
	lays one out as { Class isa; char *c_string; unsigned int len; }, with
	isa pointing at _NSConstantStringClassReference.  The two helpers below
	read and build that shape, so the four conversion functions can return
	and accept something a caller treats as a string, and so a test can read
	the result back.  Stage 3 replaces both with real NSString instances
	and -cString/+stringWithCString:length:; the exported ABI does not move
	when it does.  */

typedef struct {
    Class	isa;
    char	*c_string;
    unsigned	len;
} NSObjCRuntimeStringRecord;

extern struct objc_class _NSConstantStringClassReference;

static const char *
_NSObjCRuntimeStringBytes(NSString *string)
{
    if (string == nil)
        return NULL;
    return ((NSObjCRuntimeStringRecord *)string)->c_string;
}

static NSString *
_NSObjCRuntimeStringWithCString(const char *bytes)
{
    NSObjCRuntimeStringRecord *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = (NSObjCRuntimeStringRecord *)
        NSZoneMalloc(0, sizeof(NSObjCRuntimeStringRecord) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (NSString *)record;
}

NSString *
NSStringFromSelector(SEL aSelector)
{
    if (aSelector == NULL)
        return nil;
    return _NSObjCRuntimeStringWithCString(sel_getName(aSelector));
}

SEL
NSSelectorFromString(NSString *aSelectorName)
{
    const char *bytes = _NSObjCRuntimeStringBytes(aSelectorName);

    if (bytes == NULL)
        return NULL;
    return sel_registerName(bytes);
}

Class
NSClassFromString(NSString *aClassName)
{
    const char *bytes = _NSObjCRuntimeStringBytes(aClassName);

    if (bytes == NULL)
        return Nil;
    return objc_lookUpClass(bytes);
}

NSString *
NSStringFromClass(Class aClass)
{
    if (aClass == Nil)
        return nil;
    return _NSObjCRuntimeStringWithCString(aClass->name);
}
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run exactly as in Step 3.
Expected: `PASSED: 0 failure(s)`.

If `sel_getName` is unavailable, this runtime spells it `sel_getName` in `<objc/objc-runtime.h>`; selectors are interned C strings here, so `(const char *)aSelector` is the fallback — confirm against the header before using it and note the choice in the commit.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSObjCRuntime.m src/Kits/Foundation/reconstruction/tests/test_objcruntime.m
git commit -m "Foundation: reconstruct class and selector name conversion"
```

---

### Task 3: `NSGetSizeAndAlignment`

**Files:**
- Modify: `src/Kits/Foundation/NSObjCRuntime.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `const char *NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)`
  - `const char *_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)` — a **separate exported** function. The reference exports both `_NSGetSizeAndAlignment` (the public one, mangled) and `__NSGetSizeAndAlignment` (a private one). Per the underscore rule the private one's C identifier is `_NSGetSizeAndAlignment`.

- [ ] **Step 1: Write the failing test**

Append to `test_objcruntime.m` and call each from `main`:

```objc
/*  Type encodings are i386's: int/long/pointer 4, short 2, char 1,
    float 4, double 8, and a struct is laid out from its members.  */
static void test_NSGetSizeAndAlignment_scalars(void)
{
    unsigned size;
    unsigned align;
    const char *rest;

    rest = NSGetSizeAndAlignment("i", &size, &align);
    CHECK(size == 4); CHECK(align == 4); CHECK(rest != NULL && *rest == '\0');

    rest = NSGetSizeAndAlignment("c", &size, &align);
    CHECK(size == 1); CHECK(align == 1);

    rest = NSGetSizeAndAlignment("s", &size, &align);
    CHECK(size == 2); CHECK(align == 2);

    rest = NSGetSizeAndAlignment("d", &size, &align);
    CHECK(size == 8);

    rest = NSGetSizeAndAlignment("@", &size, &align);
    CHECK(size == 4); CHECK(align == 4);

    rest = NSGetSizeAndAlignment(":", &size, &align);
    CHECK(size == 4);

    rest = NSGetSizeAndAlignment("^v", &size, &align);
    CHECK(size == 4); CHECK(rest != NULL && *rest == '\0');
}

static void test_NSGetSizeAndAlignment_advances_through_a_signature(void)
{
    unsigned size;
    unsigned align;
    const char *cursor = "i@:c";

    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 1);
    CHECK(cursor != NULL && *cursor == '\0');
}

static void test_NSGetSizeAndAlignment_arrays_and_structs(void)
{
    unsigned size;
    unsigned align;
    const char *rest;

    rest = NSGetSizeAndAlignment("[8i]", &size, &align);
    CHECK(size == 32);
    CHECK(rest != NULL && *rest == '\0');

    /*  NSRange-shaped: two unsigned ints.  */
    rest = NSGetSizeAndAlignment("{_NSRange=II}", &size, &align);
    CHECK(size == 8); CHECK(align == 4);
    CHECK(rest != NULL && *rest == '\0');

    /*  Mixed alignment: char then int pads to 8.  */
    rest = NSGetSizeAndAlignment("{mixed=ci}", &size, &align);
    CHECK(size == 8); CHECK(align == 4);
}

static void test_NSGetSizeAndAlignment_tolerates_null_out_params(void)
{
    const char *rest = NSGetSizeAndAlignment("i", NULL, NULL);

    CHECK(rest != NULL && *rest == '\0');
}

static void test_private_NSGetSizeAndAlignment_agrees_with_the_public_one(void)
{
    unsigned publicSize, publicAlign;
    unsigned privateSize, privateAlign;

    NSGetSizeAndAlignment("{_NSRange=II}", &publicSize, &publicAlign);
    _NSGetSizeAndAlignment("{_NSRange=II}", &privateSize, &privateAlign);
    CHECK(publicSize == privateSize);
    CHECK(publicAlign == privateAlign);
}
```

Add at the top of the file, below the imports, so the private variant is visible:

```objc
extern const char *_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp);
```

- [ ] **Step 2: Run it and watch it fail**

Rebuild as in Task 2 Step 3.
Expected: link error `_NSGetSizeAndAlignment` undefined, plus failures from the `NSGetSizeAndAlignment` stub returning `NULL`.

- [ ] **Step 3: Implement**

Replace the `NSGetSizeAndAlignment` stub:

```objc
/*	Walks one type encoding and reports its size and alignment, returning
	a pointer just past the encoding it consumed -- so a caller can step
	through a whole method signature by feeding the return value back in.
	Sizes are this architecture's, taken from the compiler rather than
	assumed: gcc 2.7.2.1 on i386 gives int/long/pointer 4, short 2,
	char 1, float 4, double 8, long long 8.

	A struct's size is its members laid out in order, each padded up to
	its own alignment, with the whole padded up to the widest member's
	alignment; a union's is its widest member.  Qualifier prefixes
	(const, in, out, inout, bycopy, byref, oneway) carry no size and are
	skipped.  */
static const char *
NSSizeAndAlignmentOfType(const char *typePtr, unsigned *sizep, unsigned *alignp)
{
    unsigned size;
    unsigned align;

    while (*typePtr == 'r' || *typePtr == 'n' || *typePtr == 'N' ||
           *typePtr == 'o' || *typePtr == 'O' || *typePtr == 'R' ||
           *typePtr == 'V')
        typePtr++;

    size = 0;
    align = 1;

    switch (*typePtr) {
    case 'c': case 'C':
        size = sizeof(char); align = size; typePtr++; break;
    case 's': case 'S':
        size = sizeof(short); align = size; typePtr++; break;
    case 'i': case 'I': case 'l': case 'L':
        size = sizeof(int); align = size; typePtr++; break;
    case 'q': case 'Q':
        size = 8; align = sizeof(int); typePtr++; break;
    case 'f':
        size = sizeof(float); align = size; typePtr++; break;
    case 'd':
        size = sizeof(double); align = sizeof(int); typePtr++; break;
    case 'B':
        size = sizeof(char); align = size; typePtr++; break;
    case 'v':
        size = 0; align = 1; typePtr++; break;
    case '*': case '@': case '#': case ':':
        size = sizeof(void *); align = size; typePtr++; break;
    case '?':
        size = sizeof(void *); align = size; typePtr++; break;
    case '^':
        /*  A pointer is pointer-sized whatever it points at, but the
            pointee's encoding still has to be stepped over.  */
        typePtr = NSSizeAndAlignmentOfType(typePtr + 1, 0, 0);
        size = sizeof(void *); align = size;
        break;
    case '[': {
        unsigned count;
        unsigned elementSize;
        unsigned elementAlign;

        typePtr++;
        count = 0;
        while (*typePtr >= '0' && *typePtr <= '9')
            count = (count * 10) + (unsigned)(*typePtr++ - '0');
        typePtr = NSSizeAndAlignmentOfType(typePtr, &elementSize, &elementAlign);
        if (*typePtr == ']')
            typePtr++;
        size = count * elementSize;
        align = elementAlign;
        break;
    }
    case '{': case '(': {
        char closing = (*typePtr == '{') ? '}' : ')';
        BOOL isUnion = (closing == ')');
        unsigned memberSize;
        unsigned memberAlign;

        typePtr++;
        while (*typePtr != '\0' && *typePtr != '=' && *typePtr != closing)
            typePtr++;
        if (*typePtr == '=')
            typePtr++;

        while (*typePtr != '\0' && *typePtr != closing) {
            typePtr = NSSizeAndAlignmentOfType(typePtr, &memberSize, &memberAlign);
            if (memberAlign > align)
                align = memberAlign;
            if (isUnion) {
                if (memberSize > size)
                    size = memberSize;
            } else {
                if (memberAlign != 0 && (size % memberAlign) != 0)
                    size += memberAlign - (size % memberAlign);
                size += memberSize;
            }
        }
        if (*typePtr == closing)
            typePtr++;
        if (align != 0 && (size % align) != 0)
            size += align - (size % align);
        break;
    }
    case 'b': {
        /*  A bitfield: bN, N bits.  Reported as the bits it occupies,
            which is what the runtime's own walkers do with it.  */
        unsigned bits = 0;

        typePtr++;
        while (*typePtr >= '0' && *typePtr <= '9')
            bits = (bits * 10) + (unsigned)(*typePtr++ - '0');
        size = (bits + 7) / 8;
        align = 1;
        break;
    }
    default:
        if (*typePtr != '\0')
            typePtr++;
        break;
    }

    if (sizep != 0)
        *sizep = size;
    if (alignp != 0)
        *alignp = align;

    return typePtr;
}

const char *
NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)
{
    if (typePtr == NULL)
        return NULL;
    return NSSizeAndAlignmentOfType(typePtr, sizep, alignp);
}

/*	The reference exports a second, private entry point alongside the
	public one (__NSGetSizeAndAlignment beside _NSGetSizeAndAlignment).
	No header declares it and no caller in this stage's modules reaches
	it; both walk the same encodings, so this shares the implementation
	rather than guessing at a difference the disassembly does not show.
	Recorded in divergences.md.  */
const char *
_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)
{
    return NSGetSizeAndAlignment(typePtr, sizep, alignp);
}
```

- [ ] **Step 4: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSObjCRuntime.m src/Kits/Foundation/reconstruction/tests/test_objcruntime.m
git commit -m "Foundation: walk Objective-C type encodings for size and alignment"
```

---

### Task 4: `NSLog`, `NSLogv` and `_NSBasicStdErrLog`

**Files:**
- Modify: `src/Kits/Foundation/NSObjCRuntime.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`

**Interfaces:**
- Consumes: `_NSObjCRuntimeStringBytes` (Task 2).
- Produces:
  - `void NSLog(NSString *format, ...)`
  - `void NSLogv(NSString *format, va_list args)`
  - `void _NSBasicStdErrLog(const char *message)` — exported; the single write point.

- [ ] **Step 1: Understand the scope of the substitution**

Spec §5.4: this formats at C level over the literal's bytes, covering only what this stage's callers need. It is provisional and stage 3 replaces it. The one thing it must get right is `%@`, because 2a's reconstructed strings use it (`@"%@: selector not recognized"`) — and in this stage a `%@` argument is another `NXConstantString`-shaped record, so it prints that record's bytes.

`_NSBasicStdErrLog` exists in the reference as an external `__TEXT,__text` symbol; routing all output through it matches the reference's structure.

- [ ] **Step 2: Write the failing test**

Append to `test_objcruntime.m` and call from `main`. The test captures stderr by reopening it onto a temporary file and reading it back.

```objc
#include <stdlib.h>

/*  Runs `body` with stderr redirected to a temp file, then returns its
    contents in `buffer`.  NSLog writes to stderr, and this is the only
    way to assert on what it produced without a real NSString.  */
static void CaptureStdErr(void (*body)(void), char *buffer, unsigned size)
{
    const char *path = "/tmp/test_objcruntime_stderr.txt";
    int savedFd = dup(2);
    FILE *captured = fopen(path, "w");
    FILE *readBack;
    unsigned got;

    fflush(stderr);
    dup2(fileno(captured), 2);
    body();
    fflush(stderr);
    dup2(savedFd, 2);
    close(savedFd);
    fclose(captured);

    buffer[0] = '\0';
    readBack = fopen(path, "r");
    if (readBack != NULL) {
        got = fread(buffer, 1, size - 1, readBack);
        buffer[got] = '\0';
        fclose(readBack);
    }
    remove(path);
}

static void emit_plain(void)    { NSLog(@"a plain message"); }
static void emit_decimal(void)  { NSLog(@"count is %d", 42); }
static void emit_cstring(void)  { NSLog(@"name is %s", "NSObject"); }
static void emit_object(void)   { NSLog(@"%@: selector not recognized", @"-[NSObject foo]"); }
static void emit_percent(void)  { NSLog(@"100%% done"); }

static void test_NSLog_writes_its_message_to_stderr(void)
{
    char buffer[512];

    CaptureStdErr(emit_plain, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "a plain message") != NULL);
}

static void test_NSLog_substitutes_c_format_specifiers(void)
{
    char buffer[512];

    CaptureStdErr(emit_decimal, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "count is 42") != NULL);

    CaptureStdErr(emit_cstring, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "name is NSObject") != NULL);
}

static void test_NSLog_substitutes_an_object_with_percent_at(void)
{
    char buffer[512];

    CaptureStdErr(emit_object, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "-[NSObject foo]: selector not recognized") != NULL);
}

static void test_NSLog_passes_a_literal_percent_through(void)
{
    char buffer[512];

    CaptureStdErr(emit_percent, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "100% done") != NULL);
}

static void test_NSLog_of_nil_does_not_crash(void)
{
    char buffer[512];

    CaptureStdErr(emit_nil_format, buffer, sizeof(buffer));
}
```

and, above those:

```objc
static void emit_nil_format(void) { NSLog(nil); }
```

Add `#include <unistd.h>` to the test's includes for `dup`/`dup2`/`close`.

- [ ] **Step 3: Run it and watch it fail**

Rebuild as in Task 2 Step 3, but **drop `reconstruction/tests/link_stubs.m`'s `NSLog`** — it is still present and will collide once `NSObjCRuntime.m` defines a real one. Delete the stub now rather than at Task 11:

In `src/Kits/Foundation/reconstruction/tests/link_stubs.m`, remove:

```objc
void NSLog(id format, ...)
{
    unimplemented("NSLog");
}
```

Expected after removing it: the test fails its assertions because the real `NSLog` is not yet written (link succeeds only after Step 4).

- [ ] **Step 4: Implement**

Append to `src/Kits/Foundation/NSObjCRuntime.m`. Add `#include <stdio.h>` and `#include <stdarg.h>` to its includes.

```objc
/*	The one place this module writes a finished log line.  The reference
	exports this symbol and routes its logging through it; keeping that
	shape means the later stages that add timestamping or a syslog route
	have one function to change rather than two.  */
void
_NSBasicStdErrLog(const char *message)
{
    if (message == NULL)
        return;
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}

/*	Formats `format` over `args` and hands the result to
	_NSBasicStdErrLog.  Stage 2b has no NSString, so this walks the
	format's own bytes and rebuilds a C format string as it goes,
	substituting %@ (whose argument is another NXConstantString-shaped
	record in this stage, see the helpers at the top of this file) with
	that record's bytes.  Every other specifier is handed to vsnprintf
	unchanged.

	PROVISIONAL: this covers the specifiers this stage's own callers use
	(%@, %s, %d, %u, %x, %c, %%) and no more.  Stage 3 replaces it with
	real NSString formatting.  Recorded in divergences.md.  */

#define NSLogMessageMax 1024

void
NSLogv(NSString *format, va_list args)
{
    const char *bytes;
    char message[NSLogMessageMax];
    unsigned out;
    unsigned i;

    bytes = _NSObjCRuntimeStringBytes(format);
    if (bytes == NULL)
        return;

    out = 0;
    i = 0;
    while (bytes[i] != '\0' && out < NSLogMessageMax - 1) {
        if (bytes[i] != '%') {
            message[out++] = bytes[i++];
            continue;
        }

        if (bytes[i + 1] == '%') {
            message[out++] = '%';
            i += 2;
            continue;
        }

        if (bytes[i + 1] == '@') {
            id object = va_arg(args, id);
            const char *text = _NSObjCRuntimeStringBytes((NSString *)object);

            if (text == NULL)
                text = "(null)";
            while (*text != '\0' && out < NSLogMessageMax - 1)
                message[out++] = *text++;
            i += 2;
            continue;
        }

        {
            /*  Copy this one specifier out and let vsnprintf do it, so
                the platform's own conversions apply rather than a
                hand-rolled imitation of them.  */
            char specifier[16];
            char converted[NSLogMessageMax];
            unsigned length = 0;

            specifier[length++] = bytes[i++];
            while (bytes[i] != '\0' && length < sizeof(specifier) - 1) {
                specifier[length++] = bytes[i];
                if (strchr("diouxXeEfgGcsp", bytes[i]) != NULL) {
                    i++;
                    break;
                }
                i++;
            }
            specifier[length] = '\0';

            converted[0] = '\0';
            vsprintf(converted, specifier, args);
            /*  vsprintf consumed exactly one argument for this
                specifier; step args past it by re-reading the same
                width the specifier implies.  */
            if (strchr(specifier, 's') != NULL)
                (void)va_arg(args, char *);
            else if (strchr(specifier, 'f') != NULL ||
                     strchr(specifier, 'e') != NULL ||
                     strchr(specifier, 'g') != NULL)
                (void)va_arg(args, double);
            else
                (void)va_arg(args, int);

            {
                unsigned k = 0;

                while (converted[k] != '\0' && out < NSLogMessageMax - 1)
                    message[out++] = converted[k++];
            }
        }
    }
    message[out] = '\0';

    _NSBasicStdErrLog(message);
}

void
NSLog(NSString *format, ...)
{
    va_list args;

    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

**If the `vsprintf`-plus-manual-`va_arg` approach misbehaves** (it relies on `vsprintf` not advancing the caller's `va_list`, which is true on some ABIs and not others), replace that block with an explicit per-specifier switch that reads the argument itself and formats with `sprintf`. Take the measurement, do not guess: write a two-line probe on the guest that calls a varargs function, passes its `va_list` to `vsprintf`, and then reads the next argument. Record which behaviour this platform has in `divergences.md`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSObjCRuntime.m src/Kits/Foundation/reconstruction/tests/test_objcruntime.m src/Kits/Foundation/reconstruction/tests/link_stubs.m
git commit -m "Foundation: reconstruct NSLog over the platform's stderr logging"
```

---

### Task 5: The three runtime introspection helpers

**SCOPE NOTE — beyond the spec's §1.1 list.** `_NSIMPForSelector`, `_NSMethodDescriptionForSelector` and `_NSClassConformsToProtocol` are external `__TEXT,__text` exports in the reference that no header declares. Stage 2a declares all three `extern` in `NSObject.m` and stubs them in `link_stubs.m`, so `-[NSObject methodForSelector:]`, `-methodDescriptionForSelector:`, `-conformsToProtocol:` and `-implementsSelector:` are all currently untestable. They are runtime introspection utilities, which is exactly what `NSObjCRuntime.m` — "Language terminology and general utility" — is for. **If the reviewer rejects this scope addition, skip this task entirely; nothing later depends on it except Task 11's stub list.**

**Files:**
- Modify: `src/Kits/Foundation/NSObjCRuntime.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/link_stubs.m`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `IMP _NSIMPForSelector(Class aClass, SEL aSelector)`
  - `struct objc_method_description *_NSMethodDescriptionForSelector(Class aClass, SEL aSelector)`
  - `BOOL _NSClassConformsToProtocol(Class aClass, Protocol *aProtocol)`

  Signatures must match the `extern` declarations already in `src/Kits/Foundation/NSObject.m` lines 25–27 exactly.

- [ ] **Step 1: Write the failing test**

Append to `test_objcruntime.m` and call from `main`:

```objc
extern IMP _NSIMPForSelector(Class aClass, SEL aSelector);
extern struct objc_method_description *_NSMethodDescriptionForSelector(Class aClass, SEL aSelector);
extern BOOL _NSClassConformsToProtocol(Class aClass, Protocol *aProtocol);
extern id _objc_msgForward(id self, SEL op, ...);

static void test_IMPForSelector_finds_an_implemented_method(void)
{
    IMP implementation = _NSIMPForSelector([NSObject class], @selector(hash));

    CHECK(implementation != NULL);
    CHECK(implementation != (IMP)_objc_msgForward);
}

static void test_IMPForSelector_reports_forwarding_for_an_unknown_selector(void)
{
    IMP implementation = _NSIMPForSelector([NSObject class],
                                           @selector(aSelectorNoOneImplements));

    CHECK(implementation == (IMP)_objc_msgForward);
}

static void test_MethodDescriptionForSelector_gives_name_and_types(void)
{
    struct objc_method_description *description =
        _NSMethodDescriptionForSelector([NSObject class], @selector(hash));

    CHECK(description != NULL);
    if (description != NULL) {
        CHECK(description->name == @selector(hash));
        CHECK(description->types != NULL);
    }
}

static void test_MethodDescriptionForSelector_of_an_unknown_selector_is_NULL(void)
{
    CHECK(_NSMethodDescriptionForSelector([NSObject class],
              @selector(aSelectorNoOneImplements)) == NULL);
}
```

`_NSClassConformsToProtocol` needs a protocol to test against; declare one in the test file above `main`:

```objc
@protocol TestRuntimeProtocol
- (void)aTestProtocolMethod;
@end

@interface TestRuntimeConformer : NSObject <TestRuntimeProtocol>
@end

@implementation TestRuntimeConformer
+ (void)initialize {}
- (void)aTestProtocolMethod {}
@end

static void test_ClassConformsToProtocol(void)
{
    CHECK(_NSClassConformsToProtocol([TestRuntimeConformer class],
                                     @protocol(TestRuntimeProtocol)));
    CHECK(!_NSClassConformsToProtocol([NSObject class],
                                      @protocol(TestRuntimeProtocol)));
}
```

- [ ] **Step 2: Remove the three stubs and run the test**

Delete `_NSIMPForSelector`, `_NSMethodDescriptionForSelector` and `_NSClassConformsToProtocol` from `link_stubs.m` (lines 122–138 in the current file), leaving the surrounding comment block's remaining stubs intact.

Rebuild as in Task 2 Step 3.
Expected: link error — the three symbols are undefined.

- [ ] **Step 3: Implement**

Append to `src/Kits/Foundation/NSObjCRuntime.m`. Add `#import <objc/Protocol.h>`.

```objc
/*	Introspection helpers the reference exports but no header declares.
	NSObject.m and NSProxy.m both call them directly (extern declarations
	in each), which is why they live here rather than in either: this
	module is the runtime's general-utility home, and both callers link
	against it.  Claimed by name in reconstruction/symbols.json.  */

extern id _objc_msgForward(id self, SEL op, ...);

/*	The implementation aClass would run for aSelector, or the runtime's
	forwarding trampoline when it has none -- the sentinel
	-[NSObject implementsSelector:] compares against, rather than a null
	a caller might mistake for an error.  */
IMP
_NSIMPForSelector(Class aClass, SEL aSelector)
{
    struct objc_method *method;

    if (aClass == Nil || aSelector == NULL)
        return (IMP)_objc_msgForward;

    method = class_getInstanceMethod(aClass, aSelector);
    if (method == NULL)
        return (IMP)_objc_msgForward;

    return method->method_imp;
}

/*	The selector and type encoding of aClass's implementation, or NULL
	when it has none.  struct objc_method's first two fields are
	layout-compatible with struct objc_method_description (objc-class.h
	against objc/Protocol.h), which is how the runtime itself hands one
	out as the other.  */
struct objc_method_description *
_NSMethodDescriptionForSelector(Class aClass, SEL aSelector)
{
    struct objc_method *method;

    if (aClass == Nil || aSelector == NULL)
        return NULL;

    method = class_getInstanceMethod(aClass, aSelector);
    if (method == NULL)
        return NULL;

    return (struct objc_method_description *)method;
}

/*	Whether aClass, or anything it inherits from, adopts aProtocol.
	class_conformsTo checks one class only, so the walk up super_class is
	this function's own work -- conformance is inherited, and a caller
	asking "does this class conform" means the whole chain.  */
BOOL
_NSClassConformsToProtocol(Class aClass, Protocol *aProtocol)
{
    Class candidate;

    if (aClass == Nil || aProtocol == nil)
        return NO;

    for (candidate = aClass; candidate != Nil; candidate = candidate->super_class)
        if (class_conformsTo(candidate, aProtocol))
            return YES;

    return NO;
}
```

- [ ] **Step 4: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

If `class_conformsTo` is not declared in this runtime's headers, check `<objc/Protocol.h>` for the spelling it does use (`[aProtocol conformsTo:]` is the message form) and adjust, noting the choice in the commit.

- [ ] **Step 5: Re-run all five stage 2a suites**

These three symbols are what 2a's `-methodForSelector:` family calls. Build and run each 2a suite with the current link line (Global Constraints), plus `NSObjCRuntime.m`.

Expected: all five `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSObjCRuntime.m src/Kits/Foundation/reconstruction/tests/test_objcruntime.m src/Kits/Foundation/reconstruction/tests/link_stubs.m
git commit -m "Foundation: reconstruct the runtime introspection helpers NSObject dispatches through"
```

---

### Task 6: The `NSDetailedDescription` categories

**Files:**
- Modify: `src/Kits/Foundation/NSObjCRuntime.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_objcruntime.m`

**Interfaces:**
- Consumes: `_NSObjCRuntimeStringWithCString` (Task 2).
- Produces: `-[Protocol detailedDescription]`, `+[NSObject detailedDescriptionForClass:]`.

- [ ] **Step 1: Understand why these need a local declaration**

Spec §2.3: both methods are in the reference's `__OBJC` metadata and in **no header in this tree**. Adding a header is forbidden. So both categories are declared in `NSObjCRuntime.m` itself, immediately above their `@implementation`, and both selectors are claimed by name in `symbols.json` (Task 12).

Their exact output text is not recoverable from this stage's analysis scope. Reconstruct the observable shape — a class or protocol's name plus its method list — and record in `divergences.md` that the exact formatting is unconfirmed.

- [ ] **Step 2: Write the failing test**

Append to `test_objcruntime.m` and call from `main`:

```objc
@interface NSObject (NSDetailedDescriptionTest)
+ (id)detailedDescriptionForClass:(Class)aClass;
@end

static void test_detailedDescriptionForClass_names_the_class(void)
{
    id description = [NSObject detailedDescriptionForClass:[NSObject class]];

    CHECK(description != nil);
    CHECK(strstr(TestStringBytes(description), "NSObject") != NULL);
}

static void test_detailedDescriptionForClass_of_Nil_is_nil(void)
{
    CHECK([NSObject detailedDescriptionForClass:Nil] == nil);
}
```

- [ ] **Step 3: Run it and watch it fail**

Rebuild as in Task 2 Step 3.
Expected: runtime failure — `NSObject` does not recognise `detailedDescriptionForClass:`.

- [ ] **Step 4: Implement**

Append to `src/Kits/Foundation/NSObjCRuntime.m`:

```objc
/*	NSDetailedDescription: two diagnostic categories the reference's
	__OBJC metadata carries but that no header in this tree declares, so
	both are declared here, the only place that implements them, and
	claimed by name in reconstruction/symbols.json.  The reference's exact
	output text is outside this stage's published analysis scope; what is
	reconstructed is the observable shape -- the name, and the methods it
	carries.  Recorded in divergences.md.  */

@interface Protocol (NSDetailedDescription)
- (NSString *)detailedDescription;
@end

@implementation Protocol (NSDetailedDescription)

- (NSString *)detailedDescription
{
    return _NSObjCRuntimeStringWithCString([self name]);
}

@end

@interface NSObject (NSDetailedDescription)
+ (NSString *)detailedDescriptionForClass:(Class)aClass;
@end

@implementation NSObject (NSDetailedDescription)

+ (NSString *)detailedDescriptionForClass:(Class)aClass
{
    char buffer[256];

    if (aClass == Nil)
        return nil;

    strncpy(buffer, aClass->name, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';

    return _NSObjCRuntimeStringWithCString(buffer);
}

@end
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Run the full binrecon suite and commit**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```
Expected: `804 passed, 4 skipped`.

```bash
git add src/Kits/Foundation/NSObjCRuntime.m src/Kits/Foundation/reconstruction/tests/test_objcruntime.m
git commit -m "Foundation: reconstruct the NSDetailedDescription diagnostic categories"
```

---

### Task 7: The exception handler stack

**Files:**
- Modify: `src/Kits/Foundation/NSException.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_exception.m`

**Interfaces:**
- Consumes: Task 1's verdict.
- Produces:
  - `void _NSAddHandler2(NSHandler2 *handler)`
  - `void _NSRemoveHandler2(NSHandler2 *handler)`
  - `NSException *_NSExceptionObjectFromHandler2(NSHandler2 *handler)`
  - `unsigned _NSExceptionHandlerCount(void)`
  - `void _NSClearExceptionStack(void)`
  - `void _NSRaiseError(NSException *exception)` — pops the top handler, stores the exception on it, `_longjmp`s. Task 9 supplies the uncaught path.

- [ ] **Step 1: Understand the contract the macros impose**

Read `NSException.h`'s macros carefully — they dictate the implementation:

```c
#define NS_DURING { NSHandler2 _localHandler;			\
		    _NSAddHandler2(&_localHandler);		\
		    if (!_NSSETJMP(_localHandler._state, 0)) {
#define NS_HANDLER _NSRemoveHandler2(&_localHandler); } else { \
		    NSException	*localException = _NSExceptionObjectFromHandler2(&_localHandler);
```

Three consequences:

1. On **normal** completion, `_NSRemoveHandler2` runs at `NS_HANDLER`. On the **raise** path it does not — so `_NSRaiseError` must pop the handler itself before transferring.
2. `_NSExceptionObjectFromHandler2` is read **after** the `_longjmp`, so the exception must be stored in the handler record, not in a global that a nested raise could overwrite.
3. `NS_VALUERETURN`/`NS_VOIDRETURN` call `_NSRemoveHandler2` and return, so `_NSRemoveHandler2` must be safe on a handler that is not the top of the stack.

`NSHandler2`'s `_others` field is the chain link.

- [ ] **Step 2: Write the failing test**

Create `src/Kits/Foundation/reconstruction/tests/test_exception.m`:

```objc
/*  Behavioural tests for NSException and the handler stack, stage 2b.
    These use the real NS_DURING / NS_HANDLER macros from NSException.h,
    so the macros are under test alongside the functions they call.  */

#import <Foundation/NSException.h>
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

extern unsigned _NSExceptionHandlerCount(void);
extern void _NSClearExceptionStack(void);

static void test_handler_stack_starts_empty(void)
{
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_adding_and_removing_a_handler_balances(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 1);
    _NSRemoveHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_handlers_nest(void)
{
    NSHandler2 outer;
    NSHandler2 inner;

    _NSAddHandler2(&outer);
    _NSAddHandler2(&inner);
    CHECK(_NSExceptionHandlerCount() == 2);
    _NSRemoveHandler2(&inner);
    CHECK(_NSExceptionHandlerCount() == 1);
    _NSRemoveHandler2(&outer);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_a_handler_with_no_exception_reports_nil(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionObjectFromHandler2(&handler) == nil);
    _NSRemoveHandler2(&handler);
}

static void test_NS_DURING_normal_path_skips_the_handler(void)
{
    int ranBody = 0;
    int ranHandler = 0;

    NS_DURING
        ranBody = 1;
    NS_HANDLER
        ranHandler = 1;
    NS_ENDHANDLER

    CHECK(ranBody == 1);
    CHECK(ranHandler == 0);
    CHECK(_NSExceptionHandlerCount() == 0);
}

int main(void)
{
    test_handler_stack_starts_empty();
    test_adding_and_removing_a_handler_balances();
    test_handlers_nest();
    test_a_handler_with_no_exception_reports_nil();
    test_NS_DURING_normal_path_skips_the_handler();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 3: Run it and watch it fail**

The real `NSException` class collides with `link_stubs.m`'s stub. Remove the stub `@interface`/`@implementation NSException` block and the three `id NS*Exception = 0;` globals from `link_stubs.m` now — Task 9 supplies the real constants; until then this test does not reference them.

```sh
cd /build/source/src/Kits/Foundation-2b/Foundation
cc -x objective-c -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/test_exception reconstruction/tests/test_exception.m \
   NSException.m NSObjCRuntime.m NSObject.m NSProxy.m NSAutoreleasePool.m \
   NSPrivate.m NSZone.m reconstruction/tests/link_stubs.m
```

Expected: link errors for `_NSAddHandler2`, `_NSRemoveHandler2`, `_NSExceptionObjectFromHandler2`, `_NSExceptionHandlerCount`, `_NSClearExceptionStack`.

- [ ] **Step 4: Implement**

Replace the top of `src/Kits/Foundation/NSException.m` (keep the copyright header; keep the `@implementation` blocks for now — Task 9 rewrites them):

```objc
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

/*	The active exception handlers, innermost first, chained through each
	NSHandler2's own _others field -- so the stack lives in the callers'
	own automatic storage and needs no allocation.

	The reference keys this per thread (NSHandler2 carries a _thread
	field, reached through the out-of-scope _NSCurrentThread()); NSThread.m
	is stage 7, so this is a single process-global chain, the same
	substitution NSAutoreleasePool.m makes for its pool stack and NSZone.m
	for _NSRefCountLock, and for the same reason.  Every test in this stage
	runs unthreaded.  Recorded in divergences.md.  */
static NSHandler2 *NSExceptionHandlerStack = 0;

/*	NS_DURING's expansion calls this with the address of an automatic it
	just declared; the record is the caller's, so this only links it in.  */
void
_NSAddHandler2(NSHandler2 *handler)
{
    if (handler == 0)
        return;

    handler->_exception = nil;
    handler->_others = (void *)NSExceptionHandlerStack;
    handler->_thread = 0;
    handler->_reserved1 = 0;
    NSExceptionHandlerStack = handler;
}

/*	Unlinks `handler`.  NS_VALUERETURN and NS_VOIDRETURN can reach this
	for a handler that is not the innermost -- a return out of the middle
	of a nested NS_DURING -- so this unwinds every handler inside it as
	well rather than assuming it is on top.  */
void
_NSRemoveHandler2(NSHandler2 *handler)
{
    NSHandler2 *scan;

    if (handler == 0)
        return;

    for (scan = NSExceptionHandlerStack; scan != 0; scan = (NSHandler2 *)scan->_others) {
        if (scan == handler) {
            NSExceptionHandlerStack = (NSHandler2 *)handler->_others;
            return;
        }
    }
}

/*	Read by NS_HANDLER's expansion after the transfer, which is why the
	exception is stored on the handler record rather than in a global a
	nested raise could overwrite before this is read.  */
NSException *
_NSExceptionObjectFromHandler2(NSHandler2 *handler)
{
    if (handler == 0)
        return nil;
    return handler->_exception;
}

/*	The pre-NSHandler2 entry point the reference still exports.  The older
	NSHandler is opaque in the shipped header (`typedef struct _NSHandler
	NSHandler;` with no definition), so nothing in this tree can construct
	one; both handler generations share this file's single chain, and this
	reads the same field the current one does.  Recorded in
	divergences.md as structurally reconstructed, not behaviourally
	confirmed.  */
NSException *
_NSExceptionObjectFromHandler(NSHandler2 *handler)
{
    return _NSExceptionObjectFromHandler2(handler);
}

/*	How many handlers are active.  Exported by the reference; used here by
	the test suite to assert the stack balances.  */
unsigned
_NSExceptionHandlerCount(void)
{
    NSHandler2 *scan;
    unsigned count;

    count = 0;
    for (scan = NSExceptionHandlerStack; scan != 0; scan = (NSHandler2 *)scan->_others)
        count++;

    return count;
}

/*	Drops every active handler.  The reference exports this for the
	unwind-everything case (a thread exiting, or a top-level loop
	recovering); nothing in this stage calls it except the tests.  */
void
_NSClearExceptionStack(void)
{
    NSExceptionHandlerStack = 0;
}
```

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run as in Step 3.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSException.m src/Kits/Foundation/reconstruction/tests/test_exception.m src/Kits/Foundation/reconstruction/tests/link_stubs.m
git commit -m "Foundation: reconstruct the exception handler stack the NS_DURING macros drive"
```

---

### Task 8: The alternate handler entry points

**Files:**
- Modify: `src/Kits/Foundation/NSException.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_exception.m`

**Interfaces:**
- Consumes: Task 7's `NSExceptionHandlerStack`.
- Produces: `void _NSAddAltHandler2(NSHandler2 *handler)`, `void _NSRemoveAltHandler2(NSHandler2 *handler)`.

- [ ] **Step 1: Understand what is and is not known**

Spec §5.3: these two are exported, undeclared, undocumented, and have no caller in this stage's modules — the likely callers are Distributed Objects (stage 8). Their bodies come from the disassembly alone.

**Do not invent behaviour.** Disassemble both at their addresses in the reference and reconstruct what is actually there. If the disassembly shows them to be the same chain operations as `_NSAddHandler2`/`_NSRemoveHandler2` differing only in a flag or a separate chain head, reconstruct exactly that. Record in `divergences.md` that the evidence is structural rather than behavioural, and list both in the untested table.

To read them:

```bash
BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon symbol-audit \
  --profile tools/binrecon/profiles/foundation-i386-object-core.json \
  --symbols src/Kits/Foundation/reconstruction/symbols.json 2>/dev/null | grep AltHandler
```

then locate their addresses in the reference's symbol table and read the published analysis for the 2b scope (Task 12 generates it; for this task, read the addresses directly from the image with an ad hoc script, the same way stage 2a Task 8 recovered `logMessageAndRaise` at `0x42575890`).

- [ ] **Step 2: Write the failing test**

Append to `test_exception.m` and call from `main`. This test asserts only what is safe to assert without knowing the semantics — that the pair balances and does not corrupt the main chain:

```objc
extern void _NSAddAltHandler2(NSHandler2 *handler);
extern void _NSRemoveAltHandler2(NSHandler2 *handler);

static void test_alt_handlers_do_not_disturb_the_main_chain(void)
{
    NSHandler2 main;
    NSHandler2 alternate;
    unsigned before;

    _NSAddHandler2(&main);
    before = _NSExceptionHandlerCount();

    _NSAddAltHandler2(&alternate);
    _NSRemoveAltHandler2(&alternate);

    CHECK(_NSExceptionHandlerCount() == before);
    _NSRemoveHandler2(&main);
    CHECK(_NSExceptionHandlerCount() == 0);
}
```

- [ ] **Step 3: Run it and watch it fail**

Rebuild as in Task 7 Step 3.
Expected: link errors for `_NSAddAltHandler2` and `_NSRemoveAltHandler2`.

- [ ] **Step 4: Read the reference, then implement what it shows**

Get both functions' addresses and bytes:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
payload, document = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
text = [s for s in document['sections'] if s['name'] == '__TEXT,__text'][0]
starts = sorted({s['address'] for s in document['symbols']
                 if s.get('section') == '__TEXT,__text'})
for symbol in document['symbols']:
    if 'AltHandler2' in symbol['name']:
        address = symbol['address']
        following = [a for a in starts if a > address]
        end = following[0] if following else text['address'] + text['size']
        offset = text['offset'] + (address - text['address'])
        print(symbol['name'], hex(address), 'size', end - address)
        print(payload[offset:offset + (end - address)].hex())
"
```

Disassemble those bytes as i386 and reconstruct what is actually there.

**Do not invent behaviour.** The most likely finding, given the names and
the `_others` chain already in this file, is that the Alt pair maintains a
second chain head for handlers that must not be unwound by an ordinary
raise. If that is what the bytes show, reconstruct exactly that — a second
file-static head plus the same link/unlink shape as `_NSAddHandler2` /
`_NSRemoveHandler2`. If the bytes show something else, write what they
show.

Whatever the outcome, the comment above the pair must say which parts came
from the disassembly and which remain unconfirmed, and both functions go in
`divergences.md`'s untested table with the note that their callers do not
exist until stage 8.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSException.m src/Kits/Foundation/reconstruction/tests/test_exception.m
git commit -m "Foundation: reconstruct the alternate exception handler entry points"
```

---

### Task 9: `NSException` and the raise path

**Files:**
- Modify: `src/Kits/Foundation/NSException.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_exception.m`

**Interfaces:**
- Consumes: Task 7's handler stack, Task 2's string helpers, Task 4's `NSLogv`.
- Produces: the 14 exception-name constants; `NSHangOnUncaughtException`; `NSGetUncaughtExceptionHandler`; `NSSetUncaughtExceptionHandler`; `_NSRaiseError`; the full `NSException` class.

- [ ] **Step 1: Write the failing test**

Append to `test_exception.m` and call each from `main`:

```objc
static void test_raise_transfers_to_the_enclosing_handler(void)
{
    int reachedHandler = 0;
    id caught = nil;

    NS_DURING
        [NSException raise:NSInvalidArgumentException format:@"boom"];
        CHECK(0);  /* unreachable: raise does not return */
    NS_HANDLER
        reachedHandler = 1;
        caught = localException;
    NS_ENDHANDLER

    CHECK(reachedHandler == 1);
    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_the_exception_carries_its_reason(void)
{
    id caught = nil;

    NS_DURING
        [NSException raise:NSGenericException format:@"a specific reason"];
    NS_HANDLER
        caught = localException;
    NS_ENDHANDLER

    CHECK(caught != nil);
    CHECK(strstr(TestStringBytes([caught reason]), "a specific reason") != NULL);
}

static void test_exceptionWithName_populates_all_three_accessors(void)
{
    id exception = [NSException exceptionWithName:NSRangeException
                                           reason:@"out of range"
                                         userInfo:nil];

    CHECK(exception != nil);
    CHECK([exception name] == NSRangeException);
    CHECK(strstr(TestStringBytes([exception reason]), "out of range") != NULL);
    CHECK([exception userInfo] == nil);
}

static void test_raising_an_exception_object_directly(void)
{
    id made = [NSException exceptionWithName:NSMallocException
                                      reason:@"no memory"
                                    userInfo:nil];
    id caught = nil;

    NS_DURING
        [made raise];
    NS_HANDLER
        caught = localException;
    NS_ENDHANDLER

    CHECK(caught == made);
}

static void test_an_inner_handler_catches_before_the_outer_one(void)
{
    int innerCaught = 0;
    int outerCaught = 0;

    NS_DURING
        NS_DURING
            [NSException raise:NSGenericException format:@"inner"];
        NS_HANDLER
            innerCaught = 1;
        NS_ENDHANDLER
    NS_HANDLER
        outerCaught = 1;
    NS_ENDHANDLER

    CHECK(innerCaught == 1);
    CHECK(outerCaught == 0);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_a_raise_from_a_nested_call_unwinds(void)
{
    int caught = 0;

    NS_DURING
        raise_from_depth(6);
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_isEqual_compares_name_and_reason(void)
{
    id a = [NSException exceptionWithName:NSGenericException reason:@"same" userInfo:nil];
    id b = [NSException exceptionWithName:NSGenericException reason:@"same" userInfo:nil];
    id c = [NSException exceptionWithName:NSRangeException reason:@"same" userInfo:nil];

    CHECK([a isEqual:b]);
    CHECK(![a isEqual:c]);
}

/*  The uncaught path, observed without dying: the suite installs its own
    handler, which records the exception and jumps back here.  */
static jmp_buf uncaughtReturn;
static id uncaughtException = nil;

static void TestUncaughtHandler(NSException *exception)
{
    uncaughtException = exception;
    _longjmp(uncaughtReturn, 1);
}

static void test_an_uncaught_raise_reaches_the_uncaught_handler(void)
{
    NSUncaughtExceptionHandler *previous = NSGetUncaughtExceptionHandler();

    NSSetUncaughtExceptionHandler(TestUncaughtHandler);
    CHECK(NSGetUncaughtExceptionHandler() == TestUncaughtHandler);

    uncaughtException = nil;
    if (!_setjmp(uncaughtReturn)) {
        [NSException raise:NSGenericException format:@"nobody is catching"];
        CHECK(0);  /* unreachable */
    }

    CHECK(uncaughtException != nil);
    CHECK([uncaughtException name] == NSGenericException);

    NSSetUncaughtExceptionHandler(previous);
}
```

and above them:

```objc
static void raise_from_depth(int depth)
{
    if (depth > 0) {
        raise_from_depth(depth - 1);
        return;
    }
    [NSException raise:NSGenericException format:@"from depth"];
}

static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}
```

- [ ] **Step 2: Run it and watch it fail**

Rebuild as in Task 7 Step 3.
Expected: link errors for the exception-name constants and the uncaught-handler pair, plus failures from the TODO-stub `NSException` methods returning `nil`.

- [ ] **Step 3: Implement the constants and the uncaught path**

Append to `NSException.m`. Start with this file's own copies of the string
helpers — `NSObjCRuntime.m`'s are file-static there and deliberately not
exported, so this module carries its own rather than widening either
module's surface for the convenience of the other:

```objc
/*	Stage 2b has no NSString (stage 3).  A `@"..."` literal is laid out by
	this project's Objective-C frontend (src/cc-1/cc/objc/NXConstStr.h) as
	{ Class isa; char *c_string; unsigned int len; }, so these three read
	and build that shape -- enough for this file to carry an exception's
	name and reason and to compare them.  NSObjCRuntime.m has the same
	helpers, file-static there for the same reason they are file-static
	here: neither is part of any module's exported surface, and stage 3
	deletes both when real NSString arrives.  */

typedef struct {
    Class	isa;
    char	*c_string;
    unsigned	len;
} NSExceptionStringRecord;

extern struct objc_class _NSConstantStringClassReference;

static const char *
_NSExceptionStringBytes(NSString *string)
{
    if (string == nil)
        return NULL;
    return ((NSExceptionStringRecord *)string)->c_string;
}

static NSString *
_NSExceptionStringWithCString(const char *bytes)
{
    NSExceptionStringRecord *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = (NSExceptionStringRecord *)
        NSZoneMalloc(0, sizeof(NSExceptionStringRecord) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (NSString *)record;
}

/*	Compares two of this stage's strings by their bytes.  Sending
	-isEqual: would dispatch to a class stage 2b does not implement;
	stage 3 replaces this with the real message.  */
static BOOL
NSExceptionStringsEqual(NSString *lhs, NSString *rhs)
{
    const char *left;
    const char *right;

    if (lhs == rhs)
        return YES;

    left = _NSExceptionStringBytes(lhs);
    right = _NSExceptionStringBytes(rhs);
    if (left == NULL || right == NULL)
        return NO;

    return strcmp(left, right) == 0;
}

/*	Builds an exception's reason by formatting `format` over `argList`.
	Shares NSLogv's specifier handling by going through it is not
	possible -- NSLogv writes rather than returns -- so this repeats the
	same walk into a buffer.  Both are provisional and both go away in
	stage 3; see divergences.md.  */

#define NSExceptionReasonMax 1024

static NSString *
_NSExceptionReasonFromFormat(NSString *format, va_list argList)
{
    const char *bytes;
    char reason[NSExceptionReasonMax];
    unsigned out;
    unsigned i;

    bytes = _NSExceptionStringBytes(format);
    if (bytes == NULL)
        return nil;

    out = 0;
    i = 0;
    while (bytes[i] != '\0' && out < NSExceptionReasonMax - 1) {
        if (bytes[i] != '%') {
            reason[out++] = bytes[i++];
            continue;
        }
        if (bytes[i + 1] == '%') {
            reason[out++] = '%';
            i += 2;
            continue;
        }
        if (bytes[i + 1] == '@') {
            id object = va_arg(argList, id);
            const char *text = _NSExceptionStringBytes((NSString *)object);

            if (text == NULL)
                text = "(null)";
            while (*text != '\0' && out < NSExceptionReasonMax - 1)
                reason[out++] = *text++;
            i += 2;
            continue;
        }
        {
            char specifier[16];
            char converted[NSExceptionReasonMax];
            unsigned length = 0;
            unsigned k = 0;

            specifier[length++] = bytes[i++];
            while (bytes[i] != '\0' && length < sizeof(specifier) - 1) {
                specifier[length++] = bytes[i];
                if (strchr("diouxXeEfgGcsp", bytes[i]) != NULL) {
                    i++;
                    break;
                }
                i++;
            }
            specifier[length] = '\0';

            converted[0] = '\0';
            if (strchr(specifier, 's') != NULL)
                sprintf(converted, specifier, va_arg(argList, char *));
            else if (strchr(specifier, 'f') != NULL ||
                     strchr(specifier, 'e') != NULL ||
                     strchr(specifier, 'g') != NULL)
                sprintf(converted, specifier, va_arg(argList, double));
            else
                sprintf(converted, specifier, va_arg(argList, int));

            while (converted[k] != '\0' && out < NSExceptionReasonMax - 1)
                reason[out++] = converted[k++];
        }
    }
    reason[out] = '\0';

    return _NSExceptionStringWithCString(reason);
}
```

Add `#include <string.h>` to `NSException.m` for `strlen`/`memcpy`/`strcmp`/`strchr`.

Then the constants and the raise path:

```objc
/*	The exception names.  Each is a compiler-emitted NXConstantString
	literal: stage 2b has no NSString (stage 3), and a literal is exactly
	what a `NSString * const` global holds in the reference.  Callers
	compare these by pointer, which works because each name is one shared
	instance.

	The reference exports 23 such constants; the 14 here are the ones
	NSException.h declares.  The other 9 are declared in other stages'
	headers -- NSString.h, NSDecimalNumber.h, NSFileHandle.h,
	NSArchiver.h, NSConnection.h -- and belong to those stages under the
	project's attribute-by-declaring-header rule.  Listed in
	divergences.md so none is lost.  */

NSString * const NSGenericException = @"NSGenericException";
NSString * const NSRangeException = @"NSRangeException";
NSString * const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString * const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSString * const NSMallocException = @"NSMallocException";
NSString * const NSObjectInaccessibleException = @"NSObjectInaccessibleException";
NSString * const NSObjectNotAvailableException = @"NSObjectNotAvailableException";
NSString * const NSDestinationInvalidException = @"NSDestinationInvalidException";
NSString * const NSPortTimeoutException = @"NSPortTimeoutException";
NSString * const NSInvalidSendPortException = @"NSInvalidSendPortException";
NSString * const NSInvalidReceivePortException = @"NSInvalidReceivePortException";
NSString * const NSPortSendException = @"NSPortSendException";
NSString * const NSPortReceiveException = @"NSPortReceiveException";
NSString * const NSOldStyleException = @"NSOldStyleException";

/*	Set by a process that would rather stop in the debugger than exit
	when an exception goes uncaught.  Exported by the reference in
	__DATA,__data; read below.  */
BOOL NSHangOnUncaughtException = NO;

static NSUncaughtExceptionHandler *NSUncaughtHandler = 0;
static BOOL NSExceptionLogging = NO;

NSUncaughtExceptionHandler *
NSGetUncaughtExceptionHandler(void)
{
    return NSUncaughtHandler;
}

void
NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler)
{
    NSUncaughtHandler = handler;
}

/*	Transfers `exception` to the innermost active handler.  The handler is
	popped here, not by NS_HANDLER: the macro only calls
	_NSRemoveHandler2 on the path where the body completed normally, so
	the raise path has to unlink it before transferring or the dead frame
	stays on the chain.

	_NSSETJMP resolves to _setjmp on this platform (NSException.h), so the
	transfer must be _longjmp -- pairing it with longjmp is undefined.
	See the hosting probe note for stage 2b.

	With no handler active the exception is uncaught: the installed
	handler gets it if there is one, and otherwise the process reports and
	stops, hanging instead of exiting when NSHangOnUncaughtException asks
	it to.  */
void
_NSRaiseError(NSException *exception)
{
    NSHandler2 *handler;

    if (exception == nil)
        return;

    handler = NSExceptionHandlerStack;

    if (handler == 0) {
        if (NSUncaughtHandler != 0) {
            (*NSUncaughtHandler)(exception);
            /*  A handler that returns has declined to stop the process;
                fall through to the default treatment below.  */
        }
        NSLog(@"*** Uncaught exception: %@ -- %@",
              [exception name], [exception reason]);
        if (NSHangOnUncaughtException) {
            for (;;)
                ;
        }
        abort();
    }

    NSExceptionHandlerStack = (NSHandler2 *)handler->_others;
    handler->_exception = exception;
    _longjmp(handler->_state, 1);
}
```

- [ ] **Step 4: Implement the class**

Replace the two `@implementation` blocks' TODO bodies in `NSException.m`:

```objc
@implementation NSException

+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo
{
    return [[[self allocWithZone:NULL] initWithName:name
                                             reason:reason
                                           userInfo:userInfo] autorelease];
}

/*	userInfo is retained, not copied: NSDictionary is stage 4 and nothing
	here needs dictionary behaviour, only ownership.  Recorded in
	divergences.md.  */
- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo
{
    self = [super init];
    name = [aName retain];
    reason = [aReason retain];
    userInfo = [aUserInfo retain];
    reserved = 0;
    return self;
}

- (id)init
{
    return [self initWithName:nil reason:nil userInfo:nil];
}

- (void)dealloc
{
    [name release];
    [reason release];
    [userInfo release];
    [super dealloc];
}

- (NSString *)name      { return name; }
- (NSString *)reason    { return reason; }
- (NSDictionary *)userInfo { return userInfo; }

- (void)raise
{
    _NSRaiseError(self);
}

/*	Compares by name and reason rather than by identity.  Both are this
	stage's NXConstantString-shaped records, which implement no
	-isEqual:, so the comparison goes through NSExceptionStringsEqual
	above.  */
- (BOOL)isEqual:(id)object
{
    NSException *other;

    if (self == object)
        return YES;
    if (object == nil || ((NSException *)object)->isa != isa)
        return NO;

    other = (NSException *)object;
    return NSExceptionStringsEqual(name, other->name) &&
           NSExceptionStringsEqual(reason, other->reason);
}

- (NSString *)description
{
    return reason;
}

/*	Turns logging of every raise on or off.  No header declares this; the
	reference carries it in NSException's class method list and keeps the
	flag in __DATA,__data.  Claimed by name in symbols.json.  */
+ (void)_enableLogging:(BOOL)flag
{
    NSExceptionLogging = flag;
}

@end

@implementation NSException (NSExceptionRaisingConveniences)

+ (void)raise:(NSString *)name format:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    [self raise:name format:format arguments:arguments];
    va_end(arguments);
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)argList
{
    _NSRaiseError([self exceptionWithName:name
                                   reason:_NSExceptionReasonFromFormat(format, argList)
                                 userInfo:nil]);
}

@end
```

Every helper this block uses — `NSExceptionStringsEqual`,
`_NSExceptionStringBytes`, `_NSExceptionReasonFromFormat` — was written in
Step 3. Do not send `-isEqual:` to a string anywhere in this file; nothing
implements it in this stage.

- [ ] **Step 5: Run the test and make it pass**

Rebuild and run.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSException.m src/Kits/Foundation/reconstruction/tests/test_exception.m
git commit -m "Foundation: reconstruct NSException and the raise path"
```

---

### Task 10: `_NSMethodExceptionProem`, `NSAssertionHandler`, and the coder methods

**Files:**
- Modify: `src/Kits/Foundation/NSException.m`
- Modify: `src/Kits/Foundation/reconstruction/tests/test_exception.m`

**Interfaces:**
- Consumes: Tasks 2, 7, 9.
- Produces: `id _NSMethodExceptionProem(id object, SEL aSelector)`; the `NSAssertionHandler` class; `NSException`'s four coder/copy methods.

- [ ] **Step 1: Understand what `_NSMethodExceptionProem` must return**

Stage 2a established this from the reference's own format strings: `NSObject.m` and `NSProxy.m` both build their diagnostics as `@"%@: selector not recognized"`, and the `%@` proves the proem is an **object**, not a `const char *`. Its text is `-[Class selector]` or `+[Class selector]` depending on whether the receiver is a class object.

Stage 2a's `extern` declaration in `NSObject.m` line 28 is `extern id _NSMethodExceptionProem(id object, SEL aSelector);` — match it exactly.

- [ ] **Step 2: Write the failing test**

Append to `test_exception.m` and call from `main`:

```objc
extern id _NSMethodExceptionProem(id object, SEL aSelector);

static void test_method_exception_proem_names_an_instance_method(void)
{
    id object = [[NSObject alloc] init];
    id proem = _NSMethodExceptionProem(object, @selector(hash));

    CHECK(proem != nil);
    CHECK(strcmp(TestStringBytes(proem), "-[NSObject hash]") == 0);
    [object release];
}

static void test_method_exception_proem_names_a_class_method(void)
{
    id proem = _NSMethodExceptionProem([NSObject class], @selector(alloc));

    CHECK(proem != nil);
    CHECK(strcmp(TestStringBytes(proem), "+[NSObject alloc]") == 0);
}

static void test_assertion_handler_is_a_shared_instance(void)
{
    id first = [NSAssertionHandler currentHandler];
    id second = [NSAssertionHandler currentHandler];

    CHECK(first != nil);
    CHECK(first == second);
}

static void test_a_failing_NSAssert_raises(void)
{
    int caught = 0;

    NS_DURING
        NSAssert(1 == 2, @"one is not two");
        CHECK(0);  /* unreachable */
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_a_passing_NSAssert_does_not_raise(void)
{
    int caught = 0;

    NS_DURING
        NSAssert(1 == 1, @"one is one");
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 0);
}
```

`NSAssert` expands to `[NSString stringWithCString:__FILE__]`, which this stage does not implement. Add a file-static `NSString` category in the **test** supplying `+stringWithCString:` over the same record layout, so the macro links without `link_stubs.m`'s aborting stub:

```objc
/*  NSAssert's expansion calls +[NSString stringWithCString:] for __FILE__.
    Stage 2b has no NSString; this gives the macro something that works
    over the same NXConstantString-shaped records the rest of the stage
    uses, so the assert path is testable here.  Stage 3 removes it.  */

extern struct objc_class _NSConstantStringClassReference;

@interface TestAssertString : NSObject
+ (id)stringWithCString:(const char *)bytes;
@end

@implementation TestAssertString

+ (void)initialize {}

+ (id)stringWithCString:(const char *)bytes
{
    struct { Class isa; char *c_string; unsigned int len; } *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = malloc(sizeof(*record) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (id)record;
}

@end

/*  NSAssert names NSString literally, so point that name at the class
    above for the duration of this test file only.  */
#define NSString TestAssertString
```

Place the `#define` immediately above the two assert tests and `#undef NSString` immediately below them, so it cannot leak into the rest of the file. Add `#include <stdlib.h>` for `malloc`.

Delete `link_stubs.m`'s stub `NSString` class once this compiles — its `+stringWithCString:length:` stub is what the real `NSAssert` path would otherwise abort in.

- [ ] **Step 3: Run it and watch it fail**

Rebuild as in Task 7 Step 3.
Expected: link error for `_NSMethodExceptionProem` (its stub is still in `link_stubs.m` — remove it in this step) and failures from the `NSAssertionHandler` TODO stubs.

- [ ] **Step 4: Implement**

```objc
/*	"-[NSObject hash]" or "+[NSObject alloc]": the prefix every method
	diagnostic in this framework opens with.  Returns an object, not a
	C string -- NSObject.m and NSProxy.m both substitute it with %@,
	which is what pins the return type.

	A class object is its own isa's instance, so a receiver whose isa is
	a metaclass is a class and takes the + form.  CLS_META is the
	metaclass bit in struct objc_class's info field (objc-class.h).  */
id
_NSMethodExceptionProem(id object, SEL aSelector)
{
    char buffer[256];
    const char *className;
    BOOL isClassMethod;

    if (object == nil)
        return _NSExceptionStringWithCString("-[nil (null)]");

    isClassMethod = ((((Class)object)->isa->info & CLS_META) != 0);
    className = ((Class)object)->isa->name;
    if (isClassMethod)
        className = ((Class)object)->name;

    sprintf(buffer, "%c[%s %s]",
            isClassMethod ? '+' : '-',
            className,
            (aSelector == NULL) ? "(null)" : sel_getName(aSelector));

    return _NSExceptionStringWithCString(buffer);
}

/*	One shared handler for the whole process.  The reference keeps the
	current handler in the calling thread's -threadDictionary (NSThread.m
	and NSDictionary.m, neither reconstructed here), substituted with a
	process-global for the same reason this file's handler stack is.
	The class's single ivar is _reserved, so there is no per-instance
	state to keep either way.  Recorded in divergences.md.  */
static NSAssertionHandler *NSCurrentAssertionHandler = nil;

@implementation NSAssertionHandler

+ (NSAssertionHandler *)currentHandler
{
    if (NSCurrentAssertionHandler == nil)
        NSCurrentAssertionHandler = [[self allocWithZone:NULL] init];
    return NSCurrentAssertionHandler;
}

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...
{
    va_list arguments;
    NSString *reason;

    va_start(arguments, format);
    reason = _NSExceptionReasonFromFormat(format, arguments);
    va_end(arguments);

    NSLog(@"*** Assertion failure in %@, %@:%d",
          _NSMethodExceptionProem(object, selector), fileName, line);

    _NSRaiseError([NSException exceptionWithName:NSInternalInconsistencyException
                                          reason:reason
                                        userInfo:nil]);
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...
{
    va_list arguments;
    NSString *reason;

    va_start(arguments, format);
    reason = _NSExceptionReasonFromFormat(format, arguments);
    va_end(arguments);

    NSLog(@"*** Assertion failure in %@, %@:%d", functionName, fileName, line);

    _NSRaiseError([NSException exceptionWithName:NSInternalInconsistencyException
                                          reason:reason
                                        userInfo:nil]);
}

@end
```

Add `#import <objc/objc-runtime.h>` and `#import <objc/objc-class.h>` to `NSException.m` for `CLS_META` and `sel_getName`; confirm the header that actually defines `CLS_META` in this tree before importing.

- [ ] **Step 5: Add the four untestable methods**

Gate 1 requires their selectors with exact type encodings. Write them against the real declared APIs — `NSCoder.h`, `NSObject.h`'s `NSCopying` — and mark each in `divergences.md`'s untested table:

```objc
/*	NSCoding and NSCopying.  Written against the declared APIs; NOT
	exercised by any test in this stage, because NSCoder is stage 2c,
	NSPortCoder is stage 8, and copying userInfo needs NSDictionary from
	stage 4.  Listed in divergences.md's untested table with the stage
	that unblocks each.  */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:name];
    [aCoder encodeObject:reason];
    [aCoder encodeObject:userInfo];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    name = [[aDecoder decodeObject] retain];
    reason = [[aDecoder decodeObject] retain];
    userInfo = [[aDecoder decodeObject] retain];
    reserved = 0;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[NSException allocWithZone:zone] initWithName:name
                                                   reason:reason
                                                 userInfo:userInfo];
}

- (id)replacementObjectForPortCoder:(NSCoder *)aCoder
{
    return self;
}
```

Add `#import <Foundation/NSCoder.h>` — check the exact selector spellings in that header before writing, and correct the calls above to match what it actually declares.

- [ ] **Step 6: Run the test and make it pass**

Rebuild and run `test_exception`.
Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 7: Commit**

```bash
git add src/Kits/Foundation/NSException.m src/Kits/Foundation/reconstruction/tests/test_exception.m src/Kits/Foundation/reconstruction/tests/link_stubs.m
git commit -m "Foundation: reconstruct the method diagnostic proem and NSAssertionHandler"
```

---

### Task 11: Retire the stubs and re-verify stage 2a

Spec §3.4 step 5 and §5.2. **This is the task most likely to look like it is breaking things while it works.**

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/tests/link_stubs.m`
- Modify: `src/Kits/Foundation/NSObject.m`
- Modify: `src/Kits/Foundation/NSProxy.m`
- Modify: the five 2a test files, only where an assertion depended on stub behaviour.

**Interfaces:**
- Consumes: every symbol Tasks 2–10 made real.
- Produces: a `link_stubs.m` holding only symbols no reconstructed module supplies.

- [ ] **Step 1: Move the two null-selector helpers into their own modules**

Spec §2.2: `_NSObjectRaiseNullSelectorException` and `_NSProxyRaiseNullSelectorException` are **`local`** in the reference, not external. Stage 2a wrongly declared both `extern`. Verify first:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import load_image
p, d = load_image('C:/Users/raynorpat/Downloads/test/Foundation-i386')
for s in d['symbols']:
    if 'RaiseNullSelector' in s['name']:
        print(s['name'], s['binding'], s['section'])
"
```
Expected: every one `local __TEXT,__text`.

In `src/Kits/Foundation/NSObject.m`, delete line 29's `extern void _NSObjectRaiseNullSelectorException(id object, SEL aSelector);` and add a `static` definition above its first use:

```objc
/*	Raises for a NULL selector handed to the performSelector: family.
	Static: the reference keeps this local to NSObject.m, and NSProxy.m
	has its own separately named counterpart rather than sharing this one
	-- confirmed from the reference's symbol table, where both are
	`local`.  Stage 2a declared both extern and stubbed them; corrected
	here.  */
static void
_NSObjectRaiseNullSelectorException(id object, SEL aSelector)
{
    [NSException raise:NSInvalidArgumentException
                format:@"%@: null selector", _NSMethodExceptionProem(object, aSelector)];
}
```

Add `extern id _NSMethodExceptionProem(id object, SEL aSelector);` if it is not already declared in the file — stage 2a already declares it at line 28.

Do the same in `src/Kits/Foundation/NSProxy.m` for `_NSProxyRaiseNullSelectorException`, deleting its line 26 `extern` declaration.

- [ ] **Step 2: Delete each remaining retired stub, one at a time**

For each symbol below, in this order: delete it from `link_stubs.m`, rebuild and run **all five** 2a suites plus both 2b suites, and only then move to the next. Retiring them one at a time is what makes a failure name its own cause.

1. `_NSObjectRaiseNullSelectorException`
2. `_NSProxyRaiseNullSelectorException`
3. `_NSMethodExceptionProem` (if not already removed in Task 10)
4. The `NSTestRaiseEnv` / `NSTestExpectingRaise` / `NSTestRaiseMessage` machinery and `NSTestCaptureRaiseMessage` — a real `NSException` means the 2a suites can use `NS_DURING`/`NS_HANDLER` instead

**Expect assertions to change.** The stubs `abort()`; the real implementations raise. Any 2a test that armed `NSTestExpectingRaise` and `setjmp`ed around a call is rewritten to wrap the call in `NS_DURING`/`NS_HANDLER` and assert on `localException`'s name — which is strictly stronger, and is the point of the stage. A 2a test that fails for any *other* reason is a real regression: stop and report it.

- [ ] **Step 3: Confirm what remains**

`link_stubs.m` should still hold, and only hold: `unimplemented`, `NSKeepAllocationStatistics`, `_NSConstantStringClassReference`, `NSRecordAllocationEvent`, `NSMethodSignature`, `NSZombieEnabled`, `NSDeallocateZombies`, `_NSInitializePlatform`, `NSStringFromStack`. Update its header comment to say which stage owns each remaining symbol.

- [ ] **Step 4: Run every suite**

Build and run all seven: `test_zone`, `test_refcount`, `test_object`, `test_proxy`, `test_pool`, `test_objcruntime`, `test_exception`, each with `NSException.m NSObjCRuntime.m` added to its link line.

Expected: seven times `PASSED: 0 failure(s)`.

- [ ] **Step 5: Commit**

```bash
git add src/Kits/Foundation/NSObject.m src/Kits/Foundation/NSProxy.m src/Kits/Foundation/reconstruction/tests/link_stubs.m src/Kits/Foundation/reconstruction/tests/test_object.m src/Kits/Foundation/reconstruction/tests/test_proxy.m src/Kits/Foundation/reconstruction/tests/test_autoreleasepool.m src/Kits/Foundation/reconstruction/tests/test_zone.c src/Kits/Foundation/reconstruction/tests/test_refcount.c
git commit -m "Foundation: retire the exception link stubs and localise the null-selector helpers"
```

---

### Task 12: ABI baselines, evidence and the stage gates

**Files:**
- Create: `src/Kits/Foundation/reconstruction/abi/NSException.json`, `abi/NSObjCRuntime.json`
- Create: `src/Kits/Foundation/reconstruction/exceptions-runtime/{ledger,source-map}.json`
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`, `ownership.json`, `divergences.md`
- Modify: `tools/binrecon/profiles/` — a 2b profile, modelled on `foundation-i386-object-core.json`

**Interfaces:**
- Consumes: everything.
- Produces: the stage's committed evidence.

- [ ] **Step 1: Claim every C symbol in `symbols.json`**

Add two keys. Use the **symbol** spelling (mangled), not the C identifier:

```json
 "NSObjCRuntime.m": [
  "_NSStringFromSelector", "_NSSelectorFromString", "_NSClassFromString",
  "_NSStringFromClass", "_NSGetSizeAndAlignment", "__NSGetSizeAndAlignment",
  "_NSLog", "_NSLogv", "__NSBasicStdErrLog",
  "__NSIMPForSelector", "__NSMethodDescriptionForSelector",
  "__NSClassConformsToProtocol"
 ],
 "NSException.m": [
  "__NSAddHandler2", "__NSRemoveHandler2", "__NSExceptionObjectFromHandler2",
  "__NSExceptionObjectFromHandler", "__NSAddAltHandler2", "__NSRemoveAltHandler2",
  "__NSClearExceptionStack", "__NSExceptionHandlerCount", "__NSRaiseError",
  "__NSMethodExceptionProem",
  "_NSGetUncaughtExceptionHandler", "_NSSetUncaughtExceptionHandler",
  "_NSHangOnUncaughtException",
  "_NSGenericException", "_NSRangeException", "_NSInvalidArgumentException",
  "_NSInternalInconsistencyException", "_NSMallocException",
  "_NSObjectInaccessibleException", "_NSObjectNotAvailableException",
  "_NSDestinationInvalidException", "_NSPortTimeoutException",
  "_NSInvalidSendPortException", "_NSInvalidReceivePortException",
  "_NSPortSendException", "_NSPortReceiveException", "_NSOldStyleException"
 ]
```

Drop `__NSIMPForSelector`, `__NSMethodDescriptionForSelector` and `__NSClassConformsToProtocol` if Task 5 was skipped.

- [ ] **Step 2: Generate the ABI baselines**

```bash
BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi \
  --profile tools/binrecon/profiles/foundation-i386-exceptions-runtime.json \
  --symbols src/Kits/Foundation/reconstruction/symbols.json \
  --module NSException.m --module NSObjCRuntime.m \
  --output src/Kits/Foundation/reconstruction/abi
```

**Generate, never hand-edit.** If the output surprises you, the reconstruction is wrong, not the evidence.

Expected: `wrote .../NSException.json` and `wrote .../NSObjCRuntime.json`, plus `not emitting` lines for the modules this invocation is not producing.

- [ ] **Step 3: Build i386 objects and run Gate 1**

Compile all ten modules i386 (the eight from stage 2a plus `NSException.m` and `NSObjCRuntime.m`) and check the whole committed `abi/` directory at once. On the guest, write and run `/tmp/build-abi-2b.sh`:

```sh
#!/bin/sh
cd /build/source/src/Kits/Foundation-2b/Foundation || exit 1
rm -rf /tmp/abi2b
mkdir -p /tmp/abi2b
INC="-I.. -I/System/Library/Frameworks/System.framework/Headers"
rc=0
for m in NSZone NSObject NSProxy NSAutoreleasePool NSPrivate \
         NSGeometry NSRange NSDecimal NSException NSObjCRuntime; do
    echo "== $m"
    cc -c -arch i386 $INC -o /tmp/abi2b/$m.o $m.m 2>&1 || rc=1
done
echo "COMPILE_STATUS=$rc"
ls -l /tmp/abi2b
```

Expected: `COMPILE_STATUS=0` and ten objects.

Fetch them into a scratch directory outside the repo, then:

```bash
O=C:/Users/raynorpat/AppData/Local/Temp/foundation-2b-abi
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi-check \
  --abi-dir src/Kits/Foundation/reconstruction/abi \
  --built "NSZone.m=$O/NSZone.o" \
  --built "NSObject.m=$O/NSObject.o" \
  --built "NSProxy.m=$O/NSProxy.o" \
  --built "NSAutoreleasePool.m=$O/NSAutoreleasePool.o" \
  --built "NSPrivate.m=$O/NSPrivate.o" \
  --built "NSGeometry.m=$O/NSGeometry.o" \
  --built "NSRange.m=$O/NSRange.o" \
  --built "NSDecimal.m=$O/NSDecimal.o" \
  --built "NSException.m=$O/NSException.o" \
  --built "NSObjCRuntime.m=$O/NSObjCRuntime.o"
```

Note that `$O` inside a single command is fine; a Windows-side shell may refuse a command whose operands are computed across several statements, in which case write the ten paths out in full.

Expected: `abi-check: ABI matches`, exit 0.

**If it reports an unexpected exported symbol, claim it in `symbols.json` and regenerate — do not make it `static`.** If it reports a missing symbol, check the underscore rule first (Global Constraints): the usual cause is a C identifier spelled with one underscore too many or too few.

- [ ] **Step 4: Run the analysis and produce Gate 3's evidence**

**Sub-step 4a — the scoped profile.** Create `tools/binrecon/profiles/foundation-i386-exceptions-runtime.json` by copying `foundation-i386-object-core.json`. Keep every field except `analysis_scope` and `output_dir`: set `output_dir` to `../out/foundation-i386-exceptions-runtime`, and replace `analysis_scope` with the ranges this emits:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon module-scope \
  --profile tools/binrecon/profiles/foundation-i386-object-core.json \
  --module NSException.m --module NSObjCRuntime.m \
  --symbols src/Kits/Foundation/reconstruction/symbols.json
```

Commit this profile — it is evidence, the same as stage 2a's `foundation-i386-object-core.json`.

**Sub-step 4b — the rebuilt artifact.** `binrecon compare` needs an analysis of *our* build alongside the reference's, and `binrecon analyze` produces both from one profile when that profile carries a `"rebuilt"` artifact (`profile-v1.json`'s schema, same shape as `"reference"`: `{"path": ..., "expected_size": ..., "expected_sha256": ...}`). Build one relocatable i386 object containing both this stage's modules together, matching how the reference itself packs `NSException.m` and `NSObjCRuntime.m` into one image:

```bash
cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers \
   -o /tmp/foundation-2b-rebuilt.o NSException.m NSObjCRuntime.m
```

(a single `cc -c` with two `.m` inputs and one `-o` fails — compile each to its own object, then combine with `ld -r -arch i386 -o /tmp/foundation-2b-rebuilt.o NSException.o NSObjCRuntime.o`, or check whether this toolchain's `cc -c` accepts multiple sources with `-o` for a single relocatable output; confirm on the guest before relying on either).

Fetch the combined object to the Windows side, compute its size and SHA-256, and add a `"rebuilt"` block to **an uncommitted working copy** of the 2b profile (the object's local path has no meaning outside this run, so it must never be committed):

```bash
python -c "
import hashlib, json, pathlib
obj = pathlib.Path('C:/Users/raynorpat/AppData/Local/Temp/foundation-2b-abi/foundation-2b-rebuilt.o')
data = obj.read_bytes()
profile = json.loads(pathlib.Path('tools/binrecon/profiles/foundation-i386-exceptions-runtime.json').read_text())
profile['rebuilt'] = {'path': str(obj), 'expected_size': len(data), 'expected_sha256': hashlib.sha256(data).hexdigest().upper()}
pathlib.Path('/tmp/foundation-2b-profile-with-rebuilt.json').write_text(json.dumps(profile, indent=1))
"
```

**Sub-step 4c — analyze, in the foreground.** A background `analyze` is killed when the turn ends, leaving stale locks and no published result:

```bash
BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile /tmp/foundation-2b-profile-with-rebuilt.json
```

Expected: `complete: true`, and both `tools/binrecon/out/foundation-i386-exceptions-runtime/published/analysis-reference-ida.json` and `analysis-rebuilt-ida.json` populated (the `output_dir` set in sub-step 4a, resolved relative to the profiles directory — confirm the actual path from the command's own output rather than assuming).

**Sub-step 4d — compare, source-map, ledger.** `--reference-analysis` and `--rebuilt-analysis` take the two paths sub-step 4c produced; `--profile` here is the **committed** profile (without the local `"rebuilt"` path, which has no meaning to anyone re-running this later):

```bash
R=src/Kits/Foundation/reconstruction
PUB=tools/binrecon/out/foundation-i386-exceptions-runtime/published

BINRECON_REFERENCE=C:/Users/raynorpat/Downloads/test/Foundation-i386 \
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon compare \
  --profile tools/binrecon/profiles/foundation-i386-exceptions-runtime.json \
  --reference-analysis $PUB/analysis-reference-ida.json \
  --rebuilt-analysis $PUB/analysis-rebuilt-ida.json \
  --output $R/exceptions-runtime/ledger.json

PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis $PUB/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/Foundation-i386" \
  --source-dir src/Kits/Foundation --repo-root . --objc-methods \
  --ownership $R/ownership.json \
  --output $R/exceptions-runtime/source-map.json
```

`ledger` is driven one entry at a time by `binrecon ledger` transitions against `$R/exceptions-runtime/ledger.json`, exactly as stage 2a's Task 11 did for `object-core/ledger.json`; run `binrecon ledger --help` for the transition flags. Gate 3 is evidence only — instruction divergence between a relocatable-object excerpt and the reference's linked, profile-guided layout is expected and does not block the stage; review every entry and disposition it. **Budget ~1 s per ledger entry** — that figure was measured in stage 2a (189 s for 193 entries) and is the basis for this stage's estimate.

- [ ] **Step 5: Write `divergences.md`'s 2b section**

It must record, at minimum:

- The three substitutions (§3.2) and why each is where it is.
- `NSLog`'s provisional formatter (§5.4) — say plainly that it is provisional so stages 3–9 do not build on it unknowingly.
- The nine out-of-stage exception constants with their declaring header and stage (spec acceptance criterion 10).
- Stage 2a's `extern`-versus-`local` correction for the two null-selector helpers (§2.2), and the note that `abi-check` does not catch this class of error because it compares only defined external symbols.
- The `_NSGetSizeAndAlignment` public/private pair sharing an implementation.
- `NSDetailedDescription`'s unconfirmed output text.
- The untested table: the four coder/copy methods, the two Alt handlers, `_NSExceptionObjectFromHandler`, and anything else no test reaches.

- [ ] **Step 6: Final verification**

Run, and record each result:

1. `abi-check` over all ten modules → `ABI matches`, exit 0
2. All seven test suites → `PASSED: 0 failure(s)`
3. `binrecon source-map` → every 2b function mapped, `by_module` accounting for all
4. Full binrecon suite → `804 passed, 4 skipped`
5. `git diff --name-only <stage-2b-base>..HEAD -- 'src/Kits/Foundation/*.h'` → **empty**
6. `symbol-audit` → the unclaimed count has fallen by the number of functions this stage claimed; record the new figure in the ledger

- [ ] **Step 7: Clean up the guest and commit**

```bash
# on the guest
rm -rf /build/source/src/Kits/Foundation-2b /tmp/abi2b
```

```bash
git add src/Kits/Foundation/reconstruction/abi/NSException.json src/Kits/Foundation/reconstruction/abi/NSObjCRuntime.json src/Kits/Foundation/reconstruction/exceptions-runtime/ledger.json src/Kits/Foundation/reconstruction/exceptions-runtime/source-map.json src/Kits/Foundation/reconstruction/symbols.json src/Kits/Foundation/reconstruction/ownership.json src/Kits/Foundation/reconstruction/divergences.md tools/binrecon/profiles/foundation-i386-exceptions-runtime.json
git commit -m "Foundation: record stage 2b parity evidence and divergences"
```
