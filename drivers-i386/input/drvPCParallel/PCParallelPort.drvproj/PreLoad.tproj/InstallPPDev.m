/*
 * InstallPPDev.m - Install parallel port device node
 *
 * This tool is called during driver load to create the device node
 * in /dev/ and set appropriate permissions.
 */

#import "IODeviceMaster.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <errno.h>
#import <sys/stat.h>

#define PROGRAM_NAME "Error initializing parallel port driver"
#define DEVICE_NAME_FORMAT "ParallelPort%d"

// Global path buffer
static char path[10];

int main(int argc, char *argv[])
{
    unsigned int instanceNum;
    char deviceName[80];
    IODeviceMaster *deviceMaster;
    int objectNumber;
    const char *deviceKind;
    int majorDevNum;
    unsigned int minorDevNum;
    unsigned int count;
    kern_return_t result;

    // Check last argument for "Instance=N"
    if (argc < 2 || strncmp(argv[argc - 1], "Instance=", 9) != 0) {
        printf("%s: can't find Instance number\n", PROGRAM_NAME);
        return 0xffffffff;
    }

    // Parse the instance number
    instanceNum = atoi(argv[argc - 1] + 9);

    // Validate instance number
    if (instanceNum >= 10) {
        printf("%s: invalid instance number\n", PROGRAM_NAME);
        return 0xffffffff;
    }

    // Build device path
    bzero(path, 10);
    sprintf(path, "%s%s%d", "/dev/", "pp", instanceNum);

    // Create device master
    deviceMaster = [IODeviceMaster new];

    // Look up the parallel port device by name
    sprintf(deviceName, DEVICE_NAME_FORMAT, instanceNum);
    result = [deviceMaster lookUpByDeviceName:deviceName
                                 objectNumber:&objectNumber
                                   deviceKind:&deviceKind];
    if (result != 0) {
        printf("%s: couldn't find driver. Returned %d\n", PROGRAM_NAME, result);
        return 0xffffffff;
    }

    // Get major device number
    majorDevNum = -1;
    count = 1;
    result = [deviceMaster getIntValues:(unsigned int *)&majorDevNum
                           forParameter:"IOMajorDevice"
                           objectNumber:objectNumber
                                  count:&count];
    if (result != 0) {
        printf("%s: couldn't get major number:  Returned %d.\n", PROGRAM_NAME, result);
        return 0xffffffff;
    }

    // Get minor device number
    minorDevNum = 0xffffffff;
    count = 1;
    result = [deviceMaster getIntValues:&minorDevNum
                           forParameter:"IOMinorDevice"
                           objectNumber:objectNumber
                                  count:&count];
    if (result != 0) {
        printf("%s: couldn't get minor dev.  Returned %d.\n", PROGRAM_NAME, result);
        return 0xffffffff;
    }

    // Remove old device node (allow ENOENT error)
    result = unlink(path);
    if (result != 0 && errno != 2) {  // errno 2 = ENOENT
        printf("%s: could not delete old %s.  Errno is %d\n", PROGRAM_NAME, path, errno);
        return 0xffffffff;
    }

    // Set umask to allow full permissions
    umask(0);

    // Create character device node
    // 0x21b6 = S_IFCHR (0x2000) | 0666 (0x1b6)
    // Manual makedev: major << 8 | minor
    if (mknod(path, 0x21b6, majorDevNum << 8 | minorDevNum) != 0) {
        printf("%s: could not create %s.  Errno is %d\n", PROGRAM_NAME, path, errno);
        return 0xffffffff;
    }

    return 0;
}
