# PowerPC verification status

Current ledger state (2026-10-05): 640 of 793 entries are control-flow-confirmed and 153 are signature-confirmed, with none unexamined. `-[FieldView _refresh]`, `-[TerminalApp save:mustPrompt:howMany:inFile:]`, and `-[FieldView clearScrollback:]` are control-flow-confirmed from PPC IDA bodies and source comparison. `clearScrollback:` selector bindings now match the PPC `__sel_backref` table. The full source map has 640 mapped functions and 153 unmapped runtime/import entries; the fresh binrecon map validates against the pinned PPC analysis with no duplicate candidates or disputed boundaries. PPC `-[FieldView(FieldMouseScroll) _scrollTo:]` maps to `FieldView.m:1931` after adding tested categoryless fallback resolution for references with no exact category definition. Counts in the chronological notes below are snapshots from their respective updates.

A direct PPC IDA recheck of the six startup entries at `0x2440`–`0x2654`
confirms `start` extracts `argc`, `argv`, and `envp` and branches to `__start`;
`__start` initializes dyld/Objective-C and module initializers before entering
`_main`; and the remaining entries are dyld delayed-initializer, lazy-binding,
and function-lookup support. The worklist now records these as C runtime/loader
support rather than unresolved ownership candidates. They remain in the
793-entry ledger as signature-confirmed runtime code, not reconstructed
Terminal feature methods.

A fresh native binrecon run on 2026-10-05 completed with IDA 9.4 against the pinned 333,472-byte PPC reference. The normalized-function acceptance is false as expected for this reference-only profile; no rebuilt artifact is configured. The analysis hash and consensus hash match the prior published outputs, and the complete source map semantically validates against the refreshed analysis. At that run, the ledger had 638 control-flow-confirmed and 155 signature-confirmed entries, with no unexamined functions.

A fresh PPC IDA audit of `-[vt100 vt100DoCSI:]` found that the `L`, `M`, and `P` jump-table targets (`0x174D4`, `0x17544`, `0x175B4`) each iterate the full CSI argument array from index zero, passing its default zero value when no parameter is supplied. Source had consumed the first argument before entering the switch, so these commands dropped their first count. The handler now dispatches the initial argument and any remaining values. Both PPC/i386 syntax checks for `vt100.m` pass, and the complete Terminal host test suite passes.

PPC IDA comparison of VT52 input handling confirms `-[vt52 key:]` (`0x188B4`), `-[vt52 vt52Escape:]` (`0x18CA8`), `-[vt52 translateChars:len:]` (`0x18ED0`), and `-[vt52 ctrloutput:]` (`0x19034`) match their source branches. The escape jump table covers `0x3C`–`0x5A`; mode toggles, bounded cursor movement, home, reverse linefeed, clear operations, identify output, and two-byte `Y` cursor positioning agree, including parser-state clearing for every command except `Y`. The translator substitutions and graphics flag gate, key disposition/application-keypad paths, and control-byte scroll/tab/carriage-return behavior also match. No source change was indicated by this audit.

PPC disassembly of `-[FieldView _refresh]` (`0x1AC34`) showed that its second `_srscrolldown:to:lines:` send passes `(lineCount + drawCursOK - top, lineCount, top)`, not the source's previously inferred one-line interval. The implementation now preserves the actual `r5/r6/r7` values at that call; the first send's `(lineCount - top, lineCount + bot, top)` arguments already matched. The selector's three-argument ABI was verified against the PPC callee at `0x1AB64`. A subsequent instruction-by-instruction audit confirmed the refresh-state branches, scroll calls and trailing position/display sends; `_refresh` is now control-flow-confirmed.

PPC IDA comparison of `-[Emulation output:len:]` (`0x5E30`) confirms its control-byte loop, parser/emulator handoff, printable-run scan, available-row clipping, wrap retry, output dispatch, and remainder consumption match `Emulation.m`. The PPC body reads Terminal's `height` and active `emulator` ivars directly; source now reads `height` directly, while its `emulator` accessor returns the corresponding ivar. A direct `emulator` ivar access was rejected by both target compilers because that subclass ivar is protected.

PPC IDA comparison of `-[Emulation key:]` (`0x5924`) confirms the source's beep and autorepeat gates, function-key dispositions, alternate/meta conversion, signed-byte `setChar:` mutation, and CR-to-LF handling. The `setChar:` ABI narrows the flagged value to the same low-byte signed character in `MutableEvent`.

PPC computed-switch disassembly of `-[Emulation ctrloutput:]` (`0x5C58`) matches the source's bell, backspace with reverse-mode wrap, tab stop calculation and clamp, bottom-row LF scroll, ordinary LF, and CR behavior. The tab clamp branches at `height - 1` in assembly and `height` in C, but both store `height - 1` when that boundary is reached.

The relative jump table at `0x34554` was decoded for all 14 C0 entries.
Values 0–6 and 11–12 target the common epilogue at `0x5D8C`; values 7, 8, 9,
10, and 13 dispatch to BEL, BS, HT, LF, and CR handlers. `Emulation.m` already
matches this complete base dispatch with a no-op default; the focused
regression now pins the supported cases and default behavior.

The `vt52Escape:` relative table at `0x34C98` resolves `0x59` to the block that
stores selector `vt52getline:` from `0x384AC` and returns without clearing
escape state. `0x5A` reaches the block that sends the literal `\033/Z` at
`0x31EDC` to `output:` from selector cell `0x380C8`, then uses common escape
cleanup. Source already matches both; two focused regressions now pin the
cursor-address prefix and device-attributes response paths.

IDA's PPC selector strings at `0x3D6A8`, `0x3D6B8`, `0x3D6D0`, and `0x3D6F0`
resolve the Preferences initializer's bundle lookup, nib resource lookup,
owner-table construction, and `loadNibFile:externalNameTable:withZone:` call.
`Preferences.m` already matches the call order and arguments; the interface
notes now reflect those selector names, and a focused regression pins the nib
load path.

PPC IDA comparison of `-[Emulation wrapoutput]` (`0x5DA0`) found that the selector cell at `0x37DA0` resolves to `setWrap`, followed by the bottom-row `_lscrollup:1` call or `_cursory` increment, then `cursory` reset. Source had called a synthetic `_performAutowrap` helper which drew the cursor and omitted the wrapped-line marker. The source now follows the recovered call order and the unused helper has been removed.

PPC IDA comparison of `-[Emulation termDidResize:]` (`0x5BD0`) confirms direct stores of `bot = 0` and `drawCursOK = cursorx`. Source now performs those stores in the selector body and removes the synthetic resize helper.

`-[FieldView(FieldMouseScroll) validRequestorForSendType:returnType:]`
(`0x2097C`, 144 bytes) and `selectAll:` (`0x1FB14`, 208 bytes) are now
control-flow-confirmed. The requestor check requires the string pasteboard
type, an active selection mode, and distinct selection endpoints before
returning the view. Select All makes the view first responder, clears the old
selection, sets the full scrollback range and select-all flag, highlights
visible rows, then displays and flushes. Both implementations match the PPC
selector order and branches.

`-[FieldView(FieldMouseScroll) writeSelectionToPasteboard:types:]` (`0x20A0C`,
336 bytes) is now control-flow-confirmed. PPC IDA confirms the method enumerates
the offered types until it reaches `NSStringPboardType`, retries if `selStream`
is nil, then writes the text as `NSStringPboardType` and selection data as
`NSRTFPboardType`. Source now preserves those distinct types. PPC and i386
syntax-only checks pass. The ledger records 633 control-flow-confirmed, 7
signature-confirmed, and 153 unexamined entries.

`-[FieldView(FieldMouseScroll) copy:]` (`0x1F734`, 260 bytes) is now
control-flow-confirmed. PPC IDA matches the source's valid-requestor gate,
General pasteboard and filterable string-type acquisition, owner declaration,
and selection-write helper call. The ledger records 634 control-flow-confirmed,
6 signature-confirmed, and 153 unexamined entries. No i386 Terminal reference
binary is available for a second-architecture behavior comparison.

`-[FieldView clearScrollback:]` (`0x1F838`, 732 bytes) remains
signature-confirmed. PPC disassembly establishes the pre-compaction order:
`becomeFirstResponder`, `_clearSelection`, disable window flushing, scroll to
`lines->count - cursorx`, mark the window content view for redraw, and reenable
flushing. The first selector slot is shared with `selectAll:`'s source-confirmed
first-responder call. After row compaction and cursor adjustment, an unresolved receiver-only send
from selector cell `0x37E5C` precedes `reflectPosition`, and an unresolved
receiver-only send from `0x37E90` follows it. Both point to interior string suffixes
(`WithMnemonic:` and `erData:length:`) in the available AppKit 1.124.3 image,
which does not match Terminal's required AppKit; neither selector binding is
verified.
The wrapped-row boundary rule uses `terminalClearScrollbackRange` and is covered
by the native `scrollback` test. PPC and i386 syntax checks pass for this source;
the i386 check only establishes shared-source portability because no original
i386 Terminal binary is available for behavior parity.

On 2026-10-05, fresh PPC IDA comparisons of `-[FieldView _lscrollup:to:lines:]`
(`0x1ADAC`), `-[FieldView _lclear:to:]` (`0x1B144`), and
`-[FieldView _lscrollup:]` (`0x1C300`) confirmed that each stores the result of
`ChunkGrow` or its row-buffer helper and immediately uses it, with no null-result
early return. The source had three extra early returns after those helper calls;
they are removed so allocation-failure control flow matches the reference.
The rebuilt i386 Mach-O object decompiles with the same immediate use after
assignment. PPC and i386 target syntax checks and the 14 native C test targets
pass; these do not substitute for an i386 reference or guest runtime test.

PPC IDA reinspection of `-[FieldView _bclear:to:]` (`0x1B374`) and
`-[FieldView _bclear:from:]` (`0x1B664`) confirms the source row indexes,
wrapped-bit updates, scrolled-screen redraw gate, and `NSRectFill` geometry.
The latter uses `(height - column) * bwidth` for the fill width in both source
and reference; this unusual expression is preserved because IDA confirms it.

PPC IDA confirms `-[FieldView _binsert::bytes:]` (`0x1D160`) and
`-[FieldView _bdelete::bytes:]` (`0x1D1D8`) compute the visible-row index,
forward the column/count to `_insertChars` / `_deleteChars`, and store the
returned line pointer. Both 12-byte helpers preserve `r3` unchanged. This
matches `Chunk.c`, where the corresponding routines ignore column/count and
return the original line; the no-op is reference behavior, not missing source.

`-[Preferences init]` (`0x23558`, 616 bytes) is control-flow-confirmed. The
source and PPC pseudocode agree on superclass initialization, retrieval of
the eight controller delegates and eight pane delegates, `setCurrentTerminal:nil`,
clearing `installedPane`, reflecting pane zero, and returning the superclass
result. The selector rows in the PPC `__sel_backref` table resolve the bundle,
resource, `NSOwner`, zone, nib-load, and initializer calls; source call order
matches the reference.

`-[Preferences revert:]` (`0x23F2C`, 252 bytes) is now control-flow-confirmed.
The PPC body matches the source's missing-controller diagnostic, window flush
suppression, controller `revert:` call, flush restoration, and content-view
redraw. The ledger records 633 control-flow-confirmed, 7 signature-confirmed,
and 153 unexamined entries.

The `Preferences` PPC methods `setUpButtons:` (`0x23DE4`, 328 bytes),
`setDefaultX:` (`0x24028`, 212 bytes), `suggest:` (`0x24260`, 252 bytes), and
`showDefault:` (`0x24394`, 260 bytes) are control-flow-confirmed. IDA matches
the flag-mask and matrix attachment paths, nil-controller diagnostics,
controller dispatch, `NSApp updateWindows`, flush suppression/restoration, and
content redraw to the implementations at `Preferences.m:52`, `:91`, `:114`,
and `:125`. Current ledger counts are 633 control-flow-confirmed, 7
signature-confirmed, and 153 unexamined.

`-[FieldView(FieldMouseScroll) mouseDown:]` (`0x1EE9C`, 1304 bytes) is now
source-mapped and control-flow-confirmed. It converts the initial click,
dispatches single/double/triple or shift/option selection, then tracks
left-button events until mouse-up. Drag updates auto-scroll and redraw; when
the pointer leaves the text rows, a repeating 0.1-second `hackRoutine:` timer
is registered in default, modal, and event-tracking modes and invalidated
after each event poll. PPC and i386 syntax-only checks pass. The source map
covers 637 of 793 entries (156 unmapped), with no duplicate candidates or
disputed boundaries; the ledger records 633 control-flow-confirmed, 7 signature-confirmed, and 153 unexamined entries.

`-[FieldView hackRoutine:]` (`0x1EDB4`, 232 bytes) is now source-mapped and
control-flow-confirmed. It polls `NSApp` for mask `0x44` until the current
date in `NSDefaultRunLoopMode`, without dequeuing; when no event is pending,
it converts the static `_hackPoint`, autoscrolls, updates the drag selection,
and flushes the window. PPC and i386 syntax-only checks pass. The source map
covers 637 of 793 entries (156 unmapped), with no duplicate candidates or
disputed boundaries; the ledger records 633 control-flow-confirmed, 7 signature-confirmed, and 153 unexamined entries.

`-[FieldView _point:toPosition::]` (`0x1E940`, 1140 bytes) is now
source-mapped and control-flow-confirmed. It clamps x to the field's pixel
width and converts it to a column with a half-cell offset. Negative y maps
above-field coordinates into scrollback; visible coordinates use the cell
height; coordinates below the screen extend from the cursor row and clamp to
the final stored row and terminal-width column. PPC and i386 syntax-only
checks pass. The source map covers 637 of 793 entries (156 unmapped), with no
duplicate candidates or disputed boundaries; the ledger records 628
control-flow-confirmed, 11 signature-confirmed, and 153 unexamined entries.

`-[FieldView _drag::]` (`0x1E3AC`, 1040 bytes) is source-mapped and
control-flow-confirmed. PPC IDA confirms wrapped-line extension in whole-line
mode, previous/next-word endpoint adjustment in word-selection mode, and
character-column clamping in character-selection mode. Direction changes
re-anchor through `_dragEnd::`; PPC and i386 syntax-only checks pass. The
current source map covers 637 of 793 entries, with 156 unmapped, no duplicate
candidates or disputed boundaries; the ledger records 633 control-flow-
confirmed, 7 signature-confirmed, and 153 unexamined entries.

`-[FieldView _doubleClick::]` (`0x1E0DC`, 520 bytes) is now source-mapped and control-flow-confirmed. PPC IDA resolves forward opener and backward closer delimiter searches; successful matches seed the endpoint pair and call `_dragEnd::` with the recovered endpoint, while unmatched delimiters use the existing previous/next-word helpers. The method preserves the three-byte `ESC / Z` delimiter tail and selection-mode flag transitions. FieldView syntax checks pass for PPC and i386 with existing category warnings nonfatal.

`-[FieldView positionFrom:]` (`0x1D648`, 432 bytes) is now source-mapped and control-flow-confirmed. PPC IDA resolves sender `hitPart` dispatch to page/line movement or knob tracking; knob tracking locks focus, scales `floatValue` by `lines->count - cursorx`, calls `_scrollTo:`, and unlocks. Every path restores the saved `aflags` bit, records defaults changes, flushes the window, and waits for PostScript output. PPC and i386 syntax checks pass with the existing category incomplete-implementation warnings nonfatal.

`-[FieldView jumpToSelection:]` (`0x2088C`, 240 bytes) is now source-mapped and control-flow-confirmed. It disables window flushing, locks focus, scrolls the selection start into view when a selection flag is set or scrolls to the last valid line otherwise, then unlocks focus, reflects position, reenables flushing, and flushes the window.

`ChunkMalloc`, `ChunkRealloc`, `ChunkGrow`, `ChunkCompress`, `ChunkAdd`, and `_truncateLine` are control-flow-confirmed from PPC IDA. The chunk allocation paths preserve the 12-byte header, fixed-growth capacity, zone allocation, and append layout; source retains overflow/null guards. `ChunkAdd` uses `memmove` to retain the overlap behavior of the binary's `bcopy`. `_truncateLine` now follows its recursive tail removal and prefix-resize flow without an extra allocation-failure return. The native storage suite passes.

`ChunkCopy` (`0x21A40`) now matches PPC control flow: null checks, destination growth when capacity is below source count, a conditional `count * elementSize` copy from and to `+0x90`, and return without storing count. The PPC body is control-flow-confirmed and the source uses a bounded padded-buffer regression for the observed offset. `ChunkMalloc` still allocates payload immediately after its 12-byte header, and `_ChunkDup` passes those allocations directly to `ChunkCopy`; nonempty duplication therefore inherits the reference's out-of-bounds access. Both symbols are global text symbols, and `_ChunkDup` has no in-image callers, but external reachability cannot be excluded. The test intentionally avoids invoking nonempty `ChunkDup` because that would reproduce the reference overrun.

The PPC reference is identified by the SHA-256 in `../reference.md`. Binrecon's
IDA 9.4 reference pass is complete and published, with 793 function entries.
Its acceptance remains false because no rebuilt artifact exists. No guest build,
launch, behavior observation, rebuilt analysis, or function-parity comparison
has been performed yet.

`-[EmulationController lastVisible:]` (`0x24D74`) is an empty override. Its seven nib outlets and three revert-state bytes match the 40-byte IDA 32-bit instance layout.

`suggest:` (`0x2494C`) applies `(-1, 1, 0, 0, 0)` through
`setMeta:opts:::lock:`. At `0x24994`, the setter saves its metadata and option
values only when the final lock byte is nonzero, then calls `displayValues::::`
with the first four values. `revert:` (`0x24B18`) reapplies those saved values
without locking. The three bodies match the PPC instruction flow and the 40-byte
controller layout. The current PPC source map covers 618 of 793 IDA function entries; 175
remain unmapped, with no boundary disputes or duplicate candidates. The ledger
records 593 control-flow-confirmed, 26 signature-confirmed, and 174 unexamined
entries. PPC and i386 syntax checks pass; only PPC behavior is binary-confirmed.

`-[EmulationController setStruct:]` (`0x24C8C`, 172 bytes) copies the
translation, keypad, and strict checkbox states into the defaults record. When
`altMsg` is non-nil it writes the saved `revertMeta` byte; otherwise it obtains
the meta value from `altMatrix.selectedCell.tag`. The PPC branch and each output
offset match the source implementation. Both target syntax checks pass.

`-[EmulationController showDefault:]` (`0x24854`, 248 bytes) synchronizes the
shared user defaults, reads `Meta`, `Translate`, `Keypad`, and
`StrictEmulation`, then calls `setMeta:opts:::lock:` with the method argument as
the lock flag. PPC and i386 syntax checks pass.

`-[MiscController showDefault:]` (`0x24DCC`, 244 bytes) synchronizes defaults,
reads Scrollback, SaveLines, Autowrap, and AutoFocus, then calls
`setScrollback:lines:wrap:autoFocus:lock:` with a constant lock value of 1. Its
selector argument is passed to the defaults synchronization message by the PPC
call site; it does not control whether the loaded state becomes the revert
baseline. `MiscController.m` now records this constant lock behavior.

`-[EmulationController displayValues::::]` (`0x249F0`, 296 bytes) updates
keypad, strict, and translation states, clears the check matrix, then selects
meta tags `-1`, `0`, or `27`. An enabled custom field aborts editing and resigns
first responder before tag selection. Invalid custom meta values preserve an
existing field; without one, they update the `altBox` title. The box is redrawn
on the handled paths. PPC branches and message arguments match the source;
PPC and i386 syntax checks pass.

`-[EmulationController setDefault]` (`0x24B60`, 300 bytes) writes Translate,
Keypad, and StrictEmulation from the checkbox states. It persists Meta from
`revertMeta` when `altMsg` exists, otherwise from the selected `altMatrix` cell
tag, and returns `self`. Both target syntax checks pass.

`-[EmulationController setFromStruct:]` (`0x24804`, 80 bytes) forwards `var9`,
`var6`, `var2`, and `var5` from the defaults structure through
`setMeta:opts:::lock:` with lock set to 1. PPC and i386 syntax checks pass.


`-[EmulationController setMeta:opts:::lock:]` (`0x24994`, 92 bytes) stores
`meta` at instance offset `0x20` and the Translate, Keypad, and Strict bytes at
`0x24`?`0x26` only when `lock` is nonzero, then forwards all four values to
`displayValues::::`. `EmulationController.h` now asserts the 40-byte instance
size and recovered outlet/revert-state offsets; these assertions pass Clang
syntax checks for both PPC and i386. PPC assembly generation remains unavailable
in this LLVM installation.


`-[Preferences init]` (`0x23558`, 616 bytes) initializes its superclass,
loads Preferences.nib through the bundle-for-class path, builds the `NSOwner`
table and loads in the object's zone, reads the eight controller and eight pane
delegates in binary index order, sends `setCurrentTerminal:nil`, clears
`installedPane`, and selects pane 0. Direct PPC `__sel_backref` lookups resolve
the initializer, class, bundle, resource, dictionary, zone, nib-load, and final
pane selectors; `Preferences.m` matches the recovered calls.

`-[Preferences setUpButtons:]` (`0x23DE4`, 328 bytes) applies the recovered
flag bits to OK, Set Default, Show Default, Suggest, and Revert enablement, then
adds or removes the button matrix and redraws the affected view/window. PPC
`__sel_backref` rows confirm `setEnabled:`, `superview`, `contentView`,
`addSubview:`, `display`, and `removeFromSuperview`; source control flow and
selector order match. PPC and i386 syntax checks pass.

`-[Preferences revert:]`, `setDefaultX:`, `suggest:`, and `showDefault:` now
forward to the installed controller with the recovered nil-controller diagnostics.
Revert, Suggest, and Show Default suppress window flushing around the controller
action and mark the content view for redraw; Set Default updates app windows.
PPC control flow is reflected in source, and both target syntax checks pass.

`-[Preferences setCurrentTerminal:]` (`0x24700`) manages its
`NSNotificationCenter` registration for `NSWindowWillCloseNotification` on
the old and new terminal windows, updates `currentTerminal`, and sets OK
enablement based on whether a terminal is active. `terminalDidBecomeMain:`
(`0x23B48`) forwards the terminal defaults to the active pane controller,
restores the configured OK state, then updates the current terminal. PPC IDA
control flow and Objective-C metadata confirm these paths; PPC and i386 syntax
checks pass.

`-[Preferences terminalDidResignMain:]` (`0x23C44`) disables OK and clears the
current terminal. If Preferences is visible, it disables window flushing, logs
the missing-controller diagnostic when needed, and schedules `doFlush` after
0.1 seconds. The PPC literal is IEEE-754 0.1; PPC IDA control flow and both
target syntax checks confirm the implementation.


`-[Preferences reflectChoiceOfPane:]` (`0x2386C`, 732 bytes) updates the pane picker title from the tagged menu item, notifies, retains, and
removes the outgoing pane, then installs the selected pane and controller. It
centers the view using the recovered bounds deltas and 2.0 divisor,
then notifies the incoming controller. It loads the active terminal's defaults
or asks the controller to show saved defaults, then restores flushing and view
autoresizing. PPC and i386 syntax checks pass. IDA confirms branch and call
ordering; external AppKit and Foundation selector targets resolve in the supplied framework databases after applying the 0x1000 image slide.


`-[Preferences ok:]` (`0x240FC`, 356 bytes) logs when either the controller or
Terminal is missing, obtains Terminal defaults, applies them through
`setStruct:`, and persists them with `setDefaults:`. `windowShouldClose:`
(`0x244A8`, 104 bytes) clears the Preferences-visible flag, notifies the active
controller with `lastVisible:`, and returns YES. `notifyController:withArg:`
(`0x24688`, 120 bytes) forwards only when the controller responds to the
requested selector. PPC and i386 syntax checks pass; IDA confirms each branch
and call sequence.

`-[MiscController setFromStruct:]`, `showDefault:`, `suggest`, `setScrollback:lines:wrap:autoFocus:lock:`, `displayScrollback:lines:wrap:autoFocus:`, `revert`, `setDefault`, `setStruct:`, `checkSettings`, `firstVisible:`, `lastVisible:`, `handleReturn:`, `limitLines:`, and `unlimitLines:` are reconstructed in `MiscController.m`. The PPC bodies confirm defaults fields `var3` (Scrollback), `var1` (Autowrap), `var0` (AutoFocus), and `var17` (SaveLines), suggestion values `(1, -1, 1, 0)`, cell state/display handling, and the 1–499 warning path that sets 500. All 14 methods are control-flow-confirmed in the ledger and source-mapped. PPC/i386 syntax checks pass; behavior is confirmed against the PPC binary only.


`-[ShellController checkSettings]` (`0x26748`, 740 bytes) trims the entered shell command at whitespace, then checks existence, execute access, stat success, and regular-file type. Each failure shows its corresponding localized alert and reselects the form field; a valid regular file returns true. `showDefault:` uses the application shell plus the `SourceDotLogin` preference; `setShell:source:` updates the first form cell and checkbox; change actions persist `Shell` and `SourceDotLogin`. These bodies now map to `ShellController.m` and pass PPC/i386 syntax checks.

The PPC bodies for `ShellController` and `ProcessMonitorController` `revert`, `setDefault`, `suggest`, and `setStruct:` all raise `NSInvalidArgumentException` with the exact format `*** Method not implemented: %s` and the active selector name. Both source controllers preserve that behavior. Their remaining methods, including intentional empty `setFromStruct:` overrides, are represented in source and mapped.

The `-[ShellController showDefault:]` selector bindings were checked directly
against its PPC method-entry TOC and `__sel_backref`: the sends are
`[defaults synchronize]`, `[NSApp shell]`,
`[defaults boolForKey:@"SourceDotLogin"]`, and
`[self setShell:source:]`. The incoming `show` byte remains unused, as in the
shared source; stale values in the extra argument register do not change the
zero-argument `synchronize` call. No source behavior change was needed. The PPC
and i386 syntax-only checks for `ShellController.m` pass.

The PPC method-entry TOC and `__sel_backref` were also resolved for
`ServiceManager`'s selection, add, and save paths. `serviceSelected:` matches
the cache/set lookup, empty-set assertion, selection-state repair, selected-row
record load, dirty reset, controls refresh, and matrix redraw. `add:` matches
the preference sequence increment, unique `New Service #%d` name search,
cache insertion, row selection/editing, and window redraw order. `save:` and
`saveService:` match the accessory-panel setup, service-name row copies,
selection preservation, file open/error path, count check, all-cell callback,
row lookup, and `writeService:toFile:` arguments. No source behavior changes
were needed; the shared source still parses for both target architectures.

The `-[ServiceManager windowShouldClose:]` sends also resolve through its PPC
method-entry TOC and `__sel_backref`: clean windows close directly; dirty
windows are brought forward and validated before the appropriate localized
prompt. The unaccepted-settings prompt preserves Cancel versus Discard, while
the valid-settings prompt preserves Save, Discard, and Cancel, including the
`change:` call only for Save and the original beep on unexpected responses.
`ServiceManager.m` passes PPC and i386 syntax-only checks.

`StartupController` is a 32-byte PPC/i386 32-bit object: its outlets occupy offsets 4, 8, and 12; revert action, zone-owned filename, and fast-launch state occupy offsets 16, 20, and 24. All 17 methods are mapped and control-flow-confirmed from the PPC bodies. The pane clamps `StartupAction` to 0–2, updates `StartupFile` and `FastLaunch`, preserves the revert snapshot, and validates readable startup paths with the original dialogs. `setFromStruct:` and `setStruct:` are empty; `setDefault` returns `self`; the save-panel callback forces the three defaults. PPC and i386 syntax checks pass. The source map now has 615 mapped and 178 unmapped function entries, with no duplicate candidates or boundary disputes; the ledger has 589 control-flow-confirmed, 26 signature-confirmed, and 178 unexamined entries. Native builds and guest behavior remain unverified.


`TextAttributeController.m` reconstructs all nine methods from PPC IDA bodies. The eight color wells use the recovered table order; `setStruct:` updates `var20` cursor style/blink/double-strike bits and `showDefault:`/`setDefault` use integer `TextAttributes` plus `TextColors`. `TerminalDefaults.m` maps the `var16` custom-title string to `CustomTitle` and the `var20` packed text flags to `TextAttributes`. All nine methods are source-mapped and control-flow-confirmed. PPC and i386 syntax-only checks pass; guest behavior remains unverified. The source map now covers 615 of 793 functions (178 unmapped), with no duplicate candidates or boundary disputes; the ledger records 589 control-flow-confirmed, 26 signature-confirmed, and 178 unexamined entries.


`TitleBarController.m` covers all 16 recovered methods. It handles `TitleBits` and `CustomTitle`, validates the enabled custom-title field, and transfers the title-option byte and custom string through `var15`/`var16`. All 16 methods are control-flow-confirmed. `displayBits:custom:` (`0x28004`, 760 bytes) matches the PPC body: it updates five option cells, localizes custom-title and filename strings, builds the preview title, sizes it using the preview font width plus 10 points and centers/clips it to the saved frame, then updates the preview and custom-title form cell. `titleBitsChanged:` (`0x286F4`, 212 bytes) matches IDA's selector sequence resolved through `__sel_backref`: get the matrix window, disable flushing, read title bits and the form string, call `displayBits:custom:`, reenable flushing, and mark the content view for display. PPC and i386 syntax checks pass. The current source map covers 633 of 793 functions (160 unmapped), with no duplicates or boundary disputes.

`-[WindowController setFromStruct:]` (`0x288A8`) is source-mapped and control-flow-confirmed: it forwards the stored rows, columns, shell-exit action, font name, and font size to `displayRows:cols:exitAction:font:size:`. PPC and i386 syntax checks pass. All 16 recovered WindowController methods are now source-mapped and control-flow-confirmed.

`-[WindowController setRows:cols:exitAction:font:size:lock:]` (`0x28C48`) now matches the PPC snapshot and allocation-failure path; `displayRows:cols:exitAction:font:size:` (`0x28DB0`) redraws the size form, selects the clamped shell-exit action by tag, redraws its matrix, and forwards the font preview; `setDefault` (`0x291BC`) validates then persists shell-exit title, rows, columns, font name, and integer point size. All three methods are control-flow-confirmed and source-mapped. PPC and i386 syntax checks pass.

`-[WindowController receiveFontFromTrap:]` (`0x29C60`) converts the received font to its screen font and forwards name and point size to `displayFont:inSize:`. `fontTrapDidResignFirstResponder` (`0x29D7C`) reads the shared font manager's selected font, then updates and selects the field text. PPC flow matches both source bodies; both target syntax checks pass.

`-[WindowController showDefault:]` (`0x28914`) is source-mapped and control-flow-confirmed. It synchronizes and reads the measured defaults, converts the font-size object to a float, and forwards the show/lock byte to `setRows:cols:exitAction:font:size:lock:`.

`-[WindowController suggest]` (`0x28A6C`) is source-mapped and control-flow-confirmed: the global font lookup, font usability check, localized fallback, 80x24 size, zero exit action and unlocked state match the PPC body.

`-[WindowController displayFont:inSize:]` (`0x28EB4`) is now reconstructed from the PPC body. It converts the incoming C font name, validates the requested font, uses localized `Ohlfs`/`10.0` fallback values when unavailable, and updates the font field and formatted label. PPC and i386 syntax-only checks pass.

`-[WindowController setStruct:]` (`0x29354`) now writes rows, columns, exit-action selection, font size, and a zone-owned font name after settings validation. The recovered allocation failure path raises the WindowController allocation alert. PPC and i386 syntax-only checks pass.

`-[WindowController checkSettings]` (`0x29514`) enforces the recovered 5�5 minimum, visible-screen bounds using the font cell width and line metrics, and the 255 row/column limits. Corrections display the localized reference alerts and return false so the pane can be reviewed before saving. PPC/i386 syntax-only checks pass.

`-[WindowController setFontRequest:]` (`0x29B50`) now configures the font field and first responder before presenting the shared font panel, matching the PPC message sequence. PPC and i386 syntax-only checks pass. All 16 recovered WindowController methods are source-mapped and control-flow-confirmed.

`-[TerminalApp preferences:]` (`0x11634`) is source-mapped to `TerminalApp.m`: the app marks the preferences window visible, chooses the sender-selected pane when its tag is 0�7, binds the main-window Terminal first responder or loads defaults, then shows the preferences window. PPC and i386 syntax-only checks pass.

`-[TerminalApp applicationWillFinishLaunching:]` (`0x10A60`) now initializes the defaults registry with all 28 key/value pairs recovered from the PPC constant table and sets the process name, DPS context, and launch flags. PPC/i386 syntax-only checks pass.

`-[TerminalApp msgPaste:]` (`0x10724`) is reconstructed: it creates a Terminal, sets `var18` to 2, reapplies defaults, stores the app pointer as the service owner, and returns 0 (or -1 on creation failure). PPC and i386 syntax-only checks pass.


`-[TerminalApp makePanelGoToLibrary:]` (`0x133F4`) is reconstructed and control-flow-confirmed from PPC IDA. The verified selector references are `isEqualToString:`, `setDirectory:`, `stringByAppendingPathComponent:`, and `fileSystemRepresentation`; PPC PIC-relative constants resolve to `/` and `Library/Terminal`. It creates the terminal library directory with mode `0777` if needed, rejects a non-directory collision, and selects the home directory if creation fails. PPC and i386 syntax checks pass. The map contains 615 mapped, 178 unmapped, no duplicate candidates, and no disputed boundaries; the ledger records 589 control-flow-confirmed, 26 signature-confirmed, and 178 unexamined functions.

`-[TerminalApp updateAppStatus]` (`0x14DBC`) is control-flow-confirmed at `TerminalApp.m:393`. It selects a 16×16 representation from the bundle icon or creates a scaled application-icon fallback, builds the empty toggle image and configures/schedules the status item to call `displayAppStatus:` after 0.5 seconds. The source map still has 615 mapped and 178 unmapped functions; the ledger now has 590 control-flow-confirmed, 26 signature-confirmed, and 177 unexamined entries. i386 remains shared-source portability only because no matching executable is available.

`-[TerminalApp open:]` (`0x134F0`) is implemented at `TerminalApp.m:795`. IDA confirms the cached panel global, the `term` and `svcs` constant objects, the modal-result and filename guards, and the two dispatch branches. It is source-mapped and control-flow-confirmed. The map now has 616 mapped and 177 unmapped functions; the ledger has 591 control-flow-confirmed, 26 signature-confirmed, and 176 unexamined functions. PPC and i386 syntax checks pass; there is no i386 reference binary for parity analysis.

`-[TerminalApp openFile:]` (`0x1360C`, 1480 bytes) is reconstructed from the PPC body and typed-stream, TerminalAgent, Terminal, NSScreen, and NSWindow interfaces. It validates read access, maps the archive, restores each Terminal session record in a named zone, reapplies normalized window positions and visibility, associates the filename with restored terminals, and activates the last visible window. The two localized error paths and archive-exception alert are preserved. The method is source-mapped and control-flow-confirmed; PPC and i386 syntax checks pass. No matching i386 executable is available for parity analysis.

`-[TerminalApp application:openFile:]` (`0x13C24`, 488 bytes) is reconstructed from PPC control flow and its exact `.term`, `.svcs`, and ignored temporary-path literals. It routes terminal and service archives, opens directories as shell working folders, and launches executable files as shells. The body is source-mapped and control-flow-confirmed; PPC and i386 syntax checks pass. The i386 result is source portability only because a matching i386 reference binary is unavailable.

`-[TerminalApp openServicesFile:]` (`0x13E0C`, 1636 bytes) is source-mapped and control-flow-confirmed from the PPC body. It preserves permission and confirmation behavior, cache initialization, service parsing, duplicate replace/skip/cancel decisions, accepted-record import and cleanup, localized summary/error alerts, and the service-manager refresh. PPC and i386 syntax-only checks pass; the i386 check establishes shared-source portability only because a matching reference executable is unavailable. The source map now covers 619 of 793 functions (174 unmapped), and the ledger has 594 control-flow-confirmed, 26 signature-confirmed, and 173 unexamined entries.

`-[ServiceManager init]` (`0x2C248`, 428 bytes) is source-mapped and control-flow-confirmed. The PPC body verifies `NSBundle bundleForClass:` resource lookup for `Services.nib`, the `NSOwner` external-name table, zone-based nib loading, matrix/scroller setup, resize notification registration, saved initial frame, and state flags. PPC and i386 syntax-only checks pass; i386 behavior remains unverified because no matching reference binary is available.

`-[ServiceManager go:]` (`0x2C3F4`, 852 bytes) is source-mapped at `ServiceManager.m:94` and control-flow-confirmed. It uses the cache dirty/forced/first-load predicate, preserves a selected service by title or clamps the previous row, resets controls for an empty service set, then refreshes matrix display, dirtiness, and the window delegate. PPC and i386 syntax-only checks pass; no matching i386 reference executable is available.

`-[ServiceManager remove:]` (`0x2E454`, 340 bytes) is source-mapped at `ServiceManager.m:462` and control-flow-confirmed. It clears the old cell state, enables cache writes, clears dirty state when necessary, removes the selected service row, reloads the service matrix, and restores window flushing/display. PPC and i386 syntax-only checks pass; no i386 reference executable is available. The source map covers 622 of 793 functions (171 unmapped), and the ledger records 597 control-flow-confirmed, 26 signature-confirmed, and 170 unexamined entries.

PPC selector references are resolved through `__sel_backref` using offsets relative to the `__OBJC` segment base (`0x36000`); `__cat_inst_meth` (`0x360C4`) is only a section inside that segment. This corrected the earlier interpretation and confirms the current `go:` selector sequence. The earlier `remove:` mismatch claim remains withdrawn. `-[ServiceManager editSelectedServiceName:]` (`0x2C9F4`, 312 bytes) is reconstructed and control-flow-confirmed: the matrix selection and row/column calls feed `cellFrameAtRow:column:`, the frame is inset by +1.0 x and -2.0 y, the window supplies a field editor, the nil-editor path beeps, and the selected cell is made editable before `editWithFrame:inView:editor:delegate:event:` receives the matrix, editor, current event and adjusted frame. IDA register/stack arguments agree with the recovered `NSMatrix`, `NSWindow`, `NSCell` and `NSApplication` declarations. Binrecon maps it to `ServiceManager.m:456`.

`-[ServiceManager windowShouldClose:]` (`0x2E168`, 748 bytes) is source-mapped at `ServiceManager.m:383` and control-flow-confirmed. It permits clean closes, raises the window before prompting for dirty edits, blocks closing on Cancel, routes the valid-settings Save choice through `change:`, permits Discard, and preserves the invalid-settings discard/cancel prompt and beep fallback. Its selector references were checked against the segment-relative `__sel_backref` table. PPC/i386 compilation and i386 behavioral parity remain unverified.

`-[ServiceManager add:]` (`0x2D560`, 888 bytes) is source-mapped at `ServiceManager.m:311` and control-flow-confirmed. It ends editing and checks settings before mutation, enables cache saving, increments `ServiceSequenceNumber`, fills and validates a temporary service record, gives it the first unique localized `New Service #%d` title, inserts a copied record into the cache, frees the temporary fields, renews and selects the new editable matrix row, and restores clean-state controls and window flushing. The title key's PPC fallback object is the empty string; the persisted sequence number and title suffix use separate counters. Selector references and string objects were checked against `__sel_backref` and the PPC `__cstring_object` table. PPC/i386 compilation and i386 behavioral parity remain unverified.

`-[ServiceManager change:]` (`0x2DDC4`, 512 bytes) is source-mapped at `ServiceManager.m:279` and control-flow-confirmed. After ending editing and passing `checkSettings`, it fills and validates a temporary record, copies the selected matrix-cell title into its own zone, writes the updated record to the selected cache slot, enables cache saves, clears dirty state, renews and displays the matrix, flushes the window, and releases the temporary record. PPC/i386 compilation and i386 behavioral parity remain unverified.

`-[ServiceManager save:]` (`0x2EA20`, 888 bytes) is source-mapped at `ServiceManager.m:439` and control-flow-confirmed. It configures the `.svcs` save panel and accessory matrix, copies service titles and selection, opens the accepted path with write/create/truncate flags and mode `0666`, reports the localized write error on open failure, verifies the live cache row count, dispatches `saveService:` for the selected accessory cells, then closes the file. The binary’s C stream mode string is `"w"`. The source map covers 627 of 793 functions (166 unmapped), with no duplicate candidates or boundary disputes; the ledger records 602 control-flow-confirmed, 26 signature-confirmed, and 165 unexamined entries. PPC/i386 compilation and i386 behavioral parity remain unverified.

-[TerminalApp validateMenuItem:] (0x12278, 716 bytes) is source-mapped at TerminalApp.m:274 and control-flow-confirmed. It gates the print, shell, scroller, key-yield/steal, and Save/Save Set menu items by tags 23–33, updates localized titles and tags when needed, and preserves the binary's disabled result when the Save title already matches. PPC source-map and profile validation pass; focused source-map and ledger tests pass (49). Compilation and i386 behavioral parity remain unverified.


-[TerminalApp applicationShouldTerminate:] (`0x1199C`, 1,864 bytes) was initially signature-confirmed while its PPC selectors were unresolved. See the later verification entry below for the resolved method-entry TOC base, implementation, and current source-map/ledger status.



The early termination selector trace incorrectly treated PPC r31 as the method entry plus four. A later calibration against `-[TerminalApp preferences:]` establishes r31 at the exact method entry for these compiler-generated table references.

`-[TerminalApp save:mustPrompt:howMany:inFile:]` (`0x12B34`, 2,240 bytes) is now signature-confirmed by IDA as returning `char` with arguments `(id, char, int, const char *)`. IDA pseudocode recovers save-panel configuration, typed-stream serialization, optional window/session aggregation, post-save state updates, and localized failure alerts. A source implementation is now present. PPC and i386 `TerminalApp.m` syntax checks pass with incomplete-implementation warnings treated as errors. Exact per-call selector/branch parity and runtime archive round-trip remain pending; i386 evidence is shared-source portability only because no matching i386 Terminal reference was found.
`-[TerminalApp save:mustPrompt:howMany:inFile:]` (`0x12B34`, 2,240 bytes) now has a source-map candidate at `TerminalApp.m:277`, independently emitted by binrecon's IDA/Objective-C analysis against the PPC reference. The source body implements the save-panel path, tagged save-scope selection, typed-stream archive writer, compatible shared-window scan, output write, document-edited clearing, and startup auto-open state. PPC and i386 syntax checks pass with incomplete-implementation warnings treated as errors. The full method remains signature-confirmed, not control-flow-confirmed, pending selector-by-selector parity review and runtime archive round-trip.

The save method's path flow was compared again with PPC IDA. A nonnull `inFile` argument jumps directly to the common archive path. When the save panel succeeds, the method obtains the filename's filesystem representation and falls through to window enumeration and archive setup; there is no null-or-empty path guard on that path. Removed the source-only `path == NULL || *path == '\0'` early return so invalid or empty paths follow the reference's downstream behavior. `TerminalApp.m` passes syntax checks for both PPC and i386 triples; the method remains signature-confirmed pending selector-by-selector parity and archive round-trip evidence.


`-[TerminalApp quickTitle:]` (`0x147EC`, 572 bytes) now has a shared-source implementation for modal custom-title editing. IDA confirms it returns when there is no key window, beeps when the key-window delegate is not a Terminal, seeds the form from the Terminal defaults string, and presents the panel modally. On acceptance, the current event modifier selects whether it replaces the title flags with bit `0x08` or preserves existing flags while setting that bit; it then updates the Terminal defaults and notifies Preferences with `terminalDidBecomeMain:`. PPC IDA instruction and Objective-C metadata confirm the selector and branch behavior, including the `terminalDidBecomeMain:` Preferences callback; the ledger now records control-flow confirmation. PPC/i386 syntax checks pass; i386 is shared-source portability only.

`-[WindowController revert]` (`0x2916C`, 80 bytes) is control-flow-confirmed. PPC disassembly resolves the call through the message-reference table to `displayRows:cols:exitAction:font:size:` and forwards the five cached values directly. The source was corrected to remove the extra `setRows:...lock:NO` call.


`-[TerminalApp applicationShouldTerminate:]` (`0x1199C`, 1,864 bytes) is implemented at `TerminalApp.m:1021` and control-flow-confirmed. The resolved sends save the main window's x/top-y defaults; classify Terminal and Preferences windows; refresh process-monitor edited flags; show the generic quit confirmation when `MonitorProcs` is disabled; otherwise present the active-window Quit Anyway/Review Windows/Cancel panel when edited terminals exist; and close windows through `performClose:` while honoring visibility-based vetoes. The Review Windows branch removes and closes each edited terminal individually before continuing. The first send resolves to `-[NSApplication _mainWindow]`; its structure-return send uses `frame`, followed by `setInteger:forKey:` for `WinLocX` and `WinLocY`.

The method-entry TOC base was calibrated against the known `[self prefManager]` send in `-[TerminalApp preferences:]`. `__sel_backref` then resolves the termination method's selector cells, including `_mainWindow`, `frame`, `setInteger:forKey:`, `windows`, `count`, `arrayWithCapacity:`, `objectAtIndex:`, `delegate`, `isKindOfClass:`, `boolForKey:`, `isDead`, `dirtMonitor`, `shellDevice`, `isDeviceDirty:`, `setDocumentEdited:`, `isDocumentEdited`, `addObject:`, `removeObjectAtIndex:`, `isVisible`, and `performClose:`. The source map covers 639 of 793 functions (154 unmapped), with no duplicate candidates or boundary disputes; the PPC ledger records 635 control-flow-confirmed, 5 signature-confirmed, and 153 unexamined entries. PPC profile validation and focused source-map/ledger tests pass. A matching i386 Terminal binary is unavailable, and both target syntax checks remain blocked before this translation by existing `@defs`/class-layout assertions in `TerminalServices.h` and `ServiceManager.h`.

A follow-up branch-level comparison found that the PPC loop overwrites its
Preferences-window candidate for each matching delegate, so the final close
targets the last matching window. The source previously kept only the first
candidate with a `preferencesWindow == nil` guard; that guard is removed to
match the reference. Binrecon's ledger now records the current source line and
last-match behavior. This edge case matters only when multiple Preferences
windows are present, but the source now follows the binary in that case too.

The corrected shared source was compiled as an i386 Mach-O object and opened in
IDA (`terminalapp-quit-pref-last-i386.o`, SHA-256
`5100E2ED6B3E39D2E4289DA01243670D66BD61D8B1BD3D373B8D7C4769A05B67`).
`-[TerminalApp applicationShouldTerminate:]` at object address `0x3F90`
unconditionally assigns each matching Preferences window to the candidate,
matching the PPC reference's last-match behavior. This verifies current-source
i386 code generation, not parity with an unavailable i386 Terminal binary.

A fresh binrecon source-map pass against the pinned PPC analysis preserves all
640 mappings, all 153 startup/import boundaries, and zero duplicate or disputed
boundaries. It found stale source-line locations; the checked-in map was
refreshed, and 366 ledger source locations were reconciled through binrecon's
lock-protected ledger updater. All 640 mapped ledger entries now match the
source-map path and line exactly; evidence reasons and confirmation states were
preserved.

Selector-table work on `-[TerminalApp applicationDidFinishLaunching:]` (`0x10E60`)
confirms its local TOC base: the `updateLibraryMenu` send resolves through
`__message_refs:0x38254` to the Terminal selector at `0x3E734`. Several
Foundation references also resolve exactly after accounting for the `0x1000`
address offset between the Terminal reference and the Foundation IDA database,
including `stringForKey:`, `copyWithZone:`, `retain`, `boolForKey:`,
`allocWithZone:`, `cString`, `setDelegate:`, `localizedStringForKey:value:table:`,
`array`, `stringByAppendingPathComponent:`, and `setTarget:`. AppKit and System
references were also inspected. IDA's conditional paths for the optional
Library menu, distributed-object setup, and NXOpen/Dock auto-launch handling
match the source; the binrecon entry is now control-flow-confirmed at
`TerminalApp.m:901`. Guest runtime behavior and independent i386 binary parity
remain unverified.
The termination selector mismatch noted in earlier entries is resolved as
described above; those observations are retained as investigation history, not
current status. The PPC source map records 640 mapped functions and 153
unmapped functions, with no duplicate candidates or boundary disputes.


The entry branch of `-[TerminalApp save:mustPrompt:howMany:inFile:]` now matches the PPC pseudocode: only a Terminal key-window delegate is used, and prompt-free calls with no valid Terminal beep and return before opening the save panel or honoring a supplied path. The method remains signature-confirmed pending complete archive/write branch comparison.

`-[Preferences init]` (`0x23558`, 616 bytes) matches the PPC initialization sequence. Selector references and framework selector strings confirm `[self class]`, `[NSBundle bundleForClass:]`, `pathForResource:ofType:` for `Preferences.nib`, the `NSOwner` external-name table, `[self zone]`, and `+[NSBundle loadNibFile:externalNameTable:withZone:]`; outlet delegate reads, `setCurrentTerminal:nil`, `installedPane = nil`, pane-0 reflection, and superclass-result return also match. The entry is control-flow-confirmed in the ledger. PPC and i386 Rhapsody-target syntax checks pass for `Preferences.m`; full app linking and guest behavior remain unverified.

The save-method comparison also corrected the shared archive path: the reference uses a stack window-number list, updates the saved Terminal file-name/share state before writing the archive, and returns success after showing the localized write-error panel. It no longer treats an empty window set as a synthetic write failure or clears per-window edited flags before the existing dirty-state recalculation. Full method parity is still pending.

Selector and branch comparison further confirmed that the save panel is cached and receives `makePanelGoToLibrary:` only when first created; successful saves notify `maybeUpdateLibraryMenu`. The source now follows those local-selector references. External framework selector parity and a guest archive round-trip remain unverified.

`-[FieldView(FieldMouseScroll) _scrollTo:]` (`0x1D250`, 532 bytes) maps to `FieldView.m:1931` and is control-flow-confirmed. The PPC body clamps the requested top line to `lines->count - cursorx`, leaves an unchanged top line alone, then chooses the optimized upward/downward redraw when the visible ranges overlap or clears the visible range otherwise. Each path updates the recovered scroll-state flag bits from the end-of-buffer conditions before dispatching `_srhscrollup:to:lines:`, `_srhscrolldown:to:lines:`, or `_srhclear:to:`. The binary metadata places this method in `FieldMouseScroll`; the shared implementation is in the primary FieldView class body. Binrecon now resolves this category-qualified reference through a tested categoryless fallback because no exact category definition exists. i386 behavior parity remains unverified because no i386 Terminal executable is available.

`-[TerminalApp recalculateDirtyWindows]` (`0x120E4`, 376 bytes) is control-flow-confirmed against the PPC IDA body. It enumerates application windows, checks for a Terminal delegate, clears the edited flag when process monitoring is disabled or the Terminal is dead, and otherwise sets the flag from the dirt monitor's `isDeviceDirty:` result for that Terminal's shell device. The ledger's source line is 1629, matching the method body in `TerminalApp.m`. i386 behavior parity is unverified because no i386 Terminal reference executable is available.
`-[FieldView _rawscrollup:to:lines:]` (`0x196AC`) and `-[FieldView _rawscrolldown:to:lines:]` (`0x19AD8`) were checked against PPC IDA. Both source bodies preserve the `aflags & 0x8000` / two-line early return, DPS splat geometry, integer division of the pixel movement into six strips with remainder accumulation, background fill rectangles, and a `[self window]` then `[window flushWindow]` sequence for each strip; the optional PostScript wait follows the same edge-drawing condition. Runtime selector references point into AppKit selector data, and the nested receiver sequence corroborates the selectors in source. Ledger entries now record the implementation locations at `FieldView.m:1695` and `FieldView.m:1771`. No independent i386 Terminal executable is available, so cross-architecture parity for these methods remains unverified.

The earlier interfaces notes incorrectly described these raw scroll methods and `refreshscreen` as unimplemented. They are present in `FieldView.m` and mapped in the PPC source map. IDA confirms `refreshscreen` (`0x1A6C8`) flushes three background chunks, then underline rectangles and reverse-ordered text runs across four styles, with a second `FVshow` pass for style 2 when flag `0x00080000` is set. Function worklist and ledger reasons now reflect this evidence. Guest AppKit rendering is still unverified.

IDA reinspection of `_reallocNode` (`0x21CE0`) confirms it stores the result of `NSZoneRealloc` into the length field and writes the terminator without checking for a null result; `Chunk.c` now follows that failure path. `_overNode` (`0x21D34`) matches the gap stop, full-span removal, same-attribute merge, and different-attribute suffix trim. Direct storage regressions cover gap, full coverage, and equal-attribute concatenation, while insertion tests cover the differing-attribute trim. Host storage tests pass; zone ownership and i386 runtime behavior remain unverified.

`_ChunkCopy` (`0x21A40`, 140 bytes) now has a source implementation matching the PPC call flow and offset. The disassembly encodes `addi r3,r30,0x90` and `addi r4,r29,0x90`, followed by `count * elementSize` bytes copied and no destination-count store. This conflicts with `_ChunkMalloc` and the current `TerminalChunk` layout, which place payload at `+0x0C`; the exact PPC offset is preserved rather than replaced with the logical safe copy. `_ChunkDup` is the only in-image caller and has no in-image callers itself, though both symbols are global text symbols. The padded-buffer test verifies the copy offset and count behavior without executing the nonempty overrun.

The coverage ledger was audited with IDA against every remaining unexamined range. All 147 functions at `0x33050` through `0x344D8` are 36-byte external-symbol stubs; each loads its matching `__imp_*` dyld binding and tail-dispatches, so these are reviewed as external dependencies rather than Terminal-owned function bodies. The six low-address entries are process-entry, dyld, and Objective-C runtime startup helpers and are likewise classified as runtime infrastructure. At that point the 793-entry ledger had 638 control-flow-confirmed, 155 signature-confirmed, and zero unexamined entries. The remaining source-mapped signature-only methods are `save:mustPrompt:howMany:inFile:` and `clearScrollback:`; their selector or archive/runtime questions remain open. No i386 Terminal reference executable is present in the supplied artifact tree, so independent i386 binary comparison remains unavailable. A subsequent Mach-O symbol pass confirmed that `_ChunkCopy` and `_ChunkDup` are externally visible symbols; earlier notes that treated `_ChunkDup` as unreachable based only on internal xrefs were corrected in the ledger and worklist. The later IDA reinspection mapped the trailing cells `0x37E5C` and `0x37E90` to pointers outside Terminal. In the available mismatched AppKit 1.124.3 image they land at interior suffixes `WithMnemonic:` (`0x4369A170`) and `erData:length:` (`0x436973B8`); both selector bindings remain unresolved.

The final PPC `objc_msgSend` in `clearScrollback:` loads selector cell `0x37E90` (pointer `0x436973B8`); the immediately preceding send loads cell `0x37E5C` (pointer `0x4369A170`). In the available mismatched AppKit 1.124.3 database, these addresses are interior suffixes `erData:length:` and `WithMnemonic:` respectively. Neither establishes the selector or receiver binding for Terminal's required AppKit build.

The distinct sender-taking call before `_clearSelection` was also followed through the PPC selector-reference table: the cell at `0x37E74` contains `0x43697384`. In the AppKit IDA database that address is a NUL byte immediately following `reportException:` at `0x43697374`, not a complete selector name. The sender argument is observed, but this pointer does not identify the method; keep the call unresolved rather than naming it `reportException:`.

In the mismatched AppKit 1.124.3 database, the pointers from `0x37E74`, `0x37E5C`, and `0x37E90` happen to land at a NUL byte and interior string addresses. Those bytes describe only that other framework build and do not establish Terminal's selectors or methods. The first selector at `0x37E74` is independently identified from `selectAll:`'s first receiver-only send; the two tail bindings remain unresolved.
-[TerminalApp save:mustPrompt:howMany:inFile:] (0x12B34) remains signature-confirmed. Correction from a fresh address calculation: its PIC base is 0x12B34, anchored by the `maybeUpdateLibraryMenu` send at 0x133D4 -> selector cell 0x38340; the _NSApp_ptr load is at 0x356B4. The first three dispatches use selector cells 0x38148 (`disablePSOutput`), 0x38594 (`receiveFontFromTrap:`), and 0x385A0 (`displayRows:cols:exitAction:font:size:`), conflicting with the source keyWindow/delegate/type-check path and the call argument setup. Earlier notes assigning base 0x13134, selector 0x38448, and class-ref cell 0x38894 were incorrect. Other recovered branches include prompt/save-panel setup, typed-stream serialization, shared-file mutations, write failure handling, and library-menu update; dispatch parity and archive round-trip remain unverified.




AppKit IDA locates the clearScrollback: leading sender-taking selector slot x37E74 at x43697384, exactly the NUL after
eportException: and before _sendFileExtensionData:length: in the mismatched AppKit image. These foreign-image bytes cannot identify Terminal's selector binding. The trailing pointers likewise must remain unresolved from that image.


A repeated IDA review corrected the save-method PIC calculation: base 0x12B34 makes the known `maybeUpdateLibraryMenu` cell 0x38340 and `_NSApp_ptr` global 0x356B4. The first three selector cells are 0x38148 (`disablePSOutput`), 0x38594 (`receiveFontFromTrap:`), and 0x385A0 (`displayRows:cols:exitAction:font:size:`). They conflict with source's keyWindow/delegate/type-check path and the argument setup; no source behavior change is justified until this dispatch chain is resolved. The method remains signature-confirmed.

`Terminal.h` no longer declares `clearSelection:`. The PPC IDA function and
selector inventories contain `-[FieldView _clearSelection]` but no
`-[Terminal clearSelection:]`; the Terminal binary, AppKit binary, and bundle
resources likewise contain no `clearSelection:` selector/action reference.
Removing the stale prototype allows `Terminal.m` to pass Clang's
`-Werror=incomplete-implementation` check on PPC and i386. All 54 production
translation units pass syntax checking for both Rhapsody target triples.


On 2026-10-05, PPC reinspection of -[FieldView clearScrollback:] identified an off-by-one error in the app-called range helper: reference instruction 0x1F920 tests the preceding row's wrap bit while walking backward; forward extension at 0x1F960 tests the current row. terminalClearScrollbackRange and its native regression now match these rules. The new test failed before the helper fix at firstRow == 4 and passes afterward. Two unresolved receiver-only calls still prevent full method confirmation: cell `0x37E5C` is immediately before the confirmed `reflectPosition` send, and cell `0x37E90` is immediately after it. The available AppKit image resolves these prebound pointers to unrelated strings, so their selectors remain unknown.

On 2026-10-05, Clang 22 rebuilt and ran the C-based Terminal regression targets natively on Windows (`storage`, `filer`, `fstream`, `integerstring`, `shellexec`, `shellpolicy`, `flagmap`, `processinfo`, `processnames`, `identity`, `windowtitle`, `printline`, `servicemanagerstate`, and `scrollback`); all passed. `debugdps` is Objective-C and was not part of this host C run. The binrecon test suite also passed with 978 tests and 4 skips. `binrecon validate` confirms the PPC reference is 333,472 bytes with SHA-256 `B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7`. These checks validate the current sources and pinned PPC input; they do not close the selector/runtime questions in `save:mustPrompt:howMany:inFile:` or `clearScrollback:` or establish i386 binary parity.

IDA disassembly of `-[TerminalApp save:mustPrompt:howMany:inFile:]` at `0x12B34` confirms the first send loads its receiver from the `_NSApp_ptr` data reference and sets only `r3` (receiver) and `r4` (selector) before `_objc_msgSend`. Register `r5` still contains the incoming sender value, so Hex-Rays' rendering of that call with an `a3` argument was a stale-register artifact. `TerminalApp.m` now uses `[NSApp keyWindow]` for this call; the selector and following delegate/type-check flow match the source. Subsequent selector references remain under review.

A further native `scrollback` case sets wrap bits above `screenStart` and verifies backward range selection stops at the visible-screen boundary. It passes with the existing helper, matching the PPC loop bound; it adds coverage without changing the reconstructed behavior. The full host-side Terminal test suite passes.


Live IDA 9.4 pseudocode recheck of `-[TerminalApp save:mustPrompt:howMany:inFile:]` confirms that the source matches the major control-flow/dataflow: the delegate/type gate and beep return, optional file-name reuse, cached save-panel path, save-scope selection, typed-stream creation, direct or shared-window serialization, write/error branches, auto-open defaults, notification, and menu update. The selectors remain opaque because several PPC cells resolve to cross-image metadata pointers or incomplete string suffixes. Correction: the older claim that the first three sends use cells `0x38148`, `0x38594`, and `0x385A0` was an incorrect effective-offset calculation; the initial decompiler cells include `0x37E48`, `0x38294`, `0x37F7C`, and `0x37FA0`. This note predates discovery that the compared AppKit build does not match Terminal's dependency; the current ledger status is control-flow-confirmed, with external selector names still unverified.


The later live IDA check confirms the first-responder send independently through the shared `selectAll:` callsite. It also corrects the trailing-cell addresses: the calls use `0x37E5C` and `0x37E90`, which point outside Terminal to interior strings in the mismatched AppKit build. Keep both trailing sends unresolved.


On 2026-10-05, focused `TerminalApp.m` and `Terminal.m` checks passed for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody` with `-Werror=incomplete-implementation`, LLVM Clang's `macosx-fragile-10.4` Objective-C runtime, and the recovered DR2/System headers. The non-fragile `macosx-10.4` invocation does not support the legacy `@defs` layout assertions and is not the valid command for these sources. The updated PPC ledger/source-map suite passes 49 tests, and the terminal-ppc profile validates the pinned 333,472-byte reference hash.


A fresh IDA PPC xref audit of `_itoa` (`0x2B28`), `_char_offset` (`0x5FE0`), `_compareStrings` (`0x10120`), and `_FreeFlagMap` (`0x20CE8`) found no incoming code or data references to any of the four. IDA marks `_itoa` and `_FreeFlagMap` public and the other two private. Their implementations remain mapped for full function coverage, but the worklist now records them as standalone, unreferenced helpers instead of provisional caller-owned features.

IDA decompilation of `_CreateFlagMapFromZone` (`0x20B5C`) and `_SetFlag` (`0x20D5C`), plus the embedded strings, confirms allocation-failure assertions at `FlagMap.m:21`, `:22`, and `:64` with messages `Malloc flagmap` and `Realloc flagmap`. `FlagMap.c` now emits those `NSAssertionHandler` calls in Objective-C project builds. Host C tests and Objective-C syntax parsing pass; exception behavior still needs target-runtime validation.


IDA reinspection of `_startsleft` (`0x2239C`), `_startsright` (`0x22430`), and `_iswordchar` (`0x224BC`) confirms all three test `runetype & 0x500` only for inputs 0..127; recovered `bsd/ctype.h` defines that mask as `_A | _D`. Inputs `>= 0x80` fail the range guard. Their byte exceptions are `_`/`~` for starts-left, `_` for starts-right, and `_`/apostrophe/hyphen for is-word-character. `WordBoundary.c` already matches these rules. `tests/storage.c` now checks all 256 byte values against the recovered contract.

IDA disassembly confirms the leading `clearScrollback:` send at `0x1F858` uses selector cell `0x37E74`, shared with the first send in `selectAll:` at `0x1FB14`. In `selectAll:`, that cell is the source-confirmed `[self becomeFirstResponder]` selector; both callsites set only the receiver and selector before `objc_msgSend`, so the incoming sender register shown as an argument by Hex-Rays is stale. `FieldView.m` sends `becomeFirstResponder` before `_clearSelection`. Selector cell `0x37E5C` immediately precedes `reflectPosition`; `0x37E90` follows it. Both point to interior suffixes in the mismatched AppKit image and remain unresolved.

The earlier selector-cell comparison below is superseded by a dependency-version
check. Terminal records AppKit current version 1.124.6 and timestamp
`0x383b3ba7` in its `LC_LOAD_DYLIB` command. The supplied AppKit IDA database is
version 1.124.3 with `LC_ID_DYLIB` timestamp `0x36ceb55f`; the DR2 universal
AppKit PPC slice is 1.69.0 with timestamp `0x3550d100`. Therefore the bytes at
`0x43696A98` (`scription:`) and `0x43697384` (NUL) belong to a different AppKit
build and cannot confirm or contradict the selectors used by Terminal. The
The save method's control flow is confirmed from its full IDA body, but its
external selector names remain unverified. `clearScrollback:` remains
signature-confirmed because its two trailing receiver/selector bindings remain
unresolved; the leading `becomeFirstResponder` call is independently identified
through its shared selector cell and the matching `selectAll:` callsite.

The second `clearScrollback:` send is `_clearSelection`, confirmed by cell
`0x37E78` -> Terminal string `0x3D234`. The leading selector pointer
`0x43697384` is not a C-string start in the supplied AppKit image: it follows
`reportException:`'s terminator, and the next selector starts at `0x43697388`.
Those mismatched-framework bytes are inconclusive. The selector is independently
identified as `becomeFirstResponder` because the same cell is used by the
receiver-only first send in `selectAll:`; the incoming sender register is not
prepared as a meaningful argument at either callsite.
The final calls likewise load `0x4369A170` and `0x436973B8`, interior
addresses in other selector strings, with no AppKit selector-reference xrefs
to the containing starts. Their receiver is `self` (`FieldView`), so those
strings do not establish valid target methods. The method remains
signature-confirmed.

On 2026-10-05, a live IDA 9.4 scan found that the three selector-load
displacement patterns for `clearScrollback:` occur only at its final three
`objc_msgSend` callsites (`0x1FAD8`, `0x1FAE8`, `0x1FAF8`). The effective-slot
xref query is empty because these addresses are computed from a runtime table
base; the scan does not identify either unresolved selector. The matching
AppKit 1.124.6 binary is still required to establish those names.

On 2026-10-05, resolving `-[TerminalApp save:mustPrompt:howMany:inFile:]`
through the PPC `__sel_backref` table corrected several source mismatches.
The entry sends `mainWindow`, then `delegate`, `class`, and `isKindOfClass:`.
Save-panel setup gets the chosen cell with `itemWithTag:`, reads its `title`,
sets the panel title, disables only cell tag 0, and redraws the matrix with
`display`. The title branches resolve to `Save Set` for an existing shared
file, `Save` for a single save, `Save As` for prompt/save-as modes, and the
original fallback string for unexpected modes; each bundle lookup uses the
binary's empty-string fallback. The modal selector is `runModal`;
the selected scope is read through `title`, `itemWithTitle:`, and `tag`. Source
and full source-map line now match those recovered calls. The save-panel-mode
unit test and PPC/i386 Objective-C syntax checks pass. No matching i386 Terminal
reference is available, so this still does not prove independent i386 parity.

This 2026-10-05 finding supersedes the earlier save-method notes above that
attributed this path to `keyWindow`, described its selectors as unresolved, or
left it signature-confirmed. The PPC ledger and fresh source map now record the
recovered selector-level flow. The i386 source remains syntax-checked only; a
matching i386 reference executable is still needed for independent binary
parity.

Also on 2026-10-05, the `__sel_backref` rows for `-[FieldView clearScrollback:]`
resolved its complete send sequence: `lockFocus`, `_clearSelection`, `window`,
`disableFlushWindow`, `scrollTo:`, `window`, `contentView`, `setNeedsDisplay:`,
`window`, `enableFlushWindow`, `display`, `reflectPosition`, and `unlockFocus`.
The earlier entry-branch claim of `becomeFirstResponder` and the unresolved
selector notes above are superseded. `FieldView.m` now follows that sequence,
including the redraw and focus release after the state update. Its PPC ledger
entry is control-flow-confirmed. A source regression checks the ordered send
sequence; PPC/i386 syntax checks and the existing scrollback tests pass. There
is still no matching i386 Terminal reference for independent parity. A fresh
i386 `FieldView.m` object was separately inspected in IDA and resolves the same
send sequence; its SHA-256 is recorded in `reconstruction/i386/verification.md`.

The table rows bind the selector-cell offsets (relative to `0x36000`) to their
string offsets: `0x1C94 -> window` (`__sel_backref` row `0x45360`),
`0x1E5C -> display` (`0x430D8`), `0x1E74 -> lockFocus` (`0x43B58`),
`0x1E78 -> _clearSelection` (`0x42738`), `0x1E90 -> unlockFocus` (`0x45198`),
`0x1DDC -> contentView` (`0x42E40`), `0x1EF0 -> disableFlushWindow`
(`0x43098`), `0x1EF4 -> scrollTo:` (`0x445A0`), `0x1F0C -> enableFlushWindow`
(`0x43248`), `0x1F10 -> setNeedsDisplay:` (`0x44AA0`), and
`0x216C -> reflectPosition` (`0x44158`). The method's `addis r4,r31,2` plus
each `lwz` displacement addresses those selector cells from its PPC entry
anchor `0x1F838`.

On 2026-10-05, live PPC IDA selector-table and pseudocode review corrected the
low-level row operations in `FieldView.m`. `_lscrolldown:to:lines:` sends
`_refresh` and then `_srscrolldown:to:lines:` with the line-count-adjusted
range. `_lscrollup:to:lines:` sends `_refresh`; its scrollback branch dispatches
`_sscrollup:to:lines:` followed by `_srscrolldown:to:lines:`, while its normal
screen branch dispatches `_srscrolldown:to:lines:`. `_lclear:to:` sends
`_refresh`; the scrollback branch uses `_srscrolldown:to:lines:` followed by
`_sclear:to:` with `lines->count` as its end argument, and the normal branch
uses `_sclear:to:`. Earlier
source selector assumptions for these methods are superseded. Focused PPC
selector regressions pass, as do PPC and i386 syntax checks. Runtime parity on
the guest remains outstanding; there is no matching i386 reference executable.

The same PPC `__sel_backref` pass on 2026-10-05 completed the `_refresh`
callsite audit at `0x1AC34`. The scrollback branch's selector cell `0x38500`
(`__sel_backref` row `0x42978`) is `_srscrolldown:to:lines:` at both sends;
registers establish ranges `(lineCount - top, lineCount + bot, top)` and
`(lineCount + drawCursOK - top, lines->count, top)`. The normal-screen cell
`0x384FC` (row `0x42988`) is `_srscrollup:to:lines:` with
`(topline + bot, topline + drawCursOK, top)`. Cell `0x38154` (row `0x44168`)
resolves `refreshscreen`; the common tail resolves `reflectPosition` at
`0x3816C` (row `0x44158`), `window` at `0x37C94` (row `0x45360`), and
`flushWindow` at `0x380A8` (row `0x43478`). Source now matches both argument
flow and selector order. A regression fails on the previous endpoint and tail
sequence and passes after correction; PPC and i386 syntax checks pass. Guest
runtime behavior remains unverified.

On 2026-10-05, PPC IDA selector-table review completed the redraw tail of
`-[Terminal pruneNumLinesTo:]` at `0xEB14`. After the row compaction and
selection adjustment, the method gets `window`, then `contentView`, sends
`setNeedsDisplay:YES`, sends `display` to the Terminal, sends
`reflectPosition`, gets `window` again, and reenables window flushing. The
reference cells resolve through `__sel_backref`: `contentView` at cell `0x37DDC`
(row `0x42E40`), `setNeedsDisplay:` at `0x37F10` (row `0x44AA0`), `display`
at `0x37E5C` (row `0x430D8`), `reflectPosition` at `0x3816C` (row `0x44158`),
and `enableFlushWindow` at `0x37F0C` (row `0x43248`); both window lookups and
the initial disable-flush call also match. `Terminal.m` now includes the
previously omitted `display` and repeats the window lookup before enabling
flush. The regression fails against the previous source sequence and passes
after the correction. `Terminal.m` passes PPC and i386 syntax checks with the
recovered System framework headers. A fresh binrecon source-map build retained
640 mapped and 153 unmapped entries, with no duplicate candidates or boundary
disputes, and refreshed the affected source lines. Guest runtime behavior is
unverified.

PPC IDA body review on 2026-10-05 confirms `_winTitle` (`0xF840`) matches
`WindowTitle.c:40`: options are emitted in custom-title, command, PTY basename,
dimensions, and file-name order; command/custom/file length gates are retained;
the two-space/D0/space separator, process-name fallback, localized debug
suffix, and zone-backed cached result match. `_pathCompress` (`0xFB9C`) matches
`PathCompress.c:7` for the home-prefix comparison, suffix-length check, slash
count, `.../` prefix and retained suffix. `Terminal.windowHook::` passes these
helpers the recovered values. The helper rows now reflect their mapped source
and callers instead of their old candidate/pending classifications. The native
`windowtitle` and `storage` tests cover title composition and path compression;
this is PPC reference comparison with shared-source portability, not
independent i386 binary evidence.

Correction to the initial 2026-10-05 `outputdata:len:` selector audit: the
second cell was miscalculated. With method entry `0xC580` as the PIC base, the
first send loads selector cell `0x37E74`, independently identified as
`becomeFirstResponder` through the receiver-only send in
`-[FieldView selectAll:]`. The next cell is `0x38098`, which contains the
`_clearcursor` selector string at `0x3DF8C`; the emulator call is cell `0x37DA8`
-> `output:len:`. The common tail then loads `window` from cell `0x37C94` and
`flushWindow` from cell `0x380A8`, matching the previously audited
`-[FieldView _refresh]` tail. `Terminal.m` now sends `becomeFirstResponder`
before `_clearcursor`, forwards bytes to the emulator, and flushes the window
after cursor update. Two focused regressions failed against the old source
sequence and pass after correction. The delayed-cursor, timer, and post-prune
framework selectors remain under review.

The 2026-10-05 native pass regenerated a full source map from the pinned PPC
IDA analysis and validated it against the complete function partition. It
matches the checked-in map exactly: 640 mapped, 153 unmapped, zero duplicate
candidates, and zero disputed boundaries. All 55 current `MFILES` translation
units passed syntax checking for both `powerpc-apple-rhapsody` and
`i386-apple-rhapsody`; the binrecon suite passed 990 tests with 4 skipped, the
focused Terminal selector/ledger/source-map tests passed 58, and the Terminal
`windowtitle` and `storage` native tests passed. A subsequent focused regression
covers the corrected `outputdata:len:` opening selector sequence.

After the `outputdata:len:` selector corrections, the Terminal-specific
selector tests pass (11 tests), `Terminal.m` passes PPC and i386 syntax checks,
and the full binrecon suite passes (992 passed, 4 skipped). Binrecon still validates the
793-entry PPC ledger at 640 control-flow-confirmed and 153 signature-confirmed.

On 2026-10-05, a direct decode of the PPC `__sel_backref` pairs corrected the
remaining `outputdata:len:` and `selectAll:` selector assumptions. Cell
`0x37E74` maps to `lockFocus` (string `0x3D228`), and cell `0x37E90` maps to
`unlockFocus` (string `0x3D264`); both cells are shared by `outputdata:len:`,
`selectAll:`, and `clearScrollback:`. In `outputdata:len:`, cell `0x3806C`
maps to `scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:` and
`0x38068` to `handleDirtTimer:`. PPC register arguments pass `self` as
`userInfo`; the returned timer then receives `retain` through cell `0x37CF0`
(string `0x3C614`) before storing in `longTermTimer`. `Terminal.m` now matches
those arguments and ownership. `selectAll:` now pairs `lockFocus` and
`unlockFocus` around the selection update, replacing the erroneous
`becomeFirstResponder` and `display` sends. Four focused regressions failed
against the prior source and pass after correction. All 55 Terminal manifest
translation units pass syntax checks on PPC and i386; the full binrecon suite
passes 995 tests with 4 skipped, all 14 Terminal host test targets pass, and
the Terminal-specific selector suite passes 14 tests. The reference-only PPC
profile still has no rebuilt artifact, and guest runtime verification remains
unavailable.

A follow-up disassembly audit of `outputdata:len:` confirms the status tail
loads the application object from the `_NSApp_ptr` data reference and sends
`isHidden` (cell `0x380AC`), followed conditionally by `updateAppStatus`
(cell `0x380B0`) to the same receiver. `Terminal.m` now uses `[NSApp isHidden]`
and `[NSApp updateAppStatus]`; it no longer routes through a delegate or the
unrelated `displayWindowStatus` selector. The new regression failed before
this source correction and passes afterward; the selector suite now has 15
passing tests. PPC and i386 `Terminal.m` syntax checks pass after the edit.

The selector pair at cells `0x3807C` and `0x380A4` also confirms
`outputdata:len:` cancels a pending `_delayedCursor:` perform through
`NSRunLoop` before scheduling its replacement on `self`. Source now preserves
that order. A focused regression failed before the correction and passes after;
the Terminal selector suite now passes 16 tests, and `Terminal.m` syntax passes
for PPC and i386.

The source-map builder was rerun against the pinned IDA analysis after the
latest edits. Its semantically validated output is byte-identical to the
checked-in map: 640 mapped, 153 unmapped, no duplicate candidates, and no
disputed boundaries. The current full binrecon run reports 996 passed and
4 skipped, with one failure because the 30-second angr paired-equivalence
fixture timed out under aggregate suite load; that exact test passes alone in
11 seconds. The Terminal-specific suite passes all 16 cases.

IDA review of `_getDefaultColors` (`0x2B74`, 784 bytes) found that the source
omitted the reference's Objective-C exception handler. The PPC body registers
an NS handler before reading `TextColors`, removes it on the normal path, and
returns through the caught-exception path otherwise. `getDefaultColors` now
uses the matching `NS_DURING`/`NS_HANDLER` structure while retaining the eight
RGB triplets, optional 2-bit grayscale quantization, and color ownership
sequence. A regression failed before the correction and passes afterward; the
focused Terminal suite now passes 17 cases, and `TerminalDefaults.m` parses for
PPC and i386. The validated source map retains 640 mapped and 153 unmapped
entries with no duplicate candidates or boundary disputes; three later
`TerminalDefaults.m` source lines were refreshed.

Native verification from the approved `D:\RhapsodiOS` checkout on 2026-10-05
reconfirmed the 333,472-byte PPC reference hash, validated the 793-entry ledger
(640 control-flow-confirmed, 153 signature-confirmed), and semantically
validated the saved IDA analysis and source map (640 mapped, 153 unmapped, no
duplicate candidates or boundary disputes). The focused Terminal selector
suite passes all 16 cases, and the Terminal host test make target exits
successfully. Previously captured manifest logs show all 55 current production
translation units pass PPC and i386 syntax checks; a same-turn rerun could not
reproduce that command because the temporary framework include junctions
resolve differently from this shell. The guest at `127.0.0.1:2222` is not
reachable, and no rebuilt Terminal executable or guest runtime result exists.

The defaults-loader comparison against PPC IDA (`_defaultsFromDB`, `0x2E84`,
1036 bytes) found extra source operations absent from the reference: zeroing the
record, creating and draining a local autorelease pool, and returning early
when the shell buffer allocation fails. The loader now follows the recovered
allocation and direct-assignment flow. A regression failed before the change;
the focused Terminal selector suite passes all 18 cases. `TerminalDefaults.m`
passes syntax checks for PPC and i386, and the source map passes schema and
source-path validation with 640 mapped, 153 unmapped, no duplicate candidates,
and no disputed boundaries. The saved analysis snapshot used for a fresh
reference-backed validation was truncated, so this update makes no new claim
of a fresh comparison against that snapshot.

IDA review of `-[Terminal childExit:status:]` (`0xCA8C`) found a key-window
cleanup branch missing from source. The source now clears the cursor under
focus and flushes the window when it is key; a regression failed before the
fix and passes afterward. An initial selector review used the wrong TOC
anchor. Recalibrating from the method's `performClose:` tail resolves its first
two sender calls to `kill` (`0x3800C`) and `close` (`0x37F54`); source now
matches after a second regression failed before changing `invalidate` to
`close`. The focused selector suite passes 20 cases. The ledger returns to 640
control-flow-confirmed and 153 signature-confirmed entries. `Terminal.m` parses
for PPC and i386. No rebuilt binary or guest runtime result is available.

The `-[Terminal invalidate]` PPC sequence at `0xC388` was re-read alongside
its source: the inherited invalidation guard, document-edited reset, cursor
timer shutdown, delayed-perform cancellation, dirt-timer removal, conditional
device unregister, shell detachment/close/release, emulator release, and
dead-state write appear in the same order. Fresh target-triple syntax checks
for `Terminal.m` pass under both PPC and i386 Rhapsody triples.

A method-entry TOC decode of `-[Terminal pruneNumLinesTo:]` (`0xEB14`) resolves
the `__sel_backref` cells to the visible clear-selection branch and complete
redraw tail: `window`, `disableFlushWindow`, `_clearSelection`, `contentView`
(`0x37DDC`), `setNeedsDisplay:`, `display`, `reflectPosition`, a fresh `window`,
and `enableFlushWindow`. Source already matches; the earlier interface note that
called `contentView` unresolved was stale. Its focused regression now checks
the whole selector sequence. The same consistency pass corrected stale
`clearScrollback:` notes: all its sends are resolved and the ledger marks it
control-flow-confirmed.

IDA disassembly of `-[vt100 vt100CollectString:]` (`0x17D40`) confirms the PPC
method increments the count, stores the input byte, grows at capacity, and
completes when the byte is at most `0x1F` or the count exceeds `0x400`. Its
completion store writes NUL to element `count - 1`, replacing both the control
terminator and the byte that crosses the limit. The 81-byte display window
therefore includes that NUL and contains at most 80 payload bytes. The host
`VT100String.c` model previously retained the final byte and reported it in the
view length; a storage regression failed on the control terminator before the
helper was corrected. Control-byte exclusion, the ellipsis window, and the
limit-crossing byte now match IDA; the full Terminal host suite and PPC/i386
syntax checks for the helper pass.

The method-entry TOC decode of `-[DirtMonitor init]` (`0x3A4C`) resolves its
notification setup selectors to `portWithMachPort:` (`0x37D4C`), `retain`
(`0x37CF0`), `setDelegate:` (`0x37D50`), `currentRunLoop` (`0x37D54`), and
`addPort:forMode:` (`0x37D58`). PPC retains the wrapped port before assigning
its delegate and registers it with the run loop afterward. `DirtMonitor.m` now
matches that order and ownership; a focused regression failed before the
source change and passes afterward.

The PPC failure branch of `-[Terminal setFileName:sharesFile:]` (`0xBE5C`)
uses the current `NSAssertionHandler`, constructs the embedded file-name
message, and sends `handleFailureInMethod:` with `_cmd`, the terminal instance,
`Terminal.m`, and line 133 before falling through to `strcpy`. The source now
preserves that handler context and fallthrough. A focused regression failed on
the previous `NSAssert` shorthand and passes with the recovered call. The
source map was rebuilt against the PPC IDA analysis and still reports 640
mapped and 153 unmapped functions, with no duplicate or disputed boundaries.

IDA PPC comparisons of `_openFStream` (`0x6FC4`), `_nextGetChar` (`0x7008`),
`_prevGetChar` (`0x717C`), `_peekChar` (`0x72E0`), and `_getPosition` (`0x7440`)
found that the reference assumes an initialized, nonempty stream. The source
had added null/empty-state early returns to these helpers; those branches are
removed so the shared implementation follows the recovered precondition and
control flow. The existing `fstream` regression exercises line boundaries,
wrapped rows, end-of-stream, and cursor normalization.

IDA PPC disassembly of `_taskIsBlocked` (`0x52EC`) shows `extsb` of the cached
thread-count byte before both the thread-loop comparisons and the
`vm_deallocate` size shift. `DirtMonitor.m` now uses a signed loop index and
the sign-extended count for the deallocation size, matching the PPC behavior
when the cached count's high bit is set.

IDA PPC review of `_become_root` (`0x20EC0`), `_become_user` (`0x20F08`), `_get_process_info_from_pid` (`0x21220`), `_cmdtok` (`0x21340`), `_execs` (`0x215B8`), and `_execs0` (`0x216E0`) found their reconstructed C control flow matches the reference. The process query uses `{CTL_KERN, KERN_PROC, KERN_PROC_PID, pid}`, lazily sizes its buffer, and reads the PPC process record at offsets 20, 24, 163, 392, 396, and 404; the shell helpers preserve in-place tokenization, `execvp` argument construction, and login-name prefixing. The ledger now records the corresponding evidence and source locations; the full PPC ledger remains at 793 reviewed entries.

A fresh source-completeness check compared the checked-in `Resources/` tree with the supplied Terminal bundle: all 32 files have identical relative paths, lengths, and SHA-256 hashes. Every translation unit listed by the current `MFILES` manifest is present (55 entries). The reference-tree search found only the PPC Terminal executable, so there is still no i386 image for independent binary comparison.

PPC IDA review of `-[Shell system:login:folder:env:]` (`0xB558`, 1044 bytes) found the PTY slave `fchmod` call passes `0x190` (octal `0620`). `Shell.m` had used `0400`; it now passes `0620`. PPC instructions show the slave descriptor in `r3` and the literal `0x190` in `r4` immediately before `_fchmod`. PPC and i386 Rhapsody syntax checks pass. A newly emitted i386 Mach-O object was decompiled in IDA and likewise loads `0x190` as the mode argument. The surrounding PTY, `vfork`, session, identity, environment, exec, and error-pipe paths match the source.

PPC IDA review of `-[Shell system:login:folder:env:]` also confirmed `c_lflag` is masked with `0x80400224` before OR-ing `0x5CB`; `Shell.m` was corrected from `0x80400267`. The fresh i386 Mach-O object decompiles to the same mask and PTY mode (`0x190`).

IDA verified `_defaultModes` at `__data` address `0x35024`: it is exported, zero-initialized in the reference image, and the Shell launch method reads it on `TIOCGWINSZ` failure into the first four bytes of `winsize`. No in-image function writes the global. `Shell.m` now defines the matching exported zero-initialized `defaultModes` and copies exactly one word into the fallback buffer, preserving the original global-based behavior.

The defaults persistence helpers were rechecked in PPC IDA and in a fresh
decompilation of the current-source i386 Mach-O object
`TerminalDefaults.m.o` (SHA-256
`D475B97429069FEBECFB2E85AD45AFCBD98216CE6602C0385EA09060F10B65D5`).
`defaultsFromDB` matches the 0x58-byte zone allocation and field offsets,
preference keys, color load, shell-path copy, fixed-pitch font, and custom title.
`writeDefaultsToTypedStream` matches version 5, the typed-value encoding,
eight color objects, and the trailing text-attribute integer.
`readDefaultsFromTypedStream` matches the v2 coordinate scaling, v3 default
colors, v4 legacy color decoding and two-bit grayscale conversion, v5 object
decoding, rejection of versions above 5, and exception cleanup of the allocated
record. The three source implementations already matched these paths; this
analysis corrects their stale “behavior candidate” labels in the function
worklist. The i386 object is generated from shared source and does not provide
independent i386 Terminal parity evidence.

PPC IDA comparison of `-[ServiceProvider doService:pasteboard:isDrag:dragTerm:errBuff:]` (`0x2EFF0`, 6248 bytes) confirms the service routing branches, sheet population and selection, privilege restoration in child processes, `/dev/null` fallback, 4096-byte pipe versus temporary-file input split, stdout/stderr routing, shell selection, 20-iteration nonblocking wait, 512-byte output reads, RTF conversion, `/usr/bin/open` paste path, pasteboard declarations, and common cleanup match `ServiceProvider.m`. IDA resolves the process waits to `_wait4(pid, &status, 1, NULL)`; the source's `waitpid(pid, &status, WNOHANG)` has the corresponding BSD wait interface and preserves the returned-status and timeout logic. The source retains the binary's unusual long-input failure condition `open(...) == 0`. No behavioral change was indicated.

PPC IDA comparison of `-[ServiceManager save:]` (`0x2EA20`, 888 bytes) confirms the NSSavePanel configuration, save-matrix row/title copy, selection preservation and scrolling, `open` with flags `0x601` and mode `0666`, `fdopen("w")`, cache service-count check, `sendAction:to:forAllCells:` serialization, and final `fclose` match `ServiceManager.m`. The binary beeps and returns on a cache-count mismatch after opening the stream; the source retains that branch. Binrecon ledger validation reports 793 entries (640 control-flow-confirmed, 153 signature-confirmed). No source change was indicated.

PPC IDA comparison of `-[ServiceManager fillServiceFromWindow:]` (`0x2DA94`, 524 bytes), `setFlags:fromControlsIn:` (`0x2DCA0`), and `setFlagsFromCell:` (`0x2DD5C`) confirms each record offset and byte store, all nine option resets, enabled/disabled control handling, selected-cell tag accumulation, required-selection default, execution/routing flags, zone-owned command copy and `-f` test, and blank-key fallback. The source and state helpers match, including the binary's unguarded command `strlen` and its empty-key space byte. No behavior change was indicated.

PPC IDA control-flow audit of `-[ServiceManager change:]` (`0x2DDC4`, 512 bytes), `warnAboutStrangeness:` (`0x2DFC4`), and `checkSettings` (`0x2E088`) confirms source behavior: end editing and display the matrix before validation; reject invalid settings; fill and warn on the service record; copy the selected title into the manager zone; replace the selected cache row and enable cache saves; clear dirty state; rebuild and redraw the matrix; flush the window; and free temporary record storage. The warning is gated by both selection type bit 4 and selection option bit 2. Settings validation returns success for acceptable settings, presents the localized alert for error 8, and beeps for other errors. No source change was indicated.

PPC IDA comparison of `-[TerminalApp openServicesFile:]` (`0x13E0C`, 1636 bytes) confirms the readable-file and Add/Don't Load gates, basename prompt, summary initialization, open error handling, lazy service-set load with example offers disabled, repeated `readService:fromFile:zone:` parsing, duplicate-name scan, Replace/Skip/Cancel response branches, insertion and imported name/command frees, comma-separated summary, service-manager reload, final alerts, and return values match `TerminalApp.m`. The reference only frees parsed records on the insertion branch; the reconstructed source preserves the same branch behavior. Cross-layer IDA checks of `readService:` (`0x2ABB8`) and `addNewTermService:` (`0x2BA0C`) confirm three-line parsing and deep-copy insertion. No behavior change was indicated.

PPC IDA comparisons of `-[ServiceCache writeServices]` (`0x2BCE0`), `writeService:toFile:` (`0x2BEBC`), `convertString:toPrintable:` (`0x2C070`), and `convertPrintable:toString:` (`0x2C134`) confirm the source's durable `.svcs` and cache format. Writes require a loaded set and `saveOK`, apply the existing-file security check (mode mask 18), create new files with the current user and mode `0644`, serialize records in array order, close and refresh the modification timestamp/Services file, and set `needsSave` when writes are deferred. Record output uses ten signed-byte fields, unsigned flags, name, and escaped command. Printable characters pass through, backslashes double, and other bytes use three-digit decimal escapes; decode reverses those rules. No behavior change was indicated.

PPC IDA comparison of `-[ServiceCache checkFile:forNaughtyModes:]` (`0x2BF70`, 256 bytes) confirms `stat` failure returns false without an alert. A successful stat passes only when the file owner is the current user and `(st_mode & modes) == 0`; every other successful-stat case presents the localized suspicious-permissions alert and returns false. The source matches the owner/mode gate, alert, and return paths. No change was indicated.

PPC IDA control-flow audit of `-[ServiceCache loadServiceSet]` (`0x2A5C8`, 1500 bytes) confirms the source's directory creation and mode check, nonempty-cache security gate, optional default-services prompt and descriptor copy, create-empty fallback, cache timestamp capture, initial ten-record allocation and ten-record growth, three-line parser loop, `fopen` failure cleanup, initialized flag, and stale Services-file update. Assembly confirms the example source and destination descriptors are closed on their respective paths; the decompiler's branch layout initially obscured the shared destination close. No source change was indicated.

PPC IDA comparisons of `-[ServiceCache saveService:inSlot:]` (`0x2B818`), `importService:from:` (`0x2B8C8`), `addNewTermService:` (`0x2BA0C`), and `removeServiceAt:` (`0x2BB78`) confirm source ownership and mutation behavior. Replacement releases the old name and frees its zone command, then deep-copies the new record and signals a changed set. Deep copy transfers the 28-byte record, replaces the name with a zone-owned initialized copy, allocates/copies the command, and asserts on allocation failure. Append increments count, reallocates by one record, copies the record, and notifies. Removal shifts raw records, decrements count, reallocates, and notifies without individually freeing the removed row's name/command. The binary's index guards check only the upper bound; the source preserves those conditions. No behavior change was indicated.

PPC IDA comparison of `-[ServiceCache init]` (`0x2A384`), `setOKToSave:` (`0x2A4FC`), and `serviceSetChanged` (`0x2A55C`) confirms the cache paths and state transitions. Initialization constructs `~/Library/services`, `~/Library/Terminal.service`, and `<dirPath>/DefaultServices`, leaves the service-directory object nil, and sets `saveOK=1`/`needsSave=0`. Save permission changes only when the value differs; switching to 1 writes deferred changes when `needsSave` is set. An initialized set is considered changed when the cache path is missing, stat fails, or its mtime is newer than `lastMod`; uninitialized sets always report changed. Source matches without changes.

PPC IDA comparison of `-[ServiceCache updateServicesFile]` (`0x2AE7C`, 2460 bytes) confirms the export-directory walk and alerts, existing `Terminal.service` permission and modification-time gate, missing-file chmod, `Services.subproj` localization-table name extraction, service eligibility filter, pasteboard send/return type arrays, default and localized menu titles, key-equivalent and user-data fields, conditional timeout, atomic property-list write, `NSUpdateDynamicServices`, and failure alert/save-disable path match `ServiceCache.m`. The source preserves the reference's mutation of the returned resource path at `.subproj` while deriving the localization table. No behavior change was indicated.

PPC IDA comparison of the six `TerminalDO` methods (`init` at `0x15238`, `protocolVersion` at `0x15650`, three forwarding wrappers at `0x15664`/`0x156D8`/`0x15748`, and the 3256-byte primary RPC at `0x157B8`) confirms the shared source. Initialization installs the default NSConnection root object, registers the receive Mach port with bootstrap, conditionally registers the public name, and returns nil after failed registration. Protocol version is 65538; wrappers pass the exact window, shell, wait, capture, exit-action, title, directory, environment, and result defaults. The main RPC matches Terminal window selection/reuse and handle assignment, terminal output/title/input paths, real uid/gid restoration, `/dev/null` and small-pipe/large-temp-file stdin setup, independent stdout/stderr capture, process group setup, directory fallback, environment replacement, shell execution, 30-second select reads, 20x100ms nonblocking background wait, signal/setup/exec exit-code mapping (`-3`, `-1`/`-2`, `221`), output data construction, and common return-code store. No source change was indicated.

A fresh PPC IDA audit of `ServiceManager setupExecBoxForWindowType:routingFlags:andSetPopUp:` (`0x2CEA8`), `polymorphicOptsChanged:` (`0x2D328`), and `execTypeChanged:` (`0x2D48C`) found a source mismatch. In `execTypeChanged:`, the binary maps selected execution type 32 to setup `windowType=1` and type 64 to `windowType=4`, while always passing `routingFlags=4`; source had passed 32/64 as `windowType` and 1/4 as `routingFlags`. The tested `TerminalServiceManagerGetExecutionBoxArguments` helper now captures the PPC mapping, and `execTypeChanged:` uses it. The setup labels, state, shell option behavior, popup mapping, polymorphic-state reactions, and dirty update otherwise match. The regression failed before the helper existed, passed after the fix, the ServiceManager state target passed, the full Terminal host test suite passed, and PPC/i386 syntax checks for `ServiceManager.m` succeeded. The host SDK emitted existing header/method-access warnings.
PPC IDA audit of `-[ServiceManager setDirty:]` (`0x2C870`), `updateForCurrentDirtiness` (`0x2C8E0`), `control:textShouldEndEditing:` (`0x2E6B0`), and `controlTextDidEndEditing:` (`0x2E7D8`) confirms dirty transitions, selection gating, button/document state, rename validation, and action dispatch. The end-edit rename path also revealed an ownership mismatch: it shallow-copies the selected record, but `ServiceCache saveService:inSlot:` frees the selected record's command before deep-copying the replacement. The source now allocates a manager-zone command buffer and copies the original command before saving. The regression exercises independent command ownership and passes; the full host suite and PPC/i386 `ServiceManager.m` syntax checks pass. Existing legacy SDK and host CRT warnings remain.

PPC IDA comparisons of `-[ServiceManager cellCountFor:]` (`0x2C1F0`), `renewForServiceSet:` (`0x2C748`), `isDirty` (`0x2C85C`), and `editSelectedServiceName:` (`0x2C9F4`) confirm row/column product, conditional row renewal, localized cell titles, sizing/display, direct dirty-byte return, and selected-cell field-editor setup with beep-on-missing-editor behavior. Source matches without changes.

PPC IDA comparison of `-[ServiceCache readService:fromFile:zone:]` (`0x2ABB8`) confirms the eleven-value numeric parse, assignment of ten signed option bytes and flags, three-line record reads, newline trimming, requested-zone name creation, printable command decoding, and zone-owned command allocation. The source matches these paths without changes.

PPC IDA comparisons of `-[ServiceManager setControlsFromService:]` (`0x2CD18`), `setControlsIn:fromFlags:` (`0x2D22C`), and `makeDirty:` (`0x2D528`) confirm the control update order and flag fields, enabled-cell state calculation, command and key display, window flush/display, and sender-independent dirty transition. The source matches without changes.
PPC IDA comparisons of `ServiceCache discardServices` (`0x2AD9C`), `serviceSet` (`0x2AE6C`), `disableOfferExamples` (`0x2ABA4`), and `loadCommandsMenu` (`0x2C1E4`) confirm record cleanup and state reset, direct set return, one-way example-disable flag, and empty menu hook. The source matches. ServiceProvider prompt helpers `ok:`, `cancel:`, `pasteboard:containsType:`, `copyString:`, `ensureNibLoaded`, `replace:with:in:`, and `windowWillResize:toSize:` (`0x309D4`–`0x30E9C`) also match PPC control flow for modal panel state, type enumeration, zone allocation/assertions, nib loading and size capture, command-string replacement, and window minimums.

PPC IDA comparisons of `ServiceProvider provideService:userData:error:` (`0x2EE14`) and both `newCommand` overloads (`0x30858`, `0x30894`) confirm cache initialization/error paths, user-data service-key lookup, nil-path forwarding, shell selection, environment propagation, and command output. The exported `NSUserData` is formatted as a decimal string by `ServiceCache`; the provider must convert it with `intValue`. Source previously sent `checkSettings`, which could not recover the service key, and now uses `intValue`.
The PPC-confirmed `NSUserData` conversion fix and accompanying accessor/provider audit pass both PPC and i386 source syntax checks. The full Terminal host test suite exits successfully; compiler output contains existing CRT and legacy-header warnings.
PPC IDA comparisons of `ServiceManager freeService:` (`0x2D8D8`), `whyAreSettingsNotAcceptable` (`0x2D924`), `nameUnique:` (`0x2D9B8`), `windowDidResize:` (`0x2E5A8`), `windowWillResize:toSize:` (`0x2E624`), and `controlTextDidChange:` (`0x2E678`) confirm temporary record ownership, service-setting acceptance, unique-name scan, matrix resize dimensions, original-frame minimum size, and dirty-state callback. The source matches without further changes.

Full PPC IDA comparisons of `ServiceManager serviceSelected:` (`0x2CB2C`), `add:` (`0x2D560`), `windowShouldClose:` (`0x2E168`), and `saveService:` (`0x2ED98`) confirm matrix action suppression/selection state, generated service creation, close confirmation branches, and per-cell cache serialization. The shared source matches each path.

PPC IDA comparisons of `CommandPanel showPanel` (`0x2664`), `commandEntered:` (`0x27B4`), and `control:textView:doCommandBySelector:` (`0x29D8`) confirm lazy UI load and command restore, default-encoding launch and LastCommand persistence, bounded ten-entry history, Up/Down traversal, completion delegate, and empty-history behavior. Source matches without changes.

PPC IDA comparison of `Terminal setUpWithDefaults:inFolder:env:` (`0xBA84`) confirms shell and emulator ownership/delegates, output image and initial state, superclass defaults, shell startup arguments, dirt monitor registration, conditional periodic timer, filename reset, and startup-failure alert. IDA renders the byte-sized `evflags` clear as a 32-bit `0x20000000` mask because of PPC big-endian layout; it corresponds to the source's `0x20` byte mask. No source change was needed.

PPC IDA comparisons of `Terminal fileName`, `sharesFile`, `setFileName:sharesFile:`, `setDefaults:`, `shell`, `cancelDelayedPerforms`, `invalidate`, `dealloc`, and `setEmulator:` (`0xBE38`–`0xC570`) confirm the shared accessors, filename ownership, defaults/color propagation, delayed selector cancellation, guarded shell teardown, and emulator assignment. The `dealloc` body removes dirt timers, obtains the receiver's zone, schedules `TerminalApp lazyDestroyZone:wait:` with a zero delay, then calls `super`. Selector and argument setup at PPC `0xC514` confirm the deferred zone destruction; shared source follows it.

PPC IDA comparisons of `Terminal outputdata:len:`, `scheduleUpdate`, `shellDevice`, `endOfFileOn:`, `childExit:status:`, `removeDirtTimers`, the output forwarding methods, `broadcastSize`, `setFrameSize:`, `keyDown:`, paste methods, service/DO accessors, title methods, `windowWillResize:toSize:`, `windowHook::`, and `handleCursorBlinkTimer:` (`0xC580`–`0xDB0C`) match the shared source. This includes cursor and redraw order, timer throttling and ownership, localized exit-status branches, PTY resize ioctl, keyboard routing, paste encoding/leading-CR conversion, title-mode state, and cursor-timer exception cleanup. No additional source correction was indicated.

PPC IDA comparisons of `cursorBlink:`, key/main-window callbacks, debug tracking, emulator access, and miniaturize/deminiaturize callbacks (`0xDC30`–`0xE3E8`) also match `Terminal.m`. The audit confirmed timer ownership, dead-key/cursor visibility transitions, preferences notifications, debug activation state, and dirt/redraw updates across miniaturization.

Correction: the preceding range included `windowShouldClose:` at its upper boundary, and its full body is now audited as well. PPC IDA comparisons of `windowShouldClose:`, dirty updates, defaults/window access, extra window info, scrollback pruning, drag negotiation and execution, spring-loaded paste, color drops, mini-window status, and dirt timer callbacks (`0xE3E8`–`0xF67C`) match the shared source. The close path covers forced quit, process-list alert variants, cancellation, next-window activation, shell kill, and deferred zone destruction. No further code correction was indicated.

PPC IDA comparison of `TerminalApp setupDefaults` (`0x107B4`) matches the shared lazy defaults initialization: user defaults zone creation/naming, passwd-based user selection with fallback initializer, beep and autorelease-pool cleanup on failure, bundle persistent-domain creation, and the final search-list ordering.

PPC IDA review of `TerminalApp applicationWillFinishLaunching:` (`0x10A60`) and `new:`, `newShell:`, `newShell:env:`, and `newShell:inFolder:env:` (`0x102FC`–`0x103AC`) matches shared startup behavior. It confirms privileged/DPS initialization, 28 registration defaults, process-name and quit-flag setup, null forwarding arguments, shell-default replacement, environment conversion, TerminalAgent creation, window delegate/target wiring, and failure cleanup branches.

`TerminalApp applicationDidFinishLaunching:` (`0x10E60`) was rechecked against the current implementation. Services send types and font manager, optional Library menu, eight preference menu items, ServiceProvider registration, status item setup, optional distributed-object zone, NXOpen/startup-action gates, and retained I-beam cursor setup match.

PPC IDA comparison of `TerminalApp openFile:` (`0x1360C`) confirms permission and mapped-data failures, typed-stream iteration, per-window zone/defaults/TerminalAgent creation, saved coordinates and hidden state, delegate/target setup, exception alert handling, last-visible-window activation, and the single-window shared-file reset. `application:openFile:` (`0x13C24`) matches its special ignored path, `.term`/`.svcs` routing, directory-shell and executable branches, and return behavior. No code correction was indicated.

2026-10-05 correction for `-[TerminalApp save:mustPrompt:howMany:inFile:]`
(`0x12B34`): PPC `__sel_backref` and branch inspection show the multi-window
scan does not filter by `sharesFile`. It serializes windows whose stored
filename matches the target; for `howMany == 1`, unmatched windows are skipped,
while Save Set mode assigns the target filename with sharing enabled before
serializing unmatched Terminal windows. Source previously inverted these cases
and stopped at the first unmatched Save Set window. `TerminalApp.m` now follows
the recovered action and `SavePanelMode` tests cover matching and unmatched
windows in both modes. The PPC ledger remains control-flow-confirmed based on
the combined selector and branch comparison. PPC/i386 syntax checks and the
focused save-panel test pass; i386 evidence is shared-source portability only.

2026-10-05 FieldPrint audit against PPC IDA at `0x6118`–`0x6F30` confirms the
print-window and accessory setup, `isFlipped`, print-panel operation, whole-row
page-height formula, row clipping, attribute backgrounds/underline/bold
overstrikes, range choices, and attribute-image changes. The PPC bodies access
the public `FieldView` ivars directly; `FieldPrint.m` previously added
`_getFieldPrintViewInfo:` sends in `fieldPrint:`, `adjustPageHeightNew:...`, and
`rangePicked:`. Those methods now use the same direct fields (`lines`, `height`,
`bwidth`, `bheight`, selection flags/endpoints, `topline`, and `cursorx`). Both
PPC and i386 `FieldPrint.m` syntax checks pass, the full Terminal host test
suite passes, and all seven PPC ledger entries remain control-flow-confirmed.
The direct behavioral evidence is PPC-only because no matching i386 Terminal
binary is available.

PPC IDA comparison of `-[TerminalApp print:]` (`0x12560`) confirms the source
gets the main window's delegate, requires it to be a `Terminal`, forwards the
original sender to that object, and beeps on any failed check. The method
matches without a source change; i386 evidence is shared-source portability.

PPC IDA comparison of `-[FieldPrint print:]` (`0x6548`) also confirms it passes
the cached shared `NSPrintInfo` to `printOperationWithView:printInfo:`, attaches
the accessory view and panel, and runs the operation. `FieldPrint.m` now passes
the same cached `fieldPrintInfo` global instead of reacquiring the shared
instance, matching the recovered send sequence.

Rechecking `-[DirtMonitor isDeviceDirty:]` (`0x4848`) against the PPC body
found that the binary zeroes its 36-byte `TerminalProcessInfo` buffer before
querying a newly discovered task. The source now clears that struct immediately
before `unix_pid` and process metadata queries, preserving its zero-state if
either path fails. The port-rename fatal return in the binary skips
`vm_deallocate`; source previously cleaned up the task list there, so that
cleanup was removed to match the recovered branch. A separate IDA comparison of
`getProcNames:onDevice:howMany:` (`0x510C`) confirms processor-set enumeration,
PID/process filters, command cleanliness, deduplication, the ten-name cutoff,
and task-list cleanup match the source and `terminal_append_process_name`.
`DirtMonitor.m` passes PPC and i386 syntax checks, and both native ProcessInfo
variants pass.


PPC IDA comparisons of `-[DirtMonitor releaseKnownTask:taskDied:]` (`0x4500`), `-[DirtMonitor uncacheThreads:]` (`0x4728`), `-[DirtMonitor compactFreePortStack]` (`0x54D4`), and `-[DirtMonitor extendFreePortStack]` (`0x5544`) confirm task-list unlinking and free-task caching, thread-right cleanup and port-cache return, free-port-stack compaction, and 32-port stack expansion with allocation-failure alerts. The source matches the task and port cache behavior in all four bodies; the post-push task overflow alert is recorded below. PPC/i386 syntax checks and the Terminal host suite pass; no matching i386 binary is available for behavioral comparison.



PPC IDA comparisons of `-[DirtMonitor registerDevice:withFD:]` (`0x40B4`) and `-[DirtMonitor setShellsClean:runningBackgroundClean:fastAudits:cleanCommands:]` (`0x429C`) confirm device-array growth and initialization, descriptor storage, tracked-task policy refresh, clean/self flag updates, and release of flagged tasks when fast audits are disabled. Source matches. `-[DirtMonitor unregisterDevice:]` (`0x43B4`) matches valid-device alerting, task-chain release, and sentinel reset. Its source adds a nonnegative check before indexing `knownDevices` in the alert condition; PPC evaluates the sentinel operand after only the upper-bound check. This only changes malformed negative-device handling; the source guard is retained to avoid a negative array access.


PPC IDA comparison of `-[DirtMonitor handleMachMessage:]` (`0x5720`) found that the final `fpnStack > numPorts` path raises `Port name free list overflow.` The source had incorrectly grown the stack there; it now presents the recovered alert. The corresponding `-[DirtMonitor releaseKnownTask:taskDied:]` (`0x4500`) post-push task-stack overflow alert is also restored. The normal release and free-port behavior is unchanged. Source-map line references after the insertion were advanced to match the source.



PPC IDA comparisons confirm `-[FieldView initWithFrame:]` (`0x7610`) matches the source's superclass initialization, line-zone/chunk allocations and counts, initial state, copied default colors, and original receiver return. `setUpWithDefaults:` (`0x7910`) matches the frame visibility tests, 160-point clearance, 25-point cascade offsets, defaults application, and window display/order. The drawing cluster also matches: `drawRect:` (`0x1CFC4`) rejects negative-height damage and follows the same clear/cursor/reflect/right-edge sequence; `_srhclear:to:` (`0x1C098`) preserves selection and autowrap cursor gates; `_cursor` (`0x1C828`) preserves the cursor cell, attribute/selection colors, shape geometry, scroll-mode row, and character refresh paths. No source corrections were needed for this cluster.


PPC IDA audit of the shell signal/accounting path confirms `+[Shell handleSignal]` (`0xAD54`) reaps with `wait3(WNOHANG)`, searches active shells backward by PID, sets the matching PID to -1, and invokes its exit action with the shell and wait status. `_handleSIGCHLD` (`0xAE14`) writes one byte to the signal pipe. `+[Shell handleFileActivity:]` (`0xAE5C`) handles pending children, clears the signal mask, and re-arms the default-mode read notification. `-[Shell login]` (`0xB298`) and `logout` (`0xB3D8`) match the 36-byte utmp records, conditional slot writes/closes, wtmp appends, privilege transitions, and tty group/ownership/mode updates. The recovered callback uses the old runtime's two-object forwarding entry point; that ABI detail remains unverified, while the source call sequence and arguments match the decompilation.


PPC IDA rechecks confirm `-[TerminalApp application:openTempFile:]` (`0x13BEC`) forwards the application and filename arguments to `application:openFile:` and returns its result. `-[Preferences windowShouldClose:]` (`0x244A8`) clears the visible flag, conditionally calls `lastVisible:`, and returns YES; `windowWillClose:` (`0x245E0`) sends `setCurrentTerminal:nil`. Each method matches its source implementation.


A PPC IDA audit of Filer exposed three source divergences. `handleFileActivity:` re-armed reads when the notification had no data, `handleOutput:` returned immediately after its EOF callback instead of continuing through the binary's timer path, and `close` nulled the output-timer ivar after release. `init` also had a nil-return path absent from the recovered body. `Filer.m` now follows the recovered notification, callback, timer, and super-init paths. The output buffer, EIO handling, file-handle observer lifecycle, and forwarding methods were compared and match.


PPC IDA audit of FindPanel confirms `doFind:findBackwards:` (`0xA794`) imports only while hidden, reads the ignore-case control, dispatches to the first responder's directional search, orders the panel on a found field-originated search, beeps/localizes misses, exports the find string, and selects the field text. `FieldView find:` (`0x1FEA4`) and `bfind:` (`0x20364`) match forward/backward selection origins, stream traversal, case-folding, match endpoints, selection scrolling, and delegate notification. The recovered methods ignore `openFStream`'s return; the source's extra early return was removed so a subsequent line-load retry follows the PPC path.


PPC IDA recheck of `-[TerminalAgent initDefaults:inFolder:env:]` (`0xFCD8`) confirms the source's window and scroll-view construction, autoresizing/scroller setup, interface-style width adjustment, Terminal initialization with the original defaults/folder/environment, delegate and view wiring, and cleanup order when window allocation or Terminal setup fails. No source correction was needed.


PPC IDA audit of `-[TerminalApp openServicesFile:]` (`0x13E0C`) confirms readable-file and add-confirmation gates, lazy service-set loading, duplicate-name replace/skip/cancel behavior, imported service ownership cleanup, summary reporting, and service-manager refresh. The source matches the recovered import paths; no correction was needed.


PPC IDA re-audit of `-[TerminalApp save:mustPrompt:howMany:inFile:]` (`0x12B34`) confirms responder/type gating, direct filename reuse, lazy save-panel setup, save-mode titles and radio selection, filename-matched single-window scans, Save Set inclusion of other Terminal windows, typed-stream serialization, atomic data writing, auto-open defaults, and menu refresh. The extracted save-mode helpers and native `savepanelmode` regression agree with the recovered `howMany` branches; no new source mismatch was found. Selector names for several framework calls remain unresolved against the available mismatched AppKit metadata.


PPC IDA branch audit of `-[vt100 vt100Escape:]` (`0x18158`) confirms the escape jump-table actions for linefeed/reverse-linefeed, tab setting, G0/G1/CSI/string handler handoff, terminal reset, application keypad mode, identify response, and cursor/attribute save and restore. Single-byte commands clear escape state while multi-byte handlers retain their dispatch state as in `vt100.m`; no source correction was needed.


PPC IDA re-audit of Terminal application-status and window-title behavior confirms `displayAppStatus:`, `resetAppStatus`, `updateAppStatus`, `redisplayTitle:`, `windowHook::`, and `_winTitle` (`0x14D04`–`0x14DBC`, `0xD8B0`–`0xD9C8`, `0xF840`) match source. The status path toggles the on/off images and debounces updates while constructing a 16x16 status icon. The title path preserves dead-terminal text, title-option component ordering, compressed command/file paths, PTY suffix, dimensions, process-name fallback and key-stealer suffix. No correction was indicated.


PPC assembly audit of `-[TerminalApp validateMenuItem:]` (`0x12278`) resolves its tag 23–33 jump table and confirms the source enablement rules, Steal/Yield Keys title and tag transitions, Save/Save Set title update, and default YES path. Hex-Rays emits only the dispatch bounds and default return for this function; case behavior is confirmed from the branch targets.


PPC IDA comparison of `-[TerminalApp setWindowStatus:withScroller:debug:setMember:]` (`0x12544`) confirms four direct byte stores for shell-window, scroller, debug, and set-membership flags. The source writes the corresponding recovered flag fields in argument order; no correction was needed.


PPC IDA caller audit confirms `-[Terminal windowDidBecomeKey:]` (`0xDE20`) sets active-window status from the scroller/debug/shared-file state, configures dead-key processing from the emulator meta character, starts cursor blinking, and restores an invalidated cursor. `windowDidResignKey:` (`0xDD18`) clears all status flags, restores dead-key processing, stops blinking, and conditionally restores the inactive cursor. `debugToggle:` (`0xE06C`) matches the activation, tracking-rectangle and status-update paths in source. No discrepancy was found.

A 2026-10-05 recheck of `-[Terminal windowDidDeminiaturize:]` (`0xE348`)
confirms selector cells `0x3814C`, `0x380C0`, `0x38150`, and `0x38154` resolve
through Terminal's selector-name table to `enablePSOutput`, `setDrawCursOK:`,
`updateDirtIfNeeded`, and `refreshscreen`. Hex-Rays receiver flow confirms the
remaining sends as a three-stage receiver chain ending with argument `1`;
source expresses that chain as `window`, `contentView`, and `setNeedsDisplay:`.
Those final selector pointers resolve outside file-backed image data, so their
names remain source/call-shape inferences rather than independent selector-table
proof. The binary body and source call structure otherwise agree; no edit was
indicated.

PPC IDA review of `-[TerminalApp application:openFile:]` (`0x13C24`) confirms
the nonempty `/tmp/.reallyignorethis.term` early-success case, `.term` dispatch
with unconditional YES, `.svcs` dispatch returning the importer result,
directory launch through `newShell:inFolder:env:`, execute-permission checking
before `newShell:`, and success based on the returned Terminal object. The
source matches these branches. The ledger now records the reviewed flow;
external Foundation selectors remain inferred where their references leave the
file-backed image.

PPC IDA review of `-[TerminalApp _newInstance]` (`0x10250`) confirms the
method's dynamic selector send receives `self` as its explicit argument, then
the method clears instance bytes `0x78` and `0x7A` and returns the original
receiver. `TerminalApp.m` performs the same send, clears the shell-window and
debug fields, and returns `self`. The send's external selector is not
statically recoverable from the Terminal image; the ledger records that limit.

PPC IDA review of `_handleSIGCHLD` (`0xAE14`) confirms the signal handler loads
the second integer at `_kiddiePipe + 4`, calls `write(fd, "X", 1)`, and returns
the write result. `Shell.m` writes the same byte to `signalPipe[1]` and ignores
the result; the signal argument is unused in both. The previously empty ledger
rationale now records this direct instruction-level comparison.

PPC IDA review of `_getDefaultColors` (`0x2B74`) confirms the eight-color
`TextColors` loop reads three float components per entry, creates calibrated
RGB colors, and applies the 2-bit grayscale quantization branch with explicit
release/replacement ownership. IDA also shows the Objective-C exception handler
and cleanup path represented by `NS_DURING`/`NS_HANDLER` in
`TerminalDefaults.m`; the ledger now records those matching behaviors.

PPC IDA review of `-[Terminal setSpringLoadedPaste:]` (`0xF188`) confirms
zone-owned storage: the first value is allocated and copied, while subsequent
values reallocate for the combined length and append with `strcat`. The body
contains no allocation-failure guard, matching `Terminal.m` and the updated
ledger rationale.

PPC IDA review of `-[Terminal pruneNumLinesTo:]` (`0xEB14`) confirms flush
suppression, freeing and compacting line chunks with wrapped flags, clearing
vacated slots, shifting or clearing selection points, updating line count and
topline, requesting redraw and scrollbar reflection, and re-enabling window
flush. `Terminal.m` matches the full sequence; the ledger now records the
review.

PPC IDA review of `-[TerminalApp newShell:inFolder:env:]` (`0x103AC`) confirms
default setup and shell cleanup, zone creation/naming, defaults loading,
optional shell replacement and flags, environment conversion, TerminalAgent
initialization, window delegate/target wiring, agent release, and failure
returns. The custom-shell allocation-failure branch alerts but then falls
through to `strcpy` with the null destination. `TerminalApp.m` previously
returned `nil` there; it now follows the reference control flow. This preserves
a reference failure-path defect for binary fidelity.

PPC IDA review of `-[TerminalApp cleanCommands]` (`0x12930`) confirms old
command frees, `CleanCommands` defaults lookup, zone copy, semicolon token
splitting and per-token allocation. The loop's index-18 path allocates that
token and breaks before incrementing; the terminator loop then clears slot 18,
so only indexes 0–17 remain visible and the just-allocated overflow token is
lost. `TerminalApp.m` now preserves this reference boundary behavior.

PPC IDA review of `-[FieldView _cursor]` (`0x1C828`) confirms the screen-line
and column lookup, selection and character-attribute inputs, cursor flag update,
block/underline/bar/framed cursor geometry, scrollback row mapping, and the
character redraw via `_smark` and `refreshscreen`. The current `FieldView.m`
branches match the recovered visible-screen and scrollback paths.

PPC IDA review of `_wordEnds` (`0x22558`) confirms invalid-column empty ranges,
contiguous space selection, expansion across word characters, punctuation
trimming at token edges, special leading-tilde behavior, and final end-bound
validation. `WordSelection.c` follows those rules; its ASCII class checks agree
with the independently reviewed PPC `_iswordchar` implementation.

PPC IDA review of `-[FieldView _rawclear:to:]` (`0x19F10`) confirms the base
background color and row-range rectangle geometry; `FieldView.m` matches the
`[first,last)` fill.

PPC IDA review of `-[FieldView reflectPosition]` (`0x1D854`) confirms the
scroller is disabled when visible rows equal total rows and enabled otherwise,
with messages sent only on state transitions. Its value and knob proportion
are `topline / (lineCount - visibleRows)` and `visibleRows / lineCount`.
`FieldView.m` matches the same transitions and ratios.

PPC IDA review of `-[ServiceManager setupExecBoxForWindowType:routingFlags:andSetPopUp:]`
(`0x2CEA8`) found the popup tag branch tests `r28`, which carries `windowType`;
`r27` carries `routingFlags`. The previous source passed `routingFlags` to the
popup-tag helper, so a service with `windowType=1` and `routingFlags=4` selected
tag 64 instead of 32. `ServiceManager.m` now passes both values to
`TerminalServiceManagerExecutionPopupTagForWindowType`, which selects from
`windowType`. The regression case for the conflicting values failed to link
before the helper existed and passes now. The remaining mode labels, selection
flags, shell-option behavior, and popup-title fallback match IDA.

PPC IDA review of `-[ServiceManager fillServiceFromWindow:]` (`0x2DA94`)
confirms record sequence and option initialization, control-to-flag reads,
execution/routing flags, zone-owned command copy, `-f` detection and key
fallback. `ServiceManager.m` matches the record bytes and branches.

PPC IDA review of `-[ServiceManager controlTextDidEndEditing:]` (`0x2E7D8`)
confirms service-matrix-only handling, unchanged-name abort, changed-title
commit, independent command copy into the manager zone before cache replacement,
and Return-triggered Change plus suppression of the next matrix action. The
source matches the ownership and event order.

PPC IDA review of `-[ServiceManager setControlsFromService:]` (`0x2CD18`)
confirms flush suppression, controls restored from record flags, execution setup,
conditional shell control restoration, command/key values, flush re-enable and
`displayIfNeeded`. A stored space key is presented as empty text; the source
matches that conversion and the full sequence.

PPC IDA review of `_main` (`0x20F50`) confirms the wrapper launch sequence: when
the bundle path is unreadable, change to the argument directory first and show
the “No Wrapper” alert and exit immediately if `chdir` fails. Only after a
successful directory change does the binary query the process-name path and
check its readability. `TerminalCheckWrapperLaunch` now preserves that
short-circuit ordering, and its host regression verifies that neither callback
runs after a failed directory change. The remaining shared application,
Terminal nib owner-table, launch, event loop, pool release, and exit order also
matches the source. PPC/i386 syntax checks pass for `TerminalMain.m` and the
target-independent launch helper; the full native Terminal host regression
suite passes.

PPC IDA audit resolved previously uncertain selectors in three lifecycle paths.
For `-[Terminal updateDirtIfNeeded]` (`0xE918`), `__sel_backref` row `0x42B98`
maps cell `0x37D00` to `boolForKey:`; the adjacent argument object at `0x36DA8`
contains `MonitorProcs`. Rows `0x45360`, `0x448C0`, `0x43088`, and `0x43838`
resolve the remaining sends to `window`, `setDocumentEdited:`, `dirtMonitor`,
and `isDeviceDirty:`. `Terminal.m` matches the guards, dirty query, update, and
pending-flag clear.

For `-[FieldView scrollTo:]` (`0x1D464`), direct `__sel_backref` decoding maps
`0x37E74` to `lockFocus` (row `0x43B58`), `0x38528` to `_scrollTo:`
(`0x428E8`), `0x37E90` to `unlockFocus` (`0x45198`), and `0x3816C` to
`reflectPosition` (`0x44158`). The former `disablePSOutput`/`enablePSOutput`
pair in `FieldView.m` was a real mismatch. The new source-order regression
failed before the correction and passes now. PPC and i386 syntax checks pass.

The final receiver chain in `-[Terminal windowDidDeminiaturize:]` (`0xE348`)
is also selector-table-confirmed: `window` at `0x37C94` (row `0x45360`),
`contentView` at `0x37DDC` (`0x42E40`), and `setNeedsDisplay:` at `0x37F10`
(`0x44AA0`). This supersedes the earlier note that treated those three names as
call-shape inferences; `Terminal.m` matches all seven sends and the YES argument.

PPC IDA selector-table review of `-[FieldView setDelegate:]` (`0x9228`) found a
second source mismatch. Cell `0x37DC0` resolves through `__sel_backref` row
`0x42B58` to `autorelease`; cell `0x37CF0` resolves through row `0x44390` to
`retain`. The body conditionally autoreleases the old delegate, stores the new
pointer, then retains it. `FieldView.m` now matches; the ownership regression
failed with the previous `release` call and passes after correction. PPC/i386
syntax checks pass, and IDA inspection of the generated i386 object confirms
the same message sequence.

PPC IDA resolved `-[FieldView windowDidBecomeMain:]` (`0x91D4`) and exposed a
third source mismatch in the reviewed window/font paths. The selector cell
`0x37EDC` maps through `__sel_backref` row `0x43C88` to `new`; cell `0x37EE0`
maps through row `0x44B70` to `setSelectedFont:isMultiple:`. IDA passes the
FieldView font ivar at offset `0xC8` and integer zero. `FieldView.m` now sends
`[[NSFontPanel new] setSelectedFont:font isMultiple:NO]`, matching the PPC
sequence. The new regression failed against `sharedFontPanel`/`setPanelFont:`
and passes after correction. PPC/i386 syntax checks pass; IDA confirms the
fresh i386 object emits the same calls.

PPC IDA review of `-[MutableEvent setChars:]` (`0x193F0`) maps selector cell
`0x37CC8` through `__sel_backref` row `0x441E8` to `release`, and cell
`0x37CF0` through row `0x44390` to `retain`. The method stores the retained
input and clears the cached character byte. A regression failed against the
former `copy` send and passes with the recovered ownership sequence.

PPC IDA review of `-[Emulation key:]` (`0x5924`) found a source mask mismatch
in the non-alternate function-key branch. Instructions `0x5A1C`–`0x5A24` load
`eflags` at object offset `0xC`, rotate left three bits, and mask the second
least significant bit, returning 2 when `eflags & 0x40000000` is nonzero.
`Emulation.m` previously tested `0x20000000`; it now tests `0x40000000`. The
new regression failed before the fix and passes after. PPC/i386 source syntax
checks pass.


PPC IDA review of `-[Emulation output:len:]` (`0x5E30`) confirms the body
enters a `length != 0` loop without first checking the terminal or input
pointer: `mr. r26, r6` at `0x5E4C` loads/tests the length and `beq` at `0x5E50`
exits for zero length, then the first input byte is read at `0x5E54`. The
source's `term == nil || bytes == 0` early return was extra behavior and has
been removed. The focused regression failed before the change and passes after;
PPC/i386 syntax checks pass.

PPC IDA review of `_main` (`0x20F50`) also corrected the resource startup path.
After creating `TerminalApp`, the reference asks the bundle for `WindowTop.tiff`
and only constructs the `NSOwner` table and calls `loadNibFile:` when that
resource exists. It then sends `finishLaunching`, `run`, releases the pool, and
exits. `TerminalMain.m` now matches the conditional `WindowTop.tiff` load and
does not add a separate `finishLaunching` call. The regression checks the
resource name, conditional load, and send sequence; it passes. PPC and i386
syntax checks pass, and a fresh i386 Mach-O object inspected in IDA reproduces
the conditional resource-load branch and startup calls. No i386 reference
binary or linked application/runtime verification is available.

PPC IDA review of `_environmentDataFromDictionary` (`0x1538C`) and
`_environmentFrom` (`0x15534`) confirms the serialized environment format and
pointer-vector reconstruction implemented in `TerminalDO.m`. A fresh i386
`TerminalDO.m` Mach-O object decompiles to the same double-NUL scan, zone
allocation, and per-entry key/value append flow. The two target syntax checks
and i386 object compile pass. The three convenience-method implementations now
carry the protocol's `inout` window-handle and `out` return-code qualifiers;
this removed Clang's distributed-object modifier conflict warnings. No i386
Terminal reference binary or target-runtime test is available.

PPC `__sel_backref` review of `-[Preferences init]` (`0x23558`) resolves the
previously unknown initializer sends. Cells `0x37D14`, `0x37F7C`, `0x37F80`,
`0x37F84`, `0x37F88`, `0x37C8C`, and `0x37F8C` decode to `init`, `class`,
`bundleForClass:`, `pathForResource:ofType:`, `dictionaryWithObjectsAndKeys:`,
`zone`, and `loadNibFile:externalNameTable:withZone:`. Cell `0x3867C` resolves
to `setCurrentTerminal:` and `0x382A8` to `reflectChoiceOfPane:`. The source
had called `setUpButtons:0` at the former callsite; it now sends
`setCurrentTerminal:nil`, matching PPC. The regression failed before the edit
and passes after it. The refreshed i386 `Preferences.m` object
(SHA-256 `E9E428C3B83A9D6113E27435BA6F1AD9FE01B6EF11221CE8203C705E2BFAB432`)
was inspected in IDA and emits the corrected initializer call sequence.

For `-[Preferences setUpButtons:]` (`0x23DE4`), PPC `__sel_backref` resolves
cells `0x37E04`, `0x38664`, `0x37DDC`, `0x37DE0`, `0x37E5C`, and `0x37E10` to
`setEnabled:`, `superview`, `contentView`, `addSubview:`, `display`, and
`removeFromSuperview`. The source's button state masks, attach/remove branches,
and redraw order match these sends.

The current-source native binrecon run completed with IDA 9.4 against the
pinned PPC executable (333,472 bytes, SHA-256
`B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7`). Its
793-function analysis validates against the checked-in source map: 640 mapped,
153 classified runtime/import entries, and zero boundary disputes. The ledger
also validates with 640 control-flow-confirmed and 153 signature-confirmed
entries. Binrecon marks normalized-function acceptance false because no
rebuilt executable is configured in this PPC reference-only profile.
