/* CONFIDENTIAL
 * Copyright (c) 1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * VGAPSDriver.h -- VGA PostScript Driver Interface
 *
 * Created for RhapsodiOS VGA PostScript support
 */

#ifndef VGAPSDRIVER_H__
#define VGAPSDRIVER_H__

/* PostScript driver initialization */
int VGAPSInit(void);

/* PostScript driver cleanup */
void VGAPSCleanup(void);

/* PostScript rendering functions */
int VGAPSBeginPage(void);
int VGAPSEndPage(void);
int VGAPSRenderImage(const void *imageData, int width, int height, int bitsPerPixel);

/* Color management */
int VGAPSSetColorSpace(int colorSpace);
int VGAPSSetGamma(float gamma);

/* Display information */
int VGAPSGetDisplayInfo(void *info);

#endif /* VGAPSDRIVER_H__ */
