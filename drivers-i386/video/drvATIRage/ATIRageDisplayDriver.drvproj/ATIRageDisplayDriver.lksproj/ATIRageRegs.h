/*
 * ATIRageRegs.h - ATI Rage Register Definitions
 * Based on XFree86 r128 driver register definitions
 */

#ifndef __ATIRAGEREGS_H__
#define __ATIRAGEREGS_H__

/* MMIO Register Offsets */
#define R128_MMIOSIZE                   0x4000

/* Configuration Registers */
#define R128_CONFIG_MEMSIZE             0x00f8
#define R128_CONFIG_MEMSIZE_EMBEDDED    0x0114
#define R128_CONFIG_APER_SIZE           0x0108
#define R128_CONFIG_REG_1_BASE          0x010c
#define R128_CONFIG_REG_APER_SIZE       0x0110

/* CRTC Registers */
#define R128_CRTC_GEN_CNTL              0x0050
#  define R128_CRTC_DBL_SCAN_EN         (1 <<  0)
#  define R128_CRTC_INTERLACE_EN        (1 <<  1)
#  define R128_CRTC_CSYNC_EN            (1 <<  4)
#  define R128_CRTC_CUR_EN              (1 << 16)
#  define R128_CRTC_CUR_MODE_MASK       (7 << 17)
#  define R128_CRTC_EXT_DISP_EN         (1 << 24)
#  define R128_CRTC_EN                  (1 << 25)
#  define R128_CRTC_DISP_REQ_EN_B       (1 << 26)

#define R128_CRTC_EXT_CNTL              0x0054
#  define R128_CRTC_VGA_XOVERSCAN       (1 <<  0)
#  define R128_VGA_ATI_LINEAR           (1 <<  3)
#  define R128_XCRT_CNT_EN              (1 <<  6)
#  define R128_CRTC_HSYNC_DIS           (1 <<  8)
#  define R128_CRTC_VSYNC_DIS           (1 <<  9)
#  define R128_CRTC_DISPLAY_DIS         (1 << 10)

#define R128_CRTC_H_TOTAL_DISP          0x0200
#define R128_CRTC_H_SYNC_STRT_WID       0x0204
#define R128_CRTC_V_TOTAL_DISP          0x0208
#define R128_CRTC_V_SYNC_STRT_WID       0x020c
#define R128_CRTC_OFFSET                0x0224
#define R128_CRTC_OFFSET_CNTL           0x0228
#define R128_CRTC_PITCH                 0x022c

/* DAC Registers */
#define R128_DAC_CNTL                   0x0058
#  define R128_DAC_RANGE_CNTL           (3 <<  0)
#  define R128_DAC_BLANKING             (1 <<  2)
#  define R128_DAC_CRT_SEL_CRTC2        (1 <<  4)
#  define R128_DAC_PALETTE_ACC_CTL      (1 <<  5)
#  define R128_DAC_8BIT_EN              (1 <<  8)
#  define R128_DAC_VGA_ADR_EN           (1 << 13)
#  define R128_DAC_MASK_ALL             (0xff << 24)

#define R128_PALETTE_INDEX              0x00b0
#define R128_PALETTE_DATA               0x00b4
#define R128_PALETTE_30_DATA            0x00b8

/* Memory Controller Registers */
#define R128_MEM_CNTL                   0x0140
#  define R128_MEM_CTLR_STATUS_IDLE     (1 << 0)
#  define R128_MEM_NUM_CHANNELS_MASK    0x00000001
#  define R128_MEM_USE_B_CH_ONLY        0x00000002

/* General Control Registers */
#define R128_GEN_RESET_CNTL             0x00f0
#  define R128_SOFT_RESET_GUI           (1 <<  0)
#  define R128_SOFT_RESET_VCLK          (1 <<  8)
#  define R128_SOFT_RESET_PCLK          (1 <<  9)
#  define R128_SOFT_RESET_ECP           (1 << 10)
#  define R128_SOFT_RESET_DISPENG_XCLK  (1 << 11)

#define R128_GEN_TEST_CNTL              0x00d4

/* BIOS Definitions */
#define R128_VBIOS_SIZE                 0x00010000
#define R128_BIOS_BASE                  0xC0000

/* Memory Types */
#define R128_MEM_SDR_SGRAM              0
#define R128_MEM_SDR_SGRAM_2_1          1
#define R128_MEM_DDR_SGRAM              2

/* Cursor Registers */
#define R128_CUR_OFFSET                 0x0260
#define R128_CUR_HORZ_VERT_POSN         0x0264
#define R128_CUR_HORZ_VERT_OFF          0x0268
#define R128_CUR_CLR0                   0x026c
#define R128_CUR_CLR1                   0x0270

/* Register read/write macros */
#define INREG8(addr)        (*(volatile unsigned char *)(addr))
#define INREG16(addr)       (*(volatile unsigned short *)(addr))
#define INREG(addr)         (*(volatile unsigned int *)(addr))
#define OUTREG8(addr, val)  (*(volatile unsigned char *)(addr) = (val))
#define OUTREG16(addr, val) (*(volatile unsigned short *)(addr) = (val))
#define OUTREG(addr, val)   (*(volatile unsigned int *)(addr) = (val))

#endif /* __ATIRAGEREGS_H__ */
