#import <driverkit/i386/ioPorts.h>
#import "vgaModes.h"
#include "mga.h"

static const VGAMode VGAMode_3 = {
    0x67, 0x00,
    { 0x01, 0x00, 0x03, 0x00, 0x02 },
    {					
	0x5f, 0x4f, 0x50, 0x82, 0x55, 0x81, 0xbf, 0x1f, 0x00, 0x4f,
	0x0d, 0x0e, 0x00, 0x00, 0x00, 0x00, 0x9c, 0x8e, 0x8f, 0x28,
	0x1f, 0x96, 0xb9, 0xa3, 0xff,
    },
    {
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07, 0x38, 0x39,
	0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x0c, 0x00, 0x0f, 0x08,
    },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x0e, 0x00, 0xff },
};

static const VGAMode VGAMode_12 = {
    0xE3, 0x00,
    { 0x03, 0x01, 0x0f, 0x00, 0x06 },
    {
	0x5f, 0x4f, 0x50, 0x82, 0x54, 0x80, 0x0b, 0x3e, 0x00, 0x40,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x59, 0xea, 0x8c, 0xdf, 0x28,
	0x00, 0xe7, 0x04, 0xe3, 0xff,
    },
    {
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07, 0x38, 0x39,
	0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x01, 0x00, 0x0f, 0x00,
    },
    { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f, 0xff },
};

int
VGASetMode(unsigned int mode)
{
    switch (mode) {
    case 0x03:
	VGASetModeData(&VGAMode_3);
	break;
    case 0x12:
	VGASetModeData(&VGAMode_12);
	break;
    default:
	return -1;
    }
    return 0;
}

int
VGASetModeData(const VGAMode *modeData)
{
    int k;
    
    /* NOTE: The attribute registers are a little weird. For most registers,
     * there is a separate index and data port. The attribute register set
     * has just one port that gets used for both. You write an index to the
     * port, then use the same port for data. The VGA automatically toggles
     * the sense of the port (between index and data) with an internal
     * flip-flop.  You set the state of the flip-flop by doing an inb() on
     * the input status 1 port.
     *
     * The other weird thing is that the attribute index register also
     * contains a palette access bit. This bit determines whether the
     * CPU or the VGA has control of the palette. While the CPU owns the
     * palette, the display is effectively off.
     */

    /* Turn the video off while we are doing this.... */

    BREG (VGA_INPUT_STATUS_1);	/* Set the attribute flip-flop to "index". */
    BREGO (VGA_ATTR_INDEX, 0x00);	/* Gives palette to CPU, turning off video. */
    
    /* Set the misc. output register. */
    BREGO (VGA_MISC_OUTPUT, modeData->miscOutput);
    
    /* Set the feature control register */
    BREGO (VGA_FEATURE_CTRL, modeData->featureCtrl);

    /* Load the sequencer registers. */
    for (k = 0; k < VGA_SEQ_COUNT; k++) {
	BREGO (VGA_SEQ_INDEX, k);
	BREGO (VGA_SEQ_DATA, modeData->seqx[k]);
    }
    BREGO (VGA_SEQ_INDEX, 0x00);
    BREGO (VGA_SEQ_DATA, 0x03);	/* Low order two bits are reset bits. */
    
    /* Load the CRTC registers.  CRTC registers 0-7 are locked by a bit
     * in register 0x11. We need to unlock these registers before we can
     * start setting them. */
    BREGO (VGA_CRTC_INDEX, 0x11);
    BREGO (VGA_CRTC_DATA, 0x00);		/* Unlocks registers 0-7. */
    for (k = 0; k < VGA_CRTC_COUNT; k++) {
	BREGO (VGA_CRTC_INDEX, k);
	BREGO (VGA_CRTC_DATA, modeData->crtc[k]);
    }

    /* Load the attribute registers. */
    BREG (VGA_INPUT_STATUS_1);	/* Set the attribute flip-flop to "index" */
    for (k = 0; k < VGA_ATTR_COUNT; k++) {
	BREGO (VGA_ATTR_INDEX, k);
	BREGO (VGA_ATTR_DATA, modeData->attr[k]);
    }

    /* Load graphics registers. */
    for (k = 0; k < VGA_GRFX_COUNT; k++) {
	BREGO (VGA_GRFX_INDEX, k);
	BREGO (VGA_GRFX_DATA, modeData->grfx[k]);
    }    

    /* Re-enable video. */
    BREG (VGA_INPUT_STATUS_1);	/* Set the attribute flip-flop to "index" */
    BREGO (VGA_ATTR_INDEX, 0x20);	/* Give the palette back to the VGA */
    
    return 0;
}
