# Portable AppKit reconstruction

Date: 2026-09-29

## Intent and agreed scope

Reconstruct the supplied AppKit framework as readable Objective-C and C source
under `src/Kits/AppKit`, targeting the historical PowerPC and i386 environments
of RhapsodiOS. The supplied PowerPC release is the behavior reference. An older
DR2 framework provides architecture comparisons, not permission to substitute
older behavior. The user selected portable reconstruction and approved this
staged design in conversation.

This document defines the overall program and the first stage's boundaries.
Detailed implementation planning follows review of this written specification.
Later subsystem stages receive their own scoped plans as dependencies become
known. The present request is for planning; it does not start reconstruction.

Success means compatible interfaces and demonstrated behavior, with separate
build and runtime evidence for each architecture. Exact original source recovery
and byte-identical compiler output are not acceptance requirements.

## Inspected baseline

The reference directory is:

`C:/Users/raynorpat/Downloads/test/Frameworks/AppKit.framework/Versions/C`

| Property | Observed value |
| --- | --- |
| Primary binary | `AppKit` |
| Size | 5,268,704 bytes |
| SHA-256 | `6897A7FA932BA92CFE92A4A1AF36DB9300D63C1DCC81EB66CEBA5963710A9240` |
| Format | 32-bit, big-endian PowerPC Mach-O dylib |
| Code section | `__TEXT,__text`, 3,039,956 bytes |
| Objective-C module records | 296 |
| Declared install name | `/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit` |
| Declared framework dependencies | Foundation version C; System version B |
| Existing source directory | 124 headers and 103 `.m` files |
| Header comparison | All 124 headers byte-identical to reference headers |

The module records retain filenames, including `NSFramework_AppKit.m`,
`NSActionCell.m`, `NSAffineTransform.m`, and private modules such as
`NSButtonImageSource.m`. Module records are attribution evidence; their count is
not a count of fully recovered implementations or necessarily unique filenames.
The sampled `NSApplication.m` contains only an import and stub comments.
Inventory every implementation before replacing anything; the sample does not
establish that every file is empty.

The adjacent `AppKit_profile` is 6,014,264 bytes, with SHA-256
`E1479FF523429774AB755FADE564AA4B53F941CA442E826604A4B95D231D5049`.
It retains 296 module records and has a larger code section. Keep it as a
secondary reference; establish whether it offers useful extra evidence before
investing in separate analysis.

The secondary binary is
`C:/Users/raynorpat/Downloads/test/DR2/Frameworks/AppKit.framework/Versions/C/AppKit`.
Its fat container has these inspected slices:

| Architecture | CPU type/subtype | Offset | Size |
| --- | --- | --- | --- |
| i386 | 7 / 3 | 8,192 | 4,764,136 |
| PowerPC | 18 / 0 | 4,775,936 | 5,239,976 |

Hash the container and extracted slices before using them in reconstruction.

The current `tools/binrecon/binrecon/macho.py` accepts selected thin Mach-O file
types but rejects `MH_DYLIB`; its architecture selection does not handle a fat
container. The framework and Objective-C ABI tooling described in the previous
Foundation plan is not present in the inspected code. Treat that document as
design input rather than completed infrastructure.

AppKit already has Project Builder build files. `PB.project` specifies deployment
version B, conflicting with the supplied version C. The build integration stage
must reconcile project metadata, generated build settings, and install names.

## Approach

Use staged, binary-grounded reconstruction. Whole-framework decompilation would
provide broad pseudocode coverage but postpone integration and create a large
review backlog. A public-API-only implementation would prioritize usability but
provide weaker fidelity for private behavior and serialization. Neither meets
the agreed priorities as well as small, verified reconstruction groups.

For each group, use this evidence flow:

1. Identify the exact reference and architecture.
2. Extract metadata, method entry points, symbols, constants, and dependencies.
3. Examine scoped disassembly and decompiler output.
4. Record the inferred behavior and remaining uncertainty.
5. Implement readable source using the existing headers and historical idioms.
6. Compile, check the applicable ABI, and run focused behavioral comparisons.
7. Update the coverage ledger before declaring the group complete.

Disassembly resolves ambiguous or misleading pseudocode. Selector names and
public signatures alone do not establish implementation behavior. Preserve
observed memory ownership, initialization, exceptions, notifications, ordering,
and archive formats where applicable.

## Source and evidence boundaries

- Keep reconstructed production source in `src/Kits/AppKit`.
- Preserve the 124 matching public headers. Any proposed public-header change
  must identify a concrete incompatibility and receive a design revision.
- Recover private classes, categories, functions, and translation units as
  needed; do not constrain implementation to the existing 103 `.m` filenames.
- Keep private declarations internal rather than expanding public headers.
- Extend shared analysis infrastructure under `tools/binrecon`, avoiding an
  AppKit-specific duplicate parser.
- Keep reference binaries, extracted slices, analyzer databases, and bulk
  pseudocode outside version control, following binrecon conventions.
- Version profiles, compact inventories, coverage records, verification
  instructions, and written findings. Tie evidence to hashes and tool versions.
- Preserve unrelated repository changes and existing useful source.

## Stage 1: establish the contract and prove the pipeline

This is the first implementation plan's scope. It must not expand into a whole
framework rewrite or a Foundation reconstruction.

### Reference and source inventory

Record primary and secondary identities, exported and imported symbols,
Objective-C classes and superclasses, categories, protocols, selectors, method
type encodings, ivars and offsets, instance sizes, module ownership, and relevant
resource files. Distinguish declarations from executable method implementations.
Inventory existing implementations and build files before changing them.

Compare the supplied release with DR2 at the metadata level. Separate release
changes from architecture differences by comparing DR2's PowerPC and i386 slices
with each other first. Where a feature exists only in the supplied release,
derive its i386 implementation from that behavior and the target ABI; do not
claim older i386 code verifies the newer feature.

### Tooling

Add bounds-checked dylib and fat-slice handling, preserving identity of both the
container and selected slice. Add historical Objective-C metadata extraction,
ABI reporting/comparison, and module-scoped analysis as needed after checking
current capabilities. Metadata parsing must respect endianness, virtual-address
mapping, pointer width, and malformed or out-of-range references.

Use recovered method addresses to generate disjoint scopes; do not assume all
code from a module occupies one continuous address range. Attribute plain C
helpers separately using symbols and call references, recording uncertainty.

Use IDA for PowerPC analysis through the existing integration. Current binrecon
Ghidra and angr adapters are documented as i386-only; expanding those adapters
is outside this stage. Establish actual analyzer availability before depending
on any decompiler output.

Test parser changes with synthetic little- and big-endian fixtures, malformed
input cases, and existing reader regression tests. Real framework inventory is
an integration check, not a replacement for parser tests.

### Build and runtime feasibility

Probe the available PowerPC and i386 compiler and guest environments. Record
toolchain versions, commands, headers, linked dependencies, produced architecture,
and errors. Older repository notes describe PowerPC build limitations; verify
current capability rather than treating those notes as a permanent constraint.

Determine the Foundation and Objective-C runtime facilities needed for the pilot.
Original system dependencies may serve as an isolated validation baseline where
available; passing against them does not prove integration with reconstructed
Foundation. Track those two results separately.

Use temporary guest disk images for runtime tests. Do not install experimental
AppKit over the working guest's system framework or alter another task's guest.

### Pilot reconstruction

Choose one small module after dependency inventory. `NSAffineTransform` is the
leading candidate, not a precommitted choice: adopt it only if its dependency
closure permits a bounded compile and behavior test. Otherwise select the
smallest suitable module and record the reason.

Recover all methods and required helpers in the selected scope. Produce readable
source, compile for available targets, check architecture-specific metadata, and
compare normal, boundary, ownership, and error behavior where relevant. Ensure
test inputs expose implementation mistakes rather than merely restating source.

Stage 1 passes when inventory and repeatable analysis exist, the pilot's evidence
is traceable, and available target checks pass. If one target cannot be built or
run, report the stage as partially verified with an explicit environment blocker;
do not claim dual-target completion. Independent analysis can continue while an
environment is unavailable, but dependent acceptance cannot be waived.

## Subsequent reconstruction stages

The metadata and call graph will determine exact grouping and ordering. The
following is the program roadmap, not a claim that dependencies are already
resolved:

1. Graphics and resource primitives: contexts, drawing helpers, colors, resource
   loading, and their runtime dependencies.
2. Application lifecycle, events, responder dispatch, screens, windows, and views:
   include the Display PostScript/window-server boundary and nib loading needed
   by the first working application.
3. Cells, controls, menus, scrolling, and collection-style widgets, sequenced by
   actual superclass and runtime dependencies.
4. Image representations, image decoding, fonts, and related resource behavior.
5. Text storage, layout, editing, input, and serialization; divide this large
   subsystem into separately verified groups.
6. Documents, panels, printing, pasteboard, workspace/services, sound and movie
   integration, and remaining public and private functionality.
7. Full packaging and representative application validation.

Account for every recovered module and exported entry point in the coverage
ledger, including functionality not named explicitly above. The ledger prevents
the roadmap's examples from becoming accidental exclusions.

Window-server, Foundation, runtime, printing, and other external dependencies
remain separate projects. Document necessary interfaces and blockers; do not
silently expand AppKit reconstruction to replace those systems.

## Verification and acceptance

Maintain a per-group ledger recording reference identity, symbol or method,
source location, evidence, architecture, implementation status, tests, dependency
requirements, and unresolved behavior. Distinguish discovered, analyzed,
implemented, compiled, behavior-tested, and blocked states. Stubs never count as
reconstructed behavior.

ABI checks include exports, class hierarchy, selectors, categories, protocols,
type encodings, instance layouts, and linkage metadata. Compare layouts against
the appropriate target ABI: raw PowerPC offsets and calling conventions are not
automatically the correct i386 contract. Document release deltas when using DR2.

Behavioral checks use the original framework as an oracle where runnable,
covering deterministic return values, state transitions, ownership, exceptions,
archive round trips and compatibility, and observable UI interactions. Normalize
only explained nondeterminism. Screenshots can supplement UI checks but cannot
establish event dispatch, object lifetime, or serialization correctness.

Full-framework acceptance requires:

- Every in-scope module and exported entry point accounted for, with unresolved
  coverage reported explicitly.
- Successful PowerPC and i386 builds and applicable ABI checks.
- Version C framework packaging with the correct install name, public headers,
  resource dependencies, and documented resource provenance.
- Focused subsystem tests plus representative application checks for startup,
  nib loading, windows, controls, menus, drawing, text, persistence, and services.
- Separate results for original-dependency validation and RhapsodiOS integration.

If a runtime or service is unavailable, retain the corresponding tests and mark
them blocked. Do not substitute a successful compile or decompiler export for
behavioral verification.

## Risks and limits

The binary's 296 module records demonstrate that the existing source skeleton
does not describe the full reconstruction scope. Private implementations,
resource coupling, historical Objective-C dispatch, endianness, floating-point
behavior, structure returns, and binary archive formats require explicit
attention. Header identity reduces interface uncertainty but does not establish
implementation or cross-architecture equivalence.

Keep uncertainty local to the relevant ledger entry and resolve it through
additional code evidence or focused experiments. Do not invent placeholder
behavior to make broad coverage appear complete. Estimates for the full program
should follow the pilot's measured effort and recovered dependency graph.
