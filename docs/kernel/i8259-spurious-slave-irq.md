# i386: a spurious slave interrupt permanently disables IRQ 8-15

## Symptom

Any device on the cascaded (slave) 8259 stops receiving interrupts at some point
during or after boot, while devices on the master PIC keep working. The device
itself is healthy and is still asserting its interrupt line; the interrupt is
simply never delivered to the CPU again.

It was found through the EIDE disk driver under QEMU, where it presents as:

```
hc0: interrupt timeout, cmd: 0xc4
hc0: ATA drive 0 is not present.
```

The defect is in the kernel's PIC handling, **not** in `drvEIDE`. Any slave IRQ
is affected — IRQ 14/15 (IDE), IRQ 12 (PS/2 mouse), IRQ 9/10/11 (typical PCI).
The driver-side investigation that led here is in
[`docs/drivers/drvEIDE-issues.md`](../drivers/drvEIDE-issues.md) §2.

## Evidence

QEMU's PIC state, sampled across 130 seconds of a wedged guest (`info pic` and
`info irq` over QMP):

| | t=20s | t=150s |
|---|---|---|
| IRQ 0 (timer) delivered | 1,438 | 14,426 |
| IRQ 2 (cascade) asserted | 562 | **13,434** |
| IRQ 14 (disk) delivered | **7** | **7** |

```
pic1: irr=40 imr=bf isr=00     <- slave: IRQ 14 requested, unmasked, not in service
pic0: irr=04 imr=fa isr=04     <- master: cascade IRQ 2 IN SERVICE
```

Identical at every sample:

- The slave has IRQ 14 pending (`irr` bit 6) and **not** masked (`imr=bf` clears
  bit 6), so nothing is suppressing the request.
- The slave raised the cascade to the master over 13,000 times.
- The master's in-service register has **bit 2 — the cascade — set and never
  cleared**.
- IRQ 14 delivery is frozen at 7.

An 8259 will not deliver an interrupt of equal or lower priority than one already
in service. With IRQ 2 stuck in service, every slave interrupt (IRQ 8-15) is
blocked indefinitely. IRQ 0 keeps running because it outranks IRQ 2 — which is
exactly why the timer survived while the disk died.

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

A spurious interrupt sets no in-service bit in the PIC that reported it, which is
how the check recognises one. But the master and slave cases are **not**
symmetric, and the original code treated them identically:

- **Spurious IRQ 7 (master).** Correct to return with no EOI — the master has
  nothing in service.
- **Spurious IRQ 15 (slave).** Incorrect. By the time the slave reports the
  interrupt as spurious, the master has *already* acknowledged the cascade and set
  its IRQ 2 in-service bit. That bit must be cleared with an EOI to the **master**
  (the slave has nothing to clear). Returning without one strands the cascade in
  service forever.

This is why the observed master ISR is exactly `0x04`: no other path in
`intr_dispatch()` produces that state.

## Why it stayed hidden

Spurious slave interrupts are rare on real hardware and the window that produces
them is timing-dependent, so a machine could run for years without hitting it.
QEMU's timing makes it reproducible within a minute or two of boot.

## The fix

Two changes, both in `machdep/i386/`.

**1. Acknowledge the cascade when a slave interrupt is spurious.** The phantom
check is split so the slave case sends a specific EOI to the master's cascade
input before returning:

```c
    if (irq == INTR_SLAVE_PHANTOM_IRQ &&
		(get_slave_isr() & INTR_PHANTOM_IRQ_MASK) == 0) {
	 intr_cnt.phantom++;
	 send_master_eoi_command(specific_eoi(INTR_SLAVE_IRQ));
	 return;
    }
```

The master case still returns without an EOI, which remains correct.

A rate-limited `printf` (first eight occurrences) reports each phantom interrupt
and its IRQ, so the path is observable rather than silent. It reaches the serial
console via the i386 kernel console added alongside this work.

**2. Acknowledge every interrupt with a specific EOI, addressed to the PIC that
raised it.** `send_eoi()` previously took no argument and sent a **non-specific**
EOI to **both** PICs, unconditionally:

```c
    outb(INTR_PRIMARY_PORT, tconv.iodata);
    outb(INTR2_PRIMARY_PORT, tconv.iodata);
```

That is wrong twice over. A non-specific EOI clears whichever in-service bit
currently has the highest priority, which is not necessarily the interrupt being
finished once interrupts nest. And because it went to both PICs, **finishing an
interrupt on the master also cleared an unrelated slave interrupt that was still
in service** — so any clock tick preempting a pending disk interrupt would clear
the slave's in-service bit for it.

It now takes the IRQ and does what Linux and NetBSD do:

```c
    if (irq >= INTR_NIRQ / 2) {
	send_slave_eoi_command(specific_eoi(irq - INTR_NIRQ / 2));
	send_master_eoi_command(specific_eoi(INTR_SLAVE_IRQ));
    }
    else
	send_master_eoi_command(specific_eoi(irq));
```

`send_eoi_command()`, which wrote to both PICs, is gone; `send_master_eoi_command()`
and `send_slave_eoi_command()` replace it.

This second change is justified on correctness grounds alone. It was *not*
measured to reduce the spurious interrupt rate — see below.

## How Linux and the BSDs handle this

The reference implementations were read before settling on the above.

**Linux** (`arch/x86/kernel/i8259.c`, `mask_and_ack_8259A`) masks the IRQ in the
PIC on *every* interrupt entry, exactly as this kernel does, and its comment says
that is mandatory:

> Careful! The 8259A is a fragile beast, it pretty much _has_ to be done exactly
> like this (mask it first, _then_ send the EOI...)

So mask-on-the-fly is not a defect. Linux acknowledges with **specific** EOI, and
for a slave IRQ sends two — the slave, then the master's cascade input:

```c
outb(0x60+(irq&7), PIC_SLAVE_CMD);         /* specific EOI to slave  */
outb(0x60+PIC_CASCADE_IR, PIC_MASTER_CMD); /* specific EOI to master */
```

On detecting a spurious interrupt it does **not** return early — it jumps to
`handle_real_irq` and sends the same EOI pair anyway:

> Theoretically we do not have to handle this IRQ, but in Linux this does not
> cause problems and is simpler for us.

**NetBSD** (`sys/arch/x86/include/i8259.h`) does the same, and is explicit about
the order:

```
#define	i8259_asm_ack2(num) \
	movb	$(0x60|(num%8)),%al	/* specific EOI */		;\
	outb	%al,$IO_ICU2		/* do the second ICU first */	;\
	movb	$(0x60|IRQ_SLAVE),%al	/* specific EOI for IRQ2 */	;\
	outb	%al,$IO_ICU1
```

**FreeBSD** (`sys/x86/isa/atpic.c`) takes a different approach and is not a useful
model here: it does not mask on every entry, masking only level-triggered sources
when a source is disabled, and uses non-specific EOI. `AUTO_EOI_1`/`AUTO_EOI_2`
are not defined by default.

This kernel deliberately differs from Linux in one respect: on a spurious slave
interrupt it EOIs only the master's cascade, where Linux also issues a specific
EOI to the slave. Both are safe — a specific EOI for a bit that is not set is a
no-op — and acknowledging only what was actually acknowledged is the smaller
change.

## Investigated and inconclusive: eliminating the spurious interrupts

The fix above makes spurious slave interrupts *harmless*. A separate effort to
stop them happening at all did not succeed, and the negative result is recorded
here so it is not repeated.

### Where they come from

With the guest booting, the rate can be measured. Counting delivered vectors
under `-d int` (slave `irq_base` is 0x48, so IRQ 14 is 0x4E and IRQ 15 is 0x4F)
over one boot to the desktop gave 227 spurious against 4,197 disk interrupts.
Of those 227:

- **100%** were immediately preceded by vector 0x40, the timer.
- **96%** were immediately followed by 0x4E, the real disk interrupt.
- None occurred consecutively.

So the sequence is always *disk asserts → timer preempts → spurious IRQ 15 → real
disk interrupt*. When the disk asserts, the slave raises INT and the master
latches a cascade request. If the clock — higher priority, on the master —
preempts before that cascade is acknowledged, `set_irq_mask()` rewrites both
PICs' masks, masking IRQ 14 in the slave. The master's latched request is still
outstanding; when it is finally acknowledged the slave has nothing unmasked to
report and answers with its IRQ 7 vector, arriving as IRQ 15.

### Why nothing was changed to prevent it

Two attempts were measured, and **the measurements turned out to be worthless**:

| configuration | spurious / disk | rate |
|---|---|---|
| non-specific EOI to both PICs (original) | 227 / 4,197 | 5.4% |
| + masking the master's IR2 across mask updates | 190 / 4,200 | 4.5% |
| specific EOI, slave-then-master | 257 / 4,193 | 6.1% |
| *same build as above, run 2* | 209 / 4,201 | 5.0% |
| *same build as above, run 3* | 228 / 4,208 | 5.4% |

An identical build produces **209, 228 and 257** — a spread of 48, roughly 23% of
the mean. Every figure in the table falls inside that band.

**No change had a demonstrable effect on the rate.** The apparent reduction from
227 to 190 was noise, as was the apparent regression to 257. Single-run
comparisons of a timing-dependent race could never resolve differences of this
size. The IR2 masking experiment was reverted: its only justification was a
difference that does not exist, and neither reference implementation does
anything like it.

The rate is roughly 5% of disk interrupts in every configuration tried.

### Conclusion

The spurious interrupts are inherent. Masking on every interrupt entry is
required for correct 8259 behaviour, and masking a slave input while the master
holds a latched cascade request is what produces the spurious vector; the two
cannot be separated without abandoning mask-on-the-fly, which exists so
level-triggered inputs work.

Linux's answer is to acknowledge them and carry on, which is what this kernel now
does. Each costs a trap, a register read and one `outb`. At ~5% of disk
interrupts that is not worth further surgery.

### If this is revisited

Use a better metric than a single boot: either run each configuration five or
more times and compare distributions rather than single values, or instrument
`intr_cnt.phantom` against a fixed, deterministic disk workload instead of a full
desktop boot, whose I/O pattern varies between runs.
