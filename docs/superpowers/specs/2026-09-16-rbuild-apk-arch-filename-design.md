# APK filenames include a short architecture token

## Purpose

Make repository APK names show which architecture they are, so a listing of
`/build/repo` (or a driver dest) is readable without extracting `.PKGINFO`.

This revises the current `package_canon_name` stem `{pkgname}-{pkgver}` (arch
only in `.PKGINFO`) that replaced Perl rbuild's `pkg_ver_arch` filename.

Approved in conversation on 16 September 2026 on branch
`rbuild-universal-bootstrap`.

## Filename contract

`package_canon_name` returns `{pkgname}-{pkgver}-{shortarch}`.

Publish appends `.apk` as today.

Examples:

| Package | Version | Effective arch | Filename |
| --- | --- | --- | --- |
| driverkit | 139.1-3 | universal | `driverkit-139.1-3-universal.apk` |
| driverkit-hdrs | 139.1-3 | universal | `driverkit-hdrs-139.1-3-universal.apk` |
| drvpcfloppy | 5 | i386 | `drvpcfloppy-5-i386.apk` |
| kernel | 154.5.1-7 | i386 | `kernel-154.5.1-7-i386.apk` |
| csu | 23.1-1 | ppc | `csu-23.1-1-ppc.apk` |

Short tokens (filename only):

| `.PKGINFO` `arch` | Filename token |
| --- | --- |
| `universal-apple-rhapsody` | `universal` |
| `i386-apple-rhapsody` | `i386` |
| `ppc-apple-rhapsody` | `ppc` |

i486 Mach-O subtype still uses filename token `i386` (same CPU family).

`.PKGINFO` keeps the full `*-apple-rhapsody` labels. APK inner layout does not
change.

Companions (`-hdrs`, `-obj`) use the same suffix.

A publish with missing or unmapped architecture is an error. Do not emit the
old `{pkgname}-{pkgver}.apk` stem and do not emit an empty `-{shortarch}`.

## Lookup, covering, and errors

Repo lookup uses the new filename only. An old `csu-23.1-1.apk` is not a hit.

Covering stays the existing policy, expressed with the new names:

- Thin consumer (ppc or i386): try `{name}-{ver}-{cpu}.apk`, then
  `{name}-{ver}-universal.apk`. A universal file still satisfies a thin
  consumer.
- Universal consumer: only `{name}-{ver}-universal.apk`. A thin file does not
  cover.

`.PKGINFO` `arch` must match the filename token (map the full label to the
short token and compare). A `*-ppc.apk` whose PKGINFO says
`universal-apple-rhapsody` is refused.

Missing file or wrong arch: same class of error as today; the message names the
new path.

Cache `already exists` / `already have` keys use the new stem. A leftover
old-named APK is not reused as a current package.

## In-place rename (no rebuild)

Do not add an `rbuild` subcommand.

A one-shot host/guest script walks `/build/repo` only:

1. For each `*.apk` (not `*.apk.invalid`), read `.PKGINFO` `arch`.
2. Map it to the short token.
3. `mv` `csu-23.1-1.apk` → `csu-23.1-1-universal.apk` when the current name
   does not already end with `-{shortarch}.apk`.
4. If the destination exists, abort. Do not overwrite.
5. Skip `*.apk.invalid`. Do not modify APK contents.

After the rename, `/build/repo` matches the new lookup. New publishes
(bootstrap, `buildpackage`, `rbuild kernel`) write the new names from then on.
No universal bootstrap rebuild is required for the rename itself.

## Tests

- `package_canon_name` emits `foo-1.2-3-universal`, `foo-1.2-3-i386`,
  `foo-1.2-3-ppc`.
- Missing architecture fails.
- Lookup finds the new name; a `*-universal.apk` covers a thin consumer; old
  `foo-1.0.apk` is not a hit; PKGINFO/token mismatch is refused.
- Publish tests expect stems like `task9-patch-proof-2.5-1-universal`.

The live `/build/repo` rename is a one-shot after the code lands, not a
required unit-test fixture.

## Out of scope

- Changing `.PKGINFO` labels or APK inner layout
- `gcc-darwin.conf` / profile `target_arch`
- Rebuilding the universal bootstrap
- Merging `rbuild-universal-bootstrap` to main
- Kernel skip scope and `-undefined suppress` follow-ups from the
  16 September 2026 whole-branch review

## Implementation home

Implement on branch `rbuild-universal-bootstrap` in the existing worktree.
