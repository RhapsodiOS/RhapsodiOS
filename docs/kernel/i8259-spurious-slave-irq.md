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

## Related, not changed

`send_eoi_command()` writes EOI to the master **before** the slave, where the
conventional order is slave-then-master. This was initially suspected of
manufacturing the spurious slave interrupts described above, and was left alone
so the effect of the fix could be measured on its own.

Part 2 below measures it and **disproves that suspicion** — the spurious
interrupts are preceded by the timer, not by the completion of a slave
interrupt. The ordering remains unchanged and is not believed to be implicated.

---

# Part 2: where the spurious IRQ 15s come from

Part 1 made spurious slave interrupts *harmless*. This part addresses why they
happen at all.

## Measurement

With the Part 1 fix in place the guest boots, so the rate can be measured
directly. Booting under `-d int` and counting delivered vectors (slave
`irq_base` is 0x48, so IRQ 14 is 0x4E and IRQ 15 is 0x4F) over one boot to the
desktop:

| vector | count | |
|---|---|---|
| 0x40 | 28,514 | IRQ 0, timer |
| 0x4E | 4,197 | IRQ 14, disk |
| **0x4F** | **227** | **IRQ 15, spurious** |

227 spurious against 4,197 real disk interrupts — a **5.4%** rate.

## The generator

The ordering is unambiguous. Of the 227 spurious interrupts:

- **100%** are immediately preceded by vector 0x40, the timer.
- **96%** are immediately followed by 0x4E, the real disk interrupt.
- None occur consecutively.

So the sequence is always *disk asserts → timer preempts → spurious IRQ 15 →
real disk interrupt*.

That identifies the mechanism as mask-on-the-fly, not anything about EOI. When
the disk asserts, the slave raises INT and the master latches a cascade request
in IRR bit 2. If the clock — higher priority, on the master — preempts before
that cascade is acknowledged, `intr_dispatch()` calls `set_masked_ipl()` for the
clock's IPL, and `set_irq_mask()` rewrites **both** PICs' mask registers,
masking IRQ 14 in the slave. The master's latched cascade request is still
outstanding. When it is finally acknowledged, the slave has nothing unmasked to
report and answers with its IRQ 7 vector, which arrives as IRQ 15.

An earlier hypothesis blamed the EOI ordering in `send_eoi_command()`
(master-before-slave, where convention is slave-first). **The measurement
disproves it** — the spurious interrupts are preceded by the timer, not by the
completion of a slave interrupt. That ordering is left unchanged.

## Fix

`set_irq_mask()` now masks the master's IR2 across the update:

    master IMR |= cascade bit     -- hold off cascade acknowledgement
    slave  IMR  = new value
    master IMR  = new value       -- release

The cascade request stays latched in the master's IRR throughout, so no
interrupt is lost; only its acknowledgement is deferred until the slave's mask
is consistent. Cost is one extra `outb` per mask change.

## Result: partial, and the hypothesis was incomplete

Measured after the change, on a comparably-loaded boot (4,200 disk interrupts
against the baseline's 4,197):

| | baseline | with IR2 bracketing |
|---|---|---|
| IRQ 14 (disk) | 4,197 | 4,200 |
| IRQ 15 (spurious) | **227** | **190** |
| rate | 5.4% | 4.5% |

A reduction, but nowhere near elimination — and this is one run against one
run, with no variance data, so the drop should be read as suggestive rather
than established.

All 190 remaining are still immediately preceded by the timer, so the
mechanism is unchanged. The fix addressed the wrong window. Bracketing the
mask *write* only closes a few microseconds; the real exposure is the whole
time the slave IRQ stays masked:

1. Disk asserts; the master latches the cascade in IRR2.
2. The clock preempts and raises the IPL, masking IRQ 14 in the slave.
3. The clock handler finishes and EOIs, clearing the master's ISR bit 0.
4. The master now delivers the still-latched cascade — but IRQ 14 remains
   masked, because the IPL is not lowered until the handler returns.
5. The slave has nothing unmasked to report and answers with IRQ 7.

Closing that properly would mean holding IR2 masked for the entire elevated-IPL
window, which is not acceptable: masking IR2 blocks *every* slave interrupt,
including higher-IPL ones that should still be delivered. It would trade a
benign spurious interrupt for broken interrupt priority.

The remaining options are to restructure mask-on-the-fly entirely — the
`set_masked_ipl()` call in `intr_dispatch()` exists so level-triggered inputs
work, so it cannot simply be dropped — or to accept the spurious interrupts.
They are correctly handled by the Part 1 fix and cost one cheap trap each, so
accepting them is the reasonable engineering answer at roughly 4.5% of disk
interrupts.

The IR2 bracketing is kept: it is correct, costs one `outb` per mask change,
and narrows a genuine race. It is simply not sufficient on its own.

## Verifying

Re-run the measurement and compare against the 227 baseline:

```bash
cd vm && python pic-probe.py     # or a -d int boot, counting 0x4F
```

The Part 1 `printf` is a cheap proxy: it reports the first eight phantom
interrupts, so a boot that no longer prints eight of them has improved. The
counter `intr_cnt.phantom` holds the true total.

If the rate does not fall, this hypothesis is wrong too, and the next candidate
is the mask-before-acknowledge sequence in `intr_dispatch()` itself — which
exists to make level-triggered inputs work and so cannot simply be removed.
