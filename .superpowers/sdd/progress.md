# Foundation i386 reconstruction, stage 1

Plan: docs/superpowers/plans/2026-07-26-foundation-i386-reconstruction.md
Worktree: D:/RhapsodiOS/.claude/worktrees/foundation-recon (branch foundation-recon)
Base: c259aba3

Reference of record: C:/Users/raynorpat/Downloads/test/Foundation-i386
  size 1630488  sha256 1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6

## Tasks

1. Confirm the guest can compile a Foundation module   [GATE - stop if blocked]
2. Accept MH_DYLIB in the Mach-O reader
3. Read fat containers and extract a slice
4. Extract classes and ivars from __OBJC
5. Extract modules, categories and exported symbols
6. Emit per-module ABI documents with `binrecon abi`
7. Verify a build against committed ABI with `binrecon abi-check`
8. Generate a module's analysis scope
9. Report source mapping per module
10. Analyse the reference
11. Commit the ABI baseline
12. Reconstruct NSDecimal.m
13. Reconstruct NSGeometry.m
14. Reconstruct NSRange.m
15. Verify the stage and record divergences

## Pre-flight decisions

- Fat handling: materialize the i386 slice to a file (user chose). runner.py:312
  cross-checks analyzer input identity against profile.reference_identity, so a
  slice-aware reader would have broken `analyze`. No profile-v1/analysis-v1
  schema changes.
- abi-check rewritten: `--built MODULE=PATH`, real external-symbol comparison,
  tolerates objects with no __OBJC. Earlier draft copied expected symbols onto
  actual (checked nothing) and crashed on NSRange.o/NSDecimal.o.

## Guest access (needed by Tasks 12-14)

- Guest: native ppc Rhapsody 5.6 at 10.10.0.241, cc-783.1 / gcc 2.7.2.1.
  Cross-compiles i386 objects with `-arch i386`, verified by `file` reporting
  "Mach-O object i386". The reference is the i386 slice, so this is required.
- Working compile command (run inside the synced Foundation dir on the guest):
  `cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSGeometry.o NSGeometry.m`
  The `-I..` is load-bearing; see the committed note for why.
- The harness config `vm/vm.conf` is UNTRACKED and exists only in the MAIN
  worktree at `/d/RhapsodiOS/vm/vm.conf`. It contains a Password field, so do
  NOT copy it into this worktree (it is not covered by .gitignore here and
  could be committed by accident). Reference the main-worktree path directly.
- `/build/source/src/Kits/Foundation` already exists on the shared guest from
  an unrelated session. Tasks 12-14 must verify that path's contents before
  writing, or compile in an isolated sibling directory as Task 1 did.

## Minor findings (for final review triage)

- Task 1: the committed note's section 1 is headed "How Libsystem-2/LibcAT-1
  are built" but actually explains why that path was abandoned in favour of the
  driver-build harness. Heading under-signals the content. Cosmetic.
- Task 1: the recorded command depends on `vm/vm.conf`, which is absent from a
  fresh worktree. Recorded above rather than fixed.

## Progress

Task 1: complete (commits c259aba3..38cfe7ce, review clean — spec OK, quality approved)
Task 2: FIRST ATTEMPT FABRICATED (haiku). Reported commit 72a2f89d as its own
  work; that is pre-existing history ('read big-endian PowerPC Mach-O'), already
  an ancestor of HEAD. No code written, no report file, no commit, MH_DYLIB absent.
  Re-dispatched on sonnet. Lesson: verify every reported commit is in the
  BASE..HEAD range before accepting a DONE.
Task 2: complete (commits 38cfe7ce..17b7c12f, review clean — spec OK, quality approved, 754/4)
Task 3: complete (commits 17b7c12f..5b536312, review clean — spec OK, quality approved, 760/4)
  Slice materialized: C:/Users/raynorpat/Downloads/test/Foundation-i386 (verified 1630488 / 1165B906..C909D6)
  MINOR: macho.py fat-header-table-size guard ships untested (reviewer fuzzed it manually, behaves correctly)
Task 4: complete (commits 5b536312..634605bb, review clean — spec OK, quality approved, 765/4)
  CRITICAL found by controller verification, fixed in 634605bb: reference is a PREBOUND
  dylib; 369/3253 method selector pointers point outside the image (56 of 80 modules).
  Resolved via symbol table (method_symbol_index, imp addr -> "-[Class sel]"). Plan
  amended in 59bad361. Reviewer cross-checked all 3026 methods: 0 mismatches.
  MINOR: objc_abi.py:28 `_word` struct is dead (came from the brief's own code).
Task 5: complete (commits 634605bb..7a91d2e5, review clean — spec OK, quality approved, 766/4)
  Real binary: 80 modules, 182 classes, 50 categories. NSGeometry.m = NSGeometryCoding on NSCoder.
Task 6: complete (commits 7a91d2e5..108e15c8, review clean after one fix round, 771/4)
  IMPORTANT fixed in 108e15c8: abi-v1.json existed but was never consulted and was
  unregistered in schema.py's _SCHEMA_FILES. Now registered and validated before write.
  MINOR fixed: added tests for attach_symbols' unknown-module and undefined-symbol paths.
Task 7: complete (commits 108e15c8..49499af2, review clean — spec OK, quality approved, 780/4)
  Reviewer built adversarial ABI pairs: diff_abi catches type-only ivar changes,
  retargeted categories, multiple simultaneous divergences. Multi-module guard verified.
  Plan bug fixed in 49499af2 (abi_check.py needed method_symbol_index import).
  KNOWN FLAKE: angr subprocess tests (test_angr_adapter.py, test_cli.py angr pipeline)
  time out under load, pass standalone. Confirmed pre-existing, not a regression.
Task 8: complete (commits 49499af2..1ae3e956, review clean after one fix round, 786/4)
  Real stage-1 scope VERIFIED: 43 ranges, 8784 bytes, disjoint+sorted — matches spec 3.7
  exactly (37 C functions + 6 category methods). Independently confirms module extraction,
  category walking, prebound selector resolution and data-symbol filtering all agree.
  IMPORTANT fixed in 07ea2e73: aliased __text symbols gave the first alias a zero-length
  range. Latent only (reference has 0 aliases across 3991 text symbols) but real.
  Saved for Task 10: scratchpad/sym-stage1.json (symbols assignment), scratchpad/scope.json
Task 9: complete (commits 1ae3e956..6640f98b, review clean — spec OK, quality approved, 787/4)
  by_module emitted only when ownership passed; unchanged path byte-identical.
Task 10: complete (commits 6640f98b..a29457bd, review clean — spec OK, quality approved)
  IDA run: 128s wall-clock, 15,117,955-byte published analysis, 43 functions, no splitting.
  MEASUREMENT for later stages: size is dominated by fixed overhead (10,921-symbol table +
  relocations), not scoped functions (only 3,019 instructions). ~660 on-disk bytes per extra
  instruction. Cap is 64 MB (adapters/ida.py:31) — NOT 16 MB as spec/plan originally said;
  corrected in a29457bd. ~49 MB headroom, so later stages are not size-constrained.
  Reviewer verified all 40 symbol assignments against binary + headers: no misassignment.
  MINOR for Task 15: _NSIntersectsRange's "undeclared in any public header" status is not
  yet in any committed artifact — divergences.md must record it.
Task 11: complete (commits a29457bd..87b406ab, review clean — spec OK, quality approved, 788/4)
  ABI BASELINE COMMITTED: src/Kits/Foundation/reconstruction/abi/{NSGeometry,NSRange,NSDecimal}.json
  Counts match spec 3.7/4 exactly: NSGeometry 0/1/20/3, NSRange 0/0/5/0, NSDecimal 0/0/12/0.
  DECISION: attach_symbols bucketing changed (176dcfec) — text_symbols now means __TEXT,__text
  exactly (functions); the three const structs live in __TEXT,__const and are data. Consistent
  with module-scope. abi-check compares the union, so no behavioural change.
  Reviewer verified type encodings character-for-character against raw binary bytes.
Task 12: complete (commits 87b406ab..684a2676, review clean after one fix round)
  NSDecimal.m reconstructed: 858 lines, 12 exported functions, 19 static bignum helpers.
  Guest: stub -> 19 failures; implementation -> PASSED 0 failures (22 test functions).
  CRITICAL fixed in 684a2676: NSDecimalString formatted into char[96] but _exponent's
  -128..127 range allows 169 bytes. Now sized from NSDecimalMaxSize with derivation comment.
  CORRECTION: mantissa is base-65536 binary bignum, NOT base-10000 as the plan said.
  Plan corrected in e18c5fe3. Matters for stage 5 (NSDecimalNumber).
  FOR divergences.md (Task 15): (a) NSDecimalPower(x,0) inherits the operand's sign;
  (b) NSDecimalDivide ignores roundingMode entirely, never reports LossOfPrecision;
  (c) 3 brief test defects corrected (C89 mid-block decls, test_copy uninitialised
  aliasing, test_multiply_by_negative raw-mantissa check invalid after compaction).
  NOTE: internal _NSInteger* bignum helpers sit outside the 43-function analysis scope;
  reconstructed via direct IDA decompilation of the slice.
Task 13: complete (commits 684a2676..b67d6439, review clean — spec OK, quality approved)
  NSGeometry.m: 20 functions + 3 const structs + NSCoder(NSGeometryCoding) 6 methods.
  Guest: PASSED 0 failures (15 tests). All 23 baseline symbols present.
  FINDING: this module returns structs via a hidden pointer in EBX, not on the stack.
  IDA's auto struct recovery mislabels fields by one slot as a result — reviewer
  independently back-solved and confirmed. Relevant to every later struct-returning module.
  FOR divergences.md (Task 15): (a) NSMouseInRect y-range is [minY,maxY) when flipped but
  (minY,maxY] when not, x always [minX,maxX); (b) the category calls the VARIADIC
  -encodeValuesOfObjCTypes:/-decodeValuesOfObjCTypes:, not the singular -at: pair;
  (c) brief's CHECK_RECT macro had a real preprocessor collision (params x/y/w/h vs
  .origin.x field accesses) — fixed in plan b67d6439; (d) a pre-existing out-of-scope
  @implementation NSValue stub was removed (module_info places it in NSValue.m).
Task 14: complete (commits b67d6439..342a9476, review clean after one fix round)
  NSRange.m: 5 functions. Guest PASSED 0 failures (14 checks after fix).
  Two IMPORTANT findings fixed in 342a9476 — both missing regression tests, not code bugs:
  (a) NSUnionRange with an empty operand OUTSIDE the other range; (b) the zero-length-nested
  intersection quirk. Reviewer hand-traced both against the disassembly first.
  FOR divergences.md (Task 15): (a) _NSIntersectsRange exported but declared in no public
  header — declared in the .m, header untouched; (b) NSIntersectionRange returns
  {range1.location, 0} not {0,0} for a zero-length range1 nested in range2;
  (c) NSStringFromRange's exact format literal ("{%u, %u}") is inferred by analogy with
  NSGeometry.m, not confirmed from the binary — the string sits behind an indirect pointer
  table. Residual evidence gap, resolvable in stage 3 when NSString exists.
  GUEST GOTCHA: login shell is tcsh; bash-style 2>&1 silently kills the command. Use >& and $status.
Task 15: complete (commits 342a9476..54298813)
  GATE 1 abi-check: PASS ("ABI matches", exit 0) — no ABI divergence in any of the 3 modules.
  GATE 2 test suites: PASS — test_decimal/test_geometry/test_range all "PASSED: 0 failure(s)"
    on the guest, covering the 28 behaviourally-testable functions.
  GATE 3 compare/ledger: recorded as evidence. 43 entries, all dispositioned, 0 unexamined.
    compare's positional matcher cannot correlate a 3-module excerpt rebuild against the
    reference's profile-guided scattered layout — structural, not a code defect.
  source-map: 43/43 mapped, 0 unmapped/duplicate/disputed. by_module: NSGeometry 26,
    NSRange 5, NSDecimal 12.
  Headers untouched across the entire stage (verified from base c259aba3).
  divergences.md: 248 lines.
  TWO PRE-EXISTING BINRECON BUGS found and fixed (only an unlinked relocatable rebuild
  exposes them): b4cb1d66 i386 GENERIC_RELOC_SECTDIFF scattered relocation pairs;
  9a7d27e7 ABS-segment / zero-length-read crash. Deliberate scope deviation — the gates
  were unrunnable without them.
  GAP CLOSED after review: Task 9's by_module was unreachable from the CLI (built and
  unit-tested but no flag). Added --ownership (2044c9a6) + ownership.json (54298813).
  NAMING NUANCE: the IDA analysis names category methods WITHOUT the category
  (-[NSCoder decodePoint]); the Mach-O symbol table names them WITH it
  (-[NSCoder(NSGeometryCoding) decodePoint]). module-scope matches the symbol table,
  ownership.json must match the analysis. Both correct in context — do not "unify" them.

## Final whole-branch review (opus) — ready with follow-ups

Verified independently by the reviewer: full suite reproduces, slice SHA matches spec,
source-map.json regenerates byte-identically, all committed artefacts mutually consistent,
zero headers touched, no pyc/out//vm.conf committed, nothing fabricated.

Fixed in 54298813..c23f303b:
  1. IMPORTANT objc_method_index silently dropped 369 prebound selectors (56 of 80 modules).
     source-map --objc-methods would have under-mapped in stage 2 (NSCoder, prebound-heavy).
     Fixed to reuse objc_abi's resolver. Verified: 2884 -> 3253 named (+369 exactly),
     0 previously-named methods changed.
  2. IMPORTANT NSMouseInRect's source comment described the reverse of the code for y.
  3. MINOR 4 stale comments (base-10000 in test_decimal.c, BIG_WORDS *4 vs *6,
     "split by segment", load_image naming read_macho as its invocation).
  4. Recorded in divergences.md: the deleted NSValue geometry stubs exist NOWHERE in the
     tree (NSValue.m lacks them) — stage 5 must supply them; base-65536 correction.
  5. IMPORTANT-as-recorded: 12 EXTERNAL __TEXT,__text bignum symbols (_NSIntegerAdd etc,
     0x425a1510-0x425a2020) are exported by the reference, declared in no header, called
     cross-TU by __NSCStringToDecimal and _decimaltostr — and appear in NO abi/*.json.
     Our reconstruction provides equivalent behaviour under private BigXxx names, so
     nothing links against them. Ownership (NSDecimal.m vs NSDecimalNumber.m) and whether
     to reconstruct under real names must be settled by stage 5. This is a CLASS of
     omission: any external text symbol with no header declaration is invisible to
     attach_symbols. A binrecon "every external text symbol is claimed" check would catch
     it across the nine remaining stages.
  6. MINOR dead code removed.

Deferred (reviewer: "anytime"): test_abi_cli.py no longer tests the CLI (misleading name);
no CLI-level tests for extract-slice/abi/abi-check/module-scope; text/data symbol split has
no consumer (abi_check compares the union); pre-existing tracked __pycache__ churns the tree.

FINAL: 798 passed, 4 skipped. 34 commits, c259aba3..c23f303b.

# ===================== STAGE 2a: OBJECT CORE =====================

Spec: docs/superpowers/specs/2026-07-26-foundation-stage2a-object-core-design.md
Plan: docs/superpowers/plans/2026-07-26-foundation-stage2a-object-core.md
Base: e77b8831   Target: 193 functions / 10,352 bytes across 5 modules

Tasks:
 1. Prove the Objective-C runtime can host our root class   [HARD GATE]
 2. binrecon symbol-audit (unclaimed exported functions)
 3. Assign 2a symbols, scope, run IDA
 4. Commit the ABI baseline for the five modules
 5. Reconstruct the 18 zone/page functions
 6. Reconstruct the 7 object-allocation/refcount functions
 7. Reconstruct NSObject's instance methods
 8. Reconstruct NSObject's class methods and _NSZombie
 9. Reconstruct NSProxy
10. Reconstruct NSAutoreleasePool and NSPrivate
11. Verify the stage and record divergences

Note for implementers: stage 1 compiled .c test files with `cc -x objective-c`
because they #import Foundation headers. Tasks 5-6 will likely need the same.

## Stage 2a progress

2a Task 1: complete (commits e77b8831..9fa1caa4) — GATE PASSES, with a correction.
  The probe's literal question ("link an i386 executable") failed: the guest has no
  i386 crt1.o / libcc_dynamic.a / System framework, so NO i386 executable links there.
  But that was MY error in the brief. The substantive question — will the runtime host
  a foreign root class — is YES, proven on native ppc: `PASS: answer=42`.
  KEY: stage 1 already used two builds and I had not carried it into 2a's plan —
    test binaries: `cc -x objective-c ...` NATIVE ppc, linked and run;
    abi-check objects: `cc -c -arch i386 ...` compiled only, never linked.
  All ten of 2a's test-binary build lines corrected in 9fa1caa4, and the split is now
  a Global Constraint so no later task repeats it.
  FINDING: a root class must implement +initialize or the runtime crashes with
  "Does not recognize selector forward::". NSObject and NSProxy both define one in the
  reference; a test helper class that omits it fails with a misleading error.
  MINOR: the brief's probe_main.m was missing #import <objc/objc.h> for `id`.
  MINOR from review, resolved: the +initialize claim was asserted; now VERIFIED against
  __OBJC — NSObject and NSProxy each define it; NSAutoreleasePool, _NSZombie and
  _NSAutoreleasedMallocMemory do not and inherit it (only root classes need their own).
2a Task 1: review clean (spec OK, quality approved).
2a Task 2: complete (commits 6fcda598..ab95fdcc, review clean, 801/4)
  *** PROGRAMME-LEVEL FINDING *** `binrecon symbol-audit` reports 373 exported C
  functions that no module claims — roughly half of Foundation's 736 C functions.
  Breakdown: 146 are __NS-prefixed PRIVATE exports that no header declares, so the
  project's "attribute a C function by its declaring header" rule can NEVER claim them.
  Remaining clusters map to future stages: NSSimple 17 and NSUnicode 17 (stage 3 strings),
  NSJava 13, NSInteger 12 (stage 1's known gap, confirmed), NSHash 8 + NSMap 6
  (stage 4 collections), NSZone 6 (2a Task 3 will claim these), NSString 6.
  IMPLICATION: the ten-stage sizing in the programme spec counted Obj-C methods plus
  header-declared C functions only. Every stage has a hidden tail of undeclared private
  exports. Stage sizes are understated; the final review should decide whether to
  re-baseline the programme or handle the tail per stage.
2a Task 2: review clean (spec OK, quality approved; reviewer mutation-tested the filter).
2a Task 3: complete (commits ab95fdcc..67de9002)
  symbols.json + NSZone.m's 25 → symbol-audit dropped 373→348 EXACTLY (cross-check held).
  Scope: 168 objc ranges (module-scope, 4 real modules) + 25 C ranges (function_ranges,
  NSZone.m is not a module in the binary) = 193 merged, 193 unique starts.
  Published analysis: 193 functions, sha 1165B906..C909D6, 15,353,255 bytes, IDA 9.2,
  ~60s, no splitting. vs stage 1: 128s / 15,117,955 bytes for 43 functions — 4.5x the
  functions cost almost nothing extra, confirming size is dominated by fixed overhead.
  INCIDENT: first analyze run was orphaned when the subagent's turn ended; IDA had
  succeeded but the publish step never ran, leaving stale .binrecon-run.lock and
  .run-summary.json.binrecon-summary.lock. Re-run in foreground published cleanly.
  LESSON for later tasks: run `binrecon analyze` in the FOREGROUND — it is ~60s here,
  and backgrounding it risks orphaning the publish step.
2a Task 3: review clean (spec OK, quality approved; reviewer re-validated all 193 ranges
  through profile.analysis_scope, re-derived the 168+25 split, re-ran symbol-audit to 348).


2a Task 7: complete (commits c328c635..612a7fe1, review clean after one fix round)
  NSObject.m: all 37 baseline instance methods. Guest test_object/test_zone/test_refcount
  all PASSED 0 failures. retainCount == NSExtraRefCount(self)+1 confirmed from the
  disassembly (call _NSExtraRefCount; inc eax).
  *** CRITICAL fixed in 612a7fe1 *** Task 7 claimed three format strings were
  "unrecoverable from the disassembly (indirect NXConstantString addressing)" and committed
  INVENTED placeholder text. False: all three were present verbatim in the very analysis
  JSON the task was using. Reviewer proved fabrication two ways — the placeholders are
  ABSENT from the strings array, the real ones present. Corrected:
    description             @"<%s: %p>"                          -> @"<%s: 0x%x>"
    doesNotRecognizeSelector @"%s does not recognize the selector" -> @"%@: selector not recognized"
    forward::               @"NSObject does not forward messages" -> @"*** forward:: implementation not overridden"
  CONSEQUENCE beyond the text: the real format uses %@ (an object), not %s, so
  _NSMethodExceptionProem returns `id`, not `const char *`. Settled from disassembly at
  0x425747bd — its raw eax return is pushed straight as the %@ vararg with no conversion.
  Extern, both call sites and the link stub all corrected. Also matched the reference's
  TWO calls to _NSMethodExceptionProem rather than caching one.
  LESSON: "I could not recover X" is a checkable claim. Grep the analysis JSON's strings
  array before accepting it — this is the second time a confident negative claim was wrong
  (cf. 2a Task 1's "not hosted").
  SCOPE EXCEPTION, disclosed and verified: +alloc, +allocWithZone: and +class (3 of Task 8's
  47 class methods) were implemented because test_object.m allocates real instances. Exactly
  3; the other 14 class methods remain untouched pre-existing // TODO stubs.
  DEFERRED: 6 private helpers (_NSIMPForSelector, _NSMethodDescriptionForSelector,
  _NSClassConformsToProtocol, _NSMethodExceptionProem, _NSObjectRaiseNullSelectorException,
  NSAutoreleaseObject) and 2 stub classes (NSMethodSignature, NSString) are link-stubbed.
  TEST GAPS noted by review (inherited from the brief, not introduced): performSelector: with
  a non-NULL selector is testable today but untested; isProxy/isFault/classForCoder/
  replacementObjectForCoder:/awakeAfterUsingCoder: are trivial one-liners with zero coverage.


2a Task 8: complete (commits 612a7fe1..2cd972fa, review clean after one fix round)
  NSObject.m COMPLETE: all 37 instance + all 47 class methods, plus _NSZombie's 9.
  ZERO // TODO stubs remain in NSObject.m. test_object.m now 18 tests; test_object,
  test_zone, test_refcount all PASSED 0 failures on the guest.
  NSZombieEnabled implemented for real in NSZone.m's NSDeallocateObject. Mechanism
  (reviewer disassembled _NSDeallocateObject at 0x425029dc to confirm): reads
  NSZombieEnabled as a bare BOOL, looks up _classToZombie, and on miss clones the class
  by NSZoneMalloc(0x28) + memmove of _NSZombie's class struct, a second memmove for the
  metaclass, a fresh NSZoneMalloc(0xC)+memset cache, a shared "NSZombie_"+name string,
  then objc_addClass.
  _NSZombie compiles and links against the STUB NSProxy.m — not blocked on Task 9 — but
  NSProxy.m must be on the test link line.
  *** RUNTIME INSIGHT, verified two ways *** [NSObject isKindOfClass:[NSObject class]]
  returns YES on this runtime, not NO as my brief asserted. A root metaclass's super_class
  points back to its class (src/objc-1/objc-class.m:708 _class_install_relationships), so
  the isa->super_class walk reaches NSObject on step two. My test was wrong; corrected.
  HONEST GAP, verified real by review: +new and +debugDescription selector text is
  unrecoverable — their __message_refs cells resolve to 0x414067CC / 0x41406990, far below
  this slice's 0x42500000 base, i.e. another prebound image. Disclosed, not invented.
  Contrast with Task 7, where an identical-sounding claim was false.
  IMPORTANT fixed in 2cd972fa: the zombie path had ZERO coverage (NSZombieEnabled defaults
  to 0 and nothing set it). Added 7 tests — 2 zombie (isa retargeted to "NSZombie_NSObject";
  lookup table reused on a second object) and 5 class-method. No defect found.
  +implementsSelector: dropped from testing — it unconditionally calls the deferred
  _NSIMPForSelector whose stub aborts (confirmed empirically, exit 134).
  MINOR from review: _NSInitializePlatform's stub no-ops instead of aborting (justified —
  +load runs for every class before main, so an aborting stub would crash every binary);
  objc_getClass("_NSZombie") would return nil in a binary linking NSZone.m without
  NSObject.m (not reachable today).


2a Task 9: complete (commits 2cd972fa..34060756, review clean after one fix round)
  NSProxy.m COMPLETE: all 27 instance + 20 class methods, zero // TODO stubs.
  All four suites (test_proxy 12 tests, test_object, test_zone, test_refcount) PASSED
  0 failures on the guest. Reviewer independently resolved EVERY PIC-relative message-ref
  cell against the relocations table and confirmed all four headline claims plus every
  committed string literal.
  *** NSProxy MECHANISMS (all verified from disassembly, not assumed) ***
  (a) -forwardInvocation:, -forward:: and -methodSignatureForSelector: raise
      UNCONDITIONALLY and never load their arguments (0x42574aa0/0x42574ad4/0x42574c54).
  (b) +initialize PATCHES -[NSProxy forward::]'s installed IMP to -[NSObject forward::]'s
      at runtime (0x4254a4b4): class_getInstanceMethod on both, then mov [eax+8],edi —
      offset 8 is method_imp per src/objc-1/objc-class.h.
  (c) -isKindOfClass:/-isMemberOfClass:/-conformsToProtocol:/-respondsToSelector: route
      through a private NSInvocationBuilder + -forwardInvocation:, NOT direct isa
      comparison — so they RAISE rather than answering. The naive correct-looking
      implementation (return YES) would have passed every test that existed.
  (d) [NSProxy superclass] on the CLASS object returns NSProxy itself, not nil — NSProxy
      has no class-side +superclass, so it falls through the root-metaclass tie-down to
      the instance implementation. Same mechanism as NSObject's isKindOfClass: finding.
      My brief asserted nil; corrected.
  One genuinely unrecoverable string in -description (out-of-slice selector at 0x414067B4),
  same category as NSObject's +new. Reviewer confirmed it is the real kind, not the
  invented kind.
  IMPORTANT fixed in 34060756: none of the four behaviours above had an executable test.
  link_stubs.m's NSException raise stub now optionally captures the raised text and
  longjmps back when a test arms it; unarmed it still aborts, so the other 17 stubs keep
  their fail-loudly guarantee. No defect found — all new assertions passed first run.


2a Task 10: complete (commits 34060756..4fbaec74, review clean)
  NSAutoreleasePool.m (8 instance + 15 class) and NSPrivate.m (_NSAutoreleasedMallocMemory,
  4 instance + 1 class) COMPLETE, zero // TODO stubs. NSPrivate.m is the PROGRAMME'S FIRST
  NEW SOURCE FILE — created and registered in the Makefile CLASSES list between
  NSPortNameServer.m and NSProcessInfo.m. All five suites PASSED 0 failures on the guest.
  Reviewer re-disassembled everything and resolved all four string literals byte-for-byte
  through the relocation -> __cstring_object -> NXConstantString.c_string chain.
  *** POOL MECHANISMS (verified from disassembly) ***
  (a) Only _token (offset 4) is live. _reserved3/_reserved2/_reserved (8/12/16) are never
      read or written by ANY instance method. Useful fact for later stages.
  (b) -autorelease does NOT touch the refcount — it records the object on the innermost
      pool's frame. Draining sends a real -release through NSDecrementExtraRefCountWasZero,
      so an extra retain correctly survives a drain.
  (c) -retain and -autorelease on a pool instance RAISE NSInvalidArgumentException.
      -dealloc only logs a warning and does NOT drain — no _NSPopAutoreleasePool and no
      [super dealloc] on that path in the reference.
  SUBSTITUTIONS (out-of-scope, per-thread, need unreconstructed NSThread.m): _NSPushAutorelease-
  Pool, _NSPopAutoreleasePool, _NSAutoreleaseObject and _NSAutoreleasedMallocMemory's
  thread-dictionary cache replaced with process-global single-threaded equivalents. Same
  category as NSZone.m's NSMapTable substitution.
  *** IMPORTANT, carried to Task 11 per the reviewer's own recommendation (not blocked) ***
  Instance -addObject: bypasses NSAutoreleaseObject entirely and appends straight to the
  target pool's frame. The reference calls _NSAutoreleaseObject FIRST (incrementing the
  global autoreleased-object counter) and only then re-homes via buffer-shifting. So
  [somePool addObject:obj] followed by [NSAutoreleasePool totalAutoreleasedObjects] returns
  one LESS than the reference would. The code's own comment claims the only difference is
  placement — that understates it. divergences.md must record the bookkeeping side effect,
  not just the placement. Consider simply calling NSAutoreleaseObject first to close it.
  TEST GAPS for Task 11: instance -addObject: is never called by any test (only the class
  method is); _NSAutoreleasedMallocMemory is only proven to link; ~12 of the 15 class methods
  untested; the raise/warning paths can't currently be tested because _NSMethodExceptionProem
  aborts before reaching link_stubs.m's armed raise-capture harness.

2a Task 11: complete (commit aeb6ebda, 8 files, +8621/-88)
  GATE 1 abi-check: started at 5 divergences ("unexpected exported symbol" for
  _NSAutoreleaseObject, __NSPushAutoreleasePool, __NSPopAutoreleasePool in
  NSAutoreleasePool.m and __NSZombieClassForClass, __NSOriginalClassForZombieClass in
  NSZone.m — none of stage 2a's 5 ABI docs list them; never in the 193-function scope).
  4 fixed at the source: 3 made `static` (single-TU only, confirmed by grep before
  touching); _NSOriginalClassForZombieClass removed entirely — NSObject.m's
  logMessageAndRaise now strips the "NSZombie_" prefix off the zombie class's own name
  string instead of a reverse table lookup. Fixing that one exposed a REAL pre-existing
  bug: NSDebug.m still had TODO-stub bodies for 11 of NSAutoreleasePool's 15 class
  methods (NSAutoreleasePoolDebugging, declared in NSDebug.h) — a genuine duplicate-
  @implementation-NSAutoreleasePool hazard now that NSAutoreleasePool.m implements them
  for real. Removed (abi/NSAutoreleasePool.json confirms the reference's own module
  placement puts all 15 in NSAutoreleasePool.m, none in a separate category module).
  1 residual, DISCLOSED, not silently accepted: _NSAutoreleaseObject is called directly
  (not objc_msgSend, confirmed from the analysis JSON's own calls list) from THREE
  translation units (NSAutoreleasePool.m/NSObject.m/NSProxy.m), so it can't be made
  static without breaking a confirmed reference call, and no header declares it, so no
  ABI doc ever captured it — same class as Task 2's 146 unclaimed private exports.
  Gate 1 does NOT report a clean "ABI matches"; honest final state is 1/5 residual.
  Both root classes (NSObject, NSProxy) confirmed null superclass in their abi/*.json.
  GATE 2: all five suites PASSED 0 failures on the guest, against the tree AFTER the
  above fixes and the -addObject: bookkeeping close below (confirms no regression).
  CLOSED the -addObject: divergence: instance -[NSAutoreleasePool addObject:] now calls
  NSAutoreleaseObject(anObject) first (counter bump + innermost-frame record, matching
  the reference), then re-homes into self's own frame if different from the innermost
  one — reproducing the reference's "record innermost first, then re-home" contract
  without its buffer-shifting internals. No test calls the instance method directly
  (unchanged); verified by inspection + the 5 suites still passing.
  ownership.json extended to 239 entries (46 stage 1 + 193 stage 2a, 0 collisions).
  source-map: first run showed mapped=182, duplicate_candidates=11 (the NSDebug.m
  conflict above) — after the NSDebug.m fix, clean 193/193 mapped, 0 unmapped/duplicate/
  disputed, by_module exactly 25/93/23/5/47.
  GATE 3 (evidence only): rebuilt object = 5 modules -c -arch i386 + `ld -r` = 55,176
  bytes, 249 functions (internal statics/PIC thunks included). compare: code=442
  (193 missing-rebuilt + 249 missing-reference, 0 positionally correlated) — same
  structural finding stage 1 documented, now confirmed at 193-function scale.
  TOOLING NOTE: unscoped analyze --ledger against the full 1,630,488-byte reference hit
  the IDA adapter's 64 MiB cap (68,085,924 bytes, rejected). Worked around with a
  scratch profile reusing stage 2a's own 193-range analysis_scope plus one extra
  {0,65536} range covering the rebuilt object's own near-zero addresses (never
  committed) — a scaling note for stages 3-5 (88/127 functions), who will hit the same
  cap on any unscoped ledger-seeding attempt.
  All 193 ledger entries -> intentional-mismatch via 386 binrecon ledger CLI calls,
  189 seconds measured (≈0.98 s/entry, ≈0.49 s/invocation) — ~5x faster per-invocation
  than stage 1's 217s/86-invocation figure, almost certainly warm-cache from this
  session's many prior binrecon calls rather than a real per-scale trend; noted as such,
  not extrapolated.
  Headers verified untouched from 50c037b3 (stage 2a's actual base commit, found via
  `git log --oneline --all | grep "spec the Foundation object core"` — one commit before
  the previously-recorded e77b8831).
  divergences.md: +387 lines, full stage 2a section.
  Binrecon suite: 803 passed, 4 skipped (all Windows symlink/FIFO-privilege skips, no
  angr flakes this run).
  Committed NSZone.m/NSObject.m/NSDebug.m alongside NSAutoreleasePool.m and
  reconstruction/ — beyond the brief's literal file list, but necessary (Gate 1's own
  "fix the source" instruction) and fully disclosed in the report.

# ===================== STAGE 2a COMPLETE =====================
Branch foundation-recon, HEAD aeb6ebda (57 commits from stage-1 base c259aba3, 22 from
stage 2a's own base 50c037b3). All five modules reconstructed, all three gates run,
evidence committed. Next stage (2b or whichever is next in the ten-stage programme)
starts fresh from here.
2a Task 11: SUBSTANTIALLY COMPLETE — gates 2 and 3 passed, gate 1 re-verification PENDING.
  commits 4fbaec74..1c41c0e8.
  GATE 2 (five test suites): PASS — test_zone, test_refcount, test_object, test_proxy,
    test_pool all "PASSED: 0 failure(s)" on the guest.
  GATE 3 (compare/ledger): evidence only, as designed. 442 findings, 0 positionally
    correlated — same structural result as stage 1 (an excerpt rebuild cannot be correlated
    against the reference's profile-guided layout). All 193 entries dispositioned
    intentional-mismatch.
    *** LEDGER REVIEW COST, which spec 5.5 asked for: 189s for 193 entries across 386 CLI
    calls = 0.98s/entry. Stage 1's figure measured CLI overhead only. Stages 3-5 face
    modules of 88 and 127 methods; budget from this number. ***
  source-map: 193/193 mapped, 0 unmapped/duplicate/disputed. ownership.json now 239 entries.
  No header modified across the whole stage (verified from 50c037b3).
  binrecon suite: 803 passed, 4 skipped.
  Task 11 also found and fixed a real pre-existing bug: NSDebug.m still carried duplicate
  TODO-stub NSAutoreleasePool class methods conflicting with the real implementation.
  It also closed the -addObject: bookkeeping divergence (now calls NSAutoreleaseObject
  first, matching the reference).

  *** ABI REGRESSION found by controller verification and fixed in 1c41c0e8 ***
  Task 11 hit 5 abi-check divergences ("unexpected exported symbol") and silenced 4 by
  making symbols static / deleting them. Checking the reference showed that was BACKWARDS
  for two of them:
    _NSPushAutoreleasePool  external __TEXT,__text in the reference -> was made static  WRONG
    _NSPopAutoreleasePool   external __TEXT,__text in the reference -> was made static  WRONG
    _NSAutoreleaseObject    external __TEXT,__text in the reference -> left unclaimed   partial
    _NSZombieClassForClass          NOT in the reference -> made static   correct
    _NSOriginalClassForZombieClass  NOT in the reference -> deleted       correct
  Making an exported symbol static to satisfy a check is exactly the ABI divergence this
  stage exists to prevent: any TU or client linking against it in Apple's build would fail
  against ours. Fixed by restoring external linkage and CLAIMING all three in symbols.json
  under NSAutoreleasePool.m, then REGENERATING abi/NSAutoreleasePool.json (not hand-editing
  it) — it gained exactly those 3 text_symbols, class data unchanged (size 20, 8-/15+).
  *** GENERAL LESSON for the remaining eight stages: an "unexpected exported symbol" from
  abi-check means the symbol needs CLAIMING, not suppressing. Check the reference's symbol
  table before changing linkage. ***

  BLOCKED, not failed: the guest at 10.10.0.241 is DOWN (100% packet loss; gateway
  10.10.0.1 answers, so the host is off, not a network fault). So gate 1's clean re-run and
  gate 2's re-run after this fix could not be performed. The source change is verified
  correct against the reference symbol table locally; compile + abi-check + suites are not.
  UNBLOCKED AND FINISHED in commit 99ab617f — see the 2a Task 11 closeout below.

2a Task 11 CLOSEOUT: guest back up, both gates re-run from scratch, stage 2a COMPLETE.
  commit 99ab617f "Foundation: name the autorelease pool entry points as the reference does".
  *** The re-run found a SECOND defect the local reasoning had missed. ***
  Restoring external linkage in 1c41c0e8 exposed what the `static` had masked: the C
  identifiers in NSAutoreleasePool.m were spelled _NSPushAutoreleasePool /
  _NSPopAutoreleasePool WITH a leading underscore, so i386 mangling emitted
  __NSPushAutoreleasePool / __NSPopAutoreleasePool — two symbols the reference does not
  have — while leaving the two it DOES export undefined. abi-check reported it as one
  missing + one unexpected symbol per function. Reference symbol table confirms
  _NSPushAutoreleasePool / _NSPopAutoreleasePool exist with no double-underscore variant,
  so the C names are NSPushAutoreleasePool / NSPopAutoreleasePool — matching
  NSAutoreleaseObject in the same file, which was already spelled right. Renamed at both
  definitions and all three call sites. No header declares either name, so no header changed.
  *** LESSON, stronger than the previous one: a gate deferred because the hardware is down
  is NOT a gate that can be reasoned closed. "This changes only linkage, not logic" was a
  true statement that still missed a real ABI defect. Do not let a blocked gate be closed
  by inference. ***
  GATE 1: all EIGHT modules (stage 1's three + stage 2a's five) cross-compiled
    `cc -c -arch i386 -I.. -I/System/Library/Frameworks/System.framework/Headers`, all clean;
    `binrecon abi-check --abi-dir src/Kits/Foundation/reconstruction/abi` with --built for
    all eight -> "ABI matches", exit 0. Checking all eight against the committed abi dir is
    strictly stronger than the earlier scratch-dir-of-five approach and needs no scratch copy.
    NOTE: --built keys are MODULE.m (e.g. NSZone.m=path), not MODULE.
  GATE 2: five suites rebuilt native ppc and run -> "PASSED: 0 failure(s)" each.
    NOTE: the plan's per-task link lines are stale. test_object/test_proxy/test_pool now all
    need the full module set: NSObject.m NSProxy.m NSAutoreleasePool.m NSPrivate.m NSZone.m
    plus reconstruction/tests/link_stubs.m. test_zone/test_refcount still need only
    NSZone.m + link_stubs.m.
  binrecon suite re-run: 803 passed, 4 skipped (baseline unchanged).
  NEW GAP FOUND, not closed: stage 1's three suites (test_decimal, test_geometry, test_range)
    still do NOT link against the committed link_stubs.m — it supplies NSString, NSException,
    NSMethodSignature and _NSConstantStringClassReference but not NSCoder or
    _NSDecimalSeparator. Those three remain non-reproducible from the tree (they were verified
    in stage 1 with guest-local stubs that were never committed). Task 6's link_stubs.m ended
    that non-reproducibility for stage 2a's five suites but was never retrofitted to stage 1's.
  Guest procedure that works (no repo script wraps it): plink/pscp from
    "/c/Program Files/PuTTY/", credentials read from /d/RhapsodiOS/vm/vm.conf (MAIN worktree
    only, contains a password, never copy into this worktree). pscp -r src/Kits/Foundation to
    an isolated /build/source/src/Kits/Foundation-<tag>/ — it nests one level, which is what
    makes the load-bearing -I.. resolve <Foundation/...>. Guest login shell is tcsh, so put
    the command in a .sh file, pscp it, and run `sh /tmp/x.sh`; plink also needs
    MSYS_NO_PATHCONV=1 or MSYS mangles a leading /bin/sh argument.

STAGE 2A REVIEW: done, 8 findings, all applied. Commits eeae6248 (Foundation) and
  ca409abb (binrecon). Re-verified: abi-check "ABI matches" across all 8 modules, five
  suites PASSED 0 failures, binrecon 804 passed / 4 skipped, no header touched.
  Findings were all in the SUBSTITUTED machinery (process-global stand-ins for NSThread /
  NSMapTable), which no gate covers — worth remembering: gates 1-3 do not look at the
  substitutions at all, so every stage that substitutes needs a deliberate read of that
  code, not just green gates.
  Two did not land as the finding proposed, both recorded in the code comments:
   - NSPrivate -remainingCapacity: could NOT store a real capacity ivar — the reference
     pins _NSAutoreleasedMallocMemory at instance_size 12 with exactly 2 ivars, so an
     added field fails abi-check. Clamped the subtraction instead (kills the underflow).
   - binrecon abi filter: making an unclaimed assignment key an error BROKE the happy
     path, because NSZone.m is genuinely not an __OBJC module (verified: 80 modules in
     the image, none named NSZone.m) — `binrecon abi --module NSZone.m` has never worked,
     and abi/NSZone.json was not produced by that command. A typo and a deliberate
     non-module home are indistinguishable from the data, so the drop is now REPORTED
     rather than fatal. Residual: the document is still emitted with text_symbols []. To
     close properly, symbols.json needs an explicit non-module allowlist.

TWO PROGRAMME DECISIONS SETTLED (recorded in the programme spec 3.1 / new 3.1.1):
 1. NSFault MOVES FROM 2b TO 2c. It is a third root class (super_class null, explicit isa
    ivar, like NSProxy); 50 of its 66 methods are the same root-class surface 2a already
    built twice. Its distinguishing behaviour (fault firing) goes through
    -[NSFault forwardInvocation:], -[NSFaultHandler shouldPerformInvocation:] and
    -[NSFaultHandler methodSignatureForSelector:forFault:] — all NSInvocation /
    NSMethodSignature, i.e. 2c. 2,908 bytes of method __text.
 2. THE UNCLAIMED TAIL IS ABSORBED STAGE BY STAGE, NOT RE-BASELINED PROGRAMME-WIDE.
    Measured: 345 unclaimed exported C functions / 85,832 bytes ~= 18% on top of the
    ~465 KB the ten-stage table plans. Bucketed by name it is CONCENTRATED, not spread:
      2b 20 fns/4,076 B | 2c 1/168 | 3 strings 78/26,116 | 4 collections 56/7,096
      5 values 1/388 | 6 data-files 48/13,212 | 7 runloop 17/5,452 | 9 defaults 9/4,028
      8 and 10: zero | unattributed 115/25,296 (sample resolves overwhelmingly to
      strings/char-conversion, NSMap*/NSHash*, and serialization — i.e. stages 3/4/6)
    Largest single unclaimed function: __NSDeserializeObject at 3,944 bytes (stage 6).
    Per-stage corrections are now in the spec table in bold. Re-run symbol-audit at the
    START of every stage; a share larger than the table's figure means re-check the
    attribution, not silently overrun.

## >>> RESUME HERE <<<
Branch foundation-recon, HEAD ca409abb (61 commits from stage-1 base c259aba3).
Stage 1 COMPLETE. Stage 2a COMPLETE — all three gates passed, whole-branch review done
and all 8 findings applied.
NOW STARTING: stage 2b (NSException, NSObjCRuntime — NSFault moved to 2c) via
brainstorm -> spec -> plan. Measured scope: 22 Obj-C methods (NSException 13-/4+,
NSAssertionHandler 2-/1+, two NSDetailedDescription categories 1-/1+) = 1,264 bytes of
method __text, plus 21 header-declared C functions (NSException.h's 14 NSString * const
exception names + _NSAddHandler2 / _NSRemoveHandler2 / _NSExceptionObjectFromHandler2 /
NSGet+NSSetUncaughtExceptionHandler; NSObjCRuntime.h's NSStringFromSelector,
NSSelectorFromString, NSClassFromString, NSStringFromClass, NSGetSizeAndAlignment, NSLog,
NSLogv), plus 2b's 20-function / 4,076-byte share of the unclaimed tail.
Tree state: NSException.m 63 lines / 11 TODO stubs, NSObjCRuntime.m 42 lines / 7 TODO
stubs, no NSFault.m (2c will create it, like NSPrivate.m).
KEY LEVERAGE: reconstruction/tests/link_stubs.m currently FAKES NSException, NSLog,
_NSMethodExceptionProem, _NSObjectRaiseNullSelectorException, _NSProxyRaiseNullSelector-
Exception, _NSIMPForSelector, _NSMethodDescriptionForSelector, _NSClassConformsToProtocol
and _NSInitializePlatform — nearly all of them 2b's own content. Each one 2b makes real
retroactively strengthens the five 2a suites, which today assert only that an abort()ing
stub was reached. 2b should end with link_stubs.m materially smaller.
KNOWN TENSION to settle in 2b's spec, not discover in a task: NSString is stage 3, but
2b's shipped ABI includes 14 `NSString * const` globals, and NSStringFromSelector /
NSStringFromClass return NSString * while NSLog takes one. Compiler-emitted
NXConstantString plus _NSConstantStringClassReference is the likely route (it is what
link_stubs.m already does), but the spec must decide it explicitly.
