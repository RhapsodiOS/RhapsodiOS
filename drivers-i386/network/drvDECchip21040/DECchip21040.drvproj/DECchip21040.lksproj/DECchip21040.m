/*
 * DECchip21040.m
 * Driver for DEC 21040 Ethernet Controller
 */

#import "DECchip21040.h"
#import "DECchip2104xInline.h"
#import <driverkit/generalFuncs.h>

@implementation DECchip21040

/*
 * Probe for 21040 devices
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if ([deviceDescription respondsToSelector:@selector(getPCIVendorID)] &&
        [deviceDescription respondsToSelector:@selector(getPCIDeviceID)]) {

        vendorID = [deviceDescription getPCIVendorID];
        deviceID = [deviceDescription getPCIDeviceID];

        /* Check for DEC 21040 (vendor 0x1011, device 0x0002) */
        if (vendorID == 0x1011 && deviceID == 0x0002) {
            return YES;
        }
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    [super initFromDeviceDescription:deviceDescription];

    if (![self initChip]) {
        [self free];
        return nil;
    }

    return self;
}

/*
 * Initialize 21040-specific hardware
 */
- (BOOL)initChip
{
    /* Reset the chip */
    if (![self resetAndEnable:NO]) {
        return NO;
    }

    /* Setup SIA (Serial Interface Adapter) for 21040 */
    [self setupSIA];

    return YES;
}

/*
 * Setup SIA registers for 21040
 * The 21040 uses the SIA for 10BASE-T and AUI connections
 */
- (void)setupSIA
{
    volatile void *ioBase = _ioBase;

    /* Reset SIA */
    DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0);
    IODelay(10);

    /* Configure for 10BASE-T */
    DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x7F3F);      /* TX/RX configuration */
    DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0x0008);    /* General purpose */
    DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF01); /* Enable 10BASE-T */

    IODelay(100);
}

/*
 * Set network interface type
 */
- (IOReturn)setInterface:(unsigned int)interfaceType
{
    /* TODO: Implement interface selection for 21040 */
    return IO_R_SUCCESS;
}

/*
 * Get station (MAC) address
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    /* TODO: Read MAC address from SROM for 21040 */
    [super getEthernetAddress:addr];
}

/*
 * Select network interface
 */
- (IOReturn)selectInterface
{
    /* TODO: Implement interface selection logic for 21040 */
    return IO_R_SUCCESS;
}

@end
