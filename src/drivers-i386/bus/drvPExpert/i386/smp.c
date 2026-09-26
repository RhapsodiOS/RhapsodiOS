/*
 * smp.c
 * Starting the other processors (Intel MP spec B.4, SDM vol. 3 8.4.4).
 *
 * Each application processor gets an INIT IPI, then a start-up IPI that
 * points it at a page of conventional memory holding smp_tramp.s.  The
 * trampoline brings it to protected mode with the kernel's page
 * directory, GDT and IDT and calls smp_ap_main() on a stack of its own.
 *
 * That is as far as this goes.  The kernel is built for one processor
 * (no `cpus` line in MASTER.i386), takes no locks around its scheduler
 * or its interrupt paths, and would not survive a second processor
 * running them.  So a started processor enables its local APIC, reports
 * in, and halts with interrupts off, where an INIT IPI can still reach it.
 * Scheduling on it is the kernel's project, not the platform expert's.
 */

#include "smp.h"
#include "chips/lapic.h"

#include <string.h>

extern int printf(const char *format, ...);
extern void IODelay(unsigned int microseconds);
extern unsigned int alloc_cnvmem(unsigned int size, unsigned int align);

/* The kernel's descriptor tables and page directory. */
extern unsigned int	gdt_base;
extern unsigned short	gdt_limit;
extern unsigned int	idt_base;
extern unsigned short	idt_limit;
struct pmap_head { void *root; unsigned int cr3; };
extern struct pmap_head	*kernel_pmap;

/* smp_tramp.s */
extern char		smp_tramp_start[], smp_tramp_end[];
extern unsigned int	smp_tramp_ljmp;
extern unsigned int	smp_tramp_entry32;
extern unsigned int	smp_tramp_reload;

/* Parameter block at the end of the trampoline page. */
#define SMP_TRAMP_CR3		0x0F00
#define SMP_TRAMP_GDT		0x0F10	/* limit, base */
#define SMP_TRAMP_IDT		0x0F18
#define SMP_TRAMP_STACK		0x0F20
#define SMP_TRAMP_INDEX		0x0F24
#define SMP_TRAMP_ENTRY		0x0F28
#define SMP_TRAMP_FARPTR	0x0F30	/* offset, selector */
#define SMP_TRAMP_TMPGDTR	0x0F40	/* limit, base */
#define SMP_TRAMP_TMPGDT	0x0F50	/* null, code, data */

#define AP_STACK_SIZE		4096

static unsigned char	ap_stacks[PEXPERT_MAX_CPUS][AP_STACK_SIZE];
static volatile int	cpu_online[PEXPERT_MAX_CPUS];
static int		cpus_online = 1;	/* the boot processor */
static int		cpu_total = 1;
static unsigned char	ap_spurious_vector;

int
pexpert_cpu_count(void)
{
    return (cpu_total);
}

int
pexpert_cpus_online(void)
{
    return (cpus_online);
}

/*
 * A started processor lands here on its own stack, protected and paged,
 * interrupts off.  It never returns and never enables interrupts.
 */
void
smp_ap_main(int index)
{
    lapic_init_secondary(ap_spurious_vector);
    cpu_online[index] = 1;

    for (;;)
	asm volatile("hlt");
}

static void
build_trampoline(unsigned char *page, int index)
{
    unsigned int	base = (unsigned int)page;
    unsigned int	*p32;
    unsigned short	*p16;

    memcpy(page, smp_tramp_start, smp_tramp_end - smp_tramp_start);

    /* The real-mode far jump into the 32-bit part. */
    *(unsigned int *)(page + ((char *)&smp_tramp_ljmp - smp_tramp_start)) =
	base + smp_tramp_entry32;

    /* Temporary GDT: flat 4 GB code at 0x08 and data at 0x10. */
    p32 = (unsigned int *)(page + SMP_TRAMP_TMPGDT);
    p32[0] = 0; p32[1] = 0;
    p32[2] = 0x0000FFFF; p32[3] = 0x00CF9A00;
    p32[4] = 0x0000FFFF; p32[5] = 0x00CF9200;
    p16 = (unsigned short *)(page + SMP_TRAMP_TMPGDTR);
    p16[0] = 3 * 8 - 1;
    *(unsigned int *)(page + SMP_TRAMP_TMPGDTR + 2) = base + SMP_TRAMP_TMPGDT;

    /* The kernel's tables, page directory, stack, index and entry. */
    *(unsigned int *)(page + SMP_TRAMP_CR3) = kernel_pmap->cr3;
    p16 = (unsigned short *)(page + SMP_TRAMP_GDT);
    p16[0] = gdt_limit;
    *(unsigned int *)(page + SMP_TRAMP_GDT + 2) = gdt_base;
    p16 = (unsigned short *)(page + SMP_TRAMP_IDT);
    p16[0] = idt_limit;
    *(unsigned int *)(page + SMP_TRAMP_IDT + 2) = idt_base;
    *(unsigned int *)(page + SMP_TRAMP_STACK) =
	(unsigned int)&ap_stacks[index][AP_STACK_SIZE - 16];
    *(unsigned int *)(page + SMP_TRAMP_INDEX) = index;
    *(unsigned int *)(page + SMP_TRAMP_ENTRY) = (unsigned int)smp_ap_main;
    *(unsigned int *)(page + SMP_TRAMP_FARPTR) = base + smp_tramp_reload;
    *(unsigned short *)(page + SMP_TRAMP_FARPTR + 4) = 0x08;
}

static int
start_one(unsigned char *page, unsigned char apic_id, int index)
{
    unsigned int	vector = (unsigned int)page >> 12;
    int			i;

    build_trampoline(page, index);

    lapic_send_ipi(apic_id, LAPIC_IPI_INIT | LAPIC_IPI_ASSERT | LAPIC_IPI_LEVEL);
    IODelay(10000);

    for (i = 0; i < 2; i++) {
	lapic_send_ipi(apic_id, LAPIC_IPI_STARTUP | (vector & 0xFF));
	IODelay(200);
    }

    for (i = 0; i < 1000 && !cpu_online[index]; i++)
	IODelay(100);
    return (cpu_online[index]);
}

int
smp_start(const i386_firmware_info_t *info, unsigned char boot_apic_id,
	  unsigned char spurious_vector)
{
    unsigned char	*page;
    int			i, index, count;

    count = info->cpu_count < PEXPERT_MAX_CPUS ? info->cpu_count : PEXPERT_MAX_CPUS;
    cpu_total = info->cpu_count;
    if (count <= 1)
	return (0);

    /*
     * The start-up vector names a page below 1 MB; the conventional
     * memory allocator hands out exactly that, and the first megabyte is
     * mapped at its own address so the page can be written here.
     */
    page = (unsigned char *)alloc_cnvmem(4096, 4096);
    if (page == 0 || (unsigned int)page >= 0x100000) {
	printf("smp: no conventional memory for the start-up page\n");
	return (0);
    }
    ap_spurious_vector = spurious_vector;

    index = 1;
    for (i = 0; i < count; i++) {
	if (info->lapic_ids[i] == boot_apic_id)
	    continue;
	if (start_one(page, info->lapic_ids[i], index)) {
	    printf("smp: processor %d (local APIC %d) up and parked\n",
		   index, info->lapic_ids[i]);
	    cpus_online++;
	} else
	    printf("smp: processor with local APIC %d did not answer\n",
		   info->lapic_ids[i]);
	index++;
    }
    return (cpus_online - 1);
}
