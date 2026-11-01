"""Generate a native test for the SCI power-button shutdown request."""
import re
import sys
from pathlib import Path
source = (Path(__file__).resolve().parents[1] / 'i386/acpi_pm.c').read_text()
fallback = re.search(r'#ifndef RB_POWERDOWN.*?#endif', source, re.S).group()
handler = re.search(r'static void\nsci_handler\(.*?\n\}', source, re.S).group()
fixture = r'''
#include <stdio.h>
#include <sys/reboot.h>
#define PM1_STS_PWRBTN 0x100
static struct { unsigned int pm1a_evt, pm1b_evt; } info = { 0x600, 0 };
static int how, cleared;
static typeof(info) *fadt = &info;
static unsigned short pm1_status(unsigned int block) { return block ? 0x100 : 0; }
static void pm1_clear(unsigned int block, unsigned short bits) { if (block) cleared = bits; }
static void reboot_mach(int flags) { how = flags; }
'''
fixture += fallback + '\n' + handler
fixture += r'''
int main(void) {
    sci_handler(9, 0, 0);
    if (how != 0x10008 || cleared != 0x100) {
        printf("FAIL: power button requested 0x%x, expected halt and powerdown 0x10008\n", how);
        return 1;
    }
    printf("PASS: SCI acknowledges power button and requests halt with powerdown\n");
    return 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
