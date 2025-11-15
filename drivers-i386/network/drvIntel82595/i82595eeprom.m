/*
 * i82595eeprom.m
 * Intel 82595 EEPROM Management
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>

/* EEPROM control bits (register offset 10 from base) */
#define EEPROM_SK   0x01  /* Serial clock */
#define EEPROM_CS   0x02  /* Chip select */
#define EEPROM_DI   0x04  /* Data in */
#define EEPROM_DO   0x08  /* Data out */

@interface i82595eeprom : Object
{
    unsigned short eepromCtrlReg;      /* EEPROM control register port */
    int addressWidth;                   /* Address width in bits */
    unsigned short eepromData[64];     /* EEPROM data buffer (64 words) */
}

- initWithBase:(unsigned short)base CurrentBank:(unsigned char *)bankPtr;
- (unsigned short)readWord:(int)address;
- (unsigned short *)getContents;

@end

@implementation i82595eeprom

/*
 * Initialize EEPROM with I/O base address and bank pointer
 */
- initWithBase:(unsigned short)base CurrentBank:(unsigned char *)bankPtr
{
    unsigned char eepromCtrl;
    int i;
    unsigned short word;
    short checksum;

    [super init];

    /* Select bank 2 for EEPROM access */
    if (*bankPtr != 0x02) {
        outb(base, 0x80);
        IODelay(1);
        *bankPtr = 0x02;
    }

    /* Store EEPROM control register address (base + 10) */
    eepromCtrlReg = base + 10;

    /* Reset EEPROM interface */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl & 0xF0);
    IODelay(20);
    IOSleep(10);

    /* Raise chip select */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_CS);
    IODelay(20);
    IOSleep(10);

    /* Send dummy start bit sequence to determine address width */
    /* Bit 1 */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, (eepromCtrl | EEPROM_DI) & ~EEPROM_SK);
    IODelay(20);

    /* Bit 2 */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, (eepromCtrl | EEPROM_DI) & ~EEPROM_SK);
    IODelay(20);

    /* Bit 3 (start bit = 0) */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl & ~EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, (eepromCtrl & ~EEPROM_DI) | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, eepromCtrl & ~(EEPROM_DI | EEPROM_SK));
    IODelay(20);

    /* Detect address width by clocking until DO goes low */
    addressWidth = 1;
    while (addressWidth < 0x21) {
        eepromCtrl = inb(eepromCtrlReg);
        outb(eepromCtrlReg, eepromCtrl & ~EEPROM_DI);
        IODelay(1);
        outb(eepromCtrlReg, (eepromCtrl & ~EEPROM_DI) | EEPROM_SK);
        IODelay(20);
        outb(eepromCtrlReg, eepromCtrl & ~(EEPROM_DI | EEPROM_SK));
        IODelay(20);

        eepromCtrl = inb(eepromCtrlReg);
        if ((eepromCtrl & EEPROM_DO) == 0) {
            break;
        }
        addressWidth++;
    }

    /* Deselect EEPROM */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl & 0xF0);
    IODelay(20);

    /* Read all 64 words from EEPROM */
    checksum = 0;
    for (i = 0; i < 64; i++) {
        word = [self readWord:i];
        checksum += word;
        eepromData[i] = word;
    }

    /* Verify checksum (should be 0xBABA) */
    if (checksum != (short)0xBABA) {
        IOLog("i82595eeprom: checksum %x incorrect\n", (unsigned short)checksum);
        return [self free];
    }

    return self;
}

/*
 * Read a word from EEPROM at specified address
 */
- (unsigned short)readWord:(int)address
{
    unsigned char eepromCtrl;
    unsigned char dataBit;
    int bitIndex;
    unsigned short result;

    /* Raise chip select */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_CS);
    IODelay(20);

    /* Send READ command (110b) - first two '1' bits */
    /* Bit 1 */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, (eepromCtrl | EEPROM_DI) & ~EEPROM_SK);
    IODelay(20);

    /* Bit 2 */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, eepromCtrl | EEPROM_DI | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, (eepromCtrl | EEPROM_DI) & ~EEPROM_SK);
    IODelay(20);

    /* Bit 3 (start bit = 0) */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl & ~EEPROM_DI);
    IODelay(1);
    outb(eepromCtrlReg, (eepromCtrl & ~EEPROM_DI) | EEPROM_SK);
    IODelay(20);
    outb(eepromCtrlReg, eepromCtrl & ~(EEPROM_DI | EEPROM_SK));
    IODelay(20);

    /* Send address bits (MSB first) */
    for (bitIndex = addressWidth - 1; bitIndex >= 0; bitIndex--) {
        dataBit = (address >> bitIndex) & 1;

        eepromCtrl = inb(eepromCtrlReg);
        if (dataBit) {
            outb(eepromCtrlReg, eepromCtrl | EEPROM_DI);
        } else {
            outb(eepromCtrlReg, eepromCtrl & ~EEPROM_DI);
        }
        IODelay(1);

        outb(eepromCtrlReg, (eepromCtrl & ~EEPROM_DI) | (dataBit << 2) | EEPROM_SK);
        IODelay(20);

        outb(eepromCtrlReg, (eepromCtrl & ~(EEPROM_DI | EEPROM_SK)) | (dataBit << 2));
        IODelay(20);
    }

    /* Read 16 bits of data (MSB first) */
    result = 0;
    for (bitIndex = 15; bitIndex >= 0; bitIndex--) {
        eepromCtrl = inb(eepromCtrlReg);

        /* Clock high */
        outb(eepromCtrlReg, eepromCtrl | EEPROM_SK);
        IODelay(20);

        /* Read data bit */
        eepromCtrl = inb(eepromCtrlReg);

        /* Clock low */
        outb(eepromCtrlReg, eepromCtrl & ~EEPROM_SK);
        IODelay(20);

        /* Extract data bit */
        dataBit = (eepromCtrl >> 3) & 1;
        result |= (dataBit << bitIndex);
    }

    /* Deselect EEPROM */
    eepromCtrl = inb(eepromCtrlReg);
    outb(eepromCtrlReg, eepromCtrl & 0xF0);
    IODelay(20);

    return result;
}

/*
 * Get EEPROM contents buffer
 */
- (unsigned short *)getContents
{
    return eepromData;
}

@end
