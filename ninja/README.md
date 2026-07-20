# Ninja / samurai build for RhapsodiOS

This directory contains a modern, `ninja`-based replacement for the old
Perl + dpkg build orchestration (`darwin-buildall` / `darwin-buildpackage` /
`Dpkg::Package::Builder` in `buildtools-2`). It is driven by
[samurai](https://github.com/michaelforney/samurai) (`samu`), a small C
implementation of ninja, whose source is **vendored in `ninja/samurai/`** so
no separate checkout or install is required.

The project sources live under **`src/`** at the repo root; this `ninja/`
directory stays at the top level and generates `build.ninja` at the repo root
(so paths and the `ninja/buildproj.sh` wrapper resolve relative to it, with
`--srcroot src`).

It replaces **only the orchestration layer**. Each project is still built by
its existing Apple/NeXT make framework (`pb_makefiles`, `CoreOSMakefiles`,
`project_makefiles`, `configure`); the ninja graph just decides *what* gets
built, *in what order*, and *in parallel*. There is **no `.deb` packaging and
no chroot** - everything installs into a single shared `DSTROOT`.

## Components

| File | Purpose |
|------|---------|
| `genninja.c` | Generator. Scans the tree for `*/apk/PKGINFO` (preferred) or `*/dpkg/control`, parses package metadata, computes the dependency DAG, and writes `build.ninja`. |
| `buildproj.sh` | Per-project build wrapper invoked by every ninja edge. Stages sources (`make installsrc`), then runs `make installhdrs` / `make install` with the `RC_*` flags, into the shared `DSTROOT`. |
| `Makefile` | Builds the vendored `samu` and `genninja`, regenerates `build.ninja`; convenience `world` / `kernel` targets. |
| `samurai/` | Vendored [samurai](https://github.com/michaelforney/samurai) source (the `samu` ninja-compatible build tool). Built with its own POSIX `Makefile`. |

## Quick start

```sh
# From the repo root: build samu + genninja, generate build.ninja, build all:
make -C ninja world      # builds ninja/samurai/samu, generates ../build.ninja,
                         # then runs `samu buildworld`
make -C ninja kernel     # ...or just the kernel

# Or do the steps by hand:
make -C ninja samu       # build the vendored samurai -> ninja/samurai/samu
make -C ninja generate   # write ../build.ninja
ninja/samurai/samu buildworld
```

By default the `Makefile` uses the vendored `ninja/samurai/samu`. To use an
external `samu` (or ninja) instead, override `SAMU`:

```sh
make -C ninja world SAMU=/usr/local/bin/samu
```

Build a single project (by its directory name) with the convenience alias
(run from the repo root, after `make -C ninja generate`):

```sh
ninja/samurai/samu zlib
ninja/samurai/samu Commands/adv_cmds
```

Headers-only for a project:

```sh
ninja/samurai/samu /tmp/rhapsody/obj/.stamps/zlib.hdrs.stamp
```

## Configuration

`genninja` reads options from the command line (or same-named environment
variables). Defaults in brackets:

| Option | Env | Default | Meaning |
|--------|-----|---------|---------|
| `--srcroot`  | `SRCROOT`  | `src` | source tree root (project sources live under `src/`) |
| `--dstroot`  | `DSTROOT`  | `/tmp/rhapsody/dst` | shared install/staging tree |
| `--objroot`  | `OBJROOT`  | `/tmp/rhapsody/obj` | per-project object roots base |
| `--symroot`  | `SYMROOT`  | `/tmp/rhapsody/sym` | per-project symbol roots base |
| `--srcbase`  | `SRCBASE`  | `/tmp/rhapsody/src` | per-project staged source roots base |
| `--toolroot` | `TOOLROOT` | `= dstroot` | staged toolchain prefix (`MAKEFILEPATH`, `PATH`) |
| `--rc-archs` | `RC_ARCHS` | `ppc i386` | target architectures |
| `--rc-os`    | `RC_OS`    | `teflon` | `RC_OS` value |
| `--wrapper`  | `WRAPPER`  | `ninja/buildproj.sh` | per-project wrapper path |
| `-o`/`--out` |            | `build.ninja` | output file |

Regenerate `build.ninja` whenever projects are added/removed or their
build dependencies change.

## Project discovery

A project is any directory under `--srcroot` that contains metadata:

1. **`apk/PKGINFO`** (preferred when both exist)
2. **`dpkg/control`** (fallback during migration)

From `apk/PKGINFO`, `genninja` reads:

| Key | Meaning |
|-----|---------|
| `pkgname` | Package name (required) |
| `builddepend` | Build dependencies (space-separated; commas also accepted) |
| `arch` | Architecture (optional; same rules as dpkg `Architecture`) |

From `dpkg/control`, it still reads `Package`, `Build-Depends`, and
`Architecture`.

## How the graph is built

For every project (a directory containing `apk/PKGINFO` or `dpkg/control`)
the generator emits **two** nodes:

* `<project>.hdrs.stamp` - runs `make installhdrs` (installs public headers).
* `<project>.full.stamp` - runs `make install`; depends on its own
  `.hdrs.stamp`.

Dependencies from `builddepend` / `Build-Depends` are mapped as follows:

* `foo-hdrs` -> depend on `foo.hdrs.stamp` (headers only)
* `foo` or `foo-obj` -> depend on `foo.full.stamp`
* `build-base` -> depend on the `build-base` aggregate (the base toolchain)
* an unknown dependency (no project provides it) -> **warned and skipped**

Splitting headers from full builds is what keeps the graph acyclic: e.g.
`kernel-hdrs` can be satisfied by the cheap `make installhdrs` long before the
full kernel is built, so header cycles between libraries never force a
full-build cycle.

### The bootstrap set (`build-base`)

`build-base` expands to the base toolchain, ported from `@basedeps` in
`buildtools-2/lib/Builder.pm`: `cc`, `cctools`, `gnumake`, the three makefile
packages, the base shells/tools, `libsystem`, `libc`, `architecture`,
`kernel`, `csu`, `objc4`, `files`, and the legacy `*-cmds` base commands.

Because the original build relied on a *seed repository* of pre-built base
packages, the from-source graph would otherwise be cyclic (e.g. `gnumake`
build-depends `perl`, and everything - including `perl` - build-depends
`build-base` which contains `gnumake`). To break this cleanly:

* Bootstrap projects only depend on **other bootstrap projects** (their wider
  `Build-Depends` are assumed satisfied by the host toolchain during the
  bootstrap phase). Their internal order is a topological sort of the
  bootstrap subset, which is acyclic.
* Every non-bootstrap project depends on the `build-base` aggregate, so the
  whole base toolchain is staged into `DSTROOT` before anything else builds.

`genninja` still runs a full cycle check over the graph and prints any cycle
it finds (they are emitted as order-only edges so the build can still proceed).

## Host assumptions

The generator is portable POSIX C (`dirent.h`, `sys/stat.h`) and can run on any
POSIX host (Rhapsody/Darwin, macOS, Linux). The **build itself** currently
assumes a native Rhapsody/Darwin host, matching the old dpkg flow:

* A minimal **host bootstrap** `cc` and `make` must exist to build the base
  toolchain first (this is the classic bootstrap chicken-and-egg; the old
  system solved it with pre-built `.deb`s).
* Once the base toolchain is installed into `DSTROOT`, `buildproj.sh` points
  `MAKEFILEPATH` at `$TOOLROOT/System/Developer/Makefiles` and prepends
  `$TOOLROOT/usr/bin` to `PATH`, so later projects use the freshly built tools.
* `sh`, `make`, `cc`, and the usual base utilities are on `PATH`.

Cross-compiling from a modern host to Rhapsody is intentionally out of scope;
the design is host-agnostic where practical and documents its assumptions here.

### Building the vendored `samu` on old hosts

samurai targets POSIX.1-2008. On an old Rhapsody/Darwin host some interfaces
may be missing; pass the relevant flags to samurai's own Makefile:

```sh
# No posix_spawn -> fall back to fork/exec; no librt -> clear LDLIBS:
make -C ninja/samurai CFLAGS="-O -DNO_POSIX_SPAWN" LDLIBS=
```

The top-level `ninja/Makefile` invokes `make -C samurai`, so you can also pass
these through the environment when running `make -C ninja world`.

## Relationship to the old build system

The Perl/dpkg orchestration (`buildtools-2` tools, `dpkg-3`,
`dpkg_scriptlib-1`) is intentionally left in place during migration. Remove it
only after this flow has been validated against a dpkg-built reference.

## Packaging with apk

After a project is built into a staging tree, package it with Alpine-style
`.apk` archives and an `APK_INDEX.gz` so the same repo can be used from install
media or over the network. (apk-tools 2.0_pre11 uses `APK_INDEX.gz`, not the
modern `APKINDEX.tar.gz` name.)

**Repo layout.** Publish under `$REPO/rhapsody/$ARCH/` (for example
`/media/apk/rhapsody/ppc/` or a directory you later serve over HTTP). Each
architecture directory holds `*.apk` packages and `APK_INDEX.gz`.

**Helpers.**

* `ninja/mkapk.sh <PKGINFO> <staging-root> <out.apk>` — builds one package from
  an `apk/PKGINFO` and a staged install root.
* `ninja/publish-apk-repo.sh <repo-dir> <pkginfo> <stage-root> [...]` — runs
  `mkapk.sh` for each pair into `<repo-dir>`, then generates `APK_INDEX.gz`
  atomically (`APK_INDEX.gz.new` then `mv`) when `apk` is on `PATH` (or set
  `APK=/path/to/apk`). Pre11 `apk index` writes the index to stdout; the helper
  gzips that stream.

**Consuming the repo.** Point `apk` at the same tree via `file://` (local media
or a mounted volume) or `http://` / `https://` (a static file server of that
directory). Example:

```sh
# Local / media
apk add --repository file:///media/apk/rhapsody/ppc zlib

# Or after configuring /etc/apk/repositories with the same URL
apk update
apk add zlib
apk add -u zlib   # upgrade installed packages from the repo
```

Full packaging of the entire world build into a seed repository is follow-on
work; these helpers support incremental seeding of individual packages.

**Tests.** See `ninja/tests/README.md`. Set `APK=` to a built binary; scripts
exit 77 if apk is unavailable.
