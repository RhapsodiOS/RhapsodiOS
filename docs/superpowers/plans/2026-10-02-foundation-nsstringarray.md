# Foundation `NSStringArray` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reconstruct the Foundation i386 `NSStringArray` and its three private UTF-8 element classes from the IDA reference and checked-in ABI manifest.

**Architecture:** Add one private implementation module containing `NSStringArray`, `_NSUTF8String`, `_NSUTF8ASCIIString`, and `_NSUTF8NonASCIIString`, then register it in the Foundation source list. Keep packed UTF-8 bytes in copied `NSData`, lazily cache the ABI-sized element records, and follow the reference's array ownership, matching, and word-extraction helper behavior.

**Tech Stack:** Objective-C with manual retain/release, existing Foundation classes, IDA pseudocode, and the repository's selector/ABI static audit.

**Spec:** `docs/superpowers/specs/2026-10-02-foundation-nsstringarray-design.md`.

## Global Constraints

- Implement every class and selector recorded in `src/Kits/Foundation/reconstruction/abi/NSStringArray.json`.
- Preserve the manifest's instance sizes, ivar offsets, selector encodings, and superclass relationships.
- Keep the implementation interfaces private and preserve existing Foundation manual retain/release conventions.
- Do not modify unrelated string or collection modules; do not reconstruct `NSPathStore2` or neighboring private string classes.
- Do not add or run tests or builds; verify source hygiene and selector coverage with static checks only.
- Use IDA caller and helper evidence for option branches and parser behavior; do not infer undocumented semantics from selector names.

## Review Focus

- Empty packed data, missing terminal NUL, and lazy count calculation: compare `initWithUTF8Data:`, `count`, and `objectAtIndex:` to their IDA guards and outcomes.
- Releasing cached non-ASCII elements and owner arrays: compare `_NSUTF8String` retain/release and `NSStringArray` teardown to the helper reference-count paths.
- ASCII separator fast path versus general component splitting: confirm the separator-width branch and terminal NUL behavior against IDA.
- Matching option values and bit-vector index mapping: account for every branch visible in IDA without assigning unsupported option meanings.
- Plain, HTML, RTF, and non-ASCII word extraction: preserve mode-specific scanning, case conversion, locale delegation, and duplicate elimination.

---

### Task 1: Add the private classes, ABI layout, and packed-data lifecycle

**Files:**
- Create: `src/Kits/Foundation/NSStringArray.m`
- Modify: `src/Kits/Foundation/Makefile.preamble`
- Review: `src/Kits/Foundation/reconstruction/abi/NSStringArray.json`

**Interfaces:**
- Produces `NSStringArray : NSArray` with `_count`, `_extraRefCount`, `_data`, `_strings`, and `_reserved` at the manifest offsets.
- Produces `_NSUTF8String : NSString`, `_NSUTF8ASCIIString : _NSUTF8String`, and `_NSUTF8NonASCIIString : _NSUTF8String` with exact manifest ivars and sizes.

- [x] Declare the four implementation-private Objective-C classes using the manifest's exact superclass and ivar layouts.
- [x] Add `NSStringArray.m` to the Foundation source list.
- [x] Implement `init`, `initWithUTF8Data:`, lazy `count`, `UTF8Data`, and `dealloc`; preserve copied backing data, the `-1` lazy-count sentinel, terminal-NUL validation, decoded-string cleanup, and backing-data release as observed in IDA.
- [x] Implement owner-array retain/release/count behavior in `_NSUTF8String`, including the target's saturation and lock-helper behavior; keep abstract allocation/initialization methods raising the observed exception.
- [x] Compare each lifecycle branch against the corresponding IDA body and record no unsupported ownership assumptions.

### Task 2: Implement construction, indexed access, and UTF-8 element behavior

**Files:**
- Modify: `src/Kits/Foundation/NSStringArray.m`

**Interfaces:**
- Consumes: the classes and packed-data lifecycle from Task 1.
- Produces: all four class factories; array/component initializers; indexed access; the `_NSUTF8ASCIIString` and `_NSUTF8NonASCIIString` NSString primitives in the ABI manifest.

- [x] Implement `stringArray`, `stringArrayWithUTF8Data:`, `stringArrayWithArray:`, and `stringArrayWithComponents:separatedByString:` as factory wrappers matching IDA allocation and autorelease behavior.
- [x] Implement `initWithArray:` and `initWithComponents:separatedByString:` with the IDA-confirmed UTF-8 packing, special NSStringArray handling, ASCII separator fast path, fallback splitting, and count assignment.
- [x] Implement `objectAtIndex:` lazy allocation of contiguous 16-byte records; point ASCII records into packed data and create owned decoded NSString values for non-ASCII records.
- [x] Implement ASCII element length, character access, range copy, hash, encoding, and C-string methods using `_bytes` and `_length`; implement non-ASCII primitives by the observed `_realString` delegation and `_length` behavior.
- [x] Implement `containsObject:` using the same comparison behavior as the IDA body.
- [x] Check index/range and empty-input branches against IDA and confirm every declared element-class selector is present exactly once.

### Task 3: Implement concatenation, string matching, and bit vectors

**Files:**
- Modify: `src/Kits/Foundation/NSStringArray.m`

**Interfaces:**
- Consumes: packed UTF-8 representation and the indexed-array APIs from Tasks 1–2.
- Produces: append operations, string/string-array matching methods, bit-vector conversion, and private matching/encoding helpers needed by their callers.

- [x] Implement `stringArrayByAppendingStringArray:` and `stringArrayByAppendingStringArrays:resultingBitVectors:` with the exact packed-data and optional result-vector mapping behavior from IDA.
- [x] Implement `_newBitVectorForStringArray` behavior: deduplicate input elements, preserve first-seen output order, and map input positions into the bit vector as observed.
- [x] Implement `_findString`, `_findStringArray`, and `_encodeStringAsUTF8` only to the extent established by their callers and decompiled helper bodies.
- [x] Implement `matchesString:option:`, `bitVectorMatchingString:option:`, `matchesStringArray:option:eachMustBeMatched:`, `bitVectorMatchingStringArray:option:`, and `stringArrayWithBitVector:`; retain the numeric option branches from IDA without inventing option semantics.
- [x] Compare empty arrays, duplicate strings, unmatched entries, and each observed option branch with IDA pseudocode and helper call flow.

### Task 4: Implement word extraction and perform static integration review

**Files:**
- Modify: `src/Kits/Foundation/NSStringArray.m`
- Review: `src/Kits/Foundation/reconstruction/abi/NSStringArray.json`

**Interfaces:**
- Consumes: constructors, packing, and deduplication from Tasks 1–3.
- Produces: the four word-extraction initializers and a complete selector-covered module.

- [x] Implement `initWithWordsOfString:convertCase:locale:` with the target scanner, locale-sensitive character handling, initial-letter rule, case flags, and duplicate-table flow.
- [x] Implement `initWithWordsOfData:convertCase:locale:`, `initWithWordsOfHTMLData:convertCase:`, and `initWithWordsOfRTFData:convertCase:` with their distinct confirmed plain, HTML, RTF, and non-ASCII fallback paths.
- [x] Confirm case conversion values, mode-specific skipping, token boundaries, and duplicate behavior against `_appendWords` and its callers in IDA.
- [x] Run `git diff --check` and the existing Foundation i386 selector audit; confirm every selector in `NSStringArray.json` is accounted for without duplicates or renames.
- [x] Do not run tests or builds, and report behavioral validation as unverified.
