# virtio driver set design (shared static library + four drivers)

## Goal

Give RhapsodiOS **i386** a working set of paravirtualised **virtio** drivers for
QEMU, built on a shared static library so the transport and virtqueue logic is
written and tested once.

Success = a RhapsodiOS guest boots with **root on virtio-scsi**, reaches a login
prompt, has working networking over **virtio-net**, a usable tty on
**virtio-console**, and can mount a data disk on **virtio-blk** — all under
`qemu-system-i386` 11.x using the `*-pci-transitional` device models.

## Scope

**In scope:** a shared `libvirtio.a` implementing the *legacy* (VIRTIO 0.9.5)
PCI transport and split virtqueues, plus four drivers — virtio-scsi, virtio-blk,
virtio-net, virtio-console.

**Out of scope,** each tracked as its own follow-on spec:

- **virtio-input and virtio-gpu.** Both are VIRTIO 1.0-only devices
  (`1af4:1052`, `1af4:1050`) with no legacy device IDs, so they require the
  modern PCI transport — capability-list walking, MMIO BAR windows, 64-bit
  feature negotiation. virtio-gpu additionally is not a linear framebuffer but a
  command-queue 2D device, so bridging it to DriverKit's
  `IOFrameBufferDisplay` needs host resources, guest backing attachment, and a
  dirty-rect flush loop. QEMU's `-vga std` already works with the existing
  linear-framebuffer drivers (`drvVBoxVideo`, `drvVMWareVideo`).
- **An i386 16550 kernel console.** Wanted for early-boot and panic output, but
  it belongs in `kernel-7`, not here. virtio-console structurally *cannot* serve
  this role: PCI enumeration and virtqueue setup must complete before it can
  emit a byte, so the earliest and most valuable output would still be missing.
- **ppc.** The library is written to be arch-neutral but only i386 is built,
  tested, or claimed.

**There is no "virtio IDE" device.** The request named IDE; virtio's block
devices are virtio-blk and virtio-scsi, and both are covered.

## Constraints and decisions

- **Legacy transport only.** Transitional QEMU devices expose the legacy device
  IDs (`1af4:1000`–`1af4:1004`) and a legacy I/O-port BAR, which is all four
  drivers need. The modern transport arrives with the input/GPU spec.
- **Verification host is `qemu-system-i386` 11.x**, not the in-tree
  `vm/qemu.exe`. That binary is **QEMU 0.9.0 (2007)**, a Rhapsody-tuned fork
  (`-rhapsodymouse`, `-M pc|isapc` only) containing **no virtio whatsoever** —
  virtio-blk/net postdate it, and virtio-scsi did not exist until QEMU 1.1
  (2012). Confirming the existing guest image boots under QEMU 11 is therefore
  **milestone 0 and a hard gate** on all driver work.
- **Shared code ships as a static `libvirtio.a`,** not as shared sources and not
  as a separate kernel server. `kl_ld` folds the archive into each driver's
  single `_reloc`, so boot drivers and loadable drivers link identically — which
  a separate kernel server could not guarantee, since cross-module symbol
  resolution through `kern_loader` is boot-order dependent and a root-disk
  driver cannot depend on another module having loaded first.
- **The library core is plain C, not Objective-C,** behind an ops vector. This
  is the decision that makes virtqueue logic testable outside the kernel. Each
  driver's Objective-C class calls into that C API.
- **virtio-scsi carries root, not virtio-blk.** virtio-blk has the simpler wire
  protocol, but virtio-scsi subclasses `IOSCSIController`, and the existing
  DriverKit SCSI stack above it already provides disk labels, partitioning,
  removable media, and `sd0` naming. The stock config's
  `"Root Device" = "sd0a"` then works unchanged. Routing root through virtio-blk
  would mean a new `IODisk` subclass *and* a root-device name the kernel does
  not know — boot-path risk stacked on driver risk.
- **No MSI-X.** Declining it keeps the device-configuration offset fixed at
  `0x14` and avoids a second interrupt path.
- **Minimal feature negotiation.** Checksum offload, GSO, and mergeable RX
  buffers are all declined so that headers stay fixed-size and buffers stay
  linear.

## Ground truth from sources

Everything below was verified in-tree rather than assumed.

- **Static libraries are supported.** `LIBRARY_STYLE = STATIC` selects an
  `ar`/`libtool` archive rule (`src/pb_makefiles-1/library.make:107`), and
  `LOADABLES` includes `$(OTHER_LIBS)` (`src/pb_makefiles-1/common.make:288`),
  so a `.a` can be linked into a kernel server.
- **Kernel servers get flags a library does not.** `PROJTYPE_CFLAGS` injects
  `-static -DKERNEL -D_KERNEL` plus `-DKERNEL_SERVER_INSTANCE=`
  (`src/driverTools-1/KernelServerProjectType/kernelserver.make`). A
  `library.make` project receives none of these and **must replicate them in its
  `Makefile.preamble`**; a mismatch risks silent runtime breakage.
- **No driver in `drivers-i386/` currently links a shared library.** Every one
  is self-contained. This is the first, so the build integration is new work.
- **`drivers-i386/` has no top-level Makefile and no `Manifest` entry.** Drivers
  are built individually, so a new `src/drivers/` root breaks no aggregate
  build — but library-before-drivers ordering is documented, not automatic.
- **PCI access has an arch-neutral façade:** `driverkit/pci/IOPCIDirectDevice.h`
  (implemented in `driverkit-3/libDriver/pci/`), not only the i386 variant. ppc
  has `driverkit/ppc/IOPCIDevice.h` and `IOPPCDeviceDescription.h`. This is what
  justifies placing the library under a *generic* tree.
- **Port I/O inlines** `inb`/`inw`/`inl`/`outb`/`outw`/`outl` exist in
  `driverkit/i386/ioPorts.h`.
- **The only allocator is `IOMalloc`** (`driverkit/generalFuncs.h:47`). There is
  **no contiguous or aligned allocator**. `IOMallocLow` is i386-only and
  intended for ISA DMA. Physical translation is `IOPhysicalFromVirtual`
  (`driverkit/kernelDriver.h:103`). The existing precedent for aligned DMA
  memory is over-allocate-and-mask:
  `(IOMallocLow(size + 15) + 15) & ~15`
  (`src/drivers-i386/network/drvVMwareVMXNet/.../VMXNet.m:342`).
- **Block drivers** declare
  `IdeDisk : IODisk <IODiskReadingAndWriting, IOPhysicalDiskMethods>`
  (`src/drivers-i386/ide/drvEIDE/.../IdeDisk.h:112`), with a separate
  `IdeController : IODirectDevice` above.
- **EIDE's own CD-ROM path is `AtapiController : IOSCSIController`**
  (`.../AtapiCnt.h:95`), confirming the SCSI family is well-trodden here.
- **Drivers register character devices themselves** via `IOAddToCdevsw`
  (`src/drivers-i386/input/drvPCParallel/.../IOParallelPort.m:138`). The
  in-kernel tty model to follow is `km.m` (`km_tty[]`,
  `src/kernel-7/bsd/dev/i386/conf.c:201`).
- **The booter reads the key `"Boot Drivers"`** in all four implementations
  (`src/boot-2/gen/libsaio/stringTable.c:532` and the i386/ppc variants). The
  `"Active Drivers"` key in `driverkit-3/tests/Devices/System.config/Instance0.table`
  is a **stale test fixture — do not copy it.**
- **Auto-detect ID format is `(device << 16) | vendor`,** derived from VMXNet's
  `"0x072015ad"` (VMware `15ad:0720`) and `"0x20001022"` (AMD `1022:2000`).
- **Shared PCI IRQs are the norm:** `"Share IRQ Levels" = "YES"` appears in most
  PCI driver `Default.table` files.
- **`sc_status_t` is defined in `src/kernel-7/bsd/dev/scsireg.h`** with 24
  members. `SR_IOST_GOOD/SELTO/CHKSV/IOTO/BCOUNT/TABT/RESET/HW` all exist;
  **there is no `SR_IOST_BUSY`.**
- **`IOSCSIRequest` fields** (`driverkit/scsiRequest.h`) relevant here:
  `driverStatus` (`sc_status_t`), `scsiStatus` (SCSI status byte),
  `bytesTransferred`, `senseData` (valid only when `driverStatus ==
  SR_IOST_CHKSV`), `timeoutLength` (I/O timeout in seconds), `maxTransfer`,
  `cdbLength`.
- **Valid `"Family"` values** in use across `drivers-i386/`: `Audio`, `Bus`,
  `Disk`, `Display`, `Keyboard`, `Network`, `Other`, `Parallel`,
  `Pointing Device`, `SCSI`, `SDSI`, `Serial`. The four this spec uses —
  `SCSI`, `Disk`, `Network`, `Serial` — are all established.
- **i386 has no kernel serial console.** `src/kernel-7/bsd/dev/i386/cons.c:195`
  notes serial output is the ppc path; i386 console is `km`/`VGAConsole`.

## Repository layout

```
src/drivers/generic/libvirtio-1/        LIBRARY_STYLE = STATIC  → libvirtio.a
src/drivers/generic/drvVirtioSCSI/      1af4:1004   root-capable
src/drivers/generic/drvVirtioBlk/       1af4:1001   data disks
src/drivers/generic/drvVirtioNet/       1af4:1000
src/drivers/generic/drvVirtioConsole/   1af4:1003
```

`src/drivers/` is a new root. The existing `drivers-i386/` and `drivers-ppc/`
trees are expected to migrate under it as `src/drivers/i386` and
`src/drivers/ppc` later; that migration is **not** part of this spec.

Each driver keeps the conventional
`drvX/X.drvproj/X.lksproj` shape and adds `-lvirtio` to `OTHER_LIBS`.

## libvirtio design

### Transport

Legacy virtio-pci places its registers in BAR0 I/O port space at fixed offsets.
With MSI-X declined, these are:

| Offset | Width | Access | Register |
|--------|-------|--------|----------|
| `0x00` | 32 | r/o | device features |
| `0x04` | 32 | r/w | guest features |
| `0x08` | 32 | r/w | queue PFN |
| `0x0C` | 16 | r/o | queue size |
| `0x0E` | 16 | r/w | queue select |
| `0x10` | 16 | r/w | queue notify |
| `0x12` | 8 | r/w | device status |
| `0x13` | 8 | r/o | ISR (clear-on-read) |
| `0x14` | — | — | device configuration begins |

Status bits: `ACKNOWLEDGE` `0x01`, `DRIVER` `0x02`, `DRIVER_OK` `0x04`,
`FAILED` `0x80`. (`FEATURES_OK` is VIRTIO 1.0 only and is not used.)

Initialisation follows the required handshake: reset (write `0`) →
`ACKNOWLEDGE` → `DRIVER` → read device features, write the accepted subset →
allocate and register queues → `DRIVER_OK`. Any abort writes `FAILED` and then
resets.

### Virtqueue layout

Split virtqueue, queue size `N`, page alignment `4096`:

- descriptor table — `N × 16` bytes (`u64 addr`, `u32 len`, `u16 flags`,
  `u16 next`); flags `NEXT 0x1`, `WRITE 0x2`, `INDIRECT 0x4`
- available ring — `u16 flags`, `u16 idx`, `u16 ring[N]`, `u16 used_event`
- padding to the next 4096 boundary
- used ring — `u16 flags`, `u16 idx`, `{u32 id; u32 len} ring[N]`,
  `u16 avail_event`

Total size is
`ALIGN(16·N + 2·(3+N), 4096) + 6 + 8·N`.

### DMA and the contiguity constraint

**This is the single largest technical risk in the design.** Legacy virtio
writes one *page frame number* to `QUEUE_PFN`, so each ring must be page-aligned
**and physically contiguous** across its whole length. DriverKit offers only
`IOMalloc`, with no contiguous or aligned allocator.

The strategy:

1. `IOMalloc(size + PAGE_SIZE)`.
2. Round the virtual address up to a page boundary.
3. Walk the region page by page calling `IOPhysicalFromVirtual`, asserting each
   physical page is contiguous with the previous.
4. On any discontinuity, free everything and fail the queue cleanly. **Never
   proceed with a partially valid ring.**

Rings are allocated at driver initialisation, while memory is least fragmented,
which makes success likely. Because likely is not certain, milestone 3 exists
solely to prove this in-guest before any driver depends on it.

### The ops vector

All register access and memory allocation is indirected, which is what allows
the core to be compiled and tested outside the kernel:

```c
struct virtio_ops {
    u8    (*in8)  (void *ctx, unsigned port);
    u16   (*in16) (void *ctx, unsigned port);
    u32   (*in32) (void *ctx, unsigned port);
    void  (*out8) (void *ctx, unsigned port, u8  v);
    void  (*out16)(void *ctx, unsigned port, u16 v);
    void  (*out32)(void *ctx, unsigned port, u32 v);
    void *(*alloc_pages)(void *ctx, unsigned len, u32 *paddr);
    void  (*free_pages) (void *ctx, void *va, unsigned len);
};
```

In the kernel these bind to the `ioPorts.h` inlines and to
`IOMalloc`/`IOPhysicalFromVirtual`. Under test they bind to a mock device model.

### Endianness

Legacy virtio uses **guest-native** byte order, so on i386 every field is
little-endian and the accessors are free. They exist explicitly anyway so that a
future ppc port must confront the question rather than silently produce
byte-swapped rings.

### Public API

```c
int   virtio_pci_attach(virtio_dev_t *, const struct virtio_ops *,
                        void *ctx, unsigned iobase);
u32   virtio_negotiate(virtio_dev_t *, u32 wanted);
void  virtio_set_status(virtio_dev_t *, u8 bits);
void  virtio_reset(virtio_dev_t *);
void  virtio_config_read(virtio_dev_t *, unsigned off, void *buf, unsigned len);
u8    virtio_read_isr(virtio_dev_t *);

int   virtqueue_alloc(virtio_dev_t *, unsigned index, virtqueue_t **out);
void  virtqueue_free(virtqueue_t *);
int   virtqueue_add_buf(virtqueue_t *, struct vio_sg *sg,
                        unsigned nout, unsigned nin, void *cookie);
void  virtqueue_kick(virtqueue_t *);
void *virtqueue_get_buf(virtqueue_t *, u32 *len);
```

## The drivers

Each driver is a controller object that owns the PCI attachment and virtqueues
through libvirtio, plus whatever family object the DriverKit stack expects.

### drvVirtioSCSI — `1af4:1004`, carries root

`VirtioSCSIController : IOSCSIController`, implementing the two required
`IOSCSIControllerExported` methods `executeRequest:buffer:client:` and
`resetSCSIBus`.

Queues: control (0), event (1), request (2). A command is one descriptor chain —
device-readable: an `8`-byte LUN, `u64` tag, task attribute, priority, CRN and a
32-byte CDB, followed by data-out; device-writable: `u32 sense_len`,
`u32 residual`, `u16 status_qualifier`, `u8 status`, `u8 response`, 96 bytes of
sense, followed by data-in.

LUN encodes as `{1, target, 0x40 | (lun >> 8), lun & 0xff, 0, 0, 0, 0}`.

**Status mapping.** virtio reports two separate things and they map to two
separate `IOSCSIRequest` fields (`driverkit/scsiRequest.h`): the `response` byte
is host-adapter level and becomes `driverStatus`; the `status` byte is the SCSI
status and is copied verbatim to `scsiStatus`. Residual becomes
`bytesTransferred`.

| virtio `response` | `driverStatus` |
|---|---|
| `S_OK`, SCSI status GOOD | `SR_IOST_GOOD` |
| `S_OK`, SCSI status CHECK CONDITION | `SR_IOST_CHKSV`, sense copied to `senseData` |
| `S_OK`, any other SCSI status | `SR_IOST_GOOD` — `scsiStatus` carries it upward |
| `S_BAD_TARGET` | `SR_IOST_SELTO` |
| `S_RESET` | `SR_IOST_RESET` |
| `S_ABORTED` | `SR_IOST_TABT` |
| `S_OVERRUN` | `SR_IOST_BCOUNT` |
| all others | `SR_IOST_HW` |

`senseData` is only meaningful when `driverStatus == SR_IOST_CHKSV`, which the
header states explicitly. Note there is **no** `SR_IOST_BUSY` in the enum —
a virtio `S_BUSY`, and a SCSI BUSY status, are distinct conditions and neither
invents a host-level code.

The caller's buffer is an address in a foreign `vm_task_t`, so it is translated
page by page with `IOPhysicalFromVirtual(client, …)` into a scatter list and
chained. `maxTransfer` and `getDMAAlignment:` are overridden to match the
device's advertised `seg_max` and `max_sectors`.

Everything above this driver — disk labels, partitioning, `sd0` naming — is
existing stack, which is precisely why root rides here.

### drvVirtioBlk — `1af4:1001`, data disks only

Mirrors EIDE's two-object split:

- `VirtioBlkController : IODirectDevice` owns PCI and the single request queue.
- `VirtioBlkDisk : IODisk <IODiskReadingAndWriting, IOPhysicalDiskMethods>` is
  the disk.

A request is a 16-byte header (`u32 type`, `u32 ioprio`, `u64 sector`), the data
buffer, then a one-byte status (`OK 0`, `IOERR 1`, `UNSUPP 2`). Types used:
`IN 0`, `OUT 1`, `FLUSH 4`. Capacity comes from device configuration in 512-byte
sectors; block size is 512 unless `VIRTIO_BLK_F_BLK_SIZE` is offered.

This driver is explicitly **not** a boot device in this spec.

### drvVirtioNet — `1af4:1000`

`VirtioNet : IOEthernet`, with receive (0) and transmit (1) queues. Only
`VIRTIO_NET_F_MAC` is negotiated — checksum offload, GSO, mergeable RX buffers
and the control queue are all declined, which fixes the per-buffer header at 10
bytes (`u8 flags`, `u8 gso_type`, `u16 hdr_len`, `u16 gso_size`,
`u16 csum_start`, `u16 csum_offset`) and keeps every buffer linear. The MAC
address is read from device configuration.

RX buffers are pre-posted at initialisation and refilled as the used ring
drains. `transmit:` maps a netbuf to physical pages, chains it behind a header,
and kicks; completions are reclaimed on interrupt. `IONetbufQueue` handles
queueing. `"Share IRQ Levels" = "YES"`.

### drvVirtioConsole — `1af4:1003`

`VirtioConsole : IODirectDevice`, with receive (0) and transmit (1) queues.
`VIRTIO_CONSOLE_F_MULTIPORT` is declined, so there is no control queue and only
port 0 exists.

It registers its own character device with `IOAddToCdevsw` — following
`IOParallelPort` — and drives a `struct tty` through the standard line
discipline, following `km.m`. Received bytes are pushed with `ttyinput()`; the
start routine drains the output clist into the transmit queue. The result is a
peer of `ISASerialPort`, usable for `getty`.

## Boot path and configuration

SeaBIOS has native virtio-blk and virtio-scsi support, so `boot0 → boot1 → boot`
read `mach_kernel` through ordinary INT13 calls — **no virtio driver of ours
participates before the kernel starts.**

`boot` then reads `"Boot Drivers"` from
`/usr/Devices/System.config/Instance0.table` and, for each named bundle, loads
its `Instance0.table` plus its `_reloc` binary through `sarld`
(`stringTable.c:532`). The kernel starts, DriverKit initialises the pre-loaded
driver, `probe:` attaches the PCI device, and the `IOSCSIController` stack
enumerates targets into `sd0`. Root mounts per `"Root Device" = "sd0a"`.
**No booter changes are required.**

`VirtioSCSI.config/Default.table`:

```
"Title"             = "Virtio SCSI Controller";
"Family"            = "SCSI";
"Bus Type"          = "PCI";
"Auto Detect IDs"   = "0x10041af4";
"Share IRQ Levels"  = "YES";
"Boot Driver"       = "Yes";
"Instance"          = "0";
"Server Name"       = "VirtioSCSI";
"Driver Name"       = "VirtioSCSI";
```

The other three follow the same shape with `"Auto Detect IDs"` of
`0x10011af4` (blk), `0x10001af4` (net), `0x10031af4` (console), families
`"Disk"`, `"Network"`, `"Serial"`, and no `"Boot Driver"` key.

Verification command line:

```
qemu-system-i386 -M pc -m 512 \
  -device virtio-scsi-pci-transitional,id=scsi0 \
  -drive if=none,id=hd0,file=rhapsody.img,format=raw \
  -device scsi-hd,drive=hd0,bus=scsi0.0 \
  -drive if=none,id=hd1,file=data.img,format=raw \
  -device virtio-blk-pci-transitional,drive=hd1 \
  -netdev user,id=n0 -device virtio-net-pci-transitional,netdev=n0 \
  -device virtio-serial-pci-transitional \
  -chardev stdio,id=c0 -device virtconsole,chardev=c0
```

Populating `/usr/Devices/` and `System.config` in the disk image is the
responsibility of the image builder
(`docs/specs/2026-07-24-image-builder-design.md`); this spec assumes that
mechanism and adds entries to it.

## Error handling

The device status register enforces the discipline: every failure path writes
`FAILED` and then resets by writing `0`, so a half-initialised device never
lingers.

- Feature negotiation that cannot meet a driver's requirements aborts in
  `probe:` and returns `NO`. No partial attach.
- A non-contiguous virtqueue allocation frees everything and fails the same way.
- Shared interrupts: read the ISR first; on zero, return immediately having
  touched no state, because the interrupt belonged to another device.
- Legacy virtio has no per-request timeout, but `IOSCSIRequest` supplies one:
  `timeoutLength`, in seconds. The SCSI driver arms its own timer from that
  value; expiry logs, resets the device, and completes outstanding requests with
  `driverStatus = SR_IOST_IOTO` rather than hanging the stack.
- Network: RX exhaustion drops and refills; TX-full returns an error so the
  layer above queues.
- Console: TX-full applies normal tty flow control.
- Descriptor exhaustion returns a distinct error so callers can retry rather
  than treating it as fatal.

Debug logging goes through a `Virtio.ddm` module in the style of `AMD_ddm.h` and
`VMXNet_ddm.h`. Operational messages use `IOLog` prefixed with the driver name,
matching existing convention.

## Testing

**There is no C compiler on the Windows host** (no `gcc`, `cc`, `clang`, or
`tcc`). Unit tests therefore compile and run in the **guest's userland** with the
same `cc` used for the kernel build — exactly as `src/rbuild-1` already does.
The testability argument holds: debugging ring logic as a userland program is
far cheaper than debugging it as a kernel panic. Installing MinGW or clang on
Windows later would let the same C core compile there unchanged; that is an
optimisation, not a prerequisite.

Tests follow the existing convention — `tests/test_X.c` using `tests/test.h`'s
`TEST`/`CHECK`/`CHECK_STR`, with a `make test` target linking only the objects
each test needs.

**Unit tier** — libvirtio's C core against a mock device:

- ring layout offsets and total size for several queue sizes
- descriptor chaining for out-only, in-only, and mixed requests
- available-index wraparound past 65535
- cookie round-trip through the used ring
- descriptor exhaustion returning cleanly without corrupting the free list
- repeated fill/drain cycles leaking no descriptors
- status-handshake ordering, including that every abort path writes `FAILED`
- contiguity checker rejecting a deliberately discontiguous mock allocation

**Smoke tier** — per driver in QEMU: enumeration first, then function.

**Integration tier** — root on virtio-scsi, the actual goal.

## Milestones

Each milestone has a single unambiguous check.

0. Existing `rhapsody.vmdk` boots on QEMU 11 → login prompt.
   **Hard gate; no driver work begins until this passes.**
1. libvirtio builds as a static `.a` with kernel flags mirrored; a stub driver
   links it and loads → `IOLog` output appears.
2. libvirtio unit tests green.
3. Page-aligned contiguous allocation succeeds in-guest → physical addresses
   logged and verified contiguous.
4. virtio-net enumerates and pings.
5. virtio-console tty echoes to host stdio; `getty` login works.
6. virtio-blk data disk read/write integrity round-trip.
7. virtio-scsi as a secondary disk.
8. virtio-scsi as root.

**Networking is deliberately first.** It exercises the entire transport and
virtqueue path end to end while being non-destructive and trivially observable;
if the ring works for net it works for everything. Storage comes last so ring
bugs surface before anything can corrupt the test image.

## Open risks

1. **QEMU 11 compatibility (milestone 0).** The in-tree QEMU is a 2007 fork with
   guest-specific patches (`-rhapsodymouse`). Whether the guest boots unmodified
   on a modern QEMU is unproven. If it does not, that becomes its own
   investigation and this spec stalls behind it.
2. **Physical contiguity.** Mitigated by allocating early and failing cleanly,
   proven by milestone 3, but there is no contiguous allocator to fall back on.
   If it proves unreliable, the fallback is adding a page-level contiguous
   allocator to DriverKit — a materially larger change.
3. **Kernel flags in a `library.make` project.** libvirtio must hand-replicate
   `-static -DKERNEL -D_KERNEL`. A mismatch may not fail at link time.
   Milestone 1 exists to catch this before four drivers depend on it.
4. **Booter BIOS-drive mapping with no IDE disk.** `sys.c:758` has a special case
   for `numIDEs == 0`, which a virtio-only machine hits and which has likely
   never been exercised. Keeping an IDE disk attached during bring-up sidesteps
   it; testing it deliberately is part of milestone 8.
5. **First shared library among the drivers.** No existing driver links one, so
   the `kl_ld` interaction is unproven in this tree, as is header-install
   ordering across the new `src/drivers/` root.
