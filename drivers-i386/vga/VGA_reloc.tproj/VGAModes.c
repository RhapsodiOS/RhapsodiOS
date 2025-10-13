/* Copyright (c) 1996 by NeXT Software, Inc.
 * All rights reserved.
 *
 * VGAModes.c -- VGA display mode definitions
 *
 * Created for RhapsodiOS VGA support
 */

#import "VGAModes.h"

/* Standard VGA 640x480 @ 60Hz, 2 bits per pixel (4 colors) */
const VGAMode vgaModes[] = {
    {
        "640x480 @ 60Hz BW.2",
        {
            640,                        /* width */
            480,                        /* height */
            640,                        /* totalWidth */
            480,                        /* rowBytes */
            60,                         /* refreshRate */
            IO_2BitsPerPixel,          /* bitsPerPixel */
            IO_OneIsWhiteColorSpace,   /* colorSpace */
            0,                         /* flags */
            0,                         /* parameters */
        },
        64 * 1024,                     /* 64KB frame buffer */
        0                              /* registerValues */
    }
};

const unsigned int vgaModeCount = sizeof(vgaModes) / sizeof(VGAMode);
