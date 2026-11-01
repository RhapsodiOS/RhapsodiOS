# Foundation stage 2b: exceptions and runtime

**Status:** design approved, plan not yet written.
**Programme spec:** [2026-07-26-foundation-i386-reconstruction-design.md](2026-07-26-foundation-i386-reconstruction-design.md).
**Predecessor:** [2026-07-26-foundation-stage2a-object-core-design.md](2026-07-26-foundation-stage2a-object-core-design.md) (complete; three gates passed, whole-branch review applied).

**Reference of record:** the extracted thin i386 slice at
`C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1630488**,
SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**.
Never point tooling at the fat container.

## Motivation

Stage 2a reconstructed the object core, but every path in it that *raises* ends
in a stub. `reconstruction/tests/link_stubs.m` currently supplies a fake
`NSException`, a fake `NSLog`, and fake `_NSMethodExceptionProem`,
`_NSObjectRaiseNullSelectorException` and `_NSProxyRaiseNullSelectorException`,
each of which `abort()`s. So `-[NSObject doesNotRecognizeSelector:]`,
`-[NSProxy forward::]`, `-[NSAutoreleasePool retain]` and a dozen other methods
are verified only as far as "an aborting stub was reached". Their actual
observable behaviour -- which exception name, which reason text, whether the
handler stack unwinds -- is untested.

This stage makes that machinery real. Its value is therefore not only its own
1.3 KB of methods and 4 KB of C functions, but the retroactive strengthening of
the five suites stage 2a already has.

## 1. Scope

### 1.1 Target

Two modules the reference's `__OBJC,__module_info` names: `NSException.m` and
`NSObjCRuntime.m`.

| Class / category | `instance_size` | Ivars | Methods |
| --- | --- | --- | --- |
| `NSException`, superclass `NSObject` | 20 | `name`@4, `reason`@8, `userInfo`@12, `reserved`@16 | 13 instance + 4 class |
| `NSAssertionHandler`, superclass `NSObject` | 8 | `_reserved`@4 | 2 instance + 1 class |
| `Protocol (NSDetailedDescription)` | — | — | 1 instance |
| `NSObject (NSDetailedDescription)` | — | — | 1 class |

Method `__text` measures **1,264 bytes**. `NSObjCRuntime.m`'s weight is entirely
in its C functions.

`NSException`'s class methods include `+_enableLogging:`, which no header
declares; its instance methods include `-replacementObjectForPortCoder:`, a
Distributed Objects hook. Both are part of the ABI and are reconstructed.

**Twenty exported C functions, 4,076 bytes.** Twelve are header-declared:

- `NSObjCRuntime.h`: `NSStringFromSelector`, `NSSelectorFromString`,
  `NSClassFromString`, `NSStringFromClass`, `NSGetSizeAndAlignment`, `NSLog`,
  `NSLogv`
- `NSException.h`: `_NSAddHandler2`, `_NSRemoveHandler2`,
  `_NSExceptionObjectFromHandler2`, `NSGetUncaughtExceptionHandler`,
  `NSSetUncaughtExceptionHandler`

Eight are undeclared private exports, the category §5.4 of the 2a spec named and
the programme spec's §3.1.1 sized: `_NSAddAltHandler2`, `_NSRemoveAltHandler2`,
`_NSClearExceptionStack`, `_NSExceptionHandlerCount`,
`_NSExceptionObjectFromHandler` (no `2`), `_NSGetSizeAndAlignment` (a private
variant alongside the public one), `_NSMethodExceptionProem`, `_NSRaiseError`.

**Data symbols.** Fourteen `NSString * const` exception names declared by
`NSException.h`, all external in `__DATA,__const`, plus
`NSHangOnUncaughtException`, external in `__DATA,__data`.

### 1.2 Out of scope

- `NSFault`, moved to stage 2c by the programme spec's §3.1.1. It is a third
  root class whose faulting path needs `NSInvocation`.
- The nine further exception-name constants the reference exports that
  `NSException.h` does not declare (§2.1).
- Real `NSString`, `NSDictionary`, `NSCoder`, `NSPortCoder` behaviour (§3.2).
- The `NSAssert`/`NSCAssert` macro families are header-only and already present;
  this stage supplies the `NSAssertionHandler` they call, not the macros.

## 2. Findings that shaped this design

### 2.1 The reference exports 23 exception names, not 14

`NSException.h` declares fourteen. The reference's `__DATA,__const` holds
**twenty-three** external exception-name constants. The extra nine are declared
in other stages' headers:

| Constant | Declaring header | Stage |
| --- | --- | --- |
| `NSCharacterConversionException`, `NSParseErrorException` | `NSString.h` | 3 |
| `NSDecimalNumberExactnessException`, `…OverflowException`, `…UnderflowException`, `…DivideByZeroException` | `NSDecimalNumber.h` | 5 |
| `NSFileHandleOperationException` | `NSFileHandle.h` | 6 |
| `NSInconsistentArchiveException` | `NSArchiver.h` | 6 |
| `NSFailedAuthenticationException` | `NSConnection.h` | 8 |

The project's default rule attributes a symbol by its declaring header, so these
belong to those stages, not to 2b -- even though the reference may well define
them all in `NSException.m`. Data symbols carry no module attribution in the
image, so there is no evidence to overturn the default with. 2b claims its
fourteen and records the other nine in `divergences.md` against their stage, so
a later stage cannot silently omit them.

### 2.2 Two symbols stage 2a exported that the reference keeps local

`_NSObjectRaiseNullSelectorException` and `_NSProxyRaiseNullSelectorException`
are **`local`** in the reference's symbol table, not external -- they are
`static` functions inside `NSObject.m` and `NSProxy.m`. Stage 2a declared both
`extern` in those modules and defined them in `link_stubs.m`.

That is a real divergence, and it is the exact inverse of the mistake 2a's Gate 1
already recorded: there the fix was to stop hiding an exported symbol; here the
fix is to stop exporting a hidden one. Because this stage retires those stubs
anyway, it also corrects the linkage: each becomes a `static` function in its own
module. `abi-check` does not currently catch this class of error -- it compares
the union of *defined external* symbols, so a symbol that should be local and
is absent from our object looks identical to one correctly absent. The check
that would catch it is the reference's `local`/`external` binding, which no gate
reads today.

The reference keeps `_NSFaultRaiseNullSelectorException` local in the same way;
stage 2c inherits that note.

### 2.3 `NSDetailedDescription` is declared nowhere

Both category methods -- `-[Protocol detailedDescription]` and
`+[NSObject detailedDescriptionForClass:]` -- appear in the reference's
`__OBJC` metadata but in no header anywhere in the tree. Like `NSFault`, they
are reachable by no header-based attribution rule and must be claimed by name in
`reconstruction/symbols.json`. Adding a header is forbidden by the programme's
hard constraint, so they are declared locally in `NSObjCRuntime.m`.

### 2.4 The handler stack is the stage's real risk

`NS_DURING`/`NS_HANDLER` are `setjmp`-based macros in `NSException.h`, and on
this platform `_NSSETJMP` resolves to `_setjmp`. Everything behavioural in this
stage depends on that unwinding correctly on the ppc guest: if a `longjmp` back
into a handler frame does not restore the stack as the macros assume, no test of
raising is meaningful. This is the same shape as 2a's runtime-hosting gate, and
it gets the same treatment -- it runs first, before any reconstruction.

### 2.5 Carried forward from stage 2a

- Two builds, two architectures. Test binaries link **native ppc** with no
  `-arch` flag; objects for `abi-check` are **i386, compile-only**.
- The guest login shell is tcsh; put commands in a `.sh` file and run `sh`.
- Gate 3 (instruction comparison) is evidence only, and an excerpt rebuild does
  not positionally correlate against the reference's profile-guided layout.
- Ledger review costs ~0.98 s/entry.

## 3. Design

### 3.1 Acceptance bar

Unchanged from the programme spec. Gate 1 (ABI) and Gate 2 (behaviour) are
pass/fail; Gate 3 (instruction comparison) is evidence.

### 3.2 Three substitutions, each with precedent

**The handler stack is process-global, not per-thread.** `NSHandler2` carries a
`_thread` field and the reference keys the stack per thread through
`_NSCurrentThread()`. `NSThread.m` is stage 7. This is the same substitution
`NSAutoreleasePool.m` makes for its pool stack and `NSZone.m` makes for
`_NSRefCountLock`, for the same reason, and every test in this stage runs
unthreaded.

**Strings are compiler-emitted `NXConstantString`.** The fourteen exception
names become `@"..."` literals, which gcc 2.7.2.1 emits with no `NSString`
implementation present, backed by `_NSConstantStringClassReference`.
`NSLog`/`NSLogv` format at the C level over the format's bytes and write through
`_NSBasicStdErrLog` -- a function that exists in the reference's own symbol
table, so this mirrors the reference's structure rather than working around it.
`NSStringFromClass`/`NSStringFromSelector` return literal-backed strings. Stage 3
replaces the internals; the ABI does not move.

**`userInfo` is held as an opaque `id`.** `NSDictionary` is stage 4.
`-initWithName:reason:userInfo:` retains it and `-dealloc` releases it, neither
of which needs dictionary behaviour.

### 3.3 The underscore rule

`NSException.h` declares `_NSAddHandler2` -- underscore included in the source
identifier. i386 Mach-O prepends another, so the correct symbol is
`__NSAddHandler2`, which is what the reference exports. Stage 2a shipped the
mirror-image bug (`_NSPushAutoreleasePool` written with an underscore the header
did not have, emitting `__NSPushAutoreleasePool`). The rule, stated once for
this stage and the seven that follow:

> The declaring header's spelling **is** the C identifier. Where no header
> declares the function, the reference's symbol minus one leading underscore is
> the C identifier. `abi-check` arbitrates. A mismatch is fixed by renaming the
> function, never by changing its linkage.

### 3.4 Sequencing

Ordered so that a gate failure still leaves value, and so that each step's
dependencies are already built.

1. **`setjmp` gate.** Probe `_NSSETJMP`/`longjmp` unwinding on the guest.
   Go/no-go for the stage's behavioural half. Records the verdict and, on
   success, the exact link line the later suites reuse.
2. **`NSObjCRuntime.m`.** The five introspection functions, both
   `NSGetSizeAndAlignment` variants, `NSLog`/`NSLogv`, and the two
   `NSDetailedDescription` category methods. First, because
   `_NSMethodExceptionProem` builds `-[Class sel]` text out of them.
3. **The handler stack.** `_NSAddHandler2`, `_NSRemoveHandler2`,
   `_NSExceptionObjectFromHandler2`, the two Alt variants,
   `_NSClearExceptionStack`, `_NSExceptionHandlerCount`, `_NSRaiseError`,
   `NSGet`/`NSSetUncaughtExceptionHandler`, `NSHangOnUncaughtException`.
4. **`NSException` and `NSAssertionHandler`.** The 20 methods and the 14
   exception-name constants, on top of the mechanism.
5. **Reconciliation.** Delete every retired stub from `link_stubs.m`; move
   `_NSObjectRaiseNullSelectorException` and
   `_NSProxyRaiseNullSelectorException` into `NSObject.m` and `NSProxy.m` as
   `static` (§2.2); update the 2a suites' link lines; re-run all five.

### 3.5 Artifacts

- `src/Kits/Foundation/NSException.m`, `NSObjCRuntime.m` — reconstructed,
  replacing the current 63- and 42-line TODO stubs.
- `reconstruction/abi/NSException.json`, `NSObjCRuntime.json` — committed
  baselines, generated by `binrecon abi`, never hand-edited.
- `reconstruction/tests/test_exception.m`, `test_objcruntime.m`.
- `reconstruction/tests/link_stubs.m` — materially smaller.
- `reconstruction/exceptions-runtime/{ledger,source-map}.json`.
- `reconstruction/symbols.json`, `ownership.json`, `divergences.md` — updated.

### 3.6 Reconstruction standard

Unchanged: Apple's copyright header preserved, C89 (declarations at the top of a
block, no `//` comments), variables named for what they hold, comments
explaining why. No `param_1`, `v3`, `sub_42501428` or decompiler commentary.
Read `NSObject.m` and `NSAutoreleasePool.m` for the house style.

## 4. Verification

Tests use the real `NS_DURING`/`NS_HANDLER` macros from `NSException.h`, so the
macros are themselves under test alongside the functions they call -- the
strongest evidence available for this stage. For the genuinely uncaught path,
the suite installs a handler through `NSSetUncaughtExceptionHandler` that
records the exception and `longjmp`s back to the test, so termination is
observed without the suite dying.

Four `NSException` methods cannot be honestly tested here and go into
`divergences.md`'s untested table with the stage that unblocks each:

| Method | Blocked on | Stage |
| --- | --- | --- |
| `-encodeWithCoder:`, `-initWithCoder:` | `NSCoder` | 2c |
| `-replacementObjectForPortCoder:` | `NSPortCoder` | 8 |
| `-copyWithZone:` | copying a `NSDictionary` `userInfo` | 4 |

Gate 1 requires all four selectors to exist with exact type encodings, so all
four are written against the real declared APIs -- every one of those headers is
already in the tree -- rather than left as raising stubs. This is the treatment
`NSProxy`'s forwarding methods got in 2a.

**Acceptance criteria.**

1. The `setjmp` gate has a recorded, reproducible verdict with its exact link line.
2. `binrecon abi-check` exits zero against all built objects, 2b's and 2a's alike.
3. `abi/NSException.json` and `abi/NSObjCRuntime.json` are committed,
   schema-valid, and describe the layouts in §1.1.
4. 2b's own suites pass.
5. **All five stage 2a suites still pass**, against the real modules rather than
   the retired stubs.
6. `binrecon source-map` maps every 2b function, with `by_module` accounting for
   all of them.
7. `ledger.json` is committed with every entry dispositioned.
8. binrecon's own suite passes (baseline: 804 passed, 4 skipped).
9. No header under `src/Kits/Foundation` is modified.
10. The nine out-of-stage exception constants (§2.1) are recorded in
    `divergences.md` against their stage.

## 5. Risks

### 5.1 The `setjmp` gate may fail

§2.4. Handled by sequencing: it runs first, and failure narrows the stage to
ABI-only rather than wasting reconstruction. If it fails, `NSException`'s objects
and `NSObjCRuntime`'s introspection functions are still fully testable; only the
raise/unwind paths degrade to inspection, and `divergences.md` enumerates them.

### 5.2 Retiring stubs can break stage 2a's suites in ways unrelated to 2b

Step 5 changes the link line of five working suites at once. A failure there is
ambiguous between "2b's implementation is wrong" and "2a's test depended on stub
behaviour". Mitigation: retire the stubs **one symbol at a time**, re-running the
five suites after each, so any breakage names its own cause. The real
implementations differ from the stubs by design -- the stubs `abort()`, the real
ones raise -- so some 2a assertions are expected to need updating, and that is
the point of the exercise rather than a regression.

### 5.3 `_NSRaiseError` and the Alt handlers are undocumented

Five of the eight undeclared private functions have no header, no documentation
and no obvious caller in this stage's own modules. `_NSAddAltHandler2` /
`_NSRemoveAltHandler2` in particular are probably Distributed Objects
machinery (stage 8). Their bodies must come from the disassembly alone, and
their *callers* will not exist until later stages, so behavioural testing of
them will be thin. Expect them in the untested table with a note that the
evidence is structural rather than behavioural.

### 5.4 `NSLog`'s format handling is a partial reimplementation

Formatting at C level over an `NXConstantString`'s bytes covers `%s`, `%d`,
`%x`, `%@` and friends only as far as this stage's own callers need. It is a
substitution, sized to its callers, and stage 3 replaces it. The risk is that it
quietly becomes load-bearing for stages 3-9 before then; `divergences.md` must
say plainly that it is provisional.
