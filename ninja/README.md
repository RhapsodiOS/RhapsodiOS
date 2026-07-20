# Ninja / samurai build for RhapsodiOS

This directory contains a `ninja`-based build orchestrator driven by
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
built, *in what order*, and *in parallel*. There is **no chroot** — everything
installs into a single shared `DSTROOT`. Runtime packaging uses **apk** (see
the packaging section below).

## Components

| File | Purpose |
|------|---------|
| `rhap-build` | Multi-command tool: generate `build.ninja`, run `samu`, build `.apk` archives, index repos, and batch-publish packages. Built from `rhap-build.c`, `generate.c`, `mkapk.c`, `index.c`, `util.c`. |
| `buildproj.sh` | Per-project build wrapper. Stages sources, runs `installhdrs` / `install`. On `install`, stages into a private pkgroot, merges into `DSTROOT`, and calls `rhap-build mkapk` to write an `.apk` into `APKREPO`. |
| `Makefile` | Builds the vendored `samu` and `rhap-build`, regenerates `build.ninja`; convenience `world` / `kernel` targets. |
| `samurai/` | Vendored [samurai](https://github.com/michaelforney/samurai) source (the `samu` ninja-compatible build tool). Built with its own POSIX `Makefile`. |

## Quick start

```sh
# From the repo root: build samu + rhap-build, generate build.ninja, build all:
make -C ninja world      # builds ninja/samurai/samu, generates ../build.ninja,
                         # then runs `samu buildworld`
make -C ninja kernel     # ...or just the kernel

# Or do the steps by hand:
make -C ninja samu       # build the vendored samurai -> ninja/samurai/samu
make -C ninja generate   # write ../build.ninja
samu buildworld
```

By default the `Makefile` uses the vendored `ninja/samurai/samu`. To use an
external `samu` (or ninja) instead, override `SAMU`:

```sh
make -C ninja world SAMU=/usr/local/bin/samu
```

Build a single project (by its directory name) with the convenience alias
(run from the repo root, after `make -C ninja generate`):

```sh
samu zlib
samu Commands/adv_cmds
```

Headers-only for a project:

```sh
samu /tmp/rhapsody/obj/.stamps/zlib.hdrs.stamp
```

## rhap-build commands

`rhap-build` is the single entry point for graph generation, packaging, and
convenience builds:

| Command | Purpose |
|---------|---------|
| `generate [opts…]` | Write `build.ninja` (same flags as below). |
| `build [opts…] [--samu PATH] [target …]` | Regenerate, then run `samu` (default target: `buildworld`). |
| `mkapk <PKGINFO> <staging-root> <out.apk>` | Build one `.apk` archive. |
| `index <repo-dir>` | Write `APK_INDEX.gz` for a repo directory. |
| `publish <repo-dir> <PKGINFO> <staging-root> […]` | Package one or more stage trees, then index the repo. |

Without a command, `rhap-build` generates `build.ninja` and prints build hints.

```sh
make -C ninja rhap-build
ninja/rhap-build generate --srcroot src
ninja/rhap-build build buildworld
ninja/rhap-build mkapk path/to/PKGINFO /stage/root out.apk
ninja/rhap-build index /tmp/rhapsody/apk
```

## Configuration

`rhap-build generate` reads options from the command line (or same-named
environment variables). Defaults in brackets:

| Option | Env | Default | Meaning |
|--------|-----|---------|---------|
| `--srcroot`  | `SRCROOT`  | `src` | source tree root (project sources live under `src/`) |
| `--dstroot`  | `DSTROOT`  | `/tmp/rhapsody/dst` | shared install/staging tree |
| `--objroot`  | `OBJROOT`  | `/tmp/rhapsody/obj` | per-project object roots base |
| `--symroot`  | `SYMROOT`  | `/tmp/rhapsody/sym` | per-project symbol roots base |
| `--srcbase`  | `SRCBASE`  | `/tmp/rhapsody/src` | per-project staged source roots base |
| `--toolroot` | `TOOLROOT` | `= dstroot` | staged toolchain prefix (`MAKEFILEPATH`, `PATH`) |
| `--apkrepo`  | `APKREPO`  | `/tmp/rhapsody/apk` | directory for generated `.apk` files + `APK_INDEX.gz` |
| `--rc-archs` | `RC_ARCHS` | `ppc i386` | target architectures |
| `--rc-os`    | `RC_OS`    | `teflon` | `RC_OS` value |
| `--wrapper`  | `WRAPPER`  | `ninja/buildproj.sh` | per-project wrapper path |
| `-o`/`--out` |            | `build.ninja` | output file |

Regenerate `build.ninja` whenever projects are added/removed or their
build dependencies change.

### Environment variables

| Variable | Used by | Meaning |
|----------|---------|---------|
| `APKREPO` | `buildproj.sh`, `generate` | Directory for `.apk` outputs and `APK_INDEX.gz` (default: parent of `DSTROOT` + `/apk`). |
| `SKIP_APK=1` | `buildproj.sh` | Skip `.apk` creation after `install` (install/merge still run). |
| `RHAP_BUILD` | `buildproj.sh`, tests | Path to the `rhap-build` binary (default: `ninja/rhap-build` next to `buildproj.sh`). |
| `SAMU` | `Makefile`, `rhap-build build` | Path to the `samu` (or ninja) executable. |

## Project discovery

A project is any directory under `--srcroot` that contains **`apk/PKGINFO`**.

From `apk/PKGINFO`, `rhap-build generate` reads:

| Key | Meaning |
|-----|---------|
| `pkgname` | Package name (required) |
| `builddepend` | Build dependencies (space-separated; commas also accepted) |
| `arch` | Architecture (optional; values containing `i386` / `ppc` select that arch) |

## How the graph is built

For every project (a directory containing `apk/PKGINFO`)
the generator emits **two** nodes:

* `<project>.hdrs.stamp` - runs `make installhdrs` (installs public headers into `DSTROOT`).
* `<project>.full.stamp` - runs `make install` into a **private pkgroot**, merges that tree into `DSTROOT`, then runs `rhap-build mkapk` to write `$APKREPO/<pkgname>-<pkgver>.apk`. Rebuilds when `apk/PKGINFO` changes.

`buildworld` also builds `apkindex`, which regenerates `$APKREPO/APK_INDEX.gz` after all packages succeed. Set `SKIP_APK=1` in the environment to skip `.apk` creation (install/merge still run).

Dependencies from `builddepend` are mapped as follows:

* `foo-hdrs` -> depend on `foo.hdrs.stamp` (headers only)
* `foo` or `foo-obj` -> depend on `foo.full.stamp`
* `build-base` -> depend on the `build-base` aggregate (the base toolchain)
* an unknown dependency (no project provides it) -> **warned and skipped**

Splitting headers from full builds is what keeps the graph acyclic: e.g.
`kernel-hdrs` can be satisfied by the cheap `make installhdrs` long before the
full kernel is built, so header cycles between libraries never force a
full-build cycle.

### The bootstrap set (`build-base`)

`build-base` expands to the base toolchain: `cc`, `cctools`, `gnumake`, the
three makefile packages, the base shells/tools, `libsystem`, `libc`,
`architecture`, `kernel`, `csu`, `objc4`, `files`, and the `*-cmds` base
commands.

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

`rhap-build generate` still runs a full cycle check over the graph and prints
any cycle it finds (they are emitted as order-only edges so the build can still
proceed).

## Host assumptions

The generator is portable POSIX C (`dirent.h`, `sys/stat.h`) and can run on any
POSIX host (Rhapsody/Darwin, macOS, Linux). The **build itself** currently
assumes a native Rhapsody/Darwin host:

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

## Packaging with apk

After a project is built into a staging tree, package it with Alpine-style
`.apk` archives and an `APK_INDEX.gz` so the same repo can be used from install
media or over the network. (apk-tools 2.0_pre11 uses `APK_INDEX.gz`, not the
modern `APKINDEX.tar.gz` name.)

**Repo layout.** Publish under `$REPO/rhapsody/$ARCH/` (for example
`/media/apk/rhapsody/ppc/` or a directory you later serve over HTTP). Each
architecture directory holds `*.apk` packages and `APK_INDEX.gz`.

**Automatic packages.** A successful `make install` for each project produces an
`.apk` under `$APKREPO` (default `/tmp/rhapsody/apk`). After `buildworld`,
`samu apkindex` (included in `buildworld`) rebuilds `APK_INDEX.gz`.

**Manual packaging.**

* `ninja/rhap-build mkapk <PKGINFO> <staging-root> <out.apk>` — build one package.
* `ninja/rhap-build index <repo-dir>` — write `APK_INDEX.gz` for a repo dir.
* `ninja/rhap-build publish <repo-dir> <pkginfo> <stage-root> [...]` — batch
  helper for packaging arbitrary stage trees.

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

For install media, copy or rsync `$APKREPO` (or a filtered subset) into the
published layout under `$REPO/rhapsody/$ARCH/`.

**Tests.** See `ninja/tests/README.md`. Set `APK=` to a built binary and ensure
`rhap-build` is built (`make -C ninja rhap-build`); scripts exit 77 if either
is unavailable.
