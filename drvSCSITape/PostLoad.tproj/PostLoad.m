/*
 *      Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * Post-Load command for SCSITape.   Creates device nodes /dev/rst<n>,
 * /dev/nrst<n>, /dev/rxt<n>, and /dev/nrxt<n> for up to 4 SCSI tape
 * units.
 *
 * HISTORY
 * 20-Apr-93    Phillip Dibner at NeXT
 *      Created.
 */

#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import "SCSITapeTypes.h"
#import <errno.h>
#import <libc.h>


#define PATH_NAME_SIZE 10
#define DEV_STRING "/dev/"
#define INSTANCE_STRING "Instance="
#define ST_INIT_ERR_STRING "Error initializing SCSI Tape driver"
#define NTAPE_NAMES 4

#define DEV_MOD 020666
#define DEV_UMASK 0

char path [PATH_NAME_SIZE];
char *scsiTapeNames[] = {"rst", "nrst", "rxt", "nrxt"};
int scsiTapeDevFlags[] = {0, 1, 2, 3}; /* bit 0 = no rewind, bit 1 = Exabyte */

int
main(int argc, char **argv)
{
    IOReturn			ret = IO_R_INVALID;
    IOObjectNumber		tag;
    IOString			kind;
    int				major, minor, iUnit, iRet = 0;
    unsigned int		count = 1;
    IODeviceMaster		*devMaster;
    int				i;

    devMaster = [IODeviceMaster new];

    for (iUnit = 0; iUnit < NST; iUnit ++) {
	bzero (path, PATH_NAME_SIZE);
	sprintf (path, "%s%s%d", DEV_STRING, "st", iUnit);

	/*
	 * Find this instance of the SCSI Tape driver
	 */

	ret = [devMaster lookUpByDeviceName: path + strlen (DEV_STRING)
	    objectNumber: &tag
	    deviceKind: &kind];

#ifdef DEBUG
printf (" unit %d, obj name %s\n", iUnit, path);
printf (" ret = %d\n", ret);
#endif DEBUG

	/*
	 * Special work to do for the first SCSITape object
	 */
	if (iUnit == 0) {

	    /*
	     * If we couldn't find the first one, we will return failure.
	     */
	    if (ret != IO_R_SUCCESS) {
		printf ("%s: couldn't find driver. Returned %d\n",
		    ST_INIT_ERR_STRING, ret);
		iRet = -1;
	    }

	    /*
	     * Query the object for its major device number
	     */
	    major = -1;
	    ret = [devMaster getIntValues:&major
		forParameter:"IOMajorDevice" objectNumber:tag
		count:&count];
	    if (ret != IO_R_SUCCESS) {
		printf ("%s: couldn't get major number:  Returned %d.\n",
		    ST_INIT_ERR_STRING, ret);
		iRet = -1;
	    }
	}

	/*
	 * Remove old devs and create new ones for this unit.
	 */
	for (i = 0; i < NTAPE_NAMES; i++) {

	    bzero (path, PATH_NAME_SIZE);
	    sprintf (path, "%s%s%d", DEV_STRING, scsiTapeNames [i], iUnit);

	    if (unlink (path)) {
		if (errno != ENOENT) {
		    printf ("%s: could not delete old %s.  Errno is %d\n",
			ST_INIT_ERR_STRING, path, errno);
		    iRet = -1;
		}
	    }


	    /*
	     * If we found this object, create new device nodes
	     */
	    if (ret == IO_R_SUCCESS) {
		minor = (iUnit << 3) | scsiTapeDevFlags [i];

		umask (DEV_UMASK);
		if (mknod(path, DEV_MOD, (major << 8) | minor)) {
		    printf ("%s: could not create %s.  Errno is %d\n",
			ST_INIT_ERR_STRING, path, errno);
		    iRet = -1;
		}
	    }
	}
    } /* for iUnit */
    return iRet;
}
