# rbuild isolated build and packaging design

**Date:** 2026-07-20  
**Status:** Approved for implementation planning  
**Replaces:** The current shared-`DSTROOT` execution model in `rhap-build`  
**Preserves:** Samurai orchestration, Apple/NeXT makefiles, and apk packaging

## Summary

Rename `rhap-build` to `rbuild` and make it the entry point for reproducible,
apk-driven builds. A one-time bootstrap phase uses the native tools already
installed on a Rhapsody host. After that phase, every project builds in a
fresh chroot populated only with its declared apk build dependencies.

The system produces three build variants:

- `universal` for fat PPC+i386 userland binaries;
- `ppc` for thin PowerPC packages and PowerPC-only kernel components;
- `i386` for thin Intel packages and Intel-only kernel components.

The preferred distribution combines universal userland with the matching
architecture-specific kernel and driver repository. apk-tools gains native
architecture awareness before those repositories are published together.

## Current-state audit

The July 2026 migration already replaced the historical Perl, dpkg, `.deb`,
and per-project chroot pipeline:

- `ninja/rhap-build` generates the samurai graph and provides package and
  repository commands.
- `ninja/buildproj.sh` runs existing project makefiles and packages private
  install roots.
- Projects are discovered through `src/**/apk/PKGINFO`.
- `src/apk-tools` provides apk-tools 2.0_pre11.
- Builds currently share one `DSTROOT`, so undeclared dependencies and stale
  outputs can affect later projects.
- Unknown build dependencies are warned about and skipped.
- apk-tools 2.0_pre11 does not store or enforce package architecture.
- `generate.c` and `buildproj.sh` already distinguish `universal`, `ppc`, and
  `i386`; universal maps to `RC_ARCHS="i386 ppc"`.
- Bootstrap still relies on a compiler, make, shell, and base utilities
  installed on the native host.

Stale migration artifacts such as `src/Manifest`, `src/PROJECTS`, the
top-level `usrtemplate/dpkg/control`, and remaining `genninja` references
should be resolved during graph-hygiene work, not treated as active inputs.

## Goals

1. Build the kernel and tooling from a clean native Rhapsody VM using only
   its installed host tools as the initial trust root.
2. Require chroot isolation for every build after bootstrap.
3. Populate each build root from declared apk build dependencies.
4. Fail on incomplete or cyclic dependency metadata.
5. Support universal userland and separate PPC/i386 repositories.
6. Make apk reject packages that are incompatible with the target root.
7. Preserve the existing project makefiles and samurai parallel graph.
8. Publish complete packages and indexes atomically.

## Non-goals

- Cross-compiling from modern macOS or Linux.
- Replacing samurai or the Apple/NeXT make framework.
- Adopting Alpine APKBUILD or abuild as a runtime dependency.
- Providing a security sandbox stronger than the host's `chroot`.
- Requiring byte-identical archives in the first milestone.
- Restoring dpkg or `.deb` compatibility.
- Keeping a long-lived `rhap-build` compatibility executable.

## Architecture

### rbuild

`ninja/rhap-build` becomes `ninja/rbuild`. `rbuild` remains a multi-command C
tool and owns:

- graph generation and strict dependency validation;
- bootstrap orchestration;
- chroot creation and lifecycle;
- isolated project execution;
- package creation and architecture validation;
- repository indexing and publication;
- build-root diagnostics and cleanup.

Samurai remains the DAG executor. Existing `generate`, `build`, `mkapk`,
`index`, and `publish` behavior moves to the new binary. New commands include
`doctor`, `bootstrap`, and `clean`. Repository callers, generated rules,
tests, and documentation switch atomically to `rbuild`.

### Bootstrap builder

`rbuild bootstrap` is the only unisolated build path. It uses the compiler,
make, shell, and utilities already installed on the native Rhapsody VM to
produce the minimum `build-base` apk repository.

Bootstrap packages are marked as provisional. Once they can populate a
working chroot, `build-base` is rebuilt inside isolated roots. Only the
isolated results are accepted as the self-hosted repository.

### Root manager

The root manager creates a fresh root for each project and target variant:

1. Initialize an empty filesystem tree.
2. Install the relevant base packages and declared `builddepend` closure
   through apk.
3. Copy the project's staged sources into the root.
4. Create root-local source, object, symbol, and package-output directories.
5. Enter the root with `chroot` and run the project worker.
6. Retain failed roots for diagnosis.
7. Remove successful roots unless retention was requested.

Version one favors fresh roots over caching. A later optimization may clone a
validated base root, but it must preserve the same clean-build semantics.

### In-chroot project worker

The worker adapts the current `buildproj.sh` responsibilities:

- set a minimal, deterministic environment;
- point `PATH` and `MAKEFILEPATH` only inside the chroot;
- select `RC_ARCHS` for `universal`, `ppc`, or `i386`;
- invoke `installhdrs` or `install`;
- install into a private package root rather than a shared `DSTROOT`;
- return the package root to the host-side packaging step.

Builds do not fetch sources or dependencies after entering the chroot. All
inputs are staged first.

The headers edge produces an installable `<pkgname>-hdrs` apk from its private
header root. This preserves the existing header-only dependency edges that
break bootstrap cycles. A `foo-hdrs` build dependency installs that package;
a `foo` dependency installs the full package. Full packages do not implicitly
claim files owned by their header packages.

### Repository manager

Repositories are indexed separately by build variant. The preferred
distribution profile enables:

- the universal userland repository; and
- exactly one architecture supplement repository (`ppc` or `i386`).

Thin-only PPC and i386 profiles remain supported. `rbuild` rejects ambiguous
publication where incompatible variants of the same package could be selected
for one target profile.

## apk architecture support

Architecture enforcement is a prerequisite for mixed repository profiles.
The vendored apk-tools gains:

- an `arch` member on `struct apk_package`;
- parsing of `arch` from `.PKGINFO`;
- an `A:` architecture field in `APK_INDEX.gz`;
- native architecture detection;
- an explicit target-architecture override for chroot and build operations;
- solver filtering that excludes incompatible package candidates.

Canonical package architecture values are:

- `powerpc-apple-rhapsody`;
- `i386-apple-rhapsody`;
- `universal`;
- `noarch`.

Compatibility rules are:

- PowerPC roots accept `powerpc-apple-rhapsody`, `universal`, and `noarch`.
- Intel roots accept `i386-apple-rhapsody`, `universal`, and `noarch`.
- Universal build roots accept `universal`, `noarch`, and the explicitly
  selected architecture supplements needed to produce both slices.
- Other combinations are rejected before dependency resolution commits a
  transaction.

During metadata migration, a missing `arch` emits a warning and is interpreted
as `universal`. After the tree is migrated, missing or unknown architecture
metadata is an error.

Before publication, `rbuild` examines packaged Mach-O files:

- universal executables and libraries must contain both PPC and i386 slices;
- thin packages must not claim the opposite architecture;
- scripts and data-only packages may use `noarch`.

## Build data flow

1. `rbuild doctor` verifies native host tools, chroot operation, filesystem
   behavior, apk availability, and target architecture support.
2. `rbuild bootstrap` builds the provisional universal `build-base`
   repository with host tools.
3. apk creates validated universal, PPC, and i386 base roots.
4. Samurai selects a project edge and target variant.
5. `rbuild` creates a fresh project root and installs the declared dependency
   closure.
6. The worker builds inside the chroot and writes a private package root.
7. Header edges publish `<pkgname>-hdrs`; full edges publish `<pkgname>`.
8. `rbuild` creates the apk, validates metadata and Mach-O slices, and
   publishes it to the matching repository.
9. Repository indexes are regenerated after all required package edges
   succeed.
10. Universal userland is combined with the selected PPC or i386 kernel and
   driver supplement for installation.

Build stamps incorporate:

- source inputs;
- package metadata;
- build variant;
- build configuration;
- checksums of dependency packages.

A dependency package change therefore invalidates downstream builds.

## Dependency policy

Graph generation is strict:

- unknown `builddepend` names are fatal;
- dependency cycles are fatal;
- duplicate providers or ambiguous project/package mappings are fatal;
- architecture-incompatible dependency closures are fatal.

Bootstrap cycles may be broken only through a small, checked-in allowlist that
states the affected package, ignored edge, reason, and removal condition.
There is no general warning-and-skip mode for `buildkernel` or `buildworld`.

## Failure handling

- Failed root creation or dependency installation stops before compilation.
- Failed build roots are retained with their logs and resolved dependency
  manifest; `rbuild clean` removes them.
- Successful roots are removed by default.
- Missing or incorrect Mach-O slices fail packaging.
- Architecture mismatches and repository collisions fail publication.
- Packages and indexes are written under temporary names and atomically
  renamed only after validation.
- Provisional bootstrap packages cannot be mistaken for self-hosted outputs.
- Interruptions leave the last complete repository index in place.

## Testing

### Unit tests

- PKGINFO and index architecture parsing and serialization;
- native and overridden architecture compatibility;
- strict dependency resolution and bootstrap exceptions;
- repository-profile selection and collision detection;
- build-stamp dependency checksum calculation.

### Integration tests

- apk rejects incompatible packages and resolves universal packages on both
  target architectures;
- declared chroot dependencies build successfully;
- header-only dependencies install generated `-hdrs` packages without pulling
  full runtime packages;
- an undeclared dependency available on the host remains unavailable inside
  the chroot and causes the fixture to fail;
- universal fixture binaries contain PPC and i386 slices;
- thin fixtures contain only their declared slice;
- dependency package changes rebuild downstream projects;
- failed or interrupted publication leaves the previous index usable.

### Fresh-VM acceptance test

For both supported target architectures:

1. Start from a clean native Rhapsody VM with host tools only.
2. Run `rbuild doctor`.
3. Produce the provisional bootstrap repository.
4. Rebuild `build-base` inside chroots.
5. Build the kernel and architecture-specific supplements.
6. Build and validate universal userland fixtures.
7. Install the resulting profile into disposable roots with apk.

The first milestone requires repeatable clean builds and equivalent package
manifests. Byte-identical archives may be addressed after timestamps and other
historical-tool nondeterminism are measured.

## Phased roadmap

### Phase 1: Naming and graph hygiene

- Rename `rhap-build` to `rbuild` across source, generated rules, tests, and
  documentation.
- Make unknown dependencies, cycles, duplicate mappings, and invalid metadata
  fatal.
- Audit and remove or update stale manifests, dpkg metadata, and `genninja`
  references.
- Produce a warning-free graph for the current tree.

### Phase 2: Architecture-aware apk

- Implement package and index architecture fields.
- Add native detection, explicit overrides, and solver filtering.
- Normalize all project architecture metadata.
- Add universal/thin package validation and repository-profile tests.

### Phase 3: Bootstrap repository

- Define the minimum host-tool bootstrap set.
- Add `rbuild doctor` and `rbuild bootstrap`.
- Produce provisional build-base packages without chroot isolation.
- Record exact host assumptions and bootstrap package provenance.

### Phase 4: Isolated build roots

- Implement root creation, apk dependency installation, chroot execution,
  diagnostics, and cleanup.
- Split host orchestration from the in-chroot project worker.
- Make chroot execution mandatory outside bootstrap.
- Rebuild `build-base` inside isolated roots.

### Phase 5: First kernel milestone

- Build the kernel subset and architecture supplements for PPC and i386 from a
  fresh VM workflow.
- Build universal userland prerequisites where required.
- Publish installable universal+PPC and universal+i386 profiles.
- Install and verify both profiles in disposable roots.

### Phase 6: World hardening

- Extend isolated builds to `buildworld`.
- Resolve undeclared dependencies exposed by clean roots.
- Add dependency-checksum invalidation and full repository acceptance tests.
- Evaluate safe base-root caching only after clean-build correctness is stable.

## First milestone success criteria

The design's first milestone is complete when a clean native Rhapsody VM,
starting with host tools and no dpkg seed, can:

1. build a provisional apk bootstrap repository;
2. self-host `build-base` inside chroots;
3. build the kernel path for PPC and i386;
4. produce validated universal userland and architecture supplements;
5. publish architecture-aware repositories; and
6. install each resulting profile with apk into a disposable root.

