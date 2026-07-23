/* CONFIDENTIAL
 * Copyright (c) 1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * VGAModes.h -- VGA mode definitions
 *
 * Created for RhapsodiOS VGA support
 */

#ifndef VGAMODES_H__
#define VGAMODES_H__

#import <driverkit/displayDefs.h>

/* VGA adapter types */
typedef enum {
    VGA_GENERIC,
    VGA_SVGA
} VGAAdapterType;

/* VGA mode structure */
typedef struct _VGAMode {
    const char *name;
    IODisplayInfo displayInfo;
    unsigned long memSize;
    unsigned char *registerValues;
} VGAMode;

/* External mode tables */
extern const VGAMode vgaModes[];
extern const unsigned int vgaModeCount;

#endif	/* VGAMODES_H__ */
