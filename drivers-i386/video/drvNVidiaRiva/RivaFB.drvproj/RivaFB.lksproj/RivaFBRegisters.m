/*
 * RivaFBRegisters.m -- Register access methods
 * NOTE: This is a stub implementation
 */

#import "RivaFB.h"

@implementation RivaFB (Registers)

- (CARD32) readReg: (CARD32) offset
{
    return rivaReadReg(regBase, offset);
}

- (void) writeReg: (CARD32) offset value: (CARD32) value
{
    rivaWriteReg(regBase, offset, value);
}

- (CARD8) readVGA: (CARD16) port
{
    return rivaReadVGA(port);
}

- (void) writeVGA: (CARD16) port value: (CARD8) value
{
    rivaWriteVGA(port, value);
}

@end
