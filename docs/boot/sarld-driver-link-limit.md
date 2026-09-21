# sarld could not link drivers much past 120k

The i386 booter links every boot driver against the kernel with `sarld`, the
standalone `rld` at `/usr/standalone/i386/sarld`. Drivers larger than roughly
120k failed to link, and the failure was not confined to the oversized driver:
it took down every driver linked after it, and the kernel then panicked for a
reason that named none of this.

Found 2026-09-21 while trying to boot `drvEIDE`, which is 131,264 bytes. Every
driver Apple shipped stays under the limit -- the largest is `Floppy_reloc` at
124,956 -- so stock installs never hit it.

## Symptom

The kernel panics early, before it prints `ISA bus` or `DriverKit version`:

```
panic: Missing EISA kernel bus class
```

This is misleading twice over. It is not a driver panic at all -- it is the
kernel's own, at `src/kernel-7/driverkit/i386/autoconf_i386.m:191` -- and
`DualEide.m:82` builds a byte-identical string from the same format, so the
message alone does not say which fired. The serial log settles it: `autoconf`
panics before `configureDriver()` runs, so no driver's `+probe:` has executed.

The booter, whose output the kernel has already scrolled away, shows the cause:

```
Error occurred while linking driver EIDE:
rld(): virtual memory exhausted (malloc failed)
Error linking EIDE device Driver.
Error occurred while linking driver ISASerialPort:
previous fatal errors occured, can no longer succeed
... Floppy, PS2Keyboard, PCIBus, EISABus, all the same
```

EIDE is first in the boot driver list. `rld` latches its fatal state, refuses
everything after it, and `EISABus` never loads -- so `EISAKernBus` never runs
`+initialize`, never registers itself, and the kernel's
`[KernBus lookupBusClassWithName:"EISA"]` returns nil.

## Root cause

Not bytes -- allocation count. `sa_rld_internal` in `src/cctools-2/ld/rld.c`
initialized the standalone allocator with a fixed 1000 nodes, and
`zallocate()` in `src/boot-2/i386/libsa/zalloc.c` appended to `zalloced[]`
without checking that limit. `malloc_init()` lays the two node tables out
adjacently, so allocation 1001 wrote over `zavailable[0]` -- the free list head.
The heap was then corrupted, the next `malloc` returned 0, and `rld` reported it
as exhausted memory.

The byte arena was never the constraint. Growing `RLD_MEM_LEN` from 1Mb to
1.5Mb did not help, and patching a 4Mb arena into the stock booter did not
either; both still failed at the same point. That is what ruled size out.

`malloc_init()` had a second, latent bug: it carved the node tables out of the
arena but still published the full arena length as available, so the allocator
could hand out memory past the end of its own block. With 1000 nodes that
overrun was 16,000 bytes into whatever followed.

## Fix

- `src/cctools-2/ld/rld.c` -- 1000 nodes to 8000.
- `src/boot-2/i386/libsa/zalloc.c` -- `malloc()` returns 0 once the node table
  is full instead of corrupting the free list, and `malloc_init()` subtracts the
  node tables from the length it publishes as available.

`sarld` is read from the filesystem by name (`boot.c` calls
`loadStandaloneLinker("/usr/standalone/i386/sarld")`), so replacing that one
file is enough; the boot blocks do not have to be rewritten.

Rebuild it with:

```
rbuild buildpackage --state /build/state --dir --target all \
    /build/src/cctools-2 /build/repo /build/out/cctools-rbuild
# copy the cctools apk into /build/repo, then
rbuild buildpackage --state /build/state --arch i386 --dir --target all \
    /build/src/boot-2 /build/repo /build/out/booter-rbuild
```

`vm/build-i386-booter.sh` runs the second step. `boot-2` also needs `gawk` in
the repository (`src/gawk-1`); it was not there and had to be built first.

## Verified

With the rebuilt `sarld` grafted onto a test image, `drvEIDE` links and the
machine boots to userland: `hc0` detects the controller, `hd0` registers, and
the root filesystem mounts on `/dev/hd0a`. Every other boot driver links as
before. The same result was obtained first by patching the node count into
Apple's own `sarld` binary, which isolates the change from the rest of our
rebuild.

## Also fixed: boot2 could not read the disk at all

`boot2` built from this tree ran but found no config files, printing
`Bad superblock: error 2` five times, and reported `K conventional / K total
memory` with no numbers. Both are fixed; the two are unrelated to the `sarld`
limit above and to each other.

`sys.c` decided the filesystem's byte order at compile time:

```c
#define BIG_ENDIAN_INTEL_FS __LITTLE_ENDIAN__
```

which is true on i386, so the booter byte-swapped every superblock, inode and
directory block it read. The filesystems NeXT's tools produced are big-endian
and want that; the ones this tree installs are little-endian and do not. Swapping
a little-endian superblock destroys the magic, so `open()` failed the check at
what was then `sys.c:861` and no file could be opened. The stock booter is
unaffected, which is why only our build showed it.

The kernel has never guessed: `ffs_mountfs()` validates the superblock as read,
byte-swaps and revalidates only if that fails, and records the answer as
`rev_endian`. `sys.c` now does the same, with `fs_rev_endian` gating the four
other swap sites. The disks that were previously fixed up for a 512-versus-1024
blocksize mismatch still are; the ones that never were still are not.

`prf.c` had no `case 'u'`, so `%u` printed nothing at all -- `printn()` has
always formatted unsigned, so the case was all that was missing.

Verified: our `boot2`, our `sarld` and our `drvEIDE` boot together to userland
on our kernel, and the prompt reads `639K conventional / 129535K total memory`.

Note that `boot2` is close to its ceiling. `boot1` reads `LOADSZ` sectors --
88, or 45,056 bytes -- and our `boot2` is 44,576, leaving 480 bytes of headroom.

`boot2/Makefile` has always failed the build when the booter went over, but it
kept its own copy of the limit as `MAXBOOTSIZE = 45056`, which could drift away
from `LOADSZ`, and it said nothing at all until the limit was already breached.
It now reads `LOADSZ` out of `boot1.s` and prints the headroom on every build:

```
booter 44576 bytes of 45056, 480 to spare
```

It fails if the booter is too large, and also if `LOADSZ` cannot be read, so a
rename in `boot1.s` cannot quietly disable the check.

## Also fixed: rcz was built for the wrong architecture

`rbuild buildpackage --arch i386 src/boot-2` built everything and then failed:

```
path usr/bin/rcz: code architecture mismatch
(CPU ppc-apple-rhapsody; required i386-apple-rhapsody)
```

`rcz` is not just a build tool -- it ships, and Apple's own i386 install has
`/usr/bin/rcz` as an i386 executable. `gen/rcz/Makefile` took its architecture
entirely from `RC_CFLAGS`, but the top-level `Makefile` passes every
subdirectory `RC_CFLAGS=$(ARCHLESS_RC_CFLAGS)`, with `-arch` stripped out,
because the `i386` and `ppc` subdirectories name their own. Nothing then told
`gen` what to build for, so it built for the host. It now takes the
architectures from `RC_ARCHS`, which `gen/Makefile` already forwards.

The package builds clean, and the `rcz` in it is `cputype 7` at 17,360 bytes
against the 17,428 Apple shipped.

## Still open

- The big-endian path is now reachable only on a big-endian disk, and there is
  no such image here to test it against.

`src/boot-2/i386/libsaio/saio_internal.h` used `__attribute__((packed))`, which
the compiler that builds the booter rejects outright, so `boot-2` could not be
built at all before this. The attribute was removed; the struct is 8 + 8 + 4 + 4
and already lays out with no padding on i386.
