# AGP Bus and DriverKit Support Design

**Status:** Approved design

**Target:** Rhapsody Developer Release 2 on i386 and PowerPC

**Milestone 1:** Shared AGP core with Intel 82443BX and Apple UniNorth providers

## Purpose

RhapsodiOS needs an architecture-neutral Accelerated Graphics Port service that
loadable DriverKit graphics drivers can use without knowing host-bridge register
layouts. Milestone 1 provides AGP discovery, AGP 1.0/2.0 capability negotiation
through 4x, aperture and GATT management, physical-page binding, deterministic
teardown, and diagnostics on i386 and PPC.

The first chipset providers are Intel 82443BX on i386 and Apple UniNorth on
PPC. Intel 440BX remains limited to the rates its hardware advertises; supported
UniNorth revisions may negotiate 4x. Graphics-driver conversion is deferred, so
the milestone proves the public API with a small loadable DriverKit test client.

AGP 3.0/8x, PCI Express, additional Intel/VIA/AMD/Apple chipsets, user-space
control, and graphics-buffer allocation are outside this milestone.

## Existing Architecture and Reference Boundaries

The two target architectures currently expose PCI differently:

- i386 DriverKit uses the singleton `PCIKernBus` contract and the
  `IOPCIDirectDevice` / `IOPCIDeviceDescription` categories in
  `src/driverkit-3`.
- PPC creates PCI devices from the Open Firmware device tree. The
  `IOMacRiscPCIBridge`, `IOGracklePCIBridge`, and `IOPCIDevice` classes own
  configuration-space access and publication.

AGP must reuse these paths rather than enumerate PCI independently. The shared
core may depend on narrow PCI configuration callbacks, but it may not import
i386- or PPC-specific headers.

The Intel 82443BX datasheet and the AGP 1.0/2.0 specifications are normative for
the i386 provider and common negotiation rules. Existing Apple device-tree and
PCI bridge code is normative for attachment within this tree. Other open-source
AGP implementations may be used only as behavioral research: their source is
not copied, and new implementation code retains file-level provenance notes.

## Architecture

The feature has four layers.

### Public DriverKit API

`IOAGPDevice` is an architecture-neutral kernel DriverKit service available to
loadable drivers. A driver obtains the service for its PCI device description.
The public header defines fixed-width capability, mode, range, and diagnostic
types and exposes methods to:

- query host/device capabilities and aperture geometry;
- acquire and release exclusive control;
- request a maximum transfer rate and optional features;
- bind physical pages at a page-aligned aperture offset;
- unbind an existing aperture span;
- flush pending translation changes; and
- query read-only state and binding diagnostics.

The API uses `IOReturn` consistently and contains no chipset register constants.
It is installed with the public DriverKit headers for both machine builds and is
linked into the kernel form of `libDriver`, allowing loadable DriverKit drivers
to consume it without private headers.

The AGP service does not allocate graphics buffers. The caller owns every
physical page and must keep it alive until a successful unbind. The AGP manager
owns only the aperture translation and its bookkeeping.

### Shared AGP Manager

The machine-independent manager owns the single active host-bridge/graphics-
device pair. It provides:

- AGP capability-list parsing with loop and bounds protection;
- AGP 1.0/2.0 rate and feature intersection;
- one controlling DriverKit owner at a time;
- aperture-range and physical-page validation;
- overlap detection and binding records;
- serialized state transitions and provider calls;
- forced teardown when the owner unloads or initialization fails; and
- rate-limited normal logs plus detailed debug diagnostics.

The manager uses an explicit lifecycle:

`absent -> discovered -> prepared -> acquired -> enabled`

`discovered` changes no hardware. `prepared` means aperture geometry is valid
and a physically suitable, zeroed GATT exists. `acquired` assigns one owner.
`enabled` means host and graphics-device AGP command registers agree and page
translations may be installed.

### Private Chipset Provider Interface

A provider supplies only hardware-specific operations:

- identify and validate a supported bridge revision;
- discover and validate aperture sizes;
- allocate or validate GATT placement constraints;
- encode valid and scratch GATT entries;
- snapshot, program, read back, and restore bridge registers;
- flush CPU caches and bridge translations with required ordering;
- enable a negotiated link mode; and
- disable and restore the bridge during teardown.

The common core chooses policy. A provider may reduce advertised capability or
reject a mode because of a documented bridge erratum, but it cannot silently
enable a feature the common negotiation rejected.

### Initial Providers

The i386 provider attaches only to Intel vendor/device identity for the
82443BX host bridge after `PCIKernBus` is usable. It implements the 440BX
aperture-size, GATT-base, control, and invalidation rules and advertises only
1x/2x operation.

The PPC provider attaches through the existing Open Firmware and
`IOMacRiscPCIBridge` flow to Apple UniNorth AGP host functions. Its initial
identity table covers UniNorth, UniNorth/Pangea, UniNorth 1.5, and UniNorth 2
families when an AGP capability is present. It uses the `device-rev` property
when available, applies an explicit per-revision quirk table, and disables 4x
on revisions marked unsafe. U3/U3L/U3H and Intrepid are separate future
providers, not aliases for UniNorth in this milestone.

Unknown PCI identities, missing capabilities, missing required device-tree
properties, invalid aperture geometry, and unknown register layouts cause a
clean unsupported result. There is no `try_unsupported` mode.

## Discovery and Data Flow

1. Architecture PCI initialization identifies a supported host bridge and
   registers one provider with the shared manager.
2. A loadable graphics driver requests `IOAGPDevice` for its device
   description.
3. The manager validates the graphics function's AGP capability and pairs it
   with the provider on the same AGP bus.
4. The driver acquires exclusive ownership.
5. The manager asks the provider to validate aperture geometry and prepare the
   GATT without enabling the link.
6. The driver requests a maximum mode. The manager intersects host and device
   rates, request-queue depth, sideband addressing, and fast-write support.
7. The provider programs and verifies the bridge. The manager programs and
   verifies the graphics device last.
8. Bind calls validate the complete request, encode all entries, perform cache
   maintenance and ordering, flush translations, and then publish the binding
   record.
9. Unbind replaces entries with the provider's scratch encoding, flushes, and
   only then removes the binding record so the caller may free pages.
10. Release or forced teardown unbinds all spans, disables the graphics device,
    disables the host bridge, restores snapshots, and frees manager-owned GATT
    resources.

Sideband addressing and fast writes are opt-in and default off. When multiple
rates are mutually supported, the manager enables no rate above the caller's
request. The test client requests explicit modes so negotiation is observable.

## Memory and Concurrency Rules

Milestone 1 uses the AGP page size of 4096 bytes. Aperture offsets, physical
addresses, and lengths must be page-aligned. Arithmetic is checked before
conversion to the 32-bit hardware formats used by these providers. A physical
page that the selected provider cannot encode is rejected rather than
truncated.

The GATT is physically suitable for the provider, zeroed before use, filled
with provider-defined scratch entries, and mapped with cache attributes that
make explicit synchronization possible. PPC cache maintenance and memory
barriers remain inside the provider boundary.

One manager lock protects lifecycle, ownership, and binding metadata. Provider
register programming and GATT mutation occur only while an operation holds the
serialized manager transaction. The public methods are callable from normal
DriverKit thread context, not interrupt context. Diagnostics take snapshots
under the lock and format output after releasing it.

## Error Handling and Rollback

Providers snapshot every register they modify. Preparation and enablement are
transactions: program the GATT and aperture first, flush, enable the host, and
enable the graphics device last. A failure unwinds only completed stages in
reverse order and restores the original values.

The public error model distinguishes unsupported hardware or modes, no device,
busy ownership, invalid arguments, alignment/range errors, overlapping
bindings, resource exhaustion, and hardware read-back failure using existing
`IOReturn` values.

Additional invariants are:

- a failed multi-page bind restores every entry changed by that call;
- a failed unbind leaves its binding record intact unless hardware entries are
  known to be safely replaced;
- owner teardown is idempotent and removes every surviving mapping;
- ordinary PCI enumeration, framebuffer BARs, and MMIO access remain usable
  after any AGP failure; and
- no public service is returned while the manager is partially prepared.

## Build and File Boundaries

The implementation plan will keep responsibilities in focused files:

- public AGP API and fixed-width types under `src/driverkit-3/driverkit`;
- common manager, negotiation, validation, and binding logic under
  `src/driverkit-3/libDriver/Kernel`;
- a private provider contract beside the common manager;
- i386 440BX attachment/provider code under `src/driverkit-3/libDriver/i386`;
- PPC UniNorth attachment/provider code under `src/driverkit-3/libDriver/ppc`;
- header-install and kernel-library source lists in the existing DriverKit
  makefiles; and
- deterministic fake-provider tests under `src/driverkit-3/tests`.

Architecture attachment points may add a small call or category to existing
PCI classes, but chipset register programming must not be added to
`PCIKernBus`, `IOPCIDevice`, or `IOMacRiscPCIBridge` themselves.

## Verification Strategy

### Deterministic Core Tests

Hosted or isolated DriverKit tests use fake PCI capability images and fake
providers. They cover:

- AGP 1.0/2.0 parsing and 1x/2x/4x capability intersection;
- optional-feature and request-depth negotiation;
- ownership and repeated acquire/release behavior;
- alignment, overflow, range, overlap, and duplicate-bind rejection;
- binding bookkeeping and scratch-entry restoration;
- lifecycle transitions and forced owner teardown; and
- every allocation, register-write, read-back, GATT-update, and flush failure,
  with rollback assertions after each injected fault.

Provider tests use synthetic PCI/device-tree identities and fake register banks
to verify 440BX and UniNorth matching, aperture decoding, GATT entry encoding,
revision quirks, ordering, invalidation, and complete register restoration.

### Build and Loadable-Driver Tests

Both i386 and PPC builds must produce the kernel, public installed header, and
kernel `libDriver` symbols. A small loadable DriverKit client must compile and
link against public headers only, query service availability, and handle the
unsupported result without touching private APIs.

### QEMU Smoke Tests

The repository's VM workflow builds and boots both architectures. QEMU is used
to verify safe integration, not to claim real AGP transfer coverage. Each boot
must preserve PCI/device-tree enumeration and storage, network, and framebuffer
startup. When no supported host/device pair is present, AGP reports absent or
unsupported once and remains inactive without a panic or register mutation.

### Deferred Real-Hardware Qualification

A later qualification run will exercise a 440BX i386 machine and UniNorth
Power Mac: negotiated modes, aperture writes, repeated bind/unbind, forced
driver unload, failure recovery, and reboot state restoration. These tests are
documented deliverables but are not milestone-1 gates.

## Milestone 1 Acceptance Criteria

Milestone 1 is complete when all of the following hold:

1. One shared manager and public API build for i386 and PPC.
2. Only provider files contain 440BX or UniNorth register details.
3. AGP 1.0/2.0 negotiation supports 1x/2x/4x while providers enforce their
   hardware and revision limits.
4. Bind/unbind, ownership, rollback, and forced teardown tests pass with fake
   providers on every injected failure point.
5. The 440BX and UniNorth provider register-image tests pass.
6. A loadable DriverKit test client builds using installed public headers and
   no private symbols.
7. i386 and PPC kernels build successfully.
8. Both QEMU targets boot normally with unsupported or absent AGP hardware and
   no regression in existing device startup.
9. Unsupported bridge identities and revisions never enter `prepared` state.
10. Provenance notes identify specifications and behavioral references; no
    incompatible reference implementation is copied.

## Delivery Sequence

1. Add public types/API contracts and the private provider interface.
2. Build fake PCI/provider fixtures and negotiation/lifecycle tests.
3. Implement the common manager, ownership, state machine, and rollback.
4. Implement range validation and transactional bind/unbind bookkeeping.
5. Add public header installation and kernel `libDriver` integration.
6. Implement and test the Intel 82443BX provider and i386 attachment.
7. Implement and test the UniNorth provider, revision quirks, and PPC
   device-tree attachment.
8. Add the public-only loadable DriverKit test client.
9. Run i386/PPC builds and QEMU negative-path boot tests.
10. Record the deferred real-hardware qualification procedure.

## Explicit Non-Goals

- Converting an existing display driver to use AGP memory
- Allocating or paging graphics buffers for drivers
- User-space aperture mapping or control
- AGP 3.0/8x and AGP Pro extensions
- PCI Express graphics
- VIA, AMD, later Intel, U3, or Intrepid providers
- Runtime power-management optimization
- Claiming functional AGP hardware coverage from QEMU-only testing
