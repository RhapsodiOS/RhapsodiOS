/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright (c) 1997 Apple Computer, Inc.
 *
 *
 * HISTORY
 *
 * Simon Douglas  22 Oct 97
 * - first checked in.
 */


#define KERNOBJC 1			// remove
#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#import <driverkit/generalFuncs.h>
#import <driverkit/IODisplay.h>
#import <driverkit/IODisplayPrivate.h>
#import	<driverkit/IOFrameBufferShared.h>
#import	<bsd/dev/kmreg_com.h>
#import	<bsd/dev/ppc/kmDevice.h>

#import <mach/vm_param.h>       /* for round_page() */
#import <machdep/ppc/proc_reg.h>
#import <string.h>

#import	<driverkit/ppc/IOFramebuffer.h>
#import	"IONDRVFramebuffer.h"

extern IODisplayInfo	bootDisplayInfo;

@implementation IONDRVFramebuffer

//=======================================================================

- (IOReturn)doControl:(UInt32)code params:(void *)params
{
    IOReturn	err;
    CntrlParam	pb;

    pb.qLink = 0;
    pb.csCode = code;
    pb.csParams = params;

    err = NDRVDoDriverIO( doDriverIO, /*ID*/ (UInt32) &pb, &pb,
	kControlCommand, kImmediateIOCommandKind );

    return( err);
}

- (IOReturn)doStatus:(UInt32)code params:(void *)params
{
    IOReturn	err;
    CntrlParam	pb;

    pb.qLink = 0;
    pb.csCode = code;
    pb.csParams = params;

    err = NDRVDoDriverIO( doDriverIO, /*ID*/ (UInt32) &pb, &pb,
	kStatusCommand, kImmediateIOCommandKind );

    return( err);
}

//=======================================================================

+ (BOOL)probe:device
{
    id		inst;
    Class       newClass = self;
    char *	name;

    if( NDRVForDevice( device)) {
        // Hardware-specific driver selection based on device node name
        name = [device nodeName];

        // Check for ATI Rage 128
        if( 0 == strncmp("ATY,Rage128", name, 11)) {
            newClass = [IOATIRAGE128NDRV class];
        }
        // Check for other ATI cards (Mach64-based)
        else if( 0 == strncmp("ATY,", name, 4)) {
            newClass = [IOATIMACH64NDRV class];
        }
        // Check for IMS TwinTurbo 128
        else if( 0 == strncmp("IMS,tt128", name, 9)) {
            newClass = [IOIXMNDRV class];
        }
        // Check for IMS TwinTurbo 3D
        else if( 0 == strncmp("IMS,tt3d", name, 8)) {
            newClass = [IOIX3DNDRV class];
        }
    } else
	newClass = [IOOFFramebuffer class];

    // Create an instance and initialize
    inst = [[newClass alloc] initFromDeviceDescription:device];
    if (inst == nil)
        return NO;

    [inst setDeviceKind:"Linear Framebuffer"];

    [inst registerDevice];

    return YES;
}

- initFromDeviceDescription:(IOPCIDevice *) deviceDescription
{
    id			me = nil;
    kern_return_t	err = 0;
    UInt32		i, propSize;
    UInt32		numMaps = 8;
    IOApertureInfo	maps[ numMaps ];	// FIX
    IOLogicalAddress	aaplAddress[ 8 ];	// FIX
    IOApertureInfo   *	map;
    IOPropertyTable  *	propTable;
    void *		prop;
    char *		logname;
    InterruptSetMember	intsProperty[ 3 ];

    do {
   	ioDevice = deviceDescription;
	logname = [ioDevice nodeName];
	propTable = [ioDevice propertyTable];

	prop = &ndrvInst;
	propSize = sizeof( NDRVInstance);
	err = [propTable getProperty:"AAPL,ndrvInst" flags:0 value:&prop length:&propSize];
	if( err)
	    continue;
	err = NDRVGetSymbol( ndrvInst, "DoDriverIO", &doDriverIO );
	if( err)
	    continue;
	err = NDRVGetSymbol( ndrvInst, "TheDriverDescription", (void **)&theDriverDesc );
	if( err)
	    continue;

	transferTable = IOMalloc(sizeof( ColorSpec) * 256);    // Initialize transfer table variables.
	brightnessLevel = EV_SCREEN_MAX_BRIGHTNESS;
	scaledTable = 0;
	cachedModeIndex = 0x7fffffff;

	numMaps = 8;
	err = [ioDevice getApertures:maps items:&numMaps];
	if( err)
	    continue;

	for( i = 0, map = maps; i < numMaps; i++, map++) {

	    if( (((UInt32)bootDisplayInfo.frameBuffer) >= ((UInt32)map->physical))
	    &&  (((UInt32)bootDisplayInfo.frameBuffer) < (map->length + (UInt32)map->physical)) )
		consoleDevice = YES;

	    // this means any graphics card grabs a BAT for the segment.
	    aaplAddress[ i ] = PEMapSegment( map->physical, 0x10000000);
	    if( aaplAddress[ i ] != map->physical) {
		IOLog("%s: NDRV needs 1-1 mapping\n", logname);
		err = IO_R_VM_FAILURE;
		break;
	    }

#if 0
           // Declare range for pmap'ing into user space
           // Shouldn't be here but it's too expensive to do it for all devices
           if( map->length > 0x01000000)
               map->length = 0x01000000;               // greed hack
           err = pmap_add_physical_memory( map->physical,
                                           map->physical + map->length, FALSE, PTE_WIMG_IO);
           if(err)
               kprintf("%s: pmap_add_physical_memory: %d for 0x%08x - 0x%08x\n",
                       logname, err, map->physical, map->physical + map->length);
#endif
	}
	if( err)
	    continue;

	// NDRV aperture vectors
        [propTable deleteProperty:"AAPL,address"];
        err = [propTable createProperty:"AAPL,address" flags:0
		    value:aaplAddress length:(numMaps * sizeof( IOLogicalAddress))];
	if( err)
	    continue;

	// interrupt tree for NDRVs - not really
	err = [propTable createProperty:"driver-ist" flags:0
		    value:intsProperty length:sizeof( intsProperty)];

	// tell kmDevice if it's on the boot console, it's going away
	if( consoleDevice)
	    [kmId unregisterDisplay:nil];

	err = [self checkDriver];
	if( err) {
	    kprintf("%s: Not usable\n", logname );
            if( err == -999)
                IOLog("%s: Driver is incompatible.\n", logname );
	    continue;
	}

	if (nil == [super initFromDeviceDescription:deviceDescription])
	    continue;
	err = [self open];
	if( err)
	    continue;

#if 0
	if ([self startIOThread] != IO_R_SUCCESS)
	    kprintf("startIOThread FAIL\n");
	[self enableAllInterrupts];
#endif

	me = self;			// Success

    } while( false);

    if( me == nil)
	[super free];

    return( me);
}


- free
{
    if (transferTable != 0) {
        IOFree(transferTable, 256 * sizeof( ColorSpec));
    }
    return [super free];
}


- (IOReturn)
    getDisplayModeTiming:(IOFBIndex)connectIndex mode:(IOFBDisplayModeID)modeID
		timingInfo:(IOFBTimingInformation *)info connectFlags:(UInt32 *)flags
{
    VDTimingInfoRec		timingInfo;
    OSStatus			err;

    timingInfo.csTimingMode = modeID;
    timingInfo.csTimingFormat = kDeclROMtables;			// in case the driver doesn't do it
    err = [self doStatus:cscGetModeTiming params:&timingInfo];
    if( err == noErr) {
	if( timingInfo.csTimingFormat == kDeclROMtables)
	    info->standardTimingID = timingInfo.csTimingData;
	else
	    info->standardTimingID = timingInvalid;
	*flags = timingInfo.csTimingFlags;
	return( [super getDisplayModeTiming:connectIndex mode:modeID timingInfo:info connectFlags:flags]);
    }
    *flags = 0;
    return( IO_R_UNDEFINED_MODE);
}

- (IOReturn)
    getDisplayModeByIndex:(IOFBIndex)modeIndex displayMode:(IOFBDisplayModeID *)displayModeID
{

    // unfortunately, there is no "kDisplayModeIDFindSpecific"
    if( modeIndex <= cachedModeIndex) {
	cachedModeID = kDisplayModeIDFindFirstResolution;
	cachedModeIndex = -1;
    }

    cachedVDResolution.csPreviousDisplayModeID = cachedModeID;

    while(
 	   (noErr == [self doStatus:cscGetNextResolution params:&cachedVDResolution])
	&& ((SInt32) cachedVDResolution.csDisplayModeID > 0) ) {

	    cachedVDResolution.csPreviousDisplayModeID = cachedVDResolution.csDisplayModeID;

	    if( modeIndex == ++cachedModeIndex) {
		cachedModeID 		= cachedVDResolution.csDisplayModeID;
		*displayModeID		= cachedModeID;
		return( noErr);
	    }
    }
    cachedModeIndex = 0x7fffffff;
    return( IO_R_UNDEFINED_MODE);
}


- (IOReturn)
    getResInfoForMode:(IOFBDisplayModeID)modeID info:(VDResolutionInfoRec **)theInfo
{

    *theInfo = &cachedVDResolution;

    if( cachedVDResolution.csDisplayModeID == modeID)
	return( noErr);

    cachedVDResolution.csPreviousDisplayModeID = kDisplayModeIDFindFirstResolution;

    while(
	(noErr == [self doStatus:cscGetNextResolution params:&cachedVDResolution])
    && ((SInt32) cachedVDResolution.csDisplayModeID > 0) )
    {
	cachedVDResolution.csPreviousDisplayModeID = cachedVDResolution.csDisplayModeID;
	if( cachedVDResolution.csDisplayModeID == modeID)
	    return( noErr);
    }
    cachedVDResolution.csDisplayModeID = -1;
    return( IO_R_UNDEFINED_MODE);
}

- (IOReturn)
    getDisplayModeInformation:(IOFBDisplayModeID)modeID info:(IOFBDisplayModeInformation *)info
{
    IOReturn			err;
    VDResolutionInfoRec	*	resInfo;

    do {
	err = [self getResInfoForMode:modeID info:&resInfo];
	if( err)
	    continue;
	info->displayModeID	= resInfo->csDisplayModeID;
	info->maxDepthIndex	= resInfo->csMaxDepthMode - kDepthMode1;
	info->nominalWidth	= resInfo->csHorizontalPixels;
	info->nominalHeight	= resInfo->csVerticalLines;
	info->refreshRate	= resInfo->csRefreshRate;
	return( noErr);
    } while( false);

    return( IO_R_UNDEFINED_MODE);
}


- (IOReturn)
    getPixelInformationForDisplayMode:(IOFBDisplayModeID)modeID andDepthIndex:(IOFBIndex)depthIndex
    	pixelInfo:(IOFBPixelInformation *)info
{
    SInt32		err;

    VDVideoParametersInfoRec	pixelParams;
    VPBlock			pixelInfo;
    VDResolutionInfoRec	*	resInfo;

    do {
	err = [self getResInfoForMode:modeID info:&resInfo];
	if( err)
	    continue;
    	pixelParams.csDisplayModeID = modeID;
	pixelParams.csDepthMode = depthIndex + kDepthMode1;
	pixelParams.csVPBlockPtr = &pixelInfo;
	err = [self doStatus:cscGetVideoParameters params:&pixelParams];
	if( err)
	    continue;

	info->flags 			= 0;
	info->rowBytes             	= pixelInfo.vpRowBytes & 0x7fff;
	info->width                	= pixelInfo.vpBounds.right;
	info->height               	= pixelInfo.vpBounds.bottom;
	info->refreshRate          	= resInfo->csRefreshRate;
	info->pageCount 		= 1;
	info->pixelType 		= (pixelInfo.vpPixelSize <= 8) ?
					kIOFBRGBCLUTPixelType : kIOFBDirectRGBPixelType;
	info->bitsPerPixel 		= pixelInfo.vpPixelSize;
//	info->channelMasks 		=

    } while( false);

    return( err);
}

- (IOReturn) open
{
    IOReturn	err;

    do {
	err = [self checkDriver];
	if( err)
	    continue;
	err = [super open];

    } while( false);

    return( err);
}

- (IOReturn) checkDriver
{
    OSStatus			err = noErr;
    struct  DriverInitInfo	initInfo;
    CntrlParam          	pb;
    IOFBConfiguration		config;
    VDClutBehavior		clutSetting = kSetClutAtSetEntries;

    if( ndrvState == 0) {
	do {
	    initInfo.refNum = 0xffcd;			// ...sure.
	    MAKE_REG_ENTRY(initInfo.deviceEntry, ioDevice)

	    err = NDRVDoDriverIO( doDriverIO, 0, &initInfo, kInitializeCommand, kImmediateIOCommandKind );
	    if( err) continue;

	    err = NDRVDoDriverIO( doDriverIO, 0, &pb, kOpenCommand, kImmediateIOCommandKind );
	    if( err) continue;

	} while( false);
	if( err)
	    return( err);

	{
	    VDVideoParametersInfoRec	pixelParams;
	    VPBlock			pixelInfo;
	    VDResolutionInfoRec		vdRes;
	    UInt32			size;

	    vramLength = 0;
	    vdRes.csPreviousDisplayModeID = kDisplayModeIDFindFirstResolution;
	    while(
		(noErr == [self doStatus:cscGetNextResolution params:&vdRes])
	    && ((SInt32) vdRes.csDisplayModeID > 0) )
	    {

		pixelParams.csDisplayModeID = vdRes.csDisplayModeID;
		pixelParams.csDepthMode = vdRes.csMaxDepthMode;
		pixelParams.csVPBlockPtr = &pixelInfo;
		err = [self doStatus:cscGetVideoParameters params:&pixelParams];
		if( err)
		    continue;

                // Control hangs its framebuffer off the end of the aperture to support
                // 832 x 624 @ 32bpp. The commented out version will correctly calculate
		// the vram length, but DPS needs the full extent to be mapped, so we'll
                // end up mapping an extra page that will address vram through the little
                // endian aperture. No other drivers like this known.
#if 1
		size = 0x40 + pixelInfo.vpBounds.bottom * (pixelInfo.vpRowBytes & 0x7fff);
#else
		size = ( (pixelInfo.vpBounds.right * pixelInfo.vpPixelSize) / 8)	// last line
			+ (pixelInfo.vpBounds.bottom - 1) * (pixelInfo.vpRowBytes & 0x7fff);
#endif
		if( size > vramLength)
		    vramLength = size;

		vdRes.csPreviousDisplayModeID = vdRes.csDisplayModeID;
	    }

	    err = [self getConfiguration:&config];
	    vramBase = config.physicalFramebuffer;
	    vramLength = (vramLength + (vramBase & 0xffff) + 0xffff) & 0xffff0000;
	    vramBase &= 0xffff0000;

#if 1
	    // Declare range for pmap'ing into user space
	    // Shouldn't be here but it's too expensive to do it for all devices
	    err = pmap_add_physical_memory( vramBase,
					    vramBase + vramLength, FALSE, PTE_WIMG_IO);
	    if(err)
		kprintf("%s: pmap_add_physical_memory: %d for 0x%08x - 0x%08x\n",
			[self name], err, vramBase, vramBase + vramLength );
#endif
	}

	// Set CLUT immediately since there's no VBL.
	[self doControl:cscSetClutBehavior params:&clutSetting];

	ndrvState = 1;
    }
    return( noErr);
}


- (IOReturn)
    setDisplayMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex page:(IOFBIndex)pageIndex;
{
    SInt32		err;
    VDSwitchInfoRec	switchInfo;
    VDPageInfo		pageInfo;

    switchInfo.csData = modeID;
    switchInfo.csMode = depthIndex + kDepthMode1;
    switchInfo.csPage = pageIndex;
    err = [self doControl:cscSwitchMode params:&switchInfo];
    if(err)
	IOLog("%s: cscSwitchMode:%d\n",[self name],(int)err);

    // duplicate QD InitGDevice
    pageInfo.csMode = switchInfo.csMode;
    pageInfo.csData = 0;
    pageInfo.csPage = pageIndex;
    [self doControl:cscSetMode params:&pageInfo];
    [self doControl:cscGrayPage params:&pageInfo];

    return( err);
}

- (IOReturn)
    setStartupMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex;
{
    SInt32		err;
    VDSwitchInfoRec	switchInfo;

    switchInfo.csData = modeID;
    switchInfo.csMode = depthIndex + kDepthMode1;
    err = [self doControl:cscSavePreferredConfiguration params:&switchInfo];
    return( err);
}

- (IOReturn)
    getStartupMode:(IOFBDisplayModeID *)modeID depth:(IOFBIndex *)depthIndex
{
    SInt32		err;
    VDSwitchInfoRec	switchInfo;

    err = [self doStatus:cscGetPreferredConfiguration params:&switchInfo];
    if( err == noErr) {
	*modeID		= switchInfo.csData;
	*depthIndex	= switchInfo.csMode - kDepthMode1;
    }
    return( err);
}


- (IOReturn)
    getConfiguration:(IOFBConfiguration *)config;
{
    IOReturn		err;
    VDSwitchInfoRec	switchInfo;
    VDGrayRecord	grayRec;

    bzero( config, sizeof( IOFBConfiguration));

    grayRec.csMode = 0;			// turn off luminance map
    err = [self doControl:cscSetGray params:&grayRec];
    if( (noErr == err) && (0 != grayRec.csMode))
        // driver refused => mono display
	config->flags |= kFBLuminanceMapped;

    err = [self doStatus:cscGetCurMode params:&switchInfo];
    config->displayMode		= switchInfo.csData;
    config->depth		= switchInfo.csMode - kDepthMode1;
    config->page		= switchInfo.csPage;
    config->physicalFramebuffer	= ((UInt32) switchInfo.csBaseAddr);
    config->mappedFramebuffer	= config->physicalFramebuffer;		// assuming 1-1

    return( err);
}

- (IOReturn)
    getApertureInformationByIndex:(IOFBIndex)apertureIndex
    	apertureInfo:(IOFBApertureInformation *)apertureInfo
{
    IOReturn		err;

    if( apertureIndex == 0) {
	apertureInfo->physicalAddress 	=	vramBase;
	apertureInfo->mappedAddress 	=	vramBase;
	apertureInfo->length 		=	vramLength;
	apertureInfo->cacheMode 	=	0;
	apertureInfo->type		=	kIOFBGraphicsMemory;
	err = noErr;
    } else
	err = IO_R_UNDEFINED_MODE;

    return( err);
}

#if 0

- (IOReturn) getInterruptFunctionsTV:(UInt32)member
			refCon:(void **)refCon,
			handler:(TVector *) handler,
			enabler:(TVector *) enabler,
			disabler:(TVector *) disabler

{
    OSStatus	err;

    err = [interrupt getInterruptFunctionsTV:member refCon:refCon handler:handler
			enabler:enabler disabler:disabler];
    return( err);
}


SInt32	StdIntHandler( InterruptSetMember setMember, void *refCon, UInt32 theIntCount)
{
    return( kIsrIsComplete);
}
void    StdIntEnabler( InterruptSetMember setMember, void *refCon)
{
    return;
}
Boolean StdIntDisabler( InterruptSetMember setMember, void *refCon)
{
    return( false);
}


- (IOReturn) setInterruptFunctionsTV:(UInt32)member
			refCon:(void *)refCon,
			handler:(TVector *) handler,
			enabler:(TVector *) enabler,
			disabler:(TVector *) disabler
{

   if( handler != NULL)
	currentIntHandler = handler;
   if( enabler != NULL)
	currentIntEnabler = enabler;
   if( disabler != NULL)
	currentIntDisabler = disabler;

    err = [interrupt setInterruptFunctions:member refCon:refCon handler:currentIntHandler
			enabler:enabler disabler:disabler];

}

- (IOReturn) setInterruptFunctions:(UInt32)member
			refCon:(void *)refCon,
			handler:(InterruptHandler) handler,
			enabler:(InterruptEnabler) enabler,
			disabler:(InterruptDisabler) disabler



- (IOReturn) getInterruptFunctions:(UInt32)member
			refCon:(void **)refCon,
			handler:(InterruptHandler *) handler,
			enabler:(InterruptEnabler *) enabler,
			disabler:(InterruptDisabler *) disabler

#endif

//////////////////////////////////////////////////////////////////////////////////////////

- (IOReturn) getAppleSense:(IOFBIndex)connectIndex info:(IOFBAppleSenseInfo *)info;
{
    OSStatus			err;
    VDDisplayConnectInfoRec	displayConnect;

    err = [self doStatus:cscGetConnection params:&displayConnect];
    if( err)
	return( err);

    if( displayConnect.csConnectFlags & ((1<<kReportsTagging) | (1<<kTaggingInfoNonStandard))
	!= ((1<<kReportsTagging)) )

	err = IO_R_UNSUPPORTED;

    else {
//	info->standardDisplayType 	= displayConnect.csDisplayType;
	info->primarySense 	= displayConnect.csConnectTaggedType;
	info->extendedSense = displayConnect.csConnectTaggedData;
	if( (info->primarySense == 0) && (info->extendedSense == 6)) {
	    info->primarySense          = kRSCSix;
	    info->extendedSense         = kESCSixStandard;
	}
	if( (info->primarySense == 0) && (info->extendedSense == 4)) {
	    info->primarySense          = kRSCFour;
	    info->extendedSense         = kESCFourNTSC;
	}
    }
    return( err);
}

- (BOOL) hasDDCConnect:(IOFBIndex)connectIndex
{
    OSStatus			err;
    VDDisplayConnectInfoRec	displayConnect;
    enum		{	kNeedFlags = (1<<kReportsDDCConnection) | (1<<kHasDDCConnection) };

    err = [self doStatus:cscGetConnection params:&displayConnect];
    if( err)
        return( NO);

    return( (displayConnect.csConnectFlags & kNeedFlags) == kNeedFlags );
}

- (IOReturn) getDDCBlock:(IOFBIndex)connectIndex blockNumber:(UInt32)num blockType:(OSType)type
	options:(UInt32)options data:(UInt8 *)data length:(ByteCount *)length
{
    OSStatus		err = 0;
    VDDDCBlockRec	ddcRec;
    ByteCount		actualLength = *length;

    ddcRec.ddcBlockNumber 	= num;
    ddcRec.ddcBlockType 	= type;
    ddcRec.ddcFlags 		= options;

    err = [self doStatus:cscGetDDCBlock params:&ddcRec];

    if( err == noErr) {

	actualLength = (actualLength < kDDCBlockSize) ? actualLength : kDDCBlockSize;
        bcopy( ddcRec.ddcBlockData, data, actualLength);
	*length = actualLength;
    }
    return( err);
}

//////////////////////////////////////////////////////////////////////////////////////////

- (IOReturn)getIntValues:(unsigned *)parameterArray
		forParameter:(IOParameterName)parameterName
    		count:(unsigned int *)count
{

    if (strcmp(parameterName, "IOGetTransferTable") == 0) {
	return( [self getTransferTable:&parameterArray[0] count:count] );

    } else
	return [super getIntValues:parameterArray
	    forParameter:parameterName
	    count:count];
}



//////////////////////////////////////////////////////////////////////////////////////////
// IOCallDeviceMethods:

// Should be in NDRV class?
- (IOReturn) IONDRVGetDriverName:(char *)outputParams size:(unsigned *) outputCount
{
    char * 	name;
    UInt32	len, plen;

    name = theDriverDesc->driverOSRuntimeInfo.driverName;

    plen = *(name++);
    len = *outputCount - 1;
    *outputCount = plen + 1;
    if( plen < len)
	len = plen;
    strncpy( outputParams, name, len);
    outputParams[ len ] = 0;

    return( noErr);
}

- (IOReturn) IONDRVDoControl:(UInt32 *)inputParams inputSize:(unsigned) inputCount
		params:(void *)outputParams outputSize:(unsigned *) outputCount
		privileged:(host_priv_t *)privileged
{
    IOReturn	err = noErr;
    UInt32	callSelect;

    if( privileged == NULL)
	err = IO_R_PRIVILEGE;
    else {
	callSelect = *inputParams;
	err = [self doControl:callSelect params:(inputParams + 1 )];
	bcopy( inputParams, outputParams, *outputCount);
    }
    return( err);
}

//////////////////////////////////////////////////////////////////////////////////////////

- (IOReturn) IONDRVDoStatus:(UInt32 *)inputParams inputSize:(unsigned) inputCount
		params:(void *)outputParams outputSize:(unsigned *) outputCount
{
    IOReturn	err = noErr;
    UInt32	callSelect;

    callSelect = *inputParams;
    err = [self doStatus:callSelect params:(inputParams + 1 )];
    bcopy( inputParams, outputParams, *outputCount);
    return( err);

}

@end

//////////////////////////////////////////////////////////////////////////////////////////
// DACrap

@implementation IONDRVFramebuffer (ProgramDAC)

- setTheTable
{
    IOReturn	err;
    ColorSpec * table = transferTable;
    VDSetEntryRecord	setEntryRec;
    int		i, code;

    if( transferTableCount != 0) {
	if( brightnessLevel != EV_SCREEN_MAX_BRIGHTNESS) {
	    if( !scaledTable)
		scaledTable = IOMalloc( 256 * sizeof( ColorSpec));
	    if( scaledTable) {
		for( i = 0; i < transferTableCount; i++ ) {
		    scaledTable[ i ].rgb.red	= EV_SCALE_BRIGHTNESS( brightnessLevel, table[ i ].rgb.red);
		    scaledTable[ i ].rgb.green	= EV_SCALE_BRIGHTNESS( brightnessLevel, table[ i ].rgb.green);
		    scaledTable[ i ].rgb.blue	= EV_SCALE_BRIGHTNESS( brightnessLevel, table[ i ].rgb.blue);
		}
		table = scaledTable;
	    }
	} else {
	    if( scaledTable) {
		IOFree( scaledTable, transferTableCount * sizeof( ColorSpec));
		scaledTable = 0;
	    }
	}

	setEntryRec.csTable = table;
	setEntryRec.csStart = 0;
	setEntryRec.csCount = transferTableCount - 1;
	if( [self displayInfo]->bitsPerPixel == IO_8BitsPerPixel)
	    code = cscSetEntries;
	else
	    code = cscDirectSetEntries;
	err = [self doControl:code params:&setEntryRec];
    }
    return self;
}

- setBrightness:(int)level token:(int)t
{
    if ((level < EV_SCREEN_MIN_BRIGHTNESS) ||
        (level > EV_SCREEN_MAX_BRIGHTNESS)){
            IOLog("Display: Invalid arg to setBrightness: %d\n",
                level);
            return nil;
    }
    brightnessLevel = level;
    [self setTheTable];
    return self;
}

#define Expand8To16(x)  (((x) << 8) | (x))


- setTransferTable:(const unsigned int *)table count:(int)count
{

// no checking table count vs. depth ??

    int         k;
    IOBitsPerPixel  bpp;
    IOColorSpace    cspace;
    VDGammaRecord		gammaRec;

    bpp = [self displayInfo]->bitsPerPixel;
    cspace = [self displayInfo]->colorSpace;

    if( table) {
        transferTableCount = count;
        if (bpp == IO_8BitsPerPixel && cspace == IO_OneIsWhiteColorSpace) {
            for (k = 0; k < count; k++) {
                transferTable[k].rgb.red = transferTable[k].rgb.green = transferTable[k].rgb.blue
                    = Expand8To16(table[k] & 0xFF);
            }
        } else if (cspace == IO_RGBColorSpace &&
            ((bpp == IO_8BitsPerPixel) ||
            (bpp == IO_15BitsPerPixel) ||
            (bpp == IO_24BitsPerPixel))) {
            for (k = 0; k < count; k++) {
                transferTable[k].rgb.red    = Expand8To16((table[k] >> 24) & 0xFF);
                transferTable[k].rgb.green  = Expand8To16((table[k] >> 16) & 0xFF);
                transferTable[k].rgb.blue   = Expand8To16((table[k] >>  8) & 0xFF);
            }
        } else {
            transferTableCount = 0;
        }
    }

    if( NO == gammaKilled) {
	gammaRec.csGTable = 0;
	[self doControl:cscSetGamma params:&gammaRec];
	gammaKilled = YES;
    }

    [self setTheTable];
    return self;
}

- (IOReturn)getTransferTable:(unsigned int *)table count:(int *)count
{
    int	k;

    if( *count != transferTableCount)
	return( IO_R_INVALID_ARG);

    for (k = 0; k < transferTableCount; k++) {
	table[k] = ((transferTable[k].rgb.red << 16) & 0xff000000)
		|  ((transferTable[k].rgb.green << 8) & 0xff0000)
		|  ((transferTable[k].rgb.blue) & 0xff00)
		|  ((transferTable[k].rgb.blue >> 8) & 0xff);
    }
    return( IO_R_SUCCESS);
}

// Apple style CLUT - pass thru gamma table

- (IOReturn)
    setCLUT:(IOFBColorEntry *) colors index:(UInt32)index numEntries:(UInt32)numEntries
    	brightness:(IOFixed)brightness options:(IOOptionBits)options
{
    IOReturn		err;
    VDSetEntryRecord	setEntryRec;
    int			code;

    setEntryRec.csTable = (ColorSpec *)colors;
    setEntryRec.csStart = index;
    setEntryRec.csCount = numEntries - 1;
    if( [self displayInfo]->bitsPerPixel == IO_8BitsPerPixel)
	code = cscSetEntries;
    else
	code = cscDirectSetEntries;
    err = [self doControl:code params:&setEntryRec];

    return( err);

}

#if 0
- (void) interruptOccurred
{
    kprintf("\n[%s]\n", [self name]);
    [self enableAllInterrupts];
}
#endif

@end

//////////////////////////////////////////////////////////////////////////////////////////

// OpenFirmware shim

enum { kTheDisplayMode	= 10 };

@implementation IOOFFramebuffer

//=======================================================================

- initFromDeviceDescription:(IOPCIDevice *) ioDevice
{
    id			me = nil;
    kern_return_t	err = 0;
    UInt32		i;
    UInt32		numMaps = 8;
    IOApertureInfo	maps[ numMaps ];	// FIX
    IOApertureInfo   *	map;

    do {
	numMaps = 8;
	err = [ioDevice getApertures:maps items:&numMaps];
	if( err)
	    continue;

	err = -1;
	for( i = 0, map = maps; i < numMaps; i++, map++) {

	    if( (((UInt32)bootDisplayInfo.frameBuffer) >= ((UInt32)map->physical))
	    &&  (((UInt32)bootDisplayInfo.frameBuffer) < (map->length + (UInt32)map->physical)) ) {

		// Declare range for pmap'ing into user space
		// Shouldn't be here but it's too expensive to do it for all devices
		err = pmap_add_physical_memory( map->physical,
						map->physical + map->length, FALSE, PTE_WIMG_IO);
		if(err)
		    kprintf("%s: pmap_add_physical_memory:%d for 0x%08x - 0x%08x\n",
			    [self name], err, map->physical, map->physical + map->length);
	    }
	}
	if( err)
	    continue;

	if (nil == [super initFromDeviceDescription:ioDevice])
	    continue;
	err = [self open];
	if( err)
	    continue;

	me = self;			// Success

    } while( false);

    if( me == nil)
	[super free];

    return( me);
}

- (IOReturn)
    getDisplayModeByIndex:(IOFBIndex)modeIndex displayMode:(IOFBDisplayModeID *)displayModeID
{
    if( modeIndex)
	return( IO_R_UNDEFINED_MODE);
    *displayModeID = kTheDisplayMode;
    return( noErr);
}

- (IOReturn)
    getDisplayModeInformation:(IOFBDisplayModeID)modeID info:(IOFBDisplayModeInformation *)info
{
    if( modeID == kTheDisplayMode) {
	info->displayModeID	= modeID;
	info->maxDepthIndex	= 0;
	info->nominalWidth	= bootDisplayInfo.width;
	info->nominalHeight	= bootDisplayInfo.height;
	info->refreshRate	= bootDisplayInfo.refreshRate << 16;
	return( noErr);
    }
    return( IO_R_UNDEFINED_MODE);
}


- (IOReturn)
    getPixelInformationForDisplayMode:(IOFBDisplayModeID)modeID andDepthIndex:(IOFBIndex)depthIndex
    	pixelInfo:(IOFBPixelInformation *)info
{

    if( (modeID == kTheDisplayMode) && (depthIndex == 0)) {

	info->flags 			= 0;
	info->rowBytes             	= bootDisplayInfo.rowBytes;
	info->width                	= bootDisplayInfo.width;
	info->height               	= bootDisplayInfo.height;
	info->refreshRate          	= bootDisplayInfo.refreshRate << 16;
	info->pageCount 		= 1;
	info->pixelType 		= kIOFBRGBCLUTPixelType;
	info->bitsPerPixel 		= 8;
//	info->channelMasks 		=
	return( noErr);
    }
    return( IO_R_UNDEFINED_MODE);
}

- (IOReturn)
    setDisplayMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex page:(IOFBIndex)pageIndex
{
    if( (modeID == kTheDisplayMode) && (depthIndex == 0) && (pageIndex == 0) )
	return( noErr);
    else
	return( IO_R_UNDEFINED_MODE);
}


- (IOReturn)
    getStartupMode:(IOFBDisplayModeID *)modeID depth:(IOFBIndex *)depthIndex
{
    *modeID		= kTheDisplayMode;
    *depthIndex		= 0;

    return( noErr);
}


- (IOReturn)
    getConfiguration:(IOFBConfiguration *)config
{
    bzero( config, sizeof( IOFBConfiguration));

    config->displayMode		= kTheDisplayMode;
    config->depth		= 0;
    config->page		= 0;
    config->physicalFramebuffer	= (IOPhysicalAddress) bootDisplayInfo.frameBuffer;
    config->mappedFramebuffer	= (IOVirtualAddress) bootDisplayInfo.frameBuffer;		// assuming 1-1

    return( noErr);
}

- (IOReturn)
    getDisplayModeTiming:(IOFBIndex)connectIndex mode:(IOFBDisplayModeID)modeID
                timingInfo:(IOFBTimingInformation *)info connectFlags:(UInt32 *)flags
{

    info->standardTimingID = timingInvalid;
    if( modeID == kTheDisplayMode) {
        *flags = kDisplayModeValidFlag | kDisplayModeSafeFlag | kDisplayModeDefaultFlag;
        return( noErr);
    } else {
        *flags = 0;
        return( IO_R_UNDEFINED_MODE);
    }
}


- setBrightness:(int)level token:(int)t
{
    return self;
}

- setTransferTable:(const unsigned int *)table count:(int)count
{
    return self;
}

- (IOReturn)getIntValues:(unsigned *)parameterArray
		forParameter:(IOParameterName)parameterName
    		count:(unsigned int *)count
{
    const UInt8 *	clut;
    int			i;
    extern const UInt8  appleClut8[ 256 * 3 ];

    if( (0 == strcmp(parameterName, "IOGetTransferTable"))
	&& (*count == 256)) {
	for( clut = appleClut8, i = 0; i < 256; i++, clut += 3)
	    *(parameterArray++) = (clut[0] << 24) | (clut[1] << 16) | (clut[3] << 8) | 0xff;
	return( noErr);

    } else
	return [super getIntValues:parameterArray
	    forParameter:parameterName
	    count:count];
}

@end

//////////////////////////////////////////////////////////////////////////////////////////

// ATI patches. Acceleration to be removed when user level blitting is in.
// Real problem : getStartupMode doesn't.

@implementation IOATINDRV

- (IOReturn)
    getStartupMode:(IOFBDisplayModeID *)modeID depth:(IOFBIndex *)depthIndex
{

    IOReturn		err;
    UInt16	*	nvram;
    ByteCount		propSize = 8;

    err = [[ioDevice propertyTable] getProperty:"Sime" flags:kReferenceProperty
		value:(void *)&nvram length:&propSize];
    if( err == noErr) {
	*modeID = nvram[ 0 ];	// 1 is physDisplayMode
	*depthIndex = nvram[ 2 ] - kDepthMode1;
    }
    return( err);
}

@end

// Register access functions
// We need to perform byte swapping on all register accesses for IMS and the ATI Mach64/Rage.

static inline UInt32 regr(volatile UInt32 *base, UInt32 offset)
{
    UInt32 value;

    offset = offset & 0xffff;
    eieio();  // Enforce I/O ordering before read

    value = *(volatile UInt32 *)((UInt8 *)base + offset);

    // Byte swap from little-endian to big-endian
    value = (value >> 24) |
            ((value >> 8) & 0xff00) |
            ((value & 0xff00) << 8) |
            (value << 24);

    return value;
}

static inline void regw(volatile UInt32 *base, UInt32 offset, UInt32 value)
{
    // Byte swap from big-endian to little-endian
    value = (value >> 24) |
            ((value >> 8) & 0xff00) |
            ((value & 0xff00) << 8) |
            (value << 24);

    *(volatile UInt32 *)((UInt8 *)base + offset) = value;
    eieio();  // Enforce I/O ordering after write
}

static inline void regwMask(volatile UInt32 *base, UInt32 offset, UInt32 value, UInt32 mask)
{
    UInt32 temp;

    temp = regr(base, offset);
    temp = (temp & mask) | value;
    regw(base, offset, temp);
}

// No-swap register access functions (for hardware that matches PowerPC endianness)
static inline UInt32 regrNoswap(volatile UInt32 *base, UInt32 offset)
{
    UInt32 value;

    offset = offset & 0xffff;
    eieio();  // Enforce I/O ordering before read

    value = *(volatile UInt32 *)((UInt8 *)base + offset);

    return value;  // No byte swapping
}

static inline void regwNoswap(volatile UInt32 *base, UInt32 offset, UInt32 value)
{
    *(volatile UInt32 *)((UInt8 *)base + offset) = value;  // No byte swapping
    eieio();  // Enforce I/O ordering after write
}

//////////////////////////////////////////////////////////////////////////////////////////
// ATI Mach64 Engine Control Functions

/*
 * _m64WaitForIdle - Wait for the Mach64 graphics engine to become idle
 *
 * @param base: Register base address
 *
 * Polls the engine status register (0x338) until bit 0 (engine busy) is clear.
 */
static void _m64WaitForIdle(volatile UInt32 *base)
{
    UInt32 status;

    do {
        status = regr(base, 0x338);  // GUI_STAT register
    } while ((status & 1) != 0);      // Wait for engine idle (bit 0 = 0)
}

/*
 * _m64WaitForFIFO - Wait for FIFO space to become available
 *
 * @param base: Register base address
 * @param entries: Number of FIFO entries needed
 *
 * Polls the FIFO status register (0x310) until the requested number
 * of entries are available in the command FIFO.
 */
static void _m64WaitForFIFO(volatile UInt32 *base, UInt32 entries)
{
    UInt32 status;
    UInt32 mask;

    mask = (0x8000 >> (entries & 0x3f)) & 0xffff;

    do {
        status = regr(base, 0x310);   // GUI_STAT register (FIFO status)
    } while ((status & 0xffff) < mask);
}

/*
 * _m64Init - Initialize the ATI Mach64 2D graphics engine
 *
 * @param base: Register base address
 *
 * Performs complete initialization of the Mach64 graphics engine:
 * - Resets engine state
 * - Clears FIFO
 * - Sets up default drawing parameters
 * - Configures pixel depth from current mode
 * - Sets clipping and mask registers
 * - Enables the drawing engine
 */
static void _m64Init(volatile UInt32 *base)
{
    UInt32 pixelDepth;
    UInt32 pitch;

    // Reset GUI engine
    regwMask(base, 0xd0, 0, 0xfffffeff);          // GEN_TEST_CNTL - clear bit 8
    regwMask(base, 0xd0, 0x100, 0xfffffeff);      // GEN_TEST_CNTL - set bit 8

    // Clear engine status and FIFO
    regw(base, 0x338, 0);                          // GUI_STAT = 0
    regw(base, 0x310, 0);                          // GUI_STAT = 0 (alt offset)

    // Configure bus mastering
    regwMask(base, 0xa0, 0xa00000, 0xff5fffff);   // BUS_CNTL

    // Reset again
    regwMask(base, 0xd0, 0, 0xfffffeff);          // GEN_TEST_CNTL
    regwMask(base, 0xd0, 0x100, 0xfffffeff);      // GEN_TEST_CNTL

    // Wait for engine to be idle before programming
    _m64WaitForIdle(base);
    _m64WaitForFIFO(base, 14);

    // Get pixel depth from CRTC configuration
    pixelDepth = regr(base, 0x1c);                 // CRTC_GEN_CNTL
    pixelDepth = (pixelDepth >> 8) & 7;            // Extract pixel depth field

    // Set DP_PIX_WIDTH (destination/source/host pixel width)
    regw(base, 0x2d0, (pixelDepth << 16) | (pixelDepth << 8) | pixelDepth);

    // Set drawing parameters
    regw(base, 0x2c8, 0xffffffff);                 // DP_WRITE_MASK - all bits enabled
    regw(base, 0x2a0, 0);                          // DP_FRGD_CLR - foreground color
    regw(base, 0x2ac, 0);                          // DP_MIX - source copy
    regw(base, 0x2b0, 0x3fff);                     // DP_SRC - source select
    regw(base, 0x2a4, 0xfff);                      // DP_BKGD_CLR - background color
    regw(base, 0x308, 0);                          // DST_CNTL - destination control

    _m64WaitForFIFO(base, 14);

    // Set pitch registers from current configuration
    pitch = regr(base, 0x14);                      // CRTC_OFF_PITCH
    regw(base, 0x100, pitch);                      // DST_OFF_PITCH
    regw(base, 0x180, pitch);                      // SRC_OFF_PITCH

    // Set clipping and control registers
    regw(base, 0x300, 0);                          // SC_LEFT_RIGHT - scissor left/right
    regw(base, 0x304, 0xffffffff);                 // SC_TOP_BOTTOM - scissor top/bottom
    regw(base, 0x308, 0);                          // DST_CNTL
    regw(base, 0x1b4, 0);                          // CLR_CMP_CNTL - color compare off

    // Set GUI control - enable drawing engine
    regw(base, 0x130, 0x23);                       // GUI_TRAJ_CNTL

    // Final wait for idle
    _m64WaitForIdle(base);
}

/*
 * _m64DoFill - Hardware-accelerated rectangle fill
 *
 * @param base: Register base address
 * @param x: X coordinate of rectangle
 * @param y: Y coordinate of rectangle
 * @param width: Width of rectangle
 * @param height: Height of rectangle
 * @param color: Fill color (32-bit ARGB)
 *
 * Fills a solid rectangle using the Mach64 2D engine.
 */
static void _m64DoFill(volatile UInt32 *base, UInt32 x, UInt32 y,
                       UInt32 width, UInt32 height, UInt32 color)
{
    _m64WaitForFIFO(base, 6);

    regw(base, 0x2d8, 0x100);           // DP_BKGD_MIX - background mix
    regw(base, 0x2d4, 0x70003);         // DP_FRGD_MIX - foreground mix (source copy)
    regw(base, 0x130, 3);               // GUI_TRAJ_CNTL - direction (left-to-right, top-to-bottom)
    regw(base, 0x2c4, color);           // DP_FRGD_CLR - fill color
    regw(base, 0x10c, (y << 16) | x);   // DST_Y_X - destination position
    regw(base, 0x118, (height << 16) | width);  // DST_HEIGHT_WIDTH - rectangle size
}

/*
 * _m64DoBlit - Hardware-accelerated screen-to-screen blit
 *
 * @param base: Register base address
 * @param src_x: Source X coordinate
 * @param src_y: Source Y coordinate
 * @param width: Width of rectangle to copy
 * @param height: Height of rectangle to copy
 * @param dst_x: Destination X coordinate
 * @param dst_y: Destination Y coordinate
 *
 * Copies a rectangle from one screen location to another using the Mach64 2D engine.
 * Automatically handles overlapping regions by adjusting blit direction.
 */
static void _m64DoBlit(volatile UInt32 *base, UInt32 src_x, UInt32 src_y,
                       UInt32 width, UInt32 height, UInt32 dst_x, UInt32 dst_y)
{
    UInt32 dx, dy;
    UInt32 direction = 3;  // Default: left-to-right, top-to-bottom
    SInt32 signed_dx, signed_dy;

    // Calculate deltas
    dx = dst_x - src_x;
    dy = dst_y - src_y;

    // Get signed versions for comparison
    signed_dx = (SInt32)dx;
    signed_dy = (SInt32)dy;

    // Check for overlap and adjust direction if needed
    // abs(dx) < width && abs(dy) < height indicates overlap
    if ((((signed_dx >> 31) ^ dx) - (signed_dx >> 31) < width) &&
        (((signed_dy >> 31) ^ dy) - (signed_dy >> 31) < height)) {

        if (signed_dy < 0) {
            // Overlapping vertically, moving up - use bottom-to-top
            direction = 1;
            dst_y = (dst_y + height) - 1;
            src_y = (src_y + height) - 1;
        } else if ((signed_dy == 0) && (signed_dx > 0)) {
            // Same line, moving right - use right-to-left
            direction = 2;
            dst_x = (dst_x + width) - 1;
            src_x = (src_x + width) - 1;
        }
    }

    _m64WaitForFIFO(base, 7);

    regw(base, 0x2d8, 0x300);           // DP_BKGD_MIX
    regw(base, 0x2d4, 0x70003);         // DP_FRGD_MIX - source copy
    regw(base, 0x190, width);           // SRC_WIDTH1 - source width
    regw(base, 0x130, direction);       // GUI_TRAJ_CNTL - blit direction
    regw(base, 0x18c, (src_y << 16) | src_x);   // SRC_Y_X - source position
    regw(base, 0x10c, (dst_y << 16) | dst_x);   // DST_Y_X - destination position
    regw(base, 0x118, (height << 16) | width);  // DST_HEIGHT_WIDTH - rectangle size
}

// ATI Mach64 NDRV - for ATI Mach64-based cards (Rage, Rage II, etc.)
// Provides hardware acceleration support for blits and fills

@implementation IOATIMACH64NDRV
{
    BOOL	engineInitialized;
}

//=======================================================================
// Hardware cursor support

- hideCursor:(int)token
{
    // Wait for any pending operations to complete before hiding cursor
    if (registerBase != NULL)
        _m64WaitForIdle(registerBase);

    // Call parent implementation for software cursor
    return [super hideCursor:token];
}

- moveCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    // Wait for any pending operations before moving cursor
    if (registerBase != NULL)
        _m64WaitForIdle(registerBase);

    // Call parent implementation for software cursor
    return [super moveCursor:cursorLoc frame:frame token:t];
}

- showCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    // Wait for any pending operations before showing cursor
    if (registerBase != NULL)
        _m64WaitForIdle(registerBase);

    // Call parent implementation for software cursor
    return [super showCursor:cursorLoc frame:frame token:t];
}

//=======================================================================
// Engine initialization

- initEngine
{
    IOFBConfiguration config;
    IOReturn err;

    // Get current configuration to find framebuffer address
    err = [self getConfiguration:&config];
    if (err != IO_R_SUCCESS) {
        IOLog("%s: Could not get configuration (err=%d)\n", [self name], err);
        engineInitialized = NO;
        registerBase = NULL;
        return self;
    }

    // Calculate MMIO register base from framebuffer address
    // For ATI Mach64, registers are located 1KB (0x400) before framebuffer
    // Page-align the framebuffer address and subtract 0x400
    registerBase = (volatile UInt32 *)((config.mappedFramebuffer & 0xffff0000) - 0x400);

    if (registerBase == NULL) {
        IOLog("%s: Register base calculation failed\n", [self name]);
        engineInitialized = NO;
        return self;
    }

    IOLog("%s: Mach64 registers at 0x%08x (framebuffer at 0x%08x)\n",
          [self name], (UInt32)registerBase, (UInt32)config.mappedFramebuffer);

    // Initialize the hardware
    _m64Init(registerBase);

    engineInitialized = YES;

    return self;
}

//=======================================================================
// Device open/configuration

- (IOReturn)open
{
    IOReturn err;

    // Call parent open
    err = [super open];
    if (err != IO_R_SUCCESS)
        return err;

    // Initialize the acceleration engine
    // This will calculate registerBase and initialize the hardware
    [self initEngine];

    return IO_R_SUCCESS;
}

- (IOReturn)setDisplayMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex page:(IOFBIndex)pageIndex
{
    IOReturn result;

    // Call parent setDisplayMode
    result = [super setDisplayMode:modeID depth:depthIndex page:pageIndex];
    if (result == 0) {
        [self initEngine];
    }
    return result;
}

//=======================================================================
// Acceleration capabilities

- (UInt32)tempFlags
{
    // Advertise hardware acceleration capabilities
    // IO_DISPLAY_CAN_BLIT = 0x20 (hardware blit support)
    // IO_DISPLAY_CAN_FILL = 0x40 (hardware fill support)
    return IO_DISPLAY_CAN_BLIT | IO_DISPLAY_CAN_FILL;
}

//=======================================================================
// Hardware acceleration operations

- (IOReturn)setIntValues:(unsigned *)parameterArray
		forParameter:(IOParameterName)parameterName
    		count:(unsigned int *)count
{
    // Handle hardware-accelerated blit operations
    if (strcmp(parameterName, IO_DISPLAY_DO_BLIT) == 0) {
        if (*count != IO_DISPLAY_BLIT_SIZE)
            return IO_R_INVALID_ARG;

        if (!engineInitialized || registerBase == NULL)
            return IO_R_RESOURCE;

        // Parameters: [0]=src_x, [1]=src_y, [2]=width, [3]=height, [4]=dst_x, [5]=dst_y
        _m64DoBlit(registerBase,
                   parameterArray[0],  // src_x
                   parameterArray[1],  // src_y
                   parameterArray[2],  // width
                   parameterArray[3],  // height
                   parameterArray[4],  // dst_x
                   parameterArray[5]); // dst_y

        return 0;  // Success (IO_R_SUCCESS = 0)
    }

    // Handle hardware-accelerated fill operations
    else if (strcmp(parameterName, IO_DISPLAY_DO_FILL) == 0) {
        if (*count != IO_DISPLAY_FILL_SIZE)
            return IO_R_INVALID_ARG;

        if (!engineInitialized || registerBase == NULL)
            return IO_R_RESOURCE;

        // Parameters: [0]=x, [1]=y, [2]=width, [3]=height, [4]=color
        _m64DoFill(registerBase,
                   parameterArray[0],  // x
                   parameterArray[1],  // y
                   parameterArray[2],  // width
                   parameterArray[3],  // height
                   parameterArray[4]); // color

        return 0;  // Success (IO_R_SUCCESS = 0)
    }

    // Handle display sync (wait for idle) operations
    else if (strcmp(parameterName, IO_DISPLAY_GET_SYNCED) == 0) {
        if (*count != IO_DISPLAY_GET_SYNCED_SIZE)
            return IO_R_INVALID_ARG;

        if (registerBase != NULL)
            _m64WaitForIdle(registerBase);

        return 0;  // Success (IO_R_SUCCESS = 0)
    }

    // Pass other parameters to parent
    return [super setIntValues:parameterArray forParameter:parameterName count:count];
}

@end


//////////////////////////////////////////////////////////////////////////////////////////
// ATI Rage 128 NDRV - for ATI Rage 128 cards

@implementation IOATIRAGE128NDRV

- moveCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    int i;

    [super moveCursor:cursorLoc frame:frame token:t];

    // Hardware delay loop (8 iterations)
    i = 0;
    do {
        i = i + 1;
    } while (i < 8);

    return self;
}

@end


//////////////////////////////////////////////////////////////////////////////////////////
// IMS TwinTurbo (tt128) NDRV - for IMS TwinTurbo 128 graphics cards
// Used in PowerMac 7200-9600 and some early G3 systems

//=======================================================================
// IMS TwinTurbo utility functions

static void _ixIdleEngine(volatile UInt32 *base)
{
    UInt32 status;

    do {
        status = regr(base, 0x90);  // Engine status register
    } while ((status & 0xc0) != 0);  // Wait for bits 6-7 to be clear
}

static void _ixDoFill(volatile UInt32 *base, UInt32 bytesPerPixel, UInt32 pixelFormat,
                     UInt32 x, UInt32 y, UInt32 width, UInt32 height, UInt32 color)
{
    UInt32 stride;
    UInt32 swappedColor;

    stride = pixelFormat & 0xffff;

    // Byte swap color based on pixel depth
    swappedColor = color;
    if (bytesPerPixel == 2) {
        // 16-bit: swap bytes and replicate
        swappedColor = ((color & 0xff) << 8) | ((color >> 8) & 0xff);
        swappedColor = swappedColor | (swappedColor << 16);
    } else if (bytesPerPixel == 1) {
        // 8-bit: replicate to all 4 bytes
        swappedColor = color & 0xff;
        swappedColor = swappedColor | (swappedColor << 8) | (swappedColor << 16) | (swappedColor << 24);
    } else if (bytesPerPixel == 4) {
        // 32-bit: full byte swap
        swappedColor = (color >> 24) | ((color >> 8) & 0xff00) |
                      ((color & 0xff00) << 8) | (color << 24);
    }

    // Wait for engine idle
    _ixIdleEngine(base);

    // Program fill operation
    regw(base, 0x18, swappedColor);  // Foreground color
    regw(base, 0x1c, swappedColor);  // Background color
    regw(base, 0x10, ((height - 1) << 16) | ((width * bytesPerPixel - 1) & 0xffff));  // Dimensions
    regw(base, 0x0c, y * stride + x * bytesPerPixel + 0x20);  // Destination offset
    regw(base, 0x08, stride);  // Destination stride
    regw(base, 0x14, stride);  // Source stride (same)
    regw(base, 0x28, 0x200000);  // Fill command
}

static void _ixDoBlit(volatile UInt32 *base, UInt32 bytesPerPixel, UInt32 pixelFormat,
                     UInt32 srcX, UInt32 srcY, UInt32 dstX, UInt32 dstY,
                     UInt32 width, UInt32 height)
{
    UInt32 stride;
    UInt32 widthBytes;
    UInt32 srcOffset, dstOffset;
    UInt32 command;
    BOOL reverseX, reverseY;

    stride = pixelFormat & 0xffff;

    // Detect overlap - need to reverse direction?
    reverseX = (srcX < dstX);
    reverseY = (srcY < dstY);

    widthBytes = width * bytesPerPixel - 1;
    if (reverseX) {
        widthBytes = -widthBytes;
    }

    // Adjust coordinates for reverse directions
    if (reverseX) {
        srcX = (srcX - 1) + width;
        dstX = (dstX - 1) + width;
    }

    if (reverseY) {
        srcY = (srcY - 1) + height;
        dstY = (dstY - 1) + height;
    }

    // Calculate offsets
    srcOffset = srcY * stride + srcX * bytesPerPixel + 0x20;
    dstOffset = dstY * stride + dstX * bytesPerPixel + 0x20;

    // Adjust for reverse X
    if (reverseX) {
        srcOffset = srcOffset - 1 + bytesPerPixel;
        dstOffset = dstOffset - 1 + bytesPerPixel;
    }

    // Adjust stride for reverse Y
    if (reverseY) {
        stride = -stride;
    }

    // Wait for engine idle
    _ixIdleEngine(base);

    // Program blit operation
    regw(base, 0x10, ((height - 1) << 16) | (widthBytes & 0xffff));  // Dimensions
    regw(base, 0x00, srcOffset);  // Source offset
    regw(base, 0x0c, dstOffset);  // Destination offset
    regw(base, 0x08, stride & 0xffff);  // Source stride
    regw(base, 0x14, stride & 0xffff);  // Destination stride

    // Command: 0x85 for reverse X, 0x5 for forward
    command = reverseX ? 0x85 : 0x5;
    regw(base, 0x28, command);
}

//=======================================================================

@implementation IOIXMNDRV

- initEngine
{
    IOFBConfiguration config;
    IOFBPixelInformation pixelInfo;
    IOReturn err;
    IOFBDisplayModeID modeID;
    IOFBIndex depthIndex, pageIndex;

    // Get current configuration
    err = [self getConfiguration:&config];
    if (err != IO_R_SUCCESS) {
        IOLog("%s: Could not get configuration (err=%d)\n", [self name], err);
        registerBase = NULL;
        return self;
    }

    // Get current display mode and depth
    modeID = config.mode;
    depthIndex = config.depth;
    pageIndex = config.page;

    // Get pixel information
    err = [self getPixelInformationForDisplayMode:modeID depth:depthIndex page:pageIndex
                                     pixelInformation:&pixelInfo];
    if (err != IO_R_SUCCESS) {
        IOLog("%s: Could not get pixel information (err=%d)\n", [self name], err);
        registerBase = NULL;
        return self;
    }

    // Calculate MMIO register base from framebuffer address
    // IMS registers are 8MB (0x800000) after framebuffer base
    registerBase = (volatile UInt32 *)((config.mappedFramebuffer & 0xffff0000) + 0x800000);

    // Calculate bytes per pixel from depth (1 << depth)
    bytesPerPixel = 1 << (depthIndex & 0x3f);

    // Store pixel format
    pixelFormat = pixelInfo.pixelType;

    IOLog("%s: IMS TwinTurbo registers at 0x%08x (framebuffer at 0x%08x, bpp=%d)\n",
          [self name], (UInt32)registerBase, (UInt32)config.mappedFramebuffer, bytesPerPixel);

    return self;
}

- hideCursor:(int)token
{
    if (registerBase != NULL)
        _ixIdleEngine(registerBase);
    return [super hideCursor:token];
}

- moveCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    if (registerBase != NULL)
        _ixIdleEngine(registerBase);
    return [super moveCursor:cursorLoc frame:frame token:t];
}

- showCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    if (registerBase != NULL)
        _ixIdleEngine(registerBase);
    return [super showCursor:cursorLoc frame:frame token:t];
}

- open
{
    int result;

    result = [super open];
    if (result == 0) {
        [self initEngine];
    }
    return result;
}

- (IOReturn)setDisplayMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex page:(IOFBIndex)pageIndex
{
    IOReturn result;

    result = [super setDisplayMode:modeID depth:depthIndex page:pageIndex];
    if (result == 0) {
        [self initEngine];
    }
    return result;
}

- (UInt32)tempFlags
{
    // Advertise hardware acceleration capabilities
    // 0x60 = 0x20 (IO_DISPLAY_CAN_BLIT) | 0x40 (IO_DISPLAY_CAN_FILL)
    return 0x60;
}

- (IOReturn)setIntValues:(unsigned int *)values forParameter:(IOParameterName)parameter count:(unsigned int)count
{
    // Handle hardware-accelerated blit operations
    if (strcmp(parameter, IO_DISPLAY_DO_BLIT) == 0 && count == IO_DISPLAY_BLIT_SIZE) {
        _ixDoBlit(registerBase, bytesPerPixel, pixelFormat,
                 values[0], values[1], values[2], values[3], values[4], values[5]);
        return 0;
    }
    // Handle hardware-accelerated fill operations
    else if (strcmp(parameter, IO_DISPLAY_DO_FILL) == 0 && count == IO_DISPLAY_FILL_SIZE) {
        _ixDoFill(registerBase, bytesPerPixel, pixelFormat,
                 values[0], values[1], values[2], values[3], values[4]);
        return 0;
    }
    // Handle display sync (wait for idle) operations
    else if (strcmp(parameter, IO_DISPLAY_GET_SYNCED) == 0 && count == IO_DISPLAY_GET_SYNCED_SIZE) {
        _ixIdleEngine(registerBase);
        return 0;
    }
    // Pass other parameters to parent
    else {
        return [super setIntValues:values forParameter:parameter count:count];
    }
}

@end


//////////////////////////////////////////////////////////////////////////////////////////
// IMS TwinTurbo 3D (tt3d) NDRV - for IMS TwinTurbo 3D graphics cards

//=======================================================================
// IMS TwinTurbo 3D utility functions

static void _ix3dIdleEngine(volatile UInt32 *base)
{
    UInt32 status;

    do {
        status = regrNoswap(base, 0xec);  // Engine status register (no byte swap)
    } while ((status & 0xc0) != 0);  // Wait for bits 6-7 to be clear
}

static void _ix3dDoFill(volatile UInt32 *base, UInt32 bytesPerPixel, UInt32 pixelFormat,
                       UInt32 x, UInt32 y, UInt32 width, UInt32 height, UInt32 color)
{
    UInt32 stride;
    UInt32 destOffset;

    stride = pixelFormat & 0xffff;

    // Wait for engine idle
    _ix3dIdleEngine(base);

    // Program fill operation
    regwNoswap(base, 0x28, color);  // Foreground color
    regwNoswap(base, 0x24, (height << 16) | (width & 0xffff));  // Dimensions
    regwNoswap(base, 0x14, y * stride + x * bytesPerPixel + 0x20);  // Destination offset
    regwNoswap(base, 0x44, ((bytesPerPixel - 1) * 0x80000) | 0x381);  // Fill command
}

static void _ix3dDoBlit(volatile UInt32 *base, UInt32 bytesPerPixel, UInt32 pixelFormat,
                       UInt32 srcX, UInt32 srcY, UInt32 dstX, UInt32 dstY,
                       UInt32 width, UInt32 height)
{
    UInt32 stride;
    UInt32 srcOffset, dstOffset;
    UInt32 command;
    BOOL reverse;

    stride = pixelFormat & 0xffff;

    // Complex overlap detection algorithm
    if (srcY < dstY) {
        reverse = FALSE;
    } else if (dstY < srcY) {
        reverse = TRUE;
    } else {
        reverse = (dstX <= srcX);
    }
    reverse = !reverse;

    // Adjust coordinates for reverse direction
    if (reverse) {
        srcX = (srcX - 1) + width;
        srcY = (srcY - 1) + height;
        dstX = (dstX - 1) + width;
        dstY = (dstY - 1) + height;
    }

    // Calculate offsets
    srcOffset = srcY * stride + srcX * bytesPerPixel;
    dstOffset = dstY * stride + dstX * bytesPerPixel;

    srcOffset += 0x20;
    dstOffset += 0x20;

    // Adjust for reverse direction
    if (reverse) {
        srcOffset = srcOffset + 0x1f + bytesPerPixel;
        dstOffset = dstOffset + 0x1f + bytesPerPixel;
    }

    // Build command value
    command = ((bytesPerPixel - 1) * 0x80000) | 0x81;
    if (!reverse) {
        command = ((bytesPerPixel - 1) * 0x80000) | 0x1;
    }

    // Wait for engine idle
    _ix3dIdleEngine(base);

    // Program blit operation
    regwNoswap(base, 0x24, (height << 16) | (width & 0xffff));  // Dimensions
    regwNoswap(base, 0x18, srcOffset);  // Source offset
    regwNoswap(base, 0x14, dstOffset);  // Destination offset
    regwNoswap(base, 0x40, 0xaa);  // ROP (copy)
    regwNoswap(base, 0x44, command);  // Command
}

//=======================================================================
// IMS TwinTurbo 3D interrupt handler

static void _ix3dInterruptHandler(void *identity, void *state, void *arg)
{
    IOIX3DNDRV *self = (IOIX3DNDRV *)arg;

    // Clear interrupt status by writing 0x30 to register 0xec
    regwNoswap(self->registerBase, 0xec, 0x30);

    // Re-enable interrupt
    IOEnableInterrupt(identity);
}

//=======================================================================

@implementation IOIX3DNDRV

- (UInt32)tempFlags
{
    // Advertise hardware acceleration capabilities
    return IO_DISPLAY_CAN_BLIT | IO_DISPLAY_CAN_FILL;
}

- showCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    _ix3dIdleEngine(registerBase);
    return [super showCursor:cursorLoc frame:frame token:t];
}

- (IOReturn)setDisplayMode:(IOFBDisplayModeID)modeID depth:(IOFBIndex)depthIndex page:(IOFBIndex)pageIndex
{
    IOReturn result;

    [self disableInterrupt:0];

    result = [super setDisplayMode:modeID depth:depthIndex page:pageIndex];
    if (result == 0) {
        [self initEngine];
    }

    [self enableInterrupt:0];

    return result;
}

- initEngine
{
    IOFBConfiguration config;
    IOFBPixelInformation pixelInfo;
    IOReturn err;
    IOFBDisplayModeID modeID;
    IOFBIndex depthIndex, pageIndex;

    // Get current configuration
    err = [self getConfiguration:&config];
    if (err != IO_R_SUCCESS) {
        IOLog("%s: Could not get configuration (err=%d)\n", [self name], err);
        registerBase = NULL;
        return self;
    }

    // Get current display mode and depth
    modeID = config.mode;
    depthIndex = config.depth;
    pageIndex = config.page;

    // Get pixel information
    err = [self getPixelInformationForDisplayMode:modeID depth:depthIndex page:pageIndex
                                     pixelInformation:&pixelInfo];
    if (err != IO_R_SUCCESS) {
        IOLog("%s: Could not get pixel information (err=%d)\n", [self name], err);
        registerBase = NULL;
        return self;
    }

    // Calculate MMIO register base from framebuffer address
    // IMS TwinTurbo 3D registers are 96MB (0x6000000) after framebuffer base
    registerBase = (volatile UInt32 *)((config.mappedFramebuffer & 0xffff0000) + 0x6000000);

    // Calculate bytes per pixel from depth (1 << depth)
    bytesPerPixel = 1 << (depthIndex & 0x3f);

    // Store pixel format
    pixelFormat = pixelInfo.pixelType;

    IOLog("%s: IMS TwinTurbo 3D registers at 0x%08x (framebuffer at 0x%08x, bpp=%d)\n",
          [self name], (UInt32)registerBase, (UInt32)config.mappedFramebuffer, bytesPerPixel);

    // Initialize engine registers
    _ix3dIdleEngine(registerBase);
    regwNoswap(registerBase, 0x04, (pixelFormat << 16) | pixelFormat);
    regwNoswap(registerBase, 0x20, (pixelFormat << 16) | pixelFormat);

    return self;
}

- hideCursor:(int)token
{
    _ix3dIdleEngine(registerBase);
    return [super hideCursor:token];
}

- moveCursor:(Point*)cursorLoc frame:(int)frame token:(int)t
{
    _ix3dIdleEngine(registerBase);
    return [super moveCursor:cursorLoc frame:frame token:t];
}

- open
{
    int result;

    result = [super open];
    if (result == 0) {
        [self initEngine];
        [self enableInterrupt:0];
    }
    return result;
}

- (IOReturn)setIntValues:(unsigned int *)values forParameter:(IOParameterName)parameter count:(unsigned int)count
{
    // Handle hardware-accelerated blit operations
    if (strcmp(parameter, IO_DISPLAY_DO_BLIT) == 0 && count == IO_DISPLAY_BLIT_SIZE) {
        _ix3dDoBlit(registerBase, bytesPerPixel, pixelFormat,
                   values[0], values[1], values[2], values[3], values[4], values[5]);
        return 0;
    }
    // Handle hardware-accelerated fill operations
    else if (strcmp(parameter, IO_DISPLAY_DO_FILL) == 0 && count == IO_DISPLAY_FILL_SIZE) {
        _ix3dDoFill(registerBase, bytesPerPixel, pixelFormat,
                   values[0], values[1], values[2], values[3], values[4]);
        return 0;
    }
    // Handle display sync (wait for idle) operations
    else if (strcmp(parameter, IO_DISPLAY_GET_SYNCED) == 0 && count == IO_DISPLAY_GET_SYNCED_SIZE) {
        _ix3dIdleEngine(registerBase);
        return 0;
    }
    // Pass other parameters to parent
    else {
        return [super setIntValues:values forParameter:parameter count:count];
    }
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)interruptIndex
{
    *handler = (IOInterruptHandler)_ix3dInterruptHandler;
    *ipl = 0x1e;  // Interrupt priority level 30
    *arg = (unsigned int)self;
    return YES;
}

@end
