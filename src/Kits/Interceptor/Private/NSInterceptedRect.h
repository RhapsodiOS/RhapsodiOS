#ifndef _NS_INTERCEPTED_RECT_PRIVATE_H_
#define _NS_INTERCEPTED_RECT_PRIVATE_H_

#import <AppKit/NSGraphics.h>
#import <Foundation/NSObject.h>
#import "Interceptor_types.h"

@interface NSInterceptedRect : NSObject
{
@private
    NSRect rect;
    NSRect screenRect;
    int windowNumber;
    id screen;
    unsigned int uniqueID;
    id target;
    unsigned int flags;
    id rectLock;
    BOOL isTotallyVisible;
    BOOL isTotallyObscured;
    BOOL moveInProgress;
    BOOL isLocked;
    id tmpBitmap;
    id interceptorClient;
    id screenRectShape;
    unsigned int _ir_padding[7];
    void *_ir_private;
}
@end

#endif
