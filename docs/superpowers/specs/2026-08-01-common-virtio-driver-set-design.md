# Common VirtIO driver set design

## Status and relationship to the earlier design

This design supersedes
`docs/superpowers/specs/2026-07-24-virtio-drivers-design.md`. The earlier design
covered legacy VirtIO PCI for SCSI, block, network, and console, and explicitly
deferred VirtIO input. This replacement adds the modern PCI transport, a single
input bundle for keyboard and mouse devices, and root-disk support through both
VirtIO SCSI and VirtIO block.

## Goal

Give RhapsodiOS i386 a common VirtIO implementation and five independently
loadable driver bundles:

- VirtIO SCSI
- VirtIO block
- VirtIO input, supporting keyboard and relative mouse instances
- VirtIO console, exposed as a TTY
- VirtIO network

The shared implementation must support both modern and legacy/transitional
VirtIO PCI. SCSI and block must each be capable of carrying the root filesystem.

Success means that QEMU 11.x can boot RhapsodiOS from either VirtIO SCSI or
VirtIO block over either applicable PCI transport, and that a modern-device
guest has working keyboard, mouse, console, and network devices at the same
time.

## Scope

### In scope

- i386 only.
- A plain-C static `libvirtio` linked into each driver bundle.
- Modern VirtIO 1.x PCI transport.
- Legacy VirtIO 0.9.x PCI transport on transitional devices.
- Split virtqueues.
- Interrupt-driven operation with shared PCI IRQ support.
- Boot-driver packaging for VirtIO SCSI and VirtIO block.
- One VirtIO input bundle that selects keyboard or pointer behavior from the
  device's advertised event bitmap.
- Host-side unit and protocol tests plus QEMU guest acceptance tests.

### Out of scope

- PowerPC and VirtIO MMIO.
- Packed virtqueues, MSI-X, indirect descriptors, and device multiqueue.
- VirtIO GPU, balloon, RNG, filesystem, sound, and other VirtIO device types.
- Absolute tablets, multitouch, force feedback, and general consumer-control
  input devices.
- Network checksum or segmentation offload, mergeable receive buffers, and the
  network control queue.
- VirtIO console multiport support and use as an early kernel console.
- Block discard and write-zeroes operations.

## Chosen architecture

The implementation consists of one shared static library and five separate
driver bundles. A monolithic all-device kernel server was rejected because it
would couple unrelated families and enlarge the boot-critical failure domain.
Copying the transport into each driver was rejected because it would duplicate
the most subtle queue and negotiation code five times.

Each `_reloc` binary statically links its own copy of `libvirtio`. No driver has
a runtime dependency on another kernel server, which is required for reliable
root-driver loading.

Proposed repository layout:

```text
src/drivers/generic/libvirtio-1/
src/drivers/i386/storage/drvVirtioSCSI/
src/drivers/i386/storage/drvVirtioBlk/
src/drivers/i386/input/drvVirtioInput/
src/drivers/i386/serial/drvVirtioConsole/
src/drivers/i386/network/drvVirtioNet/
```

The library core avoids i386 assumptions where doing so adds no complexity,
but only the i386 platform operations are implemented, built, tested, or
claimed by this design.

## Shared library

### Layers and responsibilities

`libvirtio` has four bounded layers:

1. **Platform operations** provide PCI configuration access, I/O-port access,
   BAR mapping, interrupt integration, DMA allocation, address translation, and
   memory barriers.
2. **PCI transports** implement modern capability-based registers and legacy
   I/O-port registers behind one transport interface.
3. **Virtqueue core** owns split-ring layout, descriptor free lists,
   scatter/gather chains, notification, completion, and reset.
4. **Device facade** owns status transitions, feature negotiation, transport
   selection, configuration access, and queue lifetime.

Family drivers depend only on the device facade and virtqueue API. They never
read transport registers directly.

### Transport selection

Probe matches the standard VirtIO PCI vendor ID `1af4` and the IDs needed by
the family driver:

| Family | Transitional ID | Modern ID |
|---|---:|---:|
| Network | `1000` | `1041` |
| Block | `1001` | `1042` |
| Console | `1003` | `1043` |
| SCSI | `1004` | `1048` |
| Input | none | `1052` |

For a transitional device, the driver first validates the modern vendor
capabilities. If a complete modern interface is present, it uses that interface.
If not, it falls back to the legacy interface. A modern-only device must have a
valid modern interface. VirtIO input has no legacy device model and therefore
requires modern transport.

The implementation reports the selected transport in its attachment log. Tests
can force a QEMU transitional function to legacy-only mode so fallback does not
remain unexercised.

### Modern PCI transport

The modern transport walks the PCI capability list and recognizes the VirtIO
common, notify, ISR, and device configuration capabilities. It validates every
capability's BAR number, offset, length, and range before mapping it. Capability
cycles, truncation, overflow, overlap with an invalid BAR range, or a missing
required capability cause probe to fail.

Modern initialization:

1. Reset and wait for device status zero.
2. Set `ACKNOWLEDGE`, then `DRIVER`.
3. Read 64-bit device features.
4. Require and accept `VIRTIO_F_VERSION_1`, plus the family feature subset.
5. Write driver features, set `FEATURES_OK`, and verify that the device retained
   it.
6. Allocate queues and program 64-bit descriptor, available, and used
   addresses through the common configuration region.
7. Set `DRIVER_OK` only after family initialization is complete.

The notify address is calculated from the queue's notify offset and the
capability multiplier. Modern structure and configuration fields use the
little-endian conversions required by the VirtIO specification.

### Legacy PCI transport

The legacy transport uses the transitional function's I/O BAR and the fixed
register layout for 32-bit device features, guest features, queue PFN, queue
selection, notification, device status, and clear-on-read ISR. It uses the
legacy handshake without `FEATURES_OK` and uses guest-native field byte order,
which is little-endian on the supported i386 target.

MSI-X is not negotiated, keeping legacy device configuration at its standard
non-MSI-X offset. Queue memory is registered through its page frame number.

### Split virtqueues

One queue object owns:

- The descriptor table.
- The available ring.
- The used ring.
- A descriptor free list.
- Per-head cookies and chain lengths.
- Producer and consumer indices.
- The selected transport's notification metadata.

The core supports direct descriptor chains with zero or more device-readable
segments followed by zero or more device-writable segments. A request becomes
visible only after all descriptors and the available entry have been written
and the required memory barrier has executed. Completion similarly applies a
barrier before reading device-written data.

The implementation validates used-ring head indices and rejects double
completion or impossible chain lengths. Every accepted cookie completes once,
including during reset and teardown.

### DMA allocation and mapping

Queue memory uses `IOMallocLow` and `IOFreeLow`. On i386 these call the kernel
DMA allocator, which provides aligned, physically contiguous regions of up to
64 KiB. The library caps each complete split-ring allocation to that maximum.
It verifies physical translation and page-to-page contiguity before programming
the device.

Using the same contiguous combined layout for modern and legacy queues keeps
the queue core identical. Modern transport programs the three physical
subregion addresses separately; legacy transport programs the combined ring's
page frame number.

Payload buffers need not be contiguous. Drivers translate them page by page
with `IOPhysicalFromVirtual` and create direct scatter/gather chains. Queue
limits and family limits bound the number and total length of segments before a
request is submitted.

### Failure and reset contract

Initialization failure unwinds all queues and mappings, sets `FAILED` when the
transport state permits it, resets the device, and makes `probe:` decline the
device. A half-initialized family object is never registered.

Runtime reset stops new submissions, masks or detaches interrupt processing,
completes all outstanding cookies through their family error path, resets the
device, reconstructs queues, renegotiates features, and only then resumes new
work. Reset never reuses device-owned descriptors.

## Family drivers

### VirtIO SCSI

`VirtioSCSIController` subclasses `IOSCSIController`. It owns control queue 0,
event queue 1, and request queue 2. The first version uses the request queue for
normal commands and initializes the other required queues without implementing
optional task-management policy beyond reset.

Each `IOSCSIRequest` is translated into a VirtIO SCSI request header, optional
data-out segments, response header and sense buffer, and optional data-in
segments. The LUN, tag, task attributes, CDB length, and device limits are
validated before submission.

VirtIO host response maps to `driverStatus`; the SCSI status byte maps to
`scsiStatus`. Residual length determines `bytesTransferred`, and sense data is
copied only for check condition. Timeouts use `IOSCSIRequest.timeoutLength`.
Expiry resets the device and completes affected commands with
`SR_IOST_IOTO`.

The existing SCSI stack performs device discovery, disk-label and partition
handling, and publishes disks as `sdN`. The bundle is a boot driver, permitting
`Root Device = sd0a`.

### VirtIO block

The block bundle contains a controller that owns PCI and queue state and a
`VirtioBlkDisk` subclass of `IODisk` implementing the normal physical-disk read
and write protocols. It follows the controller/disk split used by `drvEIDE`.

Each operation contains the VirtIO block header, payload segments, and status
byte. The first version implements read, write, and flush. Capacity is read in
512-byte sectors; the advertised block size is honored when present.

To participate in the existing i386 root path, each disk registers through the
kernel's shared ATA `hd` registry and publishes as `hdN`. It uses the existing
partition and root parser rather than introducing a new device prefix. The
bundle is a boot driver, permitting `Root Device = hd0a`.

### VirtIO input

One bundle supports multiple VirtIO input PCI functions. During probe, each
instance reads the device identity and event bitmaps and selects exactly one of
these roles:

- A keyboard instance accepts supported `EV_KEY` events, tracks press/release
  state and modifiers, maps Linux input key codes to the Rhapsody keyboard
  event representation, and uses the existing keymap path.
- A mouse instance accepts relative X/Y and supported button events. It
  accumulates a frame until `EV_SYN/SYN_REPORT`, then dispatches one coherent
  relative-pointer event.

Each instance owns event queue 0 and status queue 1. Event buffers are
pre-posted and replenished after completion. Keyboard LED state is sent through
the status queue when the device advertises LED events. Unsupported event types
are ignored; an incomplete frame is never dispatched.

QEMU keyboard and mouse functions can be present concurrently and are handled
by separate instances of the same bundle. Absolute tablet and multitouch event
paths are outside this design.

### VirtIO console

`VirtioConsole` exposes port 0 as a BSD TTY suitable for `getty`, login, and
normal terminal I/O. It declines the multiport feature, so it needs receive
queue 0 and transmit queue 1 only.

Receive buffers are pre-posted. Completed bytes enter the standard line
discipline. The TTY start routine drains output into transmit buffers and
applies normal backpressure when the queue is full. Transmit completion wakes
the output path.

This driver is not an early kernel console. No output is promised before PCI
enumeration, bundle initialization, and virtqueue setup.

### VirtIO network

`VirtioNet` subclasses `IOEthernet` and publishes through the existing `enN`
path. It owns receive queue 0 and transmit queue 1. Receive buffers are
pre-posted and replenished as completions are drained. Transmit uses
`IONetbufQueue` for backpressure and completion reclamation.

The first version negotiates the device MAC address and link status where
available. It declines checksum offload, segmentation offload, mergeable receive
buffers, the control queue, and multiqueue. The resulting fixed header and
linear packet policy minimize conversion code.

Malformed or oversized receive packets are dropped without publishing partial
data, and their queue capacity is replenished.

## Interrupt and concurrency model

Each driver uses the DriverKit shared-IRQ model. An interrupt handler first
checks the selected transport's ISR state. If the device did not raise the
interrupt, it returns without touching queue state.

For an owned interrupt, the handler drains completed entries from every
relevant queue, records lightweight completion state, replenishes receive or
event buffers where safe, and schedules any blocking or expensive family work
outside the interrupt path. Submission and completion protect descriptor and
index state with the existing DriverKit locking and interrupt-level conventions.

Configuration-change interrupts trigger a family-specific refresh, such as
network link state, rather than an unconditional device reset.

## Boot and configuration

Both storage bundles are listed in `Boot Drivers` when their device may carry
root. Firmware supplies the image to the booter through its normal BIOS disk
path; no RhapsodiOS VirtIO code runs before the kernel. The booter loads the
configured `_reloc`, DriverKit probes the PCI function, and the storage family
publishes `sdN` or `hdN` before root selection.

Configuration tables use the established PCI auto-detect encoding
`(device << 16) | vendor`, shared IRQs, and existing family names. Storage
tables include the boot-driver property. The input bundle contains two
configuration personalities that name the same server and `_reloc`: one with
family `Keyboard` and one with family `Pointing Device`. Both match modern ID
`1052`; probe reads the event bitmap and only the matching personality claims
the PCI function. This provides two DriverKit family registrations without
splitting the bundle or transport implementation.

No change to the accepted i386 root prefixes is required: VirtIO SCSI uses
`sd`, and VirtIO block joins `hd`.

## Testing

### Host-side shared-core tests

A mock platform and mock VirtIO device test:

- Modern capability walking, BAR bounds, cycles, truncation, and missing
  capabilities.
- Modern and legacy status transitions and feature negotiation.
- Modern preference and legacy fallback for transitional devices.
- Queue sizing and the 64 KiB allocation cap.
- Descriptor allocation, multi-segment chains, ring wraparound, notification,
  completion ordering, and descriptor reclamation.
- Allocation, translation, and contiguity failures.
- Malformed used entries, duplicate completion, reset, and teardown.
- Modern little-endian access and legacy i386 guest-native access.

### Family protocol tests

Focused tests cover:

- SCSI request construction, response/status separation, residuals, sense data,
  timeouts, and reset completion.
- Block read, write, flush, capacity, alignment, status mapping, and `hdN`
  registration contracts.
- Keyboard key-code translation, modifier state, release events, LED output,
  and unsupported events.
- Mouse frame accumulation, relative motion, buttons, and incomplete frames.
- Console RX/TX flow, TTY backpressure, and queue wakeup.
- Network RX/TX headers, queue refill, malformed packets, and link changes.

All sources must build with the repository's historical compiler and project
makefiles.

### QEMU 11.x root-boot matrix

Four isolated images or image copies prove each root path:

1. Modern-only VirtIO SCSI boots from `sd0a`.
2. Transitional VirtIO SCSI forced to legacy-only mode boots from `sd0a`.
3. Modern-only VirtIO block boots from `hd0a`.
4. Transitional VirtIO block forced to legacy-only mode boots from `hd0a`.

The transitional tests must disable the modern interface; merely attaching a
transitional function is insufficient because normal probe prefers modern.

### Integrated acceptance

A modern-device boot proves concurrent operation of storage, network, console,
keyboard, and mouse. Acceptance requires:

- Modifier, press, and release keyboard events.
- Relative mouse movement and buttons.
- Login through the VirtIO console TTY.
- Network transmit and receive through a configured `enN` interface.
- Sustained concurrent activity without lost or duplicate completions.

A forced-legacy transitional boot proves storage, console, and network together.
VirtIO input is omitted from that run because the device type has no legacy
interface.

The repository's QEMU 0.9 binary predates VirtIO and is not a verification
target.

## Implementation sequence

The implementation plan should preserve these dependency gates:

1. Prove the existing guest can boot under QEMU 11.x with emulated legacy
   hardware.
2. Build the shared core and host-side mock tests.
3. Prove modern capability mapping and forced legacy fallback in a diagnostic
   driver.
4. Prove deterministic contiguous queue allocation in the guest.
5. Implement VirtIO block and its two root-boot paths.
6. Implement VirtIO SCSI and its two root-boot paths.
7. Implement network and console.
8. Implement the combined keyboard/mouse input bundle.
9. Run the integrated modern and forced-legacy acceptance tests.

Storage is implemented first because root-boot viability is the highest-risk
acceptance requirement. Input follows the modern transport rather than driving
its design prematurely.

## Principal risks

1. **Modern BAR mapping:** the old DriverKit PCI facade must expose and map all
   vendor-capability BAR regions correctly. The diagnostic transport milestone
   isolates this before family drivers depend on it.
2. **DMA pool limits:** `IOMallocLow` has a 64 KiB maximum allocation and draws
   from the i386 DMA pool. Queue caps and early boot allocation make consumption
   explicit; allocation failure remains a clean probe failure.
3. **VirtIO block root publication:** joining the shared `hd` registry must
   preserve global unit allocation and partition semantics across EIDE and
   VirtIO block. Protocol and mixed-controller guest tests cover this contract.
4. **Keyboard translation:** VirtIO input reports Linux input codes while the
   Rhapsody input path expects its native event representation. A table-driven,
   test-covered mapping limits this risk to one component.
5. **Historical compiler constraints:** the core must remain compatible with
   the repository's C dialect and kernel-server flags. Host tests cannot replace
   native build verification.
