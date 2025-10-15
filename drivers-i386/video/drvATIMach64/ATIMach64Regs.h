/*
 * ATIMach64Regs.h - ATI Mach64 Register Definitions
 * Based on XFree86 Mach64 driver register definitions
 */

#ifndef __ATIMACH64REGS_H__
#define __ATIMACH64REGS_H__

/* MMIO Register Offsets */
#define MACH64_MMIOSIZE                 0x0400

/* Configuration and Status Registers */
#define CONFIG_CHIP_ID                  0x00E0  /* Read */
#define CONFIG_STAT0                    0x00E4  /* Read */
#define CONFIG_STAT1                    0x00E8  /* Read */
#define CONFIG_CNTL                     0x00EC  /* Read/Write */
#  define CFG_MEM_AP_LOC                (0x03UL << 0)
#  define CFG_MEM_AP_SIZE               (0x07UL << 2)

/* Scratch Registers (for detection) */
#define SCRATCH_REG0                    0x0020
#define SCRATCH_REG1                    0x0021

/* CRTC Registers */
#define CRTC_H_TOTAL_DISP               0x0000  /* Dword offset 0x00 */
#  define CRTC_H_TOTAL                  (0x01FFUL << 0)
#  define CRTC_H_DISP                   (0x00FFUL << 16)

#define CRTC_H_SYNC_STRT_WID            0x0001  /* Dword offset 0x01 */
#  define CRTC_H_SYNC_STRT              (0x00FFUL << 0)
#  define CRTC_H_SYNC_WID               (0x001FUL << 16)

#define CRTC_V_TOTAL_DISP               0x0002  /* Dword offset 0x02 */
#  define CRTC_V_TOTAL                  (0x07FFUL << 0)
#  define CRTC_V_DISP                   (0x07FFUL << 16)

#define CRTC_V_SYNC_STRT_WID            0x0003  /* Dword offset 0x03 */
#  define CRTC_V_SYNC_STRT              (0x07FFUL << 0)
#  define CRTC_V_SYNC_WID               (0x001FUL << 16)

#define CRTC_OFF_PITCH                  0x0005  /* Dword offset 0x05 */
#  define CRTC_OFFSET                   (0x000FFFFFUL << 0)
#  define CRTC_PITCH                    (0x0FFUL << 22)

#define CRTC_GEN_CNTL                   0x0007  /* Dword offset 0x07 */
#  define CRTC_DBL_SCAN_EN              (1UL << 0)
#  define CRTC_INTERLACE_EN             (1UL << 1)
#  define CRTC_HSYNC_DIS                (1UL << 2)
#  define CRTC_VSYNC_DIS                (1UL << 3)
#  define CRTC_CSYNC_EN                 (1UL << 4)
#  define CRTC_PIX_BY_2_EN              (1UL << 6)
#  define CRTC_DISPLAY_DIS              (1UL << 7)
#  define CRTC_VGA_XOVERSCAN            (1UL << 8)
#  define CRTC_PIX_WIDTH                (0x07UL << 8)
#  define CRTC_BYTE_PIX_ORDER           (1UL << 11)
#  define CRTC_EXT_DISP_EN              (1UL << 24)
#  define CRTC_EN                       (1UL << 25)
#  define CRTC_DISP_REQ_EN_B            (1UL << 26)

#define CRTC_EXT_CNTL                   0x0036  /* Dword offset 0x36 */
#  define VGA_ATI_LINEAR                (1UL << 3)
#  define XCRT_CNT_EN                   (1UL << 6)

/* DAC Registers */
#define DAC_CNTL                        0x0031  /* Dword offset 0x31 */
#  define DAC_EXT_SEL_RS2               (1UL << 0)
#  define DAC_EXT_SEL_RS3               (1UL << 1)
#  define DAC_8BIT_EN                   (1UL << 8)
#  define DAC_PIX_DLY_MASK              (3UL << 9)
#  define DAC_BLANK_ADJ_MASK            (3UL << 11)
#  define DAC1_CLK_SEL                  (1UL << 16)
#  define DAC_PALETTE_ACCESS_CNTL       (1UL << 17)
#  define DAC_FEA_CON_EN                (1UL << 23)
#  define DAC_VGA_ADR_EN                (1UL << 13)
#  define DAC_MASK_ALL                  (0xFFUL << 24)

#define DAC_REGS                        0x0030  /* Dword offset 0x30 */
#define DAC_W_INDEX                     0x00B0  /* Palette write index */
#define DAC_DATA                        0x00B1  /* Palette data */
#define DAC_MASK                        0x00B2  /* Pixel mask */
#define DAC_R_INDEX                     0x00B3  /* Palette read index */

/* Memory Controller Registers */
#define MEM_CNTL                        0x00B2  /* Dword offset 0xB2 */
#  define CTL_MEM_LOWER_APER_ENDIAN     (3UL << 2)
#  define CTL_MEM_UPPER_APER_ENDIAN     (3UL << 4)
#  define CTL_MEM_REFRESH               (7UL << 10)

#define MEM_VGA_WP_SEL                  0x00B4  /* Dword offset 0xB4 */
#define MEM_VGA_RP_SEL                  0x00B5  /* Dword offset 0xB5 */

/* General Control Registers */
#define GEN_TEST_CNTL                   0x00D4  /* Dword offset 0xD4 */
#  define GEN_GUI_EN                    (1UL << 8)

#define BUS_CNTL                        0x00A0  /* Dword offset 0xA0 */
#  define BUS_APER_REG_DIS              (1UL << 4)
#  define BUS_FIFO_ERR_ACK              (1UL << 13)
#  define BUS_HOST_ERR_ACK              (1UL << 14)

/* CONFIG_STAT0 bit definitions */
#define CFG_VGA_EN                      (1UL << 8)
#define CFG_CHIP_EN                     (1UL << 7)
#define CFG_MEM_TYPE_T                  (7UL << 0)  /* Memory type */

/* BIOS Definitions */
#define MACH64_VBIOS_SIZE               0x00010000
#define MACH64_BIOS_BASE                0xC0000

/* Memory Types (from CONFIG_STAT0) */
#define MEM_TYPE_DRAM                   0
#define MEM_TYPE_EDO_DRAM               1
#define MEM_TYPE_PSEUDO_EDO             2
#define MEM_TYPE_SDRAM                  3
#define MEM_TYPE_SGRAM                  4
#define MEM_TYPE_WRAM                   5
#define MEM_TYPE_SDRAM32                6

/* Register read/write macros - Mach64 uses dword offsets */
#define REGOFF(reg)         ((reg) * 4)
#define INREG8(base, reg)   (*(volatile unsigned char *)((base) + REGOFF(reg)))
#define INREG16(base, reg)  (*(volatile unsigned short *)((base) + REGOFF(reg)))
#define INREG(base, reg)    (*(volatile unsigned int *)((base) + REGOFF(reg)))
#define OUTREG8(base, reg, val)  (*(volatile unsigned char *)((base) + REGOFF(reg)) = (val))
#define OUTREG16(base, reg, val) (*(volatile unsigned short *)((base) + REGOFF(reg)) = (val))
#define OUTREG(base, reg, val)   (*(volatile unsigned int *)((base) + REGOFF(reg)) = (val))

#endif /* __ATIMACH64REGS_H__ */
