# rhap-build unified build/packaging CLI design

**Date:** 2026-07-19  
**Status:** Approved, pending implementation  
**Supersedes:** `ninja/genninja` as the public generator name; folds apk packaging helpers into one binary

## Summary

Rename and expand the ninja graph generator into a single multi-command C tool, **`rhap-build`**, that:

1. Generates `build.ninja` (former `genninja`).
2. Optionally runs `samu` after generate (`rhap-build build`).
3. Implements apk packaging helpers in C (`mkapk`, `index`, `publish`), replacing the standalone shell scripts.

Keep **`buildproj.sh`** as the per-project ninja wrapper; it will call `rhap-build mkapk` instead of `mkapk.sh`.

## Goals

1. One user-facing binary for generate / build orchestration entry / package helpers.
2. Port `mkapk` / index / publish logic into C (no embedded shell script bodies).
3. Preserve automatic `.apk` generation after successful install and `APK_INDEX.gz` regeneration after `buildworld`.
4. Keep `samurai` (`samu`) as the build executor; do not reimplement ninja.

## Non-goals

- Porting `buildproj.sh` into C (stays shell).
- Replacing `samu` or the Apple/NeXT make project builds.
- Long-lived `genninja` compatibility binary/symlink (unless added later as a thin alias).
- Changing apk-tools itself or `PKGINFO` format.

## Decisions (from brainstorming)

| Topic | Choice |
|-------|--------|
| Scope in binary | Generator + apk helpers; **not** buildproj |
| Bare `rhap-build` | Generate `build.ninja` + print “ready” hint; **does not** run `samu` |
| `rhap-build build` | Generate, then invoke `samu` (default target `buildworld`) |
| Apk helpers | Port to C; delete `.sh` helpers |
| Code layout | Multi-file, one binary |

## CLI

| Invocation | Behavior |
|------------|----------|
| `rhap-build` | Generate with current options/env defaults; print short hint for `samu buildworld` / `buildkernel`. Exit status from generate. |
| `rhap-build generate [opts…]` | Generate only (quiet enough for Makefile / scripts). Same generate flags as today’s `genninja` (`--srcroot`, `--dstroot`, `--apkrepo`, …). |
| `rhap-build build [target…]` | Generate, then run `samu` with remaining args as targets. Default target if none: `buildworld`. Fail without running `samu` if generate fails. Propagate `samu` exit status. |
| `rhap-build mkapk <PKGINFO> <staging-root> <out.apk>` | Build one `.apk`. |
| `rhap-build index <repo-dir>` | Rebuild `APK_INDEX.gz` in `<repo-dir>`. |
| `rhap-build publish <repo-dir> <pkginfo> <stage> […]` | For each pair, mkapk into repo as `${pkgname}-${pkgver}.apk`, then index. |

### `build` / `samu` resolution

- Binary: `SAMU` environment variable, or `--samu PATH` on the `build` subcommand, else `ninja/samurai/samu` relative to the repo root (directory containing `ninja/` when invoked as `ninja/rhap-build`, or cwd conventions matching the Makefile today).
- Working directory for `samu`: repo root (parent of `ninja/`), same as `make -C ninja world`.

### Global / generate options

Preserve existing `genninja` options and env vars (`SRCROOT`, `DSTROOT`, `OBJROOT`, `SYMROOT`, `SRCBASE`, `TOOLROOT`, `APKREPO`, `RC_ARCHS`, `RC_OS`, `WRAPPER`, `-o`/`--out`). They apply to generate and thus to bare / `build` / `generate`.

## File layout

Under `ninja/`:

| Path | Role |
|------|------|
| `rhap-build.c` | `main`, subcommand dispatch, bare hint, `build` → generate + exec `samu` |
| `generate.c` / `generate.h` | Tree scan, PKGINFO parse, DAG, emit `build.ninja` (current `genninja.c` body) |
| `mkapk.c` / `mkapk.h` | Package stage root → `.apk` |
| `index.c` / `index.h` | Index repo → `APK_INDEX.gz` |
| `publish.c` / `publish.h` (or thin wrappers in `rhap-build.c`) | Batch mkapk + index |
| `util.c` / `util.h` | Shared `die`, path helpers, `env_or` as needed |

### Removed

- `ninja/genninja.c` (content moved to `generate.c` + CLI in `rhap-build.c`)
- `ninja/mkapk.sh`
- `ninja/index-apk-repo.sh`
- `ninja/publish-apk-repo.sh`

### Kept

- `ninja/buildproj.sh` — still the ninja `buildproj` rule wrapper; on `install`, after private pkgroot + merge, calls `rhap-build mkapk` (binary beside the script, or `RHAP_BUILD` override).
- `ninja/samurai/` — unchanged.

## Generate graph changes

Emitted ninja rules that today invoke shell helpers must call the binary:

- `rule apkindex` → `ninja/rhap-build index "$apkrepo"` (with `DSTROOT`/`TOOLROOT`/`APK` env as today for finding `apk`).
- Comments / regen instructions refer to `rhap-build`, not `genninja`.
- Default `--wrapper` remains `ninja/buildproj.sh`.

## Packaging behavior (C ports)

### `mkapk`

1. Validate args: PKGINFO file, staging directory, output path.
2. Create temp directory; copy PKGINFO to `.PKGINFO`.
3. Extract/copy staging tree into temp (via `tar` pipe, matching current script).
4. Create `.apk`: archive with `.PKGINFO` first, then other members; compress with `gzip -n` when available, else `tar czf` fallback for hosts without standalone `gzip`.
5. Clean temp on exit (success or failure).

Prefer spawning host `tar`/`gzip` over linking a compressor library — matches Rhapsody/Darwin host assumptions already used by `buildproj.sh`.

### `index`

1. Require repo directory; if no `*.apk`, print skip message and exit 0.
2. Resolve `apk` binary: `APK` env if set/executable; else `$DSTROOT/sbin/apk`, `$TOOLROOT/sbin/apk`; else `PATH`.
3. If still missing: warn to stderr, exit 0 (soft failure so early world builds before apk-tools is staged do not fail the index edge).
4. Run `apk index <apk-files…>`, pipe stdout through `gzip -n` to `APK_INDEX.gz.new`, then `rename` to `APK_INDEX.gz`.

### `publish`

For each `<pkginfo> <stage>` pair: read `pkgname` / `pkgver` from PKGINFO, write `$repo/${pkgname}-${pkgver}.apk` via mkapk; then run index once.

## Makefile integration

- Build target: `rhap-build` from the listed `.c` files (`cc -O -Wall … -o rhap-build`).
- `make generate` → `ninja/rhap-build generate $(GENFLAGS)`.
- `make world` / `kernel` → may use `ninja/rhap-build build buildworld` / `buildkernel` (generate + samu in one step), or keep “generate then $(SAMU)” equivalent.
- `make clean` removes `rhap-build` (not `genninja`).
- Docs (`ninja/README.md`, root notes if any) updated for the new name and subcommands.

## Error handling

| Case | Behavior |
|------|----------|
| Unknown subcommand / bad usage | Usage on stderr, exit 2 |
| Generate failure | Non-zero; `build` does not start `samu` |
| `samu` missing | Clear error, non-zero |
| `mkapk` bad args / I/O | Non-zero |
| `index` no apks / no apk binary | Soft success (exit 0) with message |
| `index` apk/gzip failure | Non-zero |

## Testing

Update `ninja/tests/` to invoke `ninja/rhap-build mkapk` and `ninja/rhap-build index` instead of the deleted scripts. Existing smoke / roundtrip / deps / HTTP / conflict expectations unchanged (gzip magic, `.PKGINFO` member, `APK_INDEX.gz` name for pre11).

## Migration notes

- Regenerate `build.ninja` after landing so edges point at `rhap-build index`.
- Callers of `ninja/genninja` or the three apk scripts switch to `rhap-build` subcommands.
- No requirement to keep a `genninja` binary name.

## Argv convention (locked for implementation)

- Parse global/generate options anywhere before the first non-option argument that is a known subcommand, **or** after `generate` / before targets on `build`.
- Known subcommands: `generate`, `build`, `mkapk`, `index`, `publish`.
- If argv[1] is not a subcommand and not an option, treat as error (do not treat project names as bare targets — use `rhap-build build <target>`).
- `publish` may live as a short function in `rhap-build.c` unless it grows beyond ~80 lines.
