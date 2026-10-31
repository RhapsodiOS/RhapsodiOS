#import "Intel82595.h"
#import "i82595io.h"

static const unsigned short irqMap[5] = {3, 5, 9, 10, 11};

@implementation Intel82595ISA
- (const char *)description { return "Intel82595-based ISA Ethernet Adapter"; }

- (BOOL)resetChip
{
    unsigned int i;
    BOOL success = NO;
    COMMAND(14);
    IODelay(250);
    for (i = 0; i < 500000; i++) {
        if (READ8(0, 1) & 8) {
            WRITE8(0, 1, 8);
            success = YES;
            break;
        }
    }
    currentBank = 3;
    i595Bank(ioBase, &currentBank, 0);
    return success;
}

- (BOOL)busConfig
{
    unsigned char value = READ8(1, 1);
    if (value & 2) {
        WRITE8(1, 1, value & 0xbf);
        value = READ8(1, 13);
        WRITE8(1, 13, value | 2);
        READ8(1, 0);
        value = READ8(1, 13);
        WRITE8(1, 13, value & 0xfd);
        if (!(value & 1)) {
            /* The original deliberately reuses the register-13 readback. */
            WRITE8(1, 1, (value & 0xbd) | 0x40);
            value = READ8(1, 13);
            WRITE8(1, 13, value | 2);
            READ8(1, 0);
            value = READ8(1, 13);
            WRITE8(1, 13, value & 0xfd);
            if (!(value & 1)) {
                WRITE8(1, 1, value & 0xbd);
                IOLog("%s: Unable to perform 16-bit transfers\n", [self name]);
                IOLog("%s: Defaulting to 8-bit mode\n", [self name]);
            }
        }
    } else IOLog("%s: 8-bit slot detected\n", [self name]);
    return [self irqConfig];
}

- (BOOL)irqConfig
{
    unsigned char i, value;
    for (i = 0; i < 5; i++) if (irq == irqMap[i]) break;
    if (i == 5) {
        IOLog("%s: Invalid IRQ Level (%d) configured.\n", [self name], irq);
        return NO;
    }
    value = READ8(1, 2);
    WRITE8(1, 2, (value & 0xf8) | i);
    return YES;
}
@end
