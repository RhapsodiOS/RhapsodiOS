#ifndef _NS_INTERCEPTOR_CLIENT_PRIVATE_H_
#define _NS_INTERCEPTOR_CLIENT_PRIVATE_H_

#import <Foundation/NSLock.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSThread.h>
#import <AppKit/NSGraphics.h>
#import "Interceptor_types.h"

@class NSInterceptedRect;
@class NSNotification;

@interface NSInterceptorClient : NSObject
{
@private
    InterceptorClientContext *context;
    NSMutableArray *interceptedRects;
    id listLock;
    id portLock;
    id handlingThread;
    BOOL _reserved0;
    id _notifyPort;
    unsigned int _padding[8];
    void *_private;
}

- (id)_addInterceptedRect:(NSInterceptedRect *)rect
       returnedScreenRect:(NSRect *)screenRect
            returnedFlags:(int *)flags;
- (void)_removeInterceptedRect:(NSInterceptedRect *)rect;
- (InterceptorClientContext *)_context;
- (int)interceptorPort;
- (BOOL)handleInterceptorMessage:(InterceptorNotification *)message
                       withReply:(InterceptorReply *)reply;
- (void)startHandlingThread;
- (void)windowServerPortDeath:(NSNotification *)notification;
@end

#endif
