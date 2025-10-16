/*
 * voodooVSA_reg.h -- 3Dfx Voodoo3 register definitions
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 *
 * 3Dfx Voodoo3 Graphics Controller Register Definitions
 * Based on the XFree86/Xorg tdfx driver and Banshee/Voodoo3 specs
 */

#ifndef VOODOO_VSA_REG_H
#define VOODOO_VSA_REG_H

/* Basic types */
typedef unsigned char  CARD8;
typedef unsigned short CARD16;
typedef unsigned int   CARD32;

/*
 * PCI Configuration Space IDs (from XFree86 tdfx driver)
 */
#define PCI_VENDOR_3DFX         0x121a  /* 3Dfx Interactive */
#define PCI_CHIP_BANSHEE        0x0003  /* Banshee */
#define PCI_CHIP_VOODOO3        0x0005  /* Voodoo3 */
#define PCI_CHIP_VOODOO5        0x0009  /* Voodoo5 */

/* Legacy definitions for compatibility */
#define VOODOO_VSA_VENDOR_ID       PCI_VENDOR_3DFX
#define VOODOO_VSA_DEVICE_ID       PCI_CHIP_VOODOO3
#define BANSHEE_DEVICE_ID       PCI_CHIP_BANSHEE

/*
 * PCI Configuration Space Registers
 */
#define CFG_PCI_INIT_ENABLE     0x40
#define CFG_PCI_BUS_SNOOP0      0x44
#define CFG_PCI_BUS_SNOOP1      0x48

/*
 * Memory-Mapped I/O Register Offsets (from tdfxdefs.h)
 * Base registers start at offset 0x0
 */

/* Core Registers (0x00 - 0x3F) */
#define SST_STATUS              0x00    /* Status register */
#define SST_PCIINIT0            0x04    /* PCI Init 0 */
#define SST_SIPMONITOR          0x08    /* SIP Monitor */
#define SST_LFBMEMORYCONFIG     0x0C    /* LFB Memory Config */
#define SST_MISCINIT0           0x10    /* Misc Init 0 */
#define SST_MISCINIT1           0x14    /* Misc Init 1 */
#define SST_DRAMINIT0           0x18    /* DRAM Init 0 */
#define SST_DRAMINIT1           0x1C    /* DRAM Init 1 */
#define SST_AGPINIT             0x20    /* AGP Init */
#define SST_TMUGBEINIT          0x24    /* TMU/GBE Init */
#define SST_VGAINIT0            0x28    /* VGA Init 0 */
#define SST_VGAINIT1            0x2C    /* VGA Init 1 */
#define SST_DRAMCOMMAND         0x30    /* DRAM Command */
#define SST_DRAMDATA            0x34    /* DRAM Data */

/* PLL and DAC Registers (0x40 - 0x5F) */
#define SST_PLLCTRL0            0x40    /* PLL Control 0 */
#define SST_PLLCTRL1            0x44    /* PLL Control 1 */
#define SST_PLLCTRL2            0x48    /* PLL Control 2 */
#define SST_DACMODE             0x4C    /* DAC Mode */
#define SST_DACADDR             0x50    /* DAC Address */
#define SST_DACDATA             0x54    /* DAC Data */

/* Video and Cursor Registers (0x5C - 0xA4) */
#define SST_VIDPROCCFG          0x5C    /* Video Processor Config */
#define SST_HWCURPATADDR        0x60    /* HW Cursor Pattern Address */
#define SST_HWCURLOC            0x64    /* HW Cursor Location */
#define SST_HWCURC0             0x68    /* HW Cursor Color 0 */
#define SST_HWCURC1             0x6C    /* HW Cursor Color 1 */
#define SST_VIDINFORMAT         0x70    /* Video Input Format */
#define SST_VIDINSTATUS         0x74    /* Video Input Status */
#define SST_VIDSERPARPORT       0x78    /* Video Serial/Parallel Port */
#define SST_VIDINXDELTA         0x7C    /* Video Input X Delta */
#define SST_VIDININITERR        0x80    /* Video Input Init Error */
#define SST_VIDINYDELTA         0x84    /* Video Input Y Delta */
#define SST_VIDPIXBUFTHOLD      0x88    /* Video Pixel Buffer Threshold */
#define SST_VIDCHRMIN           0x8C    /* Video Chroma Min */
#define SST_VIDCHRMAX           0x90    /* Video Chroma Max */
#define SST_VIDCURLIN           0x94    /* Video Current Line */
#define SST_VIDSCREENSIZE       0x98    /* Video Screen Size */
#define SST_VIDOVRSTARTCRD      0x9C    /* Video Overlay Start Coords */
#define SST_VIDOVRENDCRD        0xA0    /* Video Overlay End Coords */
#define SST_VIDOVRDUDX          0xA4    /* Video Overlay DuDx */
#define SST_VIDOVRDUDXOFF       0xA8    /* Video Overlay DuDx Offset */
#define SST_VIDOVRDVDY          0xAC    /* Video Overlay DvDy */
#define SST_VIDOVRDVDYOFF       0xB0    /* Video Overlay DvDy Offset */
#define SST_VIDDESKTOPSTARTADDR 0xE4    /* Desktop Start Address */
#define SST_VIDDESKTOPOVERLAYSTRIDE 0xE8 /* Desktop/Overlay Stride */

/* 2D Engine Registers (Offset: 0x100000 from base) */
#define SST_2D_OFFSET           0x100000

#define SST_2D_CLIP0MIN         (SST_2D_OFFSET + 0x08)
#define SST_2D_CLIP0MAX         (SST_2D_OFFSET + 0x0C)
#define SST_2D_DSTBASEADDR      (SST_2D_OFFSET + 0x10)
#define SST_2D_DSTFORMAT        (SST_2D_OFFSET + 0x14)
#define SST_2D_SRCCOLORKEYMIN   (SST_2D_OFFSET + 0x18)
#define SST_2D_SRCCOLORKEYMAX   (SST_2D_OFFSET + 0x1C)
#define SST_2D_DSTCOLORKEYMIN   (SST_2D_OFFSET + 0x20)
#define SST_2D_DSTCOLORKEYMAX   (SST_2D_OFFSET + 0x24)
#define SST_2D_BRESOFFSET0      (SST_2D_OFFSET + 0x28)
#define SST_2D_BRESOFFSET1      (SST_2D_OFFSET + 0x2C)
#define SST_2D_BRES_ERROR0      (SST_2D_OFFSET + 0x30)
#define SST_2D_BRES_ERROR1      (SST_2D_OFFSET + 0x34)
#define SST_2D_ROP              (SST_2D_OFFSET + 0x38)
#define SST_2D_SRCBASEADDR      (SST_2D_OFFSET + 0x44)
#define SST_2D_COMMANDEXTRA     (SST_2D_OFFSET + 0x48)
#define SST_2D_LINESTIPPLE      (SST_2D_OFFSET + 0x4C)
#define SST_2D_LINESTYLE        (SST_2D_OFFSET + 0x50)
#define SST_2D_PATTERN0         (SST_2D_OFFSET + 0x54)
#define SST_2D_PATTERN1         (SST_2D_OFFSET + 0x58)
#define SST_2D_CLIP1MIN         (SST_2D_OFFSET + 0x5C)
#define SST_2D_CLIP1MAX         (SST_2D_OFFSET + 0x60)
#define SST_2D_SRCFORMAT        (SST_2D_OFFSET + 0x64)
#define SST_2D_SRCSIZE          (SST_2D_OFFSET + 0x68)
#define SST_2D_SRCXY            (SST_2D_OFFSET + 0x6C)
#define SST_2D_COLORBACK        (SST_2D_OFFSET + 0x70)
#define SST_2D_COLORFORE        (SST_2D_OFFSET + 0x74)
#define SST_2D_DSTSIZE          (SST_2D_OFFSET + 0x78)
#define SST_2D_DSTXY            (SST_2D_OFFSET + 0x7C)
#define SST_2D_COMMAND          (SST_2D_OFFSET + 0x80)
#define SST_2D_LAUNCH           (SST_2D_OFFSET + 0x80)

/* Legacy register name compatibility */
#define VOODOO_VSA_STATUS          SST_STATUS
#define VOODOO_VSA_PLLCTRL0        SST_PLLCTRL0
#define VOODOO_VSA_PLLCTRL1        SST_PLLCTRL1
#define VOODOO_VSA_DACMODE         SST_DACMODE
#define VOODOO_VSA_DACADDR         SST_DACADDR
#define VOODOO_VSA_DACDATA         SST_DACDATA
#define VOODOO_VSA_VIDPROCCFG      SST_VIDPROCCFG
#define VOODOO_VSA_VIDSCREENSIZE   SST_VIDSCREENSIZE
#define VOODOO_VSA_VIDDESKTOPSTARTADDR SST_VIDDESKTOPSTARTADDR
#define VOODOO_VSA_VIDDESKTOPOVERLAYSTRIDE SST_VIDDESKTOPOVERLAYSTRIDE
#define VOODOO_VSA_VGAINIT0        SST_VGAINIT0
#define VOODOO_VSA_VGAINIT1        SST_VGAINIT1

/*
 * Video Processor Configuration Register Bits
 */
#define VOODOO_VSA_VIDCFG_VIDPROC_ENABLE     (1 << 0)
#define VOODOO_VSA_VIDCFG_CURS_X11           (1 << 1)
#define VOODOO_VSA_VIDCFG_HALF_MODE          (1 << 4)
#define VOODOO_VSA_VIDCFG_DESK_ENABLE        (1 << 7)
#define VOODOO_VSA_VIDCFG_2X_MODE            (1 << 26)
#define VOODOO_VSA_VIDCFG_HWCURSOR_ENABLE    (1 << 27)

/*
 * Desktop Video Format (bits 0-2 of vidDesktopOverlayStride)
 */
#define VOODOO_VSA_VIDFMT_8BPP     0       /* 8 bits per pixel */
#define VOODOO_VSA_VIDFMT_16BPP    1       /* 16 bits per pixel (565) */
#define VOODOO_VSA_VIDFMT_24BPP    2       /* 24 bits per pixel */
#define VOODOO_VSA_VIDFMT_32BPP    3       /* 32 bits per pixel */

/*
 * DAC Mode Register Bits
 */
#define VOODOO_VSA_DACMODE_2X      (1 << 0)

/*
 * Status Register Bits
 */
#define VOODOO_VSA_STATUS_RETRACE  (1 << 6)  /* Vertical retrace */
#define VOODOO_VSA_STATUS_BUSY     (1 << 9)  /* 2D engine busy */

/*
 * VGA Init0 Register Bits
 */
#define VOODOO_VSA_VGAINIT0_EXTENDED       (1 << 6)  /* Extended VGA mode */
#define VOODOO_VSA_VGAINIT0_WAKEUP_3C3     (1 << 8)  /* VGA wakeup select */
#define VOODOO_VSA_VGAINIT0_ENABLE_ALT     (1 << 13) /* Enable alt readback */

/*
 * 2D Command Register Values
 */
#define VOODOO_VSA_2D_NOP          0x0
#define VOODOO_VSA_2D_SCREEN_TO_SCREEN_BLT  0x1
#define VOODOO_VSA_2D_HOST_TO_SCREEN_BLT    0x4
#define VOODOO_VSA_2D_RECTFILL     0x5
#define VOODOO_VSA_2D_LINE         0x6

/*
 * Memory Space Sizes and Offsets
 */
#define VOODOO_VSA_REG_SIZE        0x1000000   /* 16MB register space */
#define VOODOO_VSA_FB_OFFSET       0x0         /* Frame buffer at offset 0 */
#define VOODOO_VSA_REG_OFFSET      0x0         /* Registers at base */

/*
 * Standard video modes support
 */
#define VOODOO_VSA_MAX_WIDTH       1600
#define VOODOO_VSA_MAX_HEIGHT      1200

/*
 * PLL Reference Frequency
 */
#define VOODOO_VSA_REF_FREQ        14318       /* Reference frequency in kHz */

#endif /* VOODOO_VSA_REG_H */
