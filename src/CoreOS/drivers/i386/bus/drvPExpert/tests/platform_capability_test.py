"""Generate native tests of APIC MSR admission and bounded AP startup."""
import re
import sys
from pathlib import Path

tests = Path(__file__).resolve().parent
lapic = (tests.parent / 'i386/chips/lapic.c').read_text()
smp = (tests.parent / 'i386/smp.c').read_text()
def function(source, name):
    match = re.search(r'^(?:unsigned int|int)\s+' + name + r'\([^;]*?\)\s*\{', source, re.M)
    assert match, name
    start = source.index('{', match.start()); end = start + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[match.start():end]
base = function(lapic, 'lapic_physical_base')
base, reads = re.subn(r'asm volatile\("rdmsr".*?;', 'lo = msr_lo; hi = msr_hi; msr_reads++;', base, flags=re.S)
base, writes = re.subn(r'asm volatile\("wrmsr".*?;', 'msr_lo = lo; msr_hi = hi; msr_writes++;', base, flags=re.S)
assert reads == writes == 1
fixture = '#include <stdio.h>\n#include <string.h>\n'
fixture += '#include "' + (tests.parent / 'i386/pexpert_i386.h').as_posix() + '"\n'
fixture += '#include "' + (tests.parent / 'i386/chips/lapic.h').as_posix() + '"\n'
fixture += '\n'.join(re.findall(r'^#define\s+(?:APIC_BASE_\w+|LAPIC_CPUID_\w+)\s+[^\n]+',lapic,re.M)) + '\n'
fixture += r'''
static unsigned int msr_lo, msr_hi, features = LAPIC_CPUID_MSR;
static int msr_reads, msr_writes, failures;
static int cpuid_available(void) { return 1; }
static unsigned int cpuid_features(void) { return features; }
static int cpu_total, cpus_online = 1, attempts, highest_index, invalid_index;
static unsigned char ap_spurious_vector;
static unsigned int alloc_cnvmem(unsigned int size, unsigned int alignment) { return 0x70000; }
static int start_one(unsigned char *page, unsigned char id, int index) {
    attempts++;
    if (index > highest_index) highest_index = index;
    if (index < 1 || index >= PEXPERT_MAX_CPUS) invalid_index++;
    return 1;
}
static void check(char *name, int pass) {
    printf("%s: %s\n",pass ? "PASS" : "FAIL",name);
    if (!pass) failures++;
}
'''
fixture += base + '\n' + function(smp,'smp_start') + '\n'
fixture += r'''
int main(void) {
    i386_firmware_info_t info;
    int i;
    msr_lo = 0xfee00800; msr_hi = 0;
    check("enabled xAPIC supplies its MMIO base",lapic_physical_base(0) == 0xfee00000 && !msr_writes);
    msr_lo = 0xfee00c00; msr_reads = msr_writes = 0;
    check("x2APIC mode is rejected without changing the MSR",!lapic_physical_base(0xfee00000) && !msr_writes);
    msr_lo = 0xfee00000; msr_hi = 1; msr_reads = msr_writes = 0;
    check("APIC address above 4 GiB is rejected without changing the MSR",!lapic_physical_base(0xfee00000) && !msr_writes);
    msr_lo = 0xfee00000; msr_hi = 0; msr_reads = msr_writes = 0;
    check("disabled xAPIC can be enabled",lapic_physical_base(0) == 0xfee00000 && msr_writes == 1 && (msr_lo & APIC_BASE_ENABLE));
    features = 0; msr_reads = msr_writes = 0;
    check("processor without APIC MSR uses firmware base",lapic_physical_base(0xfee00000) == 0xfee00000 && !msr_reads && !msr_writes);
    memset(&info,0,sizeof(info)); info.cpu_count = PEXPERT_MAX_CPUS;
    for (i = 0; i < PEXPERT_MAX_CPUS; i++) info.lapic_ids[i] = i;
    smp_start(&info,250,127);
    check("BSP absent from retained CPUs cannot overflow AP arrays",!invalid_index && attempts == PEXPERT_MAX_CPUS - 1 && highest_index == PEXPERT_MAX_CPUS - 1 && cpus_online == PEXPERT_MAX_CPUS);
    attempts = highest_index = invalid_index = 0; cpus_online = 1;
    info.cpu_count = 4;
    smp_start(&info,0,127);
    check("normal four-CPU startup attempts three APs",!invalid_index && attempts == 3 && cpus_online == 4);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
