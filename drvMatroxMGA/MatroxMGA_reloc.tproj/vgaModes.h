/*
 * Copyright (c) 1993 by NeXT Computer, Inc.
 * All rights reserved.
 *
 * vgaModes.h -- Definitions for the standard VGA.
 *
 * Author:  Derek B Clegg	21 May 1993
 */

#ifndef VGADEFS_H__
#define VGADEFS_H__

/* Miscellaneous output register. */

#define	VGA_MISC_OUTPUT		0x3C2

/* Input status 1 register. */

#define VGA_INPUT_STATUS_1	0x3DA

/* Feature control register. */

#define VGA_FEATURE_CTRL	0x3DA

/* Sequencer. */

#define VGA_SEQ_INDEX		0x3C4
#define VGA_SEQ_DATA		0x3C5
#define VGA_SEQ_COUNT		5
#define VGA_SEQ0       0x00
#define VGA_SEQ1       0x01
#define VGA_SEQ2       0x02
#define VGA_SEQ3       0x03
#define VGA_SEQ4       0x04

/* Sequencer Indexes. */

#define VGA_RST_SYNC		0x00	/* Reset register. */
#define VGA_CLK_MODE		0x01	/* Clocking mode register. */
#define VGA_EN_WT_PL		0x02	/* Enable write plane register. */
#define VGA_CH_FONT_SL		0x03	/* Change font select register. */
#define VGA_MEM_MODE		0x04	/* Memory mode control register. */

/* CRT Controller. */

#define VGA_CRTC_INDEX 		0x3D4
#define VGA_CRTC_DATA  		0x3D5
#define VGA_CRTC_COUNT		25

#define VGA_CRTCEXT_INDEX    0x3de
#define VGA_CRTCEXT_DATA     0x3df
#define VGA_CRTCEXT0   0x00
#define VGA_CRTCEXT1   0x01
#define VGA_CRTCEXT2   0x02
#define VGA_CRTCEXT3   0x03
#define VGA_CRTCEXT4   0x04
#define VGA_CRTCEXT5   0x05

/* CRT Controller Indexes */

#define VGA_H_TOTAL		0x00	/* Horizontal total register. */
#define VGA_H_D_END		0x01	/* Horizontal display end register. */
#define VGA_S_H_BLNK		0x02	/* Start horizontal blank register. */
#define VGA_E_H_BLNK		0x03	/* End horizontal blank register. */
#define VGA_S_H_SY_P		0x04	/* Start horizontal sync position
					   register. */
#define VGA_E_H_SY_P		0x05	/* End horizontal sync position
					   register. */
#define VGA_V_TOTAL		0x06	/* Vertical total register. */
#define VGA_OVFL_REG		0x07	/* CRTC overflow register. */
#define VGA_P_R_SCAN		0x08	/* Preset row scan register. */
#define VGA_MAX_S_LN		0x09	/* Maximum scan line register. */
#define VGA_CSSL		0x0A	/* Cursor start scan line register. */
#define VGA_CESL		0x0B	/* Cursor end scan line register. */
#define VGA_STAH		0x0C	/* Start address high register. */
#define VGA_STAL		0x0D	/* Start address low register. */
#define VGA_CLAH		0x0E	/* Cursor location address high
					   register. */
#define VGA_CLAL		0x0F	/* Cursor location address low
					   register. */
#define VGA_VRS			0x10	/* Vertical retrace start register. */
#define VGA_VRE			0x11	/* Vertical retrace end register. */
#define VGA_VDE			0x12	/* Vertical display end register. */
#define VGA_SCREEN_OFFSET	0x13	/* Offset register. */
#define VGA_ULL			0x14	/* Underline location register. */
#define VGA_SVB			0x15	/* Start vertical blank register. */
#define VGA_EVB			0x16	/* End vertical blank register. */
#define VGA_CRT_MD		0x17	/* CRTC mode control register. */
#define VGA_LCM			0x18	/* Line compare register. */

/* Attribute Controller. */

#define VGA_ATTR_INDEX		0x3C0
#define VGA_ATTR_DATA		0x3C0
#define	VGA_ATTR_COUNT		20

/* Attribute Controller Indexes. */

#define VGA_PLT_REG		0x00	/* Palette registers (0x00-0x0F). */
#define VGA_ATR_MODE		0x10	/* Attribute mode control register. */
#define VGA_BDR_CLR		0x11	/* Border color register. */
#define VGA_DISP_PLN		0x12	/* Color plane enable register. */
#define VGA_H_PX_PAN		0x13	/* Horizontal pixel panning
					   register. */
/* Graphics Controller. */

#define VGA_GRFX_INDEX		0x3CE
#define VGA_GRFX_DATA		0x3CF
#define VGA_GRFX_COUNT		9

struct VGAMode {
    /* Miscellaneous output register values (3C2). */
    unsigned char miscOutput;

    /* Feature control register value (3DA). */
    unsigned char featureCtrl;

    /* Sequencer register values (3C5.00 - 3C5.04). */
    unsigned char seqx[VGA_SEQ_COUNT];

    /* CRTC register values (3D5.00 - 3D5.18). */
    unsigned char crtc[VGA_CRTC_COUNT];

    /* Attribute controller register values (3C0.00 - 3C0.13). */
    unsigned char attr[VGA_ATTR_COUNT];

    /* Graphics controller register values (3CF.00 - 3CF.08). */
    unsigned char grfx[VGA_GRFX_COUNT];
};
typedef struct VGAMode VGAMode;

extern int VGASetMode(unsigned int mode);
extern int VGASetModeData(const VGAMode *modeData);

#endif	/* VGADEFS_H__ */
