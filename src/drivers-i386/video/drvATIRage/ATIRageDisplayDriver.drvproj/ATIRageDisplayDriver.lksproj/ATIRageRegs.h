#ifndef __ATIRAGEREGS_H__
#define __ATIRAGEREGS_H__

/* MMIO register offsets recovered from drvATIRage instruction operands.
 * register_base_address points at framebuffer + 0x7ffc00. Names describe
 * observed uses; offsets are the parity-critical contract. */
#define ATI_FRAMEBUFFER_SIZE          0x00800000
#define ATI_REGISTER_WINDOW_OFFSET    0x007ffc00
#define ATI_FIFO_STATUS               0x000310
#define ATI_GUI_STATUS                0x000338
#define ATI_GUI_REG_182               0x0002d8
#define ATI_GUI_REG_109               0x0001b4
#define ATI_GUI_REG_076               0x000130
#define ATI_SRC_Y_X                   0x00018c
#define ATI_SRC_WIDTH_HEIGHT          0x000198
#define ATI_DST_Y_X                   0x00010c
#define ATI_DST_WIDTH_HEIGHT          0x000118
#define ATI_BASE_PORT_OFFSET_D0       0x0000d0
#define ATI_BASE_PORT_OFFSET_A0       0x0000a0
#define ATI_RESET_BIT                 0x00000100
#define ATI_GUI_RESET_MASK            0x00ae0000
#define ATI_FIFO_MAX                  0x00008000
#define ATI_IDLE_TIMEOUT              0x0007a120

/* Additional GUI register offsets are retained by their observed index.
 * Semantic names are added only when supported by the reference's callers. */
#define ATI_GUI_REG_064               0x000100
#define ATI_GUI_REG_067               0x00010c
#define ATI_GUI_REG_069               0x000114
#define ATI_GUI_REG_070               0x000118
#define ATI_GUI_REG_073               0x000124
#define ATI_GUI_REG_074               0x000128
#define ATI_GUI_REG_075               0x00012c
#define ATI_GUI_REG_096               0x000180
#define ATI_GUI_REG_099               0x00018c
#define ATI_GUI_REG_102               0x000198
#define ATI_GUI_REG_105               0x0001a4
#define ATI_GUI_REG_108               0x0001b0
#define ATI_GUI_REG_109               0x0001b4
#define ATI_GUI_REG_160               0x000280
#define ATI_GUI_REG_161               0x000284
#define ATI_GUI_REG_162               0x000288
#define ATI_GUI_REG_168               0x0002a0
#define ATI_GUI_REG_169               0x0002a4
#define ATI_GUI_REG_171               0x0002ac
#define ATI_GUI_REG_172               0x0002b0
#define ATI_GUI_REG_176               0x0002c0
#define ATI_GUI_REG_177               0x0002c4
#define ATI_GUI_REG_178               0x0002c8
#define ATI_GUI_REG_181               0x0002d4

/* The original C routines use repository DriverKit port-I/O primitives.
 * Keep their widths and delay behavior in the callers. */
#import <driverkit/i386/ioPorts.h>

#define ATI_INREG8(base, offset)       (*(volatile unsigned char *)((base) + (offset)))
#define ATI_INREG16(base, offset)      (*(volatile unsigned short *)((base) + (offset)))
#define ATI_INREG32(base, offset)      (*(volatile unsigned int *)((base) + (offset)))
#define ATI_OUTREG8(base, offset, val) (ATI_INREG8((base), (offset)) = (val))
#define ATI_OUTREG16(base, offset, val) (ATI_INREG16((base), (offset)) = (val))
#define ATI_OUTREG32(base, offset, val) (ATI_INREG32((base), (offset)) = (val))

#endif /* __ATIRAGEREGS_H__ */
