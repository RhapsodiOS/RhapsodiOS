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
 * Compile and install libiberty and dpkg
   ```
   cd /build/source/dpkg/dpkg.src/libiberty && ./configure --host=i386-apple-rhapsody && make && make install (replace i386-apple-rhapsody with ppc-apple-rhapsody if compiling for PowerPC)
   cd /build/source/dpkg/dpkg.src && ./configure --host=i386-apple-rhapsody && make && make install (replace i386-apple-rhapsody with ppc-apple-rhapsody if compiling for PowerPC)
   ```
 * Install dpkg_scriptlib
   ```
   cd /build/source/dpkg_scriptlib && make install
   ```
 * Install buildtools
   ```
   cd /build/source/buildtools
   cp -p lib/*.pm /usr/lib/perl5/Dpkg/Package
	 cp tools/darwin-buildall.pl /usr/bin/darwin-buildall
	 cp tools/darwin-buildpackage.pl /usr/bin/darwin-buildpackage
	 cp tools/darwin-missing.pl /usr/bin/darwin-missing
	 chmod a+x /usr/bin/*
   ```

## Building individual packages
```
usage: /usr/bin/darwin-buildpackage [ --cvs | --dir ] [ --target {all|headers|objs|local} ] <source> <repository> <dstdir>
darwin-buildpackage --dir --target all /build/source/kernel-7 /build/repo /build/built
```

## Building from the manifest file
* Current working directory must be the root directory containing source files e.g. /build/source and the Manifest file e.g. /build/source/Manifest
```
usage: /usr/bin/darwin-buildall <srclist> <repository> <dstdir>
darwin-buildall Manifest /build/repo /build/built
```
