# Interceptor reconstruction for PowerPC and i386

## Intent and scope

Reconstruct Interceptor as maintainable historical Objective-C and C source in
`src/Kits/Interceptor`, building for both 32-bit PowerPC and i386. The user
explicitly selected both architectures. The supplied framework is the primary
behavioral and API reference; DR2 provides architecture-specific supporting
evidence. This is a design for review, not an implementation-completion claim.

Recover the complete framework-owned implementation: public classes, private
classes, categories, globals, C helpers, and Mach IPC client routines. Preserve
manual memory management, the historical Objective-C runtime, published layouts,
selectors, error behavior, and wire contracts. Do not substitute modern Cocoa
APIs or count placeholder methods as reconstructed functions.

## Measured references

Primary directory:
`C:\Users\raynorpat\Downloads\test\Frameworks\Interceptor.framework\Versions\A`.

| Artifact | Measured identity |
| --- | --- |
| `Interceptor` | Thin big-endian PowerPC MH_DYLIB, 145364 bytes |
| SHA-256 | `8b98846ae99cc7b8120a5dcf8b9a21855700895d0df5fe0da403c9f183d63a96` |
| Code | 57332 bytes of `__text`; 540 symbol-table entries; 234 named Objective-C methods; no STABS |
| `Interceptor_profile` | Thin PowerPC, 170032 bytes; 541 symbols; 234 named methods; no STABS |
| Profile SHA-256 | `de209f58f70c69a346460e95bfb3ffed2d3400e49602a1b8178e1b42521084de` |

The directory includes nine public headers, `Interceptor.p`, and
`Resources/Info-nextstep.plist`. Treat the precompiled header as a reference
artifact, not portable source. The normal binary is authoritative; the profiling
build is supporting evidence and is not assumed to contain additional debug data.

Secondary container:
`C:\Users\raynorpat\Downloads\test\DR2\Frameworks\Interceptor.framework\Versions\A\Interceptor`.
Size: 311836 bytes. SHA-256:
`e7af0995aa6bcc744ce00137d29cdd8ce2daf3f93cd0efa436f4e90d3ab46041`.

| Slice | Offset | Size | SHA-256 |
| --- | --- | --- | --- |
| i386 | 8192 | 140216 | `56eb8f81b06cfbdbe898d39c4766720f71b1c1effd54869f78cd3340dc9a9dd1` |
| PowerPC | 155648 | 156188 | `9f83fda9410d56530b9d98d695ebbb84d767f58f0fb3f93fe1e45d1793755fcc` |

Both DR2 slices contain 232 named Objective-C methods. Establish the precise
release delta before using DR2 as a parity oracle. Port newer reference behavior
to i386, documenting intentional differences from DR2 rather than silently
removing newer functionality. Same-release cross-architecture evidence from DR2
helps distinguish CPU differences from release differences.

Reference binaries and generated analyzer databases remain outside Git.

## Approach and alternatives

Recommended: shared evidence-driven source, with architecture-specific code only
where required by measured ABI, byte order, or hardware behavior. Maintain separate
PowerPC and i386 evidence ledgers. This supports the requested two architectures
without mistaking cross-architecture instruction differences for behavioral bugs.

Alternatives considered: PowerPC-first reconstruction followed by an i386 port
delays portability defects; public-API-only reimplementation omits private
contracts and cannot establish full framework parity. Neither is the chosen scope.

## Components and data flow

Use the reference Objective-C module metadata to recover translation-unit
ownership before fixing implementation filenames. Proposed organization:

```
src/Kits/Interceptor/
  Interceptor.h, Interceptor_types.h, InterceptorGlobals.h
  NSBitmap.h, NSDirectBitmap.h, NSDirectPalette.h
  NSDirectScreen.h, NSFramebuffer.h, NSShape.h
  *.m, *.c, private headers, recovered IPC definitions
  Makefile, Makefile.preamble, Makefile.postamble, PB.project
  Resources/Info-nextstep.plist
  tests/
  reconstruction/
    reference.md, abi.md, release-differences.md, function-worklist.md
    ppc/, i386/
tools/binrecon/profiles/interceptor-ppc.json
tools/binrecon/profiles/interceptor-i386.json
```

The measured class/method symbols identify these implementation groups:

1. `NSSimpleBitmap`, copy helpers, and global encoding strings: bitmap layout,
   pixel descriptions, and source/destination copying.
2. `NSShape`, `_NSShapeEnumerator`, and shape helpers: rectangle-set operations
   and enumeration.
3. `NSInterceptorClient`, `NSInterceptedRect`, rendezvous/context helpers, and
   `Interceptor*`/`_Interceptor*` IPC routines: connection, ownership, messaging,
   and geometry notification behavior.
4. `NSFramebuffer`: mapping, access tokens, lock/unlock, conversion tables, and
   framebuffer metadata.
5. `NSDirectPalette`, `NSDirectScreen`, and `NSDirectBitmap`: palette management,
   display modes, fades/shielding, buffering, clipping, and flush behavior.

Preserve observed private and obsolete categories. These are binary contracts,
not permission to redesign the API. Public objects call private client and
rectangle objects; those call Mach IPC and driver interfaces; returned mappings
and geometry drive bitmap addressing, clipping, conversion, and flush operations.
Recover exact ordering, ownership, notification handling, and cleanup from code.

Dependencies measured in the supplied binary are libDriver.A.dylib, AppKit
Versions/C, Foundation Versions/C, and System Versions/B. The library install
name is `/System/Library/Frameworks/Interceptor.framework/Versions/A/Interceptor`.

## Tooling and build prerequisites

The existing binrecon Mach-O reader supports both byte orders but currently
rejects MH_DYLIB. Add narrowly scoped dylib support and fixture tests before
claiming analyzer coverage. Reuse the existing Objective-C method indexing,
source mapping, and parity tools where suitable; verify their handling of this
framework's sections, imports, stubs, and load commands. Extract fat slices into
external output directories with recorded hashes. Do not analyze fat containers
as though they were thin images.

The current documented PowerPC analyzer route is IDA; do not enable unsupported
PowerPC Ghidra/angr adapters. Validate installed tool capabilities during execution.
Decompiler output is a hypothesis to check against disassembly and metadata.

Follow the historical framework project conventions visible in
`src/Kits/SoundKit`, using version A and the measured install name. Support
`RC_ARCHS` for each thin build and the combined artifact using the repository's
current toolchain conventions. Verify Objective-C compiler/runtime support,
SDK headers, dependency dylibs, and linker availability for both architectures
early. Existing old documentation about unavailable PowerPC builds is not proof
of the current toolchain state.

No Kits entries were found in `src/Manifest` during inspection. Standalone
framework build/install targets belong to this scope; enabling global OS image
packaging is a later integration decision once dependency availability is proven.
Do not expand this reconstruction into Foundation, AppKit, or Window Server
reimplementation. Missing dependencies become explicit build/runtime blockers.

## Reconstruction sequence and checks

1. Establish references and tooling: inventory and hash headers and binaries;
   recover modules, classes, categories, ivars, selectors, exports, imports, and
   function boundaries; identify DR2/newer differences. Check inventories against
   symbol tables and Objective-C metadata independently.
2. Establish dual-architecture build and ABI checks: public header compatibility,
   structure/ivar offsets, calling conventions, return types, runtime metadata,
   and framework linkage. A diagnostic skeleton is not a deliverable framework.
3. Reconstruct pure bitmap and shape routines. Check boundary rectangles,
   empty/overlapping shapes, enumeration, stride/plane calculations, and copy
   cases that the recovered implementation supports.
4. Recover IPC contracts and private client state. Establish message IDs, sizes,
   descriptors, reply validation, port ownership, and cleanup. Recreate MIG
   definitions only where supported by evidence; otherwise preserve explicit
   wire-compatible routines. Check captured messages and failure paths.
5. Reconstruct framebuffer, palette, screen, and direct bitmap behavior. Check
   mapping lifetime, lock state transitions, geometry notifications, palette
   updates, conversion tables, display modes, and buffered/direct flush paths.
6. Build both slices, compare evidence, and run guest integration tests. Record
   function-level outcomes and remaining dependency or execution blockers.

Dependencies determine implementation order within those groups. Shared state
and notification paths must be reviewed together, even when source files differ.
Derive actual error returns, exceptions, retries, and teardown behavior from the
reference; do not introduce generic fallback behavior that masks incompatibility.

## Verification and acceptance

Track every framework-owned function and method, including private helpers and
categories. Distinguish loader/linker-generated glue from owned code using
evidence. Each owned entry must map to source and carry reviewed behavioral
evidence; unknown entries and stubs remain incomplete.

PowerPC: compare against the supplied binary for exports, layouts, selectors,
constants, control flow, calls, and observable behavior. Exact instruction matches
are useful evidence, not a universal requirement across compiler differences.

i386: compare shared behavior and ABI against the DR2 i386 slice, account for
release differences using the DR2 PowerPC slice, and test newer behavior ported
from the primary reference. Do not describe this as exact parity with an
unavailable newer i386 reference.

Run meaningful pure-operation and protocol tests on both target architectures,
plus framework load and graphics integration tests in compatible guests where
available. Exercise Window Server loss, rejected mapping/locking operations,
geometry changes, palette restoration, and object teardown according to recovered
contracts. Use disposable disk images/overlays; never modify a shared guest base
or replace its installed framework for testing.

Completion requires both architecture builds and reviewed coverage of all owned
code, with no unexplained ABI/export or behavioral discrepancies. Report build,
static parity, pure/protocol testing, and graphics runtime validation separately
for each CPU. If a compatible guest or dependency is unavailable, mark its runtime
validation blocked; a successful host test or cross-compile does not satisfy it.

## Review boundary

This document defines the proposed design and milestone sequence. After written
spec approval, expand it into an implementation plan with exact tasks, commands,
files, and per-task verification. Implementation has not started.
