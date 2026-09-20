# drvVGA boot gate — passed 2026-09-20

The VGA reconstruction's plan specified a gating boot test: put the driver on
screen under QEMU and confirm it logs
`VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)`, the string its own
`__cstring` carries. It was deferred in Phase 2, again in Phase 3a, and not
attempted in Phase 3b.

**It now passes.** The reconstructed `VGA_reloc` boots and produces output
identical to Apple's shipped driver.

## The blocker, and what cleared it

With the image's stock `mach_kernel`, the boot never reaches a display driver at
all. It dies in the open EIDE defect of [drvEIDE-issues.md](drvEIDE-issues.md):

```
rootdev 300, howto 40000
hc0: interrupt timeout, cmd: 0xc4
hc0: ATA command c4 failed. Retrying...
hc0: interrupt timeout, cmd: 0xec
hc0: ATA drive 0 is not present.
```

A control boot with the shipped `CirrusLogicGD5434DisplayDriver` configured
instead of `VGA` died at the identical point, so that failure was never about
the display driver. Active Drivers are instantiated only after the root device
is up.

**Our rebuilt kernel clears it.** Grafting `vm/install/mach_kernel` (1486184
bytes, built 2026-09-19) in place of the image's 1459520-byte one, the disk
mounts, the filesystem comes up clean and the boot reaches multi-user. The
kernel's interrupt handling is visibly different — the console now carries
`intr: phantom IRQ 15, EOI to master` — which is consistent with the lost-IRQ
mechanism that investigation describes, though this test does not establish the
mechanism and does not try to.

Note the EIDE polled-mode fallback in `IdeCnt.m` is *not* what did it: that lives
in the loadable `EIDE.config` bundle, and no rebuilt `EIDE_reloc` was injected
here. Searching our kernel for its log strings finds nothing.

## Procedure

```bash
cd vm
MSYS_NO_PATHCONV=1 python graft-kernel.py golden.img install/mach_kernel work/test.img
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img \
    set-key /private/Drivers/i386/System.config/Instance0.table \
    "Active Drivers" "VGA BusMouse NE2K"
python qemu-shot.py work/test.img shots-vga-newkern --at 30,60,95 --keys "mach_kernel -v\n"
```

`graft-kernel.py` rebuilds `work/test.img` from `golden.img`, so the
`Active Drivers` edit must follow the graft, not precede it. Which drivers load
is decided by that key, not by what is present in `/private/Drivers/i386`.

That run uses Apple's own `VGA.config`, which the image ships and whose binaries
are byte-identical to the reference this effort reconstructs against. It
establishes the gate before our build is substituted.

To substitute ours, both binaries were stripped on the build guest — Apple linked
the reference `ld -x`, ours is built `-g` — which brings them to 66812 and 26564
bytes against Apple's 71112 and 26584. `rhap_inject` refuses any write that
changes a file's fragment count, and the smaller kernel driver needed 66
fragments where the file occupies 70, so it was zero-padded back to exactly
71112. Its last section data ends at offset 43671, so the padding is inert.

```bash
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img \
    put /private/Drivers/i386/VGA.config/VGA_reloc  _vgastrip/VGA_reloc
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img \
    put /private/Drivers/i386/VGA.config/VGA_psdrvr _vgastrip/VGA_psdrvr
python qemu-shot.py work/test.img shots-vga-ours --at 30,60,95 --keys "mach_kernel -v\n"
```

## Result

Both runs — Apple's driver and ours — produce the same three lines:

```
Configuring device drivers
VGADisplay: Mode Selected: 640 x 480 @ 60 Hz (BW:2)
Registering: VGADisplay0
Using Default table for VGA
```

Because both files end up 71112 bytes, size does not prove which one ran. The
copy extracted back out of the booted image hashes to ours, not Apple's, with the
zero padding intact:

```
in image : 46425530859f3757
ours     : 46425530859f3757   <-- match
Apple    : 489d86652b871823
```

## What this does and does not establish

It establishes that the reconstructed **kernel half** loads under DriverKit,
initialises, selects its mode, registers as `VGADisplay0`, reads its config
table, and emits exactly what Apple's does. That is the first time any part of
this driver has been executed.

It does **not** exercise `VGA_psdrvr`. That half is loaded by the Window Server,
and this boot stops at `Continue without network? (y/n)`, before any GUI login.
The Window Server half remains unexecuted, and its correctness still rests
entirely on the static correspondence recorded in
`src/drivers-i386/video/drvVGA/reconstruction/divergences.md`.

It also does not exercise the SVGA path: this run uses `Default.table`, so
`enterSVGAMode:`, `int10:` and `_emu486` — the whole real-mode BIOS machinery —
were not reached. Booting `SVGABIOS.table` would be the next gate, and would be
the first execution of the emulator.
