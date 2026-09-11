/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * Copyright 1997-1998 by Apple Computer, Inc., All rights reserved.
 * Copyright 1994-1997 NeXT Software, Inc., All rights reserved.
 *
 * IdeKern.m - UNIX front end for kernel IDE Disk driver.
 *
 * HISTORY 
 * 07-Jul-1994	 Rakesh Dubey at NeXT
 *	Created from original driver written by David Somayajulu.
 * 19-Jun-97	Dieter Siegmund at Apple
 *	Updated to use the BSD4.4 ioctl interface that copies user
 *	buffer in/out of kernel automatically.
 */
 
#if (IO_DRIVERKIT_VERSION == 400)
#define _POSIX_SOURCE
#endif

/*
 * Note that this file builds with KERNEL_PRIVATE and !MACH_USER_API.
 */
#import <sys/types.h>
#import <sys/ucred.h>
#import <driverkit/generalFuncs.h>
#import "IdeCnt.h"
#import "IdeDiskInternal.h"
#import "IdeDisk.h"
#import <sys/errno.h>
#import <sys/proc.h>
#import <sys/systm.h>
#import "IdeKernel.h"
#import "EIDEIoctlValidation.h"

IONamedValue iderValues[] = {

	{IDER_SUCCESS,		"Success"			},
	{IDER_TIMEOUT,		"Timeout occured"		},
	{IDER_MEMALLOC,		"Couldn't allocate memory"	},
	{IDER_MEMFAIL,		"Memory transfer error"		},
	{IDER_REJECT,		"Bad field in ide_ioreq"	},
	{IDER_BADDRV,		"Drive not present"		},
	{IDER_CMD_ERROR,	"Command Failed"		},
	{IDER_VOLUNAVAIL,	"Requested Volume not available"},
	{IDER_SPURIOUS,		"Spurious Interrupt"		},
	{IDER_CNTRL_REJECT,	"Controller Reject" 		},
	{0,			NULL				},
};

/*
 * Handle the diagnostic requests specific to the legacy EIDE transport.
 * Generic disk ioctls are handled by the shared ATA hd registry.
 */
__private_extern__ int
IdeDiskTransportIoctl(id disk, dev_t dev, unsigned int cmd, caddr_t data,
		      int flag, struct proc *proc)
{
    ideIoReq_t *ideIoReq;
    int error;
    void *userPtr;
    BOOL wrFlag = NO;
    BOOL readFlag = NO;
    unsigned bSize = 0;
    unsigned allocationBytes = 0;
    unsigned copyBytes = 0;
    unsigned requestedBlocks = 0;
    unsigned char *alignedPtr;

    (void)dev;
    (void)flag;
    if (disk == nil)
	return (ENXIO);

    switch (cmd) {
      case IDEDIOCREQ:

	/*
	 * Perform specified I/O.
	 */
	ideIoReq = (ideIoReq_t *)data;
	if (ideIoReq->cmd != IDE_IDENTIFY_DRIVE) {
	    if (proc == NULL)
		return (EPERM);
	    error = suser(proc->p_ucred, &proc->p_acflag);
	    if (error)
		return (error);
	}

	bSize = [disk blockSize];
	error = EIDEIoctlPrepareTransfer(ideIoReq->cmd, ideIoReq->block,
		ideIoReq->blkcnt, bSize, [disk diskSize],
		&allocationBytes);
	if (error)
	    return (error);

	if ((ideIoReq->cmd == IDE_WRITE_DMA) ||
	    (ideIoReq->cmd == IDE_READ_DMA)) {
	    if ([[disk cntrlr] isDmaSupported:[disk driveNum]] != TRUE)
		return (EINVAL);
	}
	if (ideIoReq->cmd == IDE_IDENTIFY_DRIVE) {
	    ideIoReq->blkcnt = 1;
	    bSize = EIDE_IOCTL_IDENTIFY_BYTES;
	}
	requestedBlocks = ideIoReq->blkcnt;

	userPtr = (void *)ideIoReq->addr;
	alignedPtr = NULL;
	wrFlag = ((ideIoReq->cmd == IDE_WRITE) ||
		  (ideIoReq->cmd == IDE_WRITE_MULTIPLE) ||
		  (ideIoReq->cmd == IDE_WRITE_DMA));
	readFlag = ((ideIoReq->cmd == IDE_READ) ||
		    (ideIoReq->cmd == IDE_READ_MULTIPLE) ||
		    (ideIoReq->cmd == IDE_READ_DMA) ||
		    (ideIoReq->cmd == IDE_IDENTIFY_DRIVE));
	if (allocationBytes != 0) {
	    alignedPtr = (unsigned char *)IOMalloc(allocationBytes);
	    if (alignedPtr == NULL) {
		ideIoReq->status = IDER_MEMALLOC;
		return (ENOMEM);
	    }
	    if (wrFlag) {
		error = copyin(ideIoReq->addr, alignedPtr, allocationBytes);
		if (error) {
		    ideIoReq->status = IDER_MEMFAIL;
		    IOFree(alignedPtr, allocationBytes);
		    return (error);
		}
	    }
	    ideIoReq->addr = (caddr_t)alignedPtr;
	    ideIoReq->map = (struct vm_map *)IOVmTaskSelf();
	}

	[disk ideXfrIoReq:ideIoReq];
	if (allocationBytes != 0)
	    ideIoReq->addr = userPtr;
	error = EIDEIoctlValidateCompletion(ideIoReq->cmd, requestedBlocks,
		ideIoReq->blocks_xfered, bSize, &copyBytes);
	if (error) {
	    ideIoReq->status = IDER_MEMFAIL;
	    if (alignedPtr != NULL)
		IOFree(alignedPtr, allocationBytes);
	    return (error);
	}
	if (readFlag && copyBytes != 0) {
	    error = copyout(alignedPtr, userPtr, copyBytes);
	    if (error)
		ideIoReq->status = IDER_MEMFAIL;
	}
	if (alignedPtr != NULL)
	    IOFree(alignedPtr, allocationBytes);
	if (error)
	    return (error);
	break;

      case IDEDIOCINFO:
	*(ideDriveInfo_t *)data = (ideDriveInfo_t)[disk ideGetDriveInfo];
	break;

      default:
	return (EINVAL);
    }

    return (0);
}

/* end of IdeKern.m */
