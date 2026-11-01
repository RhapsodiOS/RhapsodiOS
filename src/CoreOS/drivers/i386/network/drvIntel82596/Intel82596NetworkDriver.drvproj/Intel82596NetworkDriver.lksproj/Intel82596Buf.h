#ifndef _INTEL82596_BUF_H_
#define _INTEL82596_BUF_H_

#import <objc/Object.h>
#import <machkit/NXLock.h>
#import "Intel82596Layout.h"

@interface Intel82596Buf : Object
{
    I596_BUF_IVARS;
}
- initWithRequestedSize:(unsigned int)requested
             actualSize:(unsigned int *)actual
                  count:(unsigned int)count;
- free;
- (netbuf_t)getNetBuffer;
- (unsigned int)numFree;
@end

#endif
