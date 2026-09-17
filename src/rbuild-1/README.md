# rbuild

C89 replacement for the Perl `darwin-buildpackage` / `darwin-buildall` /
`darwin-missing` tools. Produces and consumes apk packages (apk-tools 2.0)
instead of dpkg `.deb`.

## Build

    make            # builds ./rbuild
    make test       # unit tests and bootstrap integration checks
    make trace-test # planned universal flags vs Perl; thin/dry-run assertions
    make install    # installs to $(DSTROOT)/usr/bin/rbuild

## Usage

    rbuild buildpackage [--dir] [--target {all|headers|objs|local}] \
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
`ppc-apple-rhapsody` source labels select thin output. A missing Architecture
field means universal; an empty or unsupported field is an error.

Bootstrap uses the toolchain profile's thin `target_arch`; kernel commands
use `--arch i386` or `--arch ppc`. A universal source permits either operation,
but an explicit conflicting thin source is rejected. Metadata records the
canonical effective architecture without rewriting source control files.

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
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`.

The `buildtools-2` Perl remains the command-flag oracle for `make trace-test`.
That test compares the first project header command with rbuild's dry-run plan,
excluding probe commands and preserving architecture values and CFLAGS spacing.
Its empty dependency archives are planning/shim fixtures, not valid packages;
actual payload validation and native builds are tested separately.
