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
 * Download the released set of packages from the [GitHub releases page](https://github.com/evolver56k/Darwin-0.3/releases/tag/v1.0) and extract it to a directory on a supported system e.g. /build/repo
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
