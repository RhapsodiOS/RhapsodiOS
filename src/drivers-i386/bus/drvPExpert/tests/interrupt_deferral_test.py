"""Generate a native test of production IRQ mask updates and deferral."""
import re, sys
from pathlib import Path
source = (Path(__file__).resolve().parents[4] / 'kernel-7/machdep/i386/intr.c').read_text()
def function(name):
    match = re.search(r'^(?:static\s+)?(?:inline\s+)?(?:void|int|boolean_t)\s+' + name + r'\([^;]*?\)\s*\{', source, re.M)
    assert match, name
    start = source.index('{',match.start()); end = start + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[match.start():end]
globals = source[source.index('static intr_dispatch_t'):source.index('static const intr_controller_t')]
counts = re.search(r'struct \{\s*unsigned int\s+intr;.*?\} intr_cnt;',source,re.S).group()
fixture = r'''
#include <stdio.h>
#include <string.h>
typedef unsigned long long pexpert_irq_mask_t;
typedef int boolean_t;
typedef struct { pexpert_irq_mask_t mask; } intr_irq_mask_t;
typedef struct { unsigned int which; void (*routine)(); int ipl; } intr_dispatch_t;
typedef struct { int trapno; } thread_saved_state_t;
#define INTR_NIRQ 64
#define INTR_NIPL 8
#define INTR_IPL0 0
#define INTR_VECT_OFF 0x40
#define INTR_MASK_IRQ(x) ((pexpert_irq_mask_t)1 << (x))
#define TRUE 1
#define FALSE 0
static int mask_calls, serviced[64], failures, inject_nested;
static int watch_level, level_unmasked;
static void sti(void) {}
static void cli(void) {}
static void capture_mask(pexpert_irq_mask_t mask, ...) {
    mask_calls++;
    if (watch_level && !(mask & INTR_MASK_IRQ(11))) level_unmasked++;
}
static void eoi(int irq) {}
static int spurious(int irq) { return 0; }
typedef struct {
    void (*set_mask)(pexpert_irq_mask_t mask, ...);
    void (*eoi)(int irq);
    int (*is_spurious)(int irq);
} intr_controller_t;
static const intr_controller_t fake_controller = { capture_mask, eoi, spurious };
static const intr_controller_t *controller = &fake_controller;
'''
fixture += globals + counts + '\n'
for name in ['set_irq_mask','set_masked_ipl','set_ipl','lower_masked_ipl','lower_ipl','intr_handler']:
    fixture += function(name) + '\n'
fixture += r'''
static void service(unsigned int irq, void *state, int old_ipl) {
    serviced[irq]++;
    if (inject_nested && (irq == 48 || irq == 11)) {
        thread_saved_state_t nested;
        inject_nested = 0;
        nested.trapno = INTR_VECT_OFF + 14;
        intr_handler(&nested);
        if (irq == 11) watch_level = 0;
    }
}
static void check(char *name, int pass) {
    printf("%s: %s\n",pass ? "PASS" : "FAIL",name);
    if (!pass) failures++;
}
int main(void) {
    int level, irq;
    int irqs[] = {14,15,48,49};
    thread_saved_state_t state;
    pexpert_irq_mask_t active = 0;
    for (irq = 0; irq < 4; irq++) {
        int n = irqs[irq];
        active |= INTR_MASK_IRQ(n);
        dispatch_table[n].which = n;
        dispatch_table[n].routine = service;
        dispatch_table[n].ipl = 3;
    }
    for (level = 0; level < INTR_NIPL; level++)
        ipl_mask[level].mask = level < 3 ? ~active : ~(pexpert_irq_mask_t)0;
    current_ipl = masked_ipl = 7;
    disabled_irq_mask.mask = INTR_MASK_IRQ(14);
    set_irq_mask(ipl_mask[7]);
    disabled_irq_mask.mask = 0;
    set_irq_mask(ipl_mask[7]);
    check("enabling an IRQ under a raised IPL updates hardware",mask_calls == 2);
    for (irq = 0; irq < 4; irq++) {
        state.trapno = INTR_VECT_OFF + irqs[irq];
        intr_handler(&state);
    }
    check("raised IPL defers all handlers",!serviced[14] && !serviced[15] && !serviced[48] && !serviced[49]);
    lower_ipl(0,7);
    check("both ISA IRQs at the same IPL survive",serviced[14] == 1 && serviced[15] == 1);
    check("both upper IRQ bits at the same IPL survive",serviced[48] == 1 && serviced[49] == 1);
    check("lowering IPL twice does not repeat handlers",(lower_ipl(0,7),serviced[14] == 1 && serviced[49] == 1));
    serviced[14] = serviced[48] = 0;
    dispatch_table[48].ipl = 6;
    current_ipl = masked_ipl = 0;
    inject_nested = 1;
    state.trapno = INTR_VECT_OFF + 48;
    intr_handler(&state);
    check("interrupt return drains a nested deferred edge",serviced[48] == 1 && serviced[14] == 1);
    dispatch_table[11].which = 11;
    dispatch_table[11].routine = service;
    dispatch_table[11].ipl = 6;
    for (level = 0; level < INTR_NIPL; level++) {
        ipl_mask[level].mask = ~(pexpert_irq_mask_t)0;
        if (level < 3) ipl_mask[level].mask &= ~INTR_MASK_IRQ(14);
        if (level < 6) ipl_mask[level].mask &= ~INTR_MASK_IRQ(11);
    }
    current_ipl = masked_ipl = 6;
    set_irq_mask(ipl_mask[6]);
    state.trapno = INTR_VECT_OFF + 11;
    intr_handler(&state);
    watch_level = 1;
    state.trapno = INTR_VECT_OFF + 14;
    intr_handler(&state);
    watch_level = 0;
    check("lower edge arrival keeps a deferred level IRQ masked",!level_unmasked && masked_ipl == 6 && !serviced[11]);
    lower_ipl(0,6);
    check("deferred level and edge handlers run once",serviced[11] == 1 && serviced[14] == 2);
    serviced[11] = serviced[14] = level_unmasked = 0;
    current_ipl = masked_ipl = 0;
    set_irq_mask(ipl_mask[0]);
    inject_nested = watch_level = 1;
    state.trapno = INTR_VECT_OFF + 11;
    intr_handler(&state);
    watch_level = 0;
    check("nested edge preserves the active level mask until return",!level_unmasked && serviced[11] == 1 && serviced[14] == 1);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
'''
Path(sys.argv[1]).write_text(fixture)
