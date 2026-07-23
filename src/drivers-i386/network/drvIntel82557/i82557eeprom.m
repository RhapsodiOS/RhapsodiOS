/*
 * i82557eeprom.m
 * Intel 82557 EEPROM Management
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <objc/Object.h>

/* External function declarations */
extern void IODelay(int microseconds);

/* EEPROM control register bits */
#define EEPROM_SK   0x01  /* Clock */
#define EEPROM_CS   0x02  /* Chip select */
#define EEPROM_DI   0x04  /* Data in */
#define EEPROM_DO   0x08  /* Data out */

/* EEPROM commands */
#define EEPROM_READ_OPCODE  6

@interface i82557eeprom : Object
{
    unsigned char *ioBasePtr;      /* +0x04: Pointer to EEPROM control register */
    int addressWidth;              /* +0x08: Address width in bits */
    unsigned short eepromData[64]; /* +0x0C: EEPROM data (64 words) */
}

- initWithAddress:(unsigned char *)address;
- (unsigned short)readWord:(unsigned int)offset;
- (unsigned char *)getContents;
- (void)dumpContents;

@end

@implementation i82557eeprom

/*
 * Initialize EEPROM with I/O base address pointer
 * Performs EEPROM initialization sequence and reads all contents
 */
- initWithAddress:(unsigned char *)address
{
    unsigned char *ctrlReg;
    int i;
    unsigned short word;
    short checksum;

    [super init];

    /* Store I/O base pointer */
    ioBasePtr = address;

    /* Set chip select high */
    *ioBasePtr |= EEPROM_CS;

    /* Send three dummy clock cycles to reset EEPROM */
    ctrlReg = ioBasePtr;

    /* First dummy cycle */
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg |= EEPROM_DI;
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Second dummy cycle */
    ctrlReg = ioBasePtr;
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg |= EEPROM_DI;
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Third dummy cycle */
    ctrlReg = ioBasePtr;
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg &= ~EEPROM_DI;  /* Clear DI */
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Detect address width by checking DO pin */
    addressWidth = 1;
    do {
        ctrlReg = ioBasePtr;
        *ctrlReg &= ~EEPROM_DI;
        *ctrlReg &= ~EEPROM_DI;
        *ctrlReg |= EEPROM_SK;
        IODelay(20);
        *ctrlReg &= ~EEPROM_SK;
        IODelay(20);

        /* Check if DO went high (indicates address width found) */
        if ((*ioBasePtr & EEPROM_DO) == 0) {
            break;
        }

        addressWidth++;
    } while (addressWidth < 0x21);

    /* Deselect chip */
    *ioBasePtr &= ~EEPROM_CS;

    /* Read all 64 words from EEPROM */
    checksum = 0;
    for (i = 0; i < 0x40; i++) {
        word = [self readWord:i];
        checksum += word;
        eepromData[i] = word;
    }

    /* Verify checksum (should sum to 0xBABA) */
    if (checksum != (short)0xBABA) {
        IOLog("i82557eeprom: checksum %x incorrect\n", (unsigned short)checksum);
        [self free];
        return nil;
    }

    return self;
}

/*
 * Read a 16-bit word from EEPROM at specified offset
 * Uses bit-banging to communicate with EEPROM
 */
- (unsigned short)readWord:(unsigned int)offset
{
    unsigned char *ctrlReg;
    int bitIndex;
    unsigned short data;
    unsigned char bit;

    /* Set chip select high */
    *ioBasePtr |= EEPROM_CS;

    /* Send three start bits for read command */
    ctrlReg = ioBasePtr;

    /* First start bit */
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg |= EEPROM_DI;
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Second start bit */
    ctrlReg = ioBasePtr;
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg |= EEPROM_DI;
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Third start bit (read opcode - 0) */
    ctrlReg = ioBasePtr;
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg &= ~EEPROM_DI;
    *ctrlReg |= EEPROM_SK;
    IODelay(20);
    *ctrlReg &= ~EEPROM_SK;
    IODelay(20);

    /* Send address bits (MSB first) */
    bitIndex = addressWidth;
    while (--bitIndex >= 0) {
        ctrlReg = ioBasePtr;
        *ctrlReg &= ~EEPROM_DI;

        /* Set DI based on current address bit */
        *ctrlReg |= (((offset >> bitIndex) & 1) << 2);

        /* Clock the bit */
        *ctrlReg |= EEPROM_SK;
        IODelay(20);
        *ctrlReg &= ~EEPROM_SK;
        IODelay(20);
    }

    /* Read 16 data bits (MSB first) */
    data = 0;
    bitIndex = 15;
    do {
        ctrlReg = ioBasePtr;

        /* Clock in next bit */
        *ctrlReg |= EEPROM_SK;
        IODelay(20);
        bit = *ctrlReg;
        *ctrlReg &= ~EEPROM_SK;
        IODelay(20);

        /* Extract DO bit and shift into result */
        data |= ((bit >> 3) & 1) << bitIndex;

        bitIndex--;
    } while (bitIndex >= 0);

    /* Deselect chip */
    *ioBasePtr &= ~EEPROM_CS;

    return data;
}

/*
 * Get pointer to EEPROM contents
 * Returns pointer to the eepromData array
 */
- (unsigned char *)getContents
{
    return (unsigned char *)eepromData;
}

/*
 * Dump EEPROM contents to console for debugging
 * Displays formatted information about the EEPROM contents
 */
- (void)dumpContents
{
    const char *separator;
    const char *connector[4];
    const char *phyName;
    int i;
    unsigned char *dataPtr;
    const char *phyType;
    const char *phyTypes[] = {
        "No PHY device installed",
        "Intel 82553A or equivalent",
        "Intel 82553C or equivalent",
        "Intel 82503 (serial interface)",
        "Intel 82596 or equivalent",
        "Reserved",
        "Reserved",
        "Reserved"
    };

    dataPtr = (unsigned char *)eepromData;

    IOLog("The EEPROM contains the following information:\n");

    /* Display Ethernet address (bytes 0-5 at offset 0x0C) */
    IOLog("ethernet address: ");
    for (i = 0; i < 6; i++) {
        separator = (i > 0) ? ":" : "";
        IOLog("%s%02x", separator, dataPtr[i]);
    }
    IOLog("\n");

    /* Display compatibility flags (byte at offset 0x12) */
    if ((dataPtr[0x06] & 0x01) != 0) {
        IOLog("compatibility: MCSETUP workaround required for 10 Mbits\n");
    }
    if ((dataPtr[0x06] & 0x02) != 0) {
        IOLog("compatibility: MCSETUP workaround required for 100 Mbits\n");
    }

    /* Display connectors (byte at offset 0x16) */
    connector[0] = (dataPtr[0x0A] & 0x01) ? "RJ-45" : "";
    connector[1] = (dataPtr[0x0A] & 0x02) ? "BNC" : "";
    connector[2] = (dataPtr[0x0A] & 0x04) ? "AUI" : "";
    connector[3] = (dataPtr[0x0A] & 0x08) ? "MII" : "";
    IOLog("connectors: %s %s %s %s\n", connector[0], connector[1], connector[2], connector[3]);

    /* Display controller type (byte at offset 0x17) */
    IOLog("controller type: %d\n", dataPtr[0x0B]);

    /* Display PHY information for primary and secondary */
    for (i = 0; i < 2; i++) {
        phyName = (i == 0) ? "primary" : "secondary";

        /* Get PHY type (bits 0-5 of byte at offset 0x19/0x1B) */
        unsigned int phyTypeIndex = dataPtr[0x0D + i * 2] & 0x3F;

        if (phyTypeIndex < 7) {
            phyType = phyTypes[phyTypeIndex];
        } else {
            phyType = "Reserved";
        }

        IOLog("%s PHY: %s\n", phyName, phyType);

        if ((dataPtr[0x0D + i * 2] & 0x3F) != 0) {
            if ((dataPtr[0x0D + i * 2] & 0x40) != 0) {
                IOLog("%s PHY: vendor specific code required\n", phyName);
            }
            if ((dataPtr[0x0D + i * 2] & 0x80) != 0) {
                IOLog("%s PHY: 10 Mbits only, requires 503 interface\n", phyName);
            }
            IOLog("%s PHY address: 0x%x\n", phyName, dataPtr[0x0C + i * 2]);
        }
    }

    /* Display PWA Number (bytes at offsets 0x1C-0x1F) */
    IOLog("PWA Number: %d %d %d-0%d\n",
          dataPtr[0x11], dataPtr[0x10], dataPtr[0x13], dataPtr[0x12]);

    /* Display checksum (word at offset 0x8A = eepromData[0x3F]) */
    IOLog("Checksum: 0x%x\n", eepromData[0x3F]);

    /* Note: The decompiled code has a check that always compares the same value,
     * which appears to be a decompilation artifact, so we omit it here */
}

@end
