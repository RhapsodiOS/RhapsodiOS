# RhapsodiOS

This is an open source reimplementation of Apple's Rhapsody operating system, that later became Mac OS X Server 1.0 through 1.2v3.

It's a fork of the Darwin 0.3 open source release done by Apple in the summer of 1999 with additional contributions from the community.

### Compiling

## Notes
These sources work best with a case-sensitive file system. Rhapsody DR 2 and Mac OS X Server 1.0 through 1.2v3 have been tested to work at the moment.

## Pre-requisites
Things are a bit manual to get going:
 * Make the following directories
   ```
   mkdir -p /build/source
   mkdir -p /build/repo
   mkdir -p /build/built
   ```
 * Download the source files from the [RhapsodiOS GitHub repository](https://github.com/RhapsodiOS/RhapsodiOS) as a tarball and extract it to a directory on a supported system e.g. /build/source
 * The `/build/repo` directory starts **empty** — the seed package set is built
   from source in Stage 0 below (no pre-built package download required).
 * Mount the released iso cd and open Terminal and run the following commands to install dpkg and the build scripts
   ```
   cd /tmp
   ar x /CDROM/deb/dpkg_1.4.1.0.2-3_i386.deb
   cd /
   tar -xzvf /tmp/data.tar.gz
   rm /tmp/data.tar.gz
   rm /tmp/control.tar.gz
   rm /tmp/debian-binary
   ```
   Close and reopen a Terminal session and you'll be able to run dpkg commands.
 * Update perl (for Rhapsody DR2 only)
   ```
   dpkg-deb -x /CDROM/deb/perl_5.005.03-1_i386-apple-rhapsody.deb /
   ```
 * Install dpkg_scriptlib
   ```
   dpkg-deb -x /CDROM/deb/dpkg_scriptlib_1.4.1.0.2-3_i386-apple-rhapsody.deb /
   ```
 * Install buildtools
   ```
   dpkg-deb -x /CDROM/deb/buildtools_0.1-2_i386-apple-rhapsody.deb /
   ```

## Building individual packages
```
usage: darwin-buildpackage [ --cvs | --dir ] [ --target {all|headers|objs|local} ] <source> <repository> <dstdir>
example: darwin-buildpackage --dir --target all /build/source/kernel-7 /build/repo /build/built
```

## Building from the manifest file
* Current working directory must be the root directory containing source files e.g. /build/source and the Manifest file e.g. /build/source/Manifest
```
usage: darwin-buildall <srclist> <repository> <dstdir>
example: darwin-buildall Manifest /build/repo /build/built
```

## Bootstrapping from source (no pre-built packages)

The build root that `rbuild` populates for every package needs a `build-base`
set (cc, cctools, gnumake, libsystem, headers, makefile frameworks, core
commands). Those packages are themselves built by `rbuild`, so a fresh
`/build/repo` cannot build anything. Break the cycle with a three-stage
from-source bootstrap on the Rhapsody host (which already has Apple's native
toolchain):

* **Stage 0 — native seed.** Build the `build-base` closure against the host
  root (no chroot, no dependency install) and write the seed `.apk`s into the
  repository:
  ```
  cd /build/source
  rbuild bootstrap BootstrapManifest /build/repo /build/repo
  ```
* **Stage 1 — self-host.** Build the whole system in clean chroots seeded only
  by Stage 0's output (this also rebuilds `build-base`, now self-hosted):
  ```
  rbuild buildall Manifest /build/repo /build/built
  ```
* **Stage 2 — self-consistency (optional).** Reseed from Stage 1's output and
  rebuild; the `build-base` `.apk`s from Stage 1 and Stage 2 should match,
  confirming the bootstrap is reproducible:
  ```
  rbuild buildall Manifest /build/built /build/built2
  ```
