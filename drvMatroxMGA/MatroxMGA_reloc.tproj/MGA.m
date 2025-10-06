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

#include <stdlib.h>

#import <driverkit/i386/PCI.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

#import "MGA.h"
#include "XModes.h"
#include "mga_reg.h"
#include "vgaModes.h"
#include "version.h"


const char *MGA_memory_size = "MGA Memory Size";
const char *MGA_sync_on_green = "MGA Sync On Green";

/*
 * See comments where this is used.
 */
#define OFFSET_HACK (12 * 8192)

/* 
 * Multi-Headed support
 */
#define MAX_DISPLAY_HEADS	8
static id displayHead[MAX_DISPLAY_HEADS] = {nil};
static unsigned int numHeads = 0;
static unsigned long start_base_address = 0x60000000;
/*
 * We need this to bail us if the VGA-enabled card is not probed first. 
 */
static BOOL firstHeadProbeFailed = NO;


@implementation MatroxMGA

/* Put the display into linear framebuffer mode. This typically happens
 * when the window server starts running.
 */
- (void)enterLinearMode
{
	if (currentMode == MODE_LINEAR)
		return;

	currentMode = MODE_LINEAR;

	[self setPCIIOSpaceAccess:[self deviceDescription] enable:YES];

	/* Set up the chip to use the selected mode. */
	[self initializeMode];

	/* Set the gamma-corrected gray-scale palette if necessary. */
	[self setGammaTable];

	/* Enter linear mode. */
	if ([self enableLinearFrameBuffer] == nil)
	{
		IOLog("%s: Failed to enter linear mode.\n", [self name]);
		return;
	}

	[self setPCIIOSpaceAccess:[self deviceDescription] enable:NO];
}


/* Get the device out of whatever advanced linear mode it was using and back
 * into a state where it can be used as a standard VGA device.
 */
- (void)revertToVGAMode
{
    /* Reset the VGA parameters. */
    [self resetVGA];

    /* Let the superclass do whatever work it needs to do. */
    [super revertToVGAMode];
}


- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
	IODisplayInfo  *displayInfo;
	const XMode    *xmode;
	int             memSize = 0;
	void *registers;
    IORange range[3], io_range[3];
    unsigned long cmd_status;
    IOReturn rtn;
	int num_io_ranges = 0;

	MGAdac.maxPixelClock = 90000;

	IOLog(MGA_VERSION_STRING);
	IOLog("Copyright (c) 1999-2007 Mirko Viviani\n\n");

	if (numHeads >= MAX_DISPLAY_HEADS)
	{
		IOLog("%s: Maximum number of supported heads is %d\n",
			[self name], MAX_DISPLAY_HEADS);
		return [self free];
	}

	if(firstHeadProbeFailed)
		return [self free];
	
	displayHead[numHeads++] = self;
	primaryHead = YES;

/*	if ([self fixDeviceDescriptionForPCI:devDesc] == NO)
	{
		IOLog("problems with fix deviceDescription\n");
		return [super free];
	}*/

	io_range[0].start = 0x3b0;
	io_range[0].size = 0x30;
	io_range[1].start = 0x102;
	io_range[1].size = 1;
	io_range[2].start = 0x46e8;
	io_range[2].size = 1;
	num_io_ranges += 3;

	[devDesc setPortRangeList:NULL num:0];
	if(primaryHead) {
    	rtn = [devDesc setPortRangeList:io_range num:num_io_ranges];
		if(rtn != IO_R_SUCCESS) {
			IOLog("%s: Error in setPortRangeList (%s)\n", [self name],
				[self stringFromReturn:rtn]);
		}
	}

abort:

    /*
     * Restore memory space access. For primary cards also allow I/O space
     * access. 
     */
    [[self class] getPCIConfigData:&cmd_status atRegister:0x04
		  withDeviceDescription:devDesc];
    if (primaryHead) {
		cmd_status |= 0x03;
    } else {
		cmd_status |= 0x02;
	}
    [[self class] setPCIConfigData:cmd_status atRegister:0x04
		  withDeviceDescription:devDesc];

	if ([super initFromDeviceDescription:devDesc] == nil)
		return [super free];

	/*  Get access to the memory-mapped registers.  They are in memory
	    range 1, and must not be cached (should be handled by hardware
	    anyway).  */

#if 0
	if ([self mapMemoryRange:1 to:(vm_address_t *)&registers
		findSpace:YES cache:IO_CacheOff])
	{
		IOLog ("%s: Unable to map device registers\n", [self name]);
		return [self free];
	}
#endif

	if ([self determineConfiguration:devDesc] == nil)
		return [super free];

	if ([self selectMode] == nil)
		return [super free];

	redTransferTable = greenTransferTable = blueTransferTable = 0;
	transferTableCount = 0;
	brightnessLevel = EV_SCREEN_MAX_BRIGHTNESS;

	displayInfo = [self displayInfo];
	xmode = displayInfo->parameters;
	[self setFlags:displayInfo withMode:xmode];

	{
		unsigned long option;
		[self getPCIConfigData:&option atRegister:PCI_MGA_OPTION];
		option |= 0x100;
		[self setPCIConfigData:option atRegister:PCI_MGA_OPTION];
	}

	if(![self MGAProbe])
	{
		IOLog("%s: MGAProbe failed.\n", [self name]);
		return [super free];
	}

	[self MGASave:NULL];

#ifdef DEBUG
	IOLog("mapFrameBuffer [%lx %ld %ld].\n", videoRamAddress, vga256InfoRec.videoRam*1024,  xmode->memSize);
#endif

	memSize = [self integerForStringKey:MGA_memory_size withDefault:0];

	if(memSize && memSize > 2 && memSize < 64)
		vga256InfoRec.videoRam = memSize * 1024;

	availableMemory = vga256InfoRec.videoRam * 1024;

#if 1
	range[0].start = videoRamAddress;
	range[0].size  = vga256InfoRec.videoRam * 1024;
	range[1].start = 0xa0000;
	range[1].size  = 0x20000;
	range[2].start = 0xc0000;
	range[2].size  = 0x10000;
	[devDesc setMemoryRangeList:range num:3];
#endif

	[self reportConfiguration];

	displayInfo->frameBuffer = (void *)
		[self mapFrameBufferAtPhysicalAddress:
			videoRamAddress
//			[devDesc memoryRangeList][0].start
			length:vga256InfoRec.videoRam * 1024];

	if (displayInfo->frameBuffer == 0)
	{
		IOLog("%s: mapFrameBuffer [%lx %ld] failed.\n", [self name], videoRamAddress, xmode->memSize);
		return [super free];
	}

//	IOLog("%s: Initialized `%s' @ %d Hz.\n", [self name], ""/*xmode->name*/,
//		displayInfo->refreshRate);

	return self;
}

- free
{
	if(numHeads > 0)
		numHeads--;

	return [super free];
}

- (void)setFlags:(IODisplayInfo *)displayInfo withMode:(const XMode *)xmode
{
	displayInfo->flags = 0;

#ifdef DEBUG
	IOLog("%ld %d %d %d %d %d %d %d %d %d\n", xmode->memSize, xmode->Clock, xmode->HDisplay, xmode->HSyncStart, xmode->HSyncEnd, xmode->HTotal, xmode->VDisplay, xmode->VSyncStart, xmode->VSyncEnd, xmode->VTotal );
#endif

	switch(displayInfo->bitsPerPixel)
	{
		case IO_2BitsPerPixel:
			vgaBitsPerPixel = 2;
			break;
		case IO_8BitsPerPixel:
			vgaBitsPerPixel = 8;
			break;
		case IO_12BitsPerPixel:
		case IO_15BitsPerPixel:
			vgaBitsPerPixel = 16;
			break;
		case IO_24BitsPerPixel:
			vgaBitsPerPixel = 32;
			break;
		default:
			IOLog("%s: Bad bit per pixel value.\n", [self name]);
			break;
	}

//	IOLog("&& %s %d\n", displayInfo->pixelEncoding, vgaBitsPerPixel);

	vga256InfoRec.displayWidth  = vga256InfoRec.virtualX = displayInfo->width;
	                              vga256InfoRec.virtualY = displayInfo->height;

	displayInfo->flags |= IO_DISPLAY_HAS_TRANSFER_TABLE;

	curmode.next  = NULL;
	curmode.prev  = NULL;
	curmode.Flags = 0;
	curmode.Clock = xmode->Clock;
	curmode.CrtcHAdjusted = FALSE;
	curmode.CrtcVAdjusted = FALSE;
	curmode.CrtcHSkew     = curmode.HSkew = 0;

	curmode.CrtcHDisplay   = curmode.HDisplay   = xmode->HDisplay;
	curmode.CrtcHSyncStart = curmode.HSyncStart = xmode->HSyncStart;
	curmode.CrtcHSyncEnd   = curmode.HSyncEnd   = xmode->HSyncEnd;
	curmode.CrtcHTotal     = curmode.HTotal     = xmode->HTotal;
	curmode.CrtcVDisplay   = curmode.VDisplay   = xmode->VDisplay;
	curmode.CrtcVSyncStart = curmode.VSyncStart = xmode->VSyncStart;
	curmode.CrtcVSyncEnd   = curmode.VSyncEnd   = xmode->VSyncEnd;
	curmode.CrtcVTotal     = curmode.VTotal     = xmode->VTotal;

	xf86weight.red   = 5;
	xf86weight.green = 5;
	xf86weight.blue  = 5;

}

- (void)setPCIIOSpaceAccess:deviceDescription enable:(BOOL)enable
{
}

- (BOOL)fixDeviceDescriptionForPCI:deviceDescription
{
	const id self_class = [self class];

#define MAX_PCI_RANGES 6
#if 1	/* Multi-Headed support */
    IORange mem_range[MAX_PCI_RANGES + 2];
    int num_mem_ranges = 0;

    IORange io_range[MAX_PCI_RANGES + 3];
    int num_io_ranges = 0;

    unsigned long cmd_status;
    BOOL bios_pci_config_ok, pci_config_fixed;
    unsigned long base;
    IOReturn rtn;
	BOOL return_status = YES;
	IOConfigTable *configTable;
	const char *fbkey;
	unsigned long start_address;
	const unsigned long incr = 0x1000000;	// increment to start_base_address
#else
    IORange mem_range[MAX_PCI_RANGES + 2];
    int mem_pci_addr[MAX_PCI_RANGES + 2];
    int num_mem_ranges = 0;

    IORange io_range[MAX_PCI_RANGES + 3];
    int io_pci_addr[MAX_PCI_RANGES + 3];
    int num_io_ranges = 0;

    int n;
    unsigned long cmd_status;
    BOOL bios_pci_config_ok, pci_config_fixed;
    unsigned long base, test_base;
    IOReturn rtn;
	BOOL return_status = YES;
#endif

    /*  Disable the card's response to memory and I/O accesses while
	poking with the base registers.  */
    [self_class getPCIConfigData:&cmd_status atRegister:0x04
    	withDeviceDescription:deviceDescription];
    [self_class setPCIConfigData:(cmd_status & ~0x03) atRegister:0x04
    	withDeviceDescription:deviceDescription];

	/* Read from the configuration table and check for a 'FB Address' key.
	 * If found, this value is used as the start_base_address. The original
	 * start_base_address is not touched.
	 * This provides a 'hidden' way out, when two or more video cards
	 * are in the system, but not all of them have a Millenium
	 * driver configured. The PCI BIOS might place the unused cards at
	 * an address which conflicts with the default start_base_address.
	 */
	overrideStartBaseAddress = NO;
	start_address = start_base_address;
	configTable = [deviceDescription configTable];
	if(configTable != nil) {
		fbkey = [configTable valueForStringKey:"FB Address"];
		if((fbkey != NULL) && (*fbkey != 0)) {
			unsigned long fb_address = (strtol(fbkey, NULL, 16) & 0x7F000000);
			if(fb_address >= 0x04000000) {	// Greater than 64MB
				start_address = fb_address;
				overrideStartBaseAddress = YES;
			}
		}
	}

    /*
     * Since many BIOS's do the bogus thing assume that the cards are not
     * initialized correctly.
     */
    bios_pci_config_ok = NO;

    /*
     * Bogus value. Start looking for framebuffer beginning at 1G in
     * increments of 16M. 
     */
    pci_config_fixed = NO;
    if (!bios_pci_config_ok) {
		for (base = start_address; base < 0xFF000000; base += incr) {
		    mem_range[0].start = base;
		    mem_range[0].size = incr;
		    rtn = [deviceDescription setMemoryRangeList:mem_range num:1];
		    if (rtn == IO_R_SUCCESS)
		    {
	#ifdef DEBUG
		    	IOLog(("%s: reserved %lx bytes at %lx\n", 
				[self name], mem_range[0].size, mem_range[0].start));
				[deviceDescription setMemoryRangeList:NULL num:0];
				[self_class setPCIConfigData:base+0x800000-0x4000 
					atRegister:MGA2064W_MGABASE1
			    	withDeviceDescription:deviceDescription];
				[self_class setPCIConfigData:base+0x800000 
					atRegister:MGA2064W_MGABASE2
			    	withDeviceDescription:deviceDescription];
				pci_config_fixed = YES;
				mem_range[0].start = base+0x800000-0x4000;
				mem_range[0].size = 0x4000;		/* 16 K */
				mem_range[1].start = base+0x800000;
				mem_range[1].size = 0x800000;
				num_mem_ranges = 2;
				IOLog_dbg(("%s: Memory range: 0x%lx - 0x%lx\n", [self name], 
					base, base + incr));
	#endif
				if(!overrideStartBaseAddress)
					start_base_address = base + incr;  /* for next card */
				break;
		    }
		    else
		    {
	#ifdef DEBUG
		    	IOLog(("%s: failed to reserve %lx bytes at %lx\n", 
				[self name], mem_range[0].start, mem_range[0].size));
	#endif
		    }
		}
    }

    if ((!bios_pci_config_ok) && (pci_config_fixed == NO))	{
    	IOLog("%s: Failed to find framebuffer address\n", [self name]);
		return_status = NO;
		goto abort;
    }

    if (primaryHead) {
		/*  Add the usual ranges.  */

		mem_range[num_mem_ranges].start = 0xA0000;
		mem_range[num_mem_ranges].size = 0x20000;
		mem_range[num_mem_ranges+1].start = 0xC0000;
		mem_range[num_mem_ranges+1].size = 0x10000;
		num_mem_ranges += 2;
	
		io_range[num_io_ranges].start = 0x3b0;
		io_range[num_io_ranges].size = 0x30;
		io_range[num_io_ranges+1].start = 0x102;
		io_range[num_io_ranges+1].size = 1;
		io_range[num_io_ranges+2].start = 0x46e8;
		io_range[num_io_ranges+2].size = 1;
		num_io_ranges += 3;
    }

    /*  Replace the memory range list in our device description
	with the one we just made.  The first invocation is sometimes
	necessary on 3.3; without it the memory ranges are not modified.  */
    /*  Note - it is assumed in this driver and elsewhere that the first
	range is for the frame buffer.  */

    [deviceDescription setMemoryRangeList:NULL num:0];
    rtn = [deviceDescription setMemoryRangeList:mem_range num:num_mem_ranges];
	if(rtn != IO_R_SUCCESS) {
		IOLog("%s: Error in setMemoryRangeList (%s)\n", [self name],
			[self stringFromReturn:rtn]);
		return_status = NO;
	}

    /*  Same for the I/O range list.  */

    [deviceDescription setPortRangeList:NULL num:0];
	if(primaryHead) {
    	rtn = [deviceDescription setPortRangeList:io_range num:num_io_ranges];
		if(rtn != IO_R_SUCCESS) {
			IOLog("%s: Error in setPortRangeList (%s)\n", [self name],
				[self stringFromReturn:rtn]);
			return_status = NO;
		}
	}

abort:

    /*
     * Restore memory space access. For primary cards also allow I/O space
     * access. 
     */
    [self_class getPCIConfigData:&cmd_status atRegister:0x04
		withDeviceDescription:deviceDescription];
    if (primaryHead) {
		cmd_status |= 0x03;
    } else {
		cmd_status |= 0x02;
	}
    [self_class setPCIConfigData:cmd_status atRegister:0x04
		withDeviceDescription:deviceDescription];
	
    return return_status;

#undef MAX_PCI_RANGES
}

@end
