/*	NSCachedImageRep.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSCachedImageRep.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSObjCRuntime.h>
#include <math.h>

extern NSWindow *_NXSharedKitImagesWindow(NSWindow *window);

@interface NSCachedImageRep (Private)
- (void)_computeParams;
- (BOOL)_canDrawOutsideOfItsBounds;
@end

@implementation NSCachedImageRep

+ (void)initialize
{
    if (self == [NSCachedImageRep class])
        [self setVersion:17];
}

- (id)initWithWindow:(NSWindow *)window rect:(NSRect)rect
{
    self = [super init];
    if (self != nil) {
        _window = [window retain];
        _origin = rect.origin;
        [self setSize:rect.size];
        [self setOpaque:YES];
    }
    return self;
}

- (NSWindow *)window
{
    if ((unsigned long)_window - 1 <= 6)
        _window = [_NXSharedKitImagesWindow(_window) retain];
    return _window;
}

- (NSRect)rect
{
    NSRect rect;
    rect.origin = _origin;
    rect.size = [self size];
    return rect;
}

- (void)setAlpha:(BOOL)flag
{
    [super setAlpha:flag];
    _repFlags.cacheAlphaComputed = YES;
}

- (void)_computeParams
{
    if (_repFlags.cacheParamsComputed)
        return;

    NSWindowDepth depth = [[self window] depthLimit];
    NSSize size = [self size];

    if (depth == 0)
        depth = [NSWindow defaultDepthLimit];

    [self setPixelsHigh:(int)ceil(size.height)];
    [self setPixelsWide:(int)ceil(size.width)];
    [self setBitsPerSample:NSBitsPerSampleFromDepth(depth)];
    [self setColorSpaceName:NSColorSpaceFromDepth(depth)];
    _repFlags.cacheParamsComputed = YES;
}

- (int)bitsPerSample
{
    if (!_repFlags.cacheParamsComputed)
        [self _computeParams];
    return [super bitsPerSample];
}

- (NSString *)colorSpaceName
{
    if (!_repFlags.cacheParamsComputed)
        [self _computeParams];
    return [super colorSpaceName];
}

- (int)pixelsWide
{
    if (!_repFlags.cacheParamsComputed)
        [self _computeParams];
    return [super pixelsWide];
}

- (int)pixelsHigh
{
    if (!_repFlags.cacheParamsComputed)
        [self _computeParams];
    return [super pixelsHigh];
}

- (BOOL)_canDrawOutsideOfItsBounds
{
    return NO;
}

@end

