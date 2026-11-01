/* Native fixture: production MP PCI routing admission with synthetic tables. */
#include <stdio.h>
#include <string.h>
#include "../i386/chips/ioapic.h"
#include "../i386/mptable.c"
void *pexpert_map_physical(unsigned int pa, unsigned int size) { return 0; }
static struct { mp_config_t header; unsigned char entries[24]; } table;
static int failures;
static void check(char *name, int pass) {
    printf("%s: %s\n", pass ? "PASS" : "FAIL", name);
    if (!pass) failures++;
}
int main(void) {
    ioapic_t io;
    unsigned char id; unsigned int pin; unsigned short flags;
    memset(&table,0,sizeof(table)); memset(&io,0,sizeof(io));
    io.id = 2; io.pins = 24;
    config = &table.header; pci_bus[0] = 1;
    config->length = sizeof(config[0]) + 8; config->entry_count = 1;
    table.entries[0] = MP_ENTRY_BUS;
    check("table without PCI assignments retains PIC", !mptable_pci_routes_usable(&io,1));
    table.entries[0] = MP_ENTRY_IOINT; table.entries[5] = 12;
    table.entries[6] = 2; table.entries[7] = 11;
    check("valid PCI assignment admits known controller and input", mptable_pci_routes_usable(&io,1));
    check("admitted route resolves PCI slot INTA", mptable_pci_route(0,3,1,&id,&pin,&flags) && id == 2 && pin == 11);
    table.entries[6] = 3;
    check("unknown destination controller retains PIC", !mptable_pci_routes_usable(&io,1));
    table.entries[6] = 2; table.entries[7] = 24;
    check("destination outside chip pin count retains PIC", !mptable_pci_routes_usable(&io,1));
    table.entries[7] = 11; io.gsi_base = PEXPERT_GSI_IRQS - 11;
    check("destination outside supported IRQ range retains PIC", !mptable_pci_routes_usable(&io,1));
    io.gsi_base = 0; config->entry_count = 2;
    check("truncated entry list retains PIC", !mptable_pci_routes_usable(&io,1));
    config->entry_count = 1; table.entries[0] = MP_ENTRY_PROCESSOR;
    check("truncated processor entry retains PIC", !mptable_pci_routes_usable(&io,1));
    table.entries[0] = MP_ENTRY_IOINT;
    config->entry_count = 2; config->length += 8;
    table.entries[8] = MP_ENTRY_BUS; table.entries[9] = MP_MAX_BUSES;
    memcpy(table.entries + 10,"PCI   ",6);
    check("unsupported PCI bus retains PIC despite valid bus-zero route", !mptable_pci_routes_usable(&io,1));
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
