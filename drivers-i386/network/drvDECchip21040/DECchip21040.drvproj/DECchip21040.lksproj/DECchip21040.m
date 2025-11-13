/*
 * DECchip21040.m
 * Driver for DEC 21040 Ethernet Controller
 */

#import "DECchip21040.h"
#import "DECchip2104xInline.h"
#import <driverkit/generalFuncs.h>

@implementation DECchip21040

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    IORange *ioRange;
    const char *interfaceString;
    id configTable;
    const char *interfaceNames[] = {"AUTO", "BNC", "AUI", "TP"};
    int i;

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

    /* Initialize interface type to AUTO */
    _interfaceType = 0;

    /* Get network interface preference from config table */
    configTable = [deviceDescription configTable];
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
    IOLog("DECchip21040 based adapter at port 0x%x irq %d\n",
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
    if (_networkInterface == nil) {
        [self free];
        return nil;
    }

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
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x0705);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0x8F09);
            break;

        case 2:  /* AUI */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 6);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x0705);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF09);
            break;

        case 3:  /* TP (10BASE-T) */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xFFFF);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0x8F01);
            break;

        default:
            /* AUTO or invalid - default to TP */
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0);
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0xFFFF);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0x8F01);
            break;
    }

    IODelay(100);
    _interfaceType = interfaceType;

    return IO_R_SUCCESS;
}

/*
 * Get station (MAC) address
 * Reads the Ethernet MAC address from the Boot ROM (CSR9)
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    unsigned int i;
    int romData;
    volatile void *ioBase = _ioBase;

    /* Reset Boot ROM address pointer */
    DECchip_WriteCSR(ioBase, CSR9_BOOT_ROM, 0);

    /* Read 6 bytes of MAC address from Boot ROM */
    for (i = 0; i < 6; i++) {
        /* Wait for data to be ready (bit 31 = 0 means ready) */
        do {
            romData = DECchip_ReadCSR(ioBase, CSR9_BOOT_ROM);
            IOSleep(1);
        } while (romData < 0);  /* Wait for bit 31 to clear */

        /* Extract the byte and store it */
        addr->ea_byte[i] = (unsigned char)romData;
    }
}

/*
 * Select network interface
 * Auto-detects the best available interface if interfaceType is AUTO
 */
- (IOReturn)selectInterface
{
    unsigned int siaStatus;
    int timeout;
    unsigned int selectedInterface;
    volatile void *ioBase = _ioBase;

    if (_interfaceType == 0) {
        /* AUTO mode - try TP first, then AUI, then BNC */

        /* Try 10BASE-T (TP) first */
        [self setInterface:3];  /* TP */

        /* Wait up to 999ms for link status */
        timeout = 999;
        while (timeout > 0) {
            IODelay(1000);  /* 1ms delay */
            siaStatus = DECchip_ReadCSR(ioBase, CSR12_SIA_STATUS);

            /* Check for TP link (bit 2 clear indicates link) */
            if ((siaStatus & 0x04) == 0) {
                /* TP link detected */
                return IO_R_SUCCESS;
            }
            timeout--;
        }

        /* TP failed, try AUI */
        [self setInterface:2];  /* AUI */

        /* Wait up to 999ms for AUI status */
        timeout = 999;
        while (timeout > 0) {
            IODelay(1000);  /* 1ms delay */
            siaStatus = DECchip_ReadCSR(ioBase, CSR12_SIA_STATUS);

            /* Check for AUI activity (bit 1 set indicates activity) */
            if ((siaStatus & 0x02) != 0) {
                /* AUI detected, use BNC instead */
                selectedInterface = 1;  /* BNC */
                goto configure_interface;
            }
            timeout--;
        }

        /* No auto-detection succeeded, default to TP */
        selectedInterface = 3;  /* TP */
    } else {
        /* Use manually configured interface type */
        selectedInterface = _interfaceType;
    }

configure_interface:
    [self setInterface:selectedInterface];
    return IO_R_SUCCESS;
}

@end
