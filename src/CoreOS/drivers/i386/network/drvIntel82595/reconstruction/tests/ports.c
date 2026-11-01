#include <assert.h>
#include <stdio.h>

static unsigned short ports[256], values[256], reads[256];
static int writes, readCount, delays, sleeps;
static unsigned char inb(unsigned short port) { (void)port; return reads[readCount++]; }
static unsigned short inw(unsigned short port) { (void)port; return reads[readCount++]; }
static void outb(unsigned short port, unsigned char value)
{ ports[writes] = port; values[writes++] = value; }
static void outw(unsigned short port, unsigned short value)
{ ports[writes] = port; values[writes++] = value; }
static void IODelay(unsigned int us) { delays += us; }
static void IOSleep(unsigned int ms) { sleeps += ms; }

/* The production header normally gets these primitives from DriverKit. */
#define _DRIVERKIT_I386_IOPORTS_
#define I595_PORTS_PROVIDED
#include "i82595io.h"

int main(void)
{
    unsigned char bank = 3;
    unsigned short data[2] = {0x1234, 0xabcd}, result[2] = {0, 0};
    i595Write8(0x300, &bank, 2, 4, 0x55);
    i595Write8(0x300, &bank, 2, 5, 0xaa);
    assert(writes == 3 && bank == 2);
    assert(ports[0] == 0x300 && values[0] == 0x80);
    assert(ports[1] == 0x304 && values[1] == 0x55);
    assert(ports[2] == 0x305 && values[2] == 0xaa);
    assert(delays == 0);

    writes = readCount = 0;
    reads[0] = 8; reads[1] = 0xe0;
    i595Command(0x300, &bank, 4);
    assert(writes == 3 && bank == 0 && sleeps == 100);
    assert(ports[1] == 0x301 && values[1] == 8);
    assert(ports[2] == 0x300 && values[2] == 0xe4);

    writes = readCount = 0;
    i595WriteWords(0x300, &bank, data, 3);
    assert(writes == 2 && values[0] == 0x1234 && values[1] == 0xabcd);
    reads[0] = 0x1234; reads[1] = 0xabcd;
    i595ReadWords(0x300, &bank, result, 3);
    assert(readCount == 2 && result[0] == 0x1234 && result[1] == 0xabcd);

    readCount = delays = 0;
    reads[0] = 0x30; reads[1] = 0x10; reads[2] = 0;
    assert(i595Wait(0x300, &bank, 0x30, 0, 3));
    assert(readCount == 3 && delays == 2000);
    readCount = delays = 0;
    assert(!i595Wait(0x300, &bank, 0x30, 0, 2));
    assert(readCount == 2 && delays == 2000);
    puts("82595 port sequencing: passed");
    return 0;
}
