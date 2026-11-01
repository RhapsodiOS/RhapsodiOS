/*	NSActionCell.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSActionCell.h>
#import <AppKit/NSControl.h>

@implementation NSActionCell

- (NSView *)controlView
{
    return _controlView;
}

- (void)_setControlView:(NSView *)view
{
    _controlView = [view isKindOfClass:[NSView class]] ? view : nil;
}

- (id)target
{
    return _target;
}

- (void)setTarget:(id)target
{
    _target = target;
}

- (SEL)action
{
    return _action;
}

- (void)setAction:(SEL)action
{
    _action = action;
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
}

- (void)setBezeled:(BOOL)bezeled
{
    [super setBezeled:bezeled];
}

- (void)setBordered:(BOOL)bordered
{
    [super setBordered:bordered];
}

- (void)setAlignment:(NSTextAlignment)alignment
{
    if ([self alignment] != alignment) {
        [super setAlignment:alignment];
        [(NSControl *)[self controlView] updateCell:self];
    }
}

- (void)setImage:(NSImage *)image
{
    NSImage *oldImage = [self image];
    [super setImage:image];
    if (![oldImage isEqual:[self image]])
        [(NSControl *)[self controlView] updateCell:self];
}

- (int)tag
{
    return _tag;
}

- (void)setTag:(int)tag
{
    _tag = tag;
}

@end

