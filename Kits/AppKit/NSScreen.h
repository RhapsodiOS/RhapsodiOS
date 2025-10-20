/*
	NSScreen.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <AppKit/NSGraphics.h>

@interface NSScreen : NSObject {
/*All instance variables are private*/
@private
    NSRect _frame;
    NSWindowDepth _depth;
    int _screenNumber;
    unsigned int _reserved;
}

+ (NSArray *)screens;		/* All screens; first one is "zero" screen */
+ (NSScreen *)mainScreen;	/* Screen with key window */
+ (NSScreen *)deepestScreen;

- (NSWindowDepth)depth;
- (NSRect)frame;
- (NSRect)visibleFrame;
- (NSDictionary *)deviceDescription;

- (const NSWindowDepth *)supportedWindowDepths; /* 0 terminated */

@end

