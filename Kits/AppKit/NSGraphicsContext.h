/*
        NSGraphicsContext.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <Foundation/Foundation.h>

@interface NSGraphicsContext : NSObject
{
/*All instance variables are private*/
}

// Setting and identifying the current context
+ (id)currentContext;
+ (void)setCurrentContext:(NSGraphicsContext *)context;

// Testing the drawing destination
- (BOOL)isDrawingToScreen;

// Controlling the context
- (void)saveGraphicsState;
- (void)restoreGraphicsState;
- (void)flush;
- (void)wait;

- (void)flushGraphics;

@end
