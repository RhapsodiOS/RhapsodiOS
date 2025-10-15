/*
 * IOFloppyDisk_Parameters.m
 * Parameter and configuration implementation for IOFloppyDisk
 */

#import "IOFloppyDisk_Parameters.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IODevice.h>

// Disk value structure for returning geometry and status
typedef struct {
    unsigned int blockSize;
    unsigned int capacity;
    unsigned int cylinders;
    unsigned int heads;
    unsigned int sectorsPerTrack;
    BOOL isWriteProtected;
    BOOL isRemovable;
    BOOL isFormatted;
} DiskValues;

@implementation IOFloppyDisk(Parameters)

- (IOReturn)getIntValuesForParameter:(IOParameterName)param
                              count:(unsigned int *)count
                             values:(unsigned int *)values
{
    if (count == NULL) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Parameters): getIntValuesForParameter: %s\n", param);

    [_lock lock];

    // Handle common disk parameters
    if (strcmp(param, "Block Size") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _blockSize;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Block Size = %d\n", _blockSize);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Disk Capacity") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _capacity;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Disk Capacity = %d blocks\n", _capacity);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Cylinders") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _cylinders;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Cylinders = %d\n", _cylinders);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Heads") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _heads;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Heads = %d\n", _heads);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Sectors Per Track") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _sectorsPerTrack;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Sectors Per Track = %d\n", _sectorsPerTrack);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Removable") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _isRemovable ? 1 : 0;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Removable = %d\n", _isRemovable);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "Write Protected") == 0) {
        if (values != NULL && *count >= 1) {
            values[0] = _isWriteProtected ? 1 : 0;
            *count = 1;
            [_lock unlock];
            IOLog("IOFloppyDisk(Parameters): Write Protected = %d\n", _isWriteProtected);
            return IO_R_SUCCESS;
        }
        *count = 1;
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): Unsupported parameter: %s\n", param);
    return IO_R_UNSUPPORTED;
}

- (IOReturn)forParameter:(IOParameterName)param
                   count:(unsigned int *)count
{
    if (count == NULL) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Parameters): forParameter: %s\n", param);

    // Return the count of values for this parameter
    if (strcmp(param, "Block Size") == 0 ||
        strcmp(param, "Disk Capacity") == 0 ||
        strcmp(param, "Cylinders") == 0 ||
        strcmp(param, "Heads") == 0 ||
        strcmp(param, "Sectors Per Track") == 0 ||
        strcmp(param, "Removable") == 0 ||
        strcmp(param, "Write Protected") == 0) {
        *count = 1;
        return IO_R_SUCCESS;
    }

    *count = 0;
    return IO_R_UNSUPPORTED;
}

- (unsigned int)diskToReturnValues:(void *)valueStruct
{
    DiskValues *values;

    if (valueStruct == NULL) {
        IOLog("IOFloppyDisk(Parameters): diskToReturnValues called with NULL\n");
        return 0;
    }

    values = (DiskValues *)valueStruct;

    [_lock lock];

    // Fill in disk values
    values->blockSize = _blockSize;
    values->capacity = _capacity;
    values->cylinders = _cylinders;
    values->heads = _heads;
    values->sectorsPerTrack = _sectorsPerTrack;
    values->isWriteProtected = _isWriteProtected;
    values->isRemovable = _isRemovable;
    values->isFormatted = _isFormatted;

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): diskToReturnValues - capacity=%d blocks\n", _capacity);

    return _capacity;
}

- (void *)diskToReturnValuesPtr
{
    DiskValues *values;

    // Allocate disk values structure
    values = (DiskValues *)IOMalloc(sizeof(DiskValues));
    if (values == NULL) {
        IOLog("IOFloppyDisk(Parameters): Failed to allocate disk values\n");
        return NULL;
    }

    [_lock lock];

    // Fill in disk values
    values->blockSize = _blockSize;
    values->capacity = _capacity;
    values->cylinders = _cylinders;
    values->heads = _heads;
    values->sectorsPerTrack = _sectorsPerTrack;
    values->isWriteProtected = _isWriteProtected;
    values->isRemovable = _isRemovable;
    values->isFormatted = _isFormatted;

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): diskToReturnValuesPtr = %p\n", values);

    return values;
}

- (unsigned int)sizeList
{
    unsigned int capacity;

    [_lock lock];
    capacity = _capacity;
    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): sizeList = %d blocks\n", capacity);

    return capacity;
}

- (unsigned int)sizeListFromCapacities
{
    unsigned int size;

    [_lock lock];
    size = _capacity * _blockSize;
    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): sizeListFromCapacities = %d bytes\n", size);

    return size;
}

- (unsigned int)capacityFromSize
{
    unsigned int capacity;

    [_lock lock];
    capacity = _capacity;
    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): capacityFromSize = %d blocks\n", capacity);

    return capacity;
}

- (BOOL)isWriteProtected
{
    BOOL result;

    [_lock lock];
    result = _isWriteProtected;
    [_lock unlock];

    return result;
}

- (IOReturn)setWriteProtected:(BOOL)protect
{
    [_lock lock];
    _isWriteProtected = protect;
    [_lock unlock];

    if (protect) {
        IOLog("IOFloppyDisk(Parameters): Write protection enabled\n");
    } else {
        IOLog("IOFloppyDisk(Parameters): Write protection disabled\n");
    }

    return IO_R_SUCCESS;
}

- (BOOL)isPhysical
{
    BOOL result;

    [_lock lock];
    result = _isPhysical;
    [_lock unlock];

    return result;
}

- (void)setPhysical:(BOOL)physical
{
    [_lock lock];
    _isPhysical = physical;
    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): Physical disk = %s\n", physical ? "YES" : "NO");
}

// Additional parameter methods

- (IOReturn)setParameter:(IOParameterName)param
                  values:(unsigned int *)values
                   count:(unsigned int)count
{
    if (param == NULL || values == NULL || count == 0) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Parameters): setParameter: %s count:%d\n", param, count);

    [_lock lock];

    // Handle writable parameters
    if (strcmp(param, "Write Protected") == 0 && count >= 1) {
        _isWriteProtected = (values[0] != 0);
        [_lock unlock];
        IOLog("IOFloppyDisk(Parameters): Set Write Protected = %d\n", _isWriteProtected);
        return IO_R_SUCCESS;
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): Parameter %s is read-only or unsupported\n", param);
    return IO_R_UNSUPPORTED;
}

- (IOReturn)getParameterCount:(unsigned int *)count
{
    if (count == NULL) {
        return IO_R_INVALID_ARG;
    }

    // Return the total number of parameters we support
    *count = 7;  // Block Size, Capacity, Cylinders, Heads, SPT, Removable, Write Protected

    IOLog("IOFloppyDisk(Parameters): Total parameter count = %d\n", *count);

    return IO_R_SUCCESS;
}

- (IOReturn)getParameterNames:(IOParameterName *)names
                        count:(unsigned int)count
{
    if (names == NULL) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Parameters): getParameterNames count:%d\n", count);

    // Fill in parameter names
    if (count > 0) names[0] = "Block Size";
    if (count > 1) names[1] = "Disk Capacity";
    if (count > 2) names[2] = "Cylinders";
    if (count > 3) names[3] = "Heads";
    if (count > 4) names[4] = "Sectors Per Track";
    if (count > 5) names[5] = "Removable";
    if (count > 6) names[6] = "Write Protected";

    return IO_R_SUCCESS;
}

- (IOReturn)getDiskGeometry:(unsigned int *)cylinders
                      heads:(unsigned int *)heads
            sectorsPerTrack:(unsigned int *)spt
                  blockSize:(unsigned int *)blockSize
{
    [_lock lock];

    if (cylinders != NULL) {
        *cylinders = _cylinders;
    }

    if (heads != NULL) {
        *heads = _heads;
    }

    if (spt != NULL) {
        *spt = _sectorsPerTrack;
    }

    if (blockSize != NULL) {
        *blockSize = _blockSize;
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): Geometry - C:%d H:%d S:%d BS:%d\n",
          _cylinders, _heads, _sectorsPerTrack, _blockSize);

    return IO_R_SUCCESS;
}

- (IOReturn)setDiskGeometry:(unsigned int)cylinders
                      heads:(unsigned int)heads
            sectorsPerTrack:(unsigned int)spt
                  blockSize:(unsigned int)blockSize
{
    // Validate geometry
    if (cylinders == 0 || heads == 0 || spt == 0 || blockSize == 0) {
        IOLog("IOFloppyDisk(Parameters): Invalid geometry parameters\n");
        return IO_R_INVALID_ARG;
    }

    // Validate block size (must be power of 2)
    if ((blockSize & (blockSize - 1)) != 0) {
        IOLog("IOFloppyDisk(Parameters): Block size must be power of 2\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    _cylinders = cylinders;
    _heads = heads;
    _sectorsPerTrack = spt;
    _blockSize = blockSize;
    _capacity = cylinders * heads * spt;

    [_lock unlock];

    IOLog("IOFloppyDisk(Parameters): Set geometry - C:%d H:%d S:%d BS:%d (capacity:%d)\n",
          cylinders, heads, spt, blockSize, _capacity);

    return IO_R_SUCCESS;
}

@end
