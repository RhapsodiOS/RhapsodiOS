/* Exercise the mapper with the i386 kernel's 8 KB VM pages. */
#include <stdio.h>
#include "../i386/pexpert.c"

unsigned int page_size = 8192;
struct vm_map *kernel_map;
struct pmap *kernel_pmap;
int pexpert_apic, pexpert_rsdp, pexpert_lapictimer, pexpert_smp, pexpert_acpi;
static unsigned int next_va = 0x20000000, reserved, calls, first_pa;
static int failures;

int vm_map_find(struct vm_map *map, void *object, unsigned int offset,
                unsigned int *address, unsigned int size, int anywhere)
{
    *address = next_va;
    next_va += size;
    reserved = size;
    return 0;
}

void pmap_enter_cache_spec(struct pmap *pmap, unsigned int va,
                           unsigned int pa, int prot, int wired, int caching)
{
    if (!calls) first_pa = pa;
    calls++;
    if ((va | pa) & (page_size - 1)) failures++;
}

/* Other platform initialization is outside this mapping test. */
int acpi_discover(unsigned int hint, i386_firmware_info_t *info) { return 0; }
int mptable_discover(i386_firmware_info_t *info) { return 0; }
void pcicfg_set_ecam(volatile unsigned char *p, int first, int last) {}
int pcicfg_read(int b, int d, int f, int o, int s, unsigned int *v) { return 0; }
int pcicfg_write(int b, int d, int f, int o, int s, unsigned int v) { return 0; }
int msi_enable(int b, int d, int f) { return 0; }
int msi_disable(int b, int d, int f) { return 0; }
int apic_intr_enable(const i386_firmware_info_t *info) { return 0; }
unsigned char apic_boot_id(void) { return 0; }
int lapic_clock_enable(void) { return 0; }
int smp_start(const i386_firmware_info_t *info, unsigned char id,
              unsigned char vector) { return 0; }
int acpi_pm_enable(const i386_firmware_info_t *info) { return 0; }

int main(void)
{
    unsigned int result;
    result = (unsigned int)pexpert_map_physical(0x1ffe2191, 36);
    if (reserved != 8192 || calls != 1 || first_pa != 0x1ffe2000 ||
        result != 0x20000191) failures++;
    calls = 0;
    result = (unsigned int)pexpert_map_physical(0x10001800, 0x2020);
    if (reserved != 16384 || calls != 2 || first_pa != 0x10000000 ||
        result != 0x20003800) failures++;
    printf("%s: 8 KB VM alignment, reservation, page count and byte offsets\n",
           failures ? "FAIL" : "PASS");
    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
