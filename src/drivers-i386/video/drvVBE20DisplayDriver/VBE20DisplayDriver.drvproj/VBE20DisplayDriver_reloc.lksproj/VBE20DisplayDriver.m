/*
 * VBE20DisplayDriver.m - VESA 2.0 display driver.
 *
 * Reconstructed against Apple's VBE20DisplayDriver_reloc from OPENSTEP 4.2
 * User Patch 4.  Function order follows the reference's __text.
 */

#import "VBE20DisplayDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

#import <stdio.h>
#import <string.h>

extern vm_offset_t	page_mask;

/*
 * The one kernel routine this driver calls.  Its argument order is the
 * reference's, not the selector's.  The forwarder's method type encoding,
 * reference __OBJC,__meth_var_types+163, is
 *
 *	v16@8:12^{?=iiiii^vii[64c]I^viiiiiiI[1I]}16^{?=SSSSSCCCCCCCC^v}20
 *
 * where the first struct is IODisplayInfo and the second is VBEModeRec.  That
 * puts the IODisplayInfo * at frame 16 and the VBEModeRec * at frame 20, and
 * reference __text 987..994 pushes frame 16 first and frame 20 second, so the
 * record is the C call's first argument.  The kernel side only ever reads
 * through the first and only ever writes through the second.
 *
 * The callee is _VBEModeInfo2IODisplayInfo at 0x0019ED8C in the i386 slice of
 * the OPENSTEP 4.2 User Patch 4 mach_kernel (slice SHA-256
 * 33469393C0843FC741942C3AE9D91D838467D72ABD647DCF2E5BF499A3F14890);
 * reconstruction/divergences.md, D2, has the listing.  The return type is
 * inferred void - no path in that function, 0x0019ED8C..0x0019EFA6, loads eax
 * with a result - and nothing in the reference would distinguish void from an
 * ignored result.
 *
 * It stays an undefined external: the relocatable Kernel Server link leaves
 * it unresolved and the kernel supplies the definition at load time.
 */
extern void	VBEModeInfo2IODisplayInfo(VBEModeRec *mode,
					  IODisplayInfo *info);

/*
 * parseVESAModes:size: allocates its IODisplayInfo array with the kernel's
 * calloc - reference __text 828, with an external relocation naming _calloc
 * at 829.  No driverkit header declares it, so the declaration is here.
 */
extern void	*calloc(size_t count, size_t size);

/*
 * The reference's booter (OPENSTEP 4.2 User Patch 4) leaves the mode it put
 * the adapter in, and the table of modes it found, at fixed addresses inside
 * KERNBOOTSTRUCT (0x11000): one 24-byte record at +0x1858 and the array at
 * +0x1870.  The reference reaches both by absolute address - none of its
 * loads and neither of its two pushes (reference __text 519 and 659)
 * carries a relocation, while every __cstring push in the same function
 * does - so these have to stay plain integer constants with no symbol
 * behind them.
 *
 * This tree's booter does not write there.  In Rhapsody's KERNBOOTSTRUCT
 * (src/boot-2/i386/libsa/kernBootStruct.h) both offsets fall inside
 * _reserved[7500], which nothing under src/ writes; the booter's only
 * video hand-off is kernBootStruct->video, at
 * src/boot-2/i386/boot2/graphics.c:204-208.
 */

/*
 * VBE_BOOTER_MODE is the one record for the mode the booter set the adapter
 * to; VBE_BOOTER_MODES is the array of every mode it found.  Two different
 * things one letter apart, not interchangeable: the record sits 0x18 bytes,
 * one record, before the array.
 *
 * On a Rhapsody boot today both addresses are _reserved slack that
 * getKernBootStruct() zeroes and nothing fills, so xResolution reads 0 and
 * the driver takes the "card not in VBE mode" path and exports an empty mode
 * list.
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
 *
 * The count is signed even though displayModeCount returns it as
 * unsigned int (the reference's own encoding for that method is I8@8:12):
 * parseVESAModes:size: walks its array with "cmp ds:2004h, edi" and
 * jle / jg at reference __text 849 and 972, which are signed branches, so
 * both the counter and the loop index are int.  IOFrameBufferDisplay does
 * the same with its own _displayModeCount.
 */
static IODisplayInfo	*vbeDisplayModes = 0;		/* __data + 0 */
static int		 vbeDisplayModeCount = 0;	/* __data + 4 */

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
    /*
     * "[super free]", not "[self free]", is the reference's, and it is not a
     * typo: a category's super is IODisplay, so on this path
     * IOFrameBufferDisplay's own -free is skipped.  Reference __text 130 is
     * a call to _objc_msgSendSuper, whereas the three failure returns in
     * initFromDeviceDescription: share one _objc_msgSend to self, at __text
     * 598.  Writing [self free] here would change the emitted call.
     */
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
	IOLog("%s: Skipping framebuffer initialization "
	      "(card not in VBE mode).\n", [self name]);
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

/*
 * Reference __text 692, 292 bytes.  Counts the booter's mode records, then
 * builds one IODisplayInfo per record.
 *
 * The bound is the array's byte size, not a record count: reference __text
 * 747..755 forms 24 * (count + 1) and stops once it reaches size.  0x880 is
 * not a multiple of 24 - it is 24 * 90 + 16 - so the ceiling is 90 records
 * accepted, indices 0..89, the same ceiling the booter's own enumerator
 * carries.  The last 16 bytes (+2160..+2175) are slack that is read from but
 * never accepted: once 90 records are counted, the terminator test reads
 * modes[90].xResolution at +2164, inside that slack and inside size, and if
 * it is non-zero the size check (24 * 91 >= size) stops the walk there.
 */
- (void)parseVESAModes:(VBEModeRec *)modes size:(unsigned int)size
{
    int		i;

    if (vbeDisplayModes != NULL)
	return;

    vbeDisplayModeCount = 0;
    while (modes[vbeDisplayModeCount].xResolution != 0) {
	if ((vbeDisplayModeCount + 1) * sizeof(VBEModeRec) >= size)
	    break;
	vbeDisplayModeCount++;
    }

    if (vbeDisplayModeCount == 0) {
	IOLog("%s: No VBE modes found.\n", [self name]);
	return;
    }

    vbeDisplayModes = calloc(vbeDisplayModeCount, sizeof(IODisplayInfo));

    for (i = 0; i < vbeDisplayModeCount; i++) {
	[self initDisplayInfo:&vbeDisplayModes[i] fromVBEModeInfo:&modes[i]];
	IOLog("%s: VBE mode %d is width=%d, height=%d, bpp=%d\n",
	      [self name], modes[i].modeNumber, vbeDisplayModes[i].width,
	      vbeDisplayModes[i].height, modes[i].bitsPerPixel);
    }
}

/*
 * Reference __text 984, 20 bytes.  The whole body is the call.  The kernel
 * routine is also what writes the VBE mode number into the info's
 * parameters field (IODisplayInfo + 0x64): nothing in this driver stores
 * there, and getCharValues:forParameter:count: reads it back.
 */
- (void)initDisplayInfo:(IODisplayInfo *)info fromVBEModeInfo:(VBEModeRec *)mode
{
    VBEModeInfo2IODisplayInfo(mode, info);
}

/*
 * Reference __text 1004, 188 bytes (187 of body and one 90 pad).  Builds the
 * short human-readable mode string in the first of the driver's three static
 * buffers, reference __bss+0, 80 bytes.
 *
 * Which IODisplayInfo field feeds which conversion is taken from the loads,
 * not from the format string's wording: reference __text 1011 pushes [ebx+0]
 * and 1014 pushes [ebx+4], and cdecl pushes right to left, so the argument
 * printed by the *first* %d - the one labelled "Height:" - is the field at
 * +4, height, and the second is +0, width.  The label order and the struct
 * order are opposites here.
 */
- (char *)modeStringForDisplayInfo:(IODisplayInfo *)info
{
    static char	modeString[80];

    sprintf(modeString, "Height:%d Width:%d Refresh:0Hz ColorSpace:",
	    info->height, info->width);

    /*
     * Reference __text 1036 is "cmp dword ptr [ebx+1Ch], 2" against
     * IODisplayInfo.colorSpace, then one jnz - a two-way test, not a switch.
     * The six strcat calls inside the two switches are cross-jumped by the
     * compiler into the single "push buf; call _strcat" at reference __text
     * 1169, which is why that call has no stack cleanup after it: "mov esp,
     * ebp" in the epilogue does it.  The two prefix strcats, "RGB:" at 1042
     * and "BW:" at 1124, keep their own cleanup because code follows them.
     * Nothing in the source expresses that merge.
     *
     * Neither switch has a default: on an unlisted bitsPerPixel the reference
     * jumps straight to the return at __text 1179 with the colour-space
     * prefix already appended and nothing after it.
     */
    if (info->colorSpace == IO_RGBColorSpace) {
	strcat(modeString, "RGB:");
	switch (info->bitsPerPixel) {
	case IO_8BitsPerPixel:
	    strcat(modeString, "256/8");
	    break;
	case IO_12BitsPerPixel:
	    strcat(modeString, "444/16");
	    break;
	case IO_15BitsPerPixel:
	    strcat(modeString, "555/16");
	    break;
	case IO_24BitsPerPixel:
	    strcat(modeString, "888/32");
	    break;
	}
    } else {
	strcat(modeString, "BW:");
	switch (info->bitsPerPixel) {
	case IO_2BitsPerPixel:
	    strcat(modeString, "2");
	    break;
	case IO_8BitsPerPixel:
	    strcat(modeString, "8");
	    break;
	}
    }

    return modeString;
}

/*
 * Reference __text 1192, 48 bytes.  The driver's own, and narrower than C's
 * atoi: no sign, no leading whitespace, no base prefix, no overflow check.
 * The reference's undefined-symbol list holds no atoi, strtol, strtoul or
 * sscanf, so within that binary there was nothing to call; why it was
 * hand-written is not determinable from the reference.  It has to stay a
 * method: the reference reaches it through objc_msgSend on
 * __OBJC,__message_refs+44 from all four of its uses.
 */
- (unsigned int)atoi:(const char *)s
{
    unsigned int	val = 0;

    while (*s != '\0') {
	if (*s < '0' || *s > '9')
	    break;
	/*
	 * Unparenthesised: reference __text 1221..1224 reloads the digit
	 * with movsx and folds both the add and the - '0' into one
	 * "lea edx, [edx+eax-30h]".  Writing "+ (*s - '0')" instead lets
	 * the compiler attach the constant to the multiply, which emits
	 * the same four instructions in a different order.
	 */
	val = val * 10 + *s - '0';
	s++;
    }

    return val;
}

/* Reference __text 1916, 8 bytes.  The reference body is empty. */
- (void)enterLinearMode
{
}

/* Reference __text 1924, 8 bytes. */
- (void)revertToVGAMode
{
}

/*
 * Reference __text 1932, 244 bytes (242 of body, including the 24-byte jump
 * table at 1960, and two 90 pads).  Dumps one IODisplayInfo into the second
 * static buffer, reference __bss+80, 512 bytes.
 *
 * Both locals start as NULL - reference __text 1940 and 1942 are "xor ecx,
 * ecx" and "xor ebx, ebx" - and neither switch has a default, so an
 * out-of-range enum reaches the sprintf with a null %s.
 *
 * The switch on bitsPerPixel compiles to a jump table (bounds check "cmp
 * dword ptr [edx+18h], 5 / ja" at 1944 and the indirect jump at 1953), the
 * one on colorSpace to a compare tree, because its cases 0, 1, 2 and 5 are
 * not dense.  Both compares are unsigned, which is what switching on an
 * all-non-negative enum gives.
 *
 * The seventeen values pushed at reference __text 2081..2144 are the
 * IODisplayInfo fields at +0, +4, +8, +0Ch, +10h, +14h, the two strings,
 * +20h, +60h, +64h, +68h, +6Ch, +74h, +78h, +7Ch and +80h.  +70h is absent:
 * that is _reserved1, and the reference does not print it.
 */
- (char *)descriptionForDisplayInfo:(IODisplayInfo *)info
{
    static char	 description[512];
    char	*bitsPerPixelString = NULL;
    char	*colorSpaceString = NULL;

    switch (info->bitsPerPixel) {
    case IO_2BitsPerPixel:
	bitsPerPixelString = "IO_2BitsPerPixel";
	break;
    case IO_8BitsPerPixel:
	bitsPerPixelString = "IO_8BitsPerPixel";
	break;
    case IO_12BitsPerPixel:
	bitsPerPixelString = "IO_12BitsPerPixel";
	break;
    case IO_15BitsPerPixel:
	bitsPerPixelString = "IO_15BitsPerPixel";
	break;
    case IO_24BitsPerPixel:
	bitsPerPixelString = "IO_24BitsPerPixel";
	break;
    case IO_VGA:
	bitsPerPixelString = "IO_VGA";
	break;
    }

    switch (info->colorSpace) {
    case IO_OneIsBlackColorSpace:
	colorSpaceString = "IO_OneIsBlackColorSpace";
	break;
    case IO_OneIsWhiteColorSpace:
	colorSpaceString = "IO_OneIsWhiteColorSpace";
	break;
    case IO_RGBColorSpace:
	colorSpaceString = "IO_RGBColorSpace";
	break;
    case IO_CMYKColorSpace:
	colorSpaceString = "IO_CMYKColorSpace";
	break;
    }

    sprintf(description,
	    "width=%d height=%d totalWidth=%d rowBytes=%d refreshRate=%d "
	    "frameBuffer=%x bitsPerPixel=%s colorSpace=%s pixelEncoding=%s "
	    "flags=%x parameters=%x memorySize=%d scanRate=%d "
	    "dotClockRate=%d screenWidth=%d screenHeight=%d "
	    "modeUnavailableFlag=%x",
	    info->width, info->height, info->totalWidth, info->rowBytes,
	    info->refreshRate, info->frameBuffer, bitsPerPixelString,
	    colorSpaceString, info->pixelEncoding, info->flags,
	    info->parameters, info->memorySize, info->scanRate,
	    info->dotClockRate, info->screenWidth, info->screenHeight,
	    info->modeUnavailableFlag);

    return description;
}

/*
 * Reference __text 2176, 100 bytes (98 of body and two 90 pads).  Dumps one
 * raw booter record into the third static buffer, reference __bss+592, 512
 * bytes.  This is what the VBEBooterMode parameters answer with.
 *
 * The push widths at reference __text 2182..2249 are what fix VBEModeRec's
 * field widths: five movzx from word (+0, +2, +4, +6, +8), eight movzx from
 * byte (+0Ah..+11h) and one dword load (+14h).  The three mask sizes and the
 * three field positions are interleaved in the record - size, position, size,
 * position, size, position - but printed grouped, all three sizes and then
 * all three positions, so the push order is +0Ch, +0Eh, +10h, +0Dh, +0Fh,
 * +11h and not the record's own order.
 */
- (char *)descriptionForVBEMode:(VBEModeRec *)mode
{
    static char	description[512];

    sprintf(description,
	    "mode num: %d, Attrib: %x, BytesPerScanline: %d, FrameBuffer: %x,\n"
	    "XRes: %d, YRes: %d, BitsPerPixel: %d, MemoryModel: %d,\n"
	    "RGB Mask Sizes: (%d, %d, %d), RGB Field Pos: (%d, %d, %d)\n",
	    mode->modeNumber, mode->modeAttributes, mode->bytesPerScanline,
	    mode->frameBuffer, mode->xResolution, mode->yResolution,
	    mode->bitsPerPixel, mode->memoryModel, mode->redMaskSize,
	    mode->greenMaskSize, mode->blueMaskSize, mode->redFieldPosition,
	    mode->greenFieldPosition, mode->blueFieldPosition);

    return description;
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
