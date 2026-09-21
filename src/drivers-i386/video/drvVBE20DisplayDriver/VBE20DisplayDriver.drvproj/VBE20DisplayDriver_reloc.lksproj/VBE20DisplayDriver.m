/*
 * VBE20DisplayDriver.m - VESA 2.0 display driver.
 *
 * Reconstructed against Apple's VBE20DisplayDriver_reloc from OPENSTEP 4.2
 * User Patch 4.  Function order follows the reference's __text.
 */

#import "VBE20DisplayDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

extern vm_offset_t	page_mask;

/*
 * The booter leaves the mode it put the adapter in, and the table of modes
 * it found, at fixed addresses inside KERNBOOTSTRUCT (0x11000): one 24-byte
 * record at +0x1858 and the array at +0x1870.  The reference reaches both by
 * absolute address - none of its loads and neither of its two pushes
 * (reference __text 519 and 659) carries a relocation, while every __cstring
 * push in the same function does - so these have to stay plain integer
 * constants with no symbol behind them.
 */
#define VBE_BOOTER_MODE		((VBEModeRec *)0x12858)
#define VBE_BOOTER_MODES	((VBEModeRec *)0x12870)
#define VBE_BOOTER_MODES_SIZE	0x880

/*
 * The mode list lives in two file statics, not in inherited ivars: the
 * reference's displayModes and displayModeCount each load from
 * __DATA,__data with a local relocation, and __data is exactly 8 bytes.
 * The explicit initialisers are what place them in __data rather than
 * __bss; the same is recorded in the comment on the file-scope state in
 * src/drivers-i386/video/drvVGA/VGA.drvproj/VGA.lksproj/IOVGADisplay.m.
 * In the reference the only stores to them are inside parseVESAModes:size:
 * (reference __text 692..984).
 */
static IODisplayInfo	*vbeDisplayModes = 0;		/* __data + 0 */
static unsigned int	 vbeDisplayModeCount = 0;	/* __data + 4 */

/*
 * Reference __text 0, 144 bytes.  A category's [super ...] resolves at run
 * time: reference __text 24 and 110 push __cstring+0, "IODisplay", into
 * objc_getOrigClass and store the result straight into objc_super, so both
 * sends here go to IOFrameBufferDisplay's superclass and skip
 * IOFrameBufferDisplay's own initFromDeviceDescription:.  The four stores
 * are to the inherited _pendingDisplayMode, _currentDisplayMode,
 * _displayModeCount and _displayModes, at 0x214, 0x210, 0x218 and 0x21c of
 * the 552-byte instance.  This implementation has to stay ahead of
 * @implementation VBE20DisplayDriver: it owns __text 0, and "IODisplay" is
 * the reference's first __cstring entry.
 */
@implementation IOFrameBufferDisplay (UnnamedInitialization)

- (id)initUnnamedFromDeviceDescription:(IODeviceDescription *)devDesc
{
    if ([super initFromDeviceDescription:devDesc] == nil)
	return [super free];

    _currentDisplayMode = _pendingDisplayMode = -1;
    _displayModeCount = -1;
    _displayModes = NULL;

    return self;
}

@end

@implementation VBE20DisplayDriver

/* Reference __text 144, 548 bytes. */
- (id)initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IODisplayInfo	*displayInfo;
    IORange		 range;
    unsigned int	 physAddr = 0;
    unsigned int	 length;
    vm_address_t	 virtAddr;
    IOReturn		 ret;

    if (VBE_BOOTER_MODE->xResolution != 0) {
	physAddr = (unsigned int)VBE_BOOTER_MODE->frameBuffer;

	/*
	 * Reference defect, reproduced verbatim: the extent of the frame
	 * buffer is bytesPerScanline * yResolution, but reference __text
	 * 188 reads the record's +4 (xResolution), not its +6.  The
	 * kernel's own VBEModeInfo2IODisplayInfo uses +6 for the same
	 * record.  Emitting +6 here would change 0FB7155C280100 into
	 * 0FB7155E280100 and lose byte parity, so the defect stays; see
	 * reconstruction/divergences.md.
	 */
	length = VBE_BOOTER_MODE->bytesPerScanline *
		 VBE_BOOTER_MODE->xResolution;

	range.start = physAddr & ~page_mask;
	range.size = (length + (physAddr & page_mask) + page_mask) &
		     ~page_mask;

	[devDesc setMemoryRangeList:NULL num:0];
	ret = [devDesc setMemoryRangeList:&range num:1];
	if (ret != IO_R_SUCCESS) {
	    IOLog("VBEDisplay: Error in setMemoryRangeList (%s)\n",
		  [self stringFromReturn:ret]);
	    return [self free];
	}

	if ([super initFromDeviceDescription:devDesc] == nil)
	    return [self free];
    } else {
	if ([super initUnnamedFromDeviceDescription:devDesc] == nil)
	    return [self free];
	[self setName:"VBEDisplay0"];
    }

    IOLog("%s: VESA video driver initialization.\n", [self name]);

    if (VBE_BOOTER_MODE->xResolution == 0) {
	IOLog("%s: Skipping framebuffer initialization (card not in VBE mode).\n", [self name]);
	IOLog("%s: Driver loaded to export VBE mode list.\n", [self name]);
    } else {
	displayInfo = [self displayInfo];
	[self initDisplayInfo:displayInfo fromVBEModeInfo:VBE_BOOTER_MODE];

	virtAddr = [self mapFrameBufferAtPhysicalAddress:range.start
		    length:range.size];
	if (virtAddr == 0) {
	    IOLog("%s: Unable to map frame buffer\n", [self name]);
	    return [self free];
	}
	displayInfo->frameBuffer =
	    (void *)(virtAddr + physAddr - range.start);

	IOLog("%s: using VBE mode %d\n", [self name],
	      VBE_BOOTER_MODE->modeNumber);
    }

    [self parseVESAModes:VBE_BOOTER_MODES size:VBE_BOOTER_MODES_SIZE];

    return self;
}

/* Reference __text 1916, 8 bytes.  The reference body is empty. */
- (void)enterLinearMode
{
}

/* Reference __text 1924, 8 bytes. */
- (void)revertToVGAMode
{
}

/* Reference __text 2276, 12 bytes. */
- (unsigned int)displayModeCount
{
    return vbeDisplayModeCount;
}

/* Reference __text 2288, 12 bytes. */
- (IODisplayInfo *)displayModes
{
    return vbeDisplayModes;
}

@end
