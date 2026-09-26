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
 * pexpert.c
 * i386 platform expert: discovery, and the switch to APIC delivery.
 *
 * pexpert_init() runs once the kernel map is usable and before any driver
 * is probed.  It reads the ACPI static tables and the MP table, publishes
 * what it found in i386_firmware_info, hands the PCI configuration
 * accessors an MCFG space when there is one, and, if the boot line says
 * apic=1, moves interrupt delivery from the 8259s to the APICs.  APIC
 * mode is opt-in until it has been boot-tested; the 8259 path is the one
 * every existing driver has run on.
 */

#include "pexpert_i386.h"
#include "acpi.h"
#include "mptable.h"
#include "msi.h"
#include "chips/pcicfg.h"

extern int printf(const char *format, ...);

/* Boot line: apic=1 turns APIC mode on, rsdp=0x... names the RSDP. */
extern int	pexpert_apic;
extern int	pexpert_rsdp;

/* apic_intr.c */
int apic_intr_enable(const i386_firmware_info_t *info);

i386_firmware_info_t	i386_firmware_info;

/*
 * The kernel map and pmap, and the two calls
 * driverkit/KernBusMemory.m maps device memory with.  Declared here
 * rather than through <vm/...>, which the installed headers this project
 * builds against do not carry; the shapes are those of vm/vm_map.h and
 * machdep/i386/pmap.h.
 */
struct vm_map;
struct pmap;
extern struct vm_map	*kernel_map;
extern struct pmap	*kernel_pmap;
extern int vm_map_find(struct vm_map *map, void *object, unsigned int offset,
		       unsigned int *address, unsigned int size, int anywhere);
extern void pmap_enter_cache_spec(struct pmap *pmap, unsigned int va,
				  unsigned int pa, int prot, int wired,
				  int caching);

#define PAGE_SIZE_I386		4096
#define VM_PROT_READ_WRITE	3
#define CACHE_DISABLE		2	/* cache_spec_t cache_disable */

void *
pexpert_map_physical(unsigned int pa, unsigned int len)
{
    unsigned int	first, last, va, off, size;

    first = pa & ~(PAGE_SIZE_I386 - 1);
    last = (pa + len - 1) & ~(PAGE_SIZE_I386 - 1);
    size = last - first + PAGE_SIZE_I386;

    va = 0;
    if (vm_map_find(kernel_map, 0, 0, &va, size, 1) != 0)
	return (0);

    for (off = 0; off < size; off += PAGE_SIZE_I386)
	pmap_enter_cache_spec(kernel_pmap, va + off, first + off,
			      VM_PROT_READ_WRITE, 1, CACHE_DISABLE);

    return ((void *)(va + (pa - first)));
}

int
pexpert_pci_config_read(int bus, int dev, int fn, int off, int size,
			unsigned int *val)
{
    return (pcicfg_read(bus, dev, fn, off, size, val));
}

int
pexpert_pci_config_write(int bus, int dev, int fn, int off, int size,
			 unsigned int val)
{
    return (pcicfg_write(bus, dev, fn, off, size, val));
}

int
pexpert_msi_enable(int bus, int dev, int fn)
{
    return (msi_enable(bus, dev, fn));
}

int
pexpert_msi_disable(int bus, int dev, int fn)
{
    return (msi_disable(bus, dev, fn));
}

static void
report(const i386_firmware_info_t *info)
{
    int		i;

    if (info->rsdp == 0) {
	printf("pexpert: no ACPI tables\n");
    } else {
	printf("pexpert: ACPI %d.0 RSDP at %x:", info->acpi_revision >= 2 ? 2 : 1,
	       info->rsdp);
	if (info->madt) printf(" MADT");
	if (info->fadt) printf(" FADT");
	if (info->hpet) printf(" HPET");
	if (info->mcfg) printf(" MCFG");
	printf("\n");
    }
    if (info->madt) {
	printf("pexpert: %d processor%s, local APIC at %x, %d I/O APIC%s",
	       info->cpu_count, info->cpu_count == 1 ? "" : "s",
	       info->lapic_address, info->ioapic_count,
	       info->ioapic_count == 1 ? "" : "s");
	for (i = 0; i < info->ioapic_count; i++)
	    printf(", id %d at %x gsi %d", info->ioapics[i].id,
		   info->ioapics[i].address, info->ioapics[i].gsi_base);
	printf("\n");
	for (i = 0; i < info->iso_count; i++)
	    printf("pexpert: ISA irq %d is gsi %d (flags %x)\n",
		   info->isos[i].isa_irq, info->isos[i].gsi, info->isos[i].flags);
    }
    if (info->mcfg)
	printf("pexpert: PCI memory-mapped config at %x, buses %d-%d\n",
	       info->ecam_base, info->ecam_start_bus, info->ecam_end_bus);
    if (info->mp_fps)
	printf("pexpert: MP table at %x%s%s\n", info->mp_fps,
	       info->mp_config ? ", configuration table" : ", default configuration",
	       info->imcr_present ? ", IMCR" : "");
}

void
pexpert_init(void)
{
    i386_firmware_info_t	*info = &i386_firmware_info;
    static int		done;

    if (done)
	return;
    done = 1;

    (void) acpi_discover((unsigned int)pexpert_rsdp, info);
    (void) mptable_discover(info);

    if (info->ecam_base != 0) {
	unsigned int	buses = info->ecam_end_bus - info->ecam_start_bus + 1;
	void		*ecam;

	ecam = pexpert_map_physical(info->ecam_base, buses << 20);
	if (ecam != 0)
	    pcicfg_set_ecam((volatile unsigned char *)ecam,
			    info->ecam_start_bus, info->ecam_end_bus);
	else
	    printf("pexpert: cannot map the PCI memory-mapped config space\n");
    }

    report(info);

    if (pexpert_apic)
	(void) apic_intr_enable(info);
}
