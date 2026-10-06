# PPC Foundation `__NSstrtod` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the MOSXS PPC `__NSstrtod` converter and route PPC `NSScanner` double scanning through it with the target's parsing, rounding, end-pointer, and range-error behavior.

**Architecture:** Put the `Bigint` layout, shared arithmetic helpers, freelist, power-of-five cache, and shared tables in `NSBigint.h/.m`, so the module boundary can also serve the existing `___dtoa` target later. Put `_NSstrtod` and converter-only helpers/tables in `NSStrtod.m`; keep the existing i386 libc `strtod` path intact.

**Tech Stack:** Objective-C source modules, C floating-point and integer operations, Foundation project metadata, PPC ABI/source ownership JSON, live MOSXS PPC and i386 IDA databases.

**Spec:** `docs/superpowers/specs/2026-10-05-foundation-nsstrtod-design.md`

## Global Constraints

- Implement the `__NSstrtod` export and scanner route only for PPC; preserve i386 libc `strtod`.
- Preserve the scanner's existing locale decimal-separator normalization and update scan location using `_NSstrtod`'s returned end pointer.
- Keep shared helper names out of public export and source-symbol assignment manifests.
- Do not implement `___dtoa` or its `_quorem`-only dependency in this slice.
- Do not add or run tests or builds; verify against IDA and static source/metadata checks only.

## Review Focus

- Empty input, sign-only input, and decimal-point-only input must keep the end pointer at the original input when no numeric token is accepted.
- An exponent marker with no following digits must leave the end pointer at `e` or `E`; a valid exponent consumes its full digit run.
- Leading zeroes and the six accepted ASCII whitespace bytes must not perturb significant-digit and fractional-place accounting.
- Inputs around the sixteen-significant-digit cutoff must enter the correct fast or `Bigint` rounding path and preserve the IDA tie correction.
- Overflow and underflow must set `errno` to 34 only on the two confirmed range-error paths; ordinary conversions preserve errno.

These cases are review checkpoints for source-to-IDA comparison; runtime checks are excluded by the approved spec.

---

### Task 1: Shared `Bigint` arithmetic and state

**Files:**
- Create: `src/Kits/Foundation/NSBigint.h`
- Create: `src/Kits/Foundation/NSBigint.m`
- Modify: `src/Kits/Foundation/PB.project`
- Modify: `src/Kits/Foundation/Makefile.preamble`

**Interfaces:**
- Produces the shared `Bigint` structure with 32-bit fields at offsets 0, 4, 8, 12, and 16 and limbs beginning at offset 20.
- Produces linkable internal helpers with IDA-derived prototypes: `Bigint *Balloc(int k)`, `Bigint *Bfree(Bigint *)`, `Bigint *d2b(double value, int *exponent, int *bitCount)`, `double b2d(Bigint *, int *exponent)`, `int lo0bits(uint32_t *)`, `int hi0bits(uint32_t)`, `Bigint *i2b(int)`, `Bigint *pow5mult(Bigint *, int exponent)`, `Bigint *mult(Bigint *, Bigint *)`, `Bigint *lshift(Bigint *, int bits)`, `int cmp(Bigint *, Bigint *)`, `Bigint *multadd(Bigint *, int multiplier, uint32_t addend)`, and `Bigint *diff(Bigint *, Bigint *)`.
- Produces the shared `tens` and `bigtens` tables, the sixteen-entry size-class freelist, and the power-of-five cache seeded with 625.

- [ ] Add `NSBigint.m` to `PB.project` and the `CLASSES` list in `Makefile.preamble`; add `NSBigint.h` to the project header list.
- [ ] Define the shared type and helper prototypes in `NSBigint.h` with the IDA-confirmed five-word header layout.
- [ ] Implement `Balloc(int)` and `Bfree(Bigint *)` using `NSZoneMalloc(NULL, 20 + 4 * (1 << k))`, the sixteen size classes, and the observed no-lock freelist behavior; implement the cached power-of-five chain seeded by 625.
- [ ] Define `tens` and `bigtens` once for shared use; keep `_tinytens` in Task 3.
- [ ] Compare the struct layout, allocator/free behavior, cache chain, and shared table constants against IDA. Run `git diff --check -- src/Kits/Foundation/NSBigint.h src/Kits/Foundation/NSBigint.m src/Kits/Foundation/PB.project src/Kits/Foundation/Makefile.preamble` (expected: exit 0, no output).

### Task 2: Shared `Bigint` arithmetic helpers

**Files:**
- Modify: `src/Kits/Foundation/NSBigint.m`

**Interfaces:**
- Consumes the `Bigint` type, allocator, and cache from Task 1.
- Produces `d2b`, `b2d`, `lo0bits`, `hi0bits`, `i2b`, `mult`, `lshift`, `cmp`, `multadd`, and `diff` with the prototypes defined in Task 1.

- [ ] Implement each helper by matching its PPC IDA control flow, limb order, carry/borrow rules, and allocation class selection.
- [ ] Compare each helper body against its IDA entry listed in the spec and inspect helper call sites for prototype agreement. Run `git diff --check -- src/Kits/Foundation/NSBigint.m` (expected: exit 0, no output).

### Task 3: PPC decimal parser and rounding converter

**Files:**
- Create: `src/Kits/Foundation/NSStrtod.m`
- Modify: `src/Kits/Foundation/PB.project`
- Modify: `src/Kits/Foundation/Makefile.preamble`

**Interfaces:**
- Consumes `NSBigint.h` and the helper definitions from Task 1.
- Produces `double _NSstrtod(const char *string, char **endPointer)`.
- Defines converter-only `Bigint *s2b(const char *digits, int initialDigits, int totalDigits, int initialClass)`, `double ratio(Bigint *, Bigint *)`, `double ulp(double)`, and the five-value `tinytens` table in this module.

- [ ] Add `NSStrtod.m` to `PB.project` and the `CLASSES` list in `Makefile.preamble`.
- [ ] Implement `_s2b`, `_ratio`, `_ulp`, and `tinytens` by comparing their exact arithmetic and table values with the IDA bodies/data.
- [ ] Implement `_NSstrtod` lexical parsing: six ASCII C whitespace characters, optional sign, leading-zero/fraction accounting, up to sixteen significant digits, exponent acceptance only with following digits, full exponent consumption, and the 19,999 cap.
- [ ] Implement the target's table scaling and long-decimal correction loop, including estimate generation, comparisons, tie handling, and exact `Bigint` cleanup/recycling order.
- [ ] Preserve original-pointer end behavior for an unaccepted token, first-unconsumed-byte behavior for accepted input, and `errno = ERANGE` (34) only on confirmed overflow/underflow branches.
- [ ] Compare parser branches, each table value, long-decimal decisions, end-pointer movement, and cleanup paths against IDA. Run `git diff --check -- src/Kits/Foundation/NSStrtod.m src/Kits/Foundation/PB.project src/Kits/Foundation/Makefile.preamble`.

### Task 4: PPC scanner integration and reconstruction records

**Files:**
- Modify: `src/Kits/Foundation/NSScanner.m`
- Create: `src/Kits/Foundation/reconstruction/abi-ppc/NSStrtod.json`
- Modify: `src/Kits/Foundation/reconstruction/symbols.json`
- Modify: `src/Kits/Foundation/reconstruction/ownership.json`
- Modify: `src/Kits/Foundation/reconstruction/divergences.md`

**Interfaces:**
- Consumes `double _NSstrtod(const char *, char **)` from Task 3.
- Produces the PPC-only `__NSstrtod` export record owned by `NSStrtod.m` and the PPC/i386 behavior record.

- [ ] Route the PPC branch of `_NSScanDoubleFromString` through `_NSstrtod`; keep i386's `strtod` call and existing token normalization unchanged.
- [ ] Add `NSStrtod.m`'s PPC text export entry for `__NSstrtod` in `abi-ppc/NSStrtod.json`, add the source-symbol and ownership records, and leave shared internal helpers unassigned as exports.
- [ ] Record that i386 lacks this export and continues to use libc `strtod`.
- [ ] Inspect the scanner cursor update against IDA and confirm the PPC end pointer advances the same normalized buffer offset used by the existing libc path.
- [ ] Run `python -c "import json,pathlib; paths=[pathlib.Path('src/Kits/Foundation/reconstruction/abi-ppc/NSStrtod.json'),pathlib.Path('src/Kits/Foundation/reconstruction/symbols.json'),pathlib.Path('src/Kits/Foundation/reconstruction/ownership.json')]; [json.loads(p.read_text(encoding='utf-8-sig')) for p in paths]; print('JSON parse OK')"` (expected: `JSON parse OK`). Confirm the `__NSstrtod` definition is unique, owner/source mappings agree, and PB/Makefile source/header registration is present; then run `git diff --check` for the full slice (expected: exit 0, no output). Do not run tests or builds.

---

## Self-review

- **Spec coverage:** Task 1 covers the shared `Bigint` layout, allocator/cache, and tables. Task 2 covers the shared arithmetic closure. Task 3 covers converter-only helpers, lexical and range behavior, scaling, rounding, and cleanup. Task 4 covers scanner wiring, export/ownership records, and architecture divergence. `___dtoa` and `_quorem` remain out of scope.
- **Step granularity:** Each checklist item yields one module, behavior block, or metadata/integration result with a source/IDA check. The plan avoids runtime test steps because the approved spec explicitly excludes tests and builds.
- **Type consistency:** `NSBigint.h` owns the shared `Bigint` type and shared-helper declarations; `NSStrtod.m` consumes that interface and defines only converter-specific helpers. The public converter signature follows the approved spec.
- **Review focus:** The five parser and range conditions above are explicitly checked against IDA during the owning Task 3 review. Runtime tests are not prescribed.
- **Proportion:** Four tasks follow the shared state, arithmetic, converter, and integration boundaries. The plan records names, files, confirmed constants, and checks without transcribing helper implementations.
