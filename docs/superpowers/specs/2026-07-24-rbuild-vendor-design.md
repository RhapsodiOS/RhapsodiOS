# rbuild vendored-source design (tarball + patch series, apk-native metadata)

## Goal

Let a project in `src/` carry its upstream code as a **pristine tarball plus an
ordered patch series** instead of a fully-expanded checked-in tree, so that the
RhapsodiOS delta against upstream is visible in git. rbuild extracts and patches
the tree into SRCROOT during setup; the project's existing wrapper Makefile then
builds exactly as it does today, with no knowledge of any of this.

The same change moves package metadata from `dpkg/` to an apk-native `apk/`
directory, since dpkg is on its way out.

Success = `zlib/` contains no expanded upstream tree, only
`zlib-1.1.3.tar.gz` + `patches/`, and `rbuild buildpackage --dir zlib <repo>
<dst>` produces the same `zlib-1.1.3.apk` it produces today.

## Constraints and decisions

- **Tarballs are genuine upstream artifacts** (e.g. the real
  `zlib-1.1.3.tar.gz`), not snapshots we generate. Provenance is the point, so
  the tarball's top-level directory is `zlib-1.1.3/` and rbuild must rename it
  to the name the wrapper Makefile expects.
- **The tarball covers only the upstream subtree.** The wrapper `Makefile`,
  helper scripts, and package metadata stay as ordinary checked-in files.
- **Patches are an ordered series**, `patches/*.patch` applied in ascending
  `strcmp` order of filename (`0001-`, `0002-`, ...) — byte-wise, not
  locale-dependent. No `series` file: the order is implicit and there is
  nothing to keep in sync.
- **Declared by a project-local descriptor**, `apk/vendor`. No `Manifest`
  change, so a project converts by adding one file, and directory-style
  manifests keep working (`manifest_read` on a directory synthesizes type
  `dir` for every child, so anything keyed off the manifest type would
  silently skip vendoring there).
- **rbuild shells out to `patch`**, as it already does to `tar`, `gzip`,
  `rsync`, and `chroot`. No built-in diff applier.
- **Extraction and patching run host-side**, in `builder_setupdirs`, before any
  `make`. That is true for both chroot (`buildall`) and native (`bootstrap`)
  builds, since `builder_setupdirs` always runs on the host.
- **`gzip -dc | tar -xf -`**, never `tar -z`: Rhapsody's tar has no `-z`, and
  the in-tree GNU tar predates `--strip-components`.
- **apk metadata is opt-in per project.** rbuild prefers `apk/`, falls back to
  `dpkg/`. The 82 projects with `dpkg/control` keep working untouched; `dpkg/`
  support is deleted once the last one is converted.

## Ground truth from sources

- `src/rbuild-1/builder.c` `builder_setupdirs()` rsyncs `SRCDIR` → `SRCROOT`
  on the host, then `builder_build()` runs `make -C SRCROOT`. Patching belongs
  at the end of `builder_setupdirs`.
- `builder_scan_dir()` reads `<source>/dpkg/control`; on failure it synthesizes
  defaults via `makecontrol()`. It then force-overrides `architecture` to
  `universal-apple-rhapsody` and `source` to the directory basename, so those
  fields are not honored from the input file today and will not be tomorrow.
- `builder_buildpackage()` copies `dpkg/{conffiles,preinst,postinst,prerm,postrm}`
  into the package root under those names.
- `src/apk-tools-1/apk-tools/src/package.c:234` lists apk's script names:
  `pre-install`, `post-install`, `pre-deinstall`, `post-deinstall`,
  `pre-upgrade`, `post-upgrade`. `database.c:1053` matches them via
  `apk_script_type(&ae->name[1])`, so archive entries must be **dotted** at the
  package root (`.pre-install`), alongside `.PKGINFO`.
  **The dpkg names rbuild emits today are therefore never executed by apk.**
- apk has no `conffiles` concept; it writes `.apk-new` for locally-modified
  files automatically.
- Survey of the tree: 82 projects have `dpkg/`, all containing only `control`,
  except `files-5` (`conffiles`, `preinst`, `postinst`) and two inert strays
  (`objc-1/dpkg/status`, `rcs-1/dpkg/status`, which rbuild never reads).
- Only `OpenSSH` and `zlib` have continuation lines in `control` (both in
  `Description`). `package_parse` folds these into the value as `"\n "`, and
  `pkginfo_write` then emits a `pkgdesc = ...` spanning multiple physical
  lines, which apk's `.PKGINFO` line parser cannot read. Moving to a
  single-line `pkgdesc` fixes an existing latent bug.
- `patch-cmds` (GNU patch 2.5, `src/patch-1`) is in `Manifest` but **not** in
  `BootstrapManifest`.

## Project layout after conversion

```
src/zlib/
  Makefile                 unchanged
  apk/pkginfo              metadata (replaces dpkg/control)
  apk/vendor               vendor descriptor
  zlib-1.1.3.tar.gz        pristine upstream tarball
  patches/
    0001-apple-rhapsody-port.patch
    0002-....patch
  zlib/                    DELETED from git; materialized at build time
```

`zlib/Makefile` sets `Project = zlib`, so GNUSource.make resolves
`Sources = $(SRCROOT)/zlib` — which is exactly the `directory` the descriptor
names. The Makefile is not modified.

## File formats

Both new files use apk's `.PKGINFO` syntax — one `key = value` per line, blank
lines and `#` comments skipped, value is everything after the first `=`,
trimmed, no continuation lines. One shared line-splitter in `strutil`.

### `apk/pkginfo`

```
pkgname = zlib
pkgver = 1.1.3
pkgdesc = Zip library
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
builddepends = build-base
url = http://www.cdrom.com/pub/infozip/zlib/
```

| Key | Required | Notes |
|---|---|---|
| `pkgname` | yes | hard error if absent |
| `pkgver` | yes | hard error if absent |
| `pkgdesc` | no | defaults to `No description available.` |
| `maintainer` | no | defaults to the existing anonymous address |
| `builddepends` | no | split on space **or** comma, so pasted `Build-Depends` values work |
| `provides`, `replaces` | no | passed through |
| anything else | — | ignored, so `url =` / `vendor =` survive as documentation |

`arch` and `origin` are ignored on input; rbuild computes them, exactly as
`readcontrol()` force-overrides them today.

### `apk/vendor`

```
tarball = zlib-1.1.3.tar.gz
directory = zlib
patches = patches
patchlevel = 1
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `tarball` | yes | — | path relative to the project dir |
| `directory` | yes | — | name the extracted tree gets in SRCROOT |
| `patches` | no | `patches` | directory relative to the project dir |
| `patchlevel` | no | `1` | `-p` level passed to `patch` |

## Components

| Module | Change |
|---|---|
| `strutil.c/.h` | `str_parse_kv(char *line, char **key, char **val)` — splits one `key = value` line, returns 0 on a skippable (blank/comment) line. Shared by the two readers below. |
| `pkginfo.c/.h` | `int pkginfo_read(Package *p, const char *path)` — reader matching the existing `pkginfo_write`. Returns 0 on success, non-zero on a missing file or a missing required key, matching the codebase's existing convention. |
| `vendor.c/.h` (new) | `Vendor` struct + `vendor_read()` / `vendor_free()`; `vendor_apply()` performs extract + rename + patch. Same 0/non-zero convention. |
| `builder.c` | `builder_metadir()` resolves `apk/` vs `dpkg/` once per project; `builder_scan_dir()` uses it to choose reader; `builder_setupdirs()` calls `vendor_apply()` after the rsync; `builder_buildpackage()` emits apk-named dotted scripts. |
| `Makefile` | new objects and the two new test binaries. |

`vendor.c` owns everything tarball- and patch-related and knows nothing about
`Package` or `Params` — `vendor_apply(const Vendor *v, const char *srcdir,
const char *srcroot)` takes two paths and does its work, so it is testable
against a synthetic tarball with no build in sight.

## Data flow

`builder_setupdirs()`, in order:

1. Existing: mkdir the roots; `builder_makeroot()` (chroot builds only).
2. rsync `SRCDIR` → `SRCROOT`, now additionally excluding `<tarball>` and
   `<patches>/` when a descriptor is present, so SRCROOT holds only sources.
3. If no `apk/vendor`: done, unchanged behavior.
4. `rm -rf <SRCROOT>/<directory>` — makes re-extraction idempotent. rsync runs
   without `--delete` and SRCROOT persists across builds, so a stale patched
   tree would otherwise be patched again.
5. `rm -rf <SRCROOT>/.vendor-tmp` (a previous run may have died mid-extract),
   `mkdir <SRCROOT>/.vendor-tmp`, then
   `gzip -dc <SRCDIR>/<tarball> | tar -C <SRCROOT>/.vendor-tmp -xf -`.
6. `mv <SRCROOT>/.vendor-tmp/<sole entry> <SRCROOT>/<directory>`, then remove
   the scratch dir. This gets `zlib-1.1.3/` → `zlib/` without
   `--strip-components`.
7. For each `<SRCDIR>/<patches>/*.patch` in sorted order:
   `patch -p<patchlevel> -d <SRCROOT>/<directory> < <patchfile>`.
   Patches are read from SRCDIR, not SRCROOT, because step 2 excluded them.

Then `builder_build()` runs `make -C SRCROOT installhdrs/install` as today.

All steps go through `exec`, so `-n/--dry-run` prints the whole sequence.

## Metadata resolution and script emission

`builder_scan_dir()`:

1. `apk/` exists → `apk/pkginfo` is **required**; missing is a hard error, not
   a silent fall-through to `dpkg/`. No split-brain metadata.
2. Else `dpkg/control` exists → parse it with `package_parse` as today.
3. Else synthesize defaults via `makecontrol()` as today.

`builder_buildpackage()` for the `binary` target reads
`<metadir>/{pre-install,post-install,pre-deinstall,post-deinstall,pre-upgrade,post-upgrade}`
and copies each present one to `<dstroot>/.<name>`, mode 755. The dpkg names
and `conffiles` are no longer read. Projects still on `dpkg/` therefore stop
emitting their (already-inert) dpkg-named scripts; only `files-5` is affected,
and it is converted in this change.

## Error handling

Each of these aborts the current project's build with a message naming the
offending path. `run_manifest()` already logs and continues to the next
project, so one bad vendored project does not stop a `buildall`.

- `apk/` present but `apk/pkginfo` missing.
- `pkgname` or `pkgver` missing from `apk/pkginfo`.
- `tarball` or `directory` missing from `apk/vendor`.
- Tarball file not found.
- `gzip`/`tar` non-zero exit.
- Scratch dir does not contain exactly one top-level entry. Tarbombs are
  explicitly unsupported; the message says so.
- `patches` explicitly configured but the directory does not exist. An absent
  *default* `patches/` is fine and means "no patches".
- Any `patch` non-zero exit, naming the patch file.
- `patch` not found on PATH — message names `patch-cmds`.

## Constraint: patch availability at bootstrap

Patching runs host-side, so the guest running rbuild needs `/usr/bin/patch`.
`patch-cmds` is in `Manifest` but not `BootstrapManifest`. **No project in the
stage-0 bootstrap set may be vendored** until either the guest is confirmed to
ship `patch` or `patch-1` is added to `BootstrapManifest`. Neither `zlib` nor
`files-5` is in `BootstrapManifest`, so this change is unaffected.

## Testing

Following the existing `/tmp` fixture style in `tests/test_builder.c`:

- `tests/test_pkginfo.c` (extend): `pkginfo_read` → `pkginfo_write` round trip;
  missing `pkgname`/`pkgver` errors; comments and blank lines; unknown keys
  ignored; `builddepends` with both separators.
- `tests/test_vendor.c` (new): descriptor parsing, defaults for `patches` and
  `patchlevel`, missing-required-key errors, patch-file sort order, and
  `vendor_apply()` end to end against a synthetic tarball plus a one-hunk patch
  built in `/tmp`.
- `tests/test_builder.c` (extend): `builder_metadir()` prefers `apk/` over
  `dpkg/`; `builder_scan_dir()` errors when `apk/` lacks `pkginfo`.
- `Makefile`: add `vendor.o` to `OBJS`, `tests/test_vendor` to `TESTS`, and the
  matching per-test object list.
- `make trace-test` is unaffected — the Perl oracle has no equivalent behavior.

Manual verification of the pilot:

1. `rbuild -n buildpackage --dir zlib <repo> <dst>` shows extract, rename, and
   patch commands in the trace.
2. A real build produces `zlib-1.1.3.apk`.
3. The produced apk's file list matches one built from the pre-conversion tree.

## Scope of this change

In scope:

- rbuild: `apk/vendor` support, `apk/pkginfo` reader, `apk/` metadata
  resolution, apk-native dotted scripts.
- `zlib` converted end to end: pristine `zlib-1.1.3.tar.gz`, patch series
  capturing Apple's Rhapsody delta, `apk/pkginfo` + `apk/vendor`, expanded
  `zlib/zlib/` removed from git.
- `files-5` metadata converted to `apk/pkginfo`, `preinst`/`postinst` renamed
  to `pre-install`/`post-install`, `conffiles` deleted. Its scripts take no
  arguments (umount `/dev` and `rm -f /dev/*`; remount `fdesc`), so they port
  verbatim under apk's `execle(fn, "pre-install", version, "", NULL)` calling
  convention. **Consequence: these scripts will begin running on install,
  which they never have under the dpkg names.**

Out of scope:

- Converting the other 80 projects. They stay on `dpkg/control`, which keeps
  working.
- Removing `dpkg/` support from rbuild. That happens after the last project
  migrates.
- Multiple tarballs per project, checksum verification (git already checksums
  the tarball), tarball downloading, and tarbomb support.
