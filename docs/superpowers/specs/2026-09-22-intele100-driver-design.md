# drvIntelE100 — Intel 8255x (e100) Ethernet driver design

Date: 2026-09-22
Status: approved design, ready for an implementation plan

## Goal

Write a new BSD-licensed i386 DriverKit network driver, `drvIntelE100`, for
Intel's 8255x 10/100 Ethernet family (82557, 82558, 82559, 82559ER, 82550,
82551, and the ICH-integrated 82562-based parts). It replaces the existing
`drvIntel82557` reconstruction. The model is `drvIntel1000` (Pro1000): an
original work, packaged as a Driver bundle wrapping a Kernel Server, with
LICENSE and NOTICE files that record what was consulted.

Success means the driver builds warning-clean and passes real traffic in both
directions under QEMU on three emulated generations (see Testing). It is not
hardware-tested.

## Decisions made during brainstorming

- **Replace, not coexist.** `src/drivers-i386/network/drvIntel82557` is deleted
  in the same change; git history keeps it. It was a decompiled reconstruction
  of Apple's driver, auto-detected only `0x1229`, was missing its own header, and
  had no `apk/pkginfo`, so it was never packaged. `drivers-ppc/network/Intel82557`
  is a separate project and is not touched.
- **Name.** Directory `drvIntelE100`; class, Server Name and Driver Name
  `IntelE100`; bundle `IntelE100.drvproj`, kernel server `IntelE100.lksproj`.
- **Feature set: a solid core.**
  - Probe across the full ID list.
  - EEPROM MAC address with checksum check.
  - MII autonegotiation and link reporting.
  - Simplified-mode receive and transmit.
  - Multicast, promiscuous mode, hardware statistics.
  - The errata a correct driver needs.
  - Out of scope: microcode (Intel binary blobs), Wake-on-LAN, flow control,
    checksum offload, and 82550/1 extended RFDs.
- **Testing:** build, then QEMU boot tests on three models with a
  host-side packet capture. No hardware pass in this project.

## References and licensing

The driver is BSD-2-Clause, (c) 2026 Pat Raynor. NOTICE records the sources,
following Pro1000's precedent:

1. **Intel 8255x 10/100 Mbps Ethernet Controller Family Open Source Software
   Developer Manual, Rev 1.0 (2003).** This is the primary specification for the
   CSRs, SCB, CU/RU, command block formats, configure bytes, EEPROM protocol,
   MDI and statistics.
2. **FreeBSD `sys/dev/fxp` (`if_fxp.c`, `if_fxpreg.h`, `if_fxpvar.h`),
   BSD-2-Clause.** It fills the gaps the SDM leaves:
   - PCI device IDs for the 82562/ICH parts
   - the EEPROM word map and the `0xBABA` checksum
   - PHY type codes in EEPROM word 6
   - the errata workarounds

   Every value taken from it is cited in a source comment. No code is copied.
3. **Linux `drivers/net/ethernet/intel/e100.c` (GPL).** Background reading
   only. Nothing is copied from it and nothing is derived from it line by line.
   NOTICE states this explicitly.

## 1. Packaging and file layout

```
src/drivers-i386/network/drvIntelE100/
  Makefile, Makefile.preamble        Aggregate project, INCLUDED_ARCHS = i386
  LICENSE                            BSD-2-Clause
  NOTICE                             references, as above
  apk/pkginfo                        pkgname = intele100, pkgver = 1.0, arch = i386,
                                     license = BSD, makedepends = build-base,
                                     drivertools, driverkit, kernload
  IntelE100.drvproj/                 Driver bundle, BUNDLE_EXTENSION = config
    Default.table                    catalogue: Auto Detect IDs for the whole family
    Instance0.table                  example instance shaped for QEMU
    DriverInfo                       DRIVER_NAME="IntelE100"
    English.lproj/Localizable.strings
    PB.project, Makefile, Makefile.preamble, Makefile.postamble (movehelp no-op)
    IntelE100.lksproj/               Kernel Server
      E100Regs.h                     definitions only (see below)
      E100Hw.h, E100Hw.m             stateless hardware helpers
      IntelE100.m                    the IOEthernet subclass
      Load_Commands.sect             WIRE / START / DETACH
      PB.project, Makefile, Makefile.preamble, Makefile.postamble
```

### What each file does

- **`E100Regs.h`**
  - CSR offsets.
  - SCB status and ACK bits, CU and RU commands, and the mask bits.
  - PORT opcodes.
  - The CB, TxCB and RFD structure layouts with their bit definitions.
  - Configure-byte constants.
  - EEPROM control bits and the MDI control format.
  - Statistics offsets and completion codes.
- **`E100Hw.m`**
  - Waiting for the SCB command byte to clear, and issuing a command (with a
    timeout).
  - PORT software reset.
  - EEPROM microwire read and address-width detection.
  - Full EEPROM read with checksum.
  - MDI read and write.

  These helpers take an I/O base and hold no driver state.
- **`IntelE100.m`**
  - The chip table.
  - Probe and init.
  - DMA allocation, the rings, transmit and receive.
  - The interrupt handler and the watchdog.
  - Filtering and the statistics harvest.

### Load commands

`Load_Commands.sect` uses `DETACH` for the same reason as Pro1000. Once the
driver is attached to the network stack, the kernel holds references into the
module, so unloading it would panic.

### Chip table

The table is keyed on PCI device ID. Each entry holds a name and a base
generation. The revision ID then refines the generation:

| Revision | Generation |
|---|---|
| < 4 | 82557 |
| 4–5 | 82558 |
| ≥ 6 | 82559 and later |

The generation selects:
- the configure bytes
- the size of the statistics dump and where its completion word sits
- which errata flags apply

The errata flags follow if_fxp's per-ID and per-revision decisions.

`Default.table` lists every ID the chip table knows. The list is the set
if_fxp recognises, for example `1229`, `1209`, `1029`, `1030`, `1031`–`103E`,
`1050`–`1059`, `1064`–`106A`, `1091`–`1095`, `2449`, `2459`, `245D` and `27DC`.
Each ID is checked against if_fxp during implementation; this list is not
authoritative.

### Retirement

- Delete `src/drivers-i386/network/drvIntel82557`.
- Replace its line in `src/drivers-i386/README` with the drvIntelE100 entry.

## 2. Discovery and bring-up

### CSR access

CSR access goes through the I/O BAR. The window is 64 bytes, DriverKit's
`inb`/`outb`/`inw`/`outw`/`inl`/`outl` need no mapping, and the SDM notes that
some bridges mishandle memory-mapped CSRs.

The driver scans the BARs for an assigned I/O BAR, as Pro1000 does, and refuses
the device if there is none. If the BIOS left I/O-space or bus-master
disabled in the PCI command register, the driver enables them.

SCB command and status writes are byte-wide, so that writing a command cannot
clobber the interrupt-mask byte.

### `initFromDeviceDescription:`

1. Read PCI config space.
   - Refuse a vendor that is not `8086`.
   - Look up the device ID. Refuse IDs that are not in the table.
   - Refine the generation by revision ID.
   - Log the chip name, IDs, revision, generation and I/O base.
2. Read the EEPROM.
   - Detect the address width (6 or 8 bits) with the SDM's dummy-zero method.
   - Read every word, sum them, and compare the sum with `0xBABA`.
   - A mismatch logs a warning but is not fatal.
   - The MAC address comes from words 0–2, little-endian within each word.
   - Refuse the device if the MAC is all zeros, all ones, or multicast.
3. Parse EEPROM word 6, the primary PHY.
   - Bits 7:0 hold the MII address. Bits 13:8 hold the PHY type.
   - Bit 15 marks a serial-only 82503. That is legal only on an 82557, and it
     selects 503 mode: no MDI access, configure byte 8 bit 0 = 0, and byte 15
     bit 7 = 1.
4. Allocate DMA memory (Section 3), then attach with
   `attachToNetworkWithAddress:`.

The IRQ comes from the device description. The driver logs how many IRQs
DriverKit provided, as Pro1000 does, because a missing `IRQ Levels` key
silently yields zero.

### `resetAndEnable:`

1. Issue a PORT software reset and wait 20 µs. The SDM minimum is 10 µs.
2. Set SCB M to mask interrupts.
3. Load CU Base = 0, then RU Base = 0. From then on every pointer is a 32-bit
   physical address.
4. Rebuild the transmit ring, which clears every slot. Set the shadow CU state
   to idle.
5. Run configure, IA setup and multicast setup as polled command CBs in the
   transmit ring (Section 3).
6. Rebuild the receive ring and issue RU Start at its head.
7. On MII parts, write BMCR with autonegotiate enable and restart. The driver
   does not wait for link.
8. Clear SCB M to unmask interrupts, and arm the watchdog.

If any polled step times out, log the step and fail `resetAndEnable:`.

### Configure bytes

The bytes are the SDM's recommended values, 22 bytes in all. They differ
between the 82557 and the 82558 and later:

| Byte | 82557 | 82558+ | Notes |
|---|---|---|---|
| 0 | `16` | `16` | byte count |
| 1 | `08` | `08` | |
| 2 | `00` | `00` | |
| 3 | `00` | `00` | MWI off; the driver does not enable PCI MWI |
| 4 | `00` | `00` | |
| 5 | `00` | `00` | |
| 6 | `32` | `32` | CNA interrupts; standard statistics and TxCB |
| 7 | `03` | `03` | underrun retry 1, discard short frames |
| 8 | `01` | `01` | on 82557, bit 0 = 1 for MII and 0 in 503 mode |
| 9 | `00` | `00` | |
| 10 | `2E` | `2E` | |
| 11 | `00` | `00` | |
| 12 | `60` | `61` | |
| 13 | `00` | `00` | |
| 14 | `F2` | `F2` | |
| 15 | `48` | `48` | bit 0 = promiscuous; bit 7 = 1 in 503 mode |
| 16 | `00` | `00` | |
| 17 | `40` | `40` | |
| 18 | `F2` | `F2` | padding and stripping on |
| 19 | `80` | `80` | FDX pin enable |
| 20 | `3F` | `3F` | |
| 21 | `05` | `05` | `0D` = multicast-all |

On the 82559 and later, the statistics dump layout is chosen through byte 6
following if_fxp, so that the completion offset matches the table in
Section 4.

**Known limitation:** duplex follows the PHY's FDX pin. An 82557 board with an
external DP83840 PHY that does not wire FDX runs half duplex. There is no
per-PHY duplex-forcing code.

## 3. Data path

### DMA memory

All DMA memory is allocated in whole pages, using Pro1000's page-allocation
and `IOPhysicalFromVirtual` pattern. Every descriptor fits inside one page, so
physical contiguity is only needed within a page. Physical addresses are
recorded once, at allocation time.

### Transmit ring

The transmit ring has 16 slots. Each slot is 1,536 bytes, so two fit in a
page. The ring is statically linked into a circle when it is built and is
never relinked.

A slot is used in one of two ways:
- **Simplified-mode TxCB.** The command is Transmit and SF = 0. The TBD
  pointer is `FFFFFFFF`. The TCB byte count holds the frame length with EOF
  set. The frame data sits inline at offset `10h`.
- **Command CB.** Configure, IA setup or multicast setup. The multicast list
  is capped at 32 addresses, which is 192 bytes.

**`transmit:(netbuf_t)`**
1. Reap completed slots.
2. If the ring is full, append the netbuf to a bounded `IONetbufQueue`. When
   that queue is also full, free the netbuf and count a drop.
3. Otherwise:
   1. Copy the frame into the next slot's inline data, then free the netbuf.
   2. Set S on the new slot, then clear S on the previous slot.
   3. Wait for the SCB command byte to read 0.
   4. Issue CU Resume. If the shadow CU state is idle (first use, or after a
      reset), issue CU Start with the General Pointer set to this slot instead.

The driver never relies on CUS alone. The SDM says SCB status is updated late.

**Transmit threshold.** It starts low. When a completed TxCB has U (underrun)
set, the threshold rises by one unit (8 bytes), up to a ceiling below `E0h`.
It never reaches `FF`.

**Short frames** are padded by the chip (configure byte 18).

**Command CBs** go through the same ring with the same S-bit handoff.
- During `resetAndEnable:` they are polled: wait for C, with a timeout.
- At runtime, when multicast or promiscuous state changes, they are queued
  like frames. The reaper picks up their completion.

### Receive ring

The receive ring has 32 simplified-mode RFDs. Each is 1,536 bytes, two to a
page. The buffer size field is 1,520. The RFDs are linked into a circle, and
only the tail has EL set.

**On FR:**
1. Walk forward from the next RFD while C is set.
2. For an RFD with OK and EOF, and with no error bits:
   1. `nb_alloc` a netbuf of the actual count.
   2. Copy the frame into it.
   3. Hand it to the network with `handleInputPacket:extra:`.
3. An allocation failure is counted and the frame is dropped.
4. Recycle the RFD:
   1. Clear its status and actual count.
   2. Set EL on it, making it the new tail.
   3. Clear EL on the old tail.

**On RNR:** after draining, issue RU Start at the next free RFD. RU Resume is
illegal from the no-resources state.

**Receive errors** are counted rather than treated as fatal: CRC, alignment,
too short, DMA overrun, and no resources.

## 4. Interrupts, watchdog and errata

### `interruptOccurred`

This runs on DriverKit's I/O thread, not in raw interrupt context.

1. Read the STAT/ACK byte.
   - `00`: the interrupt is not ours; the line is shared.
   - `FF`: the device is gone. Ignore it.
2. Write the same bits back to acknowledge them.
3. Dispatch:
   - FR or RNR: drain the receive ring. On RNR, also restart the receive unit.
   - CX or CNA: reap the transmit ring, then move queued netbufs into the freed
     slots.
4. Repeat until STAT/ACK reads zero, with an iteration cap.

`disableAllInterrupts` and `enableAllInterrupts` set and clear SCB M.

### Watchdog (`timeoutOccurred`, 2-second period)

- **Link.**
  - MII parts: read BMSR. Log transitions with speed and duplex. On Intel
    PHYs (OUI `00AA00`) these come from register 16, where bit 1 means
    100 Mb/s and bit 0 means full duplex. On other PHYs they come from
    ANAR & ANLPAR.
  - 503-mode parts are assumed to have link.
  - No reconfiguration happens on a link change.
- **Transmit hang.** If the oldest outstanding slot has not completed across
  two consecutive ticks while link is up:
  - Run a full `resetAndEnable:`, counted and logged.
  - Keep counting across resets. After a limit, keep resetting but log more
    loudly, as Pro1000 does.
- **Statistics.** Every fifth tick:
  1. Issue Dump and Reset into a dword-aligned buffer.
  2. Poll for the completion code `A007` at the offset for this generation:
     64 bytes on the 82557, 76 on the 82558, 80 on the 82559 and later.
  3. Add the counts to the driver totals and to the DriverKit network
     counters: output errors, collisions, input errors.

### Errata

These are not in the SDM. Each one follows if_fxp and is cited in the source.
Before any code is written, each is checked against if_fxp.

1. **82557 receive lockup.** If no frame arrives for about 15 seconds,
   re-issue multicast setup. This clears a wedged receive unit, as in if_fxp's
   receive-idle tick.
2. **CU resume bug.** This applies to the parts if_fxp flags: some ICH parts
   and early 82559 steppings. Before each resume, apply if_fxp's workaround:
   a NOP CB and a short delay.
3. **ICH2/82559 Dynamic Standby.** The fix is to change an EEPROM bit and
   rewrite the checksum. It is **deliberately not applied**, because writing
   the user's EEPROM cannot be undone. The driver detects the condition and
   logs a warning.

## 5. Receive filtering

The driver overrides the same `IOEthernet` hooks that Pro1000 overrides.

- **Promiscuous mode.** Enabling or disabling it re-issues configure with
  byte 15 bit 0 set or cleared.
- **Multicast.**
  - Adding or removing an address updates a list of up to 32 entries and
    re-issues multicast setup.
  - Past 32 addresses, the driver re-issues configure with byte 21 = `0D`
    (multicast-all). It returns to the list once the count drops back.
- On receive, `isUnwantedMulticastPacket:` stays the final filter.

## Testing

### Build

- `rbuild buildpackage --arch i386` on `drvIntelE100` produces an `intele100`
  apk.
- The driver's own sources compile with no warnings.
- `IntelE100_reloc` links against symbols the kernel exports and nothing else.

### QEMU boot tests

Each run uses a temporary image of its own, per CLAUDE.md:
1. Start from a copy of `vm/golden.img` with the rebuilt i386 kernel grafted
   in.
2. Install the bundle with `vm/install-driver.py`.
3. Add `IntelE100` to Active Drivers with `rhap_inject set-key`.
4. Change the harness's QEMU line from `-device ne2k_pci,netdev=n0` to one
   eepro100 model, and add `-object filter-dump,id=f0,netdev=n0,file=<run>/e100.pcap`.
   The installed QEMU 11.1.0 provides the whole eepro100 family.

Run it on three models, one for each generation and path:

| Model | Covers |
|---|---|
| `i82557b` | 82557, the receive-lockup errata path |
| `i82559er` | 82559 generation |
| `i82801` | ICH-integrated |

Each model passes only if all of the following hold:
1. The serial log shows:
   - the probe line with chip name and generation
   - EEPROM checksum OK
   - a MAC address that matches QEMU's
   - link up at 100 Mb/s full duplex
2. The pcap contains frames with the guest's MAC as the source, for example the
   kernel's BOOTP/DHCP attempt or ARP.
3. The pcap contains frames from QEMU's slirp (10.0.2.2) addressed to the
   guest's MAC, and the driver's receive counters in the serial log show them
   arriving. Together with item 2, this proves both directions.
4. There is no panic, trap or debugger entry, and the boot reaches the Setup
   Assistant.

**Negative check:** boot with `ne2k_pci` and `IntelE100` still listed in Active
Drivers. The driver must not claim the NE2000, and the boot must still reach
the Setup Assistant.

## Documentation

- **`src/drivers-i386/README`:** the drvIntelE100 entry replaces
  drvIntel82557's. It states:
  - what was tested, and on which QEMU models
  - that it is not hardware-tested
  - the known limitations: DP83840 duplex, and Dynamic Standby not fixed
- **`NOTICE`:** the references and the rule that no code was copied, as
  described in "References and licensing".
- **`Instance0.table`:** carries a comment-free QEMU-shaped example. The
  `IRQ Levels` requirement is explained in the README entry. No separate
  README-Instance0 is needed.

## Out of scope

- Microcode download (CPU saver, receive bundling)
- Wake-on-LAN and power management
- 802.3x flow control
- Checksum offload, VLAN, and the 82550/1 extended RFD/TCB modes
- Writing the EEPROM
- Per-PHY duplex forcing
- A hardware test pass
