# i386: a spurious slave interrupt permanently disables IRQ 8-15

## Symptom

Any device on the cascaded (slave) 8259 stops receiving interrupts after some
point during or after boot, while devices on the master PIC keep working. The
device itself is healthy and is asserting its interrupt line; the interrupt is
simply never delivered to the CPU again.

This was found via the EIDE disk driver under QEMU, where it presents as:

```
hc0: interrupt timeout, cmd: 0xc4
hc0: ATA drive 0 is not present.
```

but the defect is in the kernel's PIC handling, **not** in `drvEIDE`. Any slave
IRQ is affected — IRQ 14/15 (IDE), IRQ 12 (PS/2 mouse), IRQ 9/10/11 (typical
PCI). The full driver-side investigation is in
[`docs/drivers/drvEIDE-issues.md`](../drivers/drvEIDE-issues.md) §2.

## Evidence

QEMU's PIC state, sampled every 15-30 seconds across 130 seconds of a wedged
guest (`info pic` and `info irq` via QMP):

| | t=20s | t=150s |
|---|---|---|
| IRQ 0 (timer) delivered | 1,438 | 14,426 |
| IRQ 2 (cascade) asserted | 562 | **13,434** |
| IRQ 14 (disk) delivered | **7** | **7** |

```
pic1: irr=40 imr=bf isr=00     <- slave: IRQ 14 requested, unmasked, not in service
pic0: irr=04 imr=fa isr=04     <- master: cascade IRQ 2 IN SERVICE
```

Identical at every sample. The reading is unambiguous:

- The slave has IRQ 14 pending (`irr` bit 6) and **not** masked (`imr=bf` clears
  bit 6), so nothing is suppressing the request.
- The slave raised the cascade to the master over 13,000 times.
- The master's in-service register has **bit 2 — the cascade — set and never
  cleared**.
- IRQ 14 delivery is frozen at 7.

An 8259 will not deliver an interrupt of equal or lower priority than one
already in service. With IRQ 2 stuck in service, every slave interrupt (IRQ
8-15) is blocked indefinitely. IRQ 0 continues because it outranks IRQ 2, which
is exactly why the timer kept running while the disk died.

## Root cause

`intr_dispatch()` in `machdep/i386/intr.c` had one early return ahead of its
`send_eoi()` call — the phantom (spurious) interrupt check:

```c
    if (((irq == INTR_MASTER_PHANTOM_IRQ &&
		(get_master_isr() & INTR_PHANTOM_IRQ_MASK) == 0)) ||
	((irq == INTR_SLAVE_PHANTOM_IRQ &&
		(get_slave_isr() & INTR_PHANTOM_IRQ_MASK) == 0)) ) {
	 intr_cnt.phantom++;
	 return;
    }
```

A spurious interrupt sets no in-service bit in the PIC that reported it, which
is how the check recognises one. But the master and slave cases are **not**
symmetric, and the original code treated them identically:

- **Spurious IRQ 7 (master).** Correct to return with no EOI — the master has
  nothing in service.
- **Spurious IRQ 15 (slave).** Incorrect. By the time the slave reports the
  interrupt as spurious, the master has *already* acknowledged the cascade and
  set its IRQ 2 in-service bit. That bit must be cleared with an EOI to the
  **master only** (the slave has nothing to clear). Returning without one
  strands the cascade in service forever.

This is why the observed master ISR is exactly `0x04`: no other path in
`intr_dispatch()` produces that state.

## Fix

Split the check so the slave case sends a master-only EOI before returning, via
a new `send_master_eoi_command()` in `machdep/i386/intr_inline.h` that writes
OCW2 to the master port alone. See the comment in `intr_dispatch()`.

A rate-limited `printf` (first 8 occurrences) reports each phantom interrupt and
which IRQ it was, so the path is observable rather than silent. It reaches the
serial console via the i386 kernel console added alongside this work.

## Why it stayed hidden

Spurious slave interrupts are rare on real hardware, and the window that
produces them is timing-dependent. A machine could run for years without
hitting it. QEMU's timing makes it reproducible within a minute or two of boot.

## Related, not yet changed

`send_eoi_command()` writes EOI to the master **before** the slave. The
conventional order is slave-then-master. The reversed order leaves a window in
which the slave can re-raise the cascade after the master has been EOI'd but
before the slave has, which is a plausible way to manufacture the very spurious
slave interrupt described above.

This was deliberately left alone so the effect of the root-cause fix could be
measured on its own. If spurious IRQ 15 reports continue to appear frequently
after the fix, reversing the order is the next thing to try.
