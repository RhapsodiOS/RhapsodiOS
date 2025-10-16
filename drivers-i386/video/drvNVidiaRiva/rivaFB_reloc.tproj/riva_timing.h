/*
 * riva_timing.h - CRTC timing calculation structures and definitions
 * Based on VESA GTF (Generalized Timing Formula)
 */

#ifndef _RIVA_TIMING_H_
#define _RIVA_TIMING_H_

#include "riva_hw.h"

/* Display mode timing structure */
typedef struct {
    int width;              /* Horizontal resolution */
    int height;             /* Vertical resolution */
    int refreshRate;        /* Refresh rate in Hz */
    int pixelClock;         /* Pixel clock in kHz */

    /* Horizontal timing */
    int hTotal;             /* Horizontal total */
    int hDisplay;           /* Horizontal display end */
    int hBlankStart;        /* Horizontal blank start */
    int hBlankEnd;          /* Horizontal blank end */
    int hSyncStart;         /* Horizontal sync start */
    int hSyncEnd;           /* Horizontal sync end */

    /* Vertical timing */
    int vTotal;             /* Vertical total */
    int vDisplay;           /* Vertical display end */
    int vBlankStart;        /* Vertical blank start */
    int vBlankEnd;          /* Vertical blank end */
    int vSyncStart;         /* Vertical sync start */
    int vSyncEnd;           /* Vertical sync end */

    /* Flags */
    int flags;              /* Mode flags */
} RivaModeTimingRec, *RivaModeTimingPtr;

/* Mode flags */
#define RIVA_MODE_HSYNC_POSITIVE    0x01
#define RIVA_MODE_VSYNC_POSITIVE    0x02
#define RIVA_MODE_INTERLACED        0x04

/* Standard mode timings for common resolutions */
extern const RivaModeTimingRec rivaModeTimings[];
extern const int rivaModeTimingsCount;

/* Function prototypes */
void rivaCalculateTimings(int width, int height, int refresh, RivaModeTimingPtr timing);
void rivaProgramCRTC(CARD32 *regBase, RivaModeTimingPtr timing, int pitch, int bpp);
void rivaProgramVPLL(CARD32 *regBase, int pixelClock, RivaChipType chipType);

#endif /* _RIVA_TIMING_H_ */
