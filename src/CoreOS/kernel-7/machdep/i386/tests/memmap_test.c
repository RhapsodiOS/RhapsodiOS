#include <assert.h>
#include <stdio.h>
#include "../memmap.h"

int
main(void)
{
	/* QEMU 128 MB: low RAM, reserved BIOS, RAM 1MB..0x7fe0000, ACPI above */
	boot_mem_range_t q[] = {{0,0x9fc00,1},{0x9fc00,0xa0000,2},{0xf0000,0x100000,2},
				{0x100000,0x7fe0000,1},{0x7fe0000,0x8000000,2},{0xfffc0000,0xfffff000,2}};
	/* unsorted, split RAM that touches exactly */
	boot_mem_range_t u[] = {{0x400000,0x800000,1},{0x100000,0x400000,1}};
	/* ISA hole at 15 MB stops the run */
	boot_mem_range_t h[] = {{0x100000,0xf00000,1},{0xf00000,0x1000000,2},{0x1000000,0x4000000,1}};
	/* nothing adjoins 1 MB */
	boot_mem_range_t n[] = {{0x200000,0x800000,1}};

	/* a reserved or ACPI range overlapping the RAM run cuts it */
	boot_mem_range_t o1[] = {{0x100000,0x8000000,1},{0x7fe0000,0x8000000,2}};
	boot_mem_range_t o2[] = {{0x100000,0x8000000,1},{0x4000000,0x4010000,3}};
	boot_mem_range_t o3[] = {{0x100000,0x8000000,1},{0x9000000,0xa000000,2}};
	boot_mem_range_t o4[] = {{0x100000,0x8000000,1},{0xf0000,0x100000,2}};
	boot_mem_range_t o5[] = {{0x100000,0x8000000,1},{0xf0000,0x200000,2}};

	assert(memmap_contiguous_top(q, 6) == 0x7fe0000);
	assert(memmap_contiguous_top(u, 2) == 0x800000);
	assert(memmap_contiguous_top(h, 3) == 0xf00000);
	assert(memmap_contiguous_top(n, 1) == 0x100000);
	assert(memmap_contiguous_top(q, 0) == 0x100000);
	assert(memmap_contiguous_top(o1, 2) == 0x7fe0000);
	assert(memmap_contiguous_top(o2, 2) == 0x4000000);
	assert(memmap_contiguous_top(o3, 2) == 0x8000000);
	assert(memmap_contiguous_top(o4, 2) == 0x8000000);
	assert(memmap_contiguous_top(o5, 2) == 0x100000);
	assert(memmap_count(-5) == 0 && memmap_count(7) == 7 && memmap_count(1000) == BOOT_MEMMAP_MAX);
	assert(memmap_end_of_memory(0x7fe0000, 0, 0x8000000) == 0x7fe0000);
	assert(memmap_end_of_memory(0x7fe0000, 0x10000000, 0) == 0x7fe0000);	/* maxmem cannot raise */
	assert(memmap_end_of_memory(0x7fe0000, 0x4000000, 0) == 0x4000000);	/* maxmem can lower */
	assert(memmap_end_of_memory(0x100000, 0, 0x7f00000) == 0x7f00000);	/* no usable map: extmem */
	assert(memmap_end_of_memory(0x100000, 0x4000000, 0x7f00000) == 0x4000000);

	/* memory and the kernel reserve above it must fit a 1GB window (8KB pages) */
	assert(memmap_clamp(0x2ffe0000, 0x40000000, 8192) == 0x2ffe0000);	/* QEMU 768 MB fits */
	assert(memmap_clamp(0x7fe0000, 0x40000000, 8192) == 0x7fe0000);
	assert(memmap_clamp(0x80000000, 0x40000000, 8192) == 0x33000000);	/* 2 GB -> 816 MB */
	assert(memmap_clamp(0x7ffe0000, 0x40000000, 8192) == 0x33000000);
	assert(memmap_clamp(0xbffe0000, 0x40000000, 8192) == 0x33000000);	/* 3 GB top -> 816 MB */
	assert(memmap_clamp(0xfffff000, 0x40000000, 8192) == 0x33000000);	/* saturated -> same */
	assert(memmap_clamp(0x80000000, 0x40000000 - 0x1000000, 8192) == 0x32000000);	/* 16 MB frame buffer */
	assert(memmap_clamp(0x80000000, 0x2000000, 8192) == 0);	/* nothing fits */
	assert(memmap_clamp(0, 0x40000000, 8192) == 0);
	printf("memmap_test: ok\n");
	return 0;
}
