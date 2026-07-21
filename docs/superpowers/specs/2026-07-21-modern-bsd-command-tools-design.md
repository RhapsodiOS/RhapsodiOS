# Modern BSD command tools design

**Date:** 2026-07-21  
**Status:** Approved for planning

## Summary

Modernize a deliberately small first wave of Rhapsody command-line tools with
current NetBSD behavior as the default.  Import each tool from a pinned,
maintained NetBSD release, preserve upstream provenance, and add narrow
Rhapsody compatibility shims only where an in-tree consumer demonstrably needs
historical behavior.  The tools must build natively on both Rhapsody `ppc` and
`i386` hosts using the existing Apple/NeXT build framework and `rhap-build`
packaging flow.

## Goals

1. Bring selected base utilities to a contemporary, maintained BSD codebase.
2. Make modern NetBSD command behavior the normal user-facing behavior.
3. Preserve required Rhapsody scripts and system consumers through tested,
   explicit shims rather than preserving every historical quirk.
4. Keep the initial migration independently buildable, testable, packageable,
   and reversible per utility or utility family.
5. Establish a repeatable import process for subsequent command waves.

## Non-goals

- Importing NetBSD's complete userland or its build system.
- Changing the Rhapsody libc, kernel, or global system headers as part of a
  command port.
- Cross-compiling the command set from a modern host.
- Modernizing shell, account/process-database, terminal, authentication,
  locate-database, or legacy time/network-sensitive commands in the first wave.

## First-wave scope

The initial candidate set is the self-contained portion of
`src/Commands/shell_cmds`:

`basename`, `dirname`, `env`, `find`, `hostname`, `kill`, `nice`, `nohup`,
`printenv`, `pwd`, `sleep`, `tee`, `test`, `uname`, `xargs`, and `yes`.

The exact per-tool sequence will be chosen after inventorying dependencies and
callers.  Tools may be deferred if their import requires a broad platform
change.

Explicitly defer `sh`, `su`, `w`, `who`, `lastcomm`, `locate`, `window`, and
`date`.  They involve, respectively, shell internals, authentication,
utmp/process accounting, locate databases, terminal state, or legacy
time/network interfaces and need separate designs.

## Architecture

### Per-tool import boundary

Each modernized tool or tightly coupled tool family owns four artifacts:

| Artifact | Purpose |
| --- | --- |
| `upstream/` snapshot | Pinned NetBSD source and required upstream license/notices, kept as close to upstream as practical. |
| `rhapsody/` layer | Native Apple/NeXT build glue plus small portability helpers or adapters. |
| provenance record | NetBSD release/tag/commit, release date, source-file list, licenses, and local changes. |
| compatibility manifest | Historical difference, affected consumer, decision, shim location, and focused regression test. |

The repository layout is selected during implementation so it fits the existing
project conventions.  It must preserve a clear separation between imported
source and local changes.

### Compatibility rule

An imported utility exposes its selected modern NetBSD behavior by default.
Compatibility code is allowed only when a checked-in consumer, startup script,
packaging tool, or documented Rhapsody interface requires the old behavior.
The preferred order is:

1. Update an in-tree consumer to the modern interface when safe.
2. Add a small, explicit adapter or feature test if retaining that consumer is
   required.
3. Escalate the port to a separate compatibility-library proposal if the only
   alternative is modifying global libc/system headers or scattering platform
   conditionals through upstream code.

Every shim must have a focused test.  Untested historical compatibility is not
part of the support contract.

### Native build and packaging

Each import integrates through the existing Apple/NeXT make project framework,
then is discovered and packaged by `rhap-build`.  It must build natively with
the historical Rhapsody toolchain for both `ppc` and `i386`, install at the
existing command path, and produce either its own APK or a small coherent
family APK.  The plan must document package ownership so replacements do not
silently overlap legacy files.

## Import and release process

For each selected tool:

1. Pick a maintained NetBSD release branch and record the exact tag/commit,
   release date, license, and imported files.
2. Inventory the Rhapsody implementation, installed path, man page, in-tree
   callers, options, environment variables, output, exit statuses, filesystem
   effects, and signal behavior.
3. Import the upstream snapshot and add only the local build/portability layer.
4. Build and package natively for both architectures into a disposable root.
5. Run upstream-style behavioral tests, local conformance tests, and probes for
   every known Rhapsody consumer.  Consider updating consumers before adding a
   shim.
6. Publish a candidate APK.  Promote it into the base image only after native
   and VM regression gates pass.

## Testing and acceptance criteria

### Build gates

- Clean native builds on Rhapsody `ppc` and `i386`.
- No undeclared host-tool dependency.
- Expected installed paths and package file ownership.
- Reproducible APK payloads when the existing toolchain permits stable
  timestamps/ordering.

### Behavioral gates

- A shared harness checks supported invocations against the selected NetBSD
  reference: exit status, stdout/stderr, filesystem effects, and signal
  behavior.
- A Rhapsody regression suite runs all identified in-tree callers, bootstrap
  and packaging scripts that use replaced tools, and a VM smoke path covering
  login shell, basic filesystem work, and package installation.
- Every compatibility manifest entry maps to a focused regression test.

### Rollback

Keep the legacy utility in a versioned fallback APK through the candidate
release.  Reverting must mean reinstalling that package; it must not require a
libc or kernel rollback.

The first wave succeeds only when every admitted tool meets both-architecture
native build gates, its defined conformance tests, VM boot/install smoke tests,
and the compatibility rule above.

## Risks and controls

| Risk | Control |
| --- | --- |
| Modern NetBSD expects APIs absent on Rhapsody. | Tool-local portability layer first; separate proposal for any shared ABI change. |
| Imported changes break undocumented system scripts. | Caller inventory, disposable-root tests, VM smoke runs, and versioned fallback APK. |
| Upstream updates become an unreviewable fork. | Pinned snapshots, provenance records, and a minimal local delta. |
| The first wave expands into high-coupling utilities. | Enforce the defined candidate boundary; create a separate design for each deferred family. |
