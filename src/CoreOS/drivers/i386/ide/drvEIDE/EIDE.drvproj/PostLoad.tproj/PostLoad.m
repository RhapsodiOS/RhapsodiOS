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
 * Post-Load command for ATA disks. Creates device nodes /dev/hd[0-31][a-h]
 * and /dev/rhd[0-31][a-h].
 *
 * HISTORY
 * 30-Sep-94    Rakesh Dubey at NeXT
 *      Created from SCSI tape source. 
 */

#import <streams/streams.h>
#import <errno.h>
#import <libc.h>
#import <sys/stat.h>

#define PATH_NAME_SIZE 			16
#define DEV_STRING 			"/dev/"
#define IDE_INIT_ERR_STRING 		"Error initializing IDE driver"

#define DEV_MOD_CHAR 			020640
#define DEV_MOD_BLOCK 			060640

#define DEV_UMASK 			0

#define NIDE_PARTITIONS 		8

#define NIDE_DEVICES			32

#define IDE_BLOCK_MAJOR			3
#define IDE_CHARACTER_MAJOR		15

static int makeNode(char *deviceName, int iUnit, int major, int num,
			unsigned short mode);

int main(int argc, char **argv)
{
    int				i, iUnit, iRet;

    iRet = 0;

    for (iUnit = 0; iUnit < NIDE_DEVICES; iUnit ++) {
	for (i = 0; i < NIDE_PARTITIONS; i++) {
	    if (makeNode("hd", iUnit, IDE_BLOCK_MAJOR, i,
			 DEV_MOD_BLOCK) != 0)
		iRet = -1;
	    if (makeNode("rhd", iUnit, IDE_CHARACTER_MAJOR, i,
			 DEV_MOD_CHAR) != 0)
		iRet = -1;
	}
    }
    
    exit(iRet);
}

static int makeNode(char *deviceName, int iUnit, int major, int num,
			unsigned short mode)
{
    struct stat status;
    dev_t device;
    int minor;
    char path[PATH_NAME_SIZE];
    
#ifdef notdef
printf ("makeNode %s, iUnit %d num %d\n", deviceName, iUnit, num);
#endif notdef

    bzero(path, PATH_NAME_SIZE);
    sprintf(path, "%s%s%d%c", DEV_STRING, deviceName, iUnit, num + 'a');

    minor = iUnit * NIDE_PARTITIONS + num;
    device = (major << 8) | minor;

    if (lstat(path, &status) == 0) {
	if ((status.st_mode & S_IFMT) == (mode & S_IFMT) &&
	    (status.st_mode & 07777) == (mode & 07777) &&
	    status.st_rdev == device)
	    return 0;
	if (unlink(path)) {
	    printf("%s: could not delete old %s.  Errno is %d\n",
		   IDE_INIT_ERR_STRING, path, errno);
	    return -1;
	}

    } else if (errno != ENOENT) {
	printf("%s: could not inspect %s.  Errno is %d\n",
	       IDE_INIT_ERR_STRING, path, errno);
	return -1;
    }

    umask(DEV_UMASK);
    if (mknod(path, mode, device)) {
	printf("%s: could not create %s.  Errno is %d\n",
	    IDE_INIT_ERR_STRING, path, errno);
	return -1;
    }

    return 0;
}
