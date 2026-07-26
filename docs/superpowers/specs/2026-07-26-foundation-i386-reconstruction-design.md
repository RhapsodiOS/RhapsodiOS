# Binary reconstruction of Foundation

Reconstruct `src/Kits/Foundation` against Apple's shipped Foundation framework
using the `tools/binrecon` toolchain. This spec covers the first of ten stages:
the tooling binrecon needs to read a framework at all, the Objective-C ABI
baseline extracted from the reference, and one small module group carried end to
end to prove the pipeline.

The request that opened this work asked for the **PowerPC** Foundation. This
spec targets **i386** instead. The reason is in §1.1: the repository cannot
build PowerPC, so a PowerPC reconstruction has no build-and-compare loop and
could never be verified. The PowerPC slice is retained as a cross-reference.

## Motivation

`src/Kits/Foundation` is 66 headers and 66 `.m` files. The headers are Apple's,
byte-identical to the shipped set. The implementations are 6,694 lines in which
every method body is `// TODO: Implement this method`. The directory appears in
no `Manifest` and no build script; nothing has ever compiled it.

Foundation is the floor the rest of Rhapsody's object layer stands on. AppKit,
the Enterprise Objects frameworks, Project Builder and every Rhapsody
application link against it. Until it exists, none of them can.

## 1. Scope

### 1.1 Reference of record

| | |
| --- | --- |
| Container | `DR2/Frameworks/Foundation.framework/Versions/C/Foundation` |
| Container SHA-256 | `215935DFAB3C083AB97E24F6B74B76C4AE668783892510F02D71AD9BFDE5192B` |
| Container size | 3,425,564 |
| Format | fat, 2 slices |
| **Slice of record** | **i386** (`cputype` 7, `cpusubtype` 3), offset 8192, size 1,630,488 |
| **Slice SHA-256** | **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`** |
| Cross-reference slice | ppc (`cputype` 18), offset 1,646,592, size 1,778,972, SHA-256 `D2387EA25C8DD66DC548541657C8E1D66A318F85FC4F6C71D85DE174942D839F` |

Four Foundation binary files were available, carrying six slices between them.
The i386 slice was chosen because it is the only one the repository can build
against. `tools/binrecon/README.md` records
that the seven existing PowerPC profiles are reference-only: "the repository
cannot build PowerPC drivers today, so there is no rebuilt artifact to compare
against." A PowerPC reconstruction would be inspection without verification.

The Mac OS X Server 1.x thin PowerPC binary was the other serious candidate,
since the in-tree headers came from it. §2.3 shows why that does not matter.

`Foundation_profile`, which sits beside each binary, was examined and rejected.
It carries no additional debug information — identical symbol table (5,231
symbols against 5,230, the difference being one profiling stub), zero stabs in
both. It is a `-pg` build whose `__text` is 28% larger (1,052,600 against
822,500 for the PowerPC pair) purely from `mcount` prologues. For reconstruction
it is the same information buried in more instructions.

### 1.2 Measured shape of the reference

| | |
| --- | --- |
| File type | `MH_DYLIB` (6) |
| `__TEXT,__text` | 668,480 bytes, `0x4250111c`–`0x425a445c` |
| `__TEXT,__picsymbol_stub` | 8,138 bytes (separate section; not part of `__text`) |
| Named text symbols | 3,990 |
| `LC_DYSYMTAB` | 3,914 local, 940 external defined, 207 undefined, 846 indirect |
| Objective-C modules | 80 |
| Classes | 182 |
| Categories | 50 |

Code accounted for: 422,616 bytes in class methods, ~73,000 in category methods,
172,396 across 736 named C functions.

Two properties of this binary make the work tractable:

**Local symbols were not stripped.** 3,914 of them. Static helper functions carry
their real names. This is a better starting position than any driver
reconstruction in the repository.

**`__OBJC,__module_info` names every original translation unit.** Not inferred —
read from the binary: `NSString.m`, `NSSimpleCString.m`, `NSCharConversion.m`,
`NSParser.m`, `NSFault.m`, `NSPrivate.m` and 74 more. Each module's symtab lists
the classes and categories it defines, so every Objective-C method's owning
source file is known exactly. Only plain C functions need attribution by header
declaration and address locality.

### 1.3 Starting state

Every method body in `src/Kits/Foundation` is a `// TODO` stub. There is no
partial reconstruction to reconcile and no `source-map` baseline worth
recording: nothing maps.

### 1.4 Out of scope for this spec

Adding Foundation to `src/Manifest`; building the framework as a framework;
modifying any header; touching the 63 stub `.m` files outside this spec's group;
raising `_MAX_ANALYSIS_BYTES`; teaching Ghidra or angr anything (both remain
i386-only and both are disabled in every recent profile); reconstructing
`__picsymbol_stub` contents.

## 2. Findings that shaped this design

### 2.1 Module code is fragmented across `__text`

Apple shipped this framework with profile-guided function ordering — which is
also why a `_profile` build exists. Hot functions are hoisted toward the front of
`__text`; cold ones remain in link order. The consequence is that **a module's
functions are not contiguous**:

| Module | Methods | Disjoint runs |
| --- | --- | --- |
| NSString.m | 88 | 65 |
| NSData.m | 120 | 59 |
| NSValue.m | 127 | 49 |
| NSSet.m | 112 | 45 |
| NSObject.m | 65 | 41 |

Across all modules: **1,273 disjoint runs**. `NSString.m`'s methods make up 2.5%
of the functions in the address span they occupy.

The existing `analysis_scope` field, added by
[2026-07-25-analyzer-address-range-scoping-design.md](2026-07-25-analyzer-address-range-scoping-design.md),
already accepts a list of disjoint ranges rather than one range
(`tools/binrecon/binrecon/profile.py:68` validates and sorts them, and the IDA
exporter's `_in_scope` matches an address against any of them). So fragmentation
costs no new schema — it means a stage's scope is many small ranges instead of
one large one, and that those ranges must be generated rather than written by
hand. §3.6 covers the generator.

A few modules are exceptions — `NSAbsoluteURL.m` is a single run, `NSURL.m` is
three — but they are rare enough not to change the mechanism.

### 2.2 Every byte of code carries a name

3,990 named text symbols partition the 668,480-byte `__text`. Combined with §1.2's
retained local symbols and §1.2's module map, attribution is essentially complete
before any analysis runs. There is no unnamed code to attribute by guesswork, and
therefore no need for the boundary-dispute machinery that earlier driver specs
leaned on.

### 2.3 The DR2 and MOSXS releases have identical ABI

The in-tree headers came from the Mac OS X Server 1.x framework, but the
reference is DR2. That is not a conflict:

- MOSXS defines **188** classes, DR2 **182**.
- The 6 extra classes are one subsystem: `NSURLHandle`, `NSFileURLHandle`,
  `NSHTTPURLHandle`, `NSHTTPConnection`, `NSHTTPRequest`, `NSHTTPSocket`.
- DR2 has **zero** classes MOSXS lacks.
- Of the 182 shared classes, **zero** differ in `instance_size`.

The delta is purely additive and confined to URL/HTTP handling. So the MOSXS
headers stay as the public API, DR2 is the ABI and behaviour reference for 182 of
188 classes with no reconciliation needed, and the 6 URL/HTTP classes become
stage 10, referenced against the MOSXS PowerPC binary.

DR2 carries one module MOSXS lacks, `NSSimpleHashing.m`, which defines no classes.

### 2.4 Public headers contain `static inline` functions

`NSGeometry.h`, `NSRange.h` and `NSDecimal.h` declare 53 functions between them.
36 of those are out-of-line symbols in the binary; the remaining 17 —
`NSMakeRect`, `NSMaxRange`, `NSMinX`, `NSDecimalIsNotANumber`,
`NSDecimalMaxSize` and others — are `static inline` in the headers and are
compiled into *callers*. They are part of the ABI contract but leave no symbol to
diff against. §5.1 covers how they are guaranteed.

### 2.5 binrecon cannot read this file

`read_macho` rejects `MH_DYLIB` outright (`tools/binrecon/binrecon/macho.py:139`,
which accepts only `MH_OBJECT`, `MH_PRELOAD`, `MH_BUNDLE`, `MH_EXECUTE`), and
`_select_architecture` reads a thin header and will fail on the fat container's
`0xcafebabe`. binrecon has `objc_methods_from_sections`, but it builds only an
address-to-name index over method lists; it models no ivars, instance sizes,
categories, protocols or modules.

## 3. Design

### 3.1 Program decomposition

Ten stages. This spec is stage 1; the rest are named so the shape is visible.
Each later stage gets its own design and plan.

| # | Stage | Modules | ~`__text` |
| --- | --- | --- | --- |
| **1** | **Tooling, ABI baseline, proof slice** | NSGeometry, NSRange, NSDecimal | **8 KB** |
| 2 | Core runtime | NSObject, NSProxy, NSAutoreleasePool, NSException, NSInvocation, NSMethodSignature, NSCoder, NSFault, NSObjCRuntime, NSPrivate, NSZone | 22 KB |
| 3 | Strings | NSString, NSMutableString, NSSimpleCString, NSSimpleString, NSConstantString, NSCharConversion, NSStringEncodings, NSStringLocalizedCompare, NSStringArray | 60 KB |
| 4 | Collections | NSArray, NSDictionary, NSSet, NSEnumerator, NSHashTable, NSMapTable, NSSimpleHashing | 65 KB |
| 5 | Values, dates, formatters | NSValue, NSDecimalNumber, NSDate, NSCalendarDate, NSTimeZone, NSFormatter, NSNumberFormatter, NSDateFormatter, NSScanner, NSCharacterSet | 80 KB |
| 6 | Data, files, archiving | NSData, NSFileManager, NSFileHandle, NSBundle, NSPathUtilities, NSSerialization, NSArchiver, NSObjCTypeSerialization | 65 KB |
| 7 | Runloop, threads, processes | NSRunLoop, NSThread, NSLock, NSTimer, NSPort, NSTask, NSProcessInfo, NSHost, NSPlatform, NSPerformTimer, NSNotification, NSNotificationQueue, NSDistributedLock | 45 KB |
| 8 | Distributed Objects | NSConnection, NSDistantObject, NSDistantString, NSPortCoder, NSPortNameServer, NSProtocolChecker, NSDistributedNotificationCenter | 45 KB |
| 9 | Defaults, parsing, misc | NSUserDefaults, NSParser, NSLanguageContext, NSLockedPropertyListFile, NSUndoManager, NSAttributedString, NSCompatibility, NSDebug, NSJavaSetup, NSURL, NSAbsoluteURL, NSURLPathUtilities | 65 KB |
| 10 | URL/HTTP handles | NSURLHandle, NSFileURLHandle, NSHTTPURLHandle, NSHTTPConnection, NSHTTPRequest, NSHTTPSocket | MOSXS ppc only |

Stage 10 has no i386 reference and therefore no compare loop, which is why it is
last.

### 3.2 Acceptance bar

Two gates are pass/fail, one is evidence.

**Gate 1 — ABI, machine-checked.** Class and metaclass layout, superclass links,
`instance_size`, ivar names, type encodings and offsets, every selector and its
type encoding, category membership and adopted protocols, and exported C symbols
must match the reference exactly. Compiled Rhapsody binaries link against this
framework; an ivar at the wrong offset is fatal in a way a different register
allocation is not. Enforced by `binrecon abi-check` (§3.5).

**Gate 2 — behaviour, tested.** Method and function bodies are reconstructed to
behave correctly, verified by tests.

**Gate 3 — instruction comparison, evidence only.** The reference is a linked PIC
dylib; our build produces relocatable objects. Their instruction streams differ
for reasons unrelated to correctness — PIC sequences, register allocation, a
different compiler generation. `binrecon compare` runs and its ledger is
committed and reviewed, but a divergence prompts investigation rather than
failing the stage. Each is dispositioned in `divergences.md` as *explained by
codegen* or *real, fix it*.

This is the deliberate difference from the driver specs, which drove parity
ledgers to zero. At 668 KB that bar would cost years and buy little: no consumer
of Foundation depends on `NSArray`'s register allocation, and all of them depend
on its ivar layout.

### 3.3 Reconstruction is reconstruction, not transcription

The SCSIServer spec found a 562-line block in `src/drvSCSIServer` transcribed
directly from decompiler output — `param_1`-style names, decompiler comments, and
a hand-written dispatch table wired wrong on all 18 entries. Nobody caught it
because the code was unreadable.

Decompiler output is evidence about behaviour. Committed source is written from
an understanding of that behaviour, in the idiom of the surrounding headers. A
reviewer must be able to read `NSDecimalAdd` and check it against documented
decimal semantics without opening a disassembler. Source containing
decompiler-generated identifiers does not pass review.

### 3.4 Artifact layout

```
src/Kits/Foundation/
  reconstruction/
    divergences.md                  shared narrative, appended by each stage
    abi/
      NSGeometry.json               one per module, not per group
      NSRange.json
      NSDecimal.json
    geometry-range-decimal/         one directory per stage's group
      ledger.json
      source-map.json
```

This follows the established driver layout
(`src/<project>/reconstruction/<target>/{ledger.json,source-map.json}` with a
shared `divergences.md`) with one change.

**ABI evidence is per module; ledgers are per group.** Groups are a scheduling
convenience and may be resequenced between stages. Modules are a fact read from
the binary and never move. Per-module ABI files mean a later stage never rewrites
an earlier stage's file, and a diff on `abi/NSString.json` means exactly one
thing: our understanding of that translation unit's ABI changed.

Each `abi/<Module>.json` holds, for one module: classes with superclass,
`instance_size`, info flags and ivars (name, type encoding, offset); categories
with target class and adopted protocols; every instance and class method as
selector plus type encoding; and exported C symbols.

`ledger.json` and `source-map.json` keep their existing schemas. Per-group
granularity is a hard requirement, not a preference: the VGA driver's 68-function
ledger is 48 KB, so a single Foundation ledger over 3,990 functions would reach
roughly 2.8 MB and be unreviewable.

`divergences.md` is shared and append-only across all ten stages, so the whole
picture stays readable in one file.

Analyzer output stays out of git — `tools/binrecon/out/foundation-i386/` is
already covered by the existing `tools/binrecon/out/` ignore rule. The reference
binary stays outside the repository at `$BINRECON_REFERENCE`.

### 3.5 binrecon changes

**Accept `MH_DYLIB`.** Add file type 6 to the accepted set in `read_macho`.
Nothing downstream assumes a relocatable object.

**Fat container support.** Parse `0xcafebabe` and add an optional
`reference.slice` field to `profile-v1` naming the architecture to extract. A fat
input with no `slice` field is an error, not a silent pick — the wrong slice
would poison every downstream artifact. The extracted slice's SHA-256 is recorded
separately from the container's so `input.sha256` stays meaningful.

**`__OBJC` ABI extraction.** The substantial new capability, producing the
`abi/<Module>.json` files of §3.4. Walks `__module_info` for module names and
symtabs, `__class` and `__meta_class` for superclass, `instance_size` and info
flags, `__instance_vars` for ivar names, encodings and offsets, `__category` for
category targets, `__protocol` for adopted protocols, and `__meth_var_types` for
method signatures.

**`binrecon abi-check`.** New CLI verb. Reads built objects, extracts their
`__OBJC` the same way, diffs against the committed `abi/<Module>.json`, exits
nonzero on any divergence — a renamed ivar, a changed offset, a missing selector,
a wrong instance size.

**`source-map` gains a module dimension.** Today it buckets reference functions
against source by name. With `__module_info` every method's owning `.m` file is
known, so the mapped/unmapped report becomes per-module. Bucket semantics are
unchanged.

### 3.6 Module scope generation

`analysis_scope` needs no schema change (§2.1). What is new is a generator, since
hand-listing a stage's ranges would be unmaintainable and wrong within a stage —
stage 3's scope alone would be 65 ranges for `NSString.m`.

A new `binrecon module-scope` command takes the profile and a set of module
names, and emits the `analysis_scope` array to paste into the profile. It derives
the ranges from `__module_info` (which names each module's classes and
categories) plus the symbol table (which gives each method's and each C
function's address), emitting one `{start, end}` per function.

Stage 1's generated scope is 43 ranges.

### 3.7 Proof slice

Three modules, chosen because they define no classes and one category, so the ABI
surface is small but nonzero, and because at 43 functions the group is smaller
than the SCSIServer driver (68) — a proven scale.

| Module | C functions | Category methods | Bytes |
| --- | --- | --- | --- |
| NSGeometry.m | 20 | 6 | 3,792 |
| NSRange.m | 5 | 0 | 636 |
| NSDecimal.m | 12 | 0 | 4,356 |
| **Total** | **37** | **6** | **8,784** |

`NSGeometry.m`'s single category is `NSCoder (NSGeometryCoding)` —
`encodePoint:`, `decodePoint`, `encodeSize:`, `decodeSize`, `encodeRect:` and
`decodeRect`, 384 bytes in total. It compiles against `NSCoder.h` without
`NSCoder` being implemented, which is what makes it usable as stage 1's ABI
surface.

The `NSValue` categories declared in `NSRange.h` and `NSGeometry.h` are *not*
part of these modules — `__module_info` places them in `NSValue.m`, so they
belong to stage 5.

`NSGeometry.m` also exports three data symbols: `NSZeroPoint`, `NSZeroSize` and
`NSZeroRect`.

All three exist as stubs in the tree, so this replaces file contents rather than
adding files.

`NSIntersectsRange` is exported but declared in no public header; it is
reconstructed and recorded in `divergences.md` as an undeclared export.

**Sequence.** Analyze the reference with IDA scoped to the 37-address allowlist →
extract `abi/` for the three modules → run `source-map` for the baseline →
reconstruct the three files → build → verify against the three gates.

**Test coverage is partial by construction.** 15 of the 43 functions are written
and ABI-checked in stage 1 but cannot be behaviourally tested there:

- **Nine** return or parse an `NSString` — `NSStringFromPoint`,
  `NSStringFromSize`, `NSStringFromRect`, `NSStringFromRange`,
  `NSPointFromString`, `NSSizeFromString`, `NSRectFromString`,
  `NSRangeFromString` and `NSDecimalString`. Their tests are deferred to stage 3.
- **Six** are the `NSGeometryCoding` category methods, which drive `NSCoder`'s
  encoding machinery. Their tests are deferred to stage 2.

The remaining **28 are tested in stage 1**: all 11 non-string `NSDecimal*`
functions and the 17 pure struct-math geometry and range functions. These are
pure functions over plain structs and need no other part of Foundation to run.
Decimal arithmetic carries the weight — exact rounding modes, overflow and
underflow returns, `NSDecimalCompact` and `NSDecimalNormalize` behaviour, and
mantissa-length limits.

### 3.8 New profile

`tools/binrecon/profiles/foundation-i386.json`: architecture i386, endianness
little, `reference.slice: "i386"`, IDA only, `analysis_scope` set to the 37
ranges generated by `binrecon module-scope`. The IDA timeout is set well above
the 900 s default; the plan records observed wall-clock so later stages can size
theirs from data.

## 4. Verification

Stage 1 is complete when all of the following hold:

1. `binrecon validate --profile tools/binrecon/profiles/foundation-i386.json`
   resolves the fat container, selects the i386 slice, and reports slice SHA-256
   `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
2. `binrecon analyze` completes with `complete: true` and a populated
   `published/` directory, having exported exactly the 43 scoped functions.
3. `abi/NSGeometry.json`, `abi/NSRange.json` and `abi/NSDecimal.json` are
   committed and describe the `NSCoder (NSGeometryCoding)` category with its six
   methods, 37 exported text symbols and 3 exported data symbols.
4. `binrecon abi-check` against the built objects exits zero.
5. The 28-function test suite passes.
6. `binrecon source-map` reports all 43 reference functions mapped for the three
   modules.
7. `ledger.json` is committed with every entry reviewed, and every divergence is
   dispositioned in `divergences.md`.
8. binrecon's own test suite passes, including new tests for `MH_DYLIB`
   acceptance, fat slice selection, missing-`slice` rejection, `__OBJC`
   extraction, `abi-check` divergence detection, and `module-scope` generation.
9. No header under `src/Kits/Foundation` is modified.

## 5. Risks

### 5.1 Inline functions are ABI but unverifiable

Per §2.4, `static inline` functions in public headers are part of the contract yet
leave no symbol to diff. `abi-check` cannot cover them. They are guaranteed
instead by the headers being Apple's unmodified shipped headers, verified
byte-identical to the MOSXS set.

The rule that follows: **stage 1 does not edit headers.** If reconstruction
appears to require a header change, that is a stop-and-report finding.

### 5.2 IDA on a 1.6 MB dylib is unmeasured

The allowlist limits *output*, which is what tripped the 16 MB guard on the DR2
kernel, but autoanalysis still loads the whole image and its runtime is unknown.
This is the most likely place stage 1 stalls. The plan measures and records
wall-clock and output size on the first run. If the guard trips despite the
allowlist, the group narrows to one module at a time rather than raising the
limit — the same call the address-range scoping spec made.

### 5.3 The proof slice may not compile standalone

Compiling `NSGeometry.m` requires the header set to parse, which pulls in
`NSString.h`, `NSObject.h` and others. Those are complete headers, so it should
compile to an object without their implementations existing — but that is an
assumption, not a verified fact.

It is the first thing the plan checks. **Before any reconstruction work, confirm
the guest compiles the existing stub `NSGeometry.m` to a `.o`.** If it fails, the
stage stops and the finding reshapes the program.

### 5.4 Vintage mismatch

We reconstruct MOSXS-era headers against a DR2-era implementation. Justified by
§2.3's measurement: 182 shared classes, zero `instance_size` differences, zero
classes in DR2 but not MOSXS. Any `abi-check` failure attributable to vintage is a
genuine surprise that stops work rather than being waived through.

### 5.5 Ledger review burden grows

37 functions is reviewable. `NSString.m` at 88 methods and `NSValue.m` at 127 will
not be at the same granularity. Stage 1 does not solve this; it records observed
review cost so stages 3–5 can size their groups from data rather than guesswork.
