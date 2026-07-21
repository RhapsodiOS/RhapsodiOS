# Generic USB 1.1 and USB 2.0 DriverKit Design

**Status:** Approved design

**Target:** Rhapsody Developer Release 2 on x86 and PowerPC

**Milestone 1:** Portable USB core and OHCI USB 1.1 host-controller support

**Milestone 2:** EHCI USB 2.0 high-speed support

## Purpose

RhapsodiOS needs one maintainable DriverKit USB host stack that runs on both x86 and PowerPC. The first milestone will provide a portable USB core, OHCI host-controller support, hub enumeration, control/bulk/interrupt transfers, and boot-protocol HID keyboard and mouse support. It must work with QEMU-emulated controllers and representative real hardware on both architectures.

The second milestone will add EHCI high-speed support behind the same host-controller interface. Isochronous transfers, audio, mass-storage class support, and UHCI are outside milestone 1.

## Existing Code and Reference Material

The PPC source tree contains an Apple USB stack under `src/kernel-7/bsd/dev/ppc/drvUSBCMD`. It includes a USB Services Library, OHCI UIM, root-hub simulation, hub and composite class drivers, and keyboard and mouse code. It is valuable as a behavioral baseline, but its global state, Mac OS compatibility types, PPC-specific accessors, DriverKit lifecycle code, USB core, and OHCI implementation are too tightly coupled to form the portable architecture directly.

Howard Cole's [OpenStep OHCI driver](https://github.com/itomato/UsbOHCI.0.5beta) demonstrates an x86 DriverKit OHCI implementation and provides useful behavioral and architectural evidence. Its repository does not establish a clear license for every source file. It must therefore be treated as clean-room reference material: the implementation may use public USB/OHCI specifications and independently observed behavior, but must not copy its source code.

Before retaining or adapting any existing Apple source, the project will record file-level license and provenance. New portable implementation code will be independently written.

## Architecture

The driver has four explicit layers.

### USBPlatform

`USBPlatform` isolates Rhapsody DR2 DriverKit and architecture dependencies. Its x86 and PPC adapters provide:

- PCI discovery and configuration
- MMIO mapping and access
- Interrupt registration, masking, acknowledgement, and delivery
- Monotonic timers and delayed work
- Locks and execution-context assertions
- DMA-safe allocation, physical mapping, and address validation
- Cache synchronization and memory barriers
- Logging and diagnostics
- Explicit CPU/PCI byte-order conversion

No upper layer may import architecture-specific headers or call platform-specific DriverKit facilities directly.

### USBCore

`USBCore` owns the controller-independent USB model:

- Buses, ports, devices, configurations, interfaces, endpoints, and pipes
- Device-address allocation
- Descriptor validation and parsing
- Enumeration and hot-plug state machines
- Transfer requests, timeouts, cancellation, and completion
- Driver matching and class-driver attach/detach
- Device topology and recursive hub removal

The core supports multiple simultaneous host controllers. It contains no singleton bus, global device table, or global interrupt state.

### USBHostController

`USBHostController` is a narrow contract between `USBCore` and a controller driver. It covers controller start/stop/reset, root-port operations, pipe creation/destruction, request submission/cancellation, frame information where available, and completion delivery.

The first implementation is `OHCI`. The second milestone adds `EHCI` without changing class-driver APIs. Controller-private schedule descriptors never cross this boundary.

### USBClass

Class drivers use only `USBCore` devices, interfaces, pipes, and requests. Milestone 1 provides:

- Hub support, including external hubs and recursive topology changes
- HID boot-protocol keyboards
- HID boot-protocol mice

Class drivers do not inspect OHCI registers or descriptors.

### DriverKit Ownership

One Objective-C `IODirectDevice` subclass owns each detected controller and bridges DriverKit lifecycle operations to the C modules. It owns the platform context, one host-controller instance, and one USB bus. Publication occurs only after PCI, MMIO, DMA, controller reset, schedule setup, and interrupt setup have succeeded.

A temporary compatibility adapter may expose the minimum existing PPC USB Services/UIM behavior needed for incremental comparison. It is optional at build time, sits above `USBCore`, and is removed after the new hub and HID paths meet parity criteria.

## Controller Lifecycle

Probe and startup proceed in this order:

1. Match and validate a PCI OHCI controller.
2. Enable the required PCI memory-space and bus-master capabilities without disturbing unrelated command bits.
3. Map and validate the OHCI register aperture.
4. Establish the controller's DMA mask, alignment rules, cache behavior, and physical-address constraints.
5. Allocate and initialize the HCCA and descriptor pools.
6. Take ownership from firmware when required, reset the controller, and initialize schedules and root-hub state.
7. Install the interrupt path with controller interrupts masked.
8. Start schedules, enable selected interrupts, and verify the controller reaches the operational state.
9. Create the USB bus and publish the DriverKit device.
10. Begin root-port observation and enumeration.

Teardown performs the inverse operations. Every startup stage records ownership so a partial failure can unwind only resources that were acquired.

## Enumeration and Topology

Each port is driven by a serialized state machine:

`disconnected -> debounce -> reset -> default-address probe -> address assignment -> descriptor discovery -> configuration -> interface binding -> active`

Enumeration performs these operations:

1. Debounce a connection and reset the port using bounded delays and retries.
2. Read the initial device descriptor at address zero.
3. Allocate and set a unique address on that bus.
4. Read and validate complete device and configuration descriptors.
5. Select and set one configuration.
6. Materialize interfaces, endpoints, and pipes.
7. Match and attach the hub or supported HID class driver.

Malformed descriptors, impossible lengths, endpoint duplication, unsupported configurations, and topology/address exhaustion fail that device without corrupting the bus. A hub disconnect recursively detaches its complete child subtree.

## Transfer Model

A controller-neutral request contains:

- Transfer type: control, bulk, or interrupt in milestone 1
- Target pipe and direction
- Optional setup packet
- One or more data-buffer spans
- Requested length and resulting actual length
- Timeout or no-timeout policy
- Completion function and context
- Typed completion status
- An internal ownership/state token used to guarantee exactly-once completion

The core owns request policy and logical lifetime. OHCI owns hardware endpoint and transfer descriptors from successful submission until completion, cancellation retirement, or controller teardown. `USBPlatform` owns DMA mappings and cache synchronization.

OHCI uses separately managed, aligned DMA pools for HCCA, endpoint descriptors, general transfer descriptors, and any later isochronous descriptors. All OHCI registers and in-memory schedule fields are accessed using explicit little-endian helpers. PPC cache maintenance and ordering are performed at the platform boundary before ownership passes between the CPU and controller.

Interrupt context is intentionally small: read and acknowledge status, mask a storming/fatal source if necessary, detach completed work from hardware-visible lists, and schedule deferred processing. Descriptor reclamation, callbacks, enumeration, and class-driver work execute outside interrupt context.

Cancellation transitions a request atomically from submitted to cancelling, prevents new hardware use, waits for or proves descriptor retirement, releases DMA ownership, and completes the request exactly once. Disconnect uses the same cancellation machinery rather than a separate unsafe teardown path.

## Error Handling and Recovery

The public status model distinguishes at least:

- Success and short transfer
- Endpoint stall
- Timeout
- Explicit cancellation
- Device disconnect
- CRC/bit-stuff, data-toggle, babble, and overrun/underrun errors
- Bandwidth or resource exhaustion
- Invalid descriptor or request
- DMA mapping/address failure
- Controller unrecoverable error

Recovery occurs at the narrowest safe level:

- A stall is reported to the caller; resumption requires an explicit clear-halt operation.
- A timeout retires that request's descriptors and preserves the pipe when controller state permits.
- A disconnect cancels the affected device subtree without being classified as a controller fault.
- A root-port failure resets or power-cycles that port and retries enumeration a bounded number of times.
- An unrecoverable OHCI error or detected schedule corruption stops schedules, fails outstanding work, resets and reinitializes the controller, and re-enumerates connected ports.
- A DMA constraint failure rejects initialization or the individual request. Virtual addresses and truncated physical addresses are never substituted.

Normal builds use rate-limited diagnostics. Debug builds additionally provide ownership assertions, state-transition tracing, schedule/descriptor validation, and bounded register and schedule dumps.

## Driver Binding and Input Delivery

Class matching uses descriptor class/subclass/protocol fields at the device or interface level as required by USB. Hub support attaches before child enumeration proceeds.

The keyboard and mouse drivers use HID boot protocol only in milestone 1. They perform required control requests, create interrupt-IN pipes, validate report sizes, recover from transient transfer errors, and translate boot reports into the existing DR2 input/event path. Device-specific report-descriptor parsing is deferred.

Attaching and detaching a class driver is idempotent. A detach first prevents resubmission, cancels the interrupt request, drains its completion, unregisters the input source, and releases interface ownership.

## Build and Packaging

The portable C sources and OHCI implementation are shared by x86 and PPC builds. Only platform adapters and narrowly scoped packaging/configuration data differ by architecture. Build rules must fail if an upper layer accidentally includes x86- or PPC-specific headers.

During migration, the existing PPC USB implementation remains available as a separately selectable fallback. Driver matching and configuration must ensure that the old and new implementations cannot claim the same controller in one boot.

## Verification Strategy

### Hosted Tests

The portable modules compile outside the kernel against fake platform and host-controller backends. Deterministic tests cover:

- Descriptor validation and parsing
- Enumeration state transitions and bounded retry behavior
- Address allocation and exhaustion
- Hub topology insertion and recursive removal
- Control, bulk, and interrupt request construction
- Timeout, cancellation, completion, and disconnect races
- Exactly-once completion and ownership transitions
- Controller reset and re-enumeration behavior
- Little-endian conversion and simulated non-coherent DMA hooks

### QEMU Integration

Rhapsody DR2 x86 and PPC boot with emulated OHCI controllers. Where possible, tests use the repository's VM automation and machine-readable log assertions. The integration matrix covers:

- Cold-plug and hot-plug
- Root hub and at least one external hub
- HID boot keyboard and mouse
- Control, bulk, and interrupt traffic
- Multiple controller instances
- Disconnect during active I/O
- Endpoint stall, timeout, and cancellation
- Controller reset and recovery
- Repeated attach/detach cycles

### Real Hardware Qualification

Qualification uses at least one x86 PCI OHCI card and one PPC onboard or PCI OHCI controller. It covers repeated boots, hot-plug loops, an external hub, simultaneous keyboard and mouse activity, sustained bulk and interrupt transfers, disconnect during I/O, and recovery from reproducible controller or port faults.

Hardware models, PCI identifiers, firmware version, interrupt routing, DMA/cache observations, and test results are recorded so later regressions can be reproduced.

## Milestone 1 Acceptance Criteria

Milestone 1 is complete only when all of the following hold:

1. x86 and PPC build from the same `USBCore`, `USBHostController`, `OHCI`, hub, and HID sources.
2. Architecture-specific behavior is confined to reviewed `USBPlatform` adapters and packaging data.
3. Each architecture enumerates root hubs and at least one external hub under QEMU and on representative real hardware.
4. Control, bulk, and interrupt transfers pass functional, error, timeout, cancellation, and disconnect tests.
5. HID boot keyboards and mice operate through the DR2 input path on both architectures.
6. Multiple host-controller instances do not share mutable bus, device, interrupt, or schedule state.
7. Repeated hot-plug and cancellation stress produces no observed leaks, double completion, stale DMA access, deadlock, or memory corruption.
8. Fatal-controller recovery fails outstanding requests deterministically and restores enumeration without reboot when the hardware can be reset.
9. The legacy PPC fallback and new driver cannot bind the same controller.
10. License and provenance records exist for every reused source file; the Howard Cole repository contributes no copied implementation code.

## Delivery Sequence

1. **Baseline and provenance:** inventory the PPC stack, record licenses, capture known-good hardware and QEMU logs, and define comparison fixtures.
2. **Contracts and fakes:** define platform, host-controller, request, pipe, device, and class-driver contracts; implement hosted fake backends and state-machine tests.
3. **Platform adapters:** implement and verify DR2 x86/PPC PCI, MMIO, interrupt, timer, synchronization, DMA, cache, barrier, and byte-order facilities.
4. **OHCI foundation:** implement controller ownership/reset, HCCA and descriptor pools, root-hub control, and fatal-error recovery.
5. **Transfers:** implement control first, then bulk and interrupt schedules, with timeout and cancellation tests at each step.
6. **Core enumeration:** implement addressing, descriptors, configurations, interface/pipe creation, hot-plug, and recursive teardown.
7. **Classes:** add external hubs, HID boot keyboard, and HID boot mouse.
8. **Packaging and integration:** add architecture builds, DriverKit matching/configuration, fallback selection, and automated QEMU scenarios.
9. **Hardware qualification:** execute and record the x86 and PPC real-hardware matrix, fixing portability defects at their owning layer.
10. **Compatibility retirement:** remove the temporary adapter after behavior and test parity are established.
11. **Milestone 2:** implement EHCI high-speed schedules, root ports, split/companion routing, and USB 2.0 qualification behind the existing host-controller contract.

## Explicit Non-Goals for Milestone 1

- EHCI high-speed transfers
- UHCI support
- Isochronous transfers and USB audio
- Mass-storage class support
- Arbitrary HID report-descriptor parsing
- USB 3.x/xHCI
- Support for operating systems other than Rhapsody DR2
- Source-level compatibility with the old PPC USB Services/UIM API after migration
