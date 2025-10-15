/*
 * IOFloppyDisk_Bsd.m
 * BSD compatibility implementation for IOFloppyDisk
 */

#import "IOFloppyDisk_Bsd.h"
#import <driverkit/generalFuncs.h>
#import <bsd/sys/errno.h>
#import <bsd/sys/ioctl.h>
#import <bsd/sys/disk.h>

@implementation IOFloppyDisk(Bsd)

- (IOReturn)bsdOpen:(int)flags
{
    IOReturn status;

    IOLog("IOFloppyDisk(Bsd): Opening device with flags 0x%x\n", flags);

    // Check if write access is requested and disk is write protected
    if ((flags & O_WRONLY) || (flags & O_RDWR)) {
        if ([self isWriteProtected]) {
            IOLog("IOFloppyDisk(Bsd): Open failed - disk is write protected\n");
            return IO_R_NOT_WRITABLE;
        }
    }

    // Open the block device
    status = [self setBlockDeviceOpen:YES];
    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Bsd): Failed to open block device\n");
        return status;
    }

    IOLog("IOFloppyDisk(Bsd): Device opened successfully\n");
    return IO_R_SUCCESS;
}

- (IOReturn)bsdClose:(int)flags
{
    IOReturn status;

    IOLog("IOFloppyDisk(Bsd): Closing device with flags 0x%x\n", flags);

    // Close the block device
    status = [self setBlockDeviceOpen:NO];
    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Bsd): Failed to close block device\n");
        return status;
    }

    IOLog("IOFloppyDisk(Bsd): Device closed successfully\n");
    return IO_R_SUCCESS;
}

- (IOReturn)bsdIoctl:(unsigned int)cmd arg:(void *)arg
{
    IOReturn status = IO_R_UNSUPPORTED;

    IOLog("IOFloppyDisk(Bsd): ioctl command 0x%x\n", cmd);

    switch (cmd) {
        case DKIOCGETBLOCKSIZE:
            // Get block size
            if (arg != NULL) {
                *(unsigned int *)arg = [self blockSize];
                status = IO_R_SUCCESS;
                IOLog("IOFloppyDisk(Bsd): DKIOCGETBLOCKSIZE = %d\n", [self blockSize]);
            } else {
                status = IO_R_INVALID_ARG;
            }
            break;

        case DKIOCGETBLOCKCOUNT:
            // Get block count
            if (arg != NULL) {
                *(unsigned int *)arg = [self diskSize];
                status = IO_R_SUCCESS;
                IOLog("IOFloppyDisk(Bsd): DKIOCGETBLOCKCOUNT = %d\n", [self diskSize]);
            } else {
                status = IO_R_INVALID_ARG;
            }
            break;

        case DKIOCEJECT:
            // Eject disk
            status = [self ejectMedia];
            IOLog("IOFloppyDisk(Bsd): DKIOCEJECT status = 0x%x\n", status);
            break;

        case DKIOCISWRITABLE:
            // Check if disk is writable
            if (arg != NULL) {
                *(int *)arg = [self isWriteProtected] ? 0 : 1;
                status = IO_R_SUCCESS;
                IOLog("IOFloppyDisk(Bsd): DKIOCISWRITABLE = %d\n",
                      [self isWriteProtected] ? 0 : 1);
            } else {
                status = IO_R_INVALID_ARG;
            }
            break;

        case DKIOCFORMAT:
            // Format disk
            status = [self formatMedia];
            IOLog("IOFloppyDisk(Bsd): DKIOCFORMAT status = 0x%x\n", status);
            break;

        default:
            IOLog("IOFloppyDisk(Bsd): Unsupported ioctl command 0x%x\n", cmd);
            status = IO_R_UNSUPPORTED;
            break;
    }

    return status;
}

- (IOReturn)bsdReadAt:(unsigned int)offset
               length:(unsigned int)length
               buffer:(void *)buffer
               client:(vm_task_t)client
{
    unsigned int actualLength;
    IOReturn status;

    IOLog("IOFloppyDisk(Bsd): Read at offset %d, length %d\n", offset, length);

    status = [self readAt:offset
                   length:length
                   buffer:buffer
             actualLength:&actualLength
                   client:client];

    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Bsd): Read failed with status 0x%x\n", status);
    } else {
        IOLog("IOFloppyDisk(Bsd): Read %d bytes successfully\n", actualLength);
    }

    return status;
}

- (IOReturn)bsdWriteAt:(unsigned int)offset
                length:(unsigned int)length
                buffer:(void *)buffer
                client:(vm_task_t)client
{
    unsigned int actualLength;
    IOReturn status;

    IOLog("IOFloppyDisk(Bsd): Write at offset %d, length %d\n", offset, length);

    status = [self writeAt:offset
                    length:length
                    buffer:buffer
              actualLength:&actualLength
                    client:client];

    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Bsd): Write failed with status 0x%x\n", status);
    } else {
        IOLog("IOFloppyDisk(Bsd): Wrote %d bytes successfully\n", actualLength);
    }

    return status;
}

@end
