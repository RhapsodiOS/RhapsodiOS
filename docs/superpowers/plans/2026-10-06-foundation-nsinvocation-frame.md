# Foundation `NSInvocation` Argument-Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reconstruct the PPC and i386 `NSInvocation` factories, initializer, frame ownership, coder destinations, and forwarded-frame copying from the two Foundation binaries.

**Architecture:** Keep the 36-byte object layout and `externalArgFrame` ivar name, but make its bit match the binaries' ownership meaning: set means a separately allocated frame is freed. Factories install an inline pointer into `NSAllocateObject`'s extra bytes; the initializer allocates a zeroed owned frame only when no pointer is already present. Preserve the existing coder stream while using inline or owned storage consistently and copying runtime frames into the invocation's existing destination.

**Tech Stack:** Objective-C, the Foundation allocator and zone APIs, Objective-C runtime class layout, PPC/i386 ABI JSON overlays, live MOSXS PPC and DR2 i386 IDA databases.

**Spec:** `docs/superpowers/specs/2026-10-06-foundation-nsinvocation-frame-design.md`

## Global Constraints

- Keep `+[NSInvocation newInvocationWithMethodSignature:]` PPC-only; the i386 image has no such selector.
- The local coder stream was retained for the frame slice; the 2026-10-07 follow-up below replaces it with the distributed-object wire protocol.
- Keep `externalArgFrame` as the ABI-visible ivar name; set its bit only for a separately allocated frame that deallocation must free.
- Preserve the shared 36-byte `NSInvocation` instance layout and all current ivar offsets.
- Do not reconstruct the distributed-object coder wire protocol or NSPortCoder dependencies in this slice.
- Do not change invocation dispatch, argument type classification outside constructor return-value initialization, or return-value marshaling.
- Do not add or run tests or builds; use IDA comparisons and static source/metadata checks only.

## Review Focus

- A factory-created inline frame must survive deallocation without being passed to `NSZoneFree`.
- A frame created by `_establishArgumentFrame` must be zeroed, marked owned, and freed exactly once.
- A signature containing an Objective-C qualifier must choose the same return-value tag as the PPC and i386 initializers.
- An i386 `_fixup` entry of zero and a nonzero entry must select the same source offsets as the target loop.
- A runtime argument frame must be copied into the invocation's existing frame; its pointer must never be adopted or freed.

---

### Task 1: Owned-frame helper and method-signature initializer

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m` (the instance layout, initialization helpers, initializer, and deallocator)

**Interfaces:**
- Produces `static void NSInvocationEstablishArgumentFrame(NSInvocation *invocation)` for the initializer and coder post-init paths, plus `NSInvocationInitializeReturnValue` shared by signature and coder construction.
- Consumes the existing `NSInvocationInstance` layout and `NSMethodSignature` accessors.

- [x] Add `NSInvocationEstablishArgumentFrame(NSInvocation *)`: read `[signature frameLength]`, allocate from `[invocation zone]`, assign `argumentFrame`, zero exactly `frameLength` bytes, then set `externalArgFrame` to 1.
- [x] Rewrite `-initWithMethodSignature:` without calling superclass `init`; a nil signature follows the target superclass-deallocation path and returns nil. Otherwise retain the signature, preserve an existing frame pointer, and call the helper only when the pointer is null.
- [x] Initialize `returnValue.type` from the signature's private `_types` pointer after skipping optional `r`: `# @ O R` map to `@`; `$ C c` to `c`; `% *` to `*`; `:` to `:`; `I L i l` to `l`; `Q q` to `q`; `S s` to `s`; `V v` to `v`; `^` to `^`; `d` to `d`; `f` to `f`; `{` to `{`. Raise the target inconsistency exception for unknown encodings. For `{` returns, allocate and zero `methodReturnLength` bytes; `invalidate` releases struct contents, frees the buffer, and clears its pointer. Reuse the buffer in `setReturnValue:`.
- [x] Keep the source's `signatureValid = 1` assignment because its invoke path consumes this field. Leave `refCount` zero-initialized: the paired target retain methods use the internal reference-count helpers, whose stored 24-bit count starts at zero and reports a retain count of one.
- [x] Change `-dealloc` to match the target order: call `invalidate`, release `container` when present, free `argumentFrame` only when `externalArgFrame` is set, release `signature`, then call `[super dealloc]`. Pass `NULL` as the zone to `NSZoneFree`.
- [x] Compare nil/non-nil initializer paths, return-type dispatch, struct-return allocation, helper zone/size/zeroing, ownership bits, and cleanup order against PPC `0x42525774`, `0x425868e8`, `0x42521370` and i386 `0x4252298c`, `0x425757f4`, `0x4251fe28`.
- [x] Run `git diff --check -- src/Kits/Foundation/NSInvocation.m` (expected: exit 0, no output).

### Task 2: Architecture-specific method-signature factories

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m` (class factories near the start of the implementation)
- Modify: `src/Kits/Foundation/NSInvocation.h` (class method declarations)
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSInvocation.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`

**Interfaces:**
- Produces PPC-only `+ (NSInvocation *)newInvocationWithMethodSignature:(NSMethodSignature *)signature`.
- Keeps `+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature` available on both architectures.

- [x] Add the PPC-guarded factory declaration to `NSInvocation.h` using the same target guard used by source files.
- [x] Implement the PPC new factory with `NSAllocateObject(self, [signature frameLength], NULL)`, install `argumentFrame` at `(char *)object + self->instance_size` only when allocation succeeds, send `initWithMethodSignature:`, and return the retained result.
- [x] Implement the PPC autoreleased factory by calling the new factory and autoreleasing its result.
- [x] Implement the i386 autoreleased factory inline: allocate the extra tail bytes, install the frame pointer only when allocation succeeds, initialize, then autorelease. Do not define the PPC new selector in the i386 branch.
- [x] Extract the complete PPC `NSInvocation.m` ABI from the reference binary into `abi-ppc/NSInvocation.json`; confirm `newInvocationWithMethodSignature:` has the PPC type `@8@4:8@12` and add its `ownership.json` owner as `NSInvocation.m`.
- [x] Compare both factory paths against PPC `0x42523884`, `0x4258220c`, and i386 `0x4251fbb0`. Parse the new ABI JSON and verify the shared ABI file remains unchanged.
- [x] Run `git diff --check` for the source, header, ABI overlay, and ownership record (expected: exit 0, no output).

### Task 3: Coder destinations and target-specific `_setArgFrame:` copies

**Files:**
- Modify: `src/Kits/Foundation/NSInvocation.m` (`_setArgFrame:`, `initWithCoder:`, `_postInitWithCoder:...`, and `newInvocationWithCoder:`)

**Interfaces:**
- Consumes `NSInvocationEstablishArgumentFrame(NSInvocation *)` from Task 1.
- Preserves `- (void)_setArgFrame:(void *)frame` as an internal method that copies into existing storage.

- [x] For PPC, implement `_setArgFrame:` as a frame-length `memmove` from the supplied pointer into `instance->argumentFrame` without changing the pointer or ownership bit.
- [x] Mirror the private `NSMethodSignature` layout in `NSInvocation.m` (fields at offsets 0, 4, 8, 12, 16, 20, 24, and 28; `fixup` is the `int *` at offset 24). For each i386 argument index below `numberOfArguments`, dereference the pointer slot at `argFrame + fixup[index]` when nonzero; zero or absent fixups use `argFrame + argumentInfo.offset`. Then call `setArgument:atIndex:`.
- [x] Reconstruct the PPC `NSMethodSignature` argument records required by `NSInvocation`: recursively populate nested struct records and calculate their PPC register/stack offsets through the IDA-confirmed `compute_pip_offset` flow; leave the existing i386 record path unchanged.
- [x] Make PPC `getArgument:atIndex:` gather struct fields from those records and narrow 8-byte frame floats into caller float slots; preserve the i386 contiguous-copy path.
- [x] In `initWithCoder:`, initialize the return-value tag/storage from the decoded signature, establish an owned destination frame when none exists, and decode the existing frame byte stream directly into that destination before restoring the decoded target and selector. Do not adopt a temporary frame pointer.
- [x] In `_postInitWithCoder:...`, initialize the reconstruction's custom reference count and return-value tag/storage, call the frame helper only if no inline frame was installed, and preserve target/selector and current stream validation behavior.
- [x] In `newInvocationWithCoder:`, allocate `frameLength` extra bytes and install the inline pointer only when allocation succeeds before `_postInitWithCoder:...`; return the result retained, without autoreleasing it.
- [x] Confirm `NSInvocationBuilder -forward::` remains a caller of `_setArgFrame:` and that the runtime-owned input pointer is copied, never stored or freed.
- [x] Compare PPC `_setArgFrame:` `0x42523908`, coder factory `0x4253b844`, `_postInitWithCoder:` `0x4253c678`; compare i386 `_setArgFrame:` `0x4251faf0`, coder factory `0x425511c8`, and `_postInitWithCoder:` by its IDA selector name.
- [x] Run `git diff --check -- src/Kits/Foundation/NSInvocation.m` (expected: exit 0, no output).

### Task 4: Architecture records and static audit

**Files:**
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`
- Verify: `src/Kits/Foundation/reconstruction/abi/NSInvocation.json`
- Verify: `src/Kits/Foundation/reconstruction/abi-ppc/NSInvocation.json`
- Verify: `src/Kits/Foundation/reconstruction/ownership.json`

**Interfaces:**
- Consumes Task 2's PPC-only class-method record and owner mapping.
- Produces a documented PPC/i386 selector and frame-ownership distinction.

- [x] Record that PPC exports `+[NSInvocation newInvocationWithMethodSignature:]`, i386 does not, and both factories use inline tail storage while separately established frames use the ownership bit.
- [x] Parse the shared ABI, PPC overlay, and ownership JSON; assert the new selector appears exactly once in the PPC overlay, is absent from the shared ABI and i386 reference selector set, and maps to `NSInvocation.m`.
- [x] Run `python tools/binrecon/selector_check.py 'C:\Users\raynorpat\Downloads\test\Frameworks\Foundation.framework\Versions\C\Foundation' src/Kits/Foundation` (expected: 11 missing PPC selectors, no renames or duplicates).
- [x] Run `python tools/binrecon/selector_check.py 'C:\Users\raynorpat\Downloads\test\Foundation-i386' src/Kits/Foundation` (expected: 0 missing i386 selectors, no renames or duplicates).
- [x] Run `git diff --check` for the complete slice and confirm `NSInvocation.m` remains registered in `PB.project` and `Makefile` (expected: no whitespace errors; both registrations present).

---

## Self-review

- **Spec coverage:** Task 1 covers nil and non-nil initialization, the owned-frame helper, return-value tags/storage, the ownership bit, and deallocation order. Task 2 covers PPC and i386 method-signature factories and the PPC-only ABI declaration. Task 3 covers coder destinations, both target `_setArgFrame:` algorithms, retained coder factory ownership, and the forwarding caller. Task 4 covers ownership/source metadata, architecture divergence, and static selector verification.
- **Step granularity:** Every implementation item names one method/helper or one metadata/check action. No source behavior is left as “handle appropriately.”
- **Type consistency:** The helper signature is shared by Task 1 and Task 3. The frame-length and selector type encodings match the existing 32-bit ABI records.
- **Review focus:** The frame/return conditions and fresh-review corrections are captured in source and checked against IDA. Runtime tests are excluded by the global constraint.
- **Proportion:** Four tasks follow helper/initializer state, public factories, coder/forwarding frame transfer, and reconstruction verification.

### Follow-up: distributed-object coder wire (2026-10-07)

The earlier coder-stream restriction above was superseded by the separately
approved `docs/superpowers/specs/2026-10-07-foundation-nsinvocation-wire-design.md`.
The frame allocation and inline-tail ownership decisions from this plan remain
in force; `encodeWithCoder:`, `initWithCoder:`, `_preInitWithCoder:...`, and
`_postInitWithCoder:...` now follow that wire design.

### Static i386/PPC class-layout check (2026-10-15)

Compared the class layout records in both `NSInvocation` and
`NSMethodSignature` ABI manifests with the source declarations.
`NSInvocationBuilder` has its explicit root `isa` plus three pointer fields
at offsets 0, 4, 8, and 12 (size 16); `NSInvocation` has the 12-byte
`NSObjCValue` return slot at offset 4, frame/signature/container at 16/20/24,
packed flags and reference count at 28/29, and reserved pointer at 32 (size
36). `NSMethodSignature`'s seven fields occupy offsets 4 through 28 and size
32. Both architecture manifests record these same class layouts; their
method type encodings remain architecture-specific. This is source-level
layout evidence, not compiled-object ABI verification.
