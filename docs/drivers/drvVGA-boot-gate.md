# drvVGA boot gate — attempted 2026-09-20, blocked

The VGA reconstruction's plan specified a gating boot test: put the driver on
screen under QEMU and confirm it logs
`VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)`, the string its own
`__cstring` carries. It was deferred in Phase 2 because the shared working image
was in use, deferred again in Phase 3a, and not attempted in Phase 3b.

It has now been attempted. **The gate cannot be reached**, for a reason that has
nothing to do with this driver.

## What was run

```bash
cd vm
qemu-img convert -O raw golden.img work/test.img          # fresh scratch image
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img \
    set-key /private/Drivers/i386/System.config/Instance0.table \
    "Active Drivers" "VGA BusMouse NE2K"
python qemu-shot.py work/test.img shots-vga-stock --at 25,50,80 --keys "mach_kernel -v\n"
```

Which drivers load is decided by that key, not by what is present in
`/private/Drivers/i386`. The image ships Apple's own `VGA.config` with both
reference binaries byte-identical to the ones this effort reconstructs against,
so this run tests **Apple's stock driver**, deliberately: it establishes the gate
before our build is ever substituted.

## What happened

The boot reaches DriverKit and registers the bus and storage drivers, then dies
before any Active Driver is instantiated:

```
Registering: kmDevice0
rootdev 300, howto 40000
hc0: interrupt timeout, cmd: 0xc4
hc0: Read Multiple: error=0x0 secCnt=0x0 secNum=0x60 cyl=0x1 drhd=0xe0 status=0x58
hc0: ATA command c4 failed. Retrying...
hc0: Resetting drives...
hc0: interrupt timeout, cmd: 0xec
hc0: ATA drive 0 is not present.
```

That is the documented, open EIDE defect in
[drvEIDE-issues.md](drvEIDE-issues.md) §2 — `cmd 0xc4` is READ MULTIPLE,
`status 0x58` is `DRDY|DSC|DRQ`, and the driver enters a zero-progress
interrupt-timeout loop and then disowns the disk. No display driver of any kind
is reached, because Active Drivers are instantiated after the root device is up.

`shots-vga-stock/serial.log` is empty; the kernel's serial console emitted
nothing on COM2 for this kernel, so the screenshots are the only channel.

## The control

To rule out the `Active Drivers` edit as the cause, the same image was booted
again with the key restored to its shipped value
`CirrusLogicGD5434DisplayDriver BusMouse NE2K`:

```bash
python qemu-shot.py work/test.img shots-vga-control --at 80 --keys "mach_kernel -v\n"
```

It dies at the same point, with the same `cmd 0xc4` timeout and the same
`ATA drive 0 is not present`. The only difference is which sector the failed
READ MULTIPLE names. **The failure is independent of the display driver
configured**, and predates this effort entirely.

## Consequence

Booting our rebuilt `VGA_reloc` and `VGA_psdrvr` would fail identically and would
demonstrate nothing about them, so it was not attempted. The gate becomes
runnable when the EIDE defect is fixed, and not before.

Nothing about the VGA reconstruction is implicated, and nothing about it is
thereby confirmed either. **Neither half of this driver has ever been executed.**
Everything the effort has established remains a static correspondence between our
sources and Apple's bytes — a real result, and not the same thing as a driver
that works.
