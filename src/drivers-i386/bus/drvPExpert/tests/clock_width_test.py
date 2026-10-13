"""Generate a native C test using the kernel's actual clock storage and functions.

Run: python clock_width_test.py /tmp/clock-width-test.c
Then compile that file with cc and execute it. Only port reads and IPL changes
are substituted; countdown conversion and rollover handling are production code.
"""
import re
import sys
from pathlib import Path

source = (Path(__file__).resolve().parents[4] /
          'kernel-7/machdep/i386/machine_clock.c').read_text()

def function(name):
    match = re.search(r'^(?:static )?(?:unsigned int|tvalspec_t)\s+' + name + r'\([^;]*?\)\s*\{', source, re.M)
    assert match, name
    start = source.index('{', match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]

storage = re.search(r'static struct _system_clock \{.*?\} system_clock;', source, re.S).group()
fixture = r'''
#include <stdio.h>
typedef unsigned short timer_cnt_val_t;
typedef struct { unsigned int tv_sec, tv_nsec; } tvalspec_t;
typedef tvalspec_t mapped_tvalspec_t;
typedef unsigned int clock_res_t;
#define TICKS_PER_SEC 100
#define NSEC_PER_TICK 10000000
#define ADD_TVALSPEC_NSEC(t, n) do { (t)->tv_nsec += (n); \
    if ((t)->tv_nsec >= 1000000000) { (t)->tv_sec++; (t)->tv_nsec -= 1000000000; } } while (0)
static int splclock(void) { return 0; }
static void splx(int s) {}
static unsigned int countdown;
static unsigned int read_count(void) { return countdown; }
static unsigned int (*tick_source_read)(void) = read_count;
'''
fixture += storage + '\n' + function('clock_set_tick_source') + '\n' + function('system_time_stamp')
fixture += r'''
static int failures;
static void check(char *name, unsigned int sec, unsigned int nsec) {
    tvalspec_t t = system_time_stamp();
    int pass = t.tv_sec == sec && t.tv_nsec == nsec;
    printf("%s: %s (%u.%09u)\n", pass ? "PASS" : "FAIL", name, t.tv_sec, t.tv_nsec);
    if (!pass) failures++;
}
int main(void) {
    unsigned int reload = clock_set_tick_source(read_count, 62500000);
    system_clock.counter.tv_sec = 13;
    system_clock.counter.tv_nsec = 0;
    countdown = reload;
    check("32-bit reload starts at the tick boundary", 13, 0);
    countdown = 468750;
    check("quarter of a LAPIC tick", 13, 2500000);
    countdown = 100000;
    check("late LAPIC tick", 13, 8400000);
    countdown = 600000;
    check("counter reload accounts for the pending tick", 13, 10400000);
    check("repeated read preserves the pending tick", 13, 10400000);
    clock_set_tick_source(read_count, 1193200);
    countdown = 5966;
    check("16-bit PIT source remains supported", 13, 5000000);
    printf("%d failures\n", failures);
    return failures ? 1 : 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
