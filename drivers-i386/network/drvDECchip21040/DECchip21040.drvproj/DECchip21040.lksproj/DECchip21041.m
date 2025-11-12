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

@implementation DECchip21041

/*
 * Probe for 21041 devices
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if ([deviceDescription respondsToSelector:@selector(getPCIVendorID)] &&
        [deviceDescription respondsToSelector:@selector(getPCIDeviceID)]) {

        vendorID = [deviceDescription getPCIVendorID];
        deviceID = [deviceDescription getPCIDeviceID];

        /* Check for DEC 21041 (vendor 0x1011, device 0x0014) */
        if (vendorID == 0x1011 && deviceID == 0x0014) {
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

    _mediaType = MEDIA_10BASET;  /* Default to 10BASE-T */

    if (![self initChip]) {
        [self free];
        return nil;
    }

    return self;
}

/*
 * Initialize 21041-specific hardware
 */
- (BOOL)initChip
{
    /* Reset the chip */
    if (![self resetAndEnable:NO]) {
        return NO;
    }

    /* Setup SIA for 21041 with default media */
    [self setupSIA];
    [self selectMedia:_mediaType];

    return YES;
}

/*
 * Setup SIA registers for 21041
 * The 21041 has enhanced SIA with auto-sensing capability
 */
- (void)setupSIA
{
    volatile void *ioBase = _ioBase;

    /* Reset SIA */
    DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0);
    IODelay(10);
}

/*
 * Select media type for 21041
 */
- (BOOL)selectMedia:(unsigned int)mediaType
{
    volatile void *ioBase = _ioBase;

    /* Reset SIA first */
    DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0);
    IODelay(10);

    switch (mediaType) {
        case MEDIA_10BASET:
            /* Configure for 10BASE-T */
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x7F3D);
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0x0008);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF01);
            break;

        case MEDIA_10BASE2:
            /* Configure for 10BASE2 (BNC) */
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x0F73);
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0x0006);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF09);
            break;

        case MEDIA_AUI:
            /* Configure for AUI */
            DECchip_WriteCSR(ioBase, CSR14_SIA_TX_RX, 0x0F3F);
            DECchip_WriteCSR(ioBase, CSR15_SIA_GENERAL, 0x0008);
            DECchip_WriteCSR(ioBase, CSR13_SIA_CONNECTIVITY, 0xEF09);
            break;

        default:
            return NO;
    }

    _mediaType = mediaType;
    IODelay(100);

    return YES;
}

/*
 * Set network interface type
 */
- (IOReturn)setInterface:(unsigned int)interfaceType
{
    /* TODO: Implement interface selection for 21041 */
    return [self selectMedia:interfaceType] ? IO_R_SUCCESS : IO_R_INVALID_ARG;
}

/*
 * Get station (MAC) address
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    /* TODO: Read MAC address from SROM for 21041 */
    [super getEthernetAddress:addr];
}

/*
 * Select network interface
 */
- (IOReturn)selectInterface
{
    /* TODO: Implement interface auto-selection logic for 21041 */
    return IO_R_SUCCESS;
}

@end
