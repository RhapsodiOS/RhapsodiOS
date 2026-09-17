# Remove dpkg source, tooling, and Perl buildtools

## Purpose

Delete Darwin `dpkg`, `dpkg-scriptlib`, and `buildtools` from the source
tree now that rbuild consumes `apk/pkginfo` and builds APKs. Rewrite
`make trace-test` as rbuild-only APK dry-run checks. Remove only those
three packages' APKs from live `/build/repo`.

This follows `docs/superpowers/specs/2026-09-16-rbuild-apk-pkginfo-design.md`
(metadata cutover) and the original rbuild follow-up in
`docs/superpowers/specs/2026-07-23-rbuild-c89-conversion-design.md`
(retire `buildtools-2` once rbuild is the builder).

Approved in conversation on 17 September 2026.

## Success criteria

- `src/dpkg-3`, `src/dpkg_scriptlib-1`, and `src/buildtools-2` are gone.
- `src/Manifest` has no rows for those projects.
- `src/rbuild-1` does not reference `buildtools-2`, `dpkg_scriptlib-1`,
  `dpkg-3`, or `dpkg-deb`.
- `tools/convert-dpkg-control-to-pkginfo.py` is gone.
- `make trace-test` PASSes using rbuild `-n` and APK seeds only (no Perl,
  no `.deb` stubs, no `dpkg-deb` shim).
- Guest `vm/build-src.ps1 -Rbuild` PASSes, and guest `make trace-test`
  PASSes.
- `/build/repo` has no APKs whose `.PKGINFO` `pkgname` is `dpkg`,
  `dpkg-scriptlib`, `buildtools`, or those names with `-hdrs` / `-obj`.
  Other APKs remain. The sysroot is not uninstalled in this cut.

## Constraints

- One cut on a branch from **qemu-debug-loop**.
- Do not wipe `/build/repo`. Do not rebuild bootstrap. Do not uninstall
  guest `/usr/bin/dpkg` (or Perl `Dpkg::*`) from the sysroot.
- Do not change `apk-tools-1`. Do not reopen the `apk/pkginfo` schema.
- Do not rewrite historical specs/plans. Update current-policy sentences
  in `src/rbuild-1/README.md` and the `trace-test` comment in
  `src/rbuild-1/Makefile` (drop the Perl oracle claim; describe
  trace-test as rbuild APK dry-run).
- Do not run full host `test-build-src.ps1` (pre-existing drvEIDE
  assertion).

## Architecture

```
src/Manifest  ──no dpkg / dpkg-scriptlib / buildtools──►  world builds
src/rbuild-1/tests/trace/run.sh  ──rbuild -n + APK seeds──►  trace-test
/build/repo/*.apk  ──pkgname whitelist──►  rm matching APKs only
```

rbuild remains the only builder. `apk-tools` remains the package manager
in tree.

## Components

| Unit | Change |
|------|--------|
| `src/dpkg-3/` | Delete |
| `src/dpkg_scriptlib-1/` | Delete |
| `src/buildtools-2/` | Delete |
| `src/Manifest` | Drop the three `dir` rows |
| `src/rbuild-1/tests/trace/run.sh` | rbuild `-n` only |
| `src/rbuild-1/tests/trace/shim/dpkg-deb` | Delete |
| `tools/convert-dpkg-control-to-pkginfo.py` | Delete |
| `src/rbuild-1/README.md` | Current-policy wording (no Perl oracle) |
| `src/rbuild-1/Makefile` | `trace-test` comment: rbuild APK dry-run, not Perl |
| `vm/remove-repo-dpkg-apks.sh` | One-shot repo cleanup |
| `vm/remove-repo-dpkg-apks.ps1` | Thin host wrapper (same pattern as `rename-repo-apk-arch`) |

No rbuild C changes unless a leftover comment is the only hit (none
expected).

## Data flow

1. **Source** — Delete the three project trees and Manifest rows. World
   `buildall` / `missing` no longer see them. Bootstrap manifests already
   omit them.
2. **trace-test** — Seed empty `{name}-1.0-universal.apk` stubs for the
   same basedeps as today. Do not create `*_1.0.deb`. Run `rbuild -n
   buildpackage` on `foo-1.0` (universal i386+ppc probes, no build root,
   no live-host seeds) and `thin-1.0` (`RC_ARCHS=i386`, no PPC probe).
   Do not invoke Perl or diff against `darwin-buildpackage`.
3. **Live repo** — Script walks `/build/repo/*.apk` (skip `*.apk.invalid`).
   Read `pkgname` via `gzip -dc | tr '\000' '\012' | grep '^pkgname ='`.
   Delete when the value is exactly `dpkg`, `dpkg-scriptlib`,
   `buildtools`, or one of those plus `-hdrs` or `-obj`. Print counts.

## Error handling

| Situation | Behavior |
|-----------|----------|
| Manifest still names a deleted tree | Bug in this cut; rows must be gone |
| trace-test writes a build root, hits live-host seeds, misses probes, or thin plan selects PPC | Fail |
| Repo helper: missing `/build/repo` | Exit 1, delete nothing |
| Repo helper: cannot read `pkgname` | Exit 1 after printing the path; do not continue |
| Repo helper: no matching APKs | Exit 0, `removed=0` |
| `pkgname` not on the whitelist | Leave the file |
| Sysroot still has `dpkg` binaries | Not an error; out of scope |

## Testing

- Guest `make test` (`vm/build-src.ps1 -Rbuild`) PASS.
- Guest `make trace-test` PASS without the deleted trees or `dpkg-deb` shim.
- Path search: those three `src/` directories absent; Manifest grep clean;
  `src/rbuild-1` has no `dpkg-deb` / `buildtools-2` / `dpkg_scriptlib` refs.
- Repo helper: matching APKs gone; other `/build/repo` APKs remain.

## Out of scope

- Uninstalling dpkg from the live sysroot / bootstrap-root
- Replacing guest `dpkg` usage in leftover operator habits
- SPDX licenses, `apk/vendor`, live world rebuild
- Host `test-build-src.ps1` drvEIDE assertion
- Rewriting historical Task 9 / rbuild conversion docs
