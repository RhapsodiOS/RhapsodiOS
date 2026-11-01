/*
 * InstallPPDev.m - Pre-Load tool: create /dev/ppN
 */

#import "IODeviceMaster.h"
#import <driverkit/IODevice.h>
#import <errno.h>
#import <libc.h>

#define PROGRAM_NAME "Error initializing parallel port driver"
#define PATH_NAME_SIZE 10
#define DEV_STRING "/dev/"

char path[PATH_NAME_SIZE];

int
main(int argc, char **argv)
{
    IOString		kind;
    IOObjectNumber	tag;
    int			major;
    unsigned int	count = 1;
    int			minor;
    IOReturn		ret;
    IODeviceMaster	*devMaster;
    unsigned int	instanceNum;

    if (strncmp(argv[argc - 1], "Instance=", 9) != 0) {
	printf("%s: can't find Instance number\n", PROGRAM_NAME);
	return -1;
    }

    instanceNum = atoi(argv[argc - 1] + 9);
    if (instanceNum > 9) {
	printf("%s: invalid instance number\n", PROGRAM_NAME);
	return -1;
    }

    bzero(path, PATH_NAME_SIZE);
    sprintf(path, "%s%s%d", DEV_STRING, "pp", instanceNum);

    devMaster = [IODeviceMaster new];

    ret = [devMaster lookUpByDeviceName:path + 5
	    objectNumber:&tag
	    deviceKind:&kind];
    if (ret != IO_R_SUCCESS) {
	printf("%s: couldn't find driver. Returned %d\n", PROGRAM_NAME, ret);
	return -1;
    }

    major = -1;
    ret = [devMaster getIntValues:&major
	    forParameter:"IOMajorDevice" objectNumber:tag
	    count:&count];
    if (ret != IO_R_SUCCESS) {
	printf("%s: couldn't get major number:  Returned %d.\n",
	    PROGRAM_NAME, ret);
	return -1;
    }

    minor = -1;
    ret = [devMaster getIntValues:&minor
	    forParameter:"IOMinorDevice" objectNumber:tag
	    count:&count];
    if (ret != IO_R_SUCCESS) {
	printf("%s: couldn't get minor dev.  Returned %d.\n",
	    PROGRAM_NAME, ret);
	return -1;
    }

    if (unlink(path)) {
	if (errno != ENOENT) {
	    printf("%s: could not delete old %s.  Errno is %d\n",
		PROGRAM_NAME, path, errno);
	    return -1;
	}
    }

    umask(0);
    if (mknod(path, 0x21b6, (major << 8) | minor)) {
	printf("%s: could not create %s.  Errno is %d\n",
	    PROGRAM_NAME, path, errno);
	return -1;
    }
    return 0;
}
