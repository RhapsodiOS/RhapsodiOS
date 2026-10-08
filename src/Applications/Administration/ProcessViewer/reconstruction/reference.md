# ProcessViewer PowerPC reference

## Identity

Source bundle: `C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\ProcessViewer.app`.

Executable: thin big-endian PowerPC Mach-O `MH_EXECUTE`, size 70852 bytes,
SHA-256 `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`.
The supplied bundle remains the behavioral authority. The bounded search of
`C:\Users\raynorpat\Downloads` found no other ProcessViewer executable or app
bundle, so no i386 binary comparison oracle is presently available.

## Executable inventory

The binrecon Mach-O reader reports 208 symbol table entries, 78 symbol-named
Objective-C methods, and 21736 bytes in `__TEXT,__text`. IDA 9.4 currently finds
128 executable function records across application, startup, and import-stub
code. Source names embedded in
the binary are `Inspector.m`, `Process.m`, `ProcessControl.m`, `ProcessType.m`,
`ProcessTableView.m`, and `UserIdCache.m`.

Application classes evident from symbol and NIB data include `Inspector`,
`MapTableEnumerator`, `Process`, `ProcessControl`, `ProcessType`,
`ProcessTableView`, and `ProcessTableHeaderView`, plus `Process(Private)`.
All 78 symbol-named Objective-C methods have now been matched to their class or
category method records by implementation address and raw method type encoding.
The metadata helper directly resolves selector strings for only 46
implementations; the other names reconcile by IMP address, so this discrepancy
did not require a Mach-O parser change. Class and ivar details are recorded in
`abi.md`. The function inventory explicitly separates application symbols from
runtime startup and imported stubs in `function-worklist.md`.

## Bundle resources

The original bundle's 12 resource files are inventoried by path and SHA-256 in
`resources.sha256`. Preserve that hierarchy and byte content during initial
reconstruction. `Info-nextstep.plist` selects `NSApplication` and
`ProcessViewer.nib`; the main NIB names `ProcessControl`, `ProcessTableView`,
`Inspector`, and `ProcessTableHeaderView`. The inspector NIB supplies its own
outlets and archived view structure. Consult the original archives when
recovering action ownership and responder-chain behavior.

`BuiltIn.processType` defines All Processes, User Processes, Administrator
Processes, and NetBoot Processes. `English.lproj` contains process-type strings,
general localized UI strings, credits, both NIBs, and the Apple menu image.

## Dependencies and cross architecture

Mach-O dependency strings name AppKit Versions/C, Foundation Versions/C, and
System Versions/B. Process-related symbols and strings include `/bin/ps`,
`_sysctl`, `_table`, `_getpwuid`, and `_kill`; recover signatures, invocation,
data formats, and error behavior from the program before implementing them.

Only the PowerPC reference has been located. Build shared historical
Objective-C/C source for ppc and i386, validate each target against its actual
compiler, ABI, process APIs, and guest runtime, and do not claim i386 instruction
parity in the absence of an i386 reference.
