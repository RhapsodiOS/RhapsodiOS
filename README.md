# RhapsodiOS

This is an open source reimplementation of Apple's Rhapsody operating system, that later became Mac OS X Server 1.0 through 1.2v3.

It's a fork of the Darwin 0.3 open source release done by Apple in the summer of 1999 with additional contributions from the community.

### Compiling

## Notes
These sources work best with a case-sensitive file system. Rhapsody DR 2 and Mac OS X Server 1.0 through 1.2v3 have been tested to work at the moment.

## Pre-requisites

Prefer a case-sensitive filesystem on Rhapsody DR 2 or Mac OS X Server 1.x.
Bootstrap a toolchain into a shared prefix (historically from release CD `.deb`s;
today the in-tree package manager is **apk**, not dpkg — see
[`docs/superpowers/specs/2026-07-19-apk-package-management-design.md`](docs/superpowers/specs/2026-07-19-apk-package-management-design.md)).

Typical layout:

```
mkdir -p /build/source /build/repo /tmp/rhapsody/dst
```

Checkout or extract this tree under `/build/source` (or any path you prefer).

## Building with ninja / samurai

The build is driven by [`ninja/`](ninja/) (samurai/`samu` vendored). Every project
builds with its existing Apple/NeXT make framework into a single shared
`DSTROOT` (no `.deb`, no chroot). See [`ninja/README.md`](ninja/README.md).

```sh
# From the repo root (builds the bundled samu, generates build.ninja, builds):
make -C ninja world     # ...or `make -C ninja kernel` for just the kernel
```
