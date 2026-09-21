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

## Still open

Two pre-existing defects in this tree's booter, both found on the way here and
neither touched:

- `boot2` built from this tree runs but cannot read the filesystem
  (`Bad superblock: error 2`), and misreports conventional/total memory. The
  stock `boot` is unaffected, and the `sarld` fix does not require replacing it.
- `rbuild buildpackage --arch i386 src/boot-2` builds everything but then fails
  its architecture check on `usr/bin/rcz`, a host tool the package installs into
  the product root.

`src/boot-2/i386/libsaio/saio_internal.h` used `__attribute__((packed))`, which
the compiler that builds the booter rejects outright, so `boot-2` could not be
built at all before this. The attribute was removed; the struct is 8 + 8 + 4 + 4
and already lays out with no padding on i386.
