# i386 verification status

No matching Terminal i386 reference was found in the searched application
tree. The supplied executable is PowerPC. The repository has an i386 compiler
profile, but no linked Terminal i386 executable or runtime result exists yet.
Treat i386 work as a separate native build/portability check; do not claim
reference parity until a release-matched i386 oracle is identified.

The 2026-10-05 FieldPrint source now mirrors the PPC-confirmed direct `FieldView`
ivar reads for print sizing and selection. `FieldPrint.m` passes the native
i386-target syntax check; this establishes source portability, not independent
i386 behavioral parity.

On 2026-10-05, all 54 production translation units emitted separate i386 Mach-O
objects with LLVM's `i386-apple-darwin` target and the fragile 10.4 Objective-C
runtime. This verifies object generation for the shared sources, not linking,
bundle construction, or runtime behavior. Objects are in the host temporary
directory `rhapsodios-terminal-i386-objects` and are not reconstruction inputs.

The latest native Terminal selector tests pass all 16 cases, and the Terminal
host test suite exits successfully. Saved target syntax logs cover the current
55-file manifest for PPC and i386. No matching i386 Terminal reference or
reachable Rhapsody guest is available, so independent i386 binary parity,
linking, and runtime behavior remain unverified.

`ProcessInfo.c` passes LLVM Clang i386 GNU C89 syntax checks against the recovered System
headers. GNU mode is needed for the SDK inline assembly; syntax acceptance does not
substitute for an i386 Terminal reference binary or runtime test.

The shared `ProcessIdentity.c`, `TerminalMain.m`, and updated `Shell.m` also
pass i386 Clang syntax checks against the recovered framework headers. This
checks source portability only; the supplied executable is PPC and there is no
matching i386 reference for parity analysis.
The new `TerminalApp` state accessors pass i386 syntax checks. Their shared
byte-field layout is not verified against an i386 reference.
The `prefManager`, `serviceProvider`, and printing-state methods also pass i386
syntax checks; their layout remains unverified without an i386 Terminal image.

The TerminalApp dirtMonitor implementation also passes i386 syntax checking. Its ivar layout and behavior are still only confirmed against the PPC binary.


On 2026-10-05, all 54 production translation units emitted separate i386 Mach-O objects with LLVM's `i386-apple-darwin` target and the fragile 10.4 Objective-C runtime. This verifies object generation for the shared sources, not linking, bundle construction, or runtime behavior. The supplied Administration bundle contains only a PPC Terminal executable; a recursive search of the supplied test tree found no i386 Terminal reference. i386 binary parity therefore remains unverified.

The TerminalApp cleanCommands implementation passes i386 syntax checking. Layout and runtime parity still require an i386 reference and target runtime.

The TerminalApp save: and saveAs: wrappers pass i386 syntax checking; their forwarding contracts are confirmed against PPC only.

The application:openTempFile: wrapper passes i386 syntax checking; its forwarding contract is confirmed against PPC only.

TerminalApp's declared instance layout now reflects the PPC UDT offsets and passes i386 syntax checking. There is still no i386 reference to confirm layout parity. displayAppStatus: and resetAppStatus also pass i386 syntax checks; behavior is PPC-confirmed.

The showServiceManager: method passes i386 syntax checking; behavior and object layout are confirmed only against PPC.

The newCommand: method passes i386 syntax checking; behavior is confirmed against PPC.

The new: action passes i386 syntax checking; its forwarding behavior is confirmed against PPC.

The TerminalApp shell method passes i386 syntax checking; its behavior is confirmed against PPC only.

DOServicesOK passes i386 syntax checking; its behavior is confirmed against PPC only.

applicationDidBecomeActive: passes i386 syntax checking; its behavior is confirmed against PPC only.

TerminalDO protocolVersion passes i386 syntax checking; its value is confirmed against the PPC image.

TerminalDO convenience RPC wrappers and its environment conversion helpers pass i386-target Objective-C syntax checking. Only the PPC reference executable is available, so i386 machine-code parity is not established.

TerminalApp runCommand:usingShell:inFolder:windowTitle:closeOnExit: passes i386-target syntax checking. The matching reference remains PPC only.

TerminalAgent, Terminal, TerminalApp, and TerminalDefaults pass i386-target syntax checking, including the defaults search-list setup and dirt-timer path. This confirms the shared source compiles for i386; machine-code parity remains unverified because the supplied Terminal executable is PPC-only.

`Terminal keyDown:` now also passes i386-target syntax checking. Its behavior is recovered from the PPC image; no matching i386 Terminal binary is available for parity verification.

`Terminal paste:` passes i386-target syntax checking. Its behavior is recovered from the PPC image; no matching i386 Terminal binary is available for parity verification.

`Terminal setFrameSize:` passes i386-target syntax checking. Its behavior is recovered from the PPC image; no matching i386 Terminal binary is available for parity verification.

`TerminalDO.m` and the new NIB-backed `ServiceProvider.m` also pass i386-target Objective-C syntax checks. The full command service path and factory branches are reconstructed from the PPC image; no matching i386 Terminal executable is available for binary comparison.

`ServiceProvider windowWillResize:toSize:` also passes i386-target syntax checking. Its NSSize instance fields preserve the 32-bit layout; behavior and the 220-byte body are confirmed against PPC only.

`ServiceProvider pasteboard:containsType:` passes i386 syntax checking; its type-list traversal and comparison are confirmed against the PPC body.

`ServiceProvider copyString:` and `replace:with:in:` pass i386 syntax checking. Their allocation and string-operation control flow is confirmed against the PPC executable; no i386 reference binary is available.

`ServiceProvider ensureNibLoaded` passes i386 syntax checking; the resource lookup, NSOwner table, conditional load, and window-size capture are confirmed against the PPC body.

`ServiceProvider ok:` and `cancel:` pass i386 syntax checking; the `NSApp showPanel` sends, 0/1 action arguments, and returned application object are confirmed against PPC only.

`ServiceProvider provideService:userData:error:` passes i386 syntax checking. Its service-set header and 28-byte record layout are explicitly fixed to the recovered 32-bit ABI; behavior is confirmed against the PPC executable only.

`ServiceProvider doService:pasteboard:isDrag:dragTerm:errBuff:` is control-flow-confirmed against the full PPC body and passes i386 target syntax checking with the recovered i386 layouts. Its i386 code generation and runtime behavior remain unverified because no matching i386 Terminal executable is available.
# Services ABI

`TerminalServices.h` and `tests/serviceabi.m` pass Clang syntax checks for
`i386-apple-rhapsody`, including 28-byte service-record, 8-byte service-set,
and 36-byte `ServiceCache` layout assertions. The declarations are based on
the PPC reference's 32-bit UDT; no i386 Terminal binary is available for
independent layout confirmation.

`vt100.m` passes Clang syntax checks for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody`, including the exact unsigned-byte lower-margin comparison used by `linefeed` and `wrapoutput`. Runtime and binary parity remain unverified for i386 because no matching Terminal executable is available.

`ServiceProvider doService:pasteboard:isDrag:dragTerm:errBuff:` is now control-flow-confirmed against the full PPC body and passes i386 target syntax checking with the recovered i386 layouts. Its i386 code generation and runtime behavior remain unverified because no matching i386 Terminal executable is available.

The ServiceManager NIB outlet declarations and 120-byte instance layout pass i386 target syntax checks. Twenty-six methods (`cellCountFor:`, `serviceSelected:`, `execTypeChanged:`, `freeService:`, `controlTextDidEndEditing:`, `saveService:`, `isDirty`, `setDirty:`, `updateForCurrentDirtiness`, `makeDirty:`, `windowWillResize:toSize:`, `controlTextDidChange:`, `windowDidResize:`, `nameUnique:`, `control:textShouldEndEditing:`, `setFlags:fromControlsIn:`, `setFlagsFromCell:`, `whyAreSettingsNotAcceptable`, `setControlsIn:fromFlags:`, `fillServiceFromWindow:`, `setControlsFromService:`, `setupExecBoxForWindowType:routingFlags:andSetPopUp:`, `polymorphicOptsChanged:`, `checkSettings`, `warnAboutStrangeness:`, and `renewForServiceSet:`) are reconstructed from PPC control flow and compile for i386; this architecture has no reference Terminal binary for independent parity checks.

-[ServiceManager setupExecBoxForWindowType:routingFlags:andSetPopUp:] passes i386 target syntax checking. Its control behavior is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

-[ServiceManager polymorphicOptsChanged:] passes i386 target syntax checking. Its behavior is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

-[ServiceManager checkSettings] passes i386 target syntax checking. Its behavior is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

-[ServiceManager warnAboutStrangeness:] passes i386 target syntax checking. Its control flow is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

-[ServiceManager renewForServiceSet:] passes i386 target syntax checking. Its control flow is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

The restored _pathCompress entry and three-argument signature pass i386 target syntax checking. Behavior is confirmed against the PPC reference; no matching i386 Terminal executable is available for independent comparison.

`FieldView changeFont:` now has a PPC-backed source reconstruction and a corresponding PPC source-map entry. The i386 target syntax check passes with the recovered System `bsd` and `objc` include roots; no i386 reference binary is available for parity.

`FieldView windowWillResize:toSize:` passes i386 syntax checking. Its behavior is confirmed against PPC; no i386 Terminal reference is available for parity.
`FontTrap`'s reconstructed `changeFont:` and `resignFirstResponder` methods pass i386 target syntax checking. The strict 5?128 point bounds and callbacks are confirmed against the PPC IDA reference; no matching i386 Terminal executable is available for independent comparison.

`WindowController.m`, including the current `setRows:...`, `displayRows:...`, `revert`, and defaults-action edits, passes LLVM Clang syntax checking for `i386-apple-rhapsody` against the recovered DR2 SDK. The provisional font-selector concern is resolved against the i386 AppKit slice: IDA confirms `NSFont screenFont`, `NSFontManager selectedFont` and `fontPanel:`, plus the text-field, font-name/size, font-panel, and calibrated-color selectors used by `WindowController` and `FontTrap`. The PPC Terminal remains the behavioral reference; no matching i386 Terminal executable is available for independent comparison.

`TerminalApp openLibraryTerm:` now constructs the selected `.term` path under `libraryDir` and returns `openFile:`'s result, matching the PPC body. The updated `TerminalApp.m` passes i386 target syntax checking. No matching i386 Terminal executable is available for independent binary comparison.

The shared `printLine` helper in `PrintLine.c` passes the i386 Rhapsody-target syntax check. Its stdout-capture regression test passes on the host; behavior is confirmed against the PPC binary because there is no matching i386 Terminal executable.

The shared `findCharacters` helper in `FindCharacters.c` passes the i386 Rhapsody-target syntax check. Its search/clamping tests pass on the host; behavior is confirmed against the PPC binary because there is no matching i386 Terminal executable.

`-[FieldView findMatchingDelimiter:::delimChars:backwards:]` passes FieldView.m syntax parsing with the i386 macro and 32-bit host ABI. Its control flow is confirmed against PPC; an i386 Terminal reference is unavailable for binary comparison.

`-[FieldView _shiftClick::]` passes FieldView.m syntax parsing with the i386 macro and 32-bit host ABI. Its behavior is confirmed against PPC; an i386 Terminal reference is unavailable.

The 2026-10-05 PPC `__sel_backref` review corrected the shared
`-[FieldView clearScrollback:]` source to send `lockFocus`, `_clearSelection`,
the recovered window/redraw messages, then `display`, `reflectPosition`, and
`unlockFocus`. The earlier source-inferred `becomeFirstResponder` and unresolved
selector claims are superseded. The shared `FieldView.m` passes i386 syntax
checking, which establishes portability only because no matching i386 Terminal
binary is available for independent comparison.

A recursive search of `C:\Users\raynorpat\Downloads` found only
`Applications_ppc\Administration\Terminal.app\Terminal`; no independent
i386 Terminal oracle is present in the available Downloads artifacts.

`-[FieldView _dragEnd::]` and `-[FieldView _tripleClick::]` pass i386-macro syntax parsing with the 32-bit host ABI. Their control flow is reconstructed from the PPC reference; a matching i386 Terminal binary is unavailable for independent comparison.

`-[FieldView _dragEnd::]` and `-[FieldView _tripleClick::]` pass i386-macro syntax parsing with the 32-bit host ABI. Their control flow is reconstructed from the PPC reference; a matching i386 Terminal binary is unavailable for independent comparison.
The shared `_appendLines` and `_splitLine` reconstructions in `Chunk.c` pass i386-macro syntax checking. Their control flow is verified against the PPC reference, and host storage regressions cover append-chain adjustment/merge and recursive line splitting; no i386 Terminal binary is available for independent comparison.

`ProcessMonitorController.m` passes syntax checks for PPC and i386 using the recovered DR2 headers. Its ten implemented methods are matched to the PPC IDA reference, including two no-op overrides; no i386 Terminal binary is available for binary comparison.

`MiscController.m` passes i386-target Objective-C syntax checking against the recovered DR2 headers. Its shared implementation and 14 method bodies were reconstructed from the PPC Terminal binary; no matching i386 reference executable is available for machine-code comparison.

`TextAttributeController.m` passes i386-target syntax checking using the shared 32-bit source and PPC-recovered interface. A matching i386 Terminal reference binary is unavailable for independent comparison.

`TitleBarController.m` passes i386-target syntax checking using the shared 32-bit implementation. Fourteen methods are control-flow-confirmed against PPC; preview drawing and action-cell details remain unexamined. A matching i386 reference binary is unavailable for independent comparison.

`-[TerminalApp open:]` passes i386-target Objective-C syntax checking. Its behavior is recovered from the PPC reference; no matching i386 Terminal executable is available for independent comparison.

`TerminalApp openFile:` passes i386-target Objective-C syntax checking as shared source. Its behavior is reconstructed from the PPC reference; no matching i386 Terminal executable is available for binary parity checks.

`TerminalApp application:openFile:` passes i386-target Objective-C syntax checking as shared source. Its behavior is reconstructed from the PPC reference; no matching i386 Terminal executable is available for binary parity checks.

`TerminalApp openServicesFile:` passes i386-target Objective-C syntax checking as shared source. Its behavior is reconstructed from the PPC IDA reference; no matching i386 Terminal executable is available for independent behavioral or binary-parity comparison.

`ServiceManager init` passes i386-target Objective-C syntax checking as shared source. Behavior is reconstructed from PPC IDA; no matching i386 Terminal executable is available for independent comparison.

`ServiceManager go:` passes i386-target Objective-C syntax checking as shared source. Its control flow is reconstructed from PPC IDA; no matching i386 Terminal executable is available for independent comparison.

`ServiceManager remove:` passes i386-target Objective-C syntax checking as shared source. Its behavior is reconstructed from PPC IDA; no matching i386 Terminal executable is available for independent comparison.

`TerminalApp.m` passes direct PPC and i386 Rhapsody-target syntax checks with the recovered DR2 SDK headers and `-Werror=incomplete-implementation`. The reconstructed save path is shared with PPC; syntax acceptance does not establish i386 binary parity or runtime archive behavior, and no matching i386 Terminal reference binary has been found.

`TerminalApp.m` now implements the shared save-panel and typed-stream save path. It passes PPC and i386 Rhapsody-target syntax checks with `-Werror=incomplete-implementation`. Save archive round-trip and i386 binary parity remain unverified.

`TerminalApp quickTitle:` passes PPC and i386 target syntax checks as shared source. Function behavior is reconstructed from the PPC IDA body; i386 binary parity and runtime behavior remain unverified because no matching i386 Terminal reference is available.

On 2026-10-05, Clang emitted a fresh i386 Mach-O object for `Chunk.c`
(`terminal-chunk-i386-copy.o`, SHA-256
`DDF0196DCC559AE103859E69D5BC5D5D6E4812BCF07517C0A8ADFCE7791E44F6`). IDA
9.4 decompilation of its `ChunkCopy` matches the shared source's growth
condition, `+0x90` source/destination offsets, count-times-element-size copy (rendered by IDA as `memmove`),
and absence of a destination-count store. The shared source issues `bcopy` on Mach targets; Clang/IDA represent the generated operation as `memmove`. This verifies the generated i386
object follows the PPC-recovered source; it is not an i386 reference match.

On 2026-10-05, Clang 22 emitted `ServiceCache.m` as an i386 Mach-O object
(SHA-256 `1F4B00DF63B794BDF6EAE032B2797D5FE8AA57A6774B105F3CDE57CB0AFF4A67`).
IDA 9.4 decompilation of `readService:fromFile:zone:`,
`writeService:toFile:`, `convertString:toPrintable:`, and
`convertPrintable:toString:` matches the shared source's record fields,
three-line format, zone-owned string/command allocation, escaped backslash and
three-digit byte decoding, and `%3u` formatting of nonprintable bytes. This is
source-generated i386 code evidence only; the supplied Terminal reference
executable is PPC, so it does not establish i386 binary parity.

`TerminalServices.h` now asserts every `ServiceCache` ivar offset, including
`initialized`, `mapFile`, `cacheFile`, `saveOK`, `needsSave`, and
`offeredExamples`. After removing a duplicate assertion, `ServiceCache.m` and
`tests/serviceabi.m` pass PPC and i386 Rhapsody-target syntax checks. The full
Terminal host regression suite also passes. These checks protect the shared
32-bit layouts; they do not provide an i386 reference comparison.

On 2026-10-05, `TerminalApp.m` passed Clang syntax checks for the PPC and i386
Rhapsody triples after the save-path receiver was aligned with PPC IDA. A
separate `i386-apple-darwin` Mach-O object was emitted and decompiled in IDA;
its `-[TerminalApp save:mustPrompt:howMany:inFile:]` begins with `NSApp`,
`keyWindow`, and `delegate`, matching the shared source. The object is preserved
in ignored D: output at
`tools/binrecon/out/terminal-ppc/generated/i386-evidence-20261005/terminalapp-save-i386-20261005.o`
(SHA-256
`AAB1E8E5F89DA7575FC8EA8E0FAFFE23DAF3A22E84C5EA85CF5EF121A0AE716E`). This
verifies source code generation, not parity with an i386 Terminal reference,
which remains unavailable.
The `FieldView.m` change that adds `becomeFirstResponder` before
`_clearSelection` passes PPC and i386 target syntax checks. A fresh
`i386-apple-darwin` Mach-O object for `FieldView.m` was decompiled in IDA; its
`clearScrollback:` begins with `becomeFirstResponder` and `_clearSelection`,
matching the shared source. The object is preserved in ignored D: output at
`tools/binrecon/out/terminal-ppc/generated/i386-evidence-20261005/fieldview-clearscrollback-i386-20261005.o`
(SHA-256
`E16AB6B0E732762FF806C4BB55FE50ECEC42135AAAE38336553D62C29D47973B`). This
confirms source lowering only; no matching i386 Terminal binary is available
for parity.

Correction (2026-10-05): those `FieldView.m` object results describe an earlier
shared-source version and are superseded by the PPC selector-table recovery.
The current source sends `lockFocus` and the recovered redraw/focus-release
sequence. A fresh i386 object was compiled and opened in IDA; its
`clearScrollback:` selector references decode in order to `lockFocus`,
`_clearSelection`, `window`, `disableFlushWindow`, `scrollTo:`, `contentView`,
`setNeedsDisplay:`, `enableFlushWindow`, `display`, `reflectPosition`, and
`unlockFocus`. The object hash is
`DA9333B2D8F8EDB82FCAA4F643D98C2B542194C6A7CF79A4B986ABE8A9EE4F7D` under
ignored `tools/binrecon/out/terminal-ppc/generated/i386-evidence-20261005/`.
This confirms current-source i386 code generation, not independent i386
Terminal binary parity.

On 2026-10-05, the shared `FindCharacters.c` emitted an i386 Mach-O object
(`fstream-parity-20261005.o`, SHA-256
`18242395FE70CEF524E2BDC7DCAEF58088E83E4780E3FE9018F5E075A52CD97D`). IDA
decompilation confirms `openFStream`, `nextGetChar`, `prevGetChar`, `peekChar`,
and `getPosition` retain the PPC-recovered initialized-stream precondition and
line-boundary behavior. This is source-generated i386 evidence, not comparison
against a matching i386 Terminal executable.

On 2026-10-05, `DirtMonitor.m` passed PPC and i386 Rhapsody-target syntax
checks after `_taskIsBlocked` was aligned with the PPC signed-byte behavior. A
fresh i386 Mach-O object (`dirtmonitor-taskblocked-20261005.o`, SHA-256
`F7406C652FBB865EEC5F676F21A7166399A850DCC187D722EAA77F660B83794A`) was
decompiled in IDA; its `taskIsBlocked` uses a signed `threadIndex` comparison
and passes `4 * TerminalTaskThreadCount(task)` to `vm_deallocate`, matching the
shared source and PPC behavior. This validates source code generation only;
there is no matching i386 Terminal image for independent parity.



A fresh full-manifest compile emitted 55 i386 Mach-O objects with LLVM Clang 22 for the current `MFILES` list; per-object sizes and SHA-256 values are recorded in the ignored `tools/binrecon/out/terminal-ppc/generated/i386-manifest-20261005/manifest.json`. IDA decompilation of the current `TerminalApp.m.o` recovered 64 functions, including `-[TerminalApp save:mustPrompt:howMany:inFile:]` (3516 bytes). Its save-panel selection, shared-window/archive traversal, startup-default update, and write-failure alert paths match the PPC-reviewed source flow. The object hash is `6BF6973F19F200522212669E11D015F62DCB11671181B33A037DC4E2EC7983B6`. This is current-source i386 code-generation evidence, not independent binary parity or a linked application.

On 2026-10-05, a fresh `MFILES` compile emitted 55 Mach-O objects using `i386-apple-darwin`; all object headers carry 32-bit Mach-O magic. IDA identifies `TerminalApp.m.o` as `metapc` and recovers 64 functions, including `-[TerminalApp openFile:]` (0x53F0), `-[TerminalApp application:openFile:]` (0x5BE0), and save handling. In `openFile:`, the emitted body checks read access, reports open/read failures, unarchives defaults, creates a TerminalAgent, restores the saved window position, and wires the window delegate/target. `TerminalApp.m.o` SHA-256 is `08F25E3167B45B624DDE820452EC1040A961C5CAD0B7E2EB2F4AFF8A44DF0CF4`. This is current-source i386 object/decompilation evidence only; the supplied executable is PPC, so it provides no independent i386 parity proof or linked app validation.

IDA also reviewed the fresh full-manifest `DirtMonitor.m.o` (SHA-256 `43376DCB054E70FBDA23C4D7CFE4F285CBBF382C0246D78492D4B909CFF23649`). Its `_taskIsBlocked` body uses the signed cached thread count for the loop bound and `vm_deallocate` byte count; `releaseKnownTask:taskDied:` unlinks the task, uncaches its threads, and returns it to the free-task stack; `uncacheThreads:` deallocates cached ports, recycles eligible port names, and clears the cached-thread flag/count. These recovered i386 bodies agree with the shared source and the PPC-reviewed behavior. In this object the functions are 581, 392, and 345 bytes respectively; the sizes are compiler output, not expected to equal PPC. This remains source-generated i386 evidence only.

After correcting both the PTY slave mode and terminal flag mask, a fresh i386 Mach-O `Shell.m` object (`Shell-lflag-80400224.m.o`, SHA-256 `4EAAC677D44F5C1578C02EAE7C70E09E800F9395099DD404D600AFA87DA47808`) was decompiled in IDA. `-[Shell system:login:folder:env:]` emits `0x190` at `_fchmod` and masks `c_lflag` with `0x80400224` before OR-ing `0x5CB`, matching PPC IDA and `Shell.m`. Both PPC and i386 Rhapsody target syntax checks pass; this is source-generated i386 evidence, not an i386 reference comparison.

A fresh i386 Mach-O object built from the current `Shell.m` (`Shell-defaultModes.m.o`, SHA-256 `9E1231D77EA6E4F68B689D1B4665EE2CC13B0ABDC310F0D8111EE0D7CFF89B64`) was decompiled in IDA. It retains mode `0x190`, the `0x80400224` `c_lflag` mask, and loads exported `defaultModes` into the four-byte failed-`TIOCGWINSZ` fallback. PPC and i386 Rhapsody syntax checks pass; this remains source-generated i386 evidence, not independent binary parity.


The universal DR2 AppKit framework was split at its recorded i386 fat-slice bounds and the i386 slice was analyzed in IDA (`AppKit-i386`, SHA-256 `AC97B39BFE16630A767705E95A91B73F72E871572BED50E2E77FF91A162CCB82`). Selector strings and implementations include `-[NSFont screenFont]`, `-[NSFont fontName]`, `-[NSFont pointSize]`, `-[NSFontManager selectedFont]`, and `-[NSFontManager fontPanel:]`; exact strings also exist for `sharedFontManager`, `convertFont:`, `setTextColor:`, `selectText:`, `setInitialFirstResponder:`, `makeKeyAndOrderFront:`, `setStringValue:`, `widths`, and `widthOfString:`. This removes the prior external-selector mismatch concern for the reconstructed font callbacks; it does not substitute for an i386 Terminal oracle.

After aligning the Preferences-window selection in
`-[TerminalApp applicationShouldTerminate:]`, the current `TerminalApp.m` was
recompiled as i386 Mach-O and decompiled in IDA. The object
`terminalapp-quit-pref-last-i386.o` has SHA-256
`5100E2ED6B3E39D2E4289DA01243670D66BD61D8B1BD3D373B8D7C4769A05B67`; its
method at `0x3F90` overwrites the saved Preferences window for every matching
delegate, emitting the PPC-derived last-match behavior. This checks current
shared-source code generation only; independent i386 Terminal parity remains
unverified.
The shared-source i386 object `shellcontroller-showdefault-i386.o` (SHA-256
`DA1DAB4A3AE0D31B395A5D63D5219E4490C527DE153732FD6868FC092EBF8D38`)
decompiles to the same `showDefault:` behavior: synchronize defaults, read
`NSApp`'s shell, read the `SourceDotLogin` Boolean, and apply both values through
`setShell:source:`. The incoming `show` byte is unused. This verifies current
i386 code generation from shared source; it is not independent i386 Terminal
reference-binary evidence.

`ServiceManager save:` was control-flow-audited against the PPC IDA body; its shared implementation's syntax acceptance is covered by the current manifest-wide PPC and i386 checks recorded in `build-environment.md`. The supplied reference is PPC only, so i386 binary parity and runtime behavior remain unverified.

`ServiceManager fillServiceFromWindow:`, `setFlags:fromControlsIn:`, and `setFlagsFromCell:` are control-flow-confirmed against PPC IDA. Their shared source passes the recorded PPC/i386 manifest syntax checks; i386 binary behavior remains unverified without a matching reference.

`ServiceManager change:`, `warnAboutStrangeness:`, and `checkSettings` are control-flow-confirmed against PPC IDA. Their shared source passes the manifest-wide PPC/i386 syntax checks recorded in `build-environment.md`; no matching i386 Terminal binary exists for independent behavior comparison.

`TerminalApp openServicesFile:` is control-flow-confirmed against PPC IDA, with its `ServiceCache readService:` and `addNewTermService:` contracts traced in the same database. The shared importer source passes the previously recorded PPC/i386 manifest syntax checks; the supplied reference is PPC only, so i386 behavior remains unverified.

`ServiceCache writeServices:`, `writeService:toFile:`, `convertString:toPrintable:`, and `convertPrintable:toString:` are control-flow-confirmed against PPC IDA. The shared serialization source passes the recorded PPC/i386 translation-unit syntax checks; binary-format parity for i386 remains unverified without a matching image.

`ServiceCache checkFile:forNaughtyModes:` is control-flow-confirmed against PPC IDA. Its shared source is included in the recorded PPC/i386 syntax checks; i386 binary behavior remains unverified without a corresponding reference.

`ServiceCache loadServiceSet` is control-flow-confirmed against the PPC IDA body, including descriptor close paths, record allocation/growth, parser termination, and failure cleanup. The shared source has recorded PPC/i386 manifest syntax coverage; only PPC has an executable reference.

`ServiceCache saveService:inSlot:`, `importService:from:`, `addNewTermService:`, and `removeServiceAt:` are control-flow-confirmed against PPC IDA, including record ownership and resize operations. The shared implementation has recorded PPC/i386 syntax coverage; independent i386 binary parity is unavailable.

`ServiceCache init`, `setOKToSave:`, and `serviceSetChanged` are control-flow-confirmed against PPC IDA. Shared source syntax coverage for both targets is recorded in `build-environment.md`; no i386 reference executable is available.

`ServiceCache updateServicesFile` is control-flow-confirmed against PPC IDA, including exported Services dictionary fields, atomic write, timestamp/security gates, and failure transitions. Shared source syntax checks for PPC/i386 are recorded; i386 has no executable reference for independent parity verification.

All six `TerminalDO` methods are now control-flow-confirmed against PPC IDA, including the primary RPC's process and output paths. The shared file's recorded PPC/i386 syntax checks establish source portability only; no i386 Terminal binary is available for behavioral parity.

`ServiceManager execTypeChanged:` now uses the PPC-confirmed setup argument mapping and has a host regression. `ServiceManager.m` passes Clang syntax checks for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody` with the recovered headers. No i386 Terminal reference is available for independent behavior comparison.
`ServiceManager setDirty:`, `updateForCurrentDirtiness`, `control:textShouldEndEditing:`, and `controlTextDidEndEditing:` are control-flow-confirmed against the PPC reference. The rename callback now preserves command ownership across `ServiceCache saveService:inSlot:` by copying the original command into the manager zone before replacement; the focused regression and full host suite pass. Shared `ServiceManager.m` syntax checks pass for PPC and i386. No matching i386 Terminal binary is available, so i386 behavioral parity remains unverified.

`ServiceManager cellCountFor:`, `renewForServiceSet:`, `isDirty`, and `editSelectedServiceName:` also match the PPC control flow. Both-architecture source syntax checks pass; independent i386 reference-binary behavior is unavailable.

`ServiceCache readService:fromFile:zone:` matches the PPC record parser and zone ownership paths. This confirms shared source only; no i386 reference binary is available.

`ServiceManager setControlsFromService:`, `setControlsIn:fromFlags:`, and `makeDirty:` match PPC control flow. Both-architecture syntax validation covers the shared implementation; i386 binary parity is unavailable.
The shared ServiceCache cleanup/accessor hooks and ServiceProvider prompt helpers match the PPC reference. i386 has shared-source compile coverage but no independent Terminal executable for behavior comparison.

`ServiceProvider provideService:userData:error:` now converts the exported decimal `NSUserData` through `intValue`, matching the PPC service-key lookup. The shared implementation is checked for i386 syntax; behavior parity cannot be independently confirmed without an i386 reference.
The focused provider change (`NSUserData` decimal string conversion with `intValue`) passes the i386 syntax check and the complete Terminal host suite. This establishes shared-source compile coverage, not i386 runtime behavior.
`ServiceManager freeService:`, `whyAreSettingsNotAcceptable`, `nameUnique:`, `windowDidResize:`, `windowWillResize:toSize:`, and `controlTextDidChange:` match PPC flow. The shared implementation has both-target syntax coverage; i386 reference behavior remains unavailable.

`ServiceManager serviceSelected:`, `add:`, `windowShouldClose:`, and `saveService:` also match PPC control flow. Shared source syntax is checked for both targets; no i386 reference binary is available.

`CommandPanel showPanel`, `commandEntered:`, and `control:textView:doCommandBySelector:` match PPC control flow. This is shared-source evidence only for i386.

`Terminal setUpWithDefaults:inFolder:env:` matches the PPC startup branches in shared source; the PPC byte-field mask interpretation is architecture-specific, and i386 has no reference binary for independent parity.

The shared Terminal lifecycle/accessor source now matches the audited PPC bodies for filename/defaults access, delayed-perform cancellation, invalidation, deallocation with deferred zone recycling, and emulator assignment. No matching i386 Terminal reference executable is available for independent comparison.

The subsequent Terminal output, process-exit, resize, key, paste, title, and timer-handler range was control-flow-compared with PPC IDA and matches the shared source. This comparison confirms the PPC-derived implementation only; i386 Terminal binary parity remains unavailable.

PPC review also confirms the shared cursor blink, main/key-window, debug tracking, and miniaturize/deminiaturize callbacks. No independent i386 Terminal binary exists to compare these paths.

The PPC review now also covers close confirmation and zone teardown, dirt-state updates, extra window info, drag-and-drop, spring-loaded paste, color drops, mini-window status animation, and dirt timer callbacks. Shared source matches the PPC behavior; independent i386 binary parity remains unavailable.

`TerminalApp setupDefaults` has also been compared with the PPC body and its shared defaults-zone, user fallback, failure cleanup, persistent-domain, and search-list behavior match. There is no independent i386 reference binary.

The PPC launch review also confirms the shared `applicationWillFinishLaunching:`, `applicationDidFinishLaunching:`, and new-shell convenience/creation methods. These are shared-source portability checks for i386; no independent i386 Terminal image is available.

The saved-terminal archive restore and application file-open routing now have PPC control-flow comparisons against the shared implementation. i386 remains source-portable only because no corresponding reference executable is available.


On 2026-10-05, `DirtMonitor.m` compiled to an i386 Mach-O object with LLVM Clang 22 and the recovered DR2/System BSD headers (SHA-256 `07674D2E9AC14987EB19B66CD8A16D3F80EFEB973584DB743BD3E1548B7C454E`). IDA decompilation of generated `-[DirtMonitor releaseKnownTask:taskDied:]` and `-[DirtMonitor handleMachMessage:]` confirms the restored post-push `Free task list overflow.` and `Port name free list overflow.` alerts are emitted for i386 too. This validates source code generation only; no matching i386 Terminal reference is available for independent parity.


On 2026-10-05, the corrected `Filer.m` compiled to an i386 Mach-O object with LLVM Clang 22 and the recovered DR2/System BSD headers (SHA-256 `F70DD4592EA99F0DADFEF6D676A43A015693F1DB9CF315AC583BDFFE419EB34D`). IDA decompilation of the generated object confirms the nonnil-data rearm guard, the EOF callback followed by timer handling, and the timer ivar remaining unchanged in `close`; these generated i386 paths agree with the PPC reference after the source corrections. This is source-generated evidence, not an independent i386 reference comparison.

The wrapper launch guard now short-circuits when `chdir` fails before querying
the process-name path, matching the reviewed PPC entry flow. `TerminalMain.m`
and the target-independent launch helper pass i386 syntax checks, and the
launch-order regression passes on the host. No independent i386 Terminal
reference is available for behavioral comparison.

On 2026-10-05, `TerminalMain.m` compiled to an i386 Mach-O object with LLVM
Clang 22 and the recovered DR2 headers (SHA-256
`52F10561EE97A67D61E0FA29C91606A46C6AF7EFB7A851FD8B6590DD72629F99`). IDA
decompilation confirms generated i386 control flow checks bundle readability,
then calls `TerminalCheckWrapperLaunch`, exits on its false result, and only
then proceeds to `TerminalApp` creation, nib loading, and the event loop. The
helper's `chdir`-before-process-name order is covered by the host regression.
This is generated-source evidence; no independent i386 Terminal reference is
available for comparison.

The i386 Mach-O object for `TerminalLaunch.c` (SHA-256
`C3BC31B400877F0495F06B9CF6C36CC56C4DC9CE87FB5FC8491AC2CA2DFB8F2A`) was also
inspected in IDA. Generated `TerminalCheckWrapperLaunch` returns false directly
when its directory callback returns `-1`; otherwise it invokes the process-name
callback and then checks that path with mode 4. This confirms i386 code
-generation order, not parity against an unavailable i386 Terminal binary.

On 2026-10-05, the corrected `FieldView.m` compiled to an i386 Mach-O object
with LLVM Clang 22 (SHA-256
`40A1797AC251F99976A9C8E8E8E9796DB9997608C590381439CE137573508555`). IDA
decompilation of `-[FieldView scrollTo:]` shows generated i386 sends in order:
`lockFocus`, `_scrollTo:`, `unlockFocus`, `reflectPosition`. The same object
shows `-[FieldView setDelegate:]` conditionally sends `autorelease`, stores the
new delegate, then sends `retain`. This confirms generated i386 code; no
independent i386 Terminal image is available for behavioral comparison.

The i386 Mach-O object for the latest `FieldView.m` source (SHA-256
`A1BD205B61A9DDB4D73FADB7A267752A2CCCBE6CACCBC38098B92EFDE7B26B18`) was
inspected in IDA. Generated `-[FieldView windowDidBecomeMain:]` sends `new` to
`NSFontPanel`, then `setSelectedFont:isMultiple:` with the recovered font ivar
and zero. This validates the i386 source code generation; no separate i386
Terminal reference is available for behavioral comparison.

The i386 Mach-O object for the latest `MutableEvent.m` source (SHA-256
`15D4CA7FF428D6D524612D7E2413C727D5A36CB5667B11BB5E15D5C222E9E6CA`) was
inspected in IDA. Generated `-[MutableEvent setChars:]` releases the prior
string, retains and stores the replacement, then clears the cache byte. This
validates generated i386 code only; no separate i386 Terminal reference is
available.

The i386 Mach-O object for the corrected `Emulation.m` source (SHA-256
`850B0BA2F0CFCF4AFD97D939D78466C1ACC7AA214F840B8C87F79DCC60E87D84`) was
inspected in IDA. `-[Emulation key:]` tests `self->eflags & 0x40000000` in
the non-alternate function-key branch and returns 2 when set. This confirms
i386 code generation only; the supplied Terminal reference is PPC.


The fresh i386 Mach-O object for `Emulation.m` without the extra output guard
(SHA-256 `029F56426CBED4401BDF9C2B9E2817A346FC1F1AACEE835D4FACFAED1DF3B545`)
was inspected in IDA. Generated `-[Emulation output:len:]` begins with the
length-controlled loop and no terminal or input-pointer preflight. This is
generated i386 code evidence; the independent behavioral reference is PPC.

The refreshed `TerminalDO.m` i386 Mach-O object (SHA-256
`BAC240946813B31C6410C61DB268C7B542E58593B7972B19F6806A1D1FC0C3E5`) was
inspected in IDA. `environmentFrom` preserves the PPC double-NUL scan and
zone-allocated pointer vector; `environmentDataFromDictionary` appends encoded
keys and values with `=` separators and double-NUL termination. The three
convenience methods also compile with the protocol's `inout`/`out` qualifiers,
removing their conflicting distributed-object modifier warnings. This is
generated i386 code evidence; no independent i386 reference binary exists.

The refreshed `Preferences.m` i386 Mach-O object (SHA-256
`E9E428C3B83A9D6113E27435BA6F1AD9FE01B6EF11221CE8203C705E2BFAB432`) was
inspected in IDA after correcting `-[Preferences init]` to send
`setCurrentTerminal:nil`. Its generated initializer preserves the PPC-derived
delegate assignments, clears `installedPane`, and reflects pane zero. PPC
`__sel_backref` supplies the independent selector evidence; no i386 reference
binary is available.

On 2026-10-05, all 56 current `MFILES` translation units passed Clang syntax
checks for `i386-apple-rhapsody`. The same 56-unit manifest passed the PPC
target syntax check. This confirms source compatibility for the two requested
architectures; the i386 result is not an independent reference-binary
comparison, and neither target was linked into a Rhapsody application.
