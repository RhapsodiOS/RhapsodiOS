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

    rbuild buildpackage [--dir] [--target {all|headers|objs|local}] \
        <source> <repository> <dstdir>
    rbuild buildall <srclist> <repository> <dstdir>
    rbuild missing  <srclist> <dstdir>
    # global: -n / --dry-run

## Notes

- Source type is always `dir`; `--cvs` is rejected (support removed).
- Produces `<name>.apk`, `<name>-hdrs.apk`, `<name>-obj.apk`.
- `.PKGINFO` carries a custom `builddepends` field (apk ignores unknown keys).
- Depends at runtime on `tar`, `gzip`, `apk`, `make`, `chroot`, `rsync`,
  `mkdir`, `cp`, `rm` on `PATH`.

The `buildtools-2` Perl remains in the tree as the reference oracle used by
`make trace-test`; it will be retired once rbuild is validated.
