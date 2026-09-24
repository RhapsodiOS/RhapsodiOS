# rbuild

C89 replacement for the Perl `darwin-buildpackage` / `darwin-buildall` /
`darwin-missing` tools. Produces and consumes apk packages (apk-tools 2.0)
instead of dpkg `.deb`.

## Build

    make            # builds ./rbuild
    make test       # unit tests and bootstrap integration checks
    make trace-test # rbuild APK dry-run: universal probes and thin RC_*
    make install    # installs to $(DSTROOT)/usr/bin/rbuild

## Usage

    rbuild buildpackage [--state DIR] [--arch ARCH] [--dir] \
        [--target {all|headers|objs|local}] \
        <source> <repository> <dstdir>
    rbuild buildall <srclist> <repository> <dstdir>
    rbuild kernel [--state DIR] --arch ARCH \
        <srcdir> <repository> <dstdir>
    rbuild kerneldrivers [--state DIR] --arch ARCH \
        <srcdir> <repository> <dstdir>
    rbuild bootstrap --sysroot ROOT --toolchain FILE --state DIR \
        <srclist> <repository> <dstdir>
    rbuild bootstrap-universal --sysroot ROOT --toolchain FILE --state DIR \
        <srclist> <repository> <dstdir>
    rbuild missing  <srclist> <dstdir>
    # global: -n / --dry-run

`rbuild kerneldrivers` reads `rbuild-1/kernel-drivers-blacklist.json` under
`<srcdir>` and skips every `skip` path. Remove a driver from that list when it
packages successfully.

## Architecture

Ordinary builds default to `universal-apple-rhapsody` (i386 + PPC), independent
of the host. Explicit `i386` / `i386-apple-rhapsody` and `ppc` /
`ppc-apple-rhapsody` source labels select thin output. A missing or omitted
`arch` field means universal; an empty or unsupported field is an error.

Bootstrap uses the toolchain profile's thin `target_arch`; kernel commands
use `--arch i386` or `--arch ppc`. `buildpackage --arch` selects that same thin
target (`RC_ARCHS` / `-arch`) and copies `/usr/libexec/<arch>` into the chroot
so `cc` can find that arch's `cc1obj` / `cpp-precomp`. A universal source
permits either operation, but an explicit conflicting thin source is rejected.
Metadata records the canonical effective architecture without rewriting
`apk/pkginfo`.

`bootstrap-universal` is the primary bootstrap method for a dual-architecture
repository: it walks `BootstrapRuntimeManifest` (Csu through Libsystem) and
then the caller's full manifest with `RB_ARCH_UNIVERSAL`. Thin `bootstrap`
remains for unit tests and the first walk that stages the profile's thin CPU.

Before an `all` or `binary` project build, private compiler/linker probes must
produce every requested CPU slice. Bootstrap may defer linking until its
explicit `ld_flags_ready` marker exists. Products, cached APKs, and dependencies
are checked by content. No probe executable is run, and there is no host-only
fallback. Dry-run prints the checks and commands without creating build roots.

Published APK filenames encode architecture as
`<pkgname>-<pkgver>-<universal|i386|ppc>.apk`; universal and thin variants
can coexist in the same repository when their tokens differ. Incompatible
cached artifacts are quarantined as `.invalid` before rebuilding. `missing`
only inspects them.

See [architecture policy and verification](../../docs/build/rbuild-universal.md)
for object collections, dependency compatibility, state migration, and the
bounded native guest acceptance evidence.

## Notes

- Source type is always `dir`; `--cvs` is rejected (support removed).
- Publishes `<pkgname>-<pkgver>-<universal|i386|ppc>.apk` and matching
  `-hdrs`/`-obj` companions; `.PKGINFO` `arch` remains `*-apple-rhapsody`.
- Source metadata is `apk/pkginfo`. Packaged `.PKGINFO` uses the same keys
  (`makedepends`, `license`, `url`, …). apk ignores unknown keys.
- `makedepends_i386` / `makedepends_ppc` add build dependencies only when the
  build includes that CPU (a universal build takes both), e.g. kernel-7's
  `makedepends_ppc = drvpexpert`.
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`, and for vendored projects on `mv`, `rmdir`
  and GNU `patch` 2.5 or later. Patching runs on the host, before any chroot.

## Vendored sources

A project may ship a pristine upstream tarball and an ordered patch series
instead of an expanded tree. `apk/vendor` uses `apk/pkginfo` syntax:

    tarball = zlib-1.1.3.tar.gz
    directory = zlib
    patches = patches
    patchlevel = 1

`tarball` and `directory` are required; `patches` and `patchlevel` default as
shown. After rsyncing the project into SRCROOT (without the tarball or the
patch directory), rbuild extracts the tarball with the toolchain's `gzip` and
`tar`, renames its single top-level entry to `directory`, and runs
`patch -f -E --no-backup-if-mismatch -p<level>` for each `<patches>/*.patch`
in filename order. The project's Makefile then builds normally. The tarball
must hold exactly one top-level entry, and the project must not also
carry the expanded tree. See `src/zlib-1`.

`make trace-test` is an rbuild `-n` dry-run against empty APK seeds: universal
i386+ppc probes, thin `RC_*` policy, no build root, no live-host bootstrap
seeds. Empty dependency archives are planning fixtures, not valid packages;
actual payload validation and native builds are tested separately.
