/*	NSClipView.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>

@implementation NSClipView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self allocateGState];
        [self setBackgroundColor:[NSColor controlBackgroundColor]];
        [self _setDrawsBackground:YES];
        _halftone = NSZoneMalloc(NULL, 8);
        ((int *)_halftone)[0] = 0;
        ((int *)_halftone)[1] = 0;
    }
    return self;
}

- (NSColor *)backgroundColor
{
    return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)backgroundColor
{
    if (_backgroundColor != backgroundColor) {
        [_backgroundColor release];
        _backgroundColor = [backgroundColor copyWithZone:[self zone]];
    }
}

- (BOOL)copiesOnScroll
{
    return !_cvFlags.noCopyOnScroll;
}

- (void)setCopiesOnScroll:(BOOL)copiesOnScroll
{
    _cvFlags.noCopyOnScroll = !copiesOnScroll;
}

- (NSCursor *)documentCursor
{
    return _cursor;
}

- (void)setDocumentCursor:(NSCursor *)documentCursor
{
    if (_cursor != documentCursor) {
        [_cursor release];
        _cursor = [documentCursor retain];
        [_window invalidateCursorRectsForView:self];
    }
}

- (NSRect)documentRect
{
    return _docRect;
}

- (NSRect)documentVisibleRect
{
    return _docView ? [_docView convertRect:[self bounds] fromView:self] : NSZeroRect;
}

- (NSPoint)constrainScrollPoint:(NSPoint)newOrigin
{
    NSRect bounds = [self bounds];
    NSPoint constrainedOrigin = newOrigin;

    if (bounds.size.width + newOrigin.x > _docRect.origin.x + _docRect.size.width)
        constrainedOrigin.x = _docRect.origin.x + _docRect.size.width - bounds.size.width;
    if (constrainedOrigin.x < _docRect.origin.x)
        constrainedOrigin.x = _docRect.origin.x;

    if (bounds.size.height + newOrigin.y > _docRect.origin.y + _docRect.size.height)
        constrainedOrigin.y = _docRect.origin.y + _docRect.size.height - bounds.size.height;
    if (constrainedOrigin.y < _docRect.origin.y)
        constrainedOrigin.y = _docRect.origin.y;

    return constrainedOrigin;
}

- (id)documentView
{
    return _docView;
}

- (void)setNextKeyView:(NSView *)nextKeyView
{
    if (_docView)
        [_docView setNextKeyView:nextKeyView];
    else
        [super setNextKeyView:nextKeyView];
}

- (void)setDocumentView:(NSView *)documentView
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    NSView *nextKeyView = [self nextKeyView];

    if (_docView) {
        [notificationCenter removeObserver:self name:NSViewFrameDidChangeNotification object:_docView];
        [notificationCenter removeObserver:self name:NSViewBoundsDidChangeNotification object:_docView];
    }

    if (documentView) {
        if (![documentView nextKeyView]) {
            if (!nextKeyView || nextKeyView == _docView || nextKeyView == documentView)
                [documentView setNextKeyView:[_docView nextKeyView]];
            else
                [documentView setNextKeyView:nextKeyView];
        }
        [super setNextKeyView:documentView];
    } else if (nextKeyView && nextKeyView == _docView) {
        [super setNextKeyView:[nextKeyView nextKeyView]];
    }

    [_docView removeFromSuperview];
    _docView = documentView;

    if (documentView) {
        [self addSubview:documentView];
        [notificationCenter addObserver:self selector:@selector(viewFrameChanged:) name:NSViewFrameDidChangeNotification object:documentView];
        [notificationCenter addObserver:self selector:@selector(viewBoundsChanged:) name:NSViewBoundsDidChangeNotification object:documentView];
    }

    [self _alignCoords];
    [self _pinDocRect];
    [self setBoundsOrigin:_docRect.origin];
    if (_cvFlags.reflectScroll)
        [[self superview] reflectScrolledClipView:self];
}

- (void)_alignCoords
{
    BOOL documentFlipped = [_docView isFlipped];
    if (documentFlipped != [self isFlipped]) {
        _cvFlags.isFlipped = documentFlipped;
        [self _invalidateFocus];
    }
}

- (void)_pinDocRect
{
    if (_docView) {
        NSRect bounds = [self bounds];
        _docRect = [_docView frame];
        if (bounds.size.width > _docRect.size.width)
            _docRect.size.width = bounds.size.width;
        if (bounds.size.height > _docRect.size.height)
            _docRect.size.height = bounds.size.height;
    }
}

- (void)viewBoundsChanged:(NSNotification *)notification
{
    if ([notification object] == _docView) {
        NSView *superview = [self superview];
        SEL selector = @selector(_reflectDocumentViewBoundsChange);
        if (superview && [superview respondsToSelector:selector])
            [superview performSelector:selector];
    }
}

- (BOOL)acceptsFirstResponder
{
    return _docView ? [_docView acceptsFirstResponder] : NO;
}

- (BOOL)isFlipped
{
    return _cvFlags.isFlipped;
}

- (BOOL)isOpaque
{
    return [self _drawsBackground];
}

- (BOOL)needsPanelToBecomeKey
{
    return NO;
}

- (BOOL)_drawsBackground
{
    return _cvFlags.drawsBackground;
}

- (void)_setDrawsBackground:(BOOL)drawsBackground
{
    _cvFlags.drawsBackground = drawsBackground;
}

@end

