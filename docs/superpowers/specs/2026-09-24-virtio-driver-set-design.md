# VirtIO driver set design (video, network, serial, block)

## Status

This design supersedes both earlier VirtIO designs:

- `docs/superpowers/specs/2026-07-24-virtio-drivers-design.md` — legacy
  transport; SCSI, block, network, console.
- `docs/superpowers/specs/2026-08-01-common-virtio-driver-set-design.md` —
  modern plus legacy transports; SCSI, block, input, console, network.

| Change | Reason |
|---|---|
| The drivers are GPU, network, console and block. SCSI and input are dropped. | Scope decision. |
| Modern PCI transport only. | virtio-gpu has no legacy interface, and QEMU 11 offers modern mode for all four devices. One transport halves the transport code and the test matrix. |
| Interrupts depend on a kernel prerequisite. | Both earlier designs assumed shared IRQs. The kernel keeps one handler per IRQ, and SeaBIOS routes every PCI interrupt to IRQ 10 or 11, so four devices cannot each own a line. |
| No `IOMallocLow`. | Its pool is carved permanently out of conventional memory below 640 KiB. Queues are capped to fit one page and come from `IOMalloc`. |
| BARs are read from PCI configuration space. | The PCI device description has no 64-bit BAR handling, and every modern VirtIO register window lives in a 64-bit BAR. |
| No 64-bit C types. | The in-tree compiler rejects `long long` under the flags the tests use. |
| Tests follow drvAHCI. | That is the established in-tree pattern for driver logic tests. |

## Goal

On `qemu-system-i386` 11.x with the i440FX `pc` machine, a RhapsodiOS guest
with all four devices attached at once:

1. boots with root on **virtio-blk** as `hd0a`,
2. runs the WindowServer on **virtio-gpu** (the `virtio-vga` device model),
3. has a working `enN` interface over **virtio-net**,
4. offers a login TTY on **virtio-console**,

while the four devices share IRQ 10 and IRQ 11 in pairs.

## Scope

**In scope:** a plain-C static `libvirtio` implementing the modern VirtIO PCI
transport and split virtqueues; four driver bundles; boot-driver packaging for
virtio-blk; unit tests; QEMU acceptance tests. i386 only.

**Out of scope:**

- The kernel shared-IRQ change itself. It is a prerequisite with its own spec
  (see below).
- The legacy and transitional VirtIO transports. A legacy backend can be added
  later behind the same transport interface.
- VirtIO SCSI, input, balloon, RNG, filesystem, sound and every other device
  type.
- MSI and MSI-X. The kernel drives a 16-line PIC only.
- Packed virtqueues, indirect descriptors, event-index notification suppression
  and multiqueue.
- virtio-gpu 3D, blob resources, EDID, the hardware cursor queue, multiple
  scanouts and host-driven resolution changes.
- Network checksum and segmentation offload, mergeable receive buffers and the
  network control queue.
- Console multiport, emergency write, and any role as an early or kernel
  console. The i386 16550 kernel console remains a separate, still-wanted spec.
- Block discard, write-zeroes and topology features.
- PowerPC.

## Prerequisite: shared interrupts in the kernel

This design cannot reach its goal without a separate `kernel-7` spec. With
SeaBIOS's routing (measured below), GPU and block share IRQ 10 and network and
console share IRQ 11. Today only the first driver to register on each line
receives interrupts. drvAHCI hit exactly this and dropped sharing in
`95af26861`.

The contract this design relies on:

1. Several DriverKit devices may attach to one IRQ when each declares
   `"Share IRQ Levels" = "YES"`. A shared line is programmed level-triggered.
2. On each assertion, every attached device's handler runs.
   `IOInterruptHandler` returns `void`, so the dispatcher calls all of them
   rather than stopping at a claimant.
3. A driver's direct handler, obtained through
   `getHandler:level:argument:forInterrupt:`, runs at interrupt level. Once every
   attached handler has returned, the line is re-enabled without waiting on any
   driver's IOThread.
4. Devices that do not declare sharing behave exactly as they do today.

Registration refuses a second handler in
`src/kernel-7/machdep/i386/intr.c` (`intr_register_irq`), and DriverKit devices
reach it through `drvEISABus`'s `EISAKernBusInterrupt.m`, which registers one
handler per IRQ and disables the line during dispatch. Both change under that
spec. Its natural first acceptance test is the reverted two-controller AHCI
case.

Each driver here can be developed and tested alone before the prerequisite
lands, because a single VirtIO device owns its line. Only the combined
acceptance run depends on it.

## Measured facts

QEMU 11.1.0, SeaBIOS, `-M pc -m 512`, measured on 2026-09-24 with `info pci`
from the monitor after firmware had run:

| Slot | Device model | PCI ID | IRQ | Memory BARs |
|---|---|---|---|---|
| 2 | `virtio-vga` | `1af4:1050`, class VGA | 10 | BAR0 32-bit prefetchable, 8 MiB at `0xfe000000`; BAR2 64-bit prefetchable at `0xfe800000`; BAR4 32-bit |
| 3 | `virtio-net-pci-non-transitional` | `1af4:1041` | 11 | BAR1 32-bit; BAR4 64-bit prefetchable at `0xfe804000` |
| 4 | `virtio-serial-pci-non-transitional` | `1af4:1043` | 11 | BAR1 32-bit; BAR4 64-bit prefetchable at `0xfe808000` |
| 5 | `virtio-blk-pci-non-transitional` | `1af4:1042` | 10 | BAR1 32-bit; BAR4 64-bit prefetchable at `0xfe80c000` |

- SeaBIOS uses **only IRQ 10 and IRQ 11** for PCI INTx (plus IRQ 9 for the
  PIIX4 power-management function). Four PIRQ lines fold onto two IRQs, so no
  slot placement avoids sharing.
- Every memory BAR landed **below 4 GiB**.
- `virtio-vga` exposes an 8 MiB linear VRAM window in BAR0 in addition to its
  VirtIO registers. `virtio-gpu-pci` does not.

## Ground truth from sources

- **One handler per IRQ.** `intr_register_irq` returns `FALSE` when
  `dispatch_table[irq].routine` is already set
  (`src/kernel-7/machdep/i386/intr.c:489`). `INTR_NIRQ` is 16
  (`intr_internal.h:48`); there is no MSI support.
- **DriverKit interrupt path.** `EISAKernBusInterrupt.m` calls
  `intr_register_irq` once per IRQ (line 88) and sets the trigger mode from its
  `shareable` argument (line 89). `IOInterruptHandler` is
  `void (*)(void *identity, void *state, unsigned int arg)`
  (`driverkit/driverTypes.h:248`). `getHandler:level:argument:forInterrupt:`
  (`driverkit/IODirectDevice.h:89`) supplies a direct handler, and
  `IOSendInterrupt` (`IODirectDevice.h:111`) forwards to the IOThread.
- **`IOMallocLow` is scarce.** It calls `dma_buf_alloc`, capped at
  `DMA_BUF_LG_LEN` = 64 KiB (`machdep/i386/dma_exported.h:42`), whose regions
  come from `alloc_cnvmem`: a bump allocator between `first_addr0` and
  `KB(cnvmem)`, i.e. conventional memory below 640 KiB, which never returns
  memory (`machdep/i386/i386_init.c`). drvAHCI already hands arena memory back
  to relieve this pool (`c51f3c2f5`).
- **64-bit BARs.** A search of `driverkit-3/libDriver/pci/` and `drvPCIBus`
  found no handling of 64-bit BAR types.
- **Physical mapping.** `IOMapPhysicalIntoIOTask(unsigned phys, unsigned len,
  vm_address_t *va)` (`driverkit/kernelDriver.h:113`) takes a 32-bit physical
  address.
- **Timers.** `IOScheduleFunc` takes whole seconds
  (`driverkit/generalFuncs.h:101`). `IOForkThread` (line 62) and
  `IOSleep(milliseconds)` (line 89) provide sub-second loops.
- **Display contract.** Display drivers hand the WindowServer a physically
  contiguous VRAM range through `mapFrameBufferAtPhysicalAddress:length:`
  (`driverkit/IOFrameBufferDisplay.h:91`; used by S3Generic, MatroxMGA,
  CirrusLogicGD5434 and the ATI drivers). `IO_24BitsPerPixel` is 32 bpp with 24
  bits used (`driverkit/displayDefs.h:46`). `"Display"` is an established
  `Family`.
- **IOEthernet contract**, as drvVMwareVMXNet uses it: `resetAndEnable:`,
  `attachToNetworkWithAddress:`, `IONetbufQueue initWithMaxCount:`, `nb_alloc`,
  `handleInputPacket:extra:` and `transmit:`.
- **The `hd` registry.** `src/kernel-7/bsd/dev/ata_hd_registry.h` provides
  `ata_hd_devsw_init`, `ata_hd_register` and `ata_hd_set_flush`. `AHCIDisk.m`
  takes a global unit, installs a flush callback and publishes `hdN`
  (lines 53–69). AHCI's tables carry `"Block Major" = "3"`,
  `"Character Major" = "15"`, `"Class Names"` and a `"Post-Load"` tool.
- **Device nodes for dynamic majors** are made by a load tool: AHCI's
  `PostLoad.tproj/PostLoad.m` (`makeNode`) and PCParallel's
  `PreLoad.tproj/InstallPPDev.m`.
- **Character devices and TTYs.** Drivers register with `IOAddToCdevsw`
  (`IOParallelPort.m:138`); the in-kernel TTY model is `km.m` (`km_tty[]`,
  `bsd/dev/i386/conf.c:201`).
- **Locks.** DriverKit kernel code uses `NXLock` (for example
  `IOSCSIController`'s `_reserveLock`, and `libDriver/Kernel/Audio*.m`).
- **Return codes** used below exist in `driverkit/return.h`: `IO_R_IO`,
  `IO_R_UNSUPPORTED`, `IO_R_TIMEOUT`, `IO_R_NOT_WRITABLE`, `IO_R_NO_MEMORY`,
  `IO_R_NO_DEVICE`.
- **No 64-bit integer types.** drvAHCI keeps even LBA48 addresses in
  `unsigned int` (`AHCICommand.h`), and its tests build with
  `cc -ansi -pedantic -Wall -Werror -traditional-cpp` on cc-783.1, under which
  gcc 2.7.2.1 rejects `long long`.
- **Booter.** It reads `"Boot Drivers"` (`boot-2/gen/libsaio/stringTable.c:532`).
  PCI auto-detect IDs are encoded `(device << 16) | vendor`.
- **Root on `hd0a` without IDE disks** has precedent: the drvAHCI bootable-core
  design boots `hd0a` on q35, which has no PIIX IDE.

## Repository layout

```
src/drivers/generic/libvirtio-1/
src/drivers/i386/storage/drvVirtioBlk/
src/drivers/i386/network/drvVirtioNet/
src/drivers/i386/serial/drvVirtioConsole/
src/drivers/i386/video/drvVirtioGPU/
```

This keeps the 2026-08-01 layout. `src/drivers/` does not exist yet; creating
`src/drivers/i386/` ahead of the planned migration of `drivers-i386` is
intentional. The library is arch-neutral C. The drivers are i386-only because
they depend on i386 DriverKit and PC firmware behaviour.

libvirtio builds with `LIBRARY_STYLE = STATIC`. Its `Makefile.preamble` mirrors
the kernel-server flags that `kernelserver.make` would otherwise inject
(`-static -DKERNEL -D_KERNEL`). Each driver adds the archive to `OTHER_LIBS`,
and `kl_ld` folds it into the driver's single `_reloc`. The library must be
built, and its headers installed, before any driver. The build box runs GNU
Make 3.74, so the makefiles use no target-specific variables.

## libvirtio

### Layers

1. **Platform operations** — the only kernel-facing code: PCI configuration
   access, register access, physical mapping, page allocation, address
   translation and delay.
2. **Modern PCI transport** — capability discovery, common configuration,
   notification, ISR and device configuration.
3. **Split virtqueue core** — ring layout, descriptor free list, chains,
   completion and teardown.
4. **Device facade** — status transitions, feature negotiation, device
   configuration reads, queue lifetime and ISR reads.

Family drivers call only the facade and the virtqueue API.

### Platform operations

```c
struct virtio_platform {
    void *ctx;
    int   (*cfg_read32)  (void *ctx, unsigned off, u32 *val);
    int   (*cfg_write32) (void *ctx, unsigned off, u32 val);
    u8    (*read8)  (void *ctx, volatile void *addr);
    u16   (*read16) (void *ctx, volatile void *addr);
    u32   (*read32) (void *ctx, volatile void *addr);
    void  (*write8) (void *ctx, volatile void *addr, u8  v);
    void  (*write16)(void *ctx, volatile void *addr, u16 v);
    void  (*write32)(void *ctx, volatile void *addr, u32 v);
    int   (*map_phys)(void *ctx, u32 phys, u32 len, volatile void **va);
    void  (*unmap)   (void *ctx, volatile void *va, u32 len);
    void *(*alloc_page)(void *ctx, u32 *phys);
    void  (*free_page) (void *ctx, void *va);
    int   (*virt_to_phys)(void *ctx, void *va, u32 *phys);
    void  (*delay_us)(void *ctx, unsigned us);
};
```

In the kernel, configuration access uses the device's
`getPCIConfigData:atRegister:` and `setPCIConfigData:atRegister:`, which are
32-bit aligned only, so capability bytes are extracted from aligned words.
Register access is a volatile load or store. `map_phys` uses
`IOMapPhysicalIntoIOTask`. `alloc_page` over-allocates two pages from `IOMalloc`
and returns the first page-aligned page; one page is always physically
contiguous. Under test, register access dispatches to a mock device model so
that it can react to writes.

`u8`, `u16` and `u32` are the only integer widths. A 64-bit wire field is read
and written as two 32-bit halves, low half first. Every physical address fits
in 32 bits, because BARs and RAM must lie below 4 GiB.

### Modern PCI transport

**Discovery.** The transport sets memory-space and bus-master enable in the PCI
command register and clears INTx-disable. Configuration writes are 32-bit only,
so the dword at `0x04` is written with its status half zero; writing back the
status bits read would clear the write-one-to-clear ones. It then walks the capability list
(status bit 4, pointer at `0x34`). The walk visits at most 48 entries and
ignores pointers below `0x40`. For each vendor-specific capability (ID `0x09`)
it reads `cfg_type` (+3), `bar` (+4), `offset` (+8) and `length` (+12); the
notify capability adds `notify_off_multiplier` (+16). The first capability of
each type wins: common (1), notify (2), ISR (3), device (4). PCI-configuration
access (5) is ignored.

**Validation.** Probe fails unless common, notify and ISR are present, and
device configuration is present whenever the family needs it. Each window's
`bar` must be 0–5 and name a memory BAR. For a 64-bit BAR the upper dword must
be zero, since a BAR above 4 GiB is unreachable. Lengths must cover the
structure they hold: common at least `0x38`, ISR at least 1, notify at least 2,
device at least the family's configuration size.

**Mapping.** The BAR base is read from configuration space, never from the
device description. Each window is mapped separately, rounded out to pages.

**Common configuration.**

| Offset | Field |
|---|---|
| `0x00` | `device_feature_select` |
| `0x04` | `device_feature` |
| `0x08` | `driver_feature_select` |
| `0x0C` | `driver_feature` |
| `0x10` | `msix_config` |
| `0x12` | `num_queues` |
| `0x14` | `device_status` |
| `0x15` | `config_generation` |
| `0x16` | `queue_select` |
| `0x18` | `queue_size` |
| `0x1A` | `queue_msix_vector` |
| `0x1C` | `queue_enable` |
| `0x1E` | `queue_notify_off` |
| `0x20` | `queue_desc` (64-bit) |
| `0x28` | `queue_driver` (64-bit) |
| `0x30` | `queue_device` (64-bit) |

Status bits: `ACKNOWLEDGE` `0x01`, `DRIVER` `0x02`, `DRIVER_OK` `0x04`,
`FEATURES_OK` `0x08`, `DEVICE_NEEDS_RESET` `0x40`, `FAILED` `0x80`.

**Initialisation.**

1. Write status 0, then poll until it reads 0, for at most one second.
2. Set `ACKNOWLEDGE`, then `DRIVER`.
3. Read both device feature words.
4. Require `VIRTIO_F_VERSION_1` (bit 32). The driver's features are
   `VERSION_1` plus the family's wanted set intersected with what the device
   offers. A missing required family feature fails probe.
5. Write the driver features, set `FEATURES_OK`, and read the status back. If
   `FEATURES_OK` did not stick, fail.
6. For each queue: select it and read `queue_size`. Zero means the queue does
   not exist, which fails probe for a required queue. Choose `N` as the smaller
   of `queue_size` and 128, rounded down to a power of two, and write it back.
   Allocate the ring page, write the three physical addresses (upper halves
   zero), read `queue_notify_off`, and set `queue_enable`.
7. Run family setup, such as pre-posting receive buffers, and then set
   `DRIVER_OK`.

MSI-X is never enabled, so the device signals through INTx and the MSI-X vector
fields are left alone. A queue is notified by writing its index as a 16-bit
value to `notify window + queue_notify_off × notify_off_multiplier`. Reading the
ISR byte returns bit 0 for queue activity and bit 1 for a configuration change,
clears it, and deasserts INTx. Device configuration reads are wrapped in a
`config_generation` check and retried until two reads agree.

All modern fields are little-endian. The accessors convert explicitly, which is
free on i386.

### Split virtqueues

With `N ≤ 128`, one ring fits in one page with no padding between its parts:

| Part | Offset | Size |
|---|---|---|
| Descriptor table | 0 | `16·N` |
| Available ring | `16·N` | `6 + 2·N` |
| Used ring | `ALIGN(18·N + 6, 4)` | `6 + 8·N` |

At `N = 128` the ring ends at byte 3,342. At `N = 256` it would not fit, which
is why the cap is 128.

The queue object owns the ring, a descriptor free list, a per-head cookie and
chain length, and its producer and consumer indices.

- **Add** takes device-readable segments followed by device-writable segments,
  needs that many free descriptors, chains them with `NEXT`, sets `WRITE` on
  the device-writable ones, and publishes the head in the available ring. A
  write barrier separates filling the descriptors from bumping the available
  index.
- **Kick** writes the notify register after a barrier, unless the device has
  set `VIRTQ_USED_F_NO_NOTIFY`.
- **Get** compares the saved used index with the device's, applies a read
  barrier, and validates the returned head: it must be below `N` and in flight.
  It then frees the chain and returns the cookie and written length.
- **Teardown** completes every in-flight cookie through a family error
  callback.

On i386 the read and write barriers are compiler barriers, since x86 does not
reorder stores with stores or loads with loads. A full barrier uses a locked
instruction.

### Interrupt path

Every driver supplies a direct handler through
`getHandler:level:argument:forInterrupt:`. The handler reads the ISR byte, which
clears it and lets the device drop INTx. If the byte is zero the interrupt
belonged to another device on the shared line, and the handler returns. If not,
it records the bits and calls `IOSendInterrupt` to wake the driver's IOThread,
which drains used rings, refills receive buffers and handles configuration
changes.

The handler touches only the ISR and the recorded bits. Each queue has one
`NXLock`, taken by whichever thread submits to or drains it, so no queue lock is
ever taken at interrupt level.

### Memory budget

Rings come from `IOMalloc`, six in total: block 1, network 2, console 2, GPU 1.
Each uses one page out of a two-page allocation, so rings cost twelve pages of
ordinary kernel memory. Payload buffers also come from `IOMalloc` and are translated
page by page; a buffer that crosses a page boundary becomes two segments.
Nothing is taken from the `IOMallocLow` pool.

## Drivers

### drvVirtioBlk — `1af4:1042`, carries root

`VirtioBlkController : IODirectDevice` owns the PCI function and the request
queue. `VirtioBlkDisk : IODisk <IODiskReadingAndWriting, IOPhysicalDiskMethods>`
is the disk. This is the controller/disk split used by drvEIDE and drvAHCI.

- **Features:** `VERSION_1` is required. `SIZE_MAX` (1), `SEG_MAX` (2),
  `RO` (5), `BLK_SIZE` (6) and `FLUSH` (9) are accepted when offered; all others
  are declined.
- **Geometry:** capacity is read as a 64-bit count of 512-byte sectors. A disk
  larger than 2³² sectors is clamped to that, with a logged warning, because
  `IODisk` block counts are 32-bit. A device whose `BLK_SIZE` is not 512 is
  declined with a logged reason.
- **Requests** are a device-readable 16-byte header (`le32 type`,
  `le32 reserved`, `le64 sector`), the data segments, and a device-writable
  status byte. Types used are IN 0, OUT 1 and FLUSH 4. Status OK 0, IOERR 1 and
  UNSUPP 2 map to `IO_R_SUCCESS`, `IO_R_IO` and `IO_R_UNSUPPORTED`.
- **Transfer size** is bounded by `SEG_MAX`, `SIZE_MAX` and free descriptors;
  larger requests are split.
- **Read-only:** `RO` makes the disk write-protected, and writes return
  `IO_R_NOT_WRITABLE`.
- **Flush:** when `FLUSH` is negotiated, a flush callback is installed with
  `ata_hd_set_flush`. Without it the device is write-through and flush succeeds
  immediately.
- **Publication:** the disk registers in the shared `hd` registry exactly as
  `AHCIDisk` does and publishes `hdN`. Unit numbers are global across drvEIDE,
  drvAHCI and drvVirtioBlk, so the root name depends on publication order. The
  acceptance configuration has no IDE or AHCI disks, which makes the virtio
  disk `hd0`.
- **Timeouts:** VirtIO has none, so the controller keeps a 30-second watchdog
  per request. Expiry triggers a runtime reset and fails in-flight requests
  with `IO_R_TIMEOUT`.
- **Configuration:** `Default.table` sets `"Boot Driver"`, `"Block Major" = "3"`,
  `"Character Major" = "15"`, `"Class Names" = "VirtioBlkController"`,
  `"Family" = "Disk"`, `"Bus Type" = "PCI"`,
  `"Auto Detect IDs" = "0x10421af4"`, `"Share IRQ Levels" = "YES"`, and a
  `"Post-Load"` tool that makes the `/dev` nodes, following AHCI's.

### drvVirtioNet — `1af4:1041`

`VirtioNet : IOEthernet`, publishing `enN`.

- **Features:** `VERSION_1` and `MAC` (5) are required, and `STATUS` (16) is
  accepted when offered. Checksum, segmentation, mergeable receive buffers, the
  control queue and multiqueue are declined.
- **Header:** with `VERSION_1` negotiated, the per-packet header is always
  12 bytes (`flags`, `gso_type`, `hdr_len`, `gso_size`, `csum_start`,
  `csum_offset`, `num_buffers`), whether or not mergeable buffers are in use.
  Both earlier designs said 10 bytes, which is the legacy size.
- **Receive** (queue 0): every descriptor slot is pre-posted with a fixed
  `IOMalloc` buffer large enough for the header plus a 1,514-byte frame. On
  completion the frame is copied into `nb_alloc` storage, handed up with
  `handleInputPacket:extra:`, and the buffer is re-posted. Frames that are too
  short, too long or malformed are dropped and re-posted.
- **Transmit** (queue 1): `transmit:` copies the frame behind a zeroed header
  into a per-slot `IOMalloc` buffer and submits it. When the ring is full,
  frames wait in an `IONetbufQueue`. Completions free their slots and drain the
  backlog.
- **Link:** with `STATUS`, a configuration-change interrupt re-reads link state
  and logs transitions.
- **Configuration:** `"Family" = "Network"`,
  `"Auto Detect IDs" = "0x10411af4"`, `"Share IRQ Levels" = "YES"`.

### drvVirtioConsole — `1af4:1043`

`VirtioConsole : IODirectDevice`, exposing port 0 as a TTY.

- **Features:** `VERSION_1` only. `SIZE`, `MULTIPORT` and `EMERG_WRITE` are
  declined, so only receive queue 0 and transmit queue 1 exist.
- **TTY:** the driver registers its own character device with `IOAddToCdevsw`,
  as `IOParallelPort` does, and drives a `struct tty` through the standard line
  discipline following `km.m`. Received bytes enter through `ttyinput()`. The
  start routine drains the output clist into transmit buffers, and transmit
  completion restarts output, which gives normal backpressure.
- **Node:** `/dev/ttyv0`, made by a load tool following `InstallPPDev`. A
  `getty` line in `/etc/ttys` is image configuration and outside this design.
- **Not a kernel console:** nothing is printed before the PCI function,
  bundle and queues are up.
- **Configuration:** `"Family" = "Serial"`,
  `"Auto Detect IDs" = "0x10431af4"`, `"Share IRQ Levels" = "YES"`.

### drvVirtioGPU — `1af4:1050`, `virtio-vga` only

`VirtioGPUDisplay : IOFrameBufferDisplay`.

**Why `virtio-vga`.** DriverKit displays hand the WindowServer a physically
contiguous VRAM range. `virtio-vga` has one (BAR0, 8 MiB); `virtio-gpu-pci` has
none. Probe therefore requires PCI class VGA and a memory BAR0 large enough for
the selected mode, and declines `virtio-gpu-pci`. BAR0's size is found once at
probe by the standard sizing sequence — memory decode off, write all ones, read
back, restore — since the device description is not trusted for BARs. `virtio-vga` also stays
VGA-compatible until the driver takes it over, so the booter and early text
console keep working.

- **Features:** `VERSION_1` only. VIRGL, EDID, resource UUID, blob resources and
  context initialisation are declined. Only control queue 0 is enabled; the
  cursor queue stays disabled, because `IOFrameBufferDisplay` draws a software
  cursor.
- **Pixels:** virtio-gpu has no 8- or 16-bit formats, so every mode is 32 bpp:
  `IO_24BitsPerPixel`, RGB, pixel encoding
  `--------RRRRRRRRGGGGGGGGBBBBBBBB`, which is
  `VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM` (2).
- **Modes:** 640×480, 800×600, 1024×768 and 1280×1024. A mode whose
  `rowBytes × height` exceeds BAR0 is marked invalid. Selection uses the
  standard `selectMode:count:valid:` path and the configuration table.

**Commands.** Every request begins with a 24-byte control header (`le32 type`,
`le32 flags`, `le64 fence_id`, `le32 ctx_id`, `le32 padding`), and every
response begins with a 24-byte header whose type is `OK_NODATA` (`0x1100`),
`OK_DISPLAY_INFO` (`0x1101`) or an error (`0x1200` and up).

**Mode set** (`enterLinearMode`) runs before the flush thread exists. Each step
waits for its response by polling the used ring, for at most one second:

1. `GET_DISPLAY_INFO` (`0x0100`), which must report scanout 0.
2. `RESOURCE_CREATE_2D` (`0x0101`): resource 1, format 2, width, height.
3. `RESOURCE_ATTACH_BACKING` (`0x0106`): resource 1 with a single entry, the
   BAR0 physical address and `rowBytes × height`.
4. `SET_SCANOUT` (`0x0103`): scanout 0 shows resource 1.
5. `TRANSFER_TO_HOST_2D` (`0x0105`) and `RESOURCE_FLUSH` (`0x0104`) over the
   full screen.

The framebuffer is then mapped with `mapFrameBufferAtPhysicalAddress:length:` on
BAR0, exactly as the VRAM-based drivers do, and the WindowServer draws straight
into it.

**Key assumption — VRAM as resource backing.** The virtio-gpu specification
describes backing as guest memory, and BAR0 is device memory. QEMU resolves
backing addresses through the device's DMA address space, in which BAR0 is RAM
mapped at its bus address, so this should work. But that is QEMU behaviour, not
a specification guarantee, and it is unproven here. The GPU milestone proves it
first. If it fails, the fallback keeps the WindowServer contract unchanged —
the WindowServer still draws into BAR0 — and attaches separate `IOMalloc` pages
as backing. The flush loop then copies BAR0 into them before each transfer, at a
lower flush rate to bound the cost of copying a full frame in the guest.

**Flush loop.** The WindowServer reports no damage, so a thread started with
`IOForkThread` loops on `IOSleep(33)` and submits a full-screen
`TRANSFER_TO_HOST_2D` and `RESOURCE_FLUSH`. At most one such pair is in flight;
if the previous pair has not completed, the tick is skipped. The IOThread
reclaims completions and logs display configuration changes.

**Returning to VGA** (`revertToVGAMode`) stops the flush thread and resets the
device, which returns `virtio-vga` to VGA compatibility. That reset behaviour is
also unproven and is checked in the GPU milestone.

**Configuration:** `"Family" = "Display"`,
`"Auto Detect IDs" = "0x10501af4"`, `"Share IRQ Levels" = "YES"`.

## Boot and configuration

The booter reads `mach_kernel` through SeaBIOS's INT 13h, so no RhapsodiOS
VirtIO code runs before the kernel. drvVirtioBlk must be listed in
`"Boot Drivers"`, with `"Root Device" = "hd0a"`. The other three drivers may be
boot drivers or load later, as existing display and network drivers do; that is
a configuration choice, not a design constraint.

Acceptance command line, run against a temporary copy of the image:

```
qemu-system-i386 -M pc -m 512 \
  -vga none -device virtio-vga,addr=2 \
  -netdev user,id=n0 \
  -device virtio-net-pci-non-transitional,netdev=n0,addr=3 \
  -device virtio-serial-pci-non-transitional,addr=4 \
  -chardev stdio,id=c0 -device virtconsole,chardev=c0 \
  -drive if=none,id=hd0,file=rhapsody-virtio-test.img,format=raw \
  -device virtio-blk-pci-non-transitional,drive=hd0,addr=5,bootindex=0
```

Pinning the slots reproduces the measured routing, so GPU and block share
IRQ 10 and network and console share IRQ 11. The acceptance run exercises
sharing on both lines deliberately.

## Error handling

- **Probe and initialisation** failures unwind queues and mappings, set
  `FAILED`, reset the device and decline. A half-initialised family object is
  never registered. Every decline logs why.
- **Negotiation:** a missing required feature, a `FEATURES_OK` that does not
  stick, or a missing required queue declines the device.
- **Shared line:** an ISR of zero returns immediately.
- **Runtime reset** is triggered by `DEVICE_NEEDS_RESET`, a used-ring head that
  is out of range or not in flight, or a block watchdog expiry. It stops new
  submissions, completes every in-flight cookie with an error, resets the
  device, rebuilds the queues and renegotiates before resuming. Descriptors the
  device might still own are never reused.
- **GPU:** a failed mode set leaves the device in VGA mode and declines. A
  failed flush is logged once and the loop continues.
- **Attach log:** each driver logs its capability windows, queue sizes,
  negotiated features and IRQ.

## Testing

The Windows host has no C compiler, so unit tests build and run on the build
box, under a private build root, with cc-783.1. They follow drvAHCI: logic lives
in plain-C files beside the Objective-C, each test links only the C it
exercises, and `tests/Makefile` uses
`CFLAGS = -ansi -pedantic -Wall -Werror -traditional-cpp`.

**libvirtio**, against a mock platform and device:

- capability walk: complete set; each required capability missing; a cycle; a
  pointer below `0x40`; a 64-bit BAR with a non-zero upper dword; a short
  capability length
- initialisation: status order; `VERSION_1` absent; `FEATURES_OK` dropped;
  every failure path ending in `FAILED` then reset
- queues: size zero means absent; clamping to 128 and to a power of two; the
  layout fitting one page; programmed addresses; notify address arithmetic
- rings: device-readable-only, device-writable-only and mixed chains;
  exhaustion; 16-bit index wraparound; an out-of-range used head; a double
  completion; teardown completing every cookie
- ISR: zero does nothing; bit 1 takes the configuration path
- `config_generation` retry

**Family logic:**

- block: request encoding, status mapping, capacity clamp, read-only handling,
  split transfers
- network: 12-byte header, receive header stripping, runt and oversize drops,
  transmit slot reuse
- console: receive delivery and transmit backpressure
- GPU: every command's size and field offsets, mode validation against BAR0,
  pixel format mapping

Unit tests do not prove the kernel flags, so every source must also build with
the project makefiles on the box.

**QEMU acceptance**, each on a temporary image copy:

1. Root boot from virtio-blk `hd0a` with no other VirtIO devices.
2. The full command line above: WindowServer on virtio-gpu, ping and TCP over
   `enN`, login on `/dev/ttyv0`, and sustained concurrent disk, network and
   console traffic with no lost or duplicate completions.
3. `revertToVGAMode`: after the device reset, VGA text output is visible again.

## Milestones

Each milestone has a single check.

0. The existing image boots unmodified on QEMU 11 `pc` with emulated IDE,
   standard VGA and NE2000 → login prompt. **Gate for all driver work.**
1. libvirtio builds as a static archive with kernel flags, and its unit tests
   pass on the box.
2. A diagnostic driver attaches to one modern device, maps its capability
   windows from configuration-space BARs, negotiates, enables a queue, and logs
   the result. This proves 64-bit BAR mapping before any family driver depends
   on it.
3. drvVirtioBlk: read/write integrity on a data disk while booted from IDE, then
   root boot from `hd0a` with IDE removed.
4. drvVirtioGPU: a test pattern written to BAR0 appears in the QEMU window
   through `TRANSFER_TO_HOST_2D` (proving VRAM backing), the device reset
   returns to VGA, and then the WindowServer runs.
5. drvVirtioNet: ping and TCP.
6. drvVirtioConsole: echo to host stdio, then a `getty` login.
7. The kernel shared-IRQ prerequisite lands and passes its own acceptance.
8. Combined acceptance with sharing on IRQ 10 and IRQ 11.

Block comes first because root boot is both the highest-value and the
highest-risk requirement; the diagnostic driver has already proven the
transport without touching a disk. The GPU is second because it rests on the
least-proven assumption.

## Risks

1. **The kernel prerequisite.** Without it only one driver per IRQ receives
   interrupts, and the combined configuration cannot work. Each driver can
   still be built and tested alone.
2. **VRAM as virtio-gpu backing** depends on QEMU behaviour, not the
   specification. The fallback works but copies a full frame in the guest on
   every flush.
3. **BARs above 4 GiB.** SeaBIOS placed every BAR below 4 GiB at 512 MiB of RAM.
   A guest configuration that pushes a 64-bit BAR higher makes the driver
   decline, with a logged reason.
4. **Panic output.** While virtio-gpu owns the scanout, console text drawn into
   BAR0 appears only when flushed. A panic shows nothing unless the kernel
   returns the display to VGA. That path is not established.
5. **`hd` unit order.** Root naming depends on the order in which drvEIDE,
   drvAHCI and drvVirtioBlk publish disks.
6. **Historical compiler.** libvirtio must stay within gcc 2.7.2.1 under
   `-ansi -pedantic`, including the barrier syntax. Box builds are the only
   proof.
