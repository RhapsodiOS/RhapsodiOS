/*
 * riva.c - NVIDIA Riva hardware access routines
 */

#include "riva_hw.h"

/* Read a 32-bit register */
CARD32 rivaReadReg(CARD32 *regBase, CARD32 offset)
{
    return regBase[offset >> 2];
}

/* Write a 32-bit register */
void rivaWriteReg(CARD32 *regBase, CARD32 offset, CARD32 value)
{
    regBase[offset >> 2] = value;
}

/* Read VGA register via I/O port */
CARD8 rivaReadVGA(CARD16 port)
{
    return inb(port);
}

/* Write VGA register via I/O port */
void rivaWriteVGA(CARD16 port, CARD8 value)
{
    outb(port, value);
}

/* Determine chip type from boot register */
RivaChipType rivaGetChipType(CARD32 *regBase)
{
    CARD32 boot0 = rivaReadReg(regBase, NV_PMC_OFFSET + NV_PMC_BOOT_0);
    CARD32 chipID = (boot0 & NV_BOOT0_CHIP_ID_MASK);

    if (chipID == NV3_CHIP_ID)
        return RIVA_CHIP_RIVA128;
    else if (chipID == NV4_CHIP_ID)
        return RIVA_CHIP_TNT;
    else if (chipID == NV5_CHIP_ID)
        return RIVA_CHIP_TNT2;

    return RIVA_CHIP_RIVA128;  /* Default */
}

/* Determine framebuffer memory size */
CARD32 rivaGetMemorySize(CARD32 *regBase, RivaChipType chipType)
{
    CARD32 boot0 = rivaReadReg(regBase, NV_PFB_OFFSET + NV_PFB_BOOT_0);
    CARD32 ramAmount = boot0 & NV_PFB_BOOT_0_RAM_AMOUNT;

    switch (ramAmount) {
        case NV_PFB_BOOT_0_RAM_AMOUNT_4MB:
            return 4 * 1024 * 1024;
        case NV_PFB_BOOT_0_RAM_AMOUNT_8MB:
            return 8 * 1024 * 1024;
        case NV_PFB_BOOT_0_RAM_AMOUNT_16MB:
            return 16 * 1024 * 1024;
        case NV_PFB_BOOT_0_RAM_AMOUNT_32MB:
            return 32 * 1024 * 1024;
        default:
            return 4 * 1024 * 1024;
    }
}

/* Lock/unlock extended VGA registers */
void rivaLockUnlockExtended(CARD8 lock)
{
    CARD8 cr11;

    /* Unlock CRTC registers 0-7 */
    outb(VGA_CRTC_INDEX, 0x11);
    cr11 = inb(VGA_CRTC_DATA);
    if (lock)
        outb(VGA_CRTC_DATA, cr11 | 0x80);
    else
        outb(VGA_CRTC_DATA, cr11 & 0x7F);

    /* Lock/Unlock extended registers */
    outb(VGA_CRTC_INDEX, NV_CIO_SR_LOCK_INDEX);
    if (lock)
        outb(VGA_CRTC_DATA, 0x00);
    else
        outb(VGA_CRTC_DATA, NV_VIO_SR_UNLOCK_VALUE);
}
