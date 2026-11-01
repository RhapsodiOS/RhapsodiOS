# Foundation stage 2c: invocation, coding, and faults

**Status:** design approved, plan not yet written.
**Programme spec:** [2026-07-26-foundation-i386-reconstruction-design.md](2026-07-26-foundation-i386-reconstruction-design.md).
**Predecessors:** stage 2a (object core) and
[stage 2b](2026-09-20-foundation-stage2b-exceptions-runtime-design.md) (exceptions and
runtime) are both complete — three gates passed, whole-branch reviews applied. Stage 2b's
own ledger records that it ran on a substitute guest (an i386 QEMU image at
`127.0.0.1:2121`, not the ppc box the earlier stages used) after the original guest became
unreachable; this stage inherits whichever guest is live when it executes and records the
choice the same way.

**Reference of record:** the extracted thin i386 slice at
`C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1630488**,
SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**.
Never point tooling at the fat container.

## Motivation

Stage 2a reconstructed `-[NSObject forward::]` and `-[NSProxy forward::]` as the last
resort of Objective-C message dispatch: both unconditionally raise
`NSInternalInconsistencyException`, because the real mechanism that turns an unhandled
message into a call to `-forwardInvocation:` needs `NSInvocation` — which didn't exist
yet. `NSProxy.m`'s own comment says as much: its four type-identity methods build an
`NSInvocationBuilder`, forward through it, and rely on `-forwardInvocation:` always
raising as the current, incomplete, observable result.

That mechanism is what this stage builds. It is not a peripheral piece of the class —
until it exists, no override of `-forwardInvocation:` anywhere in this tree (or in any
future stage that proxies, defers, or distributes a message) is ever actually reached by
the runtime. Byte count alone (17.9 KB) understates this stage's importance for that
reason: it closes the single largest functional gap the object core left open.

## 1. Scope

### 1.1 Target

Four modules the reference's `__OBJC,__module_info` names, plus one undeclared private
class and two undeclared categories inside one of them:

| Class / category | `instance_size` | Ivars | Methods |
| --- | --- | --- | --- |
| `NSMethodSignature` (root: `NSObject`) | 32 | 7 (`_types`, `_nargs`, `_sizeofParams`, `_returnValueLength`, `_parmInfoP`, `_fixup`, `_reserved`) | 13 instance + 1 class |
| `NSCoder` (root: `NSObject`) | 4 | **0** | 22 instance + 0 class |
| `NSInvocation` (root: `NSObject`) | 36 | 12 (see §1.3) | 30 instance + 4 class |
| `NSInvocationBuilder` (root: none — `isa`@0) | 16 | 4 (`isa`, `targetClass`, `target`, `reserved`) | 1 instance + 3 class |
| `NSObject (NSForwardInvocation)` | — | — | 1 instance |
| `NSObject (NSIDispatchProxy)` | — | — | 1 instance |
| `NSFaultHandler` (root: `NSObject`) | 16 | 3 (`_targetClass`, `_extraData`, `_extraRefCount`) | 16 instance + 0 class |
| `NSFault` (root: none — `isa`@0) | 8 | 2 (`isa`, `_handler`) | 21 instance + 29 class |

Measured method `__text`: `NSMethodSignature` 1,468 bytes; `NSCoder` 1,300 bytes;
`NSInvocation` (incl. `NSInvocationBuilder` and both categories) 12,188 bytes; `NSFault`
(incl. `NSFaultHandler`) 2,908 bytes. Total ≈ 17.9 KB, matching the programme spec's
table.

**`NSInvocation.h` declares 12 of `NSInvocation`'s 34 methods.** The 22 undeclared:
`+_enableLogging:` (the same private logging toggle `NSException` had in stage 2b),
`+_preInitWithCoder:signature:valid:wireSignature:target:selector:argCount:`,
`+newInvocationWithCoder:`,
`-_postInitWithCoder:signature:valid:wireSignature:target:selector:argCount:`,
`-_returnValue`, `-_setArgFrame:`, `-_signatureValid`, `-decodeReturnValueWithCoder:`,
`-encodeReturnValueWithCoder:`, `-invalidate` (missing even from this era's header),
`-replacementObjectForPortCoder:` (the same Distributed Objects hook `NSException` had),
and the inherited-but-unlisted `-retain`/`-release`/`-retainCount`/`-dealloc`/
`-description`. `NSMethodSignature.h` declares 6 of 14; the other 8 are
`-_argumentInfoAtIndex:`, `-_isReturnStructInRegisters`, `-debugDescription`, and the
inherited retain/release/retainCount/description quartet. `NSCoder.h` declares all 22 of
its own selectors — the gap here is not in the header, it is in `symbols.json` (§2.3).

`NSInvocationBuilder` and the two `NSObject` categories have no header anywhere in the
tree, exactly like `NSFault`, `NSPrivate.m`'s `_NSAutoreleasedMallocMemory`, and stage
2b's `NSDetailedDescription` categories. All are claimed by name.

### 1.2 Out of scope

- `NSPortCoder`, `NSArchiver`, and the concrete coder subclasses that give `NSCoder`'s
  five abstract primitives a real backing store — stages 6 and 8.
- `NSDictionary`/`NSArray` as real collection classes — `-encodeArrayOfObjCType:…`/
  `-decodeArrayOfObjCType:…` and `-encodePropertyList:`/`-decodePropertyList` are
  implemented against this stage's own primitives and a minimal test coder, not against
  real collections (stage 4).
- `NSPortCoder`-specific behaviour behind `-replacementObjectForPortCoder:` (stage 8).
- Real threading for `NSInvocationBuilder`'s per-call construction — process-global,
  matching every substitution stages 2a/2b already made.

### 1.3 `NSInvocation`'s ivars, in full

```
returnValue        {?="type"i"value"(?)}   offset 4    tagged union: a type tag plus
                                                        the raw return bytes
argumentFrame       ^v                     offset 16   the raw marg_list/argument frame
signature           @"NSMethodSignature"   offset 20
container           @"NSMutableArray"      offset 24   -- NOT exercised: NSMutableArray
                                                        is stage 4; confirmed unused by
                                                        every method this stage tests
retainedArgs         b1  \
isInvalid            b1   \
signatureValid       b1    } one bitfield word,
retainedRet          b1    } offset 28
externalArgFrame     b1   /
unused               b3  /
refCount             b24                   offset 29   NSInvocation's OWN retain count --
                                                        NOT NSZone.m's side table
reserved             ^v                     offset 32
```

`container`'s presence and type (`NSMutableArray *`) is recorded for completeness and
ABI fidelity; no method this stage's own test suite reaches sets or reads it, so its
actual purpose (a scratch pool for autoreleased argument boxing, most likely) is
documented as unconfirmed rather than guessed at.

## 2. Findings that shaped this design

### 2.1 The forwarding mechanism, and what it supersedes

`NSObject(NSForwardInvocation)`'s `-forward::` (type encoding `q16@8:12:16^v20`, returning
`long long` — the runtime's raw forwarding calling convention) is compiled into
`NSInvocation.m`, not `NSObject.m`. `NSObject.m` and `NSProxy.m` (stage 2a) each already
define their own `-forward::` on the same selector, returning `id`
(`@16@8:12:16^v20`ish), which unconditionally raises. In this runtime, when a class and a
category both implement the same selector, the category's implementation is installed
into the method table and the class's own is not dispatched to — confirmed against the
reference's own `__OBJC` metadata, where the category's `-forward::` and each class's own
`-forward::` are distinct compiled symbols at distinct addresses, and only one can occupy
a given class's method-table slot at a time.

This means: once this stage's `NSInvocation.m` is linked into any build, **stage 2a's
`-[NSObject forward::]` and `-[NSProxy forward::]` become ABI-correct but functionally
dead** — present in the binary, correctly typed, never actually invoked. The category
builds a real `NSInvocation` from the raw argument frame the runtime hands it and calls
`-forwardInvocation:` on the receiver, which is how a subclass's override of
`-forwardInvocation:` is reached by the runtime for the first time in this reconstruction.
Neither `NSObject.m` nor `NSProxy.m` is modified — this is purely additive, the category
lives entirely in the new file.

This is disclosed in `divergences.md` as a supersession, not a bug: both root classes'
own `-forward::` remain correct reconstructions of what the reference's `NSObject.m`/
`NSProxy.m` translation units themselves contain; the category is a separate, later-
dispatched fact about the same selector, exactly as it is in the reference binary.

### 2.2 `NSCoder` is abstract by construction, not by convention

`NSCoder`'s `instance_size` is 4 — an object with no ivars beyond `isa` has nowhere to
keep any state. Its five primitive methods (`encode`/`decodeValueOfObjCType:at:`,
`encode`/`decodeDataObject`, `versionForClassName:`) have compiled bodies in the
reference despite this, which — given there is no storage for them to act on — can only
mean they raise "subclass responsibility", the same shape `NSProxy.m`'s own abstract
forwarding methods took in stage 2a. The other 17 methods (the `NSExtendedCoder` and
`NSTypedstreamCompatibility` categories, both declared in `NSCoder.h` itself) are real,
generic implementations built by calling those five primitives — `-encodeObject:`
ultimately calls `-encodeValueOfObjCType:"@" at:&object`, and so on.

Testing the 17 concrete methods needs a concrete subclass overriding the five
primitives with a real, if minimal, in-memory implementation — test-only, the same
pattern stage 2a's test helper classes already establish, and the shape any future
concrete coder (`NSArchiver`, `NSPortCoder`) will also take.

### 2.3 `NSCoder`'s only real header gap is a claim, not a divergence

`NSCoder.h` already declares `NXReadNSObjectFromCoder` (capital `NX` — a NeXT-era
survival, not a typo) as `FOUNDATION_EXPORT NSObject *NXReadNSObjectFromCoder(NSCoder
*decoder);`. `binrecon symbol-audit` reports `_NXReadNSObjectFromCoder` unclaimed (168
bytes) — it is header-declared, so this is ordinary in-scope work, claimed under
`NSCoder.m` like any other declared function, not an undeclared-private-export case.

### 2.4 The property-list/typedstream parser

`__NSParseObjectFromASCIIPropertyListOrSerialization` (748 bytes, unclaimed) is a plain C
function, so it carries no `__OBJC` module attribution the way a method would. Its name
plausibly backs two of `NSCoder.h`'s own declared methods at once: `-decodePropertyList`
(ASCII property-list text) and `-decodeNXObject` (the old NeXT typedstream format,
`NSTypedstreamCompatibility`). No other stage's spec claims it, and both call sites are
this stage's own declared surface, so it is reconstructed here and claimed under
`NSCoder.m`. This is real parsing work — an ASCII property-list grammar (dictionaries,
arrays, quoted and unquoted strings, data blocks) and the older typedstream tagged-value
format — sized at 748 bytes, not a stub.

### 2.5 `NSInvocation`'s refcount is its own, not the shared side table

The bitfield word at offset 28 (`retainedArgs`, `isInvalid`, `signatureValid`,
`retainedRet`, `externalArgFrame`, `unused`, `refCount:24`) means `-retain`/`-release`/
`-retainCount` operate on this ivar directly. `NSIncrementExtraRefCount`/
`NSDecrementExtraRefCountWasZero` (stage 2a's `NSZone.m`) are not called — confirmed by
the ivar's mere existence: a 24-bit inline counter has no reason to exist if the object
also used the external table. `NSMethodSignature` has no comparable bitfield (only an
untyped `_reserved` pointer), so its own retain/release strategy is confirmed from its
disassembly during reconstruction, not assumed to match `NSInvocation`'s.

### 2.6 `NSFault` is `NSProxy`'s open question, now answerable

Stage 2a's `NSProxy.m` reconstructed `-isKindOfClass:`, `-isMemberOfClass:`,
`-conformsToProtocol:`, and `-respondsToSelector:` as building an `NSInvocationBuilder`
and forwarding through it, with the observable result pinned only as far as
"`-forwardInvocation:` always raises, since no test exercises an override" — an
explicitly disclosed gap. With `NSInvocation` and the real forwarding mechanism
(§2.1) in place, `NSFault`'s equivalent methods (`-forwardInvocation:`,
`-methodSignatureForSelector:forFault:`, `-[NSFaultHandler shouldPerformInvocation:]`)
are the first in this programme that can be tested with a fault actually firing and
completing a real call through a live target end to end, not merely proven to raise.

### 2.7 Carried forward from stages 2a/2b

- Two builds, two architectures: test binaries link **native**, no `-arch` flag; objects
  for `abi-check` are the guest's i386 backend, compile-only.
- The underscore rule (stage 2b §3.3): the declaring header's spelling is the C
  identifier; where undeclared, the reference's symbol minus one leading underscore is.
  `abi-check` arbitrates; a mismatch is fixed by renaming, never by relinking.
- An "unexpected exported symbol" from `abi-check` means claim it, never suppress it.
- Gate 3 (instruction comparison) is evidence only.
- Ledger review costs ~1 s/entry.
- The guest that is actually reachable when this stage executes may not be the ppc box —
  confirm and record whichever one is live, the way stage 2b did.

## 3. Design

### 3.1 Acceptance bar

Unchanged: Gate 1 (ABI, machine-checked) and Gate 2 (behaviour, tested) are pass/fail;
Gate 3 (instruction comparison) is evidence.

### 3.2 Sequencing

1. **`NSMethodSignature`.** Self-contained; parses a type-encoding string once at
   construction (`_parmInfoP`, `_fixup`) and answers from that cache rather than
   re-walking the string per call. `-_isReturnStructInRegisters` reuses stage 2b's
   `NSGetSizeAndAlignment`/type-walking logic to classify the return type by this
   architecture's calling convention (fits in `EAX`/`EDX:EAX` vs. needs a hidden
   out-pointer).
2. **`NSCoder`.** Self-contained; the five abstract primitives raise, the seventeen
   concrete methods are tested through a minimal test-only concrete subclass (§2.2),
   including the property-list/typedstream parser (§2.4).
3. **`NSInvocation` and `NSInvocationBuilder`, plus the two `NSObject` categories.**
   Needs both of the above: argument/return marshaling needs `NSMethodSignature`'s
   parsed type info, and `-encodeWithCoder:`/`-initWithCoder:`/
   `-encode`/`-decodeReturnValueWithCoder:` need a real `NSCoder` to round-trip through.
4. **The forwarding gate.** A test subclass overrides `-forwardInvocation:`, receives a
   selector it does not implement, and the test asserts the override actually ran —
   proving the category from step 3 is reached by the real runtime trampoline, not just
   present in the binary. This is new evidence, not a case restated from an earlier
   stage: nothing before this point in the programme has run because of a category
   overriding a class's own same-selector method.
5. **`NSFault` and `NSFaultHandler`.** Needs `NSInvocation`/`NSMethodSignature` from
   steps 1–4; its forwarding-based methods are tested with a fault actually firing and
   completing a call through a live target (§2.6), not merely proven to raise.
6. **Reconciliation and evidence.** `symbol-audit` re-run to confirm this stage's claims
   landed; `abi-check` across all fourteen modules; the five stage-2a suites plus stage
   2b's two re-run once more, since the forwarding fix changes `-forward::`'s dispatch
   for every class already built (§2.1) — a regression there would be silent otherwise.

### 3.3 Artifacts

- `src/Kits/Foundation/NSMethodSignature.m`, `NSCoder.m`, `NSInvocation.m` —
  reconstructed, replacing their current TODO stubs.
- `src/Kits/Foundation/NSFault.m` — new file, no header, same treatment as
  `NSPrivate.m`.
- `reconstruction/abi/NSMethodSignature.json`, `NSCoder.json`, `NSInvocation.json`,
  `NSFault.json` — committed baselines, generated by `binrecon abi`, never hand-edited.
- `reconstruction/tests/test_methodsignature.{c,m}`, `test_coder.m`, `test_invocation.m`
  (including the forwarding-gate test), `test_fault.m`.
- `reconstruction/invocation-coding/{ledger,source-map}.json`.
- `reconstruction/symbols.json`, `ownership.json`, `divergences.md` — updated.

### 3.4 Reconstruction standard

Unchanged: Apple's copyright header preserved, C89, working variables named for what
they hold, comments explaining why. No decompiler residue. Read `NSObject.m` and
`NSException.m` for house style; read `NSProxy.m`'s own comments on
`NSInvocationBuilder` before writing it, since that file already documents the shape its
disassembly showed.

## 4. Verification

**Acceptance criteria:**

1. `binrecon abi-check` exits zero against all fourteen modules (the ten from stages
   2a/2b plus this stage's four).
2. This stage's own suites pass, including the forwarding-gate test and a real
   fault-firing test.
3. **All five stage 2a suites and both stage 2b suites still pass**, re-run after this
   stage's forwarding fix lands (§3.2 step 6) — the fix changes `-forward::`'s dispatch
   for every already-built class.
4. `abi/NSMethodSignature.json`, `NSCoder.json`, `NSInvocation.json`, `NSFault.json` are
   committed, schema-valid, and describe the layouts in §1.1/§1.3.
5. `binrecon source-map` maps every 2c function, `by_module` accounting for all of them.
6. `ledger.json` is committed with every entry dispositioned.
7. binrecon's own suite passes.
8. No header under `src/Kits/Foundation` is modified.
9. `divergences.md` records: the forwarding-mechanism supersession (§2.1), `NSCoder`'s
   abstract-primitives pattern (§2.2), the inline-bitfield-refcount divergence (§2.5),
   and the plist/typedstream parser's scope (§2.4).
10. `symbol-audit`'s unclaimed count drops by this stage's claimed share (`_NXReadNSObjectFromCoder`, `__NSParseObjectFromASCIIPropertyListOrSerialization`, and any
    further undeclared exports this stage's own disassembly work turns up).

## 5. Risks

### 5.1 The forwarding gate is a new kind of test for this programme

Every prior test in this programme asserts on a function's return value or an object's
state. The forwarding gate asserts on *which implementation the runtime dispatched to*
for a given selector — a fact about the method table, not about any one function's
logic. If it fails to reach the override, that is not a small bug to patch around: it
means the category is not actually superseding the class's own method the way §2.1
assumes, and the task should stop and re-derive the mechanism from the disassembly rather
than adjust the test to pass.

### 5.2 Re-running eight already-passing suites is not optional

§3.2 step 6 and acceptance criterion 3 exist because the forwarding fix is the first
change in this programme that alters the *runtime behaviour* of already-shipped, already-
gated code without editing that code's own file. `abi-check` cannot see this kind of
regression — the symbol tables of `NSObject.m`/`NSProxy.m` do not change. Only re-running
the behavioural suites can catch it.

### 5.3 `NSInvocation`'s `container` ivar is undocumented and untested

§1.3 records its presence and type for ABI fidelity but no test in this stage's own
suite exercises it, since doing so honestly would need real `NSMutableArray` (stage 4).
If a later stage's own tests reveal what it is actually for, `divergences.md` should be
updated then; this stage should not guess at behaviour it cannot verify.

### 5.4 The plist/typedstream parser is real parsing code with no reference test corpus

748 bytes is enough for a real but compact ASCII property-list grammar plus the older
typedstream tagged format; this stage's own tests are the only correctness evidence
available (no shipped `.plist`/typedstream fixture exists in this tree to check against).
Malformed-input handling should match the reference's own apparent tolerance were it
knowable; where it is not, document the choice rather than assume permissiveness or
strictness.
