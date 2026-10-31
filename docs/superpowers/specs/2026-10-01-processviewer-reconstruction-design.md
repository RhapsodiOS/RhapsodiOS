# ProcessViewer reconstruction for PowerPC and i386

## Intent and scope

Reconstruct the supplied ProcessViewer application as maintainable historical
Objective-C and C source in `src/Applications/Administration/ProcessViewer`.
Both 32-bit PowerPC and i386 are required targets, as explicitly selected by the
user. Preserve original behavior, classes, selectors, resource connections, and
application packaging. This document is a proposed design for review, not a
claim that implementation or decompilation is complete.

Use the supplied PowerPC executable as the behavioral authority. Build shared
source for both CPUs, isolating architecture-specific layout or API handling only
when supported by evidence. Preserve manual memory management and historical
Foundation/AppKit APIs. Do not modernize the UI or add functionality.

## Measured reference

Bundle:
`C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\ProcessViewer.app`.

Executable: `ProcessViewer`, a thin big-endian PowerPC Mach-O MH_EXECUTE.

| Property | Value |
| --- | --- |
| Size | 70852 bytes |
| SHA-256 | `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179` |
| `__TEXT,__text` size | 21736 bytes |
| Symbol-table entries | 208 |
| Named Objective-C methods in symbol table | 78 |
| Original source filenames in binary | `Inspector.m`, `Process.m`, `ProcessControl.m`, `ProcessType.m`, `ProcessTableView.m`, `UserIdCache.m` |

Imports identify AppKit Versions/C, Foundation Versions/C, and System Versions/B.
Process-related evidence includes `/bin/ps`, `_sysctl`, `_table`, `_kill`, and
`_getpwuid`. Recover the exact purpose, arguments, formats, and error paths of
these dependencies from code; these names alone do not specify an implementation.

The bundle includes main and inspector NIBs, their class descriptions, ascending
and descending images, the application icon, an Apple menu image, English strings,
credits, `BuiltIn.processType`, and `Info-nextstep.plist`. The latter names
`NSApplication` as principal class and `ProcessViewer.nib` as main NIB.

Seven application class names appear in the symbol evidence: `Inspector`,
`MapTableEnumerator`, `Process`, `ProcessControl`, `ProcessType`,
`ProcessTableView`, and `ProcessTableHeaderView`, plus the `Process(Private)`
category. Confirm ownership and superclass/ivar layouts through metadata.

The current binrecon Mach-O reader accepts the executable. Its Objective-C
metadata index returns fewer entries than the 78 symbol-named methods, so that
index alone must not define reconstruction coverage. Reconcile metadata, symbols,
and IDA discovery, retaining shared implementations and aliases explicitly.

No i386 reference has been established. Search available local reference media
before reconstruction, record any version differences, and keep this search
bounded. Absence of an i386 oracle does not justify inventing one or delaying
independent PowerPC evidence work.

## Approach and alternatives

Recommended: reconstruct shared source from binary evidence, preserving original
resource files and translation-unit ownership. Maintain architecture-specific
build records and parity evidence around that shared implementation.

A behavior-only rewrite would be simpler but could silently change private state,
NIB contracts, formatting, timing, and error handling. Requiring byte-identical
output would provide stronger code-generation evidence but depends on recovering
the original compiler/linker environment. Use exact matches when attainable;
acceptance requires reviewed structural and behavioral parity rather than an
unconditional whole-image match.

## Source organization and behavior

Planned layout beneath the requested source directory:

```
Inspector.m / Inspector.h
Process.m / Process.h
ProcessControl.m / ProcessControl.h
ProcessType.m / ProcessType.h
ProcessTableView.m / ProcessTableView.h
UserIdCache.m / UserIdCache.h
Makefile / Makefile.preamble / Makefile.postamble / PB.project
Resources/ (original bundle resource hierarchy)
tests/
reconstruction/
  reference.md / abi.md / dependencies.md / function-worklist.md
  build-environment.md / validation.md
  ppc/ / i386/
```

Header names are proposed organization, not recovered original header filenames.
Place `MapTableEnumerator`, `ProcessTableHeaderView`, the private category, C
helpers, globals, and `_main` according to module and call evidence. Do not invent
an extra original translation unit. Known C helpers include
`_floatFromNumberWithSuffix`, `_sortFunction`, `__readTypesFromFile`, and
`_NameForUID`; distinguish these from compiler/runtime startup support.

Recover the process model and UID cache first: enumeration, refresh, identity,
arguments, terminal and ownership information, field representations, sorting,
notifications, invalidation, and memory ownership. Then reconstruct process-type
loading and matching, table/header behavior, controller actions, and inspector
selection and visibility behavior.

The intended flow follows the original app: startup loads resources and restores
observed defaults; refresh obtains process data; process-type and text filters
select rows; sorting orders them; table selection updates the inspector. User
actions change refresh settings, sort/filter state and visible columns, export or
print the list, or request process termination. Exact ordering, persistence keys,
formats, confirmation semantics, signal values, and failure behavior come from
the reference rather than modern conventions or NIB action names alone.

Preserve existing NIB archives byte-for-byte initially. Validate outlets, actions,
class names, and selector signatures against the actual archives. Audit all NIB
actions, including inherited/responder-chain actions, without assuming every
listed action requires an application-owned method. Preserve localized content
and process-type matching rules. Determine resource installation layout using
the repository's historical Project Builder makefiles.

## Binrecon workflow and evidence

Create `tools/binrecon/profiles/processviewer-ppc.json` pinned to the measured
reference. Use the existing Python 3.12 environment and installed IDA 9.4;
Ghidra and angr remain disabled for PowerPC because current adapters reject it.
Start reference-only, then add the rebuilt artifact for comparison. Check actual
tool versions rather than installing tools to match old README examples.

Hash the complete reference bundle, analyze every executable section, and build
a reviewed inventory that separates application-owned code, imported stubs,
startup/runtime code, aliases, and unresolved boundaries. Record original address,
symbol/selector, signature, source owner, callers, evidence, and unresolved issues
for every owned function. Recover Objective-C encodings and ivar offsets before
implementing the corresponding methods. Decompiler output is evidence to review
against instructions, not source to accept blindly.

Keep raw binary inputs, analyzer databases, and large generated outputs outside
Git or under ignored `tools/binrecon/out/processviewer-ppc`. Check in compact
reviewed records, source maps, and ledgers alongside the reconstruction. Never
claim that source-map coverage or an automatically successful analysis proves
semantic parity. Inspect missing/extra selector reports explicitly: the current
selector checker does not fail solely for missing or extra methods.

If a compatible i386 reference is found, create a separate pinned
`processviewer-i386.json` and ledger. Verify its release and behavioral delta
before treating it as an oracle. Otherwise document i386 build, ABI, and behavior
validation against the shared recovered contracts; do not configure a PowerPC
image as an i386 reference or claim same-architecture binary parity.

## Build and validation

Use historical Project Builder application conventions, with separate build
outputs for `RC_ARCHS=ppc` and `RC_ARCHS=i386`. Confirm actual compiler, SDK,
framework, makefile, and guest paths before committing runnable build commands.
Probe `sysctl`, `table`, process structures, `/bin/ps` output, and resource loading
on both targets. Document byte-order, size/alignment, and API differences that
need source changes. Do not expand this app reconstruction into framework or
kernel reconstruction, toolchain installation, or global OS-image integration.

Test recovered pure behavior with deterministic fixtures: process field parsing,
numeric suffix conversion, UID lookup/cache behavior, process-type matching,
sorting in both directions, filtering, and export formatting. Establish expected
results from reference observations or reviewed instructions before asserting
them. Include reference-observed error paths, empty lists, unknown users, exited
processes during refresh/inspection, and malformed or partial process data.

Compare reference and rebuilt runtime observations in separate processes so
Objective-C class names and globals cannot collide. Live process lists change:
use controlled child processes and stable observations, and explicitly account
for time-dependent values without masking behavioral differences. Verify NIB
loading, table columns, refresh settings, zero/single/multiple selections,
inspector visibility, export, printing, preferences, and quit/cleanup behavior.
Exercise termination confirmation, cancellation, permission errors, and process
exit races using controlled child processes only.

Use disposable guest disk images/overlays for runtime tests; preserve shared
guests and their installed applications. Missing build or GUI prerequisites block
the affected verification claim, not independent reconstruction work.

Completion requires builds for both CPUs, full reviewed application-owned
function coverage, compatible Objective-C/NIB contracts, preserved resources,
and no unexplained structural or behavioral discrepancies. Report compilation,
static parity, deterministic tests, and guest GUI validation separately for each
architecture. Any unavailable validation remains explicitly incomplete.

## Milestones and review boundary

1. Establish reference identity, resource contracts, complete function inventory,
   architecture dependencies, and binrecon profile.
2. Establish dual-architecture build/test scaffolding and recovered declarations.
3. Reconstruct process data handling, UID cache, and process-type behavior.
4. Reconstruct table classes, controller actions, inspector, and application entry.
5. Close source/ABI/structural parity gaps and validate both architecture builds
   and guest behavior.

After review of this written design, expand these milestones into the detailed
implementation plan with exact files, commands, task dependencies, and checks.
No application source or binrecon tooling is changed by this design document.
