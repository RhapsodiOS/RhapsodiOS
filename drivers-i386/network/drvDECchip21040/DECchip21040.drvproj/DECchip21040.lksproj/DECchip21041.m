/*
 * DECchip21041.m
 * Driver for DEC 21041 Ethernet Controller
 */

#import "DECchip21041.h"
#import "DECchip2104xInline.h"
#import <driverkit/generalFuncs.h>

/* Media types for 21041 */
#define MEDIA_10BASET       0
#define MEDIA_10BASE2       1
#define MEDIA_AUI           2

/* SROM control bits for CSR9 */
#define SROM_CS     0x01    /* Chip select */
#define SROM_CLK    0x02    /* Clock */
#define SROM_DI     0x04    /* Data in */
#define SROM_DO     0x08    /* Data out */
#define SROM_SEL    0x4800  /* SROM select */

@implementation DECchip21041

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    IORange *ioRange;
    const char *interfaceString;
    const char *sromBitsString;
    const char *sromOffsetString;
    id configTable;
    const char *interfaceNames[] = {"AUTO", "BNC", "AUI", "TP"};
    int i;
    const char *p;
    char c;

    /* Call superclass initialization */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get I/O port base address */
    if ([deviceDescription numMemoryRanges] > 0) {
        ioRange = [deviceDescription memoryRangeList];
        _portBase = (unsigned short)[ioRange start];
        _ioBase = (volatile void *)(unsigned long)_portBase;
    } else {
        IOLog("%s: No I/O ranges available\n", [self name]);
        return nil;
    }

    /* Get IRQ number */
    _irqNumber = [deviceDescription interrupt];

    /* Get SROM address bits configuration (default: 6) */
    _sromAddressBits = 6;
    configTable = [deviceDescription configTable];
    if (configTable != nil) {
        sromBitsString = [[configTable valueForStringKey:"SROM Address Bits"] cString];
        if (sromBitsString != NULL) {
            if (strcmp(sromBitsString, "8") == 0) {
                _sromAddressBits = 8;
            }
        }
    }

    /* Get SROM word offset for MAC address (default: 20) */
    _sromWordOffset = 20;
    if (configTable != nil) {
        sromOffsetString = [[configTable valueForStringKey:"SROM Word Offset"] cString];
        if (sromOffsetString != NULL) {
            /* Skip leading whitespace */
            p = sromOffsetString;
            c = *p;
            while (c != '\0' && (c == ' ' || c == '\t' || c == '\n')) {
                p++;
                c = *p;
            }

            /* Parse integer value */
            if (*p != '\0') {
                int value = 0;
                while (*p != '\0') {
                    if (*p == ' ' || *p == '\t' || *p == '\n') {
                        break;
                    }
                    if (*p >= '0' && *p <= '9') {
                        value = value * 10 + (*p - '0');
                    }
                    p++;
                }
                _sromWordOffset = value;
            }
        }
    }

    /* Initialize interface type to AUTO */
    _interfaceType = 0;

    /* Get network interface preference from config table */
    if (configTable != nil) {
        interfaceString = [[configTable valueForStringKey:"Network Interface"] cString];
        if (interfaceString != NULL) {
            /* Parse interface type */
            for (i = 0; i < 4; i++) {
                if (strcmp(interfaceString, interfaceNames[i]) == 0) {
                    _interfaceType = i;
                    break;
                }
            }
        }
    }

    /* Get station (MAC) address */
    [self getStationAddress:&_stationAddress];

    /* Allocate memory for rings and buffers */
    if (![self allocateMemory]) {
        [self free];
        return nil;
    }

    /* Initialize state flags */
    _isEnabled = NO;
    _isAttached = NO;

    /* Log adapter information */
    IOLog("DECchip21041 based adapter at port 0x%x irq %d\n",
          _portBase, _irqNumber);

    if (_interfaceType != 0) {
        IOLog("Interface: %s\n", interfaceString);
    }
    IOLog("\n");

    /* Reset and initialize the chip */
    if (![self resetAndEnable:NO]) {
        [self free];
        return nil;
    }

    /* Attach to network */
    _networkInterface = [super attachToNetworkWithAddress:_stationAddress];

    return self;
}

/*
 * Set network interface type
 * interfaceType: 0=AUTO, 1=BNC, 2=AUI, 3=TP
 */
- (IOReturn)setInterface:(unsigned int)interfaceType
{
    volatile void *ioBase = _ioBase;

    /* Reset SIA */
    DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0);
    IOSleep(1);

    switch (interfaceType) {
        case 1:  /* BNC (10BASE2) */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 6);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xF73D);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF09);
            break;

        case 2:  /* AUI */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0x0E);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xF73D);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF09);
            break;

        case 3:  /* TP (10BASE-T) */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 8);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xFF3F);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF01);
            break;

        default:
            /* AUTO or invalid - default to TP */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 8);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xFF3F);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF01);
            break;
    }

    IODelay(100);
    _interfaceType = interfaceType;

    return IO_R_SUCCESS;
}

/*
 * Get station (MAC) address
 * Reads the Ethernet MAC address from the Serial ROM (SROM) using bit-banging
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    volatile void *ioBase = _ioBase;
    unsigned short sromData[3];
    unsigned int csr9;
    int word, bit;
    unsigned int sromAddress;

    /* Initialize CSR9 for SROM access */
    DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, SROM_SEL);
    IODelay(1);

    /* Read 3 words (6 bytes) from SROM starting at configured offset */
    for (word = 0; word < 3; word++) {
        unsigned short data = 0;
        sromAddress = _sromWordOffset + word;

        /* Assert chip select */
        csr9 = SROM_SEL | SROM_CS;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);

        /* Send READ command (110 in binary) */
        /* Bit 2: 1 */
        csr9 = SROM_SEL | SROM_CS | SROM_DI;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);
        csr9 |= SROM_CLK;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);

        /* Bit 1: 1 */
        csr9 = SROM_SEL | SROM_CS | SROM_DI;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);
        csr9 |= SROM_CLK;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);

        /* Bit 0: 0 */
        csr9 = SROM_SEL | SROM_CS;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);
        csr9 |= SROM_CLK;
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
        IODelay(1);

        /* Send address bits (6 or 8 bits depending on SROM type) */
        for (bit = _sromAddressBits - 1; bit >= 0; bit--) {
            csr9 = SROM_SEL | SROM_CS;
            if (sromAddress & (1 << bit)) {
                csr9 |= SROM_DI;
            }
            DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
            IODelay(1);
            csr9 |= SROM_CLK;
            DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
            IODelay(1);
        }

        /* Clock in 16 bits of data */
        for (bit = 15; bit >= 0; bit--) {
            csr9 = SROM_SEL | SROM_CS;
            DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
            IODelay(1);
            csr9 |= SROM_CLK;
            DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, csr9);
            IODelay(1);

            /* Read data bit from SROM_DO */
            if (DECchip_ReadCSR(ioBase, CSR9_BOOT_ROM) & SROM_DO) {
                data |= (1 << bit);
            }
        }

        /* Deassert chip select */
        DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, SROM_SEL);
        IODelay(1);

        sromData[word] = data;
    }

    /* Convert 3 words to 6 bytes (little-endian) */
    addr->ea_byte[0] = sromData[0] & 0xFF;
    addr->ea_byte[1] = (sromData[0] >> 8) & 0xFF;
    addr->ea_byte[2] = sromData[1] & 0xFF;
    addr->ea_byte[3] = (sromData[1] >> 8) & 0xFF;
    addr->ea_byte[4] = sromData[2] & 0xFF;
    addr->ea_byte[5] = (sromData[2] >> 8) & 0xFF;
}

/*
 * Select network interface
 * Auto-detects the best available interface if interfaceType is AUTO
 */
- (IOReturn)selectInterface
{
    unsigned int csr5Status, csr12Status;
    int timeout;
    unsigned int selectedInterface;

    if (_interfaceType == 0) {
        /* AUTO mode - try TP first, then AUI, then BNC */

        /* Try 10BASE-T (TP) first */
        [self setInterface:3];  /* TP */

        /* Wait up to 49ms for link status */
        timeout = 49;
        while (timeout > 0) {
            IOSleep(1);  /* 1ms delay */
            csr5Status = DECchip_ReadCSR(_ioBase, CSR5_STATUS);

            /* Check for TP link (bit 0x10 set indicates link) */
            if (csr5Status & 0x10) {
                IOLog("%s: detected TP port\n", [self name]);
                return IO_R_SUCCESS;
            }

            /* Also check if bit 0x1000 is clear */
            if ((csr5Status & 0x1000) == 0) {
                timeout--;
            } else {
                break;
            }
        }

        /* TP failed, try AUI */
        [self setInterface:2];  /* AUI */

        /* Wait up to 49ms for AUI/BNC status */
        timeout = 49;
        while (timeout > 0) {
            IOSleep(1);  /* 1ms delay */
            csr5Status = DECchip_ReadCSR(_ioBase, CSR5_STATUS);

            /* Check for TP link detected during AUI test */
            if (csr5Status & 0x10) {
                IOLog("%s: detected TP port\n", [self name]);
                [self setInterface:3];  /* Switch to TP */
                return IO_R_SUCCESS;
            }

            /* Check CSR12 SIA status for media detection */
            csr12Status = DECchip_ReadCSR(_ioBase, CSR12_SIA_STATUS);

            if ((csr12Status & 0x100) == 0) {
                timeout--;
            } else {
                break;
            }
        }

        /* Check final CSR12 status to determine AUI vs BNC */
        csr12Status = DECchip_ReadCSR(_ioBase, CSR12_SIA_STATUS);

        if (csr12Status & 0x100) {
            /* AUI detected */
            IOLog("%s: detected AUI port\n", [self name]);
        } else {
            /* Default to BNC */
            [self setInterface:1];  /* BNC */
            IOLog("%s: detected BNC port\n", [self name]);
        }
    } else {
        /* Use manually configured interface type */
        [self setInterface:_interfaceType];
    }

    return IO_R_SUCCESS;
}

@end
