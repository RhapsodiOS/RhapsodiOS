/*	NSGraphicsContext.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSDPSContext.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>

static void requestConcreteImplementation(NSGraphicsContext *context)
{
    [NSException raise:NSInternalInconsistencyException
                format:@"%@ is a subclass responsibility but has not been overridden.",
                       NSStringFromClass([context class])];
}

@implementation NSGraphicsContext

+ (id)currentContext
{
    return [NSDPSContext currentContext];
}

+ (void)setCurrentContext:(NSGraphicsContext *)context
{
    [NSDPSContext setCurrentContext:context];
}

- (BOOL)isDrawingToScreen
{
    requestConcreteImplementation(self);
    return YES;
}

- (void)saveGraphicsState
{
    requestConcreteImplementation(self);
}

- (void)restoreGraphicsState
{
    requestConcreteImplementation(self);
}

- (void)flush
{
    [self flushGraphics];
    requestConcreteImplementation(self);
}

- (void)wait
{
    requestConcreteImplementation(self);
}

- (void)flushGraphics
{
    [self flush];
    requestConcreteImplementation(self);
}

@end
