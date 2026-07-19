/*
 *      Copyright (c) 1994 NeXT Computer, Inc.  All rights reserved.
 *
 * PreLoad command for SCSI Tape.   Removes old SCSI Tape device nodes.
 *
 * HISTORY
 * 1-Apr-94    Phillip Dibner at NeXT
 *      Created.
 */

#import <errno.h>
#import <libc.h>
#import "SCSITapeTypes.h"

#define PATH_NAME_SIZE 10
#define DEV_STRING "/dev/"
#define ST_PRELOAD_ERR_STRING "SCSI Tape PreLoad"
#define NTAPE_NAMES 4
#define NST 4 /* XXX This is redundant, but avoids compilation errors */

char path [PATH_NAME_SIZE];
char *scsiTapeNames[] = {"rst", "nrst", "rxt", "nrxt"};
int scsiTapeDevFlags[] = {0, 1, 2, 3}; /* bit 0 = no rewind, bit 1 = Exabyte */

int
main(int argc, char **argv)
{
    int				iUnit, iRet = 0;
    int				i;

    for (iUnit = 0; iUnit < NST; iUnit ++) {
	bzero (path, PATH_NAME_SIZE);
	sprintf (path, "%s%s%d", DEV_STRING, "st", iUnit);

	/*
	 * Remove old devs and create new ones for this unit.
	 */
	for (i = 0; i < NTAPE_NAMES; i++) {

	    bzero (path, PATH_NAME_SIZE);
	    sprintf (path, "%s%s%d", DEV_STRING, scsiTapeNames [i], iUnit);

	    if (unlink (path)) {
		if (errno != ENOENT) {
		    printf ("%s: could not delete old %s.  Errno is %d\n",
			ST_PRELOAD_ERR_STRING, path, errno);
		    iRet = -1;
		}
	    }
	}
    } /* for iUnit */
    return iRet;
}
