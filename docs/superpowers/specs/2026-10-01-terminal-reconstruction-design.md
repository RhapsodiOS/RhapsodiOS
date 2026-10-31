# Terminal reconstruction for PowerPC and i386

## Approved intent

Reconstruct the supplied Terminal application as maintainable historical
Objective-C and C source in `src/Applications/Administration/Terminal`.
Both 32-bit PowerPC and i386 are required build and runtime targets. The user
selected full binary-backed reconstruction, accounting for every recovered
function and original feature, and approved this design direction.

This specification defines the reconstruction scope and acceptance criteria.
It does not claim that implementation or runtime verification has occurred.
The detailed implementation plan follows review of this written specification.

## Measured reference and supporting evidence

Primary bundle:
`C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\Terminal.app`.

| Property | Observed value |
| --- | --- |
| Executable | `Terminal` |
| Architecture | 32-bit big-endian PowerPC Mach-O |
| File size | 333472 bytes |
| SHA-256 | `B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7` |
| `__TEXT,__text` size | 191288 bytes |
| Symbol-table entries | 972 |
| Objective-C method addresses returned by binrecon | 441 distinct addresses |

These counts come from the current binrecon Mach-O reader and Objective-C
method index. The method-address count is not a complete function inventory;
aliases, categories, unnamed C helpers, startup code, and analyzer boundary
claims must be reconciled before defining the coverage denominator.

The bundle contains seven NIBs: Terminal, CommandPanel, Find, Preferences,
PrintAccessory, ServicePrompt, and Services. It also contains localized strings,
service definitions, images, credits, and Project Builder bundle metadata.
The metadata advertises `.term` and `.svcs` documents and references external
Terminal help. Inventory that dependency without claiming the help is bundled.

The bundled `Headers/TerminalDOProtocol.h` is only an import of the missing
original `/SourceCache/terminal/terminal-100/TerminalDOProtocol.h`. However,
`C:\Users\raynorpat\Downloads\test\Applications_ppc\Developer\Headers\Apps\TerminalDOProtocol.h`
contains actual `TSTerminalDOServices` declarations and window, shell, and exit
action enums. Use this supporting header after checking its signatures and
constants against executable metadata and behavior.

No separate i386 Terminal executable was found by filename search of the
supplied test tree. Do not assume that other media contain a matching release.
If an i386 reference is subsequently found, hash and identify it and establish
release differences before using it as a direct parity oracle.

## Approach and alternatives

Use shared, evidence-driven source with architecture-specific code only where
the reference or measured ABI requires it. Preserve classes, categories,
selectors, ownership rules, document formats, resource connections, and error
behavior. Follow the repository's historical runtime and build conventions;
do not introduce modern Cocoa APIs or redesign Terminal's UI or feature set.

A working-shell-first replacement would postpone substantial original behavior
and is not the selected completion standard. Instruction-level identity may be
pursued where useful for verification, but exact image reproduction is not a
requirement and must not override maintainable, faithful source.

## Source and evidence organization

Proposed layout, with implementation filenames finalized from recovered module
ownership rather than assumed from class names:

```
src/Applications/Administration/Terminal/
  *.m, *.c, *.h
  PB.project
  Makefile, Makefile.preamble, Makefile.postamble
  Resources/
  tests/
  reconstruction/
    reference.md
    architecture.md
    function-worklist.md
    resource-inventory.md
    ppc/
    i386/
tools/binrecon/profiles/terminal-ppc.json
tools/binrecon/profiles/terminal-i386.json
```

Version source, build descriptions, compact inventories, source maps, reviewed
coverage records, and verification instructions. Keep reference/rebuilt
executables, analyzer databases, bulk disassembly, and generated analyses out
of Git, using the existing ignored binrecon output directory. Inventory and
hash original resources before deciding which to preserve in the source bundle
and which need reconstruction; copied assets retain their provenance.

## Reconstruction groups and data flow

Recover the exact boundaries from metadata and disassembly. Initial observed
classes support the following work groups:

1. Application and windows: `TerminalApp`, `Terminal`, `TerminalAgent`, and
   command panels; startup, window creation, titles, scheduling, and termination.
2. Process and I/O: `Shell`, `Filer`, and `DirtMonitor`; PTY allocation, child
   startup, login bookkeeping, signals, reads/writes, process status, and cleanup.
3. Emulation and display: `Emulation`, `FieldView`, and its drawing, emulation,
   and mouse/scroll categories; parsing, screen storage, cursor state, fonts,
   keyboard translation, selection, scrolling, and rendering.
4. User state: preferences, search, `.term` persistence, library entries, and
   window/session defaults, including original encoding and migration behavior
   where present in the binary.
5. Integration: printing, Services, service editing/prompting, and `TerminalDO`;
   recover all distributed-object methods and their input/output semantics.

Trace input from keyboard or distributed-object requests through Terminal and
Shell/Filer to the child, and output from file activity through emulation and
screen updates to drawing. Trace preferences, persistence, and Services into
that flow. Preserve observed ordering, delayed work, notifications, timers,
partial I/O handling, EOF behavior, exit status propagation, and teardown.
Do not infer missing behavior solely from NIB class listings, which may contain
stale editor metadata; verify the instantiated object graph and binary methods.

## Binrecon workflow

The current reader accepts `MH_EXECUTE` and parses this reference successfully.
Start by validating a dedicated PowerPC profile and running IDA through the
existing runner. Ghidra and angr are currently i386-only and must remain disabled
for PowerPC. No cross-analyzer consensus claim is justified by an IDA-only run.

Resolve all function boundaries, aliases, indirect dispatch, jump tables,
Objective-C methods, and non-method helpers. Separate application-owned code
from imported functions, linker stubs, and runtime/compiler support, recording
the reason for every exclusion. Map each owned function to source and keep a
reviewed ledger; disassembly controls when pseudocode or metadata disagree.

For each reconstruction group, recover interfaces and state first, reconstruct
behavior, build, inspect binary differences, and perform relevant behavioral
checks before advancing its reviewed status. Verify imports, selectors,
constants, data accesses, calls, and control flow. Source-map completeness,
successful compilation, and analyzer agreement alone are not behavioral parity.

Use an i386 profile for available i386 artifacts with supported analyzers.
Do not configure a PowerPC binary as an i386 reference or treat cross-CPU
instruction comparison as a meaningful parity result. Without a matching i386
reference, retain explicit portability and runtime results instead of fabricated
reference/rebuilt comparisons. Add direct i386 comparisons when a suitable
reference becomes available.

## Both-architecture build contract

Recover the original framework/library dependencies and resource installation
layout, then integrate with historical Project Builder makefiles and the
repository build conventions. Both architectures must build the complete app.
Keep CPU selection explicit and prevent stale artifacts from one build entering
the other. Confirm the actual available compiler, SDK, framework, and guest
combinations before recording build commands in the implementation plan.

Audit byte order, signed characters, integer widths, bitfields, alignment,
Objective-C ivar layout, calling conventions, serialized data, terminal ioctl
structures, signal interfaces, Mach/process APIs, and any recovered assembly.
Use portable source where behavior is shared. Document required ABI differences
without treating ordinary cross-architecture instruction differences as defects.

Framework or guest limitations are dependencies to report precisely. Do not
silently replace unavailable APIs or expand this project into framework-wide
reconstruction. If a prerequisite blocks a required test, that validation remains
incomplete until the dependency is resolved.

## Verification and acceptance

Use focused host-side tests for recoverable pure logic and reference-derived
fixtures, plus native guest integration tests for platform behavior. Avoid tests
that merely restate implementation choices. Record the origin and expected
observations for every reference-derived fixture.

Required scenarios on both architectures include:

- Startup, multiple windows, commands, shell/login modes, environment, directory,
  child exit, close policies, process status, and application termination.
- PTY input/output, partial writes, EOF, signal handling, resize propagation,
  burst output, and resource cleanup after both normal and failing operations.
- Every recovered emulation mode and escape family, including sequences split
  across input chunks, cursor motion, wrapping, scrolling, erasure, attributes,
  and malformed/incomplete input behavior demonstrated by the reference.
- Fonts, redraw, keyboard modifiers, selection, clipboard, search, scrollback,
  window titles, preferences, document save/load, and library entries.
- Printing ranges/attributes, service files and prompts, and distributed-object
  requests with input/output/error data, synchronous/asynchronous behavior,
  window handles, exit actions, and return codes.

Use temporary disk images for guest testing so concurrent sessions remain
isolated. Capture reproducible observations and relevant visual evidence for
reference and rebuilt runs. Compare PowerPC against the supplied reference;
exercise the same behavior fixtures on i386, separating architectural differences
from unexplained discrepancies.

Completion requires a reconciled complete function inventory, source mappings
for every owned function, implementation of all recovered original features,
successful builds and required runtime checks on both architectures, and reviewed
evidence for parity claims. Document discrepancies and unresolved evidence;
stubs, unexplained omissions, or unavailable mandatory runtime tests prevent a
claim of full completion. Lack of an i386 reference limits direct binary-parity
claims but does not remove the i386 build/runtime requirement.

## Implementation-plan stages

The subsequent plan should give concrete files, commands, dependencies, and
verification checkpoints for:

1. Reference/resource inventory and build-environment discovery.
2. Profiles, full analysis, function partition, and ABI/interface recovery.
3. Historical project setup and faithful resource wiring.
4. Process/I/O and emulation reconstruction with focused behavior fixtures.
5. Display, application state, documents, and remaining integrations.
6. Incremental PowerPC comparisons and i386 portability verification.
7. Full native acceptance, coverage audit, and final discrepancy review.

Both architectures participate throughout implementation rather than leaving
i386 portability until the end. This stage produces planning documents only;
implementation begins after the plan review and execution-method selection.
