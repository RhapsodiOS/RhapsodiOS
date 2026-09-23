# drvIntelE100 — Intel 8255x (e100) Ethernet driver design

Date: 2026-09-22
Status: approved design, revised after the FreeBSD if_fxp review (see
"Revisions" at the end); ready for an implementation plan

## Goal

`drvIntelE100` is a new BSD-licensed i386 DriverKit network driver for
Intel's 8255x 10/100 Ethernet family: the 82557, 82558, 82559, 82559ER,
82550 and 82551, plus the ICH-integrated 82562-based parts. It replaces the
existing `drvIntel82557` reconstruction.

The model is `drvIntel1000` (Pro1000): an original work, packaged as a Driver
bundle wrapping a Kernel Server, with LICENSE and NOTICE files that record
what was consulted.

Success has two parts:
- The driver's logic passes its C unit tests, and the driver builds
  warning-clean.
- It passes real traffic in both directions under QEMU on three emulated
  generations (see Testing).

It is not tested on real hardware.

## Decisions made during brainstorming

- **Replace, not coexist.** `src/drivers-i386/network/drvIntel82557` is
  deleted in the same change; git history keeps it. It was a decompiled
  reconstruction of Apple's driver:
  - it auto-detected only `0x1229`
  - it was missing its own header
  - it had no `apk/pkginfo`, so it was never packaged

  `drivers-ppc/network/Intel82557` is a separate project and is not touched.
- **Name.**
  - Directory: `drvIntelE100`.
  - Class, Server Name and Driver Name: `IntelE100`.
  - Bundle: `IntelE100.drvproj`. Kernel server: `IntelE100.lksproj`.
- **Feature set: a solid core.**
  - Probe across the full ID list.
  - Read the MAC address from the EEPROM and check its checksum.
  - MII autonegotiation and link reporting.
  - Simplified-mode receive and flexible-mode transmit (one TBD).
  - Multicast, promiscuous mode, and hardware statistics.
  - The errata a correct driver needs.
- **Not in scope:**
  - Microcode (Intel binary blobs).
  - Wake-on-LAN.
  - Flow control.
  - Checksum offload.
  - The 82550/1 extended RFDs.
- **Testing.** Guest-run C unit tests, a build, then QEMU boot tests on
  three models with a host-side packet capture. There is no hardware test
  pass.

## References and licensing

The driver is BSD-2-Clause, (c) 2026 Pat Raynor. NOTICE records the
references, following Pro1000's precedent:

1. **Intel 8255x 10/100 Mbps Ethernet Controller Family Open Source Software
   Developer Manual, Rev 1.0 (2003).** This is the primary specification. It
   covers:
   - the CSRs and the SCB
   - the CU and RU
   - the command block formats
   - the configure bytes
   - the EEPROM protocol
   - the MDI
   - the statistics dump
2. **FreeBSD `sys/dev/fxp` (`if_fxp.c`, `if_fxpreg.h`, `if_fxpvar.h`),
   BSD-2-Clause.** It fills the gaps the SDM leaves:
   - the device ID list
   - the EEPROM word map and the `0xBABA` checksum
   - the PHY type bits in word 6
   - the errata and their exact trigger conditions
   - the transmit-threshold policy

   Every value taken from it is cited in a source comment. No code is copied.
3. **Linux `drivers/net/ethernet/intel/e100.c` (GPL).** This is background
   reading only. Nothing is copied from it or derived from it line by line,
   and NOTICE says so explicitly.

## 1. Packaging and file layout

```
src/drivers-i386/network/drvIntelE100/
  Makefile, Makefile.preamble        Aggregate project, INCLUDED_ARCHS = i386
  LICENSE                            BSD-2-Clause
  NOTICE                             references, as above
  apk/pkginfo                        pkgname = intele100, pkgver = 1.0, arch = i386,
                                     license = BSD
  tests/                             C unit tests, built and run on the build guest
    Makefile, e100_logic_test.c, e100_hw_test.c, e100_test_ports.h
  IntelE100.drvproj/                 Driver bundle, BUNDLE_EXTENSION = config
    Default.table                    catalogue: Auto Detect IDs for the whole family
    Instance0.table                  QEMU-shaped instance (IRQ Levels = 11)
    DriverInfo, English.lproj/{Localizable.strings, DriverHelp/TableOfContents}
    PB.project, Makefile, Makefile.preamble
    IntelE100.lksproj/               Kernel Server
      E100Regs.h                     definitions only
      E100Logic.h, E100Logic.c       pure logic: no I/O, no kernel calls
      E100Port.h                     port I/O and delay macros (kernel or test mocks)
      E100Hw.h, E100Hw.c             SCB, PORT, EEPROM and MDI access through E100Port.h
      IntelE100.m                    the IOEthernet subclass
      Load_Commands.sect             WIRE
      PB.project, Makefile, Makefile.preamble
```

### How the code is split

The split follows drvAHCI: logic that can be tested without the kernel lives
in plain C89 files, and `tests/` builds that logic with the build guest's
`cc` and runs it.

- **`E100Logic.c`** holds everything that is a pure function:
  - the chip table and its lookup
  - the effective revision and quirk flags
  - MAC address extraction and validation
  - the configure-byte builder
  - filling the multicast CB
  - detecting that a statistics dump has completed
  - the transmit-threshold policy
  - decoding the link state
- **`E100Hw.c`** performs every register access through the `E100_INB` and
  related macros in `E100Port.h`:
  - SCB command and wait
  - CU resume, with and without the erratum NOP
  - PORT reset
  - EEPROM microwire read and address-width detection
  - MDI read and write
  - waiting for a CB to complete

  In the kernel those macros are DriverKit's `inb`/`outb`/… and `IODelay`.
  Under `-DE100_HOST_TEST` they are the test mocks. The mocks simulate a
  93C46/93C66 EEPROM, an MDI PHY and the SCB command byte.
- **`IntelE100.m`** is the only Objective-C file. It does probe and init,
  owns the DMA memory and the rings, and handles transmit, receive,
  interrupts, the watchdog and filtering.

The build guest is PowerPC, so the tests assert values rather than
little-endian byte images.

### Load commands

`Load_Commands.sect` holds only `WIRE`, like every driver in this tree that
has been built, the network drivers included. Pro1000 alone adds `START` and
`DETACH`, and it has never been built here. Boot drivers are never unloaded,
so `DETACH`'s protection against an unload panic is not needed on this path.

The bundle carries `English.lproj/DriverHelp`, as drvAHCI does, because
driver.make's `movehelp` expects the directory.

### Chip table

The chip table is FreeBSD's if_fxp ident list, with the product names in our
own words:

| Device ID | Parts |
|---|---|
| `1029`, `1030`, `1209` | discrete 82559 parts |
| `1031`–`1038` | ICH3 |
| `1039`–`103E` | ICH4 |
| `1050`, `1051` | ICH5 |
| `1059` | 82551QM |
| `1064`, `1065`, `1068`, `1069` | ICH6 |
| `1091`–`1094` | ICH7 |
| `2449` | ICH2/3 |
| `27DC` | ICH7 |
| `1229` | revision-specific entries (see below) |

For `1229`, revisions 1–3 are the 82557, 4–5 the 82558, 6–8 the 82559, 9 the
82559ER, `0C`–`0E` the 82550 and `0F`–`10` the 82551. A catch-all entry
covers any other revision. Each entry also records its ICH generation
(0 for discrete parts).

**Effective revision** (the if_fxp rule):
- ICH parts count as revision 8.
- Otherwise, an EEPROM word 5 with high byte 1 means an 82557 (revision 1).
- Otherwise the PCI revision ID is used.

The revision decides:
- **82557 versus 82558+ configure bytes:** revision below 4 is an 82557.
- **The CU-resume erratum:** applies from revision 8.
- **The receive-lockup erratum:** applies below revision 4.
- **The generation name in the log:**

  | Revision | Name |
  |---|---|
  | < 4 | 82557 |
  | 4–5 | 82558 |
  | 6–11 | 82559 |
  | ≥ 12 | 82550/82551 |

On 82550/82551 the driver runs the same simplified RFDs and flexible-mode
TxCBs as on the other parts. The SDM describes both modes for the whole
family. FreeBSD, however, only ever runs these two parts in their extended
modes, so the driver logs that the simplified receive path is unverified on
this generation.

`Default.table` lists exactly the IDs in the chip table.

### Retirement

- Delete `src/drivers-i386/network/drvIntel82557`.
- Replace its line in `src/drivers-i386/README` with the drvIntelE100 entry.

## 2. Discovery and bring-up

### CSR access

CSR access goes through the I/O BAR, for three reasons:
- the window is only 64 bytes
- DriverKit's port I/O needs no mapping
- the SDM notes that some bridges mishandle memory-mapped CSRs

The driver scans the BARs for an assigned I/O BAR, as Pro1000 does, and
refuses the device if none is assigned. If the BIOS left I/O decoding or bus
mastering off in the PCI command register, the driver turns them on. It
writes the status half back as zero, so none of that half's
write-one-to-clear bits are touched.

SCB command and status are accessed a byte at a time, so a command write
cannot clobber the interrupt-mask byte.

### `initFromDeviceDescription:`

1. **Identify the part.**
   - Read PCI config space.
   - Refuse any vendor other than `8086`.
   - Look up the device ID and revision in the chip table.
2. **Reset.** Issue a selective reset, then a software reset (the same pair
   FreeBSD uses). Mask interrupts with SCB M, because PORT commands clear it.
3. **Read the EEPROM.**
   - Detect the address width (6 or 8 bits) with the SDM's dummy-zero method.
     Refuse the device if the EEPROM does not answer.
   - Read every word and check the sum against `0xBABA`. A mismatch is
     logged, not fatal.
   - Take the MAC address from words 0–2, low byte first. Refuse it if it is
     all zeros, all ones, or multicast.
4. **Work out the effective revision and the quirk flags** (Section 4).
5. **Find the PHY**, unless the part is 82503 serial-only:
   - Try the MII address in EEPROM word 6 first.
   - Otherwise scan addresses 0–31 for a PHY whose PHYID1 is neither 0 nor
     `FFFF`.
   - Log where it was found. If none answers, link is reported as up.
   - Start autonegotiation once, here: BMCR autonegotiate enable and restart.
6. **Allocate DMA memory** (Section 3). Log the identity, MAC, EEPROM and
   PHY lines, then attach with `attachToNetworkWithAddress:`.

The IRQ comes from the device description. The driver logs how many it was
given, because a missing `IRQ Levels` key silently gives zero (the Pro1000
lesson).

### `resetAndEnable:`

This method never sleeps. Every wait is a bounded `IODelay` loop.

1. Mask interrupts, clear the timeout and set not running. Issue a
   selective reset and a software reset, then re-mask. If `enable` is NO,
   free the queued netbufs and return.
2. Load CU Base = 0, then RU Base = 0. Every pointer is now a 32-bit
   physical address. Zero the statistics block and load its address.
3. Run configure, then IA setup, then multicast setup. Each runs polled
   from one dedicated command block:
   1. Wait for the CU to be idle.
   2. Write the CB with EL set, then issue CU Start.
   3. Wait for C, then check OK.
4. Build the transmit ring and start the CU on slot 0. Slot 0 is a NOP with
   S set, so the CU suspends there and never goes idle again.
5. Build the receive ring and issue RU Start at its head.
6. Acknowledge any stale causes, unmask, set running, arm the watchdog, and
   move any queued frames into the ring.

If any step times out, the step is logged and `resetAndEnable:` fails.

### Configure bytes

The values are the SDM's recommended configure bytes, 22 in all:

| Byte | 82557 | 82558+ | Notes |
|---|---|---|---|
| 0 | `16` | `16` | |
| 1 | `08` | `08` | |
| 2 | `00` | `00` | |
| 3 | `00` | `00` | MWI off |
| 4 | `00` | `00` | |
| 5 | `00` | `00` | |
| 6 | `32` | `32` | see below |
| 7 | `03` | `03` | underrun retry 1, discard short frames |
| 8 | `01` | `01` | MII; `00` for an 82503 serial interface |
| 9 | `00` | `00` | |
| 10 | `2E` | `2E` | |
| 11 | `00` | `00` | |
| 12 | `60` | `61` | bit 0 must be 1 on the 82558 and 82559 (SDM) |
| 13 | `00` | `00` | |
| 14 | `F2` | `F2` | |
| 15 | `48` | `48` | `+80` for 82503 CRS/CDT; `+01` promiscuous |
| 16 | `00` | `00` | |
| 17 | `40` | `40` | |
| 18 | `F2` | `F2` | pad short frames |
| 19 | `80` | `80` | FDX pin |
| 20 | `3F` | `3F` | |
| 21 | `05` | `05` | `0D` = all multicast |

Byte 6 is `32`, which selects:
- **CNA interrupts, not CI.** The CU suspends rather than goes idle, and
  only CNA fires on a suspend.
- **Standard TxCBs.**
- **Standard (82557-format) statistics on every generation.**

Promiscuous mode also sets byte 6 bit 7 (save bad frames) and clears byte 7
bit 0 (discard short frames), as the SDM recommends.

**Known limitation:** duplex follows the PHY's FDX pin. An 82557 board with
an external DP83840 PHY that does not wire FDX runs half duplex. The driver
has no per-PHY forcing code.

## 3. Data path

### DMA memory

Every DMA block comes from Pro1000's idiom:
1. `IOMalloc` twice the size.
2. Use whichever half lies within one page.
3. Confirm physical contiguity with `IOPhysicalFromVirtual` at both ends.

The blocks are:
- 16 transmit slots and 32 receive slots of 1,536 bytes each
- one 256-byte command block
- one statistics block

### Transmit ring

The transmit ring is 16 flexible-mode TxCBs, each with one TBD:
- They are linked into a static circle when built and never relinked.
- Each has SF set, TCB byte count 0, TBD number 1, and a TBD at slot offset
  `600h` (1536) pointing at the frame data, which stays inline at offset
  `10h`.
- The ring carries only frames and the initial NOP. Command CBs never go
  through it.

Simplified-mode transmit (SF = 0, a TBD pointer of `FFFFFFFF`, EOF set with
the byte count) is valid per the SDM, but the installed QEMU 11.1 is a
Stefan Weil ar7-branch build whose simplified-mode transmit path never sets
the outgoing packet length, so every frame goes out zero-length. Flexible
mode with a single TBD is valid on every 8255x (SDM 6.4.2.5) and is how
FreeBSD's fxp transmits, and it is unaffected by that bug.

**`transmit:(netbuf_t)`**
1. Reap completed slots.
2. If frames are already queued, or the ring holds 15 frames, append the new
   frame to the `IONetbufQueue` (32 entries). A frame dropped because the
   queue is full is counted. Then drain what fits.
3. Otherwise:
   1. Copy the frame inline and free the netbuf.
   2. Set S on the new slot, then clear S on the previous one.
   3. Issue CU Resume. On parts with the erratum, issue a CU NOP first
     (Section 4).

**Transmit threshold** (FreeBSD's policy):
- It starts at 64 (512 bytes).
- Whenever a statistics dump reports underruns, it rises by 64, up to 192.
  The TxCB's own U bit is not used, because the SDM says wire status only
  shows up in the counters.

**Short frames** are padded by the chip (configure byte 18).

### Receive ring

The receive ring is 32 simplified-mode RFDs:
- The buffer size field is 1,520.
- The RFDs are linked into a circle, and only the tail has EL set.

**On FR or RNR:**
1. Walk forward while C is set, at most one full ring.
2. For each RFD:
   - If it has OK, no error bits, and a length of 14 to 1,519 bytes:
     `nb_alloc`, copy, filter with `isUnwantedMulticastPacket:`, count it,
     and hand it up with `handleInputPacket:extra:`.
   - Otherwise count an error.

   EOF is not checked: QEMU never sets it, and FreeBSD's fxp does not check
   it either. Without it, a count equal to the 1,520-byte buffer size could
   mean a truncated frame rather than one that exactly fills the buffer, so
   a completely full RFD is treated as an error.
3. Recycle the RFD:
   1. Clear its status and count.
   2. Set EL on it, making it the new tail.
   3. Clear EL on the old tail.

**On RNR:** after draining, issue RU Start at the head. RU Resume is illegal
from the no-resources state.

## 4. Interrupts, watchdog and errata

### `interruptOccurred`

1. Read STAT/ACK.
   - `00`: the interrupt is not ours (the line is shared).
   - `FF`: the card is gone.
2. Acknowledge exactly the bits that were read.
3. Dispatch:
   - FR or RNR: receive.
   - CX or CNA: reap the transmit ring and drain the queue.
4. Loop, at most 16 passes.
5. If the driver is running, re-enable interrupts at the framework level
   with disable then enable. This is the Pro1000 finding.

### Watchdog (`timeoutOccurred`, every 2 seconds)

- **Link.** On MII parts, read BMSR twice (link status latches low). When
  the state changes, log it:
  - up or down
  - speed and duplex, from ANAR & ANLPAR once autonegotiation has completed
  - failing that, from Intel PHY register 16 (bit 1 = 100 Mb/s, bit 0 =
    full duplex)
  - failing both, "unknown"

  Parts with no MII count as up.
- **Transmit hang.** Frames are outstanding, link is up, and nothing has
  completed for two ticks.
  - Run a full `resetAndEnable:`, counted and logged.
  - From the third reset on, the log line says so more loudly.
- **Statistics.** Every fifth tick:
  1. If the previous Dump and Reset has completed, fold its counters into
     the totals and into the DriverKit collision and error counters. Adjust
     the transmit threshold, and log a line when anything moved.
  2. Zero the block and issue the next Dump and Reset.

  Completion is `A007` at dword 16, 19 or 20. Each of the three dump layouts
  puts it at a different one of those, so a part that ignores byte 6 is
  still read correctly.

### Errata

These are not in the SDM. Each follows if_fxp and is cited in the source.

1. **82557 receive lockup.**
   - **Applies when:** revision is below 4 and EEPROM word 3 does not have
     both low bits set.
   - **Trigger:** nothing is received for 16 seconds.
   - **Action:** a full `resetAndEnable:`. if_fxp's comment says
     "reprogram multicast", but its code reinitialises the whole chip.
2. **CU resume / Dynamic Standby (82801BA erratum 30).**
   - **Applies when:** the part is ICH2/3, or is discrete with revision 8 or
     later, **and** EEPROM word `0A` has bit `0x02` (Dynamic Standby) set.
   - **Action:** write CU NOP to the SCB command byte and wait for it to be
     accepted before every CU Resume. if_fxp does exactly this, not a NOP
     CB.
   - if_fxp applies it only at 10BASE-T; this driver applies it at every
     speed, which is simpler and costs one byte write.
   - if_fxp also clears the EEPROM bit and rewrites the checksum. This
     driver **does not**, because writing the user's EEPROM cannot be undone.
     It logs that the workaround is active instead.

## 5. Receive filtering

The driver overrides the same `IOEthernet` hooks as Pro1000:
- **Promiscuous mode:** a flag.
- **Multicast mode:** a flag. When it is on and the list is empty, the
  driver accepts all multicast, as Pro1000 does.
- **Multicast addresses:** a list of up to 32, plus a count of addresses
  added beyond that. A nonzero overflow count means accept all multicast.
  Removing an address that is not in the list decrements the overflow count.

Any change re-runs `resetAndEnable:` if the driver is running, which is
FreeBSD's approach. Filter changes are rare, and it keeps commands out of the
live transmit ring. `isUnwantedMulticastPacket:` stays the final filter on
receive.

## Testing

### Unit tests

`tests/` is built and run on the build guest by `gnumake check`, with
`cc -ansi -pedantic -Wall -Werror`.

- **`e100_logic_test`** covers:
  - the chip table, including revision-specific and catch-all entries
  - the effective revision and every quirk condition
  - MAC extraction and validation
  - configure bytes for 82557, 82558+, serial, promiscuous and all-multicast
  - multicast CB filling
  - statistics completion at each offset
  - the threshold policy
  - link decoding
- **`e100_hw_test`** runs `E100Hw.c` against simulated ports:
  - EEPROM width detection and reads at 6 and 8 address bits
  - MDI read/write, a wrong-address read, and the timeout
  - the SCB command order, including the NOP before a resume
  - the SCB and CB timeouts

### Build

- `rbuild buildpackage --arch i386` produces the `intele100` apk.
- The driver's own sources compile with no warnings.

### QEMU boot tests

`vm/e100-boot.py` runs every boot on images of its own under the checkout's
`vm/work/`, per CLAUDE.md:
1. `golden.img` has the rebuilt kernel grafted in.
2. The bundle is installed as a boot driver.
3. QEMU gets the eepro100 model at `addr=03.0`, `mac=52:54:00:12:34:56`,
   plus `filter-dump` to a pcap.

There are two modes:
- **single:** boot `-s`. At the shell, run
  `ifconfig en0 10.0.2.15 netmask 255.255.255.0 up`, then
  `ping -c 3 10.0.2.2`, then `netstat -in`, taking a screenshot after each.
- **multi:** a normal boot. Answer `y` at the network prompt and take
  screenshots through to the Setup Assistant.

Models:

| Model | Covers |
|---|---|
| `i82557b` | 82557 and the receive-lockup path |
| `i82559er` | 82559 generation |
| `i82801` | ICH |
| `i82551` | 82551, as a smoke run of simplified mode on that part |

Each model must meet all of these:
1. The serial log shows:
   - the identity line with chip name and generation
   - EEPROM checksum OK
   - MAC `52:54:00:12:34:56`
   - a PHY found
   - `1 irq`
   - link up at 100 Mb/s full duplex
2. In the single run:
   - `e100-pcap.py` finds frames sent by the guest and frames sent to it,
     including ARP and ICMP echo replies from 10.0.2.2
   - the screenshot shows ping replies
   - a statistics line in the serial log shows rx > 0
3. In the multi run:
   - no panic, trap or debugger entry
   - the boot reaches the Setup Assistant

**Negative check:** a multi-mode boot with `ne2k_pci` and the driver still
installed. The driver must not claim the NE2000, and the boot must still
reach the Setup Assistant.

## Documentation

- **`src/drivers-i386/README`:** the drvIntelE100 entry replaces
  drvIntel82557's. It states what was tested and on which QEMU models, that
  it is not hardware-tested, and the known limitations:
  - DP83840 duplex
  - Dynamic Standby left set in the EEPROM
  - 82550/1 simplified receive unverified beyond QEMU
- **`NOTICE`:** the references and the rule that no code was copied.

## Out of scope

- Microcode download (CPU saver, receive bundling)
- Wake-on-LAN and power management
- 802.3x flow control
- Checksum offload, VLAN, and the 82550/1 extended RFD/TCB modes
- Writing the EEPROM
- Per-PHY duplex forcing
- A hardware test pass

## Revisions

These changes followed a reading of FreeBSD if_fxp, after the design was
first approved:

1. **Where the logic lives.** Pure logic moved into `E100Logic.c`, and
   register access into `E100Hw.c` (plain C, reached through `E100Port.h`),
   with C unit tests under `tests/`. drvAHCI is the precedent.
2. **Command CBs.** They no longer go through the transmit ring. They run
   polled with the CU idle during `resetAndEnable:`, and a filter change
   re-runs `resetAndEnable:`. The ring starts on a NOP with S set, so every
   transmit is a CU Resume.
3. **CU-resume erratum.** The workaround is an SCB-level CU NOP before each
   resume, not a NOP CB. The trigger conditions come from if_fxp.
4. **82557 receive lockup.** It has an exact trigger condition, and it
   recovers with a full reinit rather than a multicast re-issue.
5. **Transmit threshold.** It is driven by the statistics underrun counter,
   using FreeBSD's values, instead of the TxCB U bit.
6. **Statistics.** The standard layout is used on every generation, and
   completion is detected at any of the three layouts' offsets.
7. **Revision and PHY.** The effective-revision rule comes from if_fxp. The
   PHY address falls back to a scan, and autonegotiation starts once in init
   rather than on every reset.
8. **ID list.** It is if_fxp's exact list, and an i82551 smoke run joins the
   QEMU matrix.
9. **Packaging.** The project layout mirrors drvAHCI, which has built
   successfully: `WIRE`-only load commands and a `DriverHelp` directory.
   Pro1000's `START`/`DETACH` and `movehelp` override have never been built.
10. **Flexible-mode transmit.** The installed QEMU 11.1 (a Stefan Weil
    ar7-branch build) sends zero-length frames from simplified-mode TxCBs.
    The transmit ring now uses flexible mode with one TBD instead, which is
    valid on every 8255x and is how FreeBSD's fxp transmits.
11. **Receive EOF not checked.** QEMU never sets EOF in the RFD actual
    count, and FreeBSD's fxp does not check it either, so the driver no
    longer requires it. A completely full RFD is now treated as an error,
    since without EOF that could mean a truncated frame.
