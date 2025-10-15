/*
 * IOFloppyDisk_Parameters.h
 * Parameter and configuration methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * Parameters category for IOFloppyDisk
 * Contains parameter accessors and configuration methods
 */
@interface IOFloppyDisk(Parameters)

// Parameter getters
- (IOReturn)getIntValuesForParameter:(IOParameterName)param
                              count:(unsigned int *)count
                             values:(unsigned int *)values;

- (IOReturn)forParameter:(IOParameterName)param
                   count:(unsigned int *)count;

// Disk return values
- (unsigned int)diskToReturnValues:(void *)valueStruct;
- (void *)diskToReturnValuesPtr;

// Size list operations
- (unsigned int)sizeList;
- (unsigned int)sizeListFromCapacities;
- (unsigned int)capacityFromSize;

// Write protected status
- (BOOL)isWriteProtected;
- (IOReturn)setWriteProtected:(BOOL)protect;

// Physical/logical disk methods
- (BOOL)isPhysical;
- (void)setPhysical:(BOOL)physical;

// Additional parameter methods
- (IOReturn)setParameter:(IOParameterName)param
                  values:(unsigned int *)values
                   count:(unsigned int)count;

- (IOReturn)getParameterCount:(unsigned int *)count;

- (IOReturn)getParameterNames:(IOParameterName *)names
                        count:(unsigned int)count;

- (IOReturn)getDiskGeometry:(unsigned int *)cylinders
                      heads:(unsigned int *)heads
            sectorsPerTrack:(unsigned int *)spt
                  blockSize:(unsigned int *)blockSize;

- (IOReturn)setDiskGeometry:(unsigned int)cylinders
                      heads:(unsigned int)heads
            sectorsPerTrack:(unsigned int)spt
                  blockSize:(unsigned int)blockSize;

@end
