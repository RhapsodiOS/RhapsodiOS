"""Generate a native test of production defaults and platform initialization.

Privileged initialization is replaced by controlled hardware outcomes. Actual
CPU/firmware detection and interrupt delivery are covered by QEMU boots.
"""
import re
import sys
from pathlib import Path

tests = Path(__file__).resolve().parent
kernel = (tests.parents[3] / 'kernel-7/machdep/i386/i386_init.c').read_text()
defaults = re.findall(r'^int\s+pexpert_(?:apic|rsdp|lapictimer|smp|acpi)\b[^;]*;', kernel, re.M)
assert len(defaults) == 5
fixture = '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n'
fixture += '\n'.join(defaults) + '\n'
fixture += '#include "' + (tests.parent / 'i386/pexpert.c').as_posix() + '"\n'
fixture += r'''
struct vm_map *kernel_map;
struct pmap *kernel_pmap;
unsigned int page_size = 8192;
static int apic_ok = 1, clock_ok = 1, pm_ok = 1, cpus = 4;
static int active, discovery, mp_discovery, apic_calls, clock_calls, smp_calls, pm_calls;
static int sequence_error;
int vm_map_find(struct vm_map *m, void *o, unsigned int off,
                unsigned int *a, unsigned int size, int anywhere) { return 1; }
void pmap_enter_cache_spec(struct pmap *p, unsigned int va, unsigned int pa,
                           int prot, int wired, int caching) {}
int pcicfg_read(int b, int d, int f, int o, int s, unsigned int *v) { return 0; }
int pcicfg_write(int b, int d, int f, int o, int s, unsigned int v) { return 0; }
void pcicfg_set_ecam(volatile unsigned char *base, int start, int end) {}
int msi_enable(int b, int d, int f) { return -1; }
int msi_disable(int b, int d, int f) { return 0; }
int acpi_discover(unsigned int hint, i386_firmware_info_t *info) {
    discovery++;
    memset(info, 0, sizeof(*info)); info->cpu_count = cpus;
    return 1;
}
int mptable_discover(i386_firmware_info_t *info) { mp_discovery++; return 1; }
int apic_intr_enable(const i386_firmware_info_t *info) {
    apic_calls++;
    if (discovery != 1 || mp_discovery != 1) sequence_error++;
    if (apic_ok) active |= 1;
    return apic_ok;
}
unsigned char apic_boot_id(void) { return 0; }
int lapic_clock_enable(void) {
    clock_calls++;
    if (!(active & 1)) sequence_error++;
    if (clock_ok) active |= 2;
    return clock_ok;
}
int smp_start(const i386_firmware_info_t *info, unsigned char boot,
              unsigned char spurious) {
    smp_calls++;
    if (!(active & 1)) sequence_error++;
    if (info->cpu_count > 1) active |= 4;
    return info->cpu_count - 1;
}
int acpi_pm_enable(const i386_firmware_info_t *info) {
    pm_calls++;
    if (pm_ok) active |= 8;
    return pm_ok;
}
int main(int argc, char **argv) {
    int n = argc == 2 ? atoi(argv[1]) : -1;
    static const char *names[] = {
        "supported hardware needs no flags", "apic=0 keeps PIC/PIT and skips APs",
        "lapictimer=0 retains PIT", "smp=0 leaves APs alone", "acpi=0 skips PM",
        "all zero overrides retain the legacy path", "unsupported APIC retains legacy interrupts/clock",
        "failed calibration retains PIT with APIC", "unsupported PM leaves ACPI inactive",
        "one CPU starts no APs", "independent APIC and PM failures retain legacy paths",
        "explicit enable still obeys hardware checks", "initialization runs once"
    };
    static const int expected[] = {15,8,13,11,7,0,8,13,7,11,0,8,15};
    int pass;
    if (n < 0 || n >= sizeof(expected)/sizeof(expected[0])) return 2;
    switch (n) {
    case 1: pexpert_apic = 0; break;
    case 2: pexpert_lapictimer = 0; break;
    case 3: pexpert_smp = 0; break;
    case 4: pexpert_acpi = 0; break;
    case 5: pexpert_apic = pexpert_lapictimer = pexpert_smp = pexpert_acpi = 0; break;
    case 6: apic_ok = 0; break;
    case 7: clock_ok = 0; break;
    case 8: pm_ok = 0; break;
    case 9: cpus = 1; break;
    case 10: apic_ok = pm_ok = 0; break;
    case 11: pexpert_apic = pexpert_lapictimer = pexpert_smp = pexpert_acpi = 1;
             apic_ok = 0; break;
    }
    pexpert_init();
    if (n == 12) pexpert_init();
    pass = active == expected[n] && discovery == 1 && mp_discovery == 1 && !sequence_error;
    if (!(active & 1)) pass = pass && !clock_calls && !smp_calls;
    if (!pexpert_apic) pass = pass && !apic_calls;
    if (!pexpert_acpi) pass = pass && !pm_calls;
    if (n == 12) pass = pass && apic_calls == 1 && clock_calls == 1 && smp_calls == 1 && pm_calls == 1;
    printf("%s: %s (active=%d expected=%d)\n",pass ? "PASS" : "FAIL",names[n],active,expected[n]);
    return pass ? 0 : 1;
}
'''
Path(sys.argv[1]).write_text(fixture)
