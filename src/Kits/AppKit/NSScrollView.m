/*	NSScrollView.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSInterfaceStyle.h>

static Class NSScrollViewRulerClass;

@implementation NSScrollView

- (id)_contentView
{
    return _contentView;
}

- (NSClipView *)contentView
{
    return _contentView;
}

- (NSRect)documentVisibleRect
{
    return _contentView ? [_contentView documentVisibleRect] : NSZeroRect;
}

- (id)documentView
{
    return [_contentView documentView];
}

- (NSCursor *)documentCursor
{
    return [_contentView documentCursor];
}

- (void)setDocumentCursor:(NSCursor *)documentCursor
{
    [_contentView setDocumentCursor:documentCursor];
}

- (NSColor *)backgroundColor
{
    return [_contentView backgroundColor];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor
{
    [_contentView setBackgroundColor:backgroundColor];
}

- (void)_reflectDocumentViewBoundsChange
{
    if (_horizontalRuler) {
        [_horizontalRuler updateRuler];
        [_horizontalRuler setNeedsDisplay:YES];
    }
    if (_verticalRuler) {
        [_verticalRuler updateRuler];
        [_verticalRuler setNeedsDisplay:YES];
    }
}

- (NSSize)contentSize
{
    return [_contentView bounds].size;
}

- (NSScroller *)verticalScroller
{
    return _vScroller;
}

- (NSScroller *)horizontalScroller
{
    return _hScroller;
}

- (NSBorderType)borderType
{
    return _sFlags.borderType;
}

- (void)setBorderType:(NSBorderType)borderType
{
    if (_sFlags.borderType != borderType) {
        _sFlags.borderType = borderType;
        [self tile];
    }
}

- (BOOL)hasVerticalScroller
{
    return _sFlags.vScrollerRequired;
}

- (BOOL)hasHorizontalScroller
{
    return _sFlags.hScrollerRequired;
}

- (void)setHasVerticalScroller:(BOOL)hasVerticalScroller
{
    if (_sFlags.vScrollerRequired != hasVerticalScroller) {
        _sFlags.vScrollerRequired = hasVerticalScroller;
        if (hasVerticalScroller) {
            if (!_vScroller)
                [self _newScroll:YES];
        } else {
            [_vScroller setFrameSize:NSMakeSize(-100.0f, -100.0f)];
        }
        [self _update];
    }
}

- (void)setHasHorizontalScroller:(BOOL)hasHorizontalScroller
{
    if (_sFlags.hScrollerRequired != hasHorizontalScroller) {
        _sFlags.hScrollerRequired = hasHorizontalScroller;
        if (hasHorizontalScroller) {
            if (!_hScroller)
                [self _newScroll:NO];
        } else {
            [_hScroller setFrameSize:NSMakeSize(-100.0f, -100.0f)];
        }
        [self _update];
    }
}

- (id)_commonNewScroll:(NSScroller *)scroller
{
    [self addSubview:scroller];
    [scroller setTarget:self];
    [scroller setAction:@selector(_doScroller:)];
    return self;
}

- (void)setVerticalScroller:(NSScroller *)verticalScroller
{
    if (_vScroller != verticalScroller) {
        [_vScroller removeFromSuperview];
        [self _commonNewScroll:verticalScroller];
        _vScroller = verticalScroller;
    }
}

- (void)setHorizontalScroller:(NSScroller *)horizontalScroller
{
    if (_hScroller != horizontalScroller) {
        [_hScroller removeFromSuperview];
        [self _commonNewScroll:horizontalScroller];
        _hScroller = horizontalScroller;
    }
}

- (void)setCopiesOnScroll:(BOOL)copiesOnScroll
{
    [_contentView setCopiesOnScroll:copiesOnScroll];
}

- (void)setInterfaceStyle:(NSInterfaceStyle)interfaceStyle
{
    [super setInterfaceStyle:interfaceStyle];
    [self _update];
}

- (void)setNextKeyView:(NSView *)nextKeyView
{
    if (_contentView)
        [_contentView setNextKeyView:nextKeyView];
    else
        [super setNextKeyView:nextKeyView];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
    [self _update];
}

- (id)_newScroll:(BOOL)isVertical
{
    NSRect frame = NSZeroRect;
    NSScroller *scroller;

    if (isVertical)
        frame.size.height = 100.0f;
    else
        frame.size.width = 100.0f;

    scroller = [[NSScroller allocWithZone:[self zone]] initWithFrame:frame];
    [self _commonNewScroll:scroller];
    [scroller setArrowsPosition:NSScrollerArrowsMaxEnd];
    if (isVertical)
        _vScroller = scroller;
    else
        _hScroller = scroller;
    [scroller checkSpaceForParts];
    return self;
}

- (id)_update
{
    [self tile];
    [self setNeedsDisplay:YES];
    return self;
}

- (float)horizontalLineScroll
{
    return ((float *)_reserved1)[2];
}

- (float)horizontalPageScroll
{
    return ((float *)_reserved1)[0];
}

- (float)verticalLineScroll
{
    return ((float *)_reserved1)[3];
}

- (float)verticalPageScroll
{
    return ((float *)_reserved1)[1];
}

- (void)setHorizontalLineScroll:(float)horizontalLineScroll
{
    ((float *)_reserved1)[2] = horizontalLineScroll > 0.0f ? horizontalLineScroll : 0.0f;
}

- (void)setHorizontalPageScroll:(float)horizontalPageScroll
{
    ((float *)_reserved1)[0] = horizontalPageScroll > 0.0f ? horizontalPageScroll : 0.0f;
}

- (void)setVerticalLineScroll:(float)verticalLineScroll
{
    ((float *)_reserved1)[3] = verticalLineScroll > 0.0f ? verticalLineScroll : 0.0f;
}

- (void)setVerticalPageScroll:(float)verticalPageScroll
{
    ((float *)_reserved1)[1] = verticalPageScroll > 0.0f ? verticalPageScroll : 0.0f;
}

- (float)lineScroll
{
    return [self verticalLineScroll];
}

- (float)pageScroll
{
    return [self verticalPageScroll];
}

- (void)setLineScroll:(float)lineScroll
{
    [self setVerticalLineScroll:lineScroll];
    [self setHorizontalLineScroll:lineScroll];
}

- (void)setPageScroll:(float)pageScroll
{
    [self setVerticalPageScroll:pageScroll];
    [self setHorizontalPageScroll:pageScroll];
}

- (BOOL)acceptsFirstResponder
{
    return [_contentView acceptsFirstResponder];
}

- (BOOL)isFlipped
{
    return YES;
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
    return !_sFlags.doesNotDrawBackground;
}

- (void)_setDrawsBackground:(BOOL)drawsBackground
{
    _sFlags.doesNotDrawBackground = !drawsBackground;
}

- (BOOL)scrollsDynamically
{
    return !_sFlags.noDynamicScrolling;
}

- (void)setScrollsDynamically:(BOOL)scrollsDynamically
{
    _sFlags.noDynamicScrolling = !scrollsDynamically;
}

@end

@implementation NSScrollView(NSRulerSupport)

- (BOOL)rulersVisible
{
    return _sFlags.showRulers;
}

- (BOOL)hasHorizontalRuler
{
    return _sFlags.hasHorizontalRuler;
}

- (BOOL)hasVerticalRuler
{
    return _sFlags.hasVerticalRuler;
}

- (void)setRulersVisible:(BOOL)rulersVisible
{
    if (_sFlags.showRulers != rulersVisible) {
        _sFlags.showRulers = rulersVisible;
        [self tile];
    }
}

- (void)setHasHorizontalRuler:(BOOL)hasHorizontalRuler
{
    if (_sFlags.hasHorizontalRuler != hasHorizontalRuler) {
        _sFlags.hasHorizontalRuler = hasHorizontalRuler;
        if (_sFlags.showRulers) {
            [self horizontalRulerView];
            [self tile];
        }
    }
}

- (void)setHasVerticalRuler:(BOOL)hasVerticalRuler
{
    if (_sFlags.hasVerticalRuler != hasVerticalRuler) {
        _sFlags.hasVerticalRuler = hasVerticalRuler;
        if (_sFlags.showRulers) {
            [self verticalRulerView];
            [self tile];
        }
    }
}

+ (Class)rulerViewClass
{
    return NSScrollViewRulerClass ? NSScrollViewRulerClass : [NSRulerView class];
}

+ (void)setRulerViewClass:(Class)rulerViewClass
{
    NSScrollViewRulerClass = rulerViewClass;
}

- (NSRulerView *)horizontalRulerView
{
    if (!_horizontalRuler && _sFlags.hasHorizontalRuler) {
        Class rulerClass = [[self class] rulerViewClass];
        _horizontalRuler = [[rulerClass alloc] initWithScrollView:self orientation:NSHorizontalRuler];
    }
    return _horizontalRuler;
}

- (NSRulerView *)verticalRulerView
{
    if (!_verticalRuler && _sFlags.hasVerticalRuler) {
        Class rulerClass = [[self class] rulerViewClass];
        _verticalRuler = [[rulerClass alloc] initWithScrollView:self orientation:NSVerticalRuler];
    }
    return _verticalRuler;
}

@end

