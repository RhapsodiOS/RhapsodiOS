/* Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * SCSITapeKern.m -- implementation of scsi tape driver entry point routines
 *
 * HISTORY
 * 31-Mar-93	Phillip Dibner at NeXT
 *	Created.   Adapted from st.c, created by Doug Mitchell at NeXT.
 *
 */

/*
 * Four different devices are implemented here:
 *
 *	rst - generic SCSI tape, rewind on close
 *	nrst - generic SCSI tape, no rewind on close
 *	rxt - Exabyte SCSI tape, rewind on close
 *	nrxt - Exabyte SCSI tape, no rewind on close
 *
 *	All 4 devices have the same major number. Bit 0 of the minor number
 *	selects "rewind on close" (0) or "no rewind" (1). Bit 1 of the
 *	minor number select generic (0) or Exabyte (1).
 *
 *	The Exabyte drive currently requires these actions on open:
 *
 *		-- enable Buffered Write mode
 *		-- Inhibit Illegal Length errors
 *		-- Disable Disconnect During Data Transfer
 */

#import <sys/errno.h>
#import <sys/types.h>
#import <sys/buf.h>
#import <sys/conf.h>
#import <sys/uio.h>
#import <sys/mtio.h>
#import <bsd/dev/scsireg.h>

#import <driverkit/scsiTypes.h>
#import <driverkit/align.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/scsiTypes.h>
#import <driverkit/return.h>
#import <driverkit/devsw.h>
#import <kernserv/prototypes.h>
#import "SCSITape.h"


#define USE_EBD	1		/* use "even byte diconnect" rather than
				 * "no disconnect during data xfer" for exabyte
				 */

/*
 * Unix-style entry points
 */
int stopen (dev_t dev);
int stclose (dev_t dev);
int stread (dev_t dev, struct uio *uiop);
int stwrite (dev_t dev, struct uio *uiop);
int stioctl (dev_t dev, int cmd, caddr_t data, int flag);

/*
 * Subsidiary functions used by the kernel "glue" layer
 */
static int st_rw (dev_t dev, struct uio *uiop, int rw_flag);
static int st_doiocsrq (id scsiTape, scsi_req_t *srp);

/*
 * Functions to take care of byte-ordering issues
 */
extern void assign_cdb_c6s_len();
extern void assign_msbd_numblocks();
extern void assign_msbd_blocklength();
unsigned int read_er_info_low_24();

extern id		stIdMap[];


/*
 * Add ourself to cdevsw. Called from SCSIGeneric layer at probe time.
 */
extern int		nulldev();
extern int		nodev();

static int stMajor = -1;

int
st_devsw_init()
{
    int		rtn;

    /*
     * We get called once for each IOSCSIController in the system; we
     * only have to call IOAddToCdevsw() once.
     */
    if(stMajor >= 0) {
    	return stMajor;
    }
    rtn = IOAddToCdevsw ((IOSwitchFunc) stopen,
	(IOSwitchFunc) stclose,
	(IOSwitchFunc) stread,
	(IOSwitchFunc) stwrite,
	(IOSwitchFunc) stioctl,
	(IOSwitchFunc) nodev,
	(IOSwitchFunc) nulldev,		// reset
	(IOSwitchFunc) nulldev,
	(IOSwitchFunc) nodev,		// mmap
	(IOSwitchFunc) nodev,		// getc
	(IOSwitchFunc) nodev);		// putc
    if(rtn < 0) {
	IOLog("st: Can't find space in devsw\n");
    }
    else {
	IOLog("st: major number %d\n", rtn);
	stMajor = rtn;
    }
    return rtn;
}


int
stopen(dev_t dev)
{
    int			unit = ST_UNIT(dev);
    id			scsiTape = stIdMap[unit];

    if([scsiTape acquireDevice] == IO_R_BUSY)
	return(EBUSY);			/* already open */
    if ((unit >= NST) || 			/* illegal device */
	([scsiTape isInitialized] == NO)) {	/* hasn't been init'd */
	    [scsiTape releaseDevice];
	    return(ENXIO);			/* FIXME - try to init here */
    }

    /*
     * We send this once, and ignore result, to clear check condition
     * due to media change, etc.
     */
    [scsiTape setIgnoreCheckCondition: YES];
    [scsiTape stTestReady];
    [scsiTape setIgnoreCheckCondition: NO];

    if(ST_EXABYTE(dev)) {
	struct modesel_parms		*mspp;
	struct exabyte_vudata		*evudp;
	struct mode_sel_hdr		*mshp;

	mspp = IOMalloc (sizeof (struct modesel_parms));
	evudp = (struct exabyte_vudata *) &mspp->msp_data.msd_vudata;

	/*
	 * Exabyte "custom" setup
	 */

	/* Set variable block size */
	if([scsiTape setBlockSize: 0] != IO_R_SUCCESS) {
	    IOFree (mspp, sizeof (struct modesel_parms));
	    [scsiTape releaseDevice];

#ifdef DEBUG
IOLog ("stopen: cannot set block size variable\n");
#endif DEBUG

	    return(EIO);
	}

	/* Suppress illegal length errors */
	[scsiTape setSuppressIllegalLength: YES];

	/* Do a mode sense */
	mspp->msp_bcount = sizeof(struct mode_sel_hdr) +
	    sizeof(struct mode_sel_bd) + MSP_VU_EXABYTE;

	if([scsiTape stModeSense: mspp] != SR_IOST_GOOD) {
	    IOFree (mspp, sizeof (struct modesel_parms));
	    [scsiTape releaseDevice];

#ifdef DEBUG
IOLog ("stopen: Mode Sense failed\n");
#endif DEBUG

	    return(EIO);
	}

	/* some fields we have to zero as a matter of course */
	mshp = &mspp->msp_data.msd_header;
	mshp->msh_sd_length_0 = 0;
	mshp->msh_med_type = 0;
	mshp->msh_wp = 0;
	mshp->msh_bd_length = sizeof(struct mode_sel_bd);
	assign_msbd_blocklength (&mspp->msp_data.msd_blockdescript, 0);
	assign_msbd_numblocks (&mspp->msp_data.msd_blockdescript, 0);

	/*
	 * set up buffered mode, #blocks = 0, even byte disconnect,
	 * enable parity; do mode selsect
	 */
	mspp->msp_data.msd_header.msh_bufmode = 1;

#ifdef	USE_EBD
	/* clear NDD and set EBD; enable parity  */
	evudp->nd = 0;		/* disconnects OK */
	evudp->ebd = 1;		/* but only on word boundaries */
	evudp->pe = 1;		/* parity enabled */
	evudp->nbe = 1;		/* Busy status disabled */
#else	USE_EBD
	evudp->nd = 1;
#endif	USE_EBD
	if([scsiTape stModeSelect: mspp] != SR_IOST_GOOD) {
	    IOFree (mspp, sizeof (struct modesel_parms));
	    [scsiTape releaseDevice];

#ifdef DEBUG
IOLog ("stopen: Mode Select failed\n");
#endif DEBUG

	    return(EIO);
	}
	IOFree (mspp, sizeof (struct modesel_parms));
    }
    return(0);
}




int
stclose(dev_t dev)
{
    int			unit = ST_UNIT(dev);
    id			scsiTape = stIdMap[unit];
    int			rtn = 0;

    if ([scsiTape didWrite] == YES) {
	/* we must write a file mark to close the file */
	if ([scsiTape stCloseFile] != SR_IOST_GOOD) {
	    rtn = EIO;
	}
    }

    if(ST_RETURN(dev) == 0) {		/* returning device? */
	if ([scsiTape stRewind] != SR_IOST_GOOD) {
	    rtn = EIO;
	}
    }

    [scsiTape releaseDevice];
    return(rtn);
}


int
stread(dev_t dev, struct uio *uiop)
{
    return(st_rw(dev,uiop,SR_DMA_RD));
}

int
stwrite(dev_t dev, struct uio *uiop)
{
    return(st_rw(dev,uiop,SR_DMA_WR));
}


static int
st_rw(dev_t dev, struct uio *uiop, int rw_flag) {

    int 			unit = ST_UNIT(dev);
    id				scsiTape = stIdMap[unit];
    IOSCSIRequest	 	scsiReq;
    struct cdb_6s		*cdbp = &scsiReq.cdb.cdb_c6s;
    void 			*freePtr;
    int 			freeCnt;
    unsigned char		*alignedBuf;
    IODMAAlignment		dmaAlign;
    int				length;
    int				rtn = 0;

sc_status_t scRet = -1;

    if (unit >= NST)
	return(ENXIO);
    if(uiop->uio_iovcnt != 1)		/* single requests only */
	return(EINVAL);
    if(uiop->uio_iov->iov_len == 0)
	return(0);			/* nothing to do */

#ifdef	DEBUG
//	if(rw_flag == SR_DMA_RD) {
//		XCDBG(("st: READ; count = %xH\n", uiop->uio_iov->iov_len));
//	}
//	else {
//		XCDBG(("st: WRITE; count = %xH\n", uiop->uio_iov->iov_len));
//	}
#endif	DEBUG

    /*
     * FIXME: should wire user's memory and DMA from there, avoiding
     * a copyin() or copyout().
     */

    alignedBuf = [[scsiTape controller]
	allocateBufferOfLength: uiop->uio_iov->iov_len
	actualStart: &freePtr
	actualLength: &freeCnt];


    bzero(&scsiReq, sizeof(IOSCSIRequest));

    scsiReq.target 		= [scsiTape target];
    scsiReq.lun 		= [scsiTape lun];

    [[scsiTape controller] getDMAAlignment:&dmaAlign];
    if(dmaAlign.readLength > 1) {
	scsiReq.maxTransfer = IOAlign(int, uiop->uio_iov->iov_len,
	    dmaAlign.readLength);

    } else {
	scsiReq.maxTransfer = uiop->uio_iov->iov_len;
    }

    scsiReq.timeoutLength = ST_IOTO_NORM;
    scsiReq.disconnect = 1;
    cdbp->c6s_lun = [scsiTape lun];

    if ([scsiTape isFixedBlock]) {
	/* c6s_len is BLOCK COUNT */
	length = howmany(uiop->uio_iov->iov_len, [scsiTape blockSize]);
	cdbp->c6s_opt = C6OPT_FIXED;

#ifdef	DEBUG
IOLog ("SCSI Tape read/write: set up for fixed block transfer\n");
#endif	DEBUG


    } else {
	length = uiop->uio_iov->iov_len;
	if(rw_flag == SR_DMA_RD)
	    if ([scsiTape suppressIllegalLength]) {
		cdbp->c6s_opt |= C6OPT_SIL;

#ifdef	DEBUG
IOLog ("SCSI Tape read: variable block read, suppress illegal len errs\n");
#endif	DEBUG

	    }
	    else {

#ifdef	DEBUG
IOLog ("SCSI Tape read: variable block read, allow illegal len errs\n");
#endif	DEBUG

	    }
    }
    assign_cdb_c6s_len (cdbp, length);

#ifdef DEBUG
IOLog ("Transfer Length is %d\n", length);
#endif DEBUG

    if(length > C6S_MAXLEN) {
	rtn = EINVAL;
	goto out;
    }

    if(rw_flag == SR_DMA_RD) {
	cdbp->c6s_opcode  = C6OP_READ;
	scsiReq.read = YES;
    }
    else {
	cdbp->c6s_opcode  = C6OP_WRITE;
	scsiReq.read = NO;

    }

    scsiReq.bytesTransferred = 0;

    /* Copy user data to kernel space if write. */
    if(rw_flag == SR_DMA_WR)
	if((rtn = copyin(uiop->uio_iov->iov_base, alignedBuf,
	    uiop->uio_iov->iov_len)))
		goto out;

    if ((scRet = [scsiTape executeRequest: &scsiReq
	buffer: alignedBuf
	client: IOVmTaskSelf()
	senseBuf: [scsiTape senseDataPtr]]) != SR_IOST_GOOD) {

	rtn = EIO;

#ifdef	DEBUG
IOLog ("st_rw: returned on failure from executeRequest\n");
IOLog ("st_rw:  ---- returned %d\n", scRet);
#endif	DEBUG


	goto out;
    }

    /* It worked. Copy data to user space if read. */
    if(scsiReq.bytesTransferred && (rw_flag == SR_DMA_RD)) {
	rtn = copyout(alignedBuf, uiop->uio_iov->iov_base,
	    scsiReq.bytesTransferred);

#ifdef DEBUG
IOLog ("return value from copyout is %d\n", rtn);
#endif DEBUG

    }

    if(scsiReq.driverStatus != SR_IOST_GOOD) {	// XXX Can this happen?
	rtn = EIO;
    }

out:

#ifdef DEBUG
IOLog ("SCSI st_rw transferred %d bytes out of %d\n",
    scsiReq.bytesTransferred, uiop->uio_iov->iov_len);
#endif DEBUG

    uiop->uio_resid = uiop->uio_iov->iov_len - scsiReq.bytesTransferred;
    IOFree (freePtr, freeCnt);
    IOSetUNIXError (rtn);
    return rtn;

} /* st_rw() */


/*
 * ioctl for SCSI Tape.
 * XXX sc_return_t to errno conversions could use more review.
 */
int
stioctl(dev_t dev,
    int cmd, 			/* MTIOCTOP, etc */
    caddr_t data, 		/* actually a ptr to mt_op or mtget, if used */
    int flag)			/* for historical reasons. Not used. */
{
    int				error = 0;
    int				unit = ST_UNIT(dev);
    id				scsiTape = stIdMap[unit];
    struct mtget		*mgp = (struct mtget *)data;
    struct esense_reply		*erp;
    sc_status_t			scsi_err;


    if (unit >= NST)
	return(ENXIO);
    switch (cmd) {
	case MTIOCTOP:			/* do tape op */

	    if ((scsi_err =
		[scsiTape executeMTOperation: (struct mtop *) data]) !=
		SR_IOST_GOOD) {

		if (scsi_err == SR_IOST_CMDREJ) {
		    error = EINVAL;
		} else {
		    error = EIO;
		}
	    }
	    break;

	case MTIOCGET:			/* get status */

	    erp = [scsiTape senseDataPtr];

	    /*
	     * If we just did a request sense command as part of
	     * error recovery, avoid doing another one and
	     * thus blowing away possible volatile status info.
	     */
	    if([scsiTape senseDataValid] == NO) {
		if((scsi_err = [scsiTape requestSense: erp]) != SR_IOST_GOOD) {
		    error = EIO;
		    break;
		}
	    }

	    /*
	     * [scsiTape senseDataPtr] now definitely contains valid
	     * sense data.
	     */
	    if(ST_EXABYTE(dev))
		mgp->mt_type = MT_ISEXB;
	    else
		mgp->mt_type = MT_ISGS;
	    mgp->mt_dsreg = ((u_char *)erp)[2];
	    mgp->mt_erreg = erp->er_addsensecode;
	    mgp->mt_ext_err0 = (((u_short)erp->er_stat_13) << 8) |
		((u_short)erp->er_stat_14);
	    mgp->mt_ext_err1 = (((u_short)erp->er_stat_15) << 8) |
		((u_short)erp->er_rsvd_16);

#if	__BIG_ENDIAN__
	    mgp->mt_resid = (u_int) erp->er_info;
#elif	__LITTLE_ENDIAN__
	    mgp->mt_resid = read_er_info_low_24();
	    mgp->mt_resid |= (u_int) erp->er_info3;
#endif

	    /* force actual request sense next time */
	    [scsiTape forceSenseDataInvalid];
	    break;

	case MTIOCFIXBLK:			/* set fixed block mode */
	    error = [scsiTape
		errnoFromReturn: [scsiTape setBlockSize: *(int *)data]];
	    break;

	case MTIOCVARBLK:			/* set variable block mode */
	    error = [scsiTape
		errnoFromReturn: [scsiTape setBlockSize: 0]];
	    break;

	case MTIOCINILL:			/* inhibit illegal length
	    					 *    errors on Read */
	    [scsiTape setSuppressIllegalLength: YES];
	    break;

	case MTIOCALILL:			/* allow illegal length
	    					 *    errors on Read */
	    [scsiTape setSuppressIllegalLength: NO];
	    break;

	case MTIOCMODSEL:			/* mode select */
	    error = 0;
	    if ([scsiTape stModeSelect: (struct modesel_parms *)data] !=
		SR_IOST_GOOD) {

		error = EIO;
		break;
	    }

	case MTIOCMODSEN:			/* mode sense */
	    error = 0;
	    if ([scsiTape stModeSense: (struct modesel_parms *)data] !=
		SR_IOST_GOOD) {

		error = EIO;
		break;
	    }

	case MTIOCSRQ:				/* I/O via scsi_req */
	    error = st_doiocsrq(scsiTape, (struct scsi_req *) data);
	    break;

	default:
	    error = EINVAL;			/* invalid argument */
	    break;
    }
    IOSetUNIXError (error);	/* XXX Probably not necessary */
    return error;
} /* stioctl() */



/*
 * Lifted directly from sg driver.
 *
 * Execute one scsi_req. Called from client's task context. Returns an errno.
 */

/*
 * FIXME - DMA to non-page-aligned user memory doesn't work. There
 * is data corruption on read operations; the corruption occurs on page
 * boundaries.
 */
#define FORCE_PAGE_ALIGN	1
#if	FORCE_PAGE_ALIGN
int stForcePageAlign = 1;
#endif	FORCE_PAGE_ALIGN

static int st_doiocsrq(id scsiTape, scsi_req_t *srp)
{
    void 		*alignedPtr = NULL;
    unsigned 		alignedLen = 0;
    void 		*freePtr;
    unsigned 		freeLen;
    BOOL 		didAlign = NO;
    vm_task_t		client = NULL;
    int			rtn = 0;
    IOSCSIRequest	scsiReq;
    sc_status_t		srtn;

    if(srp->sr_dma_max > [[scsiTape controller] maxTransfer]) {
	return EINVAL;
    }

    /* Get some well-aligned memory if necessary. By using
     * allocateBufferOfLength we guarantee that there is enough space
     * in the buffer we pass to the controller to handle
     * end-of-buffer alignment, although we won't copy more
     * than sr_dma_max to or from the  caller.
     */
    if(srp->sr_dma_max != 0) {

	IODMAAlignment dmaAlign;
	id controller = [scsiTape controller];
	unsigned alignLength;
	unsigned alignStart;

	/*
	 * Get appropriate alignment from controller.
	 */
	[[scsiTape controller] getDMAAlignment:&dmaAlign];
	if(srp->sr_dma_dir == SR_DMA_WR) {
	    alignLength = dmaAlign.writeLength;
	    alignStart  = dmaAlign.writeStart;
	}
	else {
	    alignLength = dmaAlign.readLength;
	    alignStart  = dmaAlign.readStart;
	}
#if	FORCE_PAGE_ALIGN
	if(stForcePageAlign) {
	    alignStart = PAGE_SIZE;
	}
#endif	FORCE_PAGE_ALIGN
	if( ( (alignStart > 1) &&
		!IOIsAligned(srp->sr_addr, alignStart)
	    ) ||
	    ( (alignLength > 1) &&
		!IOIsAligned(srp->sr_dma_max, alignLength)
	    ) ||
		/*
`		 * XXX Prevent DMA from user space for now, even if the
		 * buffer is well-aligned.  We need to wire down the user
		 * memory if we are going to DMA from it.
		 */
		YES
	    ) {

	    /*
	     * DMA from kernel memory, we allocate and copy.
	     */

	    didAlign = YES;
	    client = IOVmTaskSelf();

	    if(alignLength > 1) {
		alignedLen = IOAlign(unsigned,
		    srp->sr_dma_max,
		    alignLength);
		}
		else {
		    alignedLen = srp->sr_dma_max;
		}
		alignedPtr = [controller allocateBufferOfLength:
		    srp->sr_dma_max
		    actualStart:&freePtr
		    actualLength:&freeLen];
		if(srp->sr_dma_dir == SR_DMA_WR) {
		    rtn = copyin(srp->sr_addr, alignedPtr,
			srp->sr_dma_max);
		if(rtn) {
		    rtn = EFAULT;
		    goto err_exit;
		}
	    }
	}
	else {
	    /*
	     * Well-aligned buffer, DMA directly to/from user
	     * space.
	     */
	    alignedLen = srp->sr_dma_max;
	    alignedPtr = srp->sr_addr;
	    client = IOVmTaskCurrent();
	    didAlign = NO;
	}
    }

    /*
     * Generate a contemporary version of scsi_req.
     */
    bzero(&scsiReq, sizeof(scsiReq));
    scsiReq.target = [scsiTape target];
    scsiReq.lun    = [scsiTape lun];

    /*
     * Careful. this assumes that the old and new cdb structs are
     * equivalent...
     */
    scsiReq.cdb = srp->sr_cdb;
    scsiReq.read = (srp->sr_dma_dir == SR_DMA_RD) ? YES : NO;
    scsiReq.maxTransfer = alignedLen;
    scsiReq.timeoutLength = srp->sr_ioto;
    scsiReq.disconnect = 1;

    /*
     * Go for it.
     *
     * XXX Should use the SCSITape object's sense buffer, because
     * that's where MTIOCGET looks for valid sense data, and then
     * copy back the sense data to the old-style scsi_req's sense
     * buffer.
     */
    srtn = [scsiTape executeRequest:&scsiReq
	buffer : alignedPtr
	client : client
	senseBuf : &srp->sr_esense];

    /*
     * Copy status back to user. Note that if we got this far, we
     * return good status from the function; errors are in
     * srp->sr_io_status.
     */
    srp->sr_io_status = srtn;
    srp->sr_scsi_status = scsiReq.scsiStatus;
    srp->sr_dma_xfr = scsiReq.bytesTransferred;
    if(srp->sr_dma_xfr > srp->sr_dma_max) {
	srp->sr_dma_xfr = srp->sr_dma_max;
    }
    ns_time_to_timeval(scsiReq.totalTime, &srp->sr_exec_time);

    /*
     * Copy read data back to user if appropriate.
     */
    if((srp->sr_dma_dir == SR_DMA_RD) &&
	(scsiReq.bytesTransferred != 0) && didAlign) {

	rtn = copyout(alignedPtr,
	    srp->sr_addr,
	    srp->sr_dma_xfr);
    }
err_exit:
    if(didAlign) {
	IOFree(freePtr, freeLen);
    }
    return rtn;
}


/*
 * Supporting function for managing byte-order swapping.
 */
unsigned int
read_er_info_low_24(struct esense_reply *erp)
{
#if	__BIG_ENDIAN__
    return ((unsigned int) erp->er_info);
#elif	__LITTLE_ENDIAN__
    return (unsigned int)
	(erp->er_info2 << 16) + (erp->er_info1 << 8) + erp->er_info0;

#endif

}
