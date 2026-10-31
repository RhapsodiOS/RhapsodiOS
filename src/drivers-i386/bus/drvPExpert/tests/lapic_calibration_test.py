"""Generate a native calibration test with an inaccurate spin delay."""
import re
import sys
from pathlib import Path
source = (Path(__file__).resolve().parents[1] / 'i386/clock.c').read_text()
function = re.search(r'static unsigned int\nlapic_ticks_in\(.*?\n\}', source, re.S).group()
fixture = r'''
#include <stdio.h>
#define PEXPERT_TIMER_IRQ 62
#define PEXPERT_VECTOR(irq) (0x40 + (irq))
static unsigned long long nanoseconds;
static unsigned int sample_ns = 1250000;
static void lapic_timer_start(unsigned int n, unsigned char v, int p) { nanoseconds = 0; }
static void lapic_timer_set_masked(int m) {}
static void lapic_timer_stop(void) {}
static unsigned int lapic_timer_read(void) { return 0xffffffffU - (unsigned int)(nanoseconds / 1000); }
static void IODelay(unsigned int us) { nanoseconds += us * 250; }
static void IOGetTimestamp(unsigned long long *n) { nanoseconds += sample_ns; *n = nanoseconds; }
'''
fixture += function
fixture += r'''
int main(void) {
    unsigned int count = lapic_ticks_in(10000);
    if (count < 9900 || count > 10100) {
        printf("FAIL: 1 MHz timer measured %u counts in 10 ms with short spin delay\n", count);
        return 1;
    }
    sample_ns = 1750000;
    count = lapic_ticks_in(10000);
    if (count < 9900 || count > 10100) {
        printf("FAIL: calibration overshoot changed the measured rate (%u)\n", count);
        return 1;
    }
    sample_ns = 0;
    if (lapic_ticks_in(10000) != 0) {
        printf("FAIL: stopped reference clock did not reject calibration\n");
        return 1;
    }
    printf("PASS: hardware clock calibration ignores spin speed, corrects overshoot and rejects a stopped clock\n");
    return 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
