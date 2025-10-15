/*
 * DECchip21041.m
 * DECchip 21041 specific implementation
 */

#import "DECchip21041.h"
#import <driverkit/generalFuncs.h>

/* CSR definitions */
#define CSR12_SIA_STATUS        12
#define CSR13_SIA_CONNECTIVITY  13
#define CSR14_SIA_TX_RX         14
#define CSR15_SIA_GENERAL       15

/* SIA Status bits (CSR12) - Enhanced for 21041 */
#define SIA_STATUS_PAUI         0x00000001  /* Pin AUI/TP */
#define SIA_STATUS_NCR          0x00000002  /* Network Connection Error */
#define SIA_STATUS_LKF          0x00000004  /* Link Fail */
#define SIA_STATUS_LS10         0x00000008  /* Link Status 10Mbps */
#define SIA_STATUS_APS          0x00000010  /* Auto Polarity State */
#define SIA_STATUS_DS           0x00000020  /* DE Sense */
#define SIA_STATUS_NSN          0x00000040  /* Non-Stable NLPs Detected */
#define SIA_STATUS_TRF          0x00000080  /* Transmit Remote Fault */
#define SIA_STATUS_ANS          0x00007000  /* Auto-Negotiation State */
#define SIA_STATUS_LPN          0x00008000  /* Link Partner Negotiable */
#define SIA_STATUS_NRA          0x08000000  /* New Remote Fault */

/* Autosense states */
#define AUTOSENSE_INIT          0
#define AUTOSENSE_10BASET       1
#define AUTOSENSE_10BASETFD     2
#define AUTOSENSE_10BASE2       3
#define AUTOSENSE_10BASE5       4
#define AUTOSENSE_COMPLETE      5

/* Link check interval (in ms) */
#define LINK_CHECK_INTERVAL     1000

@implementation DECchip21041

/*
 * Class method: probe
 * Only match 21041 devices
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    unsigned int vendor, device;

    if (![deviceDescription isKindOf:[IOPCIDeviceDescription class]]) {
        return NO;
    }

    vendor = [(IOPCIDeviceDescription *)deviceDescription getVendor];
    device = [(IOPCIDeviceDescription *)deviceDescription getDevice];

    /* Check for DEC vendor ID and 21041 device ID */
    if (vendor == 0x1011 && device == 0x0014) {
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

    /* Verify this is actually a 21041 */
    if (_chipType != CHIP_TYPE_21041) {
        IOLog("DECchip21041: Wrong chip type\n");
        [self free];
        return nil;
    }

    /* Initialize 21041-specific state */
    _mediaAutoDetect = YES;
    _nwayEnabled = NO;
    _linkCheckInterval = LINK_CHECK_INTERVAL;
    _linkUp = NO;
    _autosenseState = AUTOSENSE_INIT;

    IOLog("DECchip21041: Initialized at 0x%x IRQ %d\n", _ioBase, _irqLevel);

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
 * Detect 10BaseT half-duplex connection
 */
- (BOOL)detect10BaseT
{
    unsigned int status;
    int i;

    IOLog("DECchip21041: Trying 10BaseT...\n");

    /* Reset SIA */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    /* Configure for 10BaseT half-duplex */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00007F3F];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000008];

    /* Wait for link */
    IODelay(100000); /* 100ms */

    /* Check link status */
    for (i = 0; i < 20; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* Link Fail bit should be 0 for good link */
        /* LS10 bit should be 1 for 10Mbps link */
        if (!(status & SIA_STATUS_LKF) && (status & SIA_STATUS_LS10)) {
            IOLog("DECchip21041: 10BaseT half-duplex link detected\n");
            _mediaType = 0; /* 10BaseT */
            _fullDuplex = NO;
            _linkUp = YES;
            return YES;
        }

        IODelay(10000); /* 10ms */
    }

    return NO;
}

/*
 * Detect 10BaseT full-duplex connection
 */
- (BOOL)detect10BaseTFD
{
    unsigned int status;
    int i;

    IOLog("DECchip21041: Trying 10BaseT full-duplex...\n");

    /* Reset SIA */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    /* Configure for 10BaseT full-duplex */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00007F3D];  /* Different from half-duplex */
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000008];

    /* Wait for link */
    IODelay(100000); /* 100ms */

    /* Check link status */
    for (i = 0; i < 20; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* Link Fail bit should be 0 for good link */
        if (!(status & SIA_STATUS_LKF) && (status & SIA_STATUS_LS10)) {
            IOLog("DECchip21041: 10BaseT full-duplex link detected\n");
            _mediaType = 0; /* 10BaseT */
            _fullDuplex = YES;
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

    IOLog("DECchip21041: Trying 10Base2...\n");

    /* Reset SIA */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    /* Configure for 10Base2 */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000009];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];

    /* Wait for link */
    IODelay(100000); /* 100ms */

    /* Check for carrier */
    for (i = 0; i < 20; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* For BNC, NCR bit indicates carrier */
        /* On 21041, also check DS (DE Sense) */
        if (!(status & SIA_STATUS_NCR)) {
            IOLog("DECchip21041: 10Base2 link detected\n");
            _mediaType = 1; /* 10Base2 */
            _fullDuplex = NO;
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

    IOLog("DECchip21041: Trying 10Base5...\n");

    /* Reset SIA */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000000];
    IODelay(10000); /* 10ms */

    /* Configure for 10Base5 (AUI) */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00008009];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00000705];
    [self writeCSR:CSR15_SIA_GENERAL value:0x00000006];

    /* Wait for link */
    IODelay(100000); /* 100ms */

    /* Check for carrier */
    for (i = 0; i < 20; i++) {
        status = [self readCSR:CSR12_SIA_STATUS];

        /* For AUI, check PAUI bit and NCR */
        if ((status & SIA_STATUS_PAUI) && !(status & SIA_STATUS_NCR)) {
            IOLog("DECchip21041: 10Base5 link detected\n");
            _mediaType = 2; /* 10Base5 */
            _fullDuplex = NO;
            _linkUp = YES;
            return YES;
        }

        IODelay(10000); /* 10ms */
    }

    return NO;
}

/*
 * Auto-detect media type
 * The 21041 has improved auto-detection over 21040
 */
- (void)autoDetectMedia
{
    IOLog("DECchip21041: Auto-detecting media...\n");

    /* Reset autosense state */
    _autosenseState = AUTOSENSE_INIT;

    /* Perform autosense sequence */
    [self performAutosense];
}

/*
 * Perform autosense - tries each media type
 */
- (void)performAutosense
{
    /* Try media types in priority order */

    /* 1. Try 10BaseT half-duplex (most common) */
    if ([self detect10BaseT]) {
        _autosenseState = AUTOSENSE_COMPLETE;
        return;
    }

    /* 2. Try 10BaseT full-duplex */
    if ([self detect10BaseTFD]) {
        _autosenseState = AUTOSENSE_COMPLETE;
        return;
    }

    /* 3. Try 10Base2 (BNC) */
    if ([self detect10Base2]) {
        _autosenseState = AUTOSENSE_COMPLETE;
        return;
    }

    /* 4. Try 10Base5 (AUI) */
    if ([self detect10Base5]) {
        _autosenseState = AUTOSENSE_COMPLETE;
        return;
    }

    /* Default to 10BaseT if nothing detected */
    IOLog("DECchip21041: No media detected, defaulting to 10BaseT\n");
    _mediaType = 0;
    _fullDuplex = NO;
    _linkUp = NO;
    _autosenseState = AUTOSENSE_COMPLETE;

    /* Configure for 10BaseT anyway */
    [self writeCSR:CSR13_SIA_CONNECTIVITY value:0x00000001];
    [self writeCSR:CSR14_SIA_TX_RX value:0x00007F3F];
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
            _linkUp = !(status & SIA_STATUS_LKF) && (status & SIA_STATUS_LS10);
            break;

        case 1: /* 10Base2 */
            _linkUp = !(status & SIA_STATUS_NCR);
            break;

        case 2: /* 10Base5 */
            _linkUp = (status & SIA_STATUS_PAUI) && !(status & SIA_STATUS_NCR);
            break;

        default:
            _linkUp = NO;
            break;
    }

    /* Log link state changes */
    if (_linkUp && !wasUp) {
        IOLog("DECchip21041: Link up\n");
    } else if (!_linkUp && wasUp) {
        IOLog("DECchip21041: Link down - attempting re-detection\n");
        /* Re-detect media on link loss */
        if (_mediaAutoDetect) {
            [self performAutosense];
        }
    }
}

/*
 * Enable N-Way auto-negotiation
 * Note: 21041 has limited N-Way support
 */
- (BOOL)enableNway
{
    /* 21041 has limited auto-negotiation capability */
    /* It can detect link partner but cannot fully negotiate */
    IOLog("DECchip21041: N-Way auto-negotiation not fully supported\n");
    _nwayEnabled = NO;
    return NO;
}

/*
 * Disable N-Way
 */
- (void)disableNway
{
    _nwayEnabled = NO;
}

/*
 * Check if N-Way is complete
 */
- (BOOL)nwayComplete
{
    unsigned int status;

    if (!_nwayEnabled) {
        return NO;
    }

    status = [self readCSR:CSR12_SIA_STATUS];

    /* Check if link partner is negotiable */
    return (status & SIA_STATUS_LPN) ? YES : NO;
}

/*
 * Timeout occurred - periodic link check and autosense
 */
- (void)timeoutOccurred
{
    /* Check link status periodically */
    [self checkLinkStatus];

    /* Call superclass to update statistics */
    [super timeoutOccurred];
}

@end
