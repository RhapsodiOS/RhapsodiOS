/* CONFIDENTIAL
 * Copyright (c) 1993-1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * S3GenericModes.h -- internal definitions for S3 Generic driver.
 *
 * History
 * Thu Sep 15 15:16:43 PDT 1994, James C. Lee
 *   Added AT&T 20C505 DAC support
 * Modified for S3 Trio and Virge chipset support
 * Author:  Derek B Clegg	21 May 1993
 * Based on work by Peter Graffagnino, 31 January 1993.
 */

#ifndef S3GENERICMODES_H__
#define S3GENERICMODES_H__

#import <objc/objc.h>
#import <mach/mach.h>
#import <driverkit/displayDefs.h>
#import <driverkit/i386/ioPorts.h>
#import "vgaModes.h"

enum S3AdapterType {
    UnknownAdapter, S3_805, S3_928, S3_Trio32, S3_Trio64, S3_Virge, S3_VirgeDX, S3_VirgeGX,
};
typedef enum S3AdapterType S3AdapterType;

enum DACtype {
    UnknownDAC,
    ATT20C491,		/* AT&T 20C491 or Sierra SC15025. */
    Bt484,		/* BrookTree 484. */
    Bt485,		/* BrookTree 485. */
    Bt485A,		/* BrookTree 485A. */
    ATT20C505		/* AT&T 20C505 */
};
typedef enum DACtype DACtype;

#define ONE_MEGABYTE    (1 << 20)
#define TWO_MEGABYTES   (2 << 20)
#define THREE_MEGABYTES (3 << 20)
#define FOUR_MEGABYTES  (4 << 20)

#define S3_XCRTC_COUNT	48
#define S3_MODE_COUNT	10	/* Maximum refresh rate/mode control pairs. */

struct S3ModeControl {
    unsigned char refreshRate;
    unsigned char modeControl;	/* 0x3D4:42 */
};

struct S3Mode {
    const char *name;		/* The name of this mode. */
    S3AdapterType adapter;	/* The adapter required for this mode. */
    unsigned long memSize;	/* The memory necessary for this mode. */

    struct S3ModeControl modeControl[S3_MODE_COUNT];
    unsigned char advFuncCntl;	/* 0x4AE8 */
    unsigned char xcrtc[S3_XCRTC_COUNT];
    VGAMode vgaData;
};
typedef struct S3Mode S3Mode;

extern const IODisplayInfo S3_805_ModeTable[];
extern const int S3_805_ModeTableCount;
extern const int S3_805_defaultMode;
extern const IODisplayInfo S3_928_ModeTable[];
extern const int S3_928_ModeTableCount;
extern const int S3_928_defaultMode;
extern const IODisplayInfo S3_Trio_ModeTable[];
extern const int S3_Trio_ModeTableCount;
extern const int S3_Trio_defaultMode;
extern const IODisplayInfo S3_Virge_ModeTable[];
extern const int S3_Virge_ModeTableCount;
extern const int S3_Virge_defaultMode;

/* Definitions for the S3 registers that we use. */

#define S3_EXTENDED_REGISTER_MAX	0x7F

/* Indexes for S3 registers. */

#define S3_CHIP_ID_INDEX	0x30	/* Chip ID/REV register. */
#define S3_CHIP_ID_MASK		0xF0
#define S3_CHIP_ID_805		0xA0
#define S3_CHIP_ID_928		0x90
#define S3_CHIP_ID_Trio32	0xB0
#define S3_CHIP_ID_Trio64	0xE0
#define S3_CHIP_ID_Virge	0x50
#define S3_CHIP_ID_VirgeDX	0x60
#define S3_CHIP_ID_VirgeGX	0x70
#define S3_REVISION_MASK	0x0F

#define S3_MEM_CNFG_INDEX	0x31	/* Memory configuration register. */

#define S3_BKWD_2		0x33	/* Backward compatibility register. */

#define S3_CRTR_LOCK_INDEX	0x35	/* CRT register lock register. */

#define S3_CONFG_REG1_INDEX	0x36	/* Configuration 1 register. */
#define S3_CONFG_REG2_INDEX	0x37	/* Configuration 2 register. */
#define S3_BUS_SELECT_MASK	0x03
#define S3_EISA_BUS		0x00
#define S3_LOCAL_BUS		0x01
#define S3_ISA_BUS		0x03
#define S3_MEM_SIZE_MASK	0xC0
#define S3_4_MEG		0
#define S3_3_MEG		(2 << 5)
#define S3_2_MEG		(4 << 5)
#define S3_1_MEG		(6 << 5)
#define S3_HALF_MEG		(7 << 5)

/*  Lock registers */

#define S3_REG_LOCK1		0x38	/* Register lock 1 register. */
#define S3_LOCK1_KEY		0x48
#define S3_REG_LOCK2		0x39	/* Register lock 2 register. */
#define S3_LOCK2_KEY		0xA0

#define S3_DT_EX_POS		0x3B	/* Data transfer execute position
					   register. */
#define S3_IL_RTSTART		0x3C	/* Interlace retrace start register. */

/* System Control Registers */

#define S3_SYS_CNFG		0x40	/* System configuration register. */
#define S3_8514_ACCESS_MASK	0x01
#define S3_8514_ENABLE_ACCESS	0x01
#define S3_8514_DISABLE_ACCESS	0x00
#define S3_WRITE_POST_MASK	0x08
#define S3_WRITE_POST_ENABLE	0x08
#define S3_WRITE_POST_DISABLE	0x00

#define S3_MODE_CTL		0x42	/* Mode control register. */
#define S3_EXT_MODE		0x43	/* Extended mode register. */
#define S3_HGC_MODE		0x45	/* Hardware graphics cursor mode
					   register. */
#define S3_ENB_485		(1 << 5)/* Cursor control enable for Brooktree
					   Bt485 DAC. */

/* System Extension Registers. */

#define S3_EX_SCTL_1		0x50	/* Extended system control 1
					   register. */

#define S3_EX_MCTL_1		0x53	/* Extended memory control 1
					   register. */
#define S3_MMIO_ACCESS_MASK	0x10
#define S3_ENABLE_MMIO_ACCESS	0x10
#define S3_DISABLE_MMIO_ACCESS	0x00

#define S3_EX_MCTL_2		0x54	/* Extended memory control 2
					   register. */
#define S3_PREFETCH_CTRL_MASK	0x07
#define S3_PREFETCH_MAX		0x07

#define S3_EX_DAC_CT		0x55	/* Extended video DAC control
					   register. */
#define S3_DAC_R_SEL_MASK	0x03	/* Mask for extension bits of the
					   RS[1:0] signals for video DAC
					   addressing. */
#define S3_ENB_SID		0x80	/* Enable external SID operation. */
#define S3_HWGC_EXOP		0x20	/* Hardware cursor external operation
					   mode. */

#define S3_LAW_CTL		0x58	/* Linear address window control
					   register. */
#define S3_LAW_SIZE_MASK	0x03
#define S3_LAW_SIZE_64K		0x00
#define S3_LAW_SIZE_1M		0x01
#define S3_LAW_SIZE_2M		0x02
#define S3_LAW_SIZE_4M		0x03
#define S3_PREFETCH_MASK	0x04
#define S3_ENABLE_PREFETCH	0x04
#define S3_DISABLE_PREFETCH	0x00
#define S3_LAW_ENABLE_MASK	0x10
#define S3_ENABLE_LAW		0x10
#define S3_DISABLE_LAW		0x00

#define S3_LAW_POS_HI		0x59	/* Linear address window position
					   registers. */
#define S3_LAW_POS_LO		0x5A

#define S3_GOUT_PORT		0x5C	/* General output port register. */

#define S3_EXT_H_OVF		0x5D	/* Extended horizontal overflow
					   register. */
#define S3_EXT_V_OVF		0x5E	/* Extended vertical overflow
					   register. */

/* Enhanced Command Registers */

#define S3_ADVFUNC_CNTL		0x4AE8	/* Advanced function control
					   register. */
#define S3_GP_STAT		0x9AE8	/* Graphics processor status
					   register. */
#define S3_GP_BUSY_MASK		(1 << 9)

/* DAC registers. */

#define RS_00	0x3C8
#define RS_01	0x3C9
#define RS_02	0x3C6
#define RS_03	0x3C7

/* Register read/write helpers. */

/* Set an index on `port' to `index', and return the byte read from `port + 1'.
 */
static inline int rread(int port, int index)
{
    outb(port, index);
    return (inb(port + 1));
}

/* Use outw to send index and data together.
 */
static inline void rwrite(int port, int index, int value)
{
    outw(port, index | (value << 8));
}

/* Read-modify-write.
 */
static inline void rrmw(int port, int index, int protect, int value)
{
    unsigned int u = rread(port, index);
    rwrite(port,index, (u & protect) | value);
}

static inline void
S3_unlockRegisters(void)
{
    rwrite(VGA_CRTC_INDEX, S3_REG_LOCK1, S3_LOCK1_KEY);
    rwrite(VGA_CRTC_INDEX, S3_REG_LOCK2, S3_LOCK2_KEY);
}

static inline void
S3_lockRegisters(void)
{
    rwrite(VGA_CRTC_INDEX, S3_REG_LOCK1, 0);
    rwrite(VGA_CRTC_INDEX, S3_REG_LOCK2, 0);
}

#endif	/* S3GENERICMODES_H__ */
