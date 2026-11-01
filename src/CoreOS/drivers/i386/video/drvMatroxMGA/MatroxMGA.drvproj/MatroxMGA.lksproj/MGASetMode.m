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
 * Created by Mirko Viviani 4 Apr 1999
 */

#import <string.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

#import "MGA.h"
#import "XModes.h"
#import "vgaModes.h"
#import "mga_reg.h"

@implementation MatroxMGA (SetMode)


- (void)reportConfiguration
{
	char *name, *mem, *memAvail;

	switch(dac)
	{
		case PCI_CHIP_MGA2085:
			name = "MGA 2085PX";
			mem  = "WRAM size";
			break;
		case PCI_CHIP_MGA2064:
			name = "Millennium";
			mem  = "WRAM size";
			break;
		case PCI_CHIP_MGA1064:
			name = "Mystique";
			mem  = "SGRAM size";
			break;
		case PCI_CHIP_MGA2164:
			name = "Millennium II";
			mem  = "WRAM size";
			break;
		case PCI_CHIP_MGA2164_AGP:
			name = "Millennium II AGP";
			mem  = "WRAM size";
			break;
		case PCI_CHIP_MGAG400:
			if (MGAISG450)
				name = "Millennium G450 AGP";
			else
				name = "Millennium G400 AGP";
			mem  = "SGRAM size";
			break;
		case PCI_CHIP_MGAG200:
			name = "Millennium G200 AGP";
			mem  = "SGRAM size";
			break;
		case PCI_CHIP_MGAG200_PCI:
			name = "Millennium G200 PCI";
			mem  = "SGRAM size";
			break;
		case PCI_CHIP_MGAG100:
			name = "Productiva G100 AGP";
			mem  = "SGRAM size";
			break;
		case PCI_CHIP_MGAG100_PCI:
			name = "Productiva G100 PCI";
			mem  = "SGRAM size";
			break;
		default:
			name = mem = NULL;
			break;
	}

	if(MGAHasSDRAM) mem = "SDRAM size";

	switch (availableMemory)
	{
		case THIRTYTWO_MEGABYTES: memAvail = "32 MB"; break;
		case SIXTEEN_MEGABYTES: memAvail = "16 MB"; break;
		case EIGHT_MEGABYTES: memAvail = "8 MB"; break;
		case FOUR_MEGABYTES: memAvail = "4 MB"; break;
		case TWO_MEGABYTES: memAvail = "2 MB"; break;
		default: memAvail = "(unknown memory size)"; break;
	}

	IOLog( "%s: Matrox %s\n", [self name], name );
	IOLog( "%s: %s: %s\n", [self name], mem, memAvail );
	IOLog( "%s: RAMDAC: %d MHz\n", [self name], MGAdac.maxPixelClock/1000);
}


- determineConfiguration:(IODeviceDescription *)deviceDescription
{
	IOPCIConfigSpace *config;
/*	int func, bus;

    if ([deviceDescription getPCIdevice:NULL function:&func bus:&bus]
	!= IO_R_SUCCESS) {
	/*  Only PCI bus supported for now.  *//*
	IOLog ("%s: Matrox MGA2064W not found\n", [self name]);
	return nil;
    }
	IOLog("pci func=%d, bus=%d\n", func, bus);*/

	if ([[self class] getPCIConfigSpace:(IOPCIConfigSpace *)&MGApcr withDeviceDescription:deviceDescription] != IO_R_SUCCESS)
	{
		IOLog("Can't get PCI config space !!!!!\n");
	}
//	{
		if(!xf86scanpci(0, &MGApcr, PCI_VENDOR_MATROX))
		{
			IOLog("Can't get config space...\n");
			return nil;
		}
//	}

	config = (IOPCIConfigSpace *)&MGApcr;

	if(config->VendorID == PCI_VENDOR_MATROX)
	{
		switch(config->DeviceID)
		{
			case PCI_CHIP_MGA2085:
			case PCI_CHIP_MGA2064:
			case PCI_CHIP_MGA2164:
			case PCI_CHIP_MGA2164_AGP:
				availableMemory = FOUR_MEGABYTES;
				dacType = DACTYPE_TVP3026;
				break;
			case PCI_CHIP_MGA1064:
				availableMemory = TWO_MEGABYTES;
				dacType = DACTYPE_MYSTIQUE;
				break;
			case PCI_CHIP_MGAG200:
			case PCI_CHIP_MGAG200_PCI:
			case PCI_CHIP_MGAG100:
			case PCI_CHIP_MGAG100_PCI:
				availableMemory = EIGHT_MEGABYTES;
				dacType = DACTYPE_GSERIES;
				break;
			case PCI_CHIP_MGAG400:
				availableMemory = SIXTEEN_MEGABYTES;
				dacType = DACTYPE_GSERIES;
				break;
			default:
				return nil;
		}
	}

	dac = config->DeviceID;

#ifdef DEBUG
	IOLog("vendor=%04x devID=%04x mem=%ld\n", config->VendorID, config->DeviceID, availableMemory);
#endif

	modeTable      = MGA_ModeTable;
	modeTableCount = MGA_ModeTableCount;

	return self;
}


/* Select a display mode based on the adapter type, the bus configuration,
 * and the memory configuration.  Return the selected mode, or -1 if no mode
 * is valid.
 */
- selectMode
{
	int          k, mode;
	const XMode *modeData;
	BOOL         valid[modeTableCount];

	for (k = 0; k < modeTableCount; k++)
	{
		modeData = modeTable[k].parameters;
		valid[k] = (modeData->memSize <= availableMemory 
			/*&& modeData->adapter == adapter*/);
	}

	mode = [self selectMode:modeTable count:modeTableCount valid:valid];
	if (mode < 0)
	{
		IOLog("%s: Sorry, cannot use requested display mode.\n", [self name]);
		mode = MGA_defaultMode;
	}
	*[self displayInfo] = modeTable[mode];

	return self;
}


- initializeMode
{
	return self;
}


- enableLinearFrameBuffer
{
	const XMode   *mode;
	IODisplayInfo *displayInfo;

	displayInfo = [self displayInfo];
	mode = displayInfo->parameters;

	[self setFlags:displayInfo withMode:mode];
	[self TestAndSetRounding:0];

	/* Clear the screen. */
	memset(displayInfo->frameBuffer, 0, mode->memSize);

	[self MGALinearOffset];
	[self MGAAdjust:0 y:0];

	switch(dac)
	{
		case PCI_CHIP_MGA2085:
		case PCI_CHIP_MGA2064:
		case PCI_CHIP_MGA2164:
		case PCI_CHIP_MGA2164_AGP:
			[self MGA3026Init:&curmode];
			[self MGARestore:vgaNewVideoState];
			break;
		case PCI_CHIP_MGAG400:
		case PCI_CHIP_MGAG200:
		case PCI_CHIP_MGAG200_PCI:
		case PCI_CHIP_MGAG100:
		case PCI_CHIP_MGAG100_PCI:
		case PCI_CHIP_MGA1064:
			[self MGAG200Init:&curmode];
			[self MGARestore:vgaNewVideoState];
			break;
	}
	IODelay(10000);

	return self;
}

- resetVGA
{
	[self MGARestore:vgaSaved];
	return self;
}


@end
