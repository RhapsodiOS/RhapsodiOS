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

## How Linux and the BSDs handle this

Before changing anything further, the reference implementations were read.

**Linux** (`arch/x86/kernel/i8259.c`, `mask_and_ack_8259A`) masks the IRQ in the
PIC on *every* interrupt entry, exactly as this kernel does, and its comment
says that is mandatory:

> Careful! The 8259A is a fragile beast, it pretty much _has_ to be done
> exactly like this (mask it first, _then_ send the EOI...)

So mask-on-the-fly is not the defect. Linux acknowledges with **specific** EOI,
and for a slave IRQ sends two of them — the slave, then the master's cascade
input:

```c
outb(0x60+(irq&7), PIC_SLAVE_CMD);         /* specific EOI to slave  */
outb(0x60+PIC_CASCADE_IR, PIC_MASTER_CMD); /* specific EOI to master */
```

When it detects a spurious interrupt it does **not** return early — it jumps to
`handle_real_irq` and sends the same EOI pair anyway:

> Theoretically we do not have to handle this IRQ, but in Linux this does not
> cause problems and is simpler for us.

**NetBSD** (`sys/arch/x86/include/i8259.h`) does the same thing, and its comment
is explicit about the order:

```
#define	i8259_asm_ack2(num) 	movb	$(0x60|(num%8)),%al	/* specific EOI */		;	outb	%al,$IO_ICU2		/* do the second ICU first */	;	movb	$(0x60|IRQ_SLAVE),%al	/* specific EOI for IRQ2 */	;	outb	%al,$IO_ICU1
```

**FreeBSD** (`sys/x86/isa/atpic.c`) takes a different approach: it does not mask
on every entry, masking only level-triggered sources when a source is disabled,
and uses non-specific EOI. `AUTO_EOI_1`/`AUTO_EOI_2` are not defined by default.

The consensus of the two implementations whose design matches this kernel's is
therefore: **mask on entry, acknowledge with specific EOI, slave before master,
and acknowledge spurious interrupts rather than dropping them.**

## What this kernel was doing

`send_eoi()` took no argument. It sent a **non-specific** EOI to **both** PICs,
unconditionally, regardless of which PIC the interrupt came from:

```c
    outb(INTR_PRIMARY_PORT, tconv.iodata);
    outb(INTR2_PRIMARY_PORT, tconv.iodata);
```

That is wrong in two independent ways.

A non-specific EOI clears whichever in-service bit currently has the highest
priority, which is not necessarily the interrupt being finished once interrupts
nest. And because it was sent to both PICs, **finishing an interrupt on the
master also cleared an unrelated slave interrupt that was still in service** —
so every clock tick that preempted a pending disk interrupt would clear the
slave's in-service bit for it.

That is a correctness bug in its own right, independent of any spurious-interrupt
counting, and it is a strong candidate for the remaining 190: prematurely
clearing the slave's in-service bit lets the slave re-raise INT for an interrupt
that is still being handled, producing exactly the extra cascade requests that
turn into spurious IRQ 15 when the input is masked.

## Fix

`send_eoi()` now takes the IRQ and acknowledges the way Linux and NetBSD do:

```c
    if (irq >= INTR_NIRQ / 2) {
	send_slave_eoi_command(specific_eoi(irq - INTR_NIRQ / 2));
	send_master_eoi_command(specific_eoi(INTR_SLAVE_IRQ));
    }
    else
	send_master_eoi_command(specific_eoi(irq));
```

`send_eoi_command()`, which wrote to both PICs, is gone; `send_master_eoi_command()`
and `send_slave_eoi_command()` replace it. The spurious-slave path from Part 1 now
sends a specific cascade EOI rather than a non-specific one.

**The IR2 bracketing described earlier has been reverted.** It was justified by a
hypothesis the measurement showed to be incomplete, neither reference
implementation does anything like it, and keeping a speculative mitigation
alongside a principled fix would make the next measurement impossible to
attribute.

## Result: the metric could not resolve any of these changes

Measured after the change, then repeated twice more on the *same* build and the
same image to establish a noise floor:

| configuration | spurious / disk | rate |
|---|---|---|
| non-specific EOI to both PICs (original) | 227 / 4,197 | 5.4% |
| + IR2 mask bracketing | 190 / 4,200 | 4.5% |
| specific EOI, slave-then-master | 257 / 4,193 | 6.1% |
| *same build, run 2* | 209 / 4,201 | 5.0% |
| *same build, run 3* | 228 / 4,208 | 5.4% |

The identical configuration produces **209, 228 and 257** — a spread of 48,
roughly 23% of the mean. Every figure in the table sits inside that band.

**No change measured in this investigation had a demonstrable effect on the
spurious interrupt rate.** The earlier claim that IR2 bracketing reduced it from
227 to 190 was reading noise; so was the apparent regression to 257. Single-run
comparisons of a timing-dependent race were never capable of resolving
differences of this size, and should not have been presented as results.

The rate is roughly 5% of disk interrupts across every configuration tried.

## Conclusion: the spurious interrupts are inherent, and that is fine

This matches what the reference implementations imply. Masking on every
interrupt entry is required for correct 8259 behaviour — Linux says so
explicitly — and masking a slave input while the master holds a latched cascade
request is what produces the spurious vector. The two cannot be separated
without abandoning mask-on-the-fly, which exists so level-triggered inputs work.

Linux's answer is simply to acknowledge spurious interrupts and carry on, which
is what this kernel now does after Part 1. Each one costs a trap, a register
read and two `outb`s. At ~5% of disk interrupts that is not worth further
surgery.

**The specific-EOI change is kept**, but on correctness grounds rather than
because it moved this number: sending a non-specific EOI to both PICs could
clear an in-service bit belonging to an unrelated interrupt, which is a real
defect independent of spurious accounting, and specific-EOI-per-PIC is what both
Linux and NetBSD do.

## If this is revisited

Any future attempt needs a better metric than a single boot. Either run each
configuration five or more times and compare distributions rather than single
values, or instrument `intr_cnt.phantom` directly against a fixed, deterministic
disk workload instead of a full desktop boot, whose I/O pattern varies between
runs.
