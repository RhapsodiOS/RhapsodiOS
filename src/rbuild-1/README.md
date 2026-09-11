# rbuild

C89 replacement for the Perl `darwin-buildpackage` / `darwin-buildall` /
`darwin-missing` tools. Produces and consumes apk packages (apk-tools 2.0)
instead of dpkg `.deb`.

## Build

    make            # builds ./rbuild
    make test       # unit tests
    make trace-test # command-trace comparison vs the buildtools-2 Perl
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
    rbuild missing  <srclist> <dstdir>
    # global: -n / --dry-run

`rbuild kerneldrivers` reads `rbuild-1/kernel-drivers-blacklist.json` under
`<srcdir>` and skips every `skip` path. Remove a driver from that list when it
packages successfully.

`buildpackage --arch` and `kernel` / `kerneldrivers --arch` set `RC_ARCHS` and
`-arch` for that target. Default remains the host architecture. When `--arch`
selects another architecture, rbuild copies `/usr/libexec/<arch>` into the
chroot so `cc` can find that arch's `cc1obj` / `cpp-precomp`.

## Notes

- Source type is always `dir`; `--cvs` is rejected (support removed).
- Produces `<name>.apk`, `<name>-hdrs.apk`, `<name>-obj.apk`.
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`.

The `buildtools-2` Perl remains in the tree as the reference oracle used by
`make trace-test`; it will be retired once rbuild is validated.
