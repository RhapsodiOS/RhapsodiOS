"""Generate a native calibration test with a simulated 8254 counter 2 and LAPIC timer."""
import re
import sys
from pathlib import Path
source = (Path(__file__).resolve().parents[1] / 'i386/clock.c').read_text()
def function(name):
    return re.search(r'static unsigned int\n' + name + r'\(.*?\n\}', source, re.S).group()
fixture = r'''
#include <stdio.h>
#define PEXPERT_TIMER_IRQ 62
#define PEXPERT_VECTOR(irq) (0x40 + (irq))
#define TIMER_CONSTANT 1193167
#define TIMER_EVENTMODE 0
#define TIMER_CTL_RW_BOTH 3
#define TIMER_CNT2_SEL 2
#define CALIBRATE_US 10000
#define CALIBRATE_SAMPLES 5
typedef struct { unsigned char bcd:1, mode:3, rw:2, sel:2; } timer_ctl_reg_t;
/* simulated time in ns; every device access costs 2 us, and one access may stall */
static unsigned long long now, loaded;
static unsigned long long lapic_hz = 62500000;
static int accesses, stall_at = -1, stall_every;
static unsigned long long stall_ns;
static void tick(void) {
    accesses++;
    now += 2000;
    if (accesses == stall_at || (stall_every && accesses % stall_every == 0))
        now += stall_ns;
}
static unsigned long long pit_elapsed(void) { return (now - loaded) * 1193182 / 1000000000; }
static unsigned char port61;
static unsigned int inb(int port) { tick(); return (port61 & 0xf) | (pit_elapsed() > 0xffff ? 0x20 : 0); }
static void outb(int port, unsigned int v) { tick(); port61 = v; }
static void timer_set_ctl(timer_ctl_reg_t r) { tick(); }
static void aux_timer_start(void) { tick(); loaded = now; }
static void aux_timer_stop(unsigned int *cnt) { tick(); *cnt = pit_elapsed() & 0xffff; }
static void lapic_timer_start(unsigned int n, unsigned char v, int p) { tick(); }
static void lapic_timer_set_masked(int m) { tick(); }
static void lapic_timer_stop(void) { tick(); }
static unsigned int lapic_timer_read(void) { tick(); return 0xffffffffU - (unsigned int)(now * lapic_hz / 1000000000); }
'''
fixture += function('lapic_rate') + '\n' + function('lapic_calibrate')
fixture += r'''
static int failures;
static void expect(char *name, unsigned int got, unsigned int lo, unsigned int hi) {
    int pass = got >= lo && got <= hi;
    printf("%s: %s (%u)\n", pass ? "PASS" : "FAIL", name, got);
    if (!pass) failures++;
}
int main(void) {
    int k;
    expect("quiet calibration measures 62.5 MHz", lapic_calibrate(), 62250000, 62750000);
    /* a stall between a counter read and its LAPIC neighbour skewed the old single sample */
    stall_ns = 8000000;
    for (k = 1; k < 40; k += 3) {
        accesses = 0; stall_at = k;
        expect("one 8 ms stall inside a sample is refused", lapic_calibrate(), 62250000, 62750000);
    }
    accesses = 0; stall_at = 8;
    expect("a stall inside the start pair refuses the sample", lapic_rate(CALIBRATE_US), 0, 0);
    stall_ns = 12000000; accesses = 0; stall_at = 10;
    expect("a stall inside an end pair refuses the sample", lapic_rate(CALIBRATE_US), 0, 0);
    stall_ns = 60000000; accesses = 0; stall_at = 21;
    expect("counter 2 running out refuses the sample", lapic_rate(CALIBRATE_US), 0, 0);
    accesses = 0;
    expect("a 60 ms stall past counter 2's range is refused", lapic_calibrate(), 62250000, 62750000);
    stall_at = -1; stall_ns = 1000000; stall_every = 7; accesses = 0;
    expect("stalls in every sample fall back to the 8254", lapic_calibrate(), 0, 0);
    printf("%d failures\n", failures);
    return failures != 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
