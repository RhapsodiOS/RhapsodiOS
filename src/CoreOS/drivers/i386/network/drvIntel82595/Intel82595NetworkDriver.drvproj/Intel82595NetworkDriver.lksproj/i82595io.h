/* Register operations recovered from the inlined i386 port sequences. */
#ifndef I82595_IO_H
#define I82595_IO_H
#ifndef I595_PORTS_PROVIDED
#import <driverkit/i386/ioPorts.h>
#import <driverkit/generalFuncs.h>
#endif

static __inline__ void i595Bank(unsigned short base, unsigned char *bank,
                              unsigned char wanted)
{
    if (*bank != wanted) {
        outb(base, wanted << 6);
        *bank = wanted;
    }
}

static __inline__ unsigned char i595Read8(unsigned short base,
    unsigned char *bank, unsigned char wanted, unsigned char reg)
{
    i595Bank(base, bank, wanted);
    return inb(base + reg);
}

static __inline__ void i595Write8(unsigned short base, unsigned char *bank,
    unsigned char wanted, unsigned char reg, unsigned char value)
{
    i595Bank(base, bank, wanted);
    outb(base + reg, value);
}

static __inline__ void i595Write16(unsigned short base, unsigned char *bank,
    unsigned char reg, unsigned short value)
{
    i595Bank(base, bank, 0);
    outw(base + reg, value);
}

static __inline__ void i595Pointer(unsigned short base, unsigned char *bank,
                                  unsigned short address)
{
    unsigned char value = i595Read8(base, bank, 0, 3);
    i595Write8(base, bank, 0, 3, value & 0xef);
    i595Write16(base, bank, 12, address);
}

/* The reference transfers a full final word for odd byte counts. Callers
 * provide word-addressable storage, including the debugger's packet buffer. */
static __inline__ void i595ReadWords(unsigned short base, unsigned char *bank,
                                     void *buffer, unsigned short bytes)
{
    unsigned short *p = buffer;
    unsigned int i;
    i595Bank(base, bank, 0);
    for (i = 0; i < (bytes >> 1); i++) *p++ = inw(base + 14);
    if (bytes & 1) *p = inw(base + 14);
}

static __inline__ void i595WriteWords(unsigned short base, unsigned char *bank,
                              const void *buffer, unsigned short bytes)
{
    const unsigned short *p = buffer;
    unsigned int i;
    i595Bank(base, bank, 0);
    for (i = 0; i < (bytes >> 1); i++) outw(base + 14, *p++);
    if (bytes & 1) outw(base + 14, *p);
}

static __inline__ void i595Command(unsigned short base, unsigned char *bank,
                                  unsigned char command)
{
    if (i595Read8(base, bank, 0, 1) & 8) {
        i595Write8(base, bank, 0, 1, 8);
        IOSleep(100);
    }
    outb(base, (inb(base) & 0xe0) | command);
}

static __inline__ int i595Wait(unsigned short base, unsigned char *bank,
    unsigned char mask, unsigned char value, unsigned int count)
{
    unsigned int i;
    for (i = 0; i < count; i++) {
        if ((i595Read8(base, bank, 0, 1) & mask) == value) return 1;
        IODelay(1000);
    }
    return 0;
}

/* The EM525 and PRO/10 use this fixed six-address-bit EEPROM sequence.
 * This is distinct from the PRO/10+ EEPROM's width-discovery protocol. */
static __inline__ int i595AddressWord(unsigned short base, unsigned char *bank,
                                    int address, unsigned short *word)
{
    unsigned char control, command = address | 0x80;
    unsigned short mask = 0x8000;
    int i;
    *word = 0;
    control = i595Read8(base, bank, 2, 10) & 0xf0;
    i595Write8(base, bank, 2, 10, control);
    IODelay(20);
    control |= 2;
    i595Write8(base, bank, 2, 10, control);
    IODelay(1);
    control |= 4;
    for (i = 0; i < 9; i++) {
        if (i) {
            control = (control & ~4) | ((command & 0x80) ? 4 : 0);
            command <<= 1;
        }
        i595Write8(base, bank, 2, 10, control);
        control |= 1;
        i595Write8(base, bank, 2, 10, control);
        IODelay(1);
        control &= ~1;
        i595Write8(base, bank, 2, 10, control);
        IODelay(1);
    }
    for (i = 0; i < 100; i++) {
        control = i595Read8(base, bank, 2, 10);
        if (!(control & 8)) break;
        IODelay(1);
    }
    if (i == 100) return 0;
    for (i = 0; i < 16; i++) {
        IODelay(1);
        control |= 3;
        i595Write8(base, bank, 2, 10, control);
        IODelay(1);
        i595Write8(base, bank, 2, 10, control & ~1);
        control = i595Read8(base, bank, 2, 10);
        if (control & 8) *word |= mask;
        mask >>= 1;
    }
    control = i595Read8(base, bank, 2, 10);
    i595Write8(base, bank, 2, 10, control & 0xf0);
    return 1;
}

/* Short names retain the bank and access width at every call site. */
#define READ8(b,r) i595Read8(ioBase, &currentBank, (b), (r))
#define WRITE8(b,r,v) i595Write8(ioBase, &currentBank, (b), (r), (v))
#define WRITE16(r,v) i595Write16(ioBase, &currentBank, (r), (v))
#define COMMAND(c) i595Command(ioBase, &currentBank, (c))
#define POINTER(a) i595Pointer(ioBase, &currentBank, (a))
#define READ_WORDS(p,n) i595ReadWords(ioBase, &currentBank, (p), (n))
#define WRITE_WORDS(p,n) i595WriteWords(ioBase, &currentBank, (p), (n))
#define WAIT(m,v,n) i595Wait(ioBase, &currentBank, (m), (v), (n))
#endif
