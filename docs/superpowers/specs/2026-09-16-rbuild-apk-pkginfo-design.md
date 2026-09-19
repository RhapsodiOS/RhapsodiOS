# Migrate dpkg/control to apk/pkginfo

## Purpose

Replace every source `dpkg/control` with Alpine-style `apk/pkginfo`, and make
that file the only metadata rbuild reads. `.PKGINFO` inside APKs uses the same
schema. This is a hard cutover: no `dpkg/control` fallback after the change.

This supersedes the **metadata** half of
`docs/superpowers/specs/2026-07-24-rbuild-vendor-design.md` (that spec kept
`dpkg/` as fallback, used `builddepends`, and ignored `arch` on input). Vendor
tarballs / `apk/vendor` stay out of scope.

Approved in conversation on 16 September 2026.

## Success criteria

- Every production package that had `dpkg/control` has `apk/pkginfo` and no
  `dpkg/` directory (156 packages; 158 including rbuild test fixtures that
  currently ship control).
- rbuild never opens `dpkg/control`. Missing `apk/pkginfo` synthesizes in
  memory the way missing control does today.
- Source `apk/pkginfo` and packaged `.PKGINFO` share one key set: Alpine
  `.PKGINFO` keys plus `makedepends`. `pkgver` is today's dpkg `Version` (no
  `pkgrel`, no `-r0` in the version). Converted files set `license = unknown`.
- APK filenames stay `{pkgname}-{pkgver}-{universal|i386|ppc}.apk`.
- Guest `vm/build-src.ps1 -Rbuild` passes. Live `/build/repo` is not wiped or
  rebuilt.

## Constraints

- One cut on a branch from **master** (master already has arch-in-filename).
- One-shot converter `tools/convert-dpkg-control-to-pkginfo.py`, not an rbuild
  subcommand. It may remain in the tree as a record; it is not a supported
  interface after the cut.
- Do not rewrite source `apk/pkginfo` when resolving architecture.
- Do not emit Alpine computed keys (`size`, `builddate`, `datahash`, `commit`).
- `Vendor`, `Section`, `Priority`, and `Conflicts` are dropped. There are no
  runtime `Depends:` lines in the tree; do not invent `depend` from
  `Build-Depends`.

## Field mapping

`apk/pkginfo` syntax: one `key = value` per line. Blank lines and `#` comments
skipped. Value is everything after the first `=`, trimmed. No continuation
lines.

| Control | apk/pkginfo | Required in file | Notes |
|---------|-------------|------------------|-------|
| `Package` | `pkgname` | yes if file exists | |
| `Version` | `pkgver` | yes if file exists | Unchanged; no `pkgrel` |
| `Architecture` | `arch` | no | Omit when control omitted it. Scan default remains `universal-apple-rhapsody`. Honor `i386` / `ppc` / full `*-apple-rhapsody` labels when present. |
| `Description` | `pkgdesc` | no | Flatten continuation lines to a single line (space-join). Default: `No description available.` |
| `Maintainer` | `maintainer` | no | Default: existing anonymous Darwin address |
| `URL` | `url` | no | Omit if control had none |
| — | `license` | written on convert | Always `unknown` for converted files. Synthesis may omit; `pkginfo_write` still emits `license = unknown`. |
| `Build-Depends` | `makedepends` | no | Split on space or comma into the existing build-depends list |
| `Source` | (not copied) | | rbuild still sets `origin` from the directory basename (`pbase`) |
| `Provides` / `Replaces` | `provides` / `replaces` | no | Pass through; binary packages still add `<name>-hdrs` at package time |
| `Vendor` / `Section` / `Priority` / `Conflicts` / `Revision` | dropped | | |

`depend` is accepted on read if someone writes it later; the converter does not
emit it.

### Example (grep)

```
pkgname = grep
pkgver = 2.1
pkgdesc = Get-Regular-Expression-and-Print tool
maintainer = Darwin Developers <darwin-development@public.lists.apple.com>
license = unknown
url = http://www.gnu.org/software/grep/grep.html
makedepends = build-base
```

## Architecture

```
src/<pkg>/apk/pkginfo  ──pkginfo_read──►  Package (in-memory)
                                              │
                         missing file ──makepkginfo──┘
                                              │
                                              ├─ resolve arch (local copy only)
                                              ├─ makedepends → makeroot deps
                                              └─ pkginfo_write → .PKGINFO in .apk
```

Scan path is `<source>/apk/pkginfo` only. Leftover `dpkg/` after the cut is
ignored (not read, not an error).

## Components

| Unit | Change |
|------|--------|
| `pkginfo.c` | Add `pkginfo_read`. Change `pkginfo_write` to emit `makedepends`, `license`, `url`; never `builddepends`. |
| `package.c` | Drop Debian `package_parse` / `package_unparse`. Add `url` and `license` fields. |
| `builder.c` | `builder_scan_dir` reads `apk/pkginfo`; `makecontrol` becomes the same synthesizer under a pkginfo name. Delete `readcontrol`. Stage maintainer scripts from `apk/.pre-install` (etc.), not `dpkg/preinst`. |
| `kernel.c` | `has_control` looks for `apk/pkginfo`. |
| `apk.c` | Still identity-checks `pkgname` / `pkgver` / `arch`. Extra keys ignored. Old APKs with `builddepends` remain consumable. |
| Converter | `tools/convert-dpkg-control-to-pkginfo.py` converts all `dpkg/control` → `apk/pkginfo`, moves `files-5` scripts, deletes every `dpkg/`. |

In-memory synthesizer defaults (unchanged): `version=0`,
`arch=universal-apple-rhapsody`, `pkgdesc=No description available.`,
`makedepends=build-base`, maintainer = today's default.

## Data flow

1. **Converter (once)** — For each `src/**/dpkg/control`, write `apk/pkginfo`
   using the table above, then delete that `dpkg/` directory. Refuse to
   overwrite an existing `apk/pkginfo`. Refuse a control file it cannot map.
2. **Scan** — Read `apk/pkginfo` or synthesize. Architecture resolve mutates
   only the in-memory `Package`.
3. **Build** — `makedepends` seeds `builder_makeroot` as `Build-Depends` does
   today.
4. **Package** — Write `.PKGINFO` with the same keys; gzip+tar APK as today.
5. **Live repo** — Not rebuilt. New publishes get the new keys; old APKs stay
   until something rebuilds them.

## Maintainer scripts (`files-5` only)

apk-tools runs dotted names at the package root (`.pre-install`, …), not dpkg
names. Map:

| dpkg | source after cut | in APK |
|------|------------------|--------|
| `preinst` | `apk/.pre-install` | `.pre-install` |
| `postinst` | `apk/.post-install` | `.post-install` |
| `prerm` | `apk/.pre-deinstall` | `.pre-deinstall` |
| `postrm` | `apk/.post-deinstall` | `.post-deinstall` |

`files-5` has `preinst` and `postinst` only. **`conffiles` is dropped** (apk
has no conffiles list; it uses `.apk-new`).

## Error handling

| Situation | Behavior |
|-----------|----------|
| No `apk/pkginfo` | Synthesize in memory. Do not write a file. |
| File exists, missing `pkgname` or `pkgver` | Fail the scan. Do **not** synthesize. (Today a control file missing `Package:`/`Version:` accidentally synthesizes; that goes away.) |
| Invalid `arch` | Fail, same as invalid `Architecture:` today. |
| Unknown keys | Ignore. |
| Converter collision or unmappable control | Abort; do not delete that `dpkg/`. |
| Consuming old `.PKGINFO` with `builddepends` | Allowed. rbuild no longer emits that key. |

## Testing

- Unit: `pkginfo_read` (keys, `makedepends` split, `url`/`license`, missing
  file vs missing `pkgname`, invalid `arch`, unknown keys).
- Unit: `pkginfo_write` emits `makedepends` not `builddepends`; `license`; no
  `pkgrel`; one-line `pkgdesc`.
- Rewrite every rbuild test fixture that writes `dpkg/control` to
  `apk/pkginfo` (`test_package`, `test_builder`, `test_runner`, `test_kernel`,
  `bootstrap-*.sh`, trace fixtures). `bootstrap-closure.sh` asserts
  `apk/pkginfo` for sources that previously had control.
- Converter check: 156 production `apk/pkginfo`, zero `src/**/dpkg/control`,
  `files-5` scripts under `apk/`.
- Guest: `vm/build-src.ps1 -Rbuild`. No `/build/repo` wipe.

Out of scope: host `test-build-src.ps1` drvEIDE assertion; filling real SPDX
licenses; `apk/vendor` tarball layout; rebuilding the live repository.

## Landing

Branch from master. Single cut: rbuild switch + bulk convert + delete `dpkg/`
+ tests in one implementation plan.
