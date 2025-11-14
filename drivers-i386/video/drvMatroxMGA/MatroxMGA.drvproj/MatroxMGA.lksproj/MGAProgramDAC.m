/*
 * Copyright © 1998-2007 Mirko Viviani. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of the author may not be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Created by Mirko Viviani: 16 Dec 1998
*/

#import <driverkit/i386/PCI.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

#import "MGA.h"
#import "XModes.h"

#import "mgax.h"
#import "mga_reg.h"


@implementation MatroxMGA (ProgramDAC)


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
SetGammaValue(unsigned char *MGAMMIOBase, unsigned int r, unsigned int g, unsigned int b, int level)
{
#ifdef DEBUG
//	IOLog("r=%02x g=%02x b=%02x\n", EV_SCALE_BRIGHTNESS(level, r), EV_SCALE_BRIGHTNESS(level, g), EV_SCALE_BRIGHTNESS(level, b));
#endif

	OUTREG8(RAMDAC_OFFSET + TVP3026_COL_PAL, EV_SCALE_BRIGHTNESS(level, r));
	IODelay(1);
	OUTREG8(RAMDAC_OFFSET + TVP3026_COL_PAL, EV_SCALE_BRIGHTNESS(level, g));
	IODelay(1);
	OUTREG8(RAMDAC_OFFSET + TVP3026_COL_PAL, EV_SCALE_BRIGHTNESS(level, b));
	IODelay(1);
}


- setTransferTable:(unsigned int *)table count:(int)numEntries
{
	[self setPCIIOSpaceAccess:[self deviceDescription] enable:YES];

	/* redTransferTable, greenTransferTable, and blueTransferTable
	 * are driver-defined instance variables
	if (!redTransferTable || transferTableCount != numEntries)
	{
		if(redTransferTable)
			IOFree(redTransferTable, 3 * transferTableCount);

		transferTableCount = numEntries;

#ifdef DEBUG
		IOLog("ttc = %d\n", transferTableCount);
#endif

		redTransferTable   = IOMalloc(3 * numEntries);
		greenTransferTable = redTransferTable   + numEntries;
		blueTransferTable  = greenTransferTable + numEntries;
	}

	switch ([self displayInfo]->colorSpace)
	{
		case IO_OneIsWhiteColorSpace:
			for (k = 0; k < numEntries; k++)
			{
				redTransferTable[k]  = greenTransferTable[k] =
				blueTransferTable[k] = table[k] & 0xFF;
			}
			break;

		case IO_RGBColorSpace:
			for (k = 0; k < numEntries; k++)
			{
				redTransferTable[k]   = (table[k] >> 24) & 0xFF;
				greenTransferTable[k] = (table[k] >> 16) & 0xFF;
				blueTransferTable[k]  = (table[k] >> 8) & 0xFF;
			}
			break;

		default:
			IOFree(redTransferTable, 3 * numEntries);
			redTransferTable = 0;
			break;
	}
	[self setGammaTable]; /* subclass method */
	[self setPCIIOSpaceAccess:[self deviceDescription] enable:NO];

	return self;
}


- setBrightness:(int)level token:(int)t
{
#ifdef EDEBUG
	IOLog("brightness = %d, tt=%ld, ttc=%d\n", level, redTransferTable, transferTableCount);
#endif

	[self setPCIIOSpaceAccess:[self deviceDescription] enable:YES];

	if(level < EV_SCREEN_MIN_BRIGHTNESS || level > EV_SCREEN_MAX_BRIGHTNESS)
	{
		IOLog("MatroxMGA: Invalid brightness level `%d'.\n", level);
		[self setPCIIOSpaceAccess:[self deviceDescription] enable:NO];
		return nil;
	}
	brightnessLevel = level;
	[self setGammaTable];
	[self setPCIIOSpaceAccess:[self deviceDescription] enable:NO];

	return self;
}


- setGammaTable
{
	unsigned int i, j;
	const IODisplayInfo *displayInfo;

#ifdef DEBUG
	IOLog("tt=%ld c=%d\n", redTransferTable, transferTableCount);
#endif

	displayInfo = [self displayInfo];

	OUTREG8(RAMDAC_OFFSET + TVP3026_INDEX, 0x00);
	IODelay(1);

	if (redTransferTable != 0)
	{
		for (i = 0; i < transferTableCount; i++)
		{
			for (j = 0; j < 256/transferTableCount; j++)
			{
				SetGammaValue(MGAMMIOBase, redTransferTable[i], greenTransferTable[i],
					blueTransferTable[i], brightnessLevel);
			}
		}
	}
	else
	{
		switch (displayInfo->bitsPerPixel)
		{
			case IO_24BitsPerPixel:
			case IO_8BitsPerPixel:
				for (i = 0; i < 256; i++)
				{
					SetGammaValue(MGAMMIOBase, gamma8[i], gamma8[i], gamma8[i], brightnessLevel);
				}
				break;

			case IO_12BitsPerPixel:
			case IO_15BitsPerPixel:
			if (dac == PCI_CHIP_MGAG400
			||  dac == PCI_CHIP_MGAG200
			||  dac == PCI_CHIP_MGAG200_PCI
			||  dac == PCI_CHIP_MGAG100
			||  dac == PCI_CHIP_MGAG100_PCI)
			{
//				for (i=0; i < 16; i++)
				{
					for (j = 0; j < 32; j++)
					{
						SetGammaValue(MGAMMIOBase, gamma8[j*8], gamma8[j*8], gamma8[j*8], brightnessLevel);
					}
				}
			}
			else
			{
				for (i = 0; i < 16; i++)
				{
					for (j = 0; j < 16; j++)
					{
						SetGammaValue(MGAMMIOBase, gamma16[i], gamma16[i], gamma16[i], brightnessLevel);
					}
				}
			}
				break;

			default:
				break;
		}
	}

	return self;
}

@end
