# Terminal architecture and analysis baseline

## Reference and tool result

The executable identity is recorded in `reference.md`. Binrecon validated the
PowerPC/big-endian profile pinned to that exact identity. IDA Professional 9.4
completed the configured pass; analyzer version was checked from its output.
The run is `complete: true` with one analyzer and reference-only consensus. Its
acceptance is `passed: false` for `normalized-functions` because no rebuilt
artifact exists yet. This is the expected reference-only state, not a parity
result. Generated analysis and consensus are under ignored
`tools/binrecon/out/terminal-ppc/published/`; hashes are recorded in the
profile run summary.

A fresh native `binrecon analyze` run completed on 2026-10-05 against the same pinned PPC executable. IDA 9.4 reproduced the prior analysis and consensus hashes; complete is true, while normalized-function acceptance remains false because no rebuilt executable is configured. The refreshed analysis semantically validates the complete 793-entry source map (640 mapped, 153 startup/runtime or imported entries). PPC `__sel_backref` review of `clearScrollback:` and `childExit:status:` confirms 640 functions at control-flow level and 153 signature-confirmed startup/runtime or imported entries, with none unexamined.

Native binrecon was rerun against the pinned executable on 2026-10-04. The run
completed with IDA 9.4 and published a fresh reference analysis and consensus;
acceptance remains false because no rebuilt executable is configured. The
source map has since been regenerated and semantically validated against that
analysis: 640 of 793 entries map to source, 153 are unmapped, and there are no
duplicate candidates or disputed boundaries. The unmapped entries are the six
startup/runtime routines and 147 external stubs. The PPC ledger currently records 640 control-flow-confirmed and 153 signature-confirmed entries, with zero unexamined entries (current verification: 2026-10-05). These are source-location and per-function review
states, not whole-program parity or runtime results.

The source-map entry for PPC `-[FieldView(FieldMouseScroll) _scrollTo:]` maps
to `FieldView.m:1931`: IDA's Objective-C metadata assigns the method to a
category, while the recovered source declares it in the main `FieldView`
implementation. Binrecon's categoryless fallback is used only in the absence
of an exact category definition and is tested to preserve ambiguous matches.
IDA pseudocode and source agree on the clamp,
visible-range test, flag transitions, and all three redraw branches.
The adjacent `-[FieldView scrollTo:]` at `FieldView.m:2061` was also rechecked
in IDA: it performs `disablePSOutput`, `_scrollTo:`, `enablePSOutput`, and
`reflectPosition` in the same order as source. This raises confidence in this
scrolling path but does not change either method's ledger status.
IDA also confirms that three `ChunkGrow` callers (`_lscrollup:to:lines:`,
`_lclear:to:`, and `_lscrollup:`) continue directly from the returned row
buffer into field access without a null check. The source now follows that
control flow rather than returning early on allocation failure.

| Measurement | Result |
| --- | ---: |
| Analyzer functions | 793 |
| Analyzer symbols | 3478 |
| Imports | 233 |
| Sections | 36 |
| Functions starting in `__text` | 646 |
| Functions in `__picsymbol_stub` | 147 |
| Objective-C IMP/type entries / IDA method symbols | 558 / 558 |
| Binrecon selector addresses resolved / matching IDA entries | 441 / 441 |
| Static selector pointers outside file-backed sections | 117 |
| `__text` bytes covered by nonoverlapping entries | 191280 of 191288 |
| `__text` trailing padding | 8 bytes |

The text range is `0x2440..0x310D8`. IDA reports every function with a symbol
name. Text function ranges are contiguous and nonoverlapping except for eight
trailing section bytes, which are recorded as padding rather than a missed body.
Imported stubs are retained in the inventory for dependency and call-boundary
review. Full per-function rows and provisional task assignment are in
`function-worklist.md`.

## Architecture and ownership

Both PPC and i386 remain required targets. The supplied executable is PPC only.
Separate repository toolchain profiles exist for `gcc-darwin-ppc.conf` and
`gcc-darwin-i386.conf`; a universal profile also exists. These profiles do not
prove that Terminal's Objective-C frameworks, Project Builder app rules, or guest
runtime work on either CPU. No matching i386 Terminal reference was found in the
supplied test tree. Use the PPC binary as behavioral reference and mark i386
results as native portability/runtime checks unless a matching reference is
located and release-matched.

The current coverage partition for all 793 analyzer entries is:

- Task 7: startup; confirm loader ownership: 6
- Task 7: application and window lifecycle: 128
- Task 7: app/window helpers: 2
- Task 8: defaults/preferences: 4
- Task 4: process and asynchronous I/O: 45
- Task 4: process/I/O helpers: 13
- Task 5: storage and terminal emulation: 55
- Task 9: search and printing: 16
- Task 9: search/string utilities: 9
- Task 6: drawing, selection, input, and DPS: 108
- Task 6: display word selection: 10
- Task 10: Services and distributed objects: 70
- Task 8: defaults, preferences, and documents: 142
- Task 6: display and event helpers: 14
- Task 7: application entry: 1
- Task 5: screen-line storage: 23
- import stub; inspect imported target: 147

This is a task-level routing partition; imported stubs remain external call
boundaries. IDA xref review found no code or data references to four mapped C
helpers: `_itoa` and `_FreeFlagMap` are public symbols; `_char_offset` and
`_compareStrings` are private symbols. Their standalone implementations remain
source-mapped and tested, but the Terminal reference has no in-image caller for
them. The 117 Objective-C method-list selector pointers outside file-backed
sections are retained through their IMP/type metadata; dynamic callsite
selectors still require local evidence, and some window/view selectors remain
inferred from call shape. `-[TerminalApp save:mustPrompt:howMany:inFile:]` and
`-[FieldView clearScrollback:]` are control-flow-confirmed from their full PPC
IDA bodies and source comparisons; selector names in both methods were
recovered through the Terminal PPC image's `__sel_backref` table. The six PPC
process-entry/dyld routines are separately classified as C runtime/loader
support after direct disassembly review. Independent i386 parity remains
unverified because a matching i386 Terminal image is unavailable. Repository
toolchain notes attribute `__sel_backref` creation to `objcunique`; decoding
here uses its observed selector-cell/string-offset rows rather than TOC
displacements or IDA's `SEL` annotations alone.

## Toolchain interpretation

The binrecon README documents IDA 9.2 as the known configuration. This host has
IDA Professional 9.4 at `C:/Program Files/IDA Professional 9.4/idat.exe`; the
configured run produced valid `analysis-v1` output and reported 9.4. Keep that
version recorded. If a 9.2 reproduction is required later, compare results before
claiming version-independent evidence. Ghidra/angr remain disabled on PPC because
the binrecon adapters document them as i386-only.

## Implemented source groups and current method coverage

The shared source tree now contains implementations for the application and
window lifecycle, preferences, process monitoring, Services, terminal
emulation, screen storage, selection and input, printing, and UI drawing paths.
PPC binrecon semantically maps 640 of the 793 analyzed functions to source;
153 entries are startup/runtime code or imported stubs. The current ledger
records 640 control-flow-confirmed and 153 signature-confirmed entries, with
none unexamined. `-[Terminal childExit:status:]` is control-flow-confirmed
through selector-cell review and source correction. `-[FieldView _refresh]`,
`-[TerminalApp save:mustPrompt:howMany:inFile:]`, and
`-[FieldView clearScrollback:]` are control-flow-confirmed against their PPC
IDA bodies and source. The save and clear-scrollback selector names are
resolved through the PPC image's `__sel_backref` table. Terminal records AppKit
current version 1.124.6 and timestamp
`0x383b3ba7` in `LC_LOAD_DYLIB`; the supplied AppKit is version 1.124.3 with
timestamp `0x36ceb55f`. The DR2 universal AppKit PPC slice is version 1.69.0
with timestamp `0x3550d100`. Those mismatched images are not used to infer these
Terminal callsite selectors; `__sel_backref` rows bind the reference cells to
their selector names directly. Native binrecon
profile and ledger validation pass for the pinned PPC input. No i386 Terminal
executable is present in the supplied test tree, so i386 remains a required
reconstruction target without a reference binary for function-level comparison.
These per-function states are not whole-program parity or runtime results.

Host-side C tests cover the reconstructed screen/storage, parsing, string,
process-helper, and write-queue behavior. The full Terminal `MFILES` manifest
has passed syntax checks for both `powerpc-apple-rhapsody` and
`i386-apple-rhapsody` with recovered DR2 headers. This does not link the
application or establish guest runtime behavior. The only supplied Terminal
binary is PPC, so i386 has no independent binary-parity result.

The `FieldView` flag block is three bytes in IDA's `_AFlags` type. It is now
represented at that exact size, with endian-independent accessors for the upper
24 flag bits so the following `width` ivar remains at offset 215. Independent
32-bit PPC and i386 layout checks place `cursorx` at 217, `lineZone` at 228,
and the complete class record at 232 bytes, matching IDA.

IDA's leaf accessors store `drawCursOK` at instance offset 224 and
`drawsLineAtRightEdge` at 227. `FieldView.h` now represents the reserved byte
after `bot` explicitly so these tail fields and `lineZone` retain their PPC
offsets; the i386 code-generation check confirms offsets 224–228 as well.

The source map is a source-location inventory, not a semantic parity score.
Use the PPC ledger for current per-function review status and the function
worklist for analysis routing. Earlier method notes below record staged
recoveries; where their interim coverage counts differ from the current source
map and ledger, the counts above are authoritative.

`-[Terminal removeDirtTimers]` follows IDA's exact ownership sequence for both
timer ivars: invalidate, release, and clear each non-nil timer. The matching
source-map entry is at `Terminal.m:64`; Objective-C syntax parsing succeeds with
the repository's DR2 framework headers.

`-[Terminal windowWillMiniaturize:]` sets the miniaturized state, disables
cursor drawing, cancels both dirt timers, and clears the deferred dirt flag, as
recovered from IDA at `0xE2EC`.

`-[Terminal windowDidDeminiaturize:]` now matches the IDA-named selector calls
at `0xE348`: re-enable PostScript output, re-enable cursor drawing, update dirt,
and refresh the screen, then mark the window content view for display. The final
three selector calls are resolved through PPC `__sel_backref` as `window`
(`0x37C94`, row `0x45360`), `contentView` (`0x37DDC`, row `0x42E40`), and
`setNeedsDisplay:` (`0x37F10`, row `0x44AA0`). The source receiver chain matches.

`-[Terminal outputdata:len:]` is represented at its PPC implementation address
`0xC580`. The PPC `__sel_backref` rows resolve its first send at cell `0x37E74`
to `lockFocus`, then `0x38098` to `_clearcursor`, and `0x37DA8` to the
emulator's `output:len:`. The cursor tail resolves to `_refresh`, `_cursor`,
`window`, and `flushWindow`. After the optional prune call, the source releases focus with `unlockFocus` at `0x37E90`.
The timer path resolves to
`scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:` with the
`handleDirtTimer:` callback and `self` user info, then retains the returned
timer. `FieldView selectAll:` uses the shared `lockFocus`/`unlockFocus` pair;
the earlier `becomeFirstResponder` and `display` source sends were incorrect.
The output method's status tail sends `isHidden` and, only when true,
`updateAppStatus` to `NSApp`, matching selector cells `0x380AC` and `0x380B0`.
Before scheduling `_delayedCursor:`, it cancels an existing matching run-loop
perform through cell `0x3807C`; cell `0x380A4` is the subsequent
`performSelector:withObject:afterDelay:` dispatch.
The output, prune threshold, newline scheduling, and spring-loaded-paste flow
are represented; guest runtime behavior remains unverified.

`Emulation` now has a target-layout base declaration and recovered defaults
behavior. IDA's UDT places `term` and `meta` at offsets 4 and 8, but its
`setDefaults:` and `autowrapIsOn` instructions access the flags word at offset
12; the implementation follows those direct accesses and reserves bytes 10–11.
The defaults prefix places `var9` at offset 12. PPC and i386 layout assertions
confirm the 16-byte object and 88-byte defaults record. The terminal accessors
at `0x58C8` and `0x58D8`, defaults methods at `0x58E8` and `0x5BF4`, empty base
translator at `0x5C4C`, autowrap getter at `0x5FBC`, and `metaCharacter` getter
at `0x5FD0` are now represented in source. `termDidResize:` at `0x5BD0` resets
the terminal bottom and cursor-draw rows via a FieldView helper. `wrapoutput`
at `0x5DA0` tests the autowrap flag, clears the cursor, scrolls at the last row
or advances `_cursory`, and resets `cursory` to zero.
`deAlternatize:` at `0x5B14` clears the alternate modifier flag, chooses
characters according to the control-modifier bit, then performs the two
recovered `setChars:` updates.

`-[FieldView _clearSelection]` clears the selection flag bits and redraws the
affected range with the recovered `_highlightsel:to:isLit:` call, then restores
the cursor when the view is invalidated. Binrecon maps it at `0x1E8C0`.

`-[FieldView _highlightsel:to:isLit:]` forwards the stored selection endpoints
and requested visible range to `_highlight::to::in::isLit:`. The simpler
`-[FieldView _highlight::to::isLit:]` wrapper supplies `topline` through
`topline + cursorx`, matching IDA at `0x1C044` and `0x1BFF8`; the lower-level
viewport-aware wrapper is implemented at `0x1BE44`.

`-[FieldView _highlight::to::in::isLit:]` now clips the selection to the
visible line interval, adjusts endpoint columns at row boundaries, and divides
the result into partial first/last rows and complete middle rows before
dispatching `_sshighlight::::isLit:`. Its selector and implementation address
`0x1BE44` are confirmed by binrecon.

`-[FieldView _sshighlight::::isLit:]` now walks the PPC eight-byte line slots
and their linked text fragments, emits unoccupied selection rectangles, routes
selected text runs through `_smark:len:attr:at::back:`, and requests a screen
refresh. `_smark` builds per-style text entries and the recovered background
and underline rectangle chunks. Its text entries retain the eight-byte PPC
layout with length, attributes, and a data pointer. Binrecon maps both
implementations at `0x1B9AC` and `0x1A3C0`. `refreshscreen` at `0x1A6C8` is
also implemented and its IDA body confirms background, underline, and text
chunk flush order, reverse text-entry traversal, and the conditional second
pass for style 2. Guest rendering remains runtime-unverified.

`-[FieldView _clearcursor]` now locates the current screen line and column,
checks the selection, retrieves the underlying character and attributes from
the line fragments, clears the cursor state bit, and restores the character
through `_smark` when the recovered scroll/display flags allow it. Its
`isSelected::` predicate preserves the binary's inclusive start and exclusive
end comparison. Its row arithmetic uses `cursorx` as the visible row count and
its column clamp uses `height` as the column count, matching the PPC byte loads
at offsets `0xD9` and `0xD8`. `_smark` allocates text rows at the recovered column
width (`height`). Binrecon maps the methods at `0x1CE5C` and `0x1C744`.

`-[FieldView _srscrollup:to:lines:]` and
`-[FieldView _srscrolldown:to:lines:]` clamp line intervals to the visible
scrollback viewport and dispatch the recovered three-argument scroll plus
two-argument exposed-row redraw selectors. `-[FieldView _refresh]` routes emulator update state through those helpers,
performs cursor-row scroll calculations and flag transitions, refreshes screen
state when requested, and reflects scrollbar position. PPC register flow at
`0x1AC34` confirms both scrollback redraw ranges and the normal-screen scroll-up
range. The second scrollback redraw ends at `lines->count`; source now uses that
full-buffer endpoint instead of `lineCount`. The PPC `__sel_backref` table also
confirms the common tail as `reflectPosition`, `window`, and `flushWindow`; the
source now follows that sequence. Focused source regressions and PPC/i386 syntax
checks cover these corrections. Guest runtime behavior remains unverified.

`-[FieldView _lscrolldown:to:lines:]` now frees the discarded bottom line nodes,
shifts the surviving eight-byte row slots down, clears the newly exposed slots,
and dispatches the scrollback redraw range. The implementation at `0x1B024`
matches the PPC row-base arithmetic and argument setup. It uses the host
`lineFree` equivalent for the recovered `freeLine` dependency; binary runtime
ownership parity still requires the guest build.

`-[FieldView _lscrollup:to:lines:]` at `0x1ADAC` now reconstructs both the
normal and scrollback-enabled branches. The normal branch frees the discarded
line fragments, shifts eight-byte row slots, and clears the exposed rows. The
scrollback branch grows the chunk, retains displaced rows, applies the
bottom-following `topline` adjustment, and performs the recovered partial
region move. It then dispatches the two screen-scroll redraw calls or the
scrollback redraw range and reflects the scroller position. `FieldView.m`
coordinates AppKit and line ownership; `terminalLineBufferScrollUpRows` in
`TerminalScreen.c` implements the packed eight-byte chunk operation. The host
test covers slot preservation and zeroing; Objective-C parsing and source-map
mapping pass, while PPC runtime parity remains unverified.

`-[FieldView _lclear:to:]` at `0x1B144` clears a row interval while preserving
the removed rows in scrollback. Its storage helper grows the eight-byte chunk,
shifts the visible rows, copies the cleared interval into the retained prefix,
and zeros the interval. `FieldView.m` then dispatches the recovered screen-scroll
and exposed-row redraw selectors and updates the scroller. Native storage tests
cover the retained rows and clearing; target runtime parity remains unverified.

`-[FieldView _lscrollup:]` at `0x1C300` now applies the binary's display-mode
transition rules, including the `top` threshold and selection clearing, then
moves the visible rows and retains displaced rows when scrollback is enabled.
It records `_cursory` in `scrolls`, matching the final PPC store. IDA control
flow and Objective-C syntax are verified; target runtime behavior remains open.

`-[FieldView _sclear:to:]` (`0x1A1D8`) clips a row interval against the visible
scrollback viewport and refreshes only when the intersection is nonempty.
`-[FieldView _srclear:to:]` (`0x1A9A4`) clips the same interval, clears the
visible display rows, walks each stored line-fragment list, redraws its spans,
and refreshes. Both implementations follow the PPC control flow and are
recorded in the binrecon ledger; guest rendering parity remains unverified.

`-[FieldView reflectPosition]` enables the scroller only when scrollback exceeds
the visible row count, then sets its normalized thumb position and proportion.
IDA confirms the calculation at `0x1D854`; the `NSScroller` and `NSControl`
headers confirm the three selectors used by the method.

The Terminal host regression suite runs under Windows Clang and passed on
2026-10-05. The 55-file `MFILES` manifest passed PPC and i386 target syntax
checks with the recovered DR2 headers; targeted source groups have also emitted
i386 Mach-O objects for IDA inspection. These checks do not link or run the
application. The supplied reference remains PPC-only, and the configured PPC
guest was unavailable during the latest SSH preflight, so guest build and
runtime verification remain open.

The current `PB.project` and `Makefile` now carry identical source and header
manifests (56 translation units and 55 headers). A manifest regression checks
set equality and file existence. This prevents Project Builder from omitting
the reconstructed `TerminalLaunch.c` helper.
