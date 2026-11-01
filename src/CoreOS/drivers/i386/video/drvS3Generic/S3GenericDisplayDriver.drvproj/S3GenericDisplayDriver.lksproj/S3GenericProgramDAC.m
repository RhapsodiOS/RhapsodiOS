/* Copyright (c) 1993-1996 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * S3GenericProgramDAC.m -- DAC support for the S3 Generic driver.
 *
 * History
 * Thu Sep 15 15:16:43 PDT 1994, James C. Lee
 *   Added AT&T 20C505 DAC support
 * Author:  Derek B Clegg	1 July 1993
 * Based on work by Joe Pasqua.
 */
#import "S3Generic.h"

/* The `ProgramDAC' category of `S3Generic'. */

@implementation S3Generic (ProgramDAC)

static inline void
setCommandRegister0(unsigned char value)
{
    rwrite(VGA_CRTC_INDEX, 0x55, 0x01);
    outb(RS_02, value);
}

static inline void
setCommandRegister1(unsigned char value)
{
    rwrite(VGA_CRTC_INDEX, 0x55, 0x02);
    outb(RS_00, value);
}

static inline void
setCommandRegister2(unsigned char value)
{
    rwrite(VGA_CRTC_INDEX, 0x55, 0x02);
    outb(RS_01, value);
}

static inline void
setCommandRegister3(unsigned char value)
{
    unsigned char commandRegister0, addressRegister;

    rwrite(VGA_CRTC_INDEX, 0x55, 0x01);
    commandRegister0 = inb(RS_02);
    outb(RS_02, 0x80 | commandRegister0);
    rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
    addressRegister = inb(RS_00);
    outb(RS_00, 0x01);
    rwrite(VGA_CRTC_INDEX, 0x55, 0x02);
    outb(RS_02, value);
    rwrite(VGA_CRTC_INDEX, 0x55, 0x01);
    outb(RS_02, commandRegister0);
    rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
    outb(RS_00, addressRegister);
}

// also check for AT&T 20C505 DAC; it's BT485 compatible
static DACtype checkForBrooktreeDAC(void)
{
    DACtype dac;
    unsigned char commandRegister0;

    S3_unlockRegisters();

    /* Save the value of command register 0. */
    rwrite(VGA_CRTC_INDEX, 0x55, 0x01);
    commandRegister0 = inb(RS_02);

    /* Write a zero to bit 7 of command register 0. */
    outb(RS_02, commandRegister0 & ~(1 << 7));

    /* Read the status register. */
    rwrite(VGA_CRTC_INDEX, 0x55, 0x02);
    switch (inb(RS_02) & 0xF0) {
    case 0x40:
	dac = Bt484;
	break;
    case 0x80:
	dac = Bt485;
	break;
    case 0x20:
	dac = Bt485A;
	break;
    case 0xd0:
	dac = ATT20C505;
	break;
    default:
	dac = UnknownDAC;
	break;
    }

    /* Restore the old value of command register 0. */
    setCommandRegister0(commandRegister0);

    /* Make sure that we are addressing RS(00xx). */
    rwrite(VGA_CRTC_INDEX, 0x55, 0x00);

    S3_lockRegisters();

    return dac;
}

- determineDACType
{
    dac = checkForBrooktreeDAC();
    if (dac == UnknownDAC) {
	/* Assume that it's an AT&T 20C491 or some other compatible DAC,
	 * such as the Sierra SC15025. */
	dac = ATT20C491;
    }
    return self;
}

- (BOOL)hasTransferTable
{
    switch (dac) {
    case ATT20C491:
	if ([self displayInfo]->bitsPerPixel == IO_8BitsPerPixel)
	    return YES;
	else 
	    return NO;
	break;
    case Bt484:
    case Bt485:
    case Bt485A:
    case ATT20C505:
	return YES;
	break;
    default:
	return NO;
	break;
    }
}

- (BOOL)needsSoftwareGammaCorrection
{
    switch (dac) {
    case ATT20C491:
	return YES;
	break;
    case Bt484:
    case Bt485:
    case Bt485A:
    case ATT20C505:
	return NO;
	break;
    default:
	return YES;
	break;
    }
}

/* Default gamma precompensation table for color displays.
 * Gamma 2.2 LUT for P22 phosphor displays (Hitachi, NEC, generic VGA) */

static const unsigned char gamma16[] = {
      0,  74, 102, 123, 140, 155, 168, 180,
    192, 202, 212, 221, 230, 239, 247, 255
};

static const unsigned char gamma8[] = {
      0,  15,  22,  27,  31,  35,  39,  42,  45,  47,  50,  52,
     55,  57,  59,  61,  63,  65,  67,  69,  71,  73,  74,  76,
     78,  79,  81,  82,  84,  85,  87,  88,  90,  91,  93,  94,
     95,  97,  98,  99, 100, 102, 103, 104, 105, 107, 108, 109,
    110, 111, 112, 114, 115, 116, 117, 118, 119, 120, 121, 122,
    123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 141, 141, 142, 143, 144, 145,
    146, 147, 148, 148, 149, 150, 151, 152, 153, 153, 154, 155, 
    156, 157, 158, 158, 159, 160, 161, 162, 162, 163, 164, 165,
    165, 166, 167, 168, 168, 169, 170, 171, 171, 172, 173, 174,
    174, 175, 176, 177, 177, 178, 179, 179, 180, 181, 182, 182,
    183, 184, 184, 185, 186, 186, 187, 188, 188, 189, 190, 190, 
    191, 192, 192, 193, 194, 194, 195, 196, 196, 197, 198, 198,
    199, 200, 200, 201, 201, 202, 203, 203, 204, 205, 205, 206, 
    206, 207, 208, 208, 209, 210, 210, 211, 211, 212, 213, 213,
    214, 214, 215, 216, 216, 217, 217, 218, 218, 219, 220, 220, 
    221, 221, 222, 222, 223, 224, 224, 225, 225, 226, 226, 227,
    228, 228, 229, 229, 230, 230, 231, 231, 232, 233, 233, 234, 
    234, 235, 235, 236, 236, 237, 237, 238, 238, 239, 240, 240,
    241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 
    247, 247, 248, 248, 249, 249, 250, 250, 251, 251, 252, 252,
    253, 253, 254, 255, 
};

static void
SetGammaValue(unsigned int r, unsigned int g, unsigned int b, int level)
{
    outb(RS_01, EV_SCALE_BRIGHTNESS(level, r));
    outb(RS_01, EV_SCALE_BRIGHTNESS(level, g));
    outb(RS_01, EV_SCALE_BRIGHTNESS(level, b));
}

- setGammaTable
{
    unsigned int i, j, g;
    const IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];

    outb(RS_00, 0x00);

    switch (dac) {
    case Bt484:
    case Bt485:
    case Bt485A:
    case ATT20C505:
	if (redTransferTable != 0) {
	    for (i = 0; i < transferTableCount; i++) {
		for (j = 0; j < 256/transferTableCount; j++) {
		    SetGammaValue(redTransferTable[i], greenTransferTable[i],
				  blueTransferTable[i], brightnessLevel);
		}
	    }
	} else {
	    switch (displayInfo->bitsPerPixel) {
	    case IO_24BitsPerPixel:
	    case IO_8BitsPerPixel:
		for (g = 0; g < 256; g++) {
		    SetGammaValue(gamma8[g], gamma8[g], gamma8[g], 
				  brightnessLevel);
	    }
	    break;

	    case IO_15BitsPerPixel:
		for (i = 0; i < 32; i++) {
		    for (j = 0; j < 8; j++) {
			SetGammaValue(gamma16[i/2], gamma16[i/2], gamma16[i/2],
				      brightnessLevel);
		    }
		}
		break;
	    default:
		break;
	    }
	}
	break;

    case ATT20C491:	/* ATT20C491 or other compatible DAC. */
	switch (displayInfo->bitsPerPixel) {
	  const unsigned char *rTable, *gTable, *bTable;
	case IO_8BitsPerPixel:
	  
	    /* Write out the gamma-corrected grayscale palette. */
	    if (redTransferTable != 0) {
		rTable = redTransferTable;
		gTable = greenTransferTable;
		bTable = blueTransferTable;
	    } else {
		rTable = gTable = bTable = gamma8;
	    }
	    for (g = 0; g < 256; g++) {
		unsigned int r,gr,b;
		r = rTable[g] * 63 / 255;
		gr = gTable[g] * 63 / 255;
		b = bTable[g] * 63 / 255;
		SetGammaValue(r, gr, b, brightnessLevel);
	    }
	    break;
	default:
	    break;
	}
	break;
    default:
	break;
    }
    return self;
}

- resetDAC
{
    const IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];

    switch (dac) {
    case ATT20C491:
	inb(RS_03);		/* Take DAC out of command mode. */
	inb(RS_02);		/* Four reads to get DAC into command mode */
	inb(RS_02);
	inb(RS_02);
	inb(RS_02);
	outb(RS_02, 0x00);	/* Get DAC into 8bpp mode. */
	inb(RS_03);		/* Take DAC out of command mode. */
	rwrite(VGA_CRTC_INDEX, 0x45, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
	break;

    case Bt484:
    case Bt485:
    case Bt485A:
    case ATT20C505:
	setCommandRegister0(0x00);
	setCommandRegister1(0x00);
	setCommandRegister2(0x00);
	if (dac == Bt485 || dac == Bt485A || dac == ATT20C505)
	    setCommandRegister3(0x00);
	rwrite(VGA_CRTC_INDEX, 0x45, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
	rrmw(VGA_CRTC_INDEX, 0x55, ~S3_DAC_R_SEL_MASK, 0x00);
    default:
	break;
    }

    /* Restore the PIXEL mask. */
    outb(RS_02, 0xFF);

    /* Set correct falling edge mode. */
    rrmw(VGA_CRTC_INDEX, S3_EXT_MODE, 0xFE, 0x00);

    return self;
}

- programDAC
{
    const IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];

    switch (dac) {
    case ATT20C491:
	inb(RS_03);	/* Take DAC out of command mode. */
	inb(RS_02);	/* Four reads to get DAC into command mode */
	inb(RS_02);
	inb(RS_02);
	inb(RS_02);

	switch (displayInfo->bitsPerPixel) {
	case IO_8BitsPerPixel:
	    outb(RS_02, 0x00);		/* Get DAC into 8bpp mode. */
	    break;
	case IO_15BitsPerPixel:
	    outb(RS_02, 0xA0);		/* Get DAC into 15bpp mode. */
	    break;
	default:
	    break;
	}
	inb(RS_03);	/* Take DAC out of command mode. */
	rwrite(VGA_CRTC_INDEX, 0x45, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
	rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
	break;

    case Bt484:
    case Bt485:
    case Bt485A:
    case ATT20C505:
	switch (displayInfo->bitsPerPixel) {
	case IO_8BitsPerPixel:
	    if (displayInfo->width == 1280) {
		setCommandRegister0(0x02);
		setCommandRegister1(0x40);
		setCommandRegister2(0x30);
		if (dac == Bt485 || dac == Bt485A || dac == ATT20C505)
		    setCommandRegister3(0x08);
		rwrite(VGA_CRTC_INDEX, 0x45, 0x20);
		rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
		rwrite(VGA_CRTC_INDEX, 0x55, 0x28);
	    } else {
		setCommandRegister0(0x02);
		setCommandRegister1(0x00);
		setCommandRegister2(0x00);
		if (dac == Bt485 || dac == Bt485A || dac == ATT20C505)
		    setCommandRegister3(0x00);
		rwrite(VGA_CRTC_INDEX, 0x45, 0x00);
		rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
		rwrite(VGA_CRTC_INDEX, 0x55, 0x00);
	    }
	    break;

	case IO_15BitsPerPixel:
	    setCommandRegister0(0x02);
	    setCommandRegister1(0x20);
	    setCommandRegister2(0x30);
	    if (dac == Bt485 || dac == Bt485A || dac == ATT20C505)
		setCommandRegister3(0x00);
	    if (displayInfo->width == 1280)
		rwrite(VGA_CRTC_INDEX, 0x53, 0x20);
	    else
		rwrite(VGA_CRTC_INDEX, 0x53, 0x00);
	    rwrite(VGA_CRTC_INDEX, 0x45, 0x20);
	    rwrite(VGA_CRTC_INDEX, 0x55, 0x28);
	    break;

	case IO_24BitsPerPixel:
	    setCommandRegister0(0x02);
	    setCommandRegister1(0x00);
	    setCommandRegister2(0x30);
	    if (dac == Bt485 || dac == Bt485A || dac == ATT20C505)
		setCommandRegister3(0x08);
	    rwrite(VGA_CRTC_INDEX, 0x45, 0x20);
	    rwrite(VGA_CRTC_INDEX, 0x53, 0x20);
	    rwrite(VGA_CRTC_INDEX, 0x55, 0x28);
	    break;

	default:
	    break;
	}
	rrmw(VGA_CRTC_INDEX, 0x55, ~S3_DAC_R_SEL_MASK, 0x00);
	break;

    default:
	break;
    }

    /* Restore the PIXEL mask. */
    outb(RS_02, 0xFF);

    /* Set correct falling edge mode. */
    rrmw(VGA_CRTC_INDEX, S3_EXT_MODE, 0xFE, 0x00);

    return self;
}
@end
