/* Native fixture: production APIC masking with simulated I/O APIC inputs. */
#include <stdio.h>
#include <string.h>
#include "../i386/apic_intr.c"
static unsigned int entries[64];
static int failures, delivered, lost, controller_switches, mappings, deny_mapping;
static unsigned int mmio[1024];
static int lapic_inits, ioapic_inits, reject_base;
static unsigned int deny_address;
static int reject_second;
static int routes_usable = 1;
void ioapic_set_masked(ioapic_t *io, unsigned int pin, int masked)
{
    if (masked) entries[pin] |= IOAPIC_MASKED;
    else entries[pin] &= ~IOAPIC_MASKED;
}
void ioapic_set_entry(ioapic_t *io, unsigned int pin, unsigned int low, unsigned char dest) { entries[pin] = low; }
unsigned int ioapic_pin_count(ioapic_t *io) { return reject_second && io->id == 1 ? 0 : 24; }
void ioapic_init(ioapic_t *io) { io->pins = 24; ioapic_inits++; }
void lapic_timer_set_masked(int masked) {}
void msi_set_masked(int irq, int masked) {}
int msi_irq_active(int irq) { return 0; }
void lapic_eoi(void) {}
unsigned char lapic_id(void) { return 0; }
int lapic_present(void) { return 1; }
unsigned int lapic_physical_base(unsigned int fallback) { return reject_base ? 0 : fallback; }
void lapic_init(volatile unsigned int *base, unsigned char vector) { lapic_inits++; }
void msi_init(unsigned char id) {}
void intr_set_controller(const intr_controller_t *c) { controller_switches++; }
void *pexpert_map_physical(unsigned int pa, unsigned int len) {
    mappings++;
    return deny_mapping || pa == deny_address ? 0 : mmio;
}
int mptable_pci_route(int b, int d, int p, unsigned char *id, unsigned int *in, unsigned short *f) { return 0; }
int mptable_pci_routes_usable(const ioapic_t *io, unsigned int count) { return routes_usable; }
static void check(char *name, int pass) {
    printf("%s: %s\n",pass ? "PASS" : "FAIL",name);
    if (!pass) failures++;
}
/* Extra arguments are ignored by the old one-argument implementation. */
static void mask(pexpert_irq_mask_t priority, pexpert_irq_mask_t disabled) {
    ((void (*)(pexpert_irq_mask_t,pexpert_irq_mask_t))apic_set_mask)(priority,disabled);
}
int main(void) {
    i386_firmware_info_t info;
    int n;
    pexpert_irq_mask_t all = ~(pexpert_irq_mask_t)0;
    memset(&info,0,sizeof(info));
    ioapic_count = 1;
    ioapics[0].gsi_base = 0; ioapics[0].pins = 24;
    info.iso_count = 1;
    info.isos[0].isa_irq = 11; info.isos[0].gsi = 11; info.isos[0].flags = 0xd;
    build_pin_map(&info);
    for (n = 0; n < 24; n++) entries[n] = IOAPIC_MASKED;
    current_masked = all;
    mask(0,0);
    mask(all,0);
    if (entries[14] & IOAPIC_MASKED) lost++; else delivered++;
    check("IRQ14 edge is retained during a priority mask",delivered == 1 && !lost);
    check("level-triggered IRQ11 stays hardware masked at high IPL",entries[11] & IOAPIC_MASKED);
    mask(all,(pexpert_irq_mask_t)1 << 14);
    check("explicit IRQ14 disable masks its input",entries[14] & IOAPIC_MASKED);
    mask(all,0);
    check("re-enable under a raised IPL restores edge delivery",!(entries[14] & IOAPIC_MASKED));
    apic_set_trigger(14,1);
    check("edge-to-level change restores priority masking",entries[14] & IOAPIC_MASKED);
    apic_set_trigger(14,0);
    check("level-to-edge change restores edge delivery",!(entries[14] & IOAPIC_MASKED));
    memset(&info,0,sizeof(info));
    info.madt = 1; info.ioapic_count = 1;
    info.lapic_address = 0xfee00000;
    info.ioapics[0].address = 0xfec00000;
    check("missing PCI routing retains PIC before hardware changes",
          !apic_intr_enable(&info) && !controller_switches && !mappings);
    controller_switches = mappings = apic_mode = 0;
    info.mp_config = 1;
    deny_mapping = 1;
    check("failed APIC mapping retains PIC",!apic_intr_enable(&info) && !controller_switches);
    deny_mapping = 0;
    check("usable APIC firmware switches controllers",apic_intr_enable(&info) && controller_switches == 1);
    controller_switches = mappings = lapic_inits = ioapic_inits = apic_mode = 0;
    reject_base = 1;
    check("unsupported local APIC mode/address retains PIC before mapping",
          !apic_intr_enable(&info) && !controller_switches && !mappings);
    reject_base = 0;
    controller_switches = mappings = lapic_inits = ioapic_inits = apic_mode = 0;
    info.iso_count = 1; info.isos[0].isa_irq = 0; info.isos[0].gsi = 48;
    check("unusable PIT route retains PIC without masking LINT0",
          !apic_intr_enable(&info) && !controller_switches && !lapic_inits && !ioapic_inits);
    info.iso_count = 0; info.ioapic_count = 2;
    info.ioapics[1].id = 1; info.ioapics[1].address = 0xfec01000;
    info.ioapics[1].gsi_base = 24;
    deny_address = info.ioapics[1].address;
    check("unmapped second I/O APIC retains PIC despite usable PIT",
          !apic_intr_enable(&info) && !controller_switches && !lapic_inits && !ioapic_inits);
    controller_switches = mappings = lapic_inits = ioapic_inits = apic_mode = 0;
    deny_address = 0; reject_second = 1;
    check("unresponsive second I/O APIC retains PIC despite usable PIT",
          !apic_intr_enable(&info) && !controller_switches && !lapic_inits && !ioapic_inits);
    controller_switches = mappings = lapic_inits = ioapic_inits = apic_mode = 0;
    info.ioapic_count = 1; reject_second = 0; routes_usable = 0;
    check("MP table without usable PCI assignments retains PIC",
          !apic_intr_enable(&info) && !controller_switches && !lapic_inits && !ioapic_inits);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
