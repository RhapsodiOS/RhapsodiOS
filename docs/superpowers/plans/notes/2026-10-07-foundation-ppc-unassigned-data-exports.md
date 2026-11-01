# Foundation PPC unassigned data exports (2026-10-07)

Rechecked the nine PPC data exports that have no source owner in
`reconstruction/ownership.json` and are absent from the module assignments in
`reconstruction/symbols.json`, using the live MOSXS PPC IDA database.

| Export | Address | Segment | First byte |
| --- | ---: | --- | ---: |
| `_YES` | `0x425cbaa8` | `__const` | `0x01` |
| `_dummyPad1` | `0x425cbaac` | `__const` | `0x00` |
| `_NO` | `0x425cbaaf` | `__const` | `0x00` |
| `_dummyPad2` | `0x425cbab0` | `__const` | `0x00` |
| `_nil` | `0x425cbab4` | `__const` | `0x00` |
| `_Nil` | `0x425cbab8` | `__const` | `0x00` |
| `__NSMsgSendCount` | `0x42626078` | `__data` | `0x00` |
| `___NSObjectAllocatorLock` | `0x42626254` | `__data` | `0x00` |
| `_NULL` | `0x42626360` | `__data` | `0x00` |

`db.xrefs.to_ea` returned no references for any of the nine names. The first
six exports occupy isolated bytes in `__const`; the remaining three are
zero-initialized data. These observations establish their current values and
lack of static references, but do not identify which source module owns them
or what relocation-level users expect. Their symbol and ownership assignments
therefore remain open rather than being guessed from spelling alone.

No source, ABI, or symbol-map changes were made. This was a read-only IDA and
metadata audit; no tests or builds were run.

## DR2 i386 counterpart check (2026-10-07)

Eight of the nine unassigned PPC exports also exist in the DR2 i386 image:

| Export | i386 address | Segment | First byte |
| --- | ---: | --- | ---: |
| `_YES` | `0x425a6374` | `__const` | `0x01` |
| `_dummyPad1` | `0x425a6375` | `__const` | `0x00` |
| `_NO` | `0x425a6378` | `__const` | `0x00` |
| `_dummyPad2` | `0x425a6379` | `__const` | `0x00` |
| `_nil` | `0x425a637c` | `__const` | `0x00` |
| `_Nil` | `0x425a6380` | `__const` | `0x00` |
| `__NSMsgSendCount` | `0x42602078` | `__data` | `0x00` |
| `_NULL` | `0x42602438` | `__data` | `0x00` |

IDA reports no xrefs to these i386 symbols either. Their order and first-byte
values match the PPC entries; `___NSObjectAllocatorLock` remains PPC-only. This
cross-target check confirms that the six constant/padding bytes and the two
zero-initialized counters/slots are common unresolved exports, but still does
not identify their source owners or establish a declaration contract. No
source or ownership claims were added.

## Neighboring symbol context (2026-10-07)

The PPC data-name pass shows `_YES`, `_dummyPad1`, `_NO`, `_dummyPad2`, `_nil`,
and `_Nil` as a compact group in `__const`, with no named data object between
that group and the next nearby jump table. In `__data`, `__NSMsgSendCount` is
between `__portCoderCache` and `_Signature`; `___NSObjectAllocatorLock` is
between `__NSIsMultiThreaded` and `___NSExternRefCountLock`; and `_NULL` is
between `__NSAltClassNameFromString` and `_classToZombie`. The corresponding
i386 groups have the same `__NSMsgSendCount` and `_NULL` neighbors, while the
allocator lock cluster differs by target.

The adjacent globals do not establish a common source owner: they span port
coding, method signatures, object runtime state, and individual class retain
locks. No source assignment is inferred from link order or symbol spelling.
The data exports remain unassigned until a declaration, object-level map, or
behavioral reference identifies their owner and width.

IDA's `get_data_size_at` reports a one-byte item at every listed symbol
address in both databases. Reading four bytes at those addresses shows the
expected leading value followed by neighboring zero bytes, but does not prove
that each C object is one byte wide; IDA may have split the underlying
storage into separate named items. Keep ABI widths unset until the source
declaration or object-level metadata is recovered.

The allocator-lock comparison is specifically non-equivalent across targets:
the i386 `___NSAllocatorLock` has three references, all in
`__NSToDoAtFirstThreadStart` / `__NSToDoAtLastThreadExit`, and the source owns
that i386-only `mutex_t` in `NSThread.m`. PPC's `___NSObjectAllocatorLock`
has no references and `NSThread.m` has no corresponding PPC declaration or
lifecycle path. Its similar placement among lock globals is not enough to
assign the PPC export to `NSThread.m` or reuse the i386 contract.

## RhapsodiOS source-tree ownership recheck (2026-10-07)

Searched the Foundation and Objective-C runtime source trees for definitions
of all nine names. No source definition or runtime reference was found. The
available Objective-C headers define `YES`, `NO`, `nil`, and `Nil` as macros;
that spelling evidence does not explain the separate exported data symbols in
the Foundation image. Keep all nine exports unassigned until object or link
metadata identifies their source owner and storage widths.

The current worktree has no PPC object files or link map for Foundation. The
available Foundation object files under `tools/binrecon/out` are partial i386
objects or host-side ABI-check objects, and the current i386 binrecon summary
has `rebuilt: null`. These artifacts cannot establish the PPC symbols'
translation-unit ownership or storage widths.

## Cross-framework consumer check (2026-10-08)

Checked the live AppKit and System IDA name tables for these nine Foundation
exports. Neither database has matching imported names for `_YES`, `_NO`,
`_nil`, `_Nil`, `_NULL`, `_dummyPad1`, `_dummyPad2`, `__NSMsgSendCount`, or
`___NSObjectAllocatorLock`. Re-read 16 bytes at each export in both Foundation
images: the expected first-byte values are present, followed by bytes belonging
to neighboring storage, so the raw spans do not establish object widths. IDA
continues to report one-byte items and no direct xrefs at each named address;
`types.get_at` and address comments are empty for each symbol in both images.

This adds no source-owner or declaration evidence. The nine PPC data exports
remain unassigned; no source, ABI, or symbol-map changes were made. No tests or
builds were run.

## Export visibility and item-size recheck (2026-10-08)

The live PPC IDA name table marks all nine symbols public and non-weak. Its
data-item API still reports one byte at each symbol start; the nearest named
items preserve the previously observed offsets (`_YES` to `_dummyPad1`: 4
bytes, `_NO` to `_dummyPad2`: 1 byte, `_dummyPad2` to `_nil`: 4 bytes, and
`_nil` to `_Nil`: 4 bytes). Public visibility confirms these are exported
names, but neither that status nor the spacing establishes their source
translation unit or declared object widths. The names remain unassigned in
source and ABI metadata. No tests or builds were run.

## Mach-O dynamic-symbol module ownership (2026-10-08)

Parsed the `LC_DYSYMTAB` table of contents and module table from both current
Foundation images and mapped each symbol-table index to its input module. All
eight common exports map identically across i386 and PPC: `_YES`, `_NO`,
`_nil`, `_Nil`, `_NULL`, `_dummyPad1`, and `_dummyPad2` map to
`ObjC.subproj_subproj.o`; `__NSMsgSendCount` maps to
`DO.subproj_subproj.o`. PPC-only `___NSObjectAllocatorLock` maps to
`Misc.subproj_subproj.o`.

This establishes the linked subproject object for each export and is stronger
than adjacency or spelling, but those aggregate object names do not identify a
specific `.m` translation unit or C declaration width. No source or ABI owner
was assigned from this evidence alone. No tests or builds were run.

## Reachable source-history recheck (2026-10-08)

Repeated exact-symbol searches in the reachable Git history for
`__NSMsgSendCount`, `___NSObjectAllocatorLock`, and `_dummyPad1` returned no
commits defining them in `src/Kits/Foundation` or `src/objc-1`. The current
source search likewise has no declarations or references. This adds no
translation-unit owner or width evidence, so the exports remain unassigned.
No source, ABI, ownership, or symbol-map changes were made; no tests or builds
were run.

## `objc-globaltext.m` candidate check (2026-10-08)

Checked the closest apparent source candidate after the module-table mapping:
`src/objc-1/objc-globaltext.m` is part of the Objective-C runtime project and
contains a generic comment reserving space for global constants, but its actual
definitions are the NX hash/map prototypes; none of the six `_YES`/`_NO`/`_nil`/
`_Nil`/padding exports is declared there. The module-table label
`ObjC.subproj_subproj.o` is an aggregate object and does not tie an export to
this translation unit. No owner or width was assigned from that hint. Exact
symbol searches in the current runtime and Foundation sources remain empty;
no tests or builds were run.

## External-definition table ranges (2026-10-08)

Re-read the PPC `LC_DYSYMTAB` module records and their external-definition
ranges. `DO.subproj_subproj.o` contains 26 external definitions, including
`__NSMsgSendCount` at symbol index 4223; `Misc.subproj_subproj.o` contains 247,
including `___NSObjectAllocatorLock` at index 4476; and
`ObjC.subproj_subproj.o` contains 80, including `_NO`, `_NULL`, `_Nil`, `_YES`,
`_dummyPad1`, `_dummyPad2`, and `_nil` at indices 4530, 4540, 4542, 4543, 4562,
4563, and 4564. This confirms the exports belong to broad aggregate objects,
not individual source files. The per-translation-unit owners and C storage
widths remain unproven, so no source, ABI, ownership, or symbol-map assignment
was made. Static Mach-O table inspection only; no tests or builds were run.

### `__NSMsgSendCount` reconstruction definition (2026-10-08)

The sender reconstruction now defines `__NSMsgSendCount` as a zero-initialized
32-bit global in `NSPortMessage.m`, the source file containing the target
method that increments it immediately before `msg_send`. `ownership.json` and
`symbols.json` record this reconstruction owner. The original source
translation unit within `DO.subproj_subproj.o` remains unknown; this mapping
places the reconstructed storage with its only confirmed source use. No build
or tests were run.

### ABI ownership closure (2026-10-08)

Added `__NSMsgSendCount` to the shared data-symbol ABI record for
`NSPortMessage.m`. The reconstructed source owner and 32-bit declaration are
now represented across source, ABI, symbol, and ownership metadata. The
original object-file translation unit remains unknown. Eight PPC data exports
remain without a reconstructed source owner.

## Current ownership reconciliation (2026-10-08)

The 2026-10-07 nine-export inventory is historical. `__NSMsgSendCount` is now
defined in `NSPortMessage.m` and registered in `symbols.json`,
`ownership.json`, and the shared `abi/NSPortMessage.json`. The other eight
exports remain without source ownership: `_YES`, `_dummyPad1`, `_NO`,
`_dummyPad2`, `_nil`, `_Nil`, `___NSObjectAllocatorLock`, and `_NULL`. A
current-tree lookup across the source symbol and ownership maps confirmed only
`__NSMsgSendCount` is assigned. The eight remaining names still lack direct
IDA references and source declarations, so their owners and storage widths
remain open.

## Darwin 0.3 source-image check (2026-10-08)

Inspected the community-hosted Darwin 0.3 source image listed by SourceForge
(`Darwin03_debs_source_31_5_2017.iso`, 118,163,456 bytes; SHA-256
`2584cc877f13702e8b1abd1b4d94516036766c1b42b1a779bf6797f8e74f6b98`). The
image contains source tarballs for `objc-1` and `objc4`, but no Foundation
source package. Extracted `objc-1.tar.gz` and searched for the eight remaining
exports; it contains no definitions. The only `_nil`-related hit is an
unrelated ChangeLog entry for `_nilName`. Also extracted `objc4-1.tar.gz` and
searched it; its matches are unrelated `NULL` tokens and `objc` identifiers,
not definitions of the exports. This external source snapshot does not resolve
Foundation translation-unit ownership or declaration widths, so the eight
exports remain unassigned. No source or ABI changes were made; no tests or
builds were run.

## Local aggregate-object availability recheck (2026-10-08)

Searched the current repository and `C:\Users\raynorpat\Downloads` for the
three aggregate object filenames identified by the PPC module table:
`ObjC.subproj_subproj.o`, `DO.subproj_subproj.o`, and
`Misc.subproj_subproj.o`. No matching files were present. This leaves no local
object-level artifact to narrow the eight remaining exports to a translation
unit or recover their declaration widths. No source or metadata changes were
made; no tests or builds were run.
