
/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * SCSITape.h - Interface for SCSI Tape device class.
 *
 * HISTORY
 * 31-Mar-93    Phillip Dibner at NeXT
 *      Created.
 */

#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/generalFuncs.h>
#import <dev/scsireg.h>
#import <machkit/NXLock.h>
#import <objc/Protocol.h>
#import "SCSITapeTypes.h"


@interface SCSITape: IODevice
{
@private
    /*
     * Configuration information
     */
    id 		_controller;	// the SCSIController object which does
				// our SCSI transactions
    u_char	_target;	// target/lun of this device
    u_char	_lun;

    int		_majorDevNum;

    int		_blockSize;

    /*
     * Driver state
     */
    esense_reply_t	*_senseDataPtr;	// for MTIOCGET
    id			_devLock;	// NXLock for exclusive open
    BOOL		_isInitialized;	// Object has been initialized
    BOOL		_devAcquired;	// device reserved by some task
    BOOL		_didWrite;	// last command was a write
    BOOL		_suppressIllegalLength;	// Suppress IL errors
    BOOL		_senseDataValid;// *_senseDataPtr from last command OK
    BOOL		_reservedTargetLun; // Controller has reserved t & l
    BOOL		_ignoreCheckCondition; // during Test Ready in open()
};


/* Class methods */

+ (BOOL)probe: deviceDescription;
+ (IODeviceStyle) deviceStyle;
+ (Protocol **) requiredProtocols;

- (stInitReturn_t) initSCSITape: (int) stUnit
    target:		(u_char) stTarget
    lun:		(u_char) stLun
    controller:		stController
    majorDeviceNumber:	(int) major;

- (int)target;
- (int)lun;
- controller;
- (BOOL) isInitialized;
- (BOOL) isFixedBlock;
- (BOOL) senseDataValid;
- (BOOL) didWrite;
- forceSenseDataInvalid;
- (struct esense_reply *) senseDataPtr;
- (int) blockSize;
- (BOOL) suppressIllegalLength;
- setSuppressIllegalLength: (BOOL) condition;
- setReservedTargetLun: (BOOL) condition;
- (BOOL) ignoreCheckCondition;
- setIgnoreCheckCondition: (BOOL) condition;
- (BOOL) reservedTargetLun;
- (int) majorDevNum;
- (IOReturn) acquireDevice;
- (IOReturn) releaseDevice;

- (sc_status_t) stInquiry: (inquiry_reply_t *) inquiryReply;
- (BOOL) stTestReady;
- (sc_status_t) stCloseFile;
- (sc_status_t) stRewind;
- (sc_status_t) requestSense: (esense_reply_t *)senseBuf;
- (sc_status_t) stModeSelect: (struct modesel_parms *) modeSelectParmsPtr;
- (sc_status_t) stModeSense: (struct modesel_parms *) modeSenseParmsPtr;
- (sc_status_t) executeMTOperation: (struct mtop *) mtopp;
- (IOReturn) setBlockSize: (int) blockSize;
- (sc_status_t) executeRequest: (IOSCSIRequest *)scsiReq
    buffer:(void *) buffer
    client:(vm_task_t) client
    senseBuf:(esense_reply_t *) senseBuf;

@end
