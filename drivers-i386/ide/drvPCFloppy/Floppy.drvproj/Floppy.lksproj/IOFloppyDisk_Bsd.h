/*
 * IOFloppyDisk_Bsd.h
 * BSD compatibility methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * BSD compatibility category for IOFloppyDisk
 * Contains BSD-style device operations
 */
@interface IOFloppyDisk(Bsd)

// BSD device entry points
- (IOReturn)bsdOpen:(int)flags;
- (IOReturn)bsdClose:(int)flags;
- (IOReturn)bsdIoctl:(unsigned int)cmd arg:(void *)arg;

// BSD-style I/O
- (IOReturn)bsdReadAt:(unsigned int)offset
               length:(unsigned int)length
               buffer:(void *)buffer
               client:(vm_task_t)client;

- (IOReturn)bsdWriteAt:(unsigned int)offset
                length:(unsigned int)length
                buffer:(void *)buffer
                client:(vm_task_t)client;

@end
