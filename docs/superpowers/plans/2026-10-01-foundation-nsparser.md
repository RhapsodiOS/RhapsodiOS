# Foundation Property-List Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct Foundation's grammar-driven `NSParser` and use it for ASCII and strings-file property lists so `NSDictionary` can load file contents.

**Architecture:** Implement the generic parser and its syntax-node classes in `NSParser.m`, preserving the selectors and 32-bit instance layouts recorded in the ABI manifest. Build `NSPropertyListParser` and `_NSPListParserOldStyle` on that engine, then route dictionary file and URL initializers through the shared ASCII/typed-serialization parser entry point confirmed in IDA.

**Tech Stack:** Objective-C, the Foundation collection/string/data APIs already in this framework, IDA pseudocode for the Foundation i386 binary, and the repository ABI manifest.

**Spec:** IDA-confirmed methods and pseudocode for `NSParser`, `NSPropertyListParser`, `_NSPListParserOldStyle`, `NSString.propertyList`, `NSString.propertyListFromStringsFileFormat`, `NSDictionary._initWithData:`, and the file/URL loading methods; ABI source: `src/Kits/Foundation/reconstruction/abi/NSParser.json`.

### Encoded input buffer and cursor behavior (approved 2026-10-06)

- Keep parser input in a zone-owned buffer. Copy default C-encoded strings as
  bytes and other strings as UTF-16 code units; do not change the parser's ABI
  ivar layout.
- Keep narrow-input tokenization byte-oriented. Whitespace, comments, numbers,
  separators, and unquoted text consume bytes directly.
- Decode narrow characters only while appending quoted text: use the existing
  EUC decoder for the default Japanese EUC encoding and the existing NEXTSTEP
  byte conversion otherwise. Advance the source cursor by the decoder's byte
  consumption and preserve its remaining-length argument.
- For UTF-16 input, positions remain code-unit offsets. Free the input buffer
  through the parser's zone on reset and teardown.
- This design is implemented in `NSParser.m`; the 2026-10-06 analysis note
  records the PPC/i386 IDA recheck and static source audit. Object-level ABI
  comparison remains unverified because it requires a build.

## Global Constraints

- Preserve selectors, type encodings, and instance sizes recorded in `src/Kits/Foundation/reconstruction/abi/NSParser.json`.
- Keep changes inside the existing `src/Kits/Foundation/NSParser.m`, `src/Kits/Foundation/NSDictionary.m`, and Foundation ABI/build metadata required by the implementation.
- Follow IDA control flow and ownership behavior for parser entry points and dictionary loading.
- Support the project's historical ppc and i386 targets; do not introduce modern Foundation dependencies.
- Do not add or run tests unless requested; verify source integrity and ABI metadata with available static checks.

## Review Focus

- Empty input and trailing non-whitespace: parser entry points must distinguish empty input from a valid empty container and reject unconsumed tokens.
- Quoted strings with escapes, including unterminated quotes: preserve decoded characters and report malformed input.
- Nested arrays and dictionaries with missing separators or closing delimiters: reject malformed structure instead of returning partial containers.
- ASCII and Unicode input: keep token positions and token text consistent with the source string representation.
- Missing, unreadable, and non-file URLs: return nil through the same loading path without leaking the temporary data object.

---

### Task 1: Reconstruct the generic parser ABI and syntax nodes

**Files:**
- Modify: `src/Kits/Foundation/NSParser.m`
- Reference: `src/Kits/Foundation/reconstruction/abi/NSParser.json`

**Interfaces:**
- Produces: `NSParser` with the ABI-listed tokenizer, grammar, token, sequence, pair-suite, and error selectors; `_NSParserSyntaxNode` with `initWithType:arg:`, `copyWithZone:`, `description`, and `dealloc`.
- Consumes: existing `NSString`, `NSArray`, `NSDictionary`, `NSMutableArray`, `NSMutableDictionary`, `NSData`, `NSZone`, and exception APIs.

- [x] Define private class interfaces and ivars matching the ABI manifest's offsets and instance sizes.
- [x] Implement string setup, parser initialization/deallocation, tokenization configuration, token lookahead/consumption, and parse errors from the IDA behavior.
- [x] Implement grammar dispatch and syntax-node evaluation with type-1 sequences, type-2 `|` choices, and type-3 `||` backtracking choices confirmed by `parseForSyntaxNode`.
- [x] Implement generic dictionary, pair-suite, suite, separator, number, quoted/unquoted string, and data productions.
- [x] Parse `NSParser.json`, confirm all 47 manifest selectors have one exact source owner, and scan `NSParser.m` for trailing whitespace.
- [ ] Run the repository's object ABI check for `NSParser`; resolve any reported selector/layout mismatch.

### Task 2: Reconstruct plist-specific grammar consumers

**Files:**
- Modify: `src/Kits/Foundation/NSParser.m`

**Interfaces:**
- Consumes: Task 1's `NSParser` grammar and token APIs.
- Produces: `NSPropertyListParser` and `_NSPListParserOldStyle`, plus the two `NSString` parsing category methods.

- [x] Implement the cached plist grammar initialization and `parseDictionary` / `parseArray` productions as shown by IDA.
- [x] Implement old-style and modern strings-file dictionary parsing, including bracketed empty dictionaries and bracketless key/value pairs.
- [x] Implement `NSString.propertyList` and `propertyListFromStringsFileFormat` with the reference's end-of-input and exception behavior.
- [x] Parse `NSParser.json`, confirm all 47 manifest selectors have one exact source owner, and scan `NSParser.m` for trailing whitespace.
- [ ] Run the repository's object ABI check for `NSParser`; resolve any reported selector/layout mismatch.

### Task 3: Connect dictionary loading to property-list parsing

**Files:**
- Modify: `src/Kits/Foundation/NSDictionary.m`
- Modify: `src/Kits/Foundation/NSDictionary.h` only if the private data initializer must be declared for source consistency.

**Interfaces:**
- Consumes: `NSData` file/URL initializers, `NSDeserializer`, and Task 2's ASCII plist parser.
- Produces: `NSDictionary` file and URL factory/initializer methods and `_initWithData:` matching the IDA call and ownership flow.

- [x] Implement `_initWithData:` to preserve the receiver's zone, parse ASCII or serialized input, verify the result is a dictionary, and copy it into the receiver's zone.
- [x] Implement `initWithContentsOfFile:` and `initWithContentsOfURL:` using temporary `NSData` instances and release them on every return path.
- [x] Implement `dictionaryWithContentsOfFile:` and `dictionaryWithContentsOfURL:` as alloc/init/autorelease wrappers.
- [x] Parse `NSDictionary.json`, confirm all 109 manifest selectors have one exact source owner, and run `git diff --check` for `NSDictionary.m`.
- [ ] Run the repository's object ABI check for `NSDictionary`; resolve any reported selector/layout mismatch.

### Task 4: Integrate and review the parser reconstruction

**Files:**
- Review: `src/Kits/Foundation/NSParser.m`
- Review: `src/Kits/Foundation/NSDictionary.m`
- Review: `src/Kits/Foundation/Makefile.preamble`

- [x] Confirm `NSParser.m` is built exactly once and the existing plist-related dependencies are present.
- [x] Review exception paths, temporary-object ownership, recursion progress, and end-of-input enforcement against the IDA entry-point pseudocode.
- [x] Confirm `NSParser.m` registration, both JSON manifests, exact source selector owners, source whitespace, and tracked-file whitespace checks.
- [ ] Run the repository's object ABI checks and report unsupported or unverified runtime behavior explicitly.

### Static review notes (2026-10-03)

- `git diff --check` is clean for `NSParser.m`, `NSDictionary.m`, and both ABI
  manifests.
- A source-level exact-owner check finds all 47 selectors in `NSParser.json`
  exactly once. The parser integration selectors `initWithContentsOfFile:`,
  `initWithContentsOfURL:`, and `_initWithData:` are present in `NSDictionary.m`.
- The repository's `abi-check` command compares a built object against the
  ABI manifest. No `NSParser.o` or `NSDictionary.o` is present under the
  Foundation source tree, and this plan prohibits builds, so object-level
  selector encodings and class layouts remain unverified here. The source-level
  selector check is not a substitute for that comparison.
- The exact-owner `NSDictionary` manifest check also reports 12 base-class
  selectors without definitions, including coding/copy and collection
  utilities. They are outside this parser integration slice and remain open
  Foundation reconstruction work.
- IDA recheck of `makeNewString`, `autoreleaseAllStrings`, `setString:`, and
  `dealloc` showed that `_allStrings` at offset 60 is a lazily created,
  zone-backed `NSHashTable` using non-retaining object callbacks. `NSParser.m`
  now interns inline strings up to 512 characters, uses owned no-copy buffers
  for longer tokens, and autoreleases interned strings before freeing the
  table on input reset and parser teardown. Object-level ABI verification
  remains pending with the check above.

### Static check rerun (2026-10-04)

The exact-profile selector audit was rerun against `Foundation-i386`: 3,253
reference selectors, 3,300 source definitions, zero missing selectors,
renames, or duplicates, and 47 source extras. `NSParser.json` and
`NSDictionary.json` parse as JSON; `git diff --check` passes for the tracked
dictionary source, and a direct whitespace scan passes for the untracked
`NSParser.m` and ABI manifest. This does not replace object-level ABI
verification: no compiled `NSParser.o` or `NSDictionary.o` is present, so the
plan's ABI check remains open without a build.

### Static selector check rerun (2026-10-05)

The current ABI-manifest-to-source ownership scan finds all 47 `NSParser.json`
selectors exactly once in `NSParser.m` and all 109 `NSDictionary.json`
selectors exactly once in `NSDictionary.m`; no expected selector is missing,
duplicated, or outside its recorded owner. The initial source scan found one
source-only selector, `-[NSMutableDictionary initWithDictionary:copyItems:]`.
IDA places this selector on `NSDictionary` and `NSConcreteMutableDictionary`,
but not on `NSMutableDictionary`. The target `NSDictionary` implementation
builds key/value arrays from the source dictionary, copies values when
requested, and initializes through `initWithObjects:forKeys:count:`; the
concrete mutable class has its own optimized body. The worktree's base class
used to have an abstract stub and an extra mutable-class body. That gap is now
corrected: the generic IDA path is implemented on `NSDictionary`, and the
redundant `NSMutableDictionary` override is removed while
`NSConcreteMutableDictionary` keeps its specialized implementation. The fresh
selector audit now reports 109 expected and 109 source definitions, with no
missing, duplicate, or extra owners. Both ABI JSON files parse, and
`git diff --check` passes for `NSDictionary.m`. No `NSParser.o` or
`NSDictionary.o` exists under the Foundation source tree, so object-level ABI
comparison remains unverified without a build.

### Encoded input buffer reconstruction (2026-10-06)

An IDA recheck of PPC `setString:` and `nextToken` confirmed the parser stores
input in a zone-owned buffer: default C-encoded input is copied as bytes, while
other input is copied as UTF-16. The source now follows those two storage paths,
frees the buffer through the parser zone, and advances narrow-input positions by
the bytes consumed by the existing EUC decoder. NEXTSTEP-encoded bytes use the
existing NEXTSTEP-to-Unicode conversion helper. UTF-16 positions remain code
unit offsets. The `NSParser` ivars and ABI manifest are unchanged.

The i386 selector audit still reports zero missing, renamed, or duplicate
selectors. `NSParser.json` parses, and a direct whitespace scan of the
untracked `NSParser.m` reports no trailing whitespace. The 163 selector extras
are the existing source-only Foundation reconstruction methods recorded in
the broader audit. No build or tests were run. Object-level ABI comparison
remains open because it requires a build.

### Static selector check rerun (2026-10-06)

The current source-level ownership scan finds all 47 selectors in
`NSParser.json` exactly once in `NSParser.m`, with no missing or duplicate
owners. `NSParser.json` and `NSDictionary.json` parse as JSON. `git diff --check`
passes for the tracked `NSDictionary.m` slice; a direct whitespace
scan passes for the untracked `NSParser.m` and ABI manifests. Object-level ABI
comparison remains unverified because it requires a build, which was not run.

### Encoded cursor fidelity correction (2026-10-06)

A paired PPC/i386 IDA recheck found EUC and NEXTSTEP conversion only in the
quoted-string path. Whitespace, comments, numeric scanning, separators, and
unquoted text operate on the stored byte stream directly. `NSParser.m` now
keeps `NSParserCharacterAt` byte-oriented for narrow input and performs the
encoding conversion while appending quoted input characters, advancing the
cursor by the bytes consumed. This prevents other tokenizer paths from
interpreting EUC byte sequences as decoded Unicode prematurely. The parser
instance layout and ABI manifest are unchanged. The EUC call also preserves
the target's remaining-length argument, including its final-sequence edge
behavior. Static source checks only; no tests or builds were run.

### Static selector and whitespace check rerun (2026-10-06)

Both ABI JSON files parse, and the source-method audit finds all 47
`NSParser.json` selectors exactly once in `NSParser.m` and all 109
`NSDictionary.json` selectors exactly once in `NSDictionary.m`, with no extra
definitions in either module. A direct whitespace scan finds no trailing
whitespace in either source file; `git diff --check` reports no whitespace
errors for the tracked parser and dictionary files. The object-level ABI
checks remain open because neither `NSParser.o` nor `NSDictionary.o` exists in
the worktree; this static audit does not verify compiled selector encodings or
instance layouts, and no build or tests were run.

### Encoded cursor clamp correction (2026-10-06)

The PPC and i386 `nextToken` pseudocode both compute the extra byte advance
after `NSNextEUCToUnicode` as a signed difference and clamp negative values to
zero. `NSParserAppendQuotedInputCharacter` now preserves that clamp instead of
performing the subtraction as unsigned arithmetic. No ABI fields or selectors
changed. Static source checks only; no tests or builds were run.

### Source-declared ABI layout recheck (2026-10-07)

Compared the private declarations in `NSParser.m` with `NSParser.json`.
`NSParser` declares the same 20 ivars in manifest order at 32-bit offsets
4 through 68, including the four one-byte tokenizer flags at offsets 32–35.
`NSPropertyListParser` and `_NSPListParserOldStyle` add no ivars, preserving
the manifest's 72-byte instance size. `_NSParserSyntaxNode` declares `type`,
`theIndex`, and `arg` at offsets 4, 8, and 12, matching its 16-byte manifest
size. This verifies the source-declared layout only; compiled object ABI
verification remains open because it requires a build.

### Current-tree ABI verification recheck (2026-10-08)

The current source-to-reference selector inventory reports zero missing,
renamed, or duplicate selectors for both Foundation targets. A repository-wide
search under `src/` and `tools/` found no existing `NSParser.o` or
`NSDictionary.o` to feed to the object-level `abi-check`; that check therefore
remains unverified until a Foundation object is built. No build or test was run.

### NSDictionary source-selector reconciliation (2026-10-09)

The earlier static review note that listed 12 `NSDictionary` base selectors
without source definitions describes an older source snapshot. A fresh
architecture-aware source inventory against the current shared manifest finds
all 41 base instance selectors and all 9 class selectors in source for both
i386 and PPC; no base-manifest selectors are missing. The 10 additional
instance methods counted on the class are the `NSDictionary(NSFileAttributes)`
category and do not replace base definitions. This source check does not
verify compiled encodings or layouts; object-level ABI comparison still
requires a build and remains unverified.

### Dual-target selector ownership reconciliation (2026-10-09)

The earlier note that `NSDictionary.json` had 12 base-class selectors without
source definitions is stale. The current `selector_check.py` run against the
PPC image reports 3,397 target selectors and 3,397 source definitions with no
missing selectors, renames, or duplicates. The i386 run reports 3,253 target
selectors and 3,284 source definitions with no missing selectors, renames, or
duplicates; the 31 extras are PPC-only URL-loading methods. This verifies
source selector ownership, not object-level ABI encodings or runtime behavior.
The object ABI check remains unverified because it requires built objects and
the project workflow prohibits builds in this reconstruction pass.

### Static check refresh (2026-10-10)

- The current dual-architecture selector audit reports 3,253 i386 reference
  selectors and 3,283 source definitions, with zero missing, renamed, or
  duplicate selectors; the 30 extras are the documented PPC-only `NSURL` and
  `NSURLHandle` APIs. PPC reports 3,397 reference selectors and 3,397 source
  definitions, with zero missing, extra, renamed, or duplicate selectors.
- Static layout inspection shows the `NSParser` source ivars at offsets 4
  through 68, instance size 72, and `_NSParserSyntaxNode` at offsets 4, 8, and
  12, instance size 16. The i386 and PPC ABI manifests agree; parser subclasses
  have instance size 72 and no additional ivars.
- A recursive search including ignored files found no existing `NSParser.o` or
  `NSDictionary.o`. Object-level ABI comparison remains unverified because it
  requires those objects and this plan prohibits builds. No tests or builds
  were run.

### Current source ownership recheck (2026-10-13)

Re-ran the repository source-definition scanner against `NSParser.json` and `NSDictionary.json`. All 47 NSParser selector records and all 109 NSDictionary selector records resolve to exactly one current source definition. This supersedes the earlier note that listed 12 NSDictionary methods without owners; that count is stale after subsequent reconstruction. A recursive worktree search found no `NSParser.o` or `NSDictionary.o`, so object-level ABI comparison remains unverified and its plan checkboxes stay open. No tests or builds were run.

### Static i386 instance-layout check (2026-10-15)

Calculated the i386 layout from the current class declarations in
`NSParser.m` and compared it with `reconstruction/abi/NSParser.json`. All 20
`NSParser` ivar offsets and its 72-byte size match; all three
`_NSParserSyntaxNode` ivars and its 16-byte size match; and
`NSPropertyListParser` plus `_NSPListParserOldStyle` inherit the 72-byte size
with no additional ivars. This is source-level layout evidence only. The
object ABI check remains open because it requires a compiled object and this
workflow does not build Foundation.

The same source-level check was applied to `NSDictionary.h`,
`NSDictionary.m`, and `reconstruction/abi/NSDictionary.json`: the two base
classes have no ivars at size 4, and each concrete dictionary has `_table` at
offset 4 and `_retainCount` at offset 8, with total size 12. All four class
layouts match the i386 manifest. The object-level check for both modules
remains unverified without compiling objects.
