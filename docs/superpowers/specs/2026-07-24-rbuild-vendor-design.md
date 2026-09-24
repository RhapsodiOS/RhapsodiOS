# rbuild vendored-source design (tarball + patch series)

**Revised 2026-09-24** against rbuild as of `eb1c28351`. The original July
draft also moved package metadata from `dpkg/control` to `apk/`. That half
shipped separately under
`docs/superpowers/specs/2026-09-16-rbuild-apk-pkginfo-design.md`, which
supersedes it, so this spec now covers vendoring only.

## Goal

Let a project in `src/` carry its upstream code as a **pristine tarball plus an
ordered patch series** instead of a fully-expanded checked-in tree, so that the
RhapsodiOS delta against upstream is visible in git. rbuild extracts and patches
the tree into SRCROOT during setup; the project's existing wrapper Makefile then
builds exactly as it does today, with no knowledge of any of this.

Success = `src/zlib-1/` contains no expanded upstream tree, only
`zlib-1.1.3.tar.gz` + `patches/`, and `rbuild buildpackage --dir zlib-1 ...`
on the build box produces an APK with the same name and the same member list as
it produced before the conversion.

## Constraints and decisions

- **Tarballs are genuine upstream artifacts** (e.g. the real
  `zlib-1.1.3.tar.gz`), not snapshots we generate. Their top-level directory is
  `zlib-1.1.3/`, and rbuild renames it to the name the wrapper Makefile expects.
- **The tarball covers only the upstream subtree.** The wrapper `Makefile`,
  helper scripts, and `apk/` stay as ordinary checked-in files.
- **Patches are an ordered series**, `patches/*.patch` applied in ascending
  `strcmp` order of filename (`0001-`, `0002-`, ...): byte-wise, not
  locale-dependent. There is no `series` file.
- **Declared by `apk/vendor`**, a separate file beside `apk/pkginfo`. It is not
  folded into `apk/pkginfo`, because the apk-pkginfo design requires source
  `apk/pkginfo` and packaged `.PKGINFO` to share one key set, and vendor keys
  would be source-only. No `Manifest` change.
- **Extraction uses the toolchain's `tar` and `gzip`**, through the same
  pipeline and the same pax fallback that dependency APKs use. It does **not**
  use `apk_extract()`. That path always runs `validate_artifact()`, which
  requires POSIX `ustar\0` magic (`apk.c:383`) and is tested to reject
  old-GNU headers (`test_rejects_oldgnu_header_layout`). Upstream tarballs from
  this era are GNU tar archives.
- **rbuild runs `patch` from PATH, host-side**, with no toolchain-profile key.
  `toolchain_load()` rejects unknown keys, and a new key would mean editing all
  three profiles for a tool that has one sensible value.
- **Everything happens in `builder_setupdirs()`**, which every build command
  reaches through `builder_build()` (`buildpackage`, `buildall`, `bootstrap`,
  `bootstrap-universal`, `kernel`, `kerneldrivers`). It runs on the host in
  both chroot and bootstrap builds.
- **No shell strings.** rbuild has moved to argv vectors and C pipelines;
  nothing in it calls `sh -c` any more. The new code follows suit.

## Ground truth from the current source

- `builder_setupdirs()` (`builder.c:1057`) starts by `rmtree`ing SRCROOT and
  every other root. **Every build therefore starts from an empty SRCROOT**, so
  vendoring needs no idempotence logic of its own.
- It then runs the toolchain's `rsync` (default `rsync`) as an argv vector:
  `rsync -avr SRCDIR/ --exclude=CVS/ --exclude=.svn/ --exclude=.git/
  --exclude=.hg/ SRCROOT`. Because the source ends in `/`, a leading-`/`
  exclude pattern anchors at the project root.
- `apk.c` has a static `tar_pipeline(fd, root, list_only, tc)` that runs
  `gzip -dc` into either `tar -C root -xf -` or, for the `pax` fallback,
  `chdir(root); pax -r`. `apk_use_arch()` substitutes `tar = "pax"`,
  `gzip = "gzip"` when no toolchain is given. All three shipped profiles set
  `tar = /build/src/rbuild-1/pax-gnutar.sh`, which accepts `-C ROOT -xf -`.
- `tar_pipeline()` is not dry-run aware. Its callers print a line such as
  `validate APK ...` and return early.
- GNU patch 2.5 (`src/patch-1`) sets `backup_if_mismatch = !posixly_correct`
  (`patch.c:132`), so **by default it writes `.orig` files next to any hunk
  applied with offset or fuzz**. Those would land in SRCROOT and could be
  installed by Makefiles that copy directories. `--no-backup-if-mismatch`
  (`patch.c:498`) turns that off. `-f` stops it asking questions: `ask()`
  opens `/dev/tty` whenever stdout is a terminal (`util.c:583`), which would
  hang an interactive SSH build. `-E` removes files a patch empties: patch 2.5
  does not otherwise delete a file that a `diff -N` hunk removes. `-i` names
  the patch file, so no stdin redirect and no shell are needed.
- `patch-cmds` is now in `basedeps` (`builder.c`) and in
  `BootstrapManifest`. Patching still runs on the **host**, though, so the
  box's own `patch` is the one that matters.
- `src/zlib` is now `src/zlib-1` (commit `96dfea6e0`). `builder_dir2name()`
  turns the `-1` suffix into a revision, so the package version is
  `1.1.3-1`. `zlib-1/Makefile` still sets `Project = zlib`, so GNUSource.make
  resolves `Sources = $(SRCROOT)/zlib`.
- `.gitattributes` applies `* text=auto eol=lf`. All 102 files of the current
  `src/zlib-1/zlib` tree are LF in the index and the worktree, and `*.gz` is
  already `binary`. **A `.patch` file is text under this rule**, so any CR byte
  inside a hunk would be stripped on commit and the patch would stop applying.

## Project layout after conversion

```
src/zlib-1/
  Makefile                 unchanged
  apk/pkginfo              unchanged
  apk/vendor               NEW vendor descriptor
  zlib-1.1.3.tar.gz        NEW pristine upstream tarball
  patches/
    0001-rhapsody-port.patch
  zlib/                    DELETED from git; materialized at build time
```

## `apk/vendor`

Same syntax as `apk/pkginfo`: one `key = value` per line, blank lines and `#`
comments skipped, value is everything after the first `=`, trimmed. Both files
are parsed by one shared helper, `str_parse_kv()`, which `pkginfo_read()` is
switched over to, so the two can never disagree about syntax.

```
tarball = zlib-1.1.3.tar.gz
directory = zlib
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `tarball` | yes | — | path relative to the project dir |
| `directory` | yes | — | name the extracted tree gets in SRCROOT |
| `patches` | no | `patches` | directory relative to the project dir |
| `patchlevel` | no | `1` | `-p` level passed to `patch` |

Unknown keys are ignored, matching `pkginfo_read()`.

## Components

| Module | Change |
|---|---|
| `strutil.c/.h` | `str_parse_kv(char *line, char **key, char **val)`, the one `key = value` splitter. `pkginfo_read()` switches to it; its behavior is unchanged. |
| `apk.c/.h` | `apk_untar(path, root, tc)`: extracts a gzipped tar with the toolchain tools, or the pax fallback, **without** APK validation. It wraps the existing `tar_pipeline()`. In dry-run it prints `extract <path> into <root>` and returns 0. |
| `vendor.c/.h` (new) | `Vendor` struct; `vendor_path`, `vendor_read`, `vendor_free`, `vendor_list_patches`, `vendor_apply`. It knows nothing about `Package` or `Params`: `vendor_apply(v, srcdir, srcroot, tc)` takes two paths and a toolchain. |
| `builder.c` | `builder_setupdirs()` reads `apk/vendor` if present, adds anchored rsync excludes, and calls `vendor_apply()` after the rsync. |
| `Makefile` | `vendor.o` in `OBJS`, `test_builder_OBJS`, and `test_runner_OBJS`; new `tests/test_vendor`. |
| `.gitattributes` | `src/*/patches/*.patch -text`, so patch bytes are stored exactly. |
| `README.md` | Document `apk/vendor` and the `patch` runtime dependency. |

## Data flow

In `builder_setupdirs()`, after the existing wipe, mkdir, and makeroot steps:

1. If `<SRCDIR>/apk/vendor` exists, read it. A parse error fails the build.
2. rsync `SRCDIR/` → `SRCROOT` as today, plus `--exclude=/<tarball>` and
   `--exclude=/<patches>/` when vendored. The patterns are **anchored**, so
   an upstream-style `patches/` directory deeper in a project is not
   excluded (compare `src/ntp-1/ntp/patches`).
3. Then `vendor_apply(v, SRCDIR, SRCROOT, opt->toolchain)`:
   1. Fail if `<SRCDIR>/<tarball>` is missing.
   2. Collect the patch list. Fail if an explicitly configured `patches` dir
      is missing. A missing default `patches/` means no patches.
   3. Fail if `<SRCROOT>/<directory>` already exists. That means the project
      still has its expanded tree checked in alongside `apk/vendor`: a
      half-finished conversion that would otherwise be silently overwritten.
   4. `mkdir <SRCROOT>/.vendor-tmp` and
      `apk_untar(<SRCDIR>/<tarball>, <SRCROOT>/.vendor-tmp, tc)`. SRCROOT was
      wiped at the start of setup, so no stale scratch directory can exist.
   5. Require exactly one top-level entry, then
      `mv <tmp>/<entry> <SRCROOT>/<directory>` and `rmdir <tmp>`. Tarbombs are
      rejected.
   6. For each patch in order:
      `patch -f -E --no-backup-if-mismatch -p<level> -d <SRCROOT>/<directory> -i <patch>`.
      Patches are read from SRCDIR, since step 2 kept them out of SRCROOT.

Then `builder_build()` runs `make` exactly as today.

In dry-run, rsync, `mkdir`, `rmdir`, and `patch` print through
`exec_run`. `apk_untar` prints its own line. Steps 3.3 and 3.5 are skipped,
because nothing was extracted, and the rename prints as
`rename sole entry of <tmp> to <dest>`.

## Error handling

Each of these fails the current project's build with a message naming the
path. `run_manifest()` already logs the failure and continues with the next
project.

- `apk/vendor` unreadable, or missing `tarball` or `directory`.
- Tarball not found.
- Explicitly configured patch directory not found.
- Expanded tree already present in SRCROOT (half-finished conversion).
- Extraction failure (`gzip` or `tar` non-zero).
- Tarball does not hold exactly one top-level entry.
- Any `patch` non-zero exit, naming the patch file. If `patch` is not on PATH,
  `exec_run` already prints `exec "patch" failed`.

## Patch generation and line endings

Patches are generated on the Windows host with GNU diff from Git Bash:
`diff -urN --strip-trailing-cr <upstream> <ours>`. The git tree is LF-only
after `eol=lf` normalization, while upstream archives may carry CRLF in
DOS/Windows build files. `--strip-trailing-cr` keeps line-ending-only noise out
of the series. If a real hunk touches a CRLF upstream file, the generated
context will not match and the verification step fails loudly; handle that case
by hand. `src/*/patches/*.patch -text` makes sure whatever is committed is
exactly what was generated.

## Testing

No C compiler exists on the Windows host. All `make test` runs happen on the
Rhapsody build box, in a private build root under `/build/rbuild-vendor`, over
**one SSH session at a time**.

- `tests/test_strutil.c`: `str_parse_kv` cases. The existing
  `tests/test_pkginfo.c` must still pass unchanged after the switch-over.
- `tests/test_apk.c`: `apk_untar` extracts an **old-GNU** archive, the one
  `apk_validate` rejects, and fails on a missing file.
- `tests/test_vendor.c` (new): descriptor parsing and defaults, sorted patch
  enumeration, and `vendor_apply` end to end. That covers rename, patch applied,
  a file deleted by `-E`, no `.orig` left behind, tarbomb rejected, bad patch
  rejected, and pre-existing directory rejected.
- `tests/test_builder.c`: `builder_setupdirs` on a vendored project with
  `bootstrap = 1`. The tree is materialized, the tarball and patch dir are
  absent from SRCROOT, and a nested `patches/` elsewhere is still copied.
- `make trace-test` is unaffected: its fixtures have no `apk/vendor`.

## Scope

In scope: rbuild vendoring support, the `.gitattributes` rule, README, and
`zlib-1` converted end to end.

Out of scope: converting other projects; multiple tarballs per project;
checksum verification (git already hashes the tarball); downloading; tarbomb
support; a toolchain-profile `patch` key.
