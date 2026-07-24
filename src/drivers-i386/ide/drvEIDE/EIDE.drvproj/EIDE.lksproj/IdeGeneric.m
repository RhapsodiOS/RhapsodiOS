/*
 * IdeGeneric.m - Generic SFF-8038i chipset back-end. Used for any bus-master
 * PCI IDE controller not claimed by a specific back-end. Programs no chip
 * timing registers (leaves BIOS/POST timing); offers PIO always plus an
 * MWDMA2 attempt gated by the driver's DMA self-test. UDMA is not offered
 * because we will not blind-program unknown UDMA timing.
 */
#import "IdeCnt.h"
#import "IdeBMIDE.h"
#import <driverkit/generalFuncs.h>

static BOOL genericMatch(unsigned long pciID, unsigned char progIf,
    ideChipCaps_t *out)
{
    /* Only claim bus-master-capable controllers; pure-legacy parts fall
     * through to the driver's legacy PIO path. */
    if (!(progIf & PCI_IDE_BUSMASTER))
        return NO;
    out->maxPIO   = 4;
    out->maxMWDMA = 2;
    out->maxUDMA  = ATA_MODE_NUM_NONE;
    out->flags    = CHIP_FLAG_BUSMASTER;
    return YES;
}

static void genericSetTiming(id self, void *drives)   { /* BIOS timing kept */ }
static void genericResetTiming(id self)                { /* nothing to revert */ }
static BOOL genericDetectCable(id self)                { return NO; }

const ideChipsetOps_t ideGenericOps = {
    "Generic PCI IDE",
    genericMatch,
    genericSetTiming,
    genericResetTiming,
    genericDetectCable
};
