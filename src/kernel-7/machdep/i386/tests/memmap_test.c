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

	assert(memmap_contiguous_top(q, 6) == 0x7fe0000);
	assert(memmap_contiguous_top(u, 2) == 0x800000);
	assert(memmap_contiguous_top(h, 3) == 0xf00000);
	assert(memmap_contiguous_top(n, 1) == 0x100000);
	assert(memmap_contiguous_top(q, 0) == 0x100000);
	assert(memmap_count(-5) == 0 && memmap_count(7) == 7 && memmap_count(1000) == BOOT_MEMMAP_MAX);
	assert(memmap_end_of_memory(0x7fe0000, 0, 0x8000000) == 0x7fe0000);
	assert(memmap_end_of_memory(0x7fe0000, 0x10000000, 0) == 0x7fe0000);	/* maxmem cannot raise */
	assert(memmap_end_of_memory(0x7fe0000, 0x4000000, 0) == 0x4000000);	/* maxmem can lower */
	assert(memmap_end_of_memory(0x100000, 0, 0x7f00000) == 0x7f00000);	/* no usable map: extmem */
	assert(memmap_end_of_memory(0x100000, 0x4000000, 0x7f00000) == 0x4000000);
	printf("memmap_test: ok\n");
	return 0;
}
