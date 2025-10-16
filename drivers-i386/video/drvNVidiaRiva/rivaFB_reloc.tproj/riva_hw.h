/*
 * NVIDIA Riva Hardware Abstraction Layer
 */

#ifndef _RIVA_HW_H_
#define _RIVA_HW_H_

#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

#include "riva_reg.h"

#ifndef CARD32
typedef uint32 CARD32;
#endif

#ifndef CARD16
typedef uint16 CARD16;
#endif

#ifndef CARD8
typedef uint8 CARD8;
#endif

/* Riva chip types */
typedef enum {
    RIVA_CHIP_RIVA128 = NV_ARCH_03,
    RIVA_CHIP_TNT     = NV_ARCH_04,
    RIVA_CHIP_TNT2    = NV_ARCH_05
} RivaChipType;

/* Riva hardware state structure */
typedef struct {
    RivaChipType chipType;
    CARD32       chipRevision;
    CARD32       fbSize;           /* Frame buffer size in bytes */
    CARD32       *fbBase;          /* Frame buffer base pointer */
    CARD32       *regBase;         /* Register base pointer */
    int          architecture;     /* NV3, NV4, or NV5 */
} RivaHWRec, *RivaHWPtr;

/* Function prototypes */
extern CARD32 rivaReadReg(CARD32 *regBase, CARD32 offset);
extern void rivaWriteReg(CARD32 *regBase, CARD32 offset, CARD32 value);
extern CARD8 rivaReadVGA(CARD16 port);
extern void rivaWriteVGA(CARD16 port, CARD8 value);
extern RivaChipType rivaGetChipType(CARD32 *regBase);
extern CARD32 rivaGetMemorySize(CARD32 *regBase, RivaChipType chipType);
extern void rivaLockUnlockExtended(CARD8 lock);

#endif /* _RIVA_HW_H_ */
