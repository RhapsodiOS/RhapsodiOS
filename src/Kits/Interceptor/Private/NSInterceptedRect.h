#ifndef _NS_INTERCEPTED_RECT_PRIVATE_H_
#define _NS_INTERCEPTED_RECT_PRIVATE_H_

#import <AppKit/NSGraphics.h>
#import <Foundation/NSObject.h>
#import "Interceptor_types.h"

@class NSShape;
@class NSInterceptorClient;

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

- initForRect:(NSRect)rect inWindow:(int)windowNumber
    onFramebuffer:(id)framebuffer forClient:(NSInterceptorClient *)client;
- (void)lockRect;
- (void)unlockRect;
- (BOOL)isLocked;
- (void)setTarget:(id)target;
- (id)target;
- (NSRect)currentScreenRect;
- (NSShape *)currentScreenRectShape;
- (id)currentClipList:(NSRect)rect count:(int)count;
- (id)compositeBits:(id)bits withOp:(int)operation;
- (void)removeFromWindowServer;
- (unsigned int)uniqueID;
- (int)windowNumber;
- (NSRect)rectangle;
- (BOOL)isTotallyVisible;
- (BOOL)isTotallyObscured;
- (unsigned int)_flags;
- (id)framebuffer;
- (id)_handleMsg:(InterceptorNotification *)message withReply:(InterceptorReply *)reply;
@end

#endif
