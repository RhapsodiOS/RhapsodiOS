/*	NSView.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSView.h>
#import <AppKit/NSAffineTransform.h>
#import <AppKit/NSScrollView.h>
#import <math.h>

@implementation NSView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super init];
    if (self) {
        _frame = frameRect;
        _bounds = NSMakeRect(0.0f, 0.0f, frameRect.size.width, frameRect.size.height);
        _vFlags.autoresizeSubviews = YES;
    }
    return self;
}

- (NSWindow *)window
{
    return _window;
}

- (NSView *)superview
{
    return _superview;
}

- (void)viewWillMoveToSuperview:(NSView *)newSuperview
{
    (void)newSuperview;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    (void)newWindow;
}

- (NSArray *)subviews
{
    return _subviews ? (NSArray *)_subviews : [NSArray array];
}

- (NSRect)frame
{
    return _frame;
}

- (NSRect)bounds
{
    return _bounds;
}

- (BOOL)isFlipped
{
    return NO;
}

- (BOOL)isOpaque
{
    return NO;
}

- (BOOL)isRotatedFromBase
{
    return _vFlags.rotatedFromBase;
}

- (BOOL)isRotatedOrScaledFromBase
{
    return _vFlags.rotatedOrScaledFromBase;
}

- (BOOL)_noVerticalAutosizing
{
    return _vFlags.noVerticalAutosizing;
}

- (id)_setNoVerticalAutosizing:(BOOL)noVerticalAutosizing
{
    _vFlags.noVerticalAutosizing = noVerticalAutosizing;
    return self;
}

- (BOOL)_allowsContextMenus
{
    return YES;
}

- (float)frameRotation
{
    NSAffineTransformStruct transform;

    if (_frameMatrix) {
        transform = [_frameMatrix transformStruct];
        return (float)(atan2(transform.m12, transform.m11) * 57.29577951308232f);
    }
    return 0.0f;
}

- (float)boundsRotation
{
    NSAffineTransformStruct transform;

    if (_drawMatrix) {
        transform = [_drawMatrix transformStruct];
        return (float)(atan2(transform.m12, transform.m11) * 57.29577951308232f);
    }
    return 0.0f;
}

- (NSScrollView *)enclosingScrollView
{
    NSView *ancestor;
    NSScrollView *scrollView;

    for (ancestor = _superview; ancestor; ancestor = [ancestor superview]) {
        if (![ancestor isKindOfClass:[NSScrollView class]])
            continue;
        scrollView = (NSScrollView *)ancestor;
        if ([scrollView contentView] && (self == [scrollView contentView] || [self isDescendantOf:[scrollView contentView]]))
            return scrollView;
    }
    return nil;
}

- (BOOL)needsDisplay
{
    return _vFlags.needsDisplay;
}

- (BOOL)_hasgState
{
    return _gState != 0;
}

- (BOOL)postsFrameChangedNotifications
{
    return !_vFlags.frameChangeNotesSuspended;
}

- (BOOL)postsBoundsChangedNotifications
{
    return !_vFlags.boundsChangeNotesSuspended;
}

- (BOOL)autoresizesSubviews
{
    return _vFlags.autoresizeSubviews;
}

- (void)setAutoresizesSubviews:(BOOL)autoresizesSubviews
{
    _vFlags.autoresizeSubviews = autoresizesSubviews;
}

- (unsigned int)autoresizingMask
{
    return _vFlags.autosizing;
}

- (void)setAutoresizingMask:(unsigned int)mask
{
    _vFlags.autosizing = mask;
}

- (BOOL)isDescendantOf:(NSView *)view
{
    if (view == self)
        return YES;
    return _superview ? [_superview isDescendantOf:view] : NO;
}

- (BOOL)_isAncestorOf:(NSView *)view
{
    NSArray *subviews = [self subviews];
    NSUInteger index;

    if ([subviews containsObject:view])
        return YES;
    for (index = 0; index < [subviews count]; index++) {
        if ([[subviews objectAtIndex:index] _isAncestorOf:view])
            return YES;
    }
    return NO;
}

- (NSView *)opaqueAncestor
{
    if ([self isOpaque])
        return self;
    return [_superview opaqueAncestor];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return NO;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)event
{
    (void)event;
    return NO;
}

- (BOOL)mouse:(NSPoint)point inRect:(NSRect)rect
{
    return NSMouseInRect(point, rect, [self isFlipped]);
}

- (int)tag
{
    return -1;
}

- (id)viewWithTag:(int)tag
{
    NSArray *subviews;
    NSUInteger index;
    NSView *view;

    if ([self tag] == tag)
        return self;
    subviews = [self subviews];
    for (index = 0; index < [subviews count]; index++) {
        view = [[subviews objectAtIndex:index] viewWithTag:tag];
        if (view)
            return view;
    }
    return nil;
}

@end

