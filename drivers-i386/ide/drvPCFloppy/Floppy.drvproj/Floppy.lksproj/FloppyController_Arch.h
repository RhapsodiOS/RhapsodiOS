/*
 * FloppyController_Arch.h
 * Architecture-specific methods for FloppyController
 */

#import "FloppyController.h"

/*
 * Architecture-specific category for FloppyController
 * Contains platform-specific hardware access methods
 */
@interface FloppyController(Arch)

// Port I/O operations (inline or category methods)
- (void)outb:(unsigned int)port value:(unsigned char)value;
- (unsigned char)inb:(unsigned int)port;

// DMA controller operations
- (IOReturn)setupDMAChannel:(unsigned int)channel
                     address:(vm_address_t)addr
                      length:(unsigned int)length
                       write:(BOOL)isWrite;

// Interrupt handling
- (void)enableInterrupts;
- (void)disableInterrupts;

@end
