# Booting on QEMU's IBM 40p (PReP)

What it would take to boot RhapsodiOS on QEMU's `-M 40p` (IBM RS/6000 7020).
Assessed 2026-10-18 from reading the code and one probe boot. Nothing is built yet.

## Where it stands

Nothing in the tree supports PReP. The ppc platform driver,
[identify_machine.c](../../../src/drivers-ppc/bus/drvPExpert/powermac/identify_machine.c),
handles a fixed list of Power Mac models (Grand Central, Heathrow, OHare and
KeyLargo chips) and panics on any other machine.

The 40p is a different kind of machine: it has no Mac I/O chip and no Mac Open
Firmware. Instead it has a PC-style ISA bridge with i8259 interrupt controllers,
a 16550 serial port, PS/2 keyboard and mouse, an M48T59 clock/NVRAM chip, and a
53C810 SCSI controller on the board.

### Probe boot

```
qemu-system-ppc -name probe40p -M 40p -m 128 -vga std -display none -snapshot \
  -drive file=rhapsody.img,format=raw,if=none,id=d0 \
  -device scsi-hd,drive=d0,scsi-id=0 \
  -serial file:40p-serial.txt -qmp tcp:127.0.0.1:4471,server,nowait -monitor none
```

`if=scsi` is rejected on this machine, so the disk has to go on the onboard SCSI
controller with `-device scsi-hd`. With the MOSXS 1.2v3 ppc reference disk:

- OpenBIOS 1.1 comes up and reports a PowerPC 604 with 128 MB.
- The serial log then repeats `call-method slw_spin failed`.
- After about 45 s the CPU is at NIP 0, and the VGA screen dump is garbled,
  which looks like a stride mismatch.

None of Rhapsody runs.

## The work, in four stages

Each stage gets visibly further than the one before.

### 1. Firmware to booter

BootX expects Mac Open Firmware, so it is out. The older pre-BootX loader in
`src/boot-2/ppc/SecondaryLoader` is the better start: it can be linked as ELF
(`ElfSecondaryLoader.ld`), which OpenBIOS can load.

Open questions:

- Does OpenBIOS on the 40p read the Apple partition map at all? If it doesn't,
  the loader has to go in a PReP boot partition (MBR type 0x41).
- The loader builds the device tree and boot arguments the kernel reads, and
  OpenBIOS's tree won't look like a Mac's.

### 2. Kernel up to serial output

This is the biggest stage. It needs a new PReP machine family in drvPExpert,
next to the ones in `powermac/families/`:

- memory mappings for PReP's I/O window at 0x80000000 and PCI memory at 0xC0000000
- interrupt dispatch through the i8259 pair instead of Heathrow/OpenPIC
- clock and NVRAM on the M48T59 instead of Cuda/VIA
- a serial console on the 16550, because `machdep/ppc/serial_console.c` only
  drives the Mac's Zilog 8530

The CPU side needs nothing: the 604 is the same chip as in a 9500, and the
decrementer and page-table code work as-is. The Yosemite/CHRP family is the
closest template, since it is Apple's only board support for a machine that
isn't a classic Mac.

### 3. Root disk, which gets single-user

- PCI config access through QEMU's Raven host bridge.
- The 53C810 should be covered by the existing
  `src/drivers-ppc/scsi/drvPPCSym8xx`, once its interrupts are routed through
  the 8259.

### 4. Console and network, which get multi-user

- The i386 `drvPS2Keyboard`, `drvPS2Mouse` and `drvISASerialPort` already
  exist, but they use x86 `inb`/`outb`. On PReP those become memory accesses
  into the 0x80000000 window, so this needs a DriverKit port-I/O shim, not a
  rewrite.
- For video, use the framebuffer the firmware reports.
- For network, add `-device tulip` and use the DEC21x4 driver from the
  `ppc-qemu` branch, because QEMU's default PCnet card has no driver here.

Userland needs nothing; the existing ppc binaries run as-is.

## Risks

- Most of the risk is in stages 1 and 2. OpenBIOS on PReP is the
  least-maintained QEMU ppc firmware.
- Mac assumptions are spread through `machdep/ppc`: VIA timers in
  `powermac.h`, DBDMA, and the 8530.
- If the goal is just a working ppc emulator, g3beige and mac99
  (`vm/ppc-guest.py` on `ppc-qemu`) already get much further. The 40p is only
  worth it if PReP is a goal in itself.

## First step

A half-day check of stage 1 alone: build the ELF SecondaryLoader and see whether
OpenBIOS on the 40p loads it and prints anything. That tells you whether the
cheap route exists before any kernel work starts.
