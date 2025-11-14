/*
 * riva_timing.c - CRTC timing calculation and programming
 */

#include "riva_timing.h"
#include "riva_reg.h"

/* Predefined standard VESA mode timings */
const RivaModeTimingRec rivaModeTimings[] = {
    /* 640x480 @ 60Hz */
    {
        640, 480, 60, 25175,
        800, 640, 640, 800,  /* hTotal, hDisplay, hBlankStart, hBlankEnd */
        656, 752,            /* hSyncStart, hSyncEnd */
        525, 480, 480, 525,  /* vTotal, vDisplay, vBlankStart, vBlankEnd */
        490, 492,            /* vSyncStart, vSyncEnd */
        0                    /* flags - negative hsync/vsync */
    },
    /* 800x600 @ 60Hz */
    {
        800, 600, 60, 40000,
        1056, 800, 800, 1056,
        840, 968,
        628, 600, 600, 628,
        601, 605,
        RIVA_MODE_HSYNC_POSITIVE | RIVA_MODE_VSYNC_POSITIVE
    },
    /* 1024x768 @ 60Hz */
    {
        1024, 768, 60, 65000,
        1344, 1024, 1024, 1344,
        1048, 1184,
        806, 768, 768, 806,
        771, 777,
        0
    },
    /* 1152x864 @ 60Hz */
    {
        1152, 864, 60, 81600,
        1520, 1152, 1152, 1520,
        1216, 1360,
        895, 864, 864, 895,
        865, 868,
        0
    },
    /* 1280x1024 @ 60Hz */
    {
        1280, 1024, 60, 108000,
        1688, 1280, 1280, 1688,
        1328, 1440,
        1066, 1024, 1024, 1066,
        1025, 1028,
        RIVA_MODE_HSYNC_POSITIVE | RIVA_MODE_VSYNC_POSITIVE
    },
    /* 1600x1200 @ 60Hz */
    {
        1600, 1200, 60, 162000,
        2160, 1600, 1600, 2160,
        1664, 1856,
        1250, 1200, 1200, 1250,
        1201, 1204,
        RIVA_MODE_HSYNC_POSITIVE | RIVA_MODE_VSYNC_POSITIVE
    }
};

const int rivaModeTimingsCount = sizeof(rivaModeTimings) / sizeof(RivaModeTimingRec);

/*
 * Calculate mode timings using simplified VESA GTF
 */
void rivaCalculateTimings(int width, int height, int refresh, RivaModeTimingPtr timing)
{
    /* Check if we have a predefined timing for this mode */
    for (int i = 0; i < rivaModeTimingsCount; i++) {
        if (rivaModeTimings[i].width == width &&
            rivaModeTimings[i].height == height &&
            rivaModeTimings[i].refreshRate == refresh) {
            *timing = rivaModeTimings[i];
            return;
        }
    }

    /* Fallback: use simple calculation for non-standard modes */
    timing->width = width;
    timing->height = height;
    timing->refreshRate = refresh;

    /* Horizontal timing (add 25% blanking) */
    timing->hDisplay = width;
    timing->hBlankStart = width;
    timing->hSyncStart = width + (width / 8);
    timing->hSyncEnd = timing->hSyncStart + (width / 16);
    timing->hBlankEnd = width + (width / 4);
    timing->hTotal = timing->hBlankEnd;

    /* Vertical timing (add 5% blanking) */
    timing->vDisplay = height;
    timing->vBlankStart = height;
    timing->vSyncStart = height + 3;
    timing->vSyncEnd = timing->vSyncStart + 6;
    timing->vBlankEnd = height + (height / 20);
    timing->vTotal = timing->vBlankEnd;

    /* Estimate pixel clock (in kHz) */
    timing->pixelClock = (timing->hTotal * timing->vTotal * refresh) / 1000;

    timing->flags = 0;
}

/*
 * Program CRTC registers with timing values
 */
void rivaProgramCRTC(CARD32 *regBase, RivaModeTimingPtr timing, int pitch, int bpp)
{
    CARD8 cr;
    int i;

    /* Unlock CRTC registers */
    outb(VGA_CRTC_INDEX, 0x11);
    cr = inb(VGA_CRTC_DATA);
    outb(VGA_CRTC_DATA, cr & 0x7F);

    /* Horizontal Total */
    outb(VGA_CRTC_INDEX, 0x00);
    outb(VGA_CRTC_DATA, (timing->hTotal / 8) - 5);

    /* Horizontal Display End */
    outb(VGA_CRTC_INDEX, 0x01);
    outb(VGA_CRTC_DATA, (timing->hDisplay / 8) - 1);

    /* Horizontal Blank Start */
    outb(VGA_CRTC_INDEX, 0x02);
    outb(VGA_CRTC_DATA, timing->hBlankStart / 8);

    /* Horizontal Blank End */
    outb(VGA_CRTC_INDEX, 0x03);
    cr = inb(VGA_CRTC_DATA) & 0xE0;  /* Preserve bits 7-5 */
    outb(VGA_CRTC_DATA, cr | ((timing->hBlankEnd / 8) & 0x1F));

    /* Horizontal Sync Start */
    outb(VGA_CRTC_INDEX, 0x04);
    outb(VGA_CRTC_DATA, timing->hSyncStart / 8);

    /* Horizontal Sync End */
    outb(VGA_CRTC_INDEX, 0x05);
    cr = inb(VGA_CRTC_DATA) & 0x60;  /* Preserve bits 6-5 */
    outb(VGA_CRTC_DATA, cr | ((timing->hSyncEnd / 8) & 0x1F));

    /* Vertical Total */
    outb(VGA_CRTC_INDEX, 0x06);
    outb(VGA_CRTC_DATA, timing->vTotal & 0xFF);

    /* Overflow register */
    outb(VGA_CRTC_INDEX, 0x07);
    cr = 0;
    if (timing->vTotal & 0x100) cr |= 0x01;
    if (timing->vTotal & 0x200) cr |= 0x20;
    if (timing->vDisplay & 0x100) cr |= 0x02;
    if (timing->vDisplay & 0x200) cr |= 0x40;
    if (timing->vSyncStart & 0x100) cr |= 0x04;
    if (timing->vSyncStart & 0x200) cr |= 0x80;
    if (timing->vBlankStart & 0x100) cr |= 0x08;
    if (timing->vBlankStart & 0x200) cr |= 0x20;
    outb(VGA_CRTC_DATA, cr);

    /* Maximum Scan Line */
    outb(VGA_CRTC_INDEX, 0x09);
    cr = inb(VGA_CRTC_DATA) & 0x60;
    if (timing->vBlankStart & 0x200) cr |= 0x20;
    outb(VGA_CRTC_DATA, cr);

    /* Vertical Sync Start */
    outb(VGA_CRTC_INDEX, 0x10);
    outb(VGA_CRTC_DATA, timing->vSyncStart & 0xFF);

    /* Vertical Sync End */
    outb(VGA_CRTC_INDEX, 0x11);
    cr = inb(VGA_CRTC_DATA) & 0xF0;
    outb(VGA_CRTC_DATA, cr | (timing->vSyncEnd & 0x0F));

    /* Vertical Display End */
    outb(VGA_CRTC_INDEX, 0x12);
    outb(VGA_CRTC_DATA, timing->vDisplay & 0xFF);

    /* Offset (pitch) */
    outb(VGA_CRTC_INDEX, 0x13);
    outb(VGA_CRTC_DATA, (pitch / 8) & 0xFF);

    /* Underline Location */
    outb(VGA_CRTC_INDEX, 0x14);
    outb(VGA_CRTC_DATA, 0x00);

    /* Vertical Blank Start */
    outb(VGA_CRTC_INDEX, 0x15);
    outb(VGA_CRTC_DATA, timing->vBlankStart & 0xFF);

    /* Vertical Blank End */
    outb(VGA_CRTC_INDEX, 0x16);
    outb(VGA_CRTC_DATA, timing->vBlankEnd & 0xFF);

    /* CRTC Mode Control */
    outb(VGA_CRTC_INDEX, 0x17);
    outb(VGA_CRTC_DATA, 0xE3);

    /* Line Compare */
    outb(VGA_CRTC_INDEX, 0x18);
    outb(VGA_CRTC_DATA, 0xFF);

    /* Extended registers for NVidia */
    /* Extended offset bits */
    outb(VGA_CRTC_INDEX, NV_CIO_CRE_RPC0_INDEX);
    outb(VGA_CRTC_DATA, ((pitch / 8) >> 8) & 0xFF);

    /* Pixel format */
    outb(VGA_CRTC_INDEX, NV_CIO_CRE_PIXEL_INDEX);
    if (bpp == 32)
        outb(VGA_CRTC_DATA, 0x03);  /* 32bpp packed */
    else if (bpp == 16)
        outb(VGA_CRTC_DATA, 0x02);  /* 16bpp */
    else
        outb(VGA_CRTC_DATA, 0x01);  /* 8bpp */

    /* Extended vertical timing bits */
    outb(VGA_CRTC_INDEX, NV_CIO_CRE_HEB__INDEX);
    cr = 0;
    if (timing->vTotal & 0x400) cr |= 0x01;
    if (timing->vDisplay & 0x400) cr |= 0x02;
    if (timing->vSyncStart & 0x400) cr |= 0x04;
    if (timing->vBlankStart & 0x400) cr |= 0x08;
    outb(VGA_CRTC_DATA, cr);
}

/*
 * Program video PLL for pixel clock
 * This is a simplified version - a real implementation would need
 * to calculate M, N, P values for the PLL
 */
void rivaProgramVPLL(CARD32 *regBase, int pixelClock, RivaChipType chipType)
{
    CARD32 m, n, p;
    CARD32 coeff;

    /* Simple PLL calculation for common clocks */
    /* These values are approximations - real hardware would need
       precise calculation based on reference clock */

    if (pixelClock <= 25200) {
        /* 25.175 MHz (640x480@60) */
        m = 7; n = 98; p = 3;
    } else if (pixelClock <= 40000) {
        /* 40 MHz (800x600@60) */
        m = 5; n = 83; p = 3;
    } else if (pixelClock <= 65000) {
        /* 65 MHz (1024x768@60) */
        m = 7; n = 172; p = 3;
    } else if (pixelClock <= 81600) {
        /* 81.6 MHz (1152x864@60) */
        m = 6; n = 163; p = 3;
    } else if (pixelClock <= 108000) {
        /* 108 MHz (1280x1024@60) */
        m = 4; n = 108; p = 3;
    } else {
        /* 162 MHz (1600x1200@60) */
        m = 4; n = 162; p = 3;
    }

    /* Combine into coefficient register format */
    coeff = (p << 16) | (n << 8) | m;

    /* Write to VPLL coefficient register */
    rivaWriteReg(regBase, NV_PRAMDAC_OFFSET + NV_PRAMDAC_VPLL_COEFF, coeff);

    /* Select VPLL */
    rivaWriteReg(regBase, NV_PRAMDAC_OFFSET + NV_PRAMDAC_PLL_COEFF_SELECT, 0x00010100);

    /* Small delay for PLL to stabilize */
    for (int i = 0; i < 10000; i++) {
        inb(VGA_IS1_RC);  /* Dummy read for delay */
    }
}
