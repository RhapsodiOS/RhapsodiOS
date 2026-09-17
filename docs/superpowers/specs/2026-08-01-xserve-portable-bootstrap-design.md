# Portable PPC bootstrap and clean world-build design

## Problem

RhapsodiOS source is synced to a PowerPC Xserve at `/build/src`, but the
checked-in build workflow cannot yet take a fresh machine cleanly from source
to a complete package repository and world build. The current bootstrap path
assumes a Rhapsody-era host root and compensates for missing headers, libraries,
CRT objects, and helper tools by copying files into live `/System`, `/usr`, and
`/lib` locations. Numerous one-off scripts under `vm/` and `/tmp` record the
resulting repairs and retries.

The first target machine is an Xserve G4 running Mac OS X Server 10.2 (Darwin
6.0). It currently has no Developer Tools installed. Installing a suitable GCC
toolchain is an accepted prerequisite, but Jaguar headers and libraries must
not leak into Rhapsody target artifacts.

The goal is one resumable local entry point that remotely builds `rbuild`,
bootstraps a source-built target repository, builds the kernel and drivers, and
then builds the rest of the world without modifying the live host system.

## Accepted model

Use the model established by whole-system BSD builders:

1. Build tools that run on the build host into a dedicated `TOOLDIR`.
2. Accumulate the target operating system in a separate target `DESTDIR`.
3. Use that target root to break the initial source/package dependency cycle.
4. Once the build-base package closure exists, build ordinary packages in
   fresh per-package roots populated only from declared target packages.

This deliberately separates system bootstrap from clean package rebuilding.
Stage 0 is an ordered target-system build into an isolated root. Stage 1 and
later enforce clean package roots.

## Canonical interface

`sync-src.ps1` remains transfer-only. It continues to sync the local `src/`
tree to the configured remote root and restore executable bits.

The canonical build command is:

```powershell
powershell -File vm\build-src.ps1 -All
```

The existing phase switches remain available for diagnosis and deliberate
partial reruns:

- `-Rbuild`
- `-Bootstrap`
- `-KernelDrivers`
- `-World`

Ordinary invocations resume. `-Fresh` is an explicit opt-in reset modifier.
Before deleting anything, `-Fresh` resolves and verifies that every target is
one of the configured output paths beneath the configured remote build root.

## Directory contract

- `/build/src`: synced source tree
- `/build/tools`: build-host executables, wrappers, and normalized toolchain
  configuration
- `/build/bootstrap-root`: accumulated Rhapsody target root used only to break
  the initial package dependency cycle
- `/build/repo`: source-built build-base APK repository
- `/build/built`: self-hosted kernel, driver, and world APK repository
- `/build/state`: phase state, project state, toolchain probes, and logs

The paths are defaults. `build-src.ps1` continues to take its remote root,
repository, and output locations from configuration.

No build phase writes into the live host's `/System`, `/usr`, or `/lib`.

## Portable toolchain contract

Jaguar Developer Tools are the first supported provider, not part of the
architecture. The build distinguishes tools by role:

- `BUILD_CC` builds programs that execute on the build host, including
  `rbuild` and any proven host-only generators.
- `TARGET_CC`, `TARGET_AR`, `TARGET_RANLIB`, and related variables produce
  PowerPC Rhapsody target objects and binaries.
- `MAKE`, `SHELL`, `TAR`, `GZIP`, and `RSYNC` name capability-checked utility
  implementations.

A generic GCC profile defines required capabilities rather than executable
paths: C89 compilation, PowerPC Mach-O output, isolated target include search,
isolated target library search, and compatible assembler/linker behavior.
Provider profiles translate those requirements into concrete flags. The first
profile maps Jaguar GCC and the Darwin linker onto the contract. A future
native or cross-GCC provider may instead use options such as GCC/ld sysroot
flags without changing manifests or bootstrap control flow.

Preflight compiles and inspects probes. Finding a program named `gcc` is not
sufficient. The resolved executables, versions, capabilities, and normalized
flags are written to `/build/state/toolchain.conf`. `rbuild` consumes this
normalized configuration and does not contain Jaguar-specific paths.

Historical source makefiles receive standard build variables (`CC`, `AR`,
`RANLIB`, `RC_CFLAGS`, and linker flags). Where an in-tree makefile hard-codes
a host tool, the focused fix is to honor the standard variable; the bootstrap
driver does not compensate by overwriting live host paths.

## Build phases

### 1. Preflight

Validate SSH connectivity, source layout, available disk space, case-sensitive
path behavior, output-directory safety, and the selected toolchain profile.
Verify all required tool capabilities before starting a long build. Failures
name the missing capability and the profile setting that controls it.

### 2. Host `rbuild`

Compile and test `src/rbuild-1` with `BUILD_CC`. Install the resulting host
executable under `/build/tools/bin`; do not install it into `/usr/bin`.

Create the target compiler/utility wrappers under `/build/tools/bin` from the
normalized toolchain configuration. These wrappers enforce the target sysroot
and make accidental host include/library resolution a hard failure.

### 3. Target bootstrap

`rbuild bootstrap` processes the existing three-column `BootstrapManifest` in
declared order. No new manifest language is needed. Header/framework providers
appear before their consumers, and projects use the existing `headers` or
`all` target as appropriate.

For each project:

1. Reconstruct its source and object roots beneath the configured build area.
2. Build on the host with target tools and `/build/bootstrap-root` as the
   exclusive target sysroot.
3. Install into that project's private `HDRROOT`/`DSTROOT` and produce its APKs.
4. Validate each APK and its metadata.
5. Extract accepted target APKs into `/build/bootstrap-root` in manifest order.
6. Atomically record completion only after package validation and target-root
   installation both succeed.

This keeps package payloads isolated even though target dependencies accumulate
in a shared bootstrap root. Host executables remain in `/build/tools` and are
never included in target APKs.

Missing headers or tools are treated as manifest-ordering, target metadata, or
source/build-rule defects. They are not repaired by copying files into the live
host or by uploading scripts to `/tmp`.

### 4. Bootstrap closure validation

After `BootstrapManifest` completes, verify that `/build/repo` provides every
package in `rbuild`'s declared build-base closure. Validate package readability,
metadata, architecture, and required header variants. Do not begin self-hosted
builds with an incomplete closure.

### 5. Kernel and drivers

Use normal clean per-package roots populated from `/build/repo` to build the
required kernel and core driver projects into `/build/built`. Required core
projects are explicit. The later optional driver sweep may continue to discover
eligible driver projects from source metadata, but it records the exact set in
state for reproducibility.

Required kernel/core-driver failures stop immediately. Optional driver builds
may continue and produce an aggregate failure summary.

### 6. World

Run `rbuild buildall Manifest /build/repo /build/built`. Every project uses a
fresh build root populated only from the bootstrap repository and its declared
target dependencies. Valid artifacts produced by the kernel/driver phase are
recognized and skipped.

World may continue through independent projects to provide a useful failure
summary, but `build-src.ps1 -All` exits nonzero until every required project has
succeeded.

## Resume and reconstruction

Valid package artifacts are primary evidence of completion. State files provide
phase, manifest position, toolchain identity, and log location, but a state file
alone never marks a package complete.

Before skipping a project, `rbuild` verifies the expected APKs, gzip/tar
readability, package metadata, architecture, and target. A partial or invalid
artifact is moved aside and rebuilt. Project completion state is written by
atomic rename after the package is installed into the bootstrap root.

If `/build/bootstrap-root` is missing while valid bootstrap packages remain,
`rbuild` recreates the root and replays accepted APKs in manifest order. It does
not recompile those projects. If a build is interrupted, the active project has
no accepted completion marker and is retried on the next invocation.

Resume requires the selected toolchain identity and relevant manifest inputs to
match recorded state. A mismatch stops with instructions to choose `-Fresh` or
restore the previous configuration; it is never silently mixed into an old
bootstrap.

## Error handling and logs

Each phase and project writes a persistent log beneath `/build/state/logs`.
Failure output includes:

- phase and project
- failing command and exit status
- log path
- accepted artifacts, if any
- exact resume command

Preflight, host `rbuild`, bootstrap closure, kernel, and required driver phases
fail fast. World and optional driver sweeps may collect independent failures.

## Verification ladder

1. Preflight accepts a supported GCC provider and reports precise capability
   failures for incomplete providers.
2. Host `rbuild` and its unit tests compile into `/build/tools`.
3. Bootstrap framework/header projects populate `/build/bootstrap-root`.
4. Verbose compiler probes and link inspection prove that target compilation
   does not resolve Jaguar headers or libraries.
5. `BootstrapManifest` produces the complete build-base APK closure in
   `/build/repo`.
6. Removing only `/build/bootstrap-root` and resuming reconstructs it from
   valid APKs without recompilation.
7. Interrupting a project produces no accepted state; resume rebuilds it and
   continues.
8. A representative target package builds in a fresh root populated only from
   `/build/repo`.
9. Kernel and required drivers build into `/build/built`.
10. World completes, and an immediate second `-All` invocation performs no
    unnecessary work.
11. A before/after host audit confirms that live `/System`, `/usr`, and `/lib`
    were not modified.

## Out of scope

- Installing Jaguar Developer Tools or another GCC provider automatically
- Creating a modern non-Mach-O cross compiler
- Rewriting the historical project makefile frameworks
- Producing installation media or installing the built system on the Xserve
- Cleaning unrelated diagnostic files already present in `vm/`

## Success criteria

After installing a supported GCC-based toolchain and syncing `src/`, a user can
run `build-src.ps1 -All` repeatedly. The command builds host `rbuild`, creates a
source-built and host-header-free bootstrap repository, builds the kernel and
drivers, and completes the world in clean package roots. Interrupted work
resumes without accepting partial artifacts, and the live host system remains
unchanged.
