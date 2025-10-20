/*
	NSBrowserCell.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSCell.h>

@class NSImage;

@interface NSBrowserCell : NSCell

+ (NSImage *)branchImage;
+ (NSImage *)highlightedBranchImage;

- (BOOL)isLeaf;
- (void)setLeaf:(BOOL)flag;
- (BOOL)isLoaded;
- (void)setLoaded:(BOOL)flag;
- (void)reset;
- (void)set;
- (void)setAlternateImage:(NSImage *)newAltImage;
- (NSImage *)alternateImage;

@end
