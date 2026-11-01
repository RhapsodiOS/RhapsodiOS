/* Copyright (c) 1996-1998 by NeXT Software, Inc. as an unpublished work.
 * All rights reserved.
 *
 * TransferTable.m -- gamma and brightness for the IBM ThinkPad 760ED
 * display driver.
 *
 * The palette DAC is the standard VGA one. The write index is set once, at
 * port 0x3C8, and auto-increments after every third write to the data
 * register at 0x3C9, so the three writes that make up one entry must stay
 * adjacent and in red, green, blue order.
 */
#import "IBMThinkPad760ED.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

/* The `TransferTable' category of `IBMThinkPad760EDDisplayDriver'. */

@implementation IBMThinkPad760EDDisplayDriver (TransferTable)

/* Set the transfer tables. One allocation of `3 * count' bytes is carved
 * into the red, green and blue tables, and is reused as long as the entry
 * count does not change.
 */
- setTransferTable:(const unsigned int *)table count:(int)count
{
    int k;

    if (redTransferTable == 0 || transferTableCount != count) {
	if (redTransferTable != 0)
	    IOFree(redTransferTable, 3 * transferTableCount);

	transferTableCount = count;

	redTransferTable = IOMalloc(3 * count);
	greenTransferTable = redTransferTable + count;
	blueTransferTable = greenTransferTable + count;
    }

    switch ([self displayInfo]->colorSpace) {
    case IO_OneIsWhiteColorSpace:
	for (k = 0; k < count; k++) {
	    redTransferTable[k] = greenTransferTable[k] =
		blueTransferTable[k] = table[k] & 0xFF;
	}
	break;

    case IO_RGBColorSpace:
	for (k = 0; k < count; k++) {
	    redTransferTable[k] = (table[k] >> 24) & 0xFF;
	    greenTransferTable[k] = (table[k] >> 16) & 0xFF;
	    blueTransferTable[k] = (table[k] >> 8) & 0xFF;
	}
	break;

    default:
	IOFree(redTransferTable, 3 * count);
	redTransferTable = 0;
	break;
    }

    [self setGammaTable];
    return self;
}

/* Set the brightness to `level'. The token is ignored.
 */
- setBrightness:(int)level token:(int)t
{
    if ((unsigned int)level > EV_SCREEN_MAX_BRIGHTNESS) {
	IOLog("%s: Invalid brightness level `%d'\n", [self name], level);
	return nil;
    }
    brightnessLevel = level;
    [self setGammaTable];
    return self;
}

/* Default gamma precompensation table for color displays.
 * Gamma 2.2 LUT for P22 phosphor displays.
 */

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

/* Write one palette entry at the current DAC write index. The eight-bit
 * ramp values are scaled by the brightness, so a level of
 * EV_SCREEN_MAX_BRIGHTNESS gives a quarter-intensity ramp and 255 would
 * give a full one.
 */
- (void)SetGammaValueRed:(unsigned int)r Green:(unsigned int)g
		    Blue:(unsigned int)b Level:(int)level
{
    outb(0x3C9, (r * level) >> 8);
    outb(0x3C9, (g * level) >> 8);
    outb(0x3C9, (b * level) >> 8);
}

/* Load all 256 palette entries, either from the client's transfer tables or
 * from the default gamma ramp for the current pixel depth.
 */
- setGammaTable
{
    unsigned int i, j, g;
    const IODisplayInfo *displayInfo;

    displayInfo = [self displayInfo];

    outb(0x3C8, 0x00);

    if (redTransferTable != 0) {
	/* Repeat each client entry until the palette is full. */
	for (i = 0; i < transferTableCount; i++) {
	    for (j = 0; j < 256 / transferTableCount; j++) {
		[self SetGammaValueRed:redTransferTable[i]
			Green:greenTransferTable[i]
			Blue:blueTransferTable[i]
			Level:brightnessLevel];
	    }
	}
    } else {
	switch (displayInfo->bitsPerPixel) {
	case IO_8BitsPerPixel:
	case IO_24BitsPerPixel:
	    for (g = 0; g < 256; g++) {
		[self SetGammaValueRed:gamma8[g] Green:gamma8[g]
			Blue:gamma8[g] Level:brightnessLevel];
	    }
	    break;

	default:
	    break;
	}
    }
    return self;
}

@end
