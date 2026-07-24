# rbuild — C89 conversion of the Perl build tools (apk-native)

**Date:** 2026-07-23
**Status:** Design approved, pending implementation plan

## Summary

Replace the three Perl build scripts and the `Dpkg::Package::*` engine they
depend on with a single C89 executable, `rbuild`, that produces and consumes
**apk** packages (targeting apk-tools 2.0_pre11) instead of dpkg `.deb`.

This accomplishes two goals at once:

1. **Bootstrapping** — removes Perl from the RhapsodiOS build toolchain, so the
   system can build itself without needing Perl present first.
2. **Modernization / simplification** — one maintainable C program in place of
   three thin Perl wrappers over a 962-line Perl module, and a move off dpkg to
   the simpler apk packaging model.

### What is being replaced

The current tools live in `src/buildtools-2/`:

- `tools/darwin-buildpackage.pl` (41 lines) — build one source
- `tools/darwin-buildall.pl` (51 lines) — build every package in a manifest not
  already present
- `tools/darwin-missing.pl` (36 lines) — report which manifest packages are
  missing, build nothing

These are thin wrappers. The real logic is in:

- `src/buildtools-2/lib/Builder.pm` (962 lines) — the build engine
- `src/buildtools-2/lib/Manifest.pm` (40 lines) — manifest / directory reader
- `src/dpkg_scriptlib-1/perl5/Dpkg/Package/Package.pm` (110 lines) — the package
  metadata object (`parse` / `unparse` / `canon_name`)

`Dpkg::Package::List` is `use`d by `Builder.pm` but never referenced; it does not
need to be ported.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Sequencing | Port to C89 **and** target apk from the start (single project) | apk is the agreed destination; reproducing dpkg semantics in C would be throwaway work, and `.PKGINFO` is simpler than Debian control parsing. |
| Executable | One binary, `rbuild`, with subcommands | User requested combining the three scripts into one tool. |
| apk interaction | Shell out to `apk` for runtime ops; build `.apk` directly in C via `tar` + `gzip` | Keeps `rbuild` self-contained for packaging (bootstrap-friendly); avoids fragile libapk dependency. 2.0_pre11 has no package-*build* command. |
| Tar/compression | Shell out to `tar` + `gzip` | Simplest, era-appropriate, no libarchive/zlib dependency. |
| Parsing | Hand-written parsers (no regex library) | Patterns are simple and structured; keeps `rbuild` dependency-free for bootstrapping. |
| CVS support | **Dropped** — build from `--dir` only | Legacy; RhapsodiOS uses local source dirs. Removes `scancvs`/`getcvs` and all cvs shell-outs. |
| Sub-packages | **Kept** — still emit `binary`, `<name>-hdrs`, `<name>-obj` | User chose to preserve; headers-only build deps remain useful. |
| Object harvesting | **Kept** — `dynamic_obj` harvest into `/usr/local/lib/objs` | User chose to preserve. |
| Build machinery | **Kept** — chroot buildroot, `DSTROOT`/`OBJROOT`/…, `RC_CFLAGS`, `make` | Essential to actually compiling a Rhapsody project; backend-agnostic. |
| Placement | New project `src/rbuild-1/` with its own Makefile | Keeps the Perl around as the test oracle; matches per-project tree layout. |
| Tests | Unit tests of pure functions + dry-run command-trace comparison | Chosen layers; see Testing. |

## CLI

```
rbuild buildpackage [--dir] [--target {all|headers|objs|local}] <source> <repository> <dstdir>
rbuild buildall   <srclist> <repository> <dstdir>
rbuild missing    <srclist> <dstdir>
```

- `--dir` is the only accepted source type. It is optional and defaults on (source
  type is always `dir`). `--cvs` is rejected with an error message pointing at the
  dropped-support note, rather than silently ignored, so old invocations fail
  loudly instead of behaving unexpectedly.
- `--target` defaults to `all` (as in the Perl).
- Global `-n` / `--dry-run` prints the commands that would be executed instead of
  running them.
- Argument-count and usage errors print usage to stderr and exit 1, matching the
  Perl.

Subcommand → old script mapping:

| Subcommand | Replaces | Args |
|---|---|---|
| `buildpackage` | `darwin-buildpackage` | `[--dir] [--target T] <source> <repository> <dstdir>` |
| `buildall` | `darwin-buildall` | `<srclist> <repository> <dstdir>` |
| `missing` | `darwin-missing` | `<srclist> <dstdir>` |

The `<repository>` argument expands to the ordered search list `[dstdir, seeddir]`
(as the Perl builds `[$dstdir, $seeddir]`).

## Module decomposition (C89)

| Module | Responsibility | Ports from |
|---|---|---|
| `main.c` | subcommand dispatch, argument parsing, usage | the three `.pl` scripts |
| `strutil.c/.h` | dynamic string buffer (`sbuf`), string list (`strlist`), `split`/`chomp`/`lowercase`/`trim`, filename glob-match | Perl string & regex idioms |
| `package.c/.h` | `Package` struct, control-text parse/unparse, `canon_version`, `canon_name` | `Package.pm` |
| `manifest.c/.h` | read a srclist file **or** a directory → list of `{type, source, targets}` | `Manifest.pm` |
| `exec.c/.h` | run an argv subprocess, `checkret` (decode wait status), `printcmd`, dry-run gate | Perl `system()` / backtick / `checkret` |
| `builder.c/.h` | the engine: `scan` (dir), `getparams`, `canonparams`, `chrootparams`, `buildflags`/`buildcmd`, `setupdirs`, `makeroot`, `build`, `exists`, `resolve_dependency`, object harvest | `Builder.pm` |
| `pkginfo.c/.h` | write apk `.PKGINFO` from a `Package`; assemble `.apk` via `tar` + `gzip` | replaces `dpkg-deb --build` |

### Data structures

The Perl `$package` and `$params` hashes use a **finite, known** set of keys, so
they become plain C structs rather than a general hashmap:

- `Package` struct fields: `package`, `version`, `architecture`, `source`,
  `description`, `maintainer`, `provides`, `conflicts`, `replaces`, `revision`,
  `package_revision`, and `build_depends` (a `strlist`). Absent/optional fields
  are represented by `NULL` (mirrors Perl `defined`).
- `params` struct fields (all path strings): `BUILDROOT`, `SRCROOT`, `OBJROOT`,
  `SYMROOT`, `DSTROOT`, `HDRROOT`, `LIBCOBJROOT`, `LOGFILE`, `SUBLIBROOTS`,
  `PACKAGEROOT`, `SRCDIR`, `PACKAGEDIR`.
- `sbuf`: `{ char *buf; size_t len; size_t cap; }` with append operations.
- `strlist`: `{ char **items; size_t count; size_t cap; }`.
- Build command flags are assembled as a `strlist` of `KEY=VALUE` strings.

## Data flow

**`buildpackage`:**
1. Parse args → `scan(dir, source)` reads `source/dpkg/control` (or synthesizes a
   default control), derives name/version via `dir2name`, and computes `params`.
2. `build()`:
   - Short-circuit if the target `.apk` already exists in `dstdir`.
   - `chrootparams` (prefix roots with the buildroot), `canonparams` (make paths
     absolute against cwd).
   - `setupdirs`: `mkdir -p` the roots; `makeroot` resolves + extracts build-deps
     into the buildroot (via `apk` / extraction); `rsync` the source into
     `SRCROOT`, excluding version-control metadata (`CVS/`, `.svn/`, `.git/`).
   - `chroot BUILDROOT make -w -C SRCROOT <flags> installhdrs` (for
     `all`/`headers`) and `… install` (for `all`/`binary`), with
     `UNAME_SYSNAME=Rhapsody` and a fixed `PATH` in the environment.
   - Object harvest: find `dynamic_obj` under `OBJROOT`, copy into
     `LIBCOBJROOT/usr/local/lib/objs/...`.
   - Package: for each of `headers` / `binary` / `objects`, write `.PKGINFO` and
     assemble the `.apk` (see apk mapping). `local` is a no-op (preserved).
   - Optional `clean` removes the buildroot.

**`buildall`:** read manifest → for each entry `scan` → `exists(package, any, dstdir)`
→ if missing, `build(... clean=1)`, logging and continuing on per-entry failure.

**`missing`:** read manifest → for each entry `scan` → `exists(...)` → print
`must build <name>.apk using <type> <source>` for the missing ones; build nothing.

## apk mapping

### Metadata: Debian control → `.PKGINFO`

| Control field | `.PKGINFO` field | Notes |
|---|---|---|
| `Package` | `pkgname` | |
| `Version` | `pkgver` | includes the `-<revision>` suffix from `dir2name` |
| `Architecture` (`universal-apple-rhapsody`) | `arch` | |
| `Description` | `pkgdesc` | defaulted to "No description available." when absent |
| `Maintainer` | `maintainer` | defaulted to the anonymous darwin-development address |
| `Source` | `origin` | |
| `Build-Depends` | `builddepends` | custom `.PKGINFO` field (space-separated); records the build-time dependency list so the graph travels with the `.apk` |

`builddepends` is a non-standard `.PKGINFO` key — it is **not** apk's runtime
`depend` field, and apk-tools ignores keys it does not recognize, so emitting it
is safe. `rbuild`'s `makeroot` reads `builddepends` (from the source control file
and/or from a candidate dependency `.apk`'s `.PKGINFO`) to decide what to extract
into the chroot buildroot. The `build-base` meta-dependency expansion is applied
to this list as before.

### Sub-packages

Still produced as separate `.apk` files:

- `binary` → `<name>` — in dpkg it `provides`/`conflicts`/`replaces` its own
  `<name>-hdrs`. Mapped to apk `provides = <name>-hdrs` + `replaces = <name>-hdrs`.
  Early apk (2.0_pre11) has no `conflicts` field; the overlap is handled
  best-effort via matching `provides`. This mapping is documented and revisitable.
- `headers` → `<name>-hdrs` (headers only, from `HDRROOT`)
- `objects` → `<name>-obj` (harvested objects, from `LIBCOBJROOT`)
- `local` → no-op (preserved as a recognized target that produces nothing)

### Packaging step

`rbuild` writes `.PKGINFO` into the package root, then shells to `tar` + `gzip` to
assemble the `.apk`. Runtime operations — extracting build-deps into the chroot
buildroot and querying what is already installed — shell out to the `apk` binary.

### Naming and matching

- Package file name: `<pkgname>-<pkgver>.apk`.
- `exists(package, any, dstdir)` and `resolve_dependency(name, repository)` match
  `<name>-<digit…>.apk`. Requiring the version segment to **start with a digit**
  replaces the Perl's `_`-delimiter trick (`^<name>_.*\.deb$`) and prevents `foo`
  from spuriously matching `foo-hdrs-1.0.apk`.

## Preserved build machinery

Ported faithfully (behavior unchanged in spirit, only re-expressed in C):

- chroot buildroot and the `mkdir -p` of all roots
- `DSTROOT` / `OBJROOT` / `SYMROOT` / `HDRROOT` / `LIBCOBJROOT` / `PACKAGEROOT`
  layout and the `BUILDIT_DIR` / per-root environment overrides
- `RC_CFLAGS` (`-arch i386 -arch ppc` + the NeXT/Rhapsody `-D` flag list),
  `RC_ARCHS`, and the `baseflags` set
- `chroot BUILDROOT make -w -C SRCROOT <KEY=VALUE…> <target>`
- `makeroot` build-dependency resolution + install into the buildroot, including
  the `build-base` meta-dependency expansion and the `package-list` tracking file
- `rsync -avr . --exclude=CVS/ --exclude=.svn/ --exclude=.git/` source staging
  (the Perl excluded only `CVS/`; `.svn/` and `.git/` are added)
- the `dynamic_obj` object-harvest pass into `/usr/local/lib/objs`

## Error handling

- Functions return `int` status (`0` = success) and report messages to stderr;
  there is no `die`/exception mechanism.
- `buildall` mirrors the Perl `eval { build(...) }; warn $@ if $@;` — a per-package
  build failure is logged and the loop continues to the next entry.
- `buildpackage` returns `build()`'s status as its process exit code.
- Argument / usage errors print usage and exit 1.
- `checkret` decodes a child process's wait status (exit code, signal, core dump,
  stopped) into a human-readable message, matching the Perl.
- Error paths use a `goto cleanup` convention to free `sbuf` / `strlist` /
  `Package` allocations.

## Testing

### Unit tests of pure functions (`src/rbuild-1/tests/`)

A tiny assertion harness (no external framework). Covered functions:

- `dir2name` (base / name / revision extraction)
- `pkgname` (underscore→hyphen, lowercasing, `appkit`→`appkit-old`,
  `ssh`→`ssh1`/`ssh2` by revision)
- `canon_version` / `canon_name`
- `Package` control-text parse → unparse round-trip (including continuation lines
  and `Build-Depends` splitting)
- `exists` / `resolve_dependency` filename matching (including the `foo` vs
  `foo-hdrs` disambiguation)
- manifest parse (comment stripping, blank-line skipping, field splitting)
- `buildflags` output

Expected values are generated by running the existing Perl on the same inputs and
captured as fixtures.

### Command-trace comparison (`src/rbuild-1/tests/trace/`)

- A **shim directory** of fake tools (`chroot`, `make`, `dpkg-deb`, `apk`, `tar`,
  `gzip`, `mkdir`, `cp`, `rm`, `rsync`, …) that log their `argv` to a trace file
  and exit 0.
- A driver runs the **unmodified Perl** (`darwin-*`) and `rbuild` over the same
  sample manifest + source-tree fixtures with `PATH` pointed at the shim dir.
- Traces are normalized (canonicalize temporary/absolute paths; set aside the
  packaging-tool lines that legitimately differ — `dpkg-deb` vs `tar`/`gzip`/`apk`)
  and the **backend-agnostic orchestration** is diffed: the `chroot make …`
  invocations (with their flags), root creation, dependency install, and source
  staging must match.

This uses the same interception mechanism for both tools, so the legacy Perl does
not need to be modified to participate.

## Build integration

`src/rbuild-1/Makefile`, following the Rhapsody per-project convention (compare
`src/buildtools-2/Makefile`):

- Default target builds `rbuild` from the `*.c` sources.
- `install` installs `rbuild` to `$(DSTROOT)/usr/bin/rbuild`.
- `installhdrs` (no-op), `installsrc`, `clean` as in the sibling projects.
- Dev targets `test` (build + run unit tests) and `trace-test` (run the
  command-trace comparison).
- Compiled as C89 (`cc -ansi -pedantic`), POSIX libc only (`opendir`, `stat`,
  `fork`+`exec`/`system`, `getenv`). No external libraries.

The `buildtools-2` Perl remains in the tree as the reference oracle until `rbuild`
is proven out, then is retired in a follow-up.

## Out of scope

- Porting `Dpkg::Package::List`, `Dpkg::Package::Index`, `Dpkg::Archive::*`
  (unused by these three tools).
- Retiring / removing `buildtools-2` (a follow-up once `rbuild` is validated).
- Linking libapk or libarchive; adding an `abuild`-style package builder.
- Package-contents comparison and full end-to-end builds in a real Rhapsody
  chroot (not selected as a test layer).
