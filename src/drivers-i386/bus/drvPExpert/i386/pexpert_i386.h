/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * pexpert_i386.h
 * The i386 platform expert's contract with the kernel and the bus drivers.
 *
 * Owned and installed by drivers-i386/bus/drvPExpert (into
 * System.framework/Headers/pexpert); the kernel's machdep/i386/intr.c and
 * the PCI bus consume it.
 */

#ifndef _PEXPERT_PEXPERT_I386_H_
#define _PEXPERT_PEXPERT_I386_H_

/*
 * Interrupt numbering.  The kernel dispatches on 64 irqs, one per IDT
 * vector 0x40-0x7F.  Under the 8259s only 0-15 exist.  Under the APICs
 * irq 0-15 are the ISA lines (through the MADT's overrides), 16-47 are
 * the remaining I/O APIC inputs by global system interrupt number, 48-62
 * are message signalled interrupts, and 63 is the local APIC's spurious
 * vector.
 */
#define PEXPERT_NIRQ		64
#define PEXPERT_VECTOR_BASE	0x40
#define PEXPERT_VECTOR(irq)	(PEXPERT_VECTOR_BASE + (irq))
#define PEXPERT_GSI_IRQS	48
#define PEXPERT_MSI_IRQ_BASE	48
#define PEXPERT_MSI_IRQS	15
#define PEXPERT_SPURIOUS_IRQ	63

typedef unsigned long long pexpert_irq_mask_t;

/*
 * The interrupt controller the kernel's intr.c drives.  intr.c keeps the
 * dispatch table, the ipl masks and the deferral logic; the controller
 * only touches hardware.  Every entry is called with interrupts disabled.
 *
 *   irq_valid	 whether irq can be registered on this controller
 *   set_mask	 make exactly the irqs whose bit is set masked
 *   eoi	 acknowledge irq, sent before its handler runs
 *   is_spurious the controller reported irq but nothing is behind it;
 *		 a TRUE return drops the interrupt (the controller has
 *		 done whatever acknowledgement that needs)
 *   set_trigger irq is level (TRUE) or edge (FALSE) triggered
 */
typedef struct intr_controller {
    const char	*name;
    int		(*irq_valid)(int irq);
    void	(*set_mask)(pexpert_irq_mask_t masked);
    void	(*eoi)(int irq);
    int		(*is_spurious)(int irq);
    int		(*set_trigger)(int irq, int level);
} intr_controller_t;

/* In the kernel (machdep/i386/intr.c). */
void intr_set_controller(const intr_controller_t *controller);

/*
 * What discovery found.  Addresses are physical; 0 means absent.
 */
#define PEXPERT_MAX_IOAPICS		4
#define PEXPERT_MAX_ISA_OVERRIDES	16

typedef struct {
    unsigned char	id;
    unsigned int	address;
    unsigned int	gsi_base;
    unsigned int	pins;		/* filled in when the chip is read */
} pexpert_ioapic_t;

typedef struct {
    unsigned char	isa_irq;
    unsigned int	gsi;
    unsigned short	flags;		/* MPS INTI flags: polarity, trigger */
} pexpert_iso_t;

typedef struct i386_firmware_info {
    unsigned int	rsdp;
    unsigned int	acpi_revision;
    unsigned int	madt, fadt, hpet, mcfg;
    unsigned int	lapic_address;
    unsigned int	madt_flags;	/* bit 0: PC-AT compatible 8259s */
    int			cpu_count;
    int			ioapic_count;
    pexpert_ioapic_t	ioapics[PEXPERT_MAX_IOAPICS];
    int			iso_count;
    pexpert_iso_t	isos[PEXPERT_MAX_ISA_OVERRIDES];
    unsigned int	mp_fps;		/* MP floating pointer structure */
    unsigned int	mp_config;	/* MP configuration table */
    int			imcr_present;
    unsigned int	ecam_base;	/* MCFG segment 0 */
    int			ecam_start_bus, ecam_end_bus;
} i386_firmware_info_t;

extern i386_firmware_info_t	i386_firmware_info;

/*
 * Called by the kernel once, after the kernel map is usable and before
 * any driver is probed.  Runs discovery and, when asked to (apic=1 on
 * the boot line) and able to, moves interrupt delivery to the APICs.
 */
void pexpert_init(void);
int pexpert_apic_mode(void);

/*
 * A permanent, uncached kernel mapping of len bytes at physical pa, or
 * 0 when the kernel map has no room.
 */
void *pexpert_map_physical(unsigned int pa, unsigned int len);

/*
 * PCI configuration space, through MCFG's memory-mapped space when there
 * is one and the offset needs it, otherwise mechanism #1.  size is 1, 2
 * or 4.  Both return 0 on success.
 */
int pexpert_pci_config_read(int bus, int dev, int fn, int off, int size,
			    unsigned int *val);
int pexpert_pci_config_write(int bus, int dev, int fn, int off, int size,
			     unsigned int val);

/*
 * The irq a PCI function's INTA-INTD (pin 1-4) reaches the CPU on in
 * APIC mode, from the MP table's routing entries; -1 when unknown.
 */
int pexpert_pci_intx_irq(int bus, int dev, int pin);

/*
 * Give a PCI function a message signalled interrupt (MSI-X when the
 * function has it, else MSI), routed to the boot processor.  Returns the
 * irq the function now raises, or -1.  Only in APIC mode.
 */
int pexpert_msi_enable(int bus, int dev, int fn);
int pexpert_msi_disable(int bus, int dev, int fn);

#endif /* _PEXPERT_PEXPERT_I386_H_ */
