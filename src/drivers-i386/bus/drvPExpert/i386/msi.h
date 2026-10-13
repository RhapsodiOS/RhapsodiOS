/*
 * msi.h
 * Message signalled interrupts for PCI functions.
 */

#ifndef _PEXPERT_MSI_H_
#define _PEXPERT_MSI_H_

/* Where messages go: the boot processor's local APIC id. */
void msi_init(unsigned char dest_apic_id);

/*
 * Give a function a single vector, MSI-X first, then MSI.  Returns the
 * irq (PEXPERT_MSI_IRQ_BASE ..) or -1 when the function has neither
 * capability or the pool is empty.
 */
int msi_enable(int bus, int dev, int fn);
int msi_disable(int bus, int dev, int fn);

/* Whether irq is a live message signalled interrupt. */
int msi_irq_active(int irq);

/*
 * Mask a message signalled irq at the function.  A plain MSI function
 * without per-vector masking cannot be masked; that is fine, its
 * interrupts are edge triggered and the kernel defers them in software.
 */
void msi_set_masked(int irq, int masked);

#endif /* _PEXPERT_MSI_H_ */
