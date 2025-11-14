/*
 * voodooVSA_reg_ext.h -- Extended Voodoo3 register bit definitions
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * Additional constants based on XFree86/Xorg tdfx driver
 */

#ifndef VOODOO_VSA_REG_EXT_H
#define VOODOO_VSA_REG_EXT_H

#include "voodooVSA_reg.h"

/*
 * Additional SST Register Bits (from XFree86 tdfx driver)
 */

/* SST_VIDPROCCFG bits */
#define SST_VIDCFG_VIDPROC_ENABLE     (1 << 0)
#define SST_VIDCFG_CURS_X11           (1 << 1)
#define SST_VIDCFG_HALF_MODE          (1 << 4)
#define SST_VIDCFG_DESK_ENABLE        (1 << 7)
#define SST_VIDCFG_2X_MODE            (1 << 26)
#define SST_VIDCFG_HWCURSOR_ENABLE    (1 << 27)
#define SST_VIDCFG_PIXFMT_SHIFT       18

/* SST_VGAINIT0 bits */
#define SST_VGAINIT0_EXTENDED         (1 << 6)
#define SST_VGAINIT0_8BIT_DAC         (1 << 2)
#define SST_VGAINIT0_EXT_TIMING       (1 << 6)
#define SST_VGAINIT0_WAKEUP_3C3       (1 << 8)
#define SST_VGAINIT0_ENABLE_ALT       (1 << 13)
#define SST_VGAINIT0_ENABLE_2DFIFO    (1 << 11)

/* SST_DRAMINIT0 bits (for memory detection) */
#define SST_SGRAM_TYPE                (1 << 27)
#define SST_SGRAM_TYPE_MASK           (1 << 27)
#define SST_SGRAM_TYPE_SDRAM          0
#define SST_SGRAM_TYPE_SGRAM          (1 << 27)
#define SST_MEM_SIZE_MASK             0x03

/* SST_MISCINIT1 bits */
#define SST_MISCINIT1_2DBLOCK_ENABLE  (1 << 15)

/* SST_STATUS bits */
#define SST_STATUS_FBI_BUSY           (1 << 7)
#define SST_STATUS_TREX_BUSY          (1 << 8)
#define SST_STATUS_BUSY               (1 << 9)

/* 2D Command bits */
#define SST_2D_CMD_NOP                0x0
#define SST_2D_CMD_BITBLT             0x1
#define SST_2D_CMD_FILLRECT           0x5
#define SST_2D_CMD_LINE               0x6
#define SST_2D_CMD_HOSTDATA_BLT       0x4

/* 2D ROP (Raster Operation) values */
#define SST_2D_ROP_COPY               0xCC  /* Dest = Src */
#define SST_2D_ROP_INVERT             0x55  /* Dest = NOT Dest */
#define SST_2D_ROP_XOR                0x66  /* Dest = Src XOR Dest */
#define SST_2D_ROP_AND                0x88  /* Dest = Src AND Dest */
#define SST_2D_ROP_OR                 0xEE  /* Dest = Src OR Dest */

/*
 * PLL calculation constants (from CalcPLL in tdfx driver)
 * Formula: f_out = REFFREQ * (n+2) / ((m+2) * (1<<k))
 */
#define PLL_N_MASK                    0xFF
#define PLL_M_MASK                    0x3F
#define PLL_K_MASK                    0x03
#define PLL_N_SHIFT                   8
#define PLL_M_SHIFT                   2
#define PLL_K_SHIFT                   16

/* Memory size constants */
#define VOODOO_VSA_MEM_2MB               (2 * 1024 * 1024)
#define VOODOO_VSA_MEM_4MB               (4 * 1024 * 1024)
#define VOODOO_VSA_MEM_8MB               (8 * 1024 * 1024)
#define VOODOO_VSA_MEM_16MB              (16 * 1024 * 1024)

/* Pixel format values for SST_VIDDESKTOPOVERLAYSTRIDE */
#define SST_OVERLAY_PIXEL_RGB565      1
#define SST_OVERLAY_PIXEL_RGB24       2
#define SST_OVERLAY_PIXEL_RGB32       3

/* MMIO region sizes */
#define VOODOO_VSA_MMIO_SIZE             0x2000000  /* 32MB (BAR0) */
#define VOODOO_VSA_IO_REG_SIZE           0x100      /* I/O registers */

/*
 * Hardware cursor constants
 */
#define VOODOO_VSA_CURSOR_SIZE           64         /* 64x64 pixels */
#define VOODOO_VSA_CURSOR_BYTES          1024       /* 64x64 * 2 bits/pixel / 8 */

/*
 * DAC Mode register bits
 */
#define SST_DACMODE_BLANK             (1 << 3)   /* Blank display */

/*
 * DPMS (Display Power Management Signaling) states
 */
#define DPMS_STATE_ON                 0          /* Full power */
#define DPMS_STATE_STANDBY            1          /* Blanked, quick wake */
#define DPMS_STATE_SUSPEND            2          /* Suspended, slower wake */
#define DPMS_STATE_OFF                3          /* Off, slowest wake */

#endif /* VOODOO_VSA_REG_EXT_H */
