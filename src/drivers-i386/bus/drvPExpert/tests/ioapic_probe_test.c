/* Real chip initialization against a memory-backed MMIO window. */
#include <stdio.h>
#include <string.h>
#include "../i386/chips/ioapic.c"
static int failures;
static void check(char *name, int pass) {
    printf("%s: %s\n",pass ? "PASS" : "FAIL",name);
    if (!pass) failures++;
}
int main(void) {
    unsigned int registers[8];
    ioapic_t io;
    memset(&io,0,sizeof(io)); memset(registers,0,sizeof(registers));
    io.base = registers;
    registers[IOWIN] = 0xffffffff;
    ioapic_init(&io);
    check("absent I/O APIC has no pins and no entry writes",!io.pins && registers[IOWIN] == 0xffffffff);
    registers[IOWIN] = 0;
    ioapic_init(&io);
    check("zero version has no pins and no entry writes",!io.pins && !registers[IOWIN]);
    registers[IOWIN] = 0x00170020;
    ioapic_init(&io);
    check("valid 24-pin I/O APIC masks its entries",io.pins == 24 && registers[IOWIN] == IOAPIC_MASKED);
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
