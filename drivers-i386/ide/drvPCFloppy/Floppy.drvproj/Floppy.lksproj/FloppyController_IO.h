/*
 * FloppyController_IO.h
 * I/O operation methods for FloppyController
 */

#import "FloppyController.h"

/*
 * I/O Operations category for FloppyController
 * Contains high-level I/O operations and transfer management
 */
@interface FloppyController(IO)

// High-level I/O operations
- (IOReturn)performRead:(unsigned int)drive
               cylinder:(unsigned int)cyl
                   head:(unsigned int)head
                 sector:(unsigned int)sec
                 buffer:(void *)buffer
                 length:(unsigned int)length
                 client:(vm_task_t)client;

- (IOReturn)performWrite:(unsigned int)drive
                cylinder:(unsigned int)cyl
                    head:(unsigned int)head
                  sector:(unsigned int)sec
                  buffer:(void *)buffer
                  length:(unsigned int)length
                  client:(vm_task_t)client;

// Transfer management
- (IOReturn)setupTransfer:(void *)buffer
                   length:(unsigned int)length
                    write:(BOOL)isWrite
                   client:(vm_task_t)client;

- (IOReturn)waitForTransferComplete;
- (IOReturn)abortTransfer;

// Error recovery
- (IOReturn)retryOperation;
- (IOReturn)recoverFromError:(IOReturn)error;

@end
