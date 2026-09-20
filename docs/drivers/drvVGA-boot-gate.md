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

## Second gate: the SVGA path and the emulator

The first run used `Default.table`, so the real-mode BIOS machinery was never
reached. The image ships no `Instance0.table` in `VGA.config`, which is why the
driver logs `Using Default table for VGA`, so the SVGA path is taken by putting
our corrected `SVGABIOS.table` over `Default.table`. Both are under one 1024-byte
fragment, so the write is accepted in place:

```bash
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img     put /private/Drivers/i386/VGA.config/Default.table _vgastrip/svga.table
```

That table carries the two keys Phase 2 added after finding our copy was missing
them, `"SVGA Mode" = "Yes"` and `"SVGA VESA BIOS Mode" = "0x6a"`. The boot then
logs:

```
VGADisplay: Mode Selected: 800 x 600 @ 60 Hz (BW:2)
VGADisplay: VESA mode selected: 0x6a
Registering: VGADisplay0
```

**That second line is the emulator's first execution.** It is emitted by
`-[IOVGADisplay(VESAMode) enterSVGAMode:]`, which reaches it only by calling
`int10:`, which calls `vidBIOS`, which runs `_emu486`. For it to print at all,
10496 bytes of transcribed hand-written assembly had to interpret a real-mode
INT 10h call into the card's video BIOS and return cleanly — no
`VGADisplay: vidBIOS failed`, none of the four `emu486 error` paths. The mode
genuinely changed: the framebuffer is 800x600 from this point on.

## Past the network prompt, and the Window Server half

`qemu-shot.py` sends one batch of keys at one time, which is enough for the boot
prompt but not for a later interactive question. `guest-console.py` drives the
emulated keyboard over QMP and reads the framebuffer back, so it can answer
`Continue without network? (y/n)` when it appears. The scenario boots, types
`mach_kernel -v`, waits, answers `y`, and keeps capturing.

The boot then reaches the GUI. The desktop comes up at 800x600 in dithered
two-bits-per-pixel — which is exactly what `ColorSpace: BW:2` means, four grey
levels — running the Rhapsody Setup Assistant, with a drawn mouse cursor, and it
is still stable at 340 seconds.

**That is `VGA_psdrvr` executing.** The Window Server loads it by name from the
bundle, per `"PostScript Driver" = "VGA_psdrvr"`, and everything on screen is
going through its planar conversion routines. The cursor being drawn means the
cursor path ran too. The copy extracted back out of the image is ours:

```
psdrvr in image : d3a5d8fa3e6e1073
ours            : d3a5d8fa3e6e1073   <-- match
Apple           : e785ba22f1121eaa
```

## What this does and does not establish

Both halves of the reconstruction have now executed.

The **kernel half** loads under DriverKit, initialises, reads its config table,
selects its mode, registers as `VGADisplay0`, and emits exactly what Apple's
does. On the SVGA path it also drives the real-mode BIOS through `vidBIOS` and
`_emu486` and changes the mode to 800x600.

The **Window Server half** is loaded by the Window Server, renders the desktop
at 800x600 in 2bpp through its planar conversion routines, and draws the cursor.

What remains unexercised is narrower than before but real. The cursor was
observed drawn, not moving, so the erase-and-redraw path — `_VGASetCursor` and
both blitters on the bundle side, `moveCursor:frame:token:` and
`_VGADisplayCursor`/`_VGARemoveCursor` on the kernel side — is not proven by
these runs. Neither is the 128-byte `save` write into a 64-byte field that both
halves reproduce: it is latent at this geometry, and a cursor-motion test is what
would exercise it. No SVGA-mode `getIntValues:`/`setIntValues:` traffic beyond
registration was exercised either.

Title notwithstanding, "passed" means the driver loads, initialises, sets modes
and paints. It does not mean every reconstructed path has run.
