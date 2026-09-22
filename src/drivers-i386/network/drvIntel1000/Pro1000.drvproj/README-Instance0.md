# About Instance0.table

**If you are installing this driver on your own machine, this is the one
file you have to edit.**

`Default.table` is a catalogue: it lists every device this driver claims
and is the same everywhere. `InstanceN.table` describes a device that was
actually found *here* — so the values that differ from machine to machine
live in it, and nowhere else. That is also why they are not constants in
the driver source.

The two that matter:

```
"Location" = "Dev:1 Func:0 Bus:2";      ← your card's PCI location
"IRQ Levels" = "3";                     ← the IRQ your BIOS assigned
```

Both come from the PCI bus, and `pcils` (shipped alongside this driver)
prints them. Look for the line naming your controller:

```
02:01.0 Ethernet controller [0200]: Intel 82547EI Gigabit Ethernet (CSA)
        IRQ 3, pin A
        BAR0: mem 0xe8100000 (32-bit, non-prefetchable)
```

`02:01.0` is bus 2, device 1, function 0 — written `"Dev:1 Func:0 Bus:2"`.
`IRQ 3` is the interrupt.

The layout follows OPENSTEP's own working driver: the 10 Mb card in the
development machine carries `"Location" = "Dev:11 Func:0 Bus:3"` in
`DECchip21040NetworkDriver.config/Instance0.table`.

## Why "IRQ Levels" is not optional

The stock drivers on this machine do not carry that key and their
interrupts work, so it looks like something that can be left out. It
cannot.

Configuration space holds the IRQ the BIOS assigned, but **DriverKit
does not necessarily know it.** The driver logs both, so the two can be
compared. Configuration space, from `+probe:`:

```
Pro1000: 8086:1019 at BAR0 0xe8100000 -> 0x222e2000, config IRQ 3
```

and what the framework actually handed over, on the summary line the
driver prints once it is enabled:

```
Pro1000: 82547EI enabled, 0 irq, RCTL 0x04008002 ...
                            ^^^^^
```

Configuration space said IRQ 3; the device description carried none.
With no interrupt registered there is nothing for the framework to
deliver, so `-interruptOccurred` is never called.

**`0 irq` on that line is the signature of a missing `"IRQ Levels"`.**

The failure is quiet and misleading. Transmits *complete in hardware* —
the descriptor is consumed and `TDH` reaches `TDT` — while the driver
waits three seconds for a completion that cannot arrive, then resets the
device and tries again. It looks like broken transmit; it is a missing
interrupt.

Adding the key fixed it — the same line then reads:

```
Pro1000: 82547EI enabled, 1 irq, RCTL 0x04008002 ...
Pro1000: interrupts flowing, first ICR 0x00000006
```

It was tempting to conclude that the boot path is different — that
`driverLoader a`, running at boot alongside a live PCI bus driver,
assigns resources that `driverLoader D=` does not. **That was tested and
it is false.** With the key removed and the machine rebooted, the boot
path reported:

```
Pro1000: 82547EI enabled, 0 irq, ...
```

No interrupt is assigned at boot either. The key is required on every
path, not just the runtime one.

## Setting it from Configure.app instead

`Configure.app` is the intended editor for this file, and its IRQ Level
matrix writes this exact key. The driver needs no change to honour a
choice made there — it never names an IRQ itself, it uses whatever the
device description carries. See "Configure.app is the intended editor
for these values" in the top-level `README.md`, which has a screenshot.

`Location` is the exception: it is not in that window and has to be
written here by hand.

## Moving to another machine

`Location` and `IRQ Levels` describe the machine, not the driver. Read
them with `pcils` on the new machine and edit this file.

**No recompile is involved.** This file is plain text inside the bundle;
only `Pro1000_reloc` is compiled. Build once, then edit tables per
machine. The driver does have to be reloaded to read them, which with
`DETACH` in place means a reboot.
