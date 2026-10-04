#import "Intel82595.h"
#import "i82595io.h"

static __inline__ void clockBit(unsigned short port, unsigned int bit)
{
    unsigned char value = (inb(port) & 0xfb) | ((bit & 1) << 2);
    outb(port, value);
    outb(port, value | 1);
    IODelay(20);
    outb(port, value & 0xfe);
    IODelay(20);
}

@implementation i82595eeprom
- initWithBase:(unsigned short)base CurrentBank:(unsigned char *)bank
{
    unsigned short checksum = 0, word;
    int i;
    [super init];
    i595Bank(base, bank, 2);
    eepromBase = base + 10;
    outb(eepromBase, inb(eepromBase) & 0xf0);
    IODelay(20);
    IOSleep(10);
    outb(eepromBase, inb(eepromBase) | 2);
    IODelay(20);
    IOSleep(10);
    clockBit(eepromBase, 1);
    clockBit(eepromBase, 1);
    clockBit(eepromBase, 0);
    nbits = 1;
    do {
        clockBit(eepromBase, 0);
        if (!(inb(eepromBase) & 8)) break;
        nbits++;
    } while (nbits <= 32);
    outb(eepromBase, inb(eepromBase) & 0xf0);
    IODelay(20);
    for (i = 0; i < 64; i++) {
        word = [self readWord:i];
        checksum += word;
        ((unsigned short *)contents)[i] = word;
    }
    if (checksum == 0xbaba) return self;
    IOLog("i82595eeprom: checksum %x incorrect\n", checksum);
    return [self free];
}

- (unsigned short)readWord:(int)address
{
    unsigned short result = 0;
    unsigned char value;
    int i;
    outb(eepromBase, inb(eepromBase) | 2);
    IODelay(20);
    clockBit(eepromBase, 1);
    clockBit(eepromBase, 1);
    clockBit(eepromBase, 0);
    for (i = nbits - 1; i >= 0; i--) clockBit(eepromBase, address >> i);
    for (i = 15; i >= 0; i--) {
        outb(eepromBase, inb(eepromBase) | 1);
        IODelay(20);
        value = inb(eepromBase);
        outb(eepromBase, value & 0xfe);
        IODelay(20);
        result |= ((value >> 3) & 1) << i;
    }
    outb(eepromBase, inb(eepromBase) & 0xf0);
    IODelay(20);
    return result;
}

- (unsigned char *)getContents { return contents; }
@end
