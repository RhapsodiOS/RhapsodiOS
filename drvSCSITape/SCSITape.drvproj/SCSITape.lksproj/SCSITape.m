/*
 * SCSITape.m -- implementation of scsi tape driver routines
 *
 * HISTORY
 * 31-Mar-93	Phillip Dibner at NeXT
 *	Created.
 *
 */


#import <sys/errno.h>
#import <sys/types.h>
#import <sys/time.h>
#import <sys/conf.h>
#import <sys/uio.h>
#import <sys/mtio.h>
#import <bsd/dev/scsireg.h>

#import <driverkit/scsiTypes.h>
#import <driverkit/align.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/return.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>
#import <kernserv/kern_server_types.h>
#import "SCSITape.h"
#import "SCSITapeTypes.h"

#define DRIVE_TYPE_LENGTH 80

#define USE_EBD	1		/* use "even byte disconnect" rather than
				 * "no disconnect during data xfer" for exabyte
				 */

extern int st_devsw_init();

static int moveString();	/* rmv nulls & blanks from inquiry strings */
void assign_cdb_c6s_len();	/* store length data in little-endian cdb_6s */
void assign_msbd_numblocks();	/* store nblks in little-endian modesel bd */
void assign_msbd_blocklength();	/* store blklen in little-endian modesel bd */
int cdb_c6s_len_value();	/* byte swap to read length data in cdb */
int er_info_value ();		/* byte swapping for sense reply info data */

id		stIdMap [NST];

@implementation SCSITape

+ (IODeviceStyle)deviceStyle
{
	return IO_IndirectDevice;
}

/*
 * The protocol we need as an indirect device.
 */
static Protocol *protocols[] = {
    @protocol(IOSCSIControllerExported),
    nil
};

+ (Protocol **)requiredProtocols
{
    return protocols;
}

static unsigned int tapeUnit = 0;

+ (BOOL) probe: deviceDescription
{
    SCSITape			*tapeId = nil;
    unsigned char		stTarget, stLun;
    id				controllerId =
					[deviceDescription directDevice];
    stInitReturn_t		irtn = STR_ERROR;
    BOOL			brtn = NO;
    int				major;

/* asm volatile("int3");  */ // Early break to debugger

    if ((major = st_devsw_init()) < 0) {
	return NO;
    }

    for (stTarget=0; stTarget<SCSI_NTARGETS; stTarget++) {
	for(stLun=0; stLun<SCSI_NLUNS; stLun++) {

#ifdef DEBUG
IOLog ("SCSITape probe: target %d  lun %d\n", stTarget, stLun);
#endif DEBUG

	    if(tapeId == nil) {
		/*
		 * Create an instance, do some basic
		 * initialization. Set up a default
		 * device name for error reporting during
		 * initialization.
		 */
		tapeId = [SCSITape alloc];
	    }

	    if ([controllerId reserveTarget:stTarget
		lun:stLun
		forOwner:tapeId]) {
		/*
		 * Someone already has this one.
		 */
		continue;
	    }
	    else {
		[tapeId setReservedTargetLun: YES];
	    }

#ifdef DEBUG
IOLog ("SCSITape probe: about to init\n");
#endif DEBUG

	    irtn = [tapeId initSCSITape:(int)tapeUnit
		target: stTarget
		lun: stLun
		controller: controllerId
		majorDeviceNumber: major];

#ifdef DEBUG
IOLog ("SCSITape probe: irtn is %d\n", irtn);
#endif DEBUG

	    switch (irtn) {
		case STR_GOOD:
		    /*
		     * Init'd OK - still must register device.
		     */
		    [tapeId registerDevice];
		    stIdMap [tapeUnit] = tapeId;
		    tapeId = nil;
		    tapeUnit++;
		    if (tapeUnit >= NST) goto done;
		    brtn = YES;
		    break;

		default:
		    [controllerId releaseTarget: stTarget
			lun: stLun
			forOwner: tapeId];
		    [tapeId setReservedTargetLun: NO];
		    if(irtn == STR_SELECTTO) {
			/*
			 * Skip the rest of the luns on
			 * this target.
			 */
			goto nextTarget;
		    }
	    /*
	     * else try next lun.
	     */
	    }	/* switch (irtn) */
	}	/* for lun */

nextTarget:

	continue;
    }		/* for target */

done:
    /*
     * Free up leftover owner and id.  At this point, tapeId does NOT have
     * a target/lun reserved.
     */
    if(tapeId) {
	[tapeId free];
    }

    return brtn;
}


- (stInitReturn_t) initSCSITape:(int)iunit 	/* IODevice unit # */
    target:		(u_char) stTarget
    lun:		(u_char) stLun
    controller:		controllerId
    majorDeviceNumber:	(int) major
{
    inquiry_reply_t	inquiryData;
    sc_status_t		rtn;
    char		driveType[DRIVE_TYPE_LENGTH];	/* name from Inquiry */
    char		*outp;
    char		deviceName[30];
    char		location[IO_STRING_LENGTH];


    /*
     * Initialize common instance variables.
     */
    _controller = controllerId;
    _target = stTarget;
    _lun = stLun;
    sprintf(deviceName, "st%d", iunit);
    [self setName: deviceName];
    [self setDeviceKind:"SCSITape"];
    [self setLocation:[_controller name]];
    [self setUnit: iunit];

#ifdef DEBUG
IOLog
    ("InitSCSITape: target %d  lun %d  unit %d  deviceName %s  location %s\n",
    stTarget, stLun, iunit, deviceName, [_controller name]);
#endif DEBUG

    /*
     * Resources for commands during initialization.
     */
    _senseDataPtr = IOMalloc (sizeof (struct esense_reply));
    _senseDataValid = NO;

    /*
     * Other instance variables
     */
    _didWrite = NO;
    _suppressIllegalLength = NO;
    _isInitialized = NO;
    _devLock = nil;			// Until we know we're a tape

    /*
     * Test Unit Ready to clear possible Unit Attention.   Success is
     * not important.
     */
    [self stTestReady];

    /*
     * Try an Inquiry command.
     */
    bzero(&inquiryData, sizeof(inquiry_reply_t));
    rtn = [self stInquiry:&inquiryData];

#ifdef DEBUG
IOLog ("InitSCSITape inquiry returned %d\n", rtn);
#endif DEBUG

    switch(rtn) {
	case SR_IOST_GOOD:
	    break;
	case SR_IOST_SELTO:
	    return STR_SELECTTO;
	default:
	    return STR_ERROR;
    }

    /*
     * Is it a tape?
     */
    if(inquiryData.ir_qual != DEVQUAL_OK ||
	inquiryData.ir_devicetype != DEVTYPE_TAPE) {

#ifdef DEBUG
IOLog ("InitSCSITape: not a tape\n");
#endif DEBUG

	return(STR_NOTATAPE);
    }

    /*
     * Set up resources for exclusive open.
     */
    _devLock = [[NXLock alloc] init];
    _devAcquired = NO;

    /*
     * Compress multiple blanks out of the vendor id and product ID.
     */
    bzero (driveType, DRIVE_TYPE_LENGTH);
    outp = driveType;
    outp += moveString((char *)&inquiryData.ir_vendorid,
	outp,
	8,
	&driveType[DRIVE_TYPE_LENGTH] - outp);
    if(*(outp - 1) != ' ')
	*outp++ = ' ';
    outp += moveString((char *)&inquiryData.ir_productid,
	outp,
	16,
	&driveType[DRIVE_TYPE_LENGTH] - outp);
    if(*(outp - 1) != ' ')
	*outp++ = ' ';
    outp += moveString((char *)&inquiryData.ir_revision,
	outp,
	4,
	&driveType[DRIVE_TYPE_LENGTH] - outp);
    *outp = '\0';

    sprintf(location, "Target %d LUN %d at %s", _target, _lun,
	[controllerId name]);
    [self setLocation: location];
    IOLog("%s: %s\n", deviceName, driveType);


    /*
     * Do another Test Unit Ready to clear a possible Unit Attention
     * condition.  We don't care about the result.
     */
    [self stTestReady];

    /*
     * Init to variable blk size.
     */
    [self setBlockSize: 0];

    /*
     * Store the major number in our instance.
     */
    _majorDevNum = major;

    [super init];
    _isInitialized = YES;
    return(STR_GOOD);
} /* - initSCSITape: */


- free
{
    if (_senseDataPtr)
	IOFree (_senseDataPtr, sizeof (struct esense_reply));
    if (_devLock)
	[_devLock free];
    if (_reservedTargetLun)
	[_controller releaseTarget: _target lun: _lun forOwner: _controller];
    return [super free];
}


- (IOReturn) getIntValues: (unsigned int *)values
    forParameter: (IOParameterName) parameter
    count: (unsigned int *) count
{
    int maxCount = *count;

    if(maxCount == 0) {
        maxCount = IO_MAX_PARAMETER_ARRAY_LENGTH;
    }

    if(strcmp(parameter, "IOMajorDevice") == 0) {
	values [0] = [self majorDevNum];
	*count = 1;
	return IO_R_SUCCESS;
    }

    if (strcmp(parameter, "Unit") == 0) {
	values [0] = [self unit];
	*count = 1;
        return IO_R_SUCCESS;

    }

    return [super getIntValues:values
	forParameter:parameter
	count:&maxCount];
}



/*
 * Gets and sets for instance variables.
 */

- (int) target			/* Set only during initialization */
{
    return (int) _target;
}

- (int) lun			/* Set only during initialization */
{
    return (int) _lun;
}

- controller			/* Set only during initialization */
{
    return _controller;
}

- (BOOL) isInitialized		/* Object has been initialized */
{
    return _isInitialized;
}

- (BOOL) didWrite		/* Last command was a write */
{
    return _didWrite;
}

- (BOOL) isFixedBlock
{
    if (_blockSize) {		/* Zero blocksize means variable block size */
	return YES;
    } else {
	return NO;
    }
}

- (BOOL) senseDataValid
{
    return _senseDataValid;
}

- forceSenseDataInvalid		/* for MTIOCGET and friends */
{
    _senseDataValid = NO;
    return self;
}

- (struct esense_reply *) senseDataPtr
{
    return _senseDataPtr;
}

- (int) blockSize		/* Set only via setBlockSize SCSI operation */
{
    return _blockSize;
}

- (BOOL) suppressIllegalLength
{
    return _suppressIllegalLength;
}

- setSuppressIllegalLength: (BOOL) condition
{
    _suppressIllegalLength = condition;
    return self;
}

- (BOOL) ignoreCheckCondition
{
    return _ignoreCheckCondition;
}

- setIgnoreCheckCondition: (BOOL) condition
{
    _ignoreCheckCondition = condition;
    return self;
}

- (int) majorDevNum
{
    return _majorDevNum;
}

- setReservedTargetLun: (BOOL) condition
{
    _reservedTargetLun = condition;
    return self;
}

- (BOOL) reservedTargetLun
{
    return _reservedTargetLun;
}

- (IOReturn) acquireDevice
{
    IOReturn		ret = IO_R_INVALID;

    [_devLock lock];
    if (_devAcquired == YES) {
	ret = IO_R_BUSY;
    } else {
	_devAcquired = YES;
	ret = IO_R_SUCCESS;
    }
    [_devLock unlock];
    return ret;
}

- (IOReturn) releaseDevice
{
    [_devLock lock];
    _devAcquired = NO;
    [_devLock unlock];
    return IO_R_SUCCESS;
}


/*
 * General SCSI commands
 */
- (sc_status_t) stInquiry: (inquiry_reply_t *) inquiryReply
{
    IOSCSIRequest 		scsiReq;
    cdb_6_t 			*cdbp = &scsiReq.cdb.cdb_c6;
    inquiry_reply_t 		*alignedReply;
    void 			*freePtr;
    int 			freeCnt;
    sc_status_t 		rtn;
    IODMAAlignment 		dmaAlign;


    /*
     * Get some well-aligned memory.
     */
    alignedReply = [_controller
	allocateBufferOfLength: sizeof(inquiry_reply_t)
	actualStart:&freePtr
	actualLength:&freeCnt];
    bzero(alignedReply, sizeof(inquiry_reply_t));
    bzero(&scsiReq, sizeof(IOSCSIRequest));
    scsiReq.target = _target;
    scsiReq.lun = _lun;
    scsiReq.read = YES;

    /*
     * Get appropriate alignment from controller.
     */
    [_controller getDMAAlignment:&dmaAlign];
    if(dmaAlign.readLength > 1) {
	scsiReq.maxTransfer = IOAlign(int, sizeof(inquiry_reply_t),
	    dmaAlign.readLength);
    }
    else {
	scsiReq.maxTransfer = sizeof(inquiry_reply_t);
    }

    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;

    cdbp->c6_opcode = C6OP_INQUIRY;
    cdbp->c6_lun = _lun;
    cdbp->c6_len = sizeof(inquiry_reply_t);

    [self executeRequest: &scsiReq
	buffer: alignedReply
	client: IOVmTaskSelf()
	senseBuf: _senseDataPtr];

    if(scsiReq.driverStatus == SR_IOST_GOOD) {
	unsigned required = (char *)(&alignedReply->ir_zero3[0]) -
	    (char *)(alignedReply);
	if(scsiReq.bytesTransferred < required) {
	    IOLog("%s: bad DMA Transfer count (%d) on Inquiry\n",
		[self name], scsiReq.bytesTransferred);
	    rtn = SR_IOST_HW;
	}
	else {
	/*
	 * Copy data back to caller's struct. Zero the
	 * portion of alignedReply which did not get valid
	 * data; the last flush out of the DMA pipe could
	 * have written trash to it (and our caller
	 * expects NULL data).
	 */
	    unsigned zeroSize;

	    zeroSize = sizeof(*alignedReply) - scsiReq.bytesTransferred;
	    if(zeroSize) {
		bzero((char *)alignedReply + scsiReq.bytesTransferred,
		    zeroSize);
	    }
	    *inquiryReply = *alignedReply;
	    rtn = scsiReq.driverStatus;
	}
    }
    else {
	rtn = scsiReq.driverStatus;
    }

    IOFree(freePtr, freeCnt);
    return rtn;
} /* - stInquiry: */



- (BOOL) stTestReady
{
    IOSCSIRequest	scsiReq;
    cdb_6_t		*cdbp = &scsiReq.cdb.cdb_c6;
    BOOL		rtn;

    bzero(&scsiReq, sizeof(IOSCSIRequest));
    scsiReq.target = _target;
    scsiReq.lun = _lun;
    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;

    cdbp->c6_opcode = C6OP_TESTRDY;
    cdbp->c6_lun = _lun;

    [self executeRequest: &scsiReq
	buffer: (void *) NULL
	client: IOVmTaskSelf()
	senseBuf: _senseDataPtr];

    /*
     * XXX Do we need to distinguish not ready from no tape?
     */
    switch(scsiReq.driverStatus) {
	case SR_IOST_GOOD:
	    rtn = YES;
	    break;
	default:
	    rtn = NO;
	    break;
    }

    return rtn;
} /* - stTestReady: */



- (sc_status_t) stCloseFile
{
    IOSCSIRequest 		scsiReq;
    cdb_6s_t 			*cdbp = &scsiReq.cdb.cdb_c6s;

    bzero(&scsiReq, sizeof(IOSCSIRequest));
    scsiReq.target = _target;
    scsiReq.lun = _lun;
    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;
    cdbp->c6s_opcode = C6OP_WRTFM;
    assign_cdb_c6s_len (cdbp, 1);		/* one file mark */

    return [self executeRequest: &scsiReq
	buffer: NULL
	client: IOVmTaskSelf()
	senseBuf: _senseDataPtr];
} /* - stCloseFile */


- (sc_status_t) stRewind
{
    IOSCSIRequest 		scsiReq;
    cdb_6s_t 			*cdbp = &scsiReq.cdb.cdb_c6s;

    bzero(&scsiReq, sizeof(IOSCSIRequest));
    scsiReq.target = _target;
    scsiReq.lun = _lun;
    scsiReq.timeoutLength = ST_IOTO_RWD;
    scsiReq.disconnect = 1;
    cdbp->c6s_opcode = C6OP_REWIND;

    return [self executeRequest: &scsiReq
	buffer: NULL
	client: IOVmTaskSelf()
	senseBuf: _senseDataPtr];
} /* - stRewind */


/*
 * Get sense data. senseBuf does not have to be well aligned.
 */
- (sc_status_t) requestSense: (esense_reply_t *)senseBuf
{
    IOSCSIRequest 	scsiReq;
    cdb_6_t 		*cdbp = &scsiReq.cdb.cdb_c6;
    esense_reply_t 	*alignedBuf;
    void 		*freePtr;
    int 		freeCnt;
    sc_status_t 	rtn;
    IODMAAlignment	dmaAlign;

    alignedBuf = [_controller allocateBufferOfLength: sizeof(esense_reply_t)
	actualStart: &freePtr
	actualLength: &freeCnt];
    bzero(&scsiReq, sizeof(IOSCSIRequest));
    [_controller getDMAAlignment:&dmaAlign];

    scsiReq.target 		= _target;
    scsiReq.lun 		= _lun;
    scsiReq.read		= YES;

    if(dmaAlign.readLength > 1) {
	scsiReq.maxTransfer = IOAlign(int, sizeof(esense_reply_t),
	    dmaAlign.readLength);

    } else {
	scsiReq.maxTransfer = sizeof(esense_reply_t);
    }

    scsiReq.timeoutLength = ST_IOTO_NORM;  // XXX Should be ST_IOTO_SENSE??
    scsiReq.disconnect = 0;
    cdbp->c6_opcode = C6OP_REQSENSE;
    cdbp->c6_lun = _lun;
    cdbp->c6_len = sizeof(esense_reply_t);

    rtn = [_controller executeRequest:&scsiReq
	buffer:alignedBuf
	client:IOVmTaskSelf()];
    if(rtn == SR_IOST_GOOD) {
	*senseBuf = *alignedBuf;
	_senseDataValid = YES;
    }
    IOFree(freePtr, freeCnt);
    return rtn;
} /* - requestSense: */




- (sc_status_t) stModeSelect: (struct modesel_parms *) modeSelectParmsPtr
{
    IOSCSIRequest 		scsiReq;
    cdb_6_t 			*cdbp = &scsiReq.cdb.cdb_c6;
    int				count = modeSelectParmsPtr->msp_bcount;
    struct mode_sel_data 	*alignedBuf;
    void 			*freePtr;
    int 			freeCnt;
    sc_status_t 		rtn;
    IODMAAlignment		dmaAlign;

    alignedBuf = [_controller
	allocateBufferOfLength: count
	actualStart: &freePtr
	actualLength: &freeCnt];


    bzero(&scsiReq, sizeof(IOSCSIRequest));

    scsiReq.target 		= _target;
    scsiReq.lun 		= _lun;
    scsiReq.read		= NO;

    [_controller getDMAAlignment:&dmaAlign];
    if(dmaAlign.readLength > 1) {
	scsiReq.maxTransfer = IOAlign(int, count,
	    dmaAlign.readLength);

    } else {
	scsiReq.maxTransfer = count;
    }

    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;
    cdbp->c6_opcode = C6OP_MODESELECT;
    cdbp->c6_lun = _lun;
    cdbp->c6_len = count;

    bcopy (&modeSelectParmsPtr->msp_data, alignedBuf, count);

    rtn = [self executeRequest:&scsiReq
	buffer:alignedBuf
	client:IOVmTaskSelf()
	senseBuf: _senseDataPtr];

    IOFree(freePtr, freeCnt);
    return rtn;
} /* - stModeSelect: */




- (sc_status_t) stModeSense: (struct modesel_parms *) modeSenseParmsPtr
{
    IOSCSIRequest 		scsiReq;
    cdb_6_t 			*cdbp = &scsiReq.cdb.cdb_c6;
    int				count = modeSenseParmsPtr->msp_bcount;
    struct mode_sel_data 	*alignedBuf;
    void 			*freePtr;
    int 			freeCnt;
    sc_status_t 		rtn;
    IODMAAlignment		dmaAlign;

    alignedBuf = [_controller
	allocateBufferOfLength: count
	actualStart: &freePtr
	actualLength: &freeCnt];


    bzero(&scsiReq, sizeof(IOSCSIRequest));

    scsiReq.target 		= _target;
    scsiReq.lun 		= _lun;
    scsiReq.read		= YES;

    [_controller getDMAAlignment:&dmaAlign];
    if(dmaAlign.readLength > 1) {
	scsiReq.maxTransfer = IOAlign(int, count,
	    dmaAlign.readLength);

    } else {
	scsiReq.maxTransfer = count;
    }

    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;
    cdbp->c6_opcode = C6OP_MODESENSE;
    cdbp->c6_lun = _lun;
    cdbp->c6_len = count;

    rtn = [self executeRequest:&scsiReq
	buffer:alignedBuf
	client:IOVmTaskSelf()
	senseBuf: _senseDataPtr];

    if(rtn == SR_IOST_GOOD) {
	bcopy (alignedBuf, &modeSenseParmsPtr->msp_data, count);
    }

    IOFree(freePtr, freeCnt);
    return rtn;
} /* - stModeSense: */



- (sc_status_t) executeMTOperation: (struct mtop *) mtopp
{
    IOSCSIRequest 		scsiReq;
    cdb_6s_t 			*cdbp = &scsiReq.cdb.cdb_c6s;
    int				count;
    sc_status_t			rtn;

    bzero(&scsiReq, sizeof(IOSCSIRequest));
    scsiReq.target = _target;
    scsiReq.lun = _lun;
    scsiReq.timeoutLength = ST_IOTO_NORM;	/* Some ops override this */
    scsiReq.disconnect = 1;  // XXX - maybe not for all ops.

    /*
     * none of these operations performs DMA. For each, just fill in
     * the cdb, and pass it to the controller.
     */

    /* build a CDB */

    switch(mtopp->mt_op) {
	case MTWEOF:		/* write file marks */
	    cdbp->c6s_opcode = C6OP_WRTFM;
	    goto setcount_f;

	case MTFSF:		/* space file marks forward */
	    cdbp->c6s_opcode = C6OP_SPACE;
	    cdbp->c6s_opt = C6OPT_SPACE_FM;
	    scsiReq.timeoutLength = mtopp->mt_count * ST_IOTO_SPFM;
	    goto setcount_f;

	case MTBSF:		/* space file marks backward */
	    cdbp->c6s_opcode = C6OP_SPACE;
	    cdbp->c6s_opt = C6OPT_SPACE_FM;
	    scsiReq.timeoutLength = mtopp->mt_count * ST_IOTO_SPFM;
	    goto setcount_b;

	case MTFSR:		/* space records forward */
	    cdbp->c6s_opcode = C6OP_SPACE;
	    cdbp->c6s_opt = C6OPT_SPACE_LB;
	    scsiReq.timeoutLength = ST_IOTO_SPR;
setcount_f:
	    assign_cdb_c6s_len (cdbp, mtopp->mt_count);
	    break;

	case MTBSR:			/* space records backward */
	    cdbp->c6s_opcode = C6OP_SPACE;
	    cdbp->c6s_opt = C6OPT_SPACE_LB;
	    scsiReq.timeoutLength = ST_IOTO_SPR;
setcount_b:
	    count = 0 - mtopp->mt_count;
	    assign_cdb_c6s_len (cdbp, count);
	    break;

	case MTREW:			/* rewind */
	    cdbp->c6s_opcode = C6OP_REWIND;
	    scsiReq.timeoutLength = ST_IOTO_RWD;
	    break;

	case MTOFFL:			/* set offline */
	    cdbp->c6s_opcode = C6OP_STARTSTOP;
					/* note load bit is 0 */
	    scsiReq.timeoutLength = ST_IOTO_RWD;
	    break;

	case MTNOP:		/* nop / get status */
	case MTCACHE:		/* enable cache */
	case MTNOCACHE:		/* disable cache */
	case MTRETEN:
	case MTERASE:
	default:
	    rtn = SR_IOST_CMDREJ;	/* FIXME: unsupported? */
	    goto out;
    }

    rtn = [self executeRequest: &scsiReq
	buffer: NULL
	client: IOVmTaskSelf()
	senseBuf: _senseDataPtr];
out:
    return rtn;
} /* - executeMTOperation: */



/*
 * Set block size for SCSI tape device.
 *
 * blocksize == 0 --> variable
 * blocksize != 0 --> fixed @ blocksize
 *
 * First, execute mode sense, then mode select with block length
 * set to 0 (variable) or blocksize (fixed)
 */
- (IOReturn) setBlockSize: (int) blockSize
{
    int				rtn;
    struct modesel_parms	*mspp;
    struct mode_sel_hdr		*mshp;

    mspp = IOMalloc (sizeof(struct modesel_parms));
    mspp->msp_bcount = sizeof(struct mode_sel_hdr) +
	sizeof(struct mode_sel_bd);

    if((rtn = [self stModeSense: mspp]) != SR_IOST_GOOD) {
	IOFree (mspp, sizeof (struct modesel_parms));
	return [_controller returnFromScStatus: rtn];
    }

    mshp = &mspp->msp_data.msd_header;
    mshp->msh_sd_length_0 = 0;
    mshp-> msh_med_type = 0;
    mshp-> msh_wp = 0;
    mshp-> msh_bd_length = sizeof(struct mode_sel_bd);
    assign_msbd_blocklength
	(&mspp->msp_data.msd_blockdescript, blockSize);
    assign_msbd_numblocks
	(&mspp->msp_data.msd_blockdescript, 0);

    if((rtn = [self stModeSelect: mspp]) != SR_IOST_GOOD) {
	IOFree (mspp, sizeof (struct modesel_parms));
	return [_controller returnFromScStatus: rtn];
    }

    _blockSize = blockSize;

    IOFree (mspp, sizeof (struct modesel_parms));
    return IO_R_SUCCESS;
} /* - setBlockSize: */




/*
 * Execute CDB.   Buffer must be well aligned.   If command results
 * in Check Status, return the sense data in *senseBuf.
 */
- (sc_status_t) executeRequest: (IOSCSIRequest *)scsiReq
    buffer:(void *) buffer /* data destination */
    client:(vm_task_t) client
    senseBuf:(esense_reply_t *) senseBuf
{
    sc_status_t			rtn;

    _senseDataValid = NO;

#ifdef DEBUG
IOLog("Entered SCSI Tape executeRequest: op %s, maxTransfer %d, len %d\n",
    IOFindNameForValue(scsiReq->cdb.cdb_opcode,
	IOSCSIOpcodeStrings),
    scsiReq->maxTransfer,
    (scsiReq->cdb.cdb_c6s.c6s_len2 << 16) |
	(scsiReq->cdb.cdb_c6s.c6s_len1 << 8) |
	(scsiReq->cdb.cdb_c6s.c6s_len0));
#endif DEBUG

    rtn = [_controller executeRequest:scsiReq
	buffer:buffer
	client:client];

#ifdef DEBUG
IOLog ("Length %d on return from executeRequest\n", scsiReq->bytesTransferred);
#endif DEBUG

    /*
     * Log error returns.
     */
    if (rtn != SR_IOST_GOOD) {
	/*
	 * If result is Check Condition, do a Request Sense, unless suppressed.
	 */
	if(rtn == SR_IOST_CHKSV) {
		/*
		 * Host Adaptor already got us sense data. Give sense data
		 * to user and save it.
		 */
		*senseBuf = *_senseDataPtr = scsiReq->senseData;
		_senseDataValid = YES;
	}
	if (((rtn == SR_IOST_CHKSNV) || (rtn == SR_IOST_CHKSV)) &&
	   	!_ignoreCheckCondition) {
	    if(rtn == SR_IOST_CHKSV) {
	    	rtn = SR_IOST_GOOD;
	    }
	    else {
		rtn = [self requestSense: senseBuf];
	    }
	    if(rtn == SR_IOST_GOOD) {
		/*
		 * If the error is a filemark, and we are reading,
		 * then return no error.   Otherwise, return
		 * check sense, with valid sense data.
		 */
		if ((scsiReq->cdb.cdb_c6.c6_opcode == C6OP_READ) &&
		    (senseBuf->er_filemark)) {

		    /*
		     * Check for correct reporting of bytes transferred.
		     * (This works around a DPT firmware bug.)
		     */
		    int	transferLength =
			cdb_c6s_len_value (&scsiReq->cdb.cdb_c6s) -
			er_info_value (senseBuf);

		    if ([self isFixedBlock]) {
			transferLength = transferLength * _blockSize;
		    }

		    if (scsiReq->bytesTransferred != transferLength) {
#ifdef DEBUG
IOLog ("%s: Incorrect byte count reported - "
    "corrected to %d\n", [self name], transferLength);
#endif DEBUG
			scsiReq->bytesTransferred = transferLength;
		    }

		    rtn = SR_IOST_GOOD;
		    scsiReq->driverStatus = SR_IOST_GOOD;

#ifdef DEBUG
IOLog ("execReq sense: er_filemark %d, er_badlen %d, er_sensekey %d, er_addsensecode %d, er_qualifier %d, er_info %d\n",
	senseBuf->er_filemark, senseBuf->er_badlen, senseBuf->er_sensekey,
	senseBuf->er_addsensecode, senseBuf->er_qualifier,
	er_info_value (senseBuf));
#endif DEBUG

		}
		else {
		    rtn = SR_IOST_CHKSV;
		}
	    }
	    else {
	 	if (_isInitialized) {
		    IOLog("%s: Request Sense on target %d lun %d "
			"failed (%s)\n",
			[self name], _target, _lun,
			IOFindNameForValue(rtn, IOScStatusStrings));
		}
		rtn = SR_IOST_CHKSNV;
	    }
	}

	/*
	 * Log error messages, except the spate of timeouts and
	 * device not ready messages during initialization.
	 */
	if (_isInitialized &&
	    (rtn != SR_IOST_GOOD) &&
	    !_ignoreCheckCondition) {

	    IOLog("%s, target %d, lun %d: op %s returned %s\n",
		[self name], _target, _lun,
		IOFindNameForValue(scsiReq->cdb.cdb_opcode,
		    IOSCSIOpcodeStrings),
		IOFindNameForValue(rtn, IOScStatusStrings));

	    if (rtn == SR_IOST_CHKSV) {
		IOLog ("    Sense key = 0x%x  Sense Code = 0x%x\n",
		    senseBuf->er_sensekey, senseBuf->er_addsensecode);
	    }
	}

	_didWrite = NO;
    }

    else {
	/* Remember good writes for device close */
	if (scsiReq->cdb.cdb_opcode == C6OP_WRITE) {
	    _didWrite = YES;
	} else {
	    _didWrite = NO;
	}
    }

    return rtn;
} /* executeRequest: */

@end

/*
 * Supporting functions.
 */

/*
 * moveString is taken directly from SCSIDiskPrivate.m.
 * It's used by -initSCSITape:
 *
 * Copy inp to outp for up to inlength input characters or outlength output
 * characters. Compress multiple spaces and eliminate nulls. Returns number
 * of characters copied to outp.
 */
static int
moveString(char *inp, char *outp, int inlength, int outlength)
{
    int lastCharSpace = 0;
    char *outpStart = outp;

    while(inlength && outlength) {
	switch(*inp) {
	    case '\0':
		inp++;
		inlength--;
		continue;
	    case ' ':
		if(lastCharSpace) {
		    inp++;
		    inlength--;
		    continue;
		}
		lastCharSpace = 1;
		goto copyit;
	    default:
		lastCharSpace = 0;
copyit:
		*outp++ = *inp++;
		inlength--;
		outlength--;
		break;
	    }
    }
    return(outp - outpStart);
}



void
assign_cdb_c6s_len (struct cdb_6s *cdbp, int length)
{
#if	__BIG_ENDIAN__
#if	__NATURAL_ALIGNMENT__
    cdbp->c6s_len[0] = (length >> 16) & 0xff;
    cdbp->c6s_len[1] = (length >> 8) & 0xff;
    cdbp->c6s_len[2] = length & 0xff;

#else	__NATURAL_ALIGNMENT__

    cdbp->c6s_len = length;

#endif	__NATURAL_ALIGNMENT__


#elif	__LITTLE_ENDIAN__

    cdbp->c6s_len0 = (u_char) length & 0xff;
    cdbp->c6s_len1 = (u_char) (length >> 8) & 0xff;
    cdbp->c6s_len2 = (u_char) (length >> 16) & 0xff;

#endif

    return;
}

void
assign_msbd_numblocks (struct mode_sel_bd *msbdp, int numblocks)
{
#if	__BIG_ENDIAN__
    msbdp->msbd_numblocks = numblocks;
#elif	__LITTLE_ENDIAN__
    msbdp->msbd_numblocks0 = (u_char) numblocks & 0xff;
    msbdp->msbd_numblocks1 = (u_char) (numblocks >> 8) & 0xff;
    msbdp->msbd_numblocks2 = (u_char) (numblocks >> 16) & 0xff;
#endif
    return;
}

void
assign_msbd_blocklength (struct mode_sel_bd *msbdp, int length)
{
#if	__BIG_ENDIAN__
    msbdp->msbd_blocklength = length;
#elif	__LITTLE_ENDIAN__
    msbdp->msbd_blocklength0 = (u_char) length & 0xff;
    msbdp->msbd_blocklength1 = (u_char) (length >> 8) & 0xff;
    msbdp->msbd_blocklength2 = (u_char) (length >> 16) & 0xff;
#endif
    return;
}

int
cdb_c6s_len_value (struct cdb_6s *cdbp)
{
#if	__BIG_ENDIAN__
    return (cdbp->c6s_len);
#elif	__LITTLE_ENDIAN__
    return (cdbp->c6s_len0 | (cdbp->c6s_len1 << 8) | (cdbp->c6s_len2 << 16));
#endif
}

int
er_info_value (struct esense_reply *esrp)
{
#if	__BIG_ENDIAN__
    return (esrp->er_info);
#elif	__LITTLE_ENDIAN__
    return (esrp->er_info0 | (esrp->er_info1 << 8) |
	(esrp->er_info2 << 16) | (esrp->er_info3 << 24));
#endif
}
