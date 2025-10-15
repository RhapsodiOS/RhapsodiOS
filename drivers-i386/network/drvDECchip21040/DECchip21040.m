/*
 * DECchip21040.m
 * DECchip 21040 specific implementation
 */

#import "DECchip21040.h"
#import <driverkit/generalFuncs.h>

/* CSR definitions */
#define CSR12_SIA_STATUS        12
#define CSR13_SIA_CONNECTIVITY  13
#define CSR14_SIA_TX_RX         14
#define CSR15_SIA_GENERAL       15

/* SIA Status bits (CSR12) */
#define SIA_STATUS_NCR          0x00000001  /* Network Connection Error */
#define SIA_STATUS_LKF          0x00000002  /* Link Fail */
#define SIA_STATUS_LS10         0x00000004  /* Link Status 10Mbps */
#define SIA_STATUS_LS100        0x00000008  /* Link Status 100Mbps */
#define SIA_STATUS_APS          0x00000010  /* Auto Polarity State */
#define SIA_STATUS_NSN          0x00000040  /* Non-Stable NLPs Detected */
#define SIA_STATUS_TRF          0x00000080  /* Transmit Remote Fault */
#define SIA_STATUS_ANS          0x00007000  /* Auto-Negotiation State */
#define SIA_STATUS_LPN          0x00008000  /* Link Partner Negotiable */

/* Link check interval (in ms) */
#define LINK_CHECK_INTERVAL     1000

@implementation DECchip21040

/*
 * Class method: probe
 * Only match 21040 devices (not 21041)
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int vendor, device;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        return NO;
    }

    vendor = [(IOPCIDeviceDescription *)deviceDescription getVendor];
    device = [(IOPCIDeviceDescription *)deviceDescription getDevice];

    /* Check for DEC vendor ID and 21040 device ID */
    if (vendor == 0x1011 && device == 0x0002) {
        return YES;
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    [super initFromDeviceDescription:deviceDescription];

    if (!self) {
        return nil;
    }

    /* Verify this is actually a 21040 */
    if (_chipType != CHIP_TYPE_21040) {
        IOLog("DECchip21040: Wrong chip type\n");
        [self free];
        return nil;
    }

    /* Initialize 21040-specific state */
    _mediaAutoDetect = YES;
    _linkCheckInterval = LINK_CHECK_INTERVAL;
    _linkUp = NO;

    IOLog("DECchip21040: Initialized at 0x%x IRQ %d\n", _ioBase, _irqLevel);

    return self;
}

/*
 * Free resources
 */
- free
{
    return [super free];
}

/*
 * Reset and enable/disable - with auto-detection
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    if (enable) {
        /* Call superclass implementation */
        if (![super resetAndEnable:enable]) {
            return NO;
        }

        /* Auto-detect media if enabled */
        if (_mediaAutoDetect) {
            [self autoDetectMedia];
        }
    } else {
        [super resetAndEnable:enable];
    }

    return YES;
}

/*
 * Detect 10BaseT connection
 */
- (BOOL)detect10BaseT
{
    unsigned int status;
    int i;

    /* Configure for 10BaseT */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
    [self writeCSR:CSR14_SIA_TX_RX value:0x0000007F];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000008];

    /* Wait for link */
    IODelay(50000); /* 50ms */

    /* Check link status */
    for (i = 0; i < 10; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* Link Fail bit should be 0 for good link */
        if (!(status & SIA_STATUS_LKF)) {
            IOLog("DECchip21040: 10BaseT link detected\n");
            _mediaType = 0; /* 10BaseT */
            _linkUp = YES;
            return YES;
        }

        IODelay(10000); /* 10ms */
    }

    return NO;
}

/*
 * Detect 10Base2 connection (BNC)
 */
- (BOOL)detect10Base2
{
    unsigned int status;
    int i;

    /* Configure for 10Base2 */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000009];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];

    /* Wait for link */
    IODelay(50000); /* 50ms */

    /* Check for carrier */
    for (i = 0; i < 10; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* For BNC, NCR bit indicates carrier */
        if (!(status & SIA_STATUS_NCR)) {
            IOLog("DECchip21040: 10Base2 link detected\n");
            _mediaType = 1; /* 10Base2 */
            _linkUp = YES;
            return YES;
        }

        IODelay(10000); /* 10ms */
    }

    return NO;
}

/*
 * Detect 10Base5 connection (AUI)
 */
- (BOOL)detect10Base5
{
    unsigned int status;
    int i;

    /* Configure for 10Base5 (same as 10Base2 on 21040) */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000009];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];

    /* Wait for link */
    IODelay(50000); /* 50ms */

    /* Check for carrier */
    for (i = 0; i < 10; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* For AUI, check carrier */
        if (!(status & SIA_STATUS_NCR)) {
            IOLog("DECchip21040: 10Base5 link detected\n");
            _mediaType = 2; /* 10Base5 */
            _linkUp = YES;
            return YES;
        }

        IODelay(10000); /* 10ms */
    }

    return NO;
}

/*
 * Auto-detect media type
 * The 21040 has limited auto-detection - try each media in order
 */
- (void)autoDetectMedia
{
    IOLog("DECchip21040: Auto-detecting media...\n");

    /* Try 10BaseT first (most common) */
    if ([self detect10BaseT]) {
        return;
    }

    /* Try 10Base2 (BNC) */
    if ([self detect10Base2]) {
        return;
    }

    /* Try 10Base5 (AUI) */
    if ([self detect10Base5]) {
        return;
    }

    /* Default to 10BaseT if nothing detected */
    IOLog("DECchip21040: No media detected, defaulting to 10BaseT\n");
    _mediaType = 0;
    _linkUp = NO;

    /* Configure for 10BaseT anyway */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
    [self writeCSR:CSR14_SIA_TX_RX value:0x0000007F];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000008];
}

/*
 * Check link status
 */
- (void)checkLinkStatus
{
    unsigned int status;
    BOOL wasUp = _linkUp;

    status = [self readCSR:CSR12_SIA_STATUS];

    /* Determine link status based on media type */
    switch (_mediaType) {
        case 0: /* 10BaseT */
            _linkUp = !(status & SIA_STATUS_LKF);
            break;

        case 1: /* 10Base2 */
        case 2: /* 10Base5 */
            _linkUp = !(status & SIA_STATUS_NCR);
            break;

        default:
            _linkUp = NO;
            break;
    }

    /* Log link state changes */
    if (_linkUp && !wasUp) {
        IOLog("DECchip21040: Link up\n");
    } else if (!_linkUp && wasUp) {
        IOLog("DECchip21040: Link down\n");
    }
}

/*
 * Timeout occurred - periodic link check
 */
- (void)timeoutOccurred
{
    /* Check link status periodically */
    [self checkLinkStatus];

    /* Call superclass to update statistics */
    [super timeoutOccurred];
}

@end
