/*	NSRulerView.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSRulerView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSRulerMarker.h>

@implementation NSRulerView

- (NSRulerOrientation)orientation
{
    return _orientation;
}

- (void)setOrientation:(NSRulerOrientation)orientation
{
    _orientation = orientation;
    [self invalidateHashMarks];
    [self setNeedsDisplay:YES];
}

- (NSScrollView *)scrollView
{
    return _scrollView;
}

- (void)setScrollView:(NSScrollView *)scrollView
{
    _scrollView = scrollView;
    [self invalidateHashMarks];
    [self setNeedsDisplay:YES];
}

- (NSView *)clientView
{
    return _clientView;
}

- (void)setClientView:(NSView *)clientView
{
    SEL selector = @selector(rulerView:willSetClientView:);
    if (_clientView && [_clientView respondsToSelector:selector])
        [_clientView rulerView:self willSetClientView:clientView];
    _clientView = clientView;
    [self _setDraggingMarker:nil];
}

- (void)_setDraggingMarker:(NSRulerMarker *)marker
{
    _draggingMarker = marker;
}

- (NSView *)accessoryView
{
    return _accessoryView;
}

- (NSRect)_rulerAccessoryViewAreaRect
{
    NSRect accessoryArea = [self bounds];
    if (_orientation == NSVerticalRuler) {
        accessoryArea.size.width = _thicknessForAccessoryView;
    } else {
        accessoryArea.size.height = _thicknessForAccessoryView;
    }
    return accessoryArea;
}

- (void)setAccessoryView:(NSView *)accessoryView
{
    if (!_clientView && accessoryView)
        NSLog(@"NSRulerView setAccessoryView: requires a client view");

    [_accessoryView removeFromSuperview];
    _accessoryView = accessoryView;

    if (accessoryView) {
        NSRect accessoryFrame = [accessoryView frame];
        NSRect rulerBounds = [self bounds];
        float requiredThickness;

        if (_orientation == NSVerticalRuler) {
            requiredThickness = accessoryFrame.size.width;
            rulerBounds.size.width = accessoryFrame.size.width;
        } else {
            requiredThickness = accessoryFrame.size.height;
            rulerBounds.size.height = accessoryFrame.size.height;
        }

        [accessoryView setFrame:rulerBounds];
        if (_thicknessForAccessoryView < requiredThickness)
            [self setReservedThicknessForAccessoryView:requiredThickness];
        [self addSubview:accessoryView];
    }

    [self setNeedsDisplayInRect:[self _rulerAccessoryViewAreaRect]];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];

    if (_accessoryView) {
        NSRect rulerBounds = [self bounds];
        NSRect accessoryFrame = [_accessoryView frame];
        accessoryFrame.origin = rulerBounds.origin;
        if (_orientation == NSVerticalRuler)
            accessoryFrame.size.height = rulerBounds.size.height;
        else
            accessoryFrame.size.width = rulerBounds.size.width;
        [_accessoryView setFrame:accessoryFrame];
    }
}

- (NSArray *)markers
{
    return _markers;
}

- (NSRect)_markerAreaRect
{
    NSRect markerArea = [self bounds];
    if (_orientation == NSVerticalRuler) {
        markerArea.origin.x += _thicknessForAccessoryView;
        markerArea.size.width = _thicknessForMarkers;
    } else {
        markerArea.origin.y += _thicknessForAccessoryView;
        markerArea.size.height = _thicknessForMarkers;
    }
    return markerArea;
}

- (void)setMarkers:(NSArray *)markers
{
    [_markers release];
    _markers = nil;

    if (markers) {
        unsigned int count = [markers count];
        _markers = [[NSMutableArray allocWithZone:[self zone]] initWithCapacity:count];
        float requiredThickness = 0.0f;

        for (unsigned int index = 0; index < count; index++) {
            NSRulerMarker *marker = [markers objectAtIndex:index];
            float markerThickness = [marker thicknessRequiredInRuler];
            if (markerThickness > requiredThickness)
                requiredThickness = markerThickness;
            [_markers addObject:marker];
        }

        requiredThickness += 2.0f;
        if (requiredThickness > _thicknessForMarkers)
            [self setReservedThicknessForMarkers:requiredThickness];
    }

    [self setNeedsDisplayInRect:[self _markerAreaRect]];
}

- (void)addMarker:(NSRulerMarker *)marker
{
    if (!_clientView)
        NSLog(@"NSRulerView addMarker: requires a client view");

    if (_markers) {
        float requiredThickness = [marker thicknessRequiredInRuler] + 2.0f;
        if (requiredThickness > _thicknessForMarkers)
            [self setReservedThicknessForMarkers:requiredThickness];
        [_markers addObject:marker];
        [self setNeedsDisplayInRect:[self _markerAreaRect]];
    } else {
        [self setMarkers:[NSMutableArray arrayWithObject:marker]];
    }
}

- (void)removeMarker:(NSRulerMarker *)marker
{
    if (!_clientView)
        NSLog(@"NSRulerView removeMarker: requires a client view");

    [_markers removeObject:marker];
    [self setNeedsDisplayInRect:[self _markerAreaRect]];
}

- (float)originOffset
{
    return _originOffset;
}

- (void)setOriginOffset:(float)offset
{
    if (_originOffset != offset) {
        _originOffset = offset;
        [self setNeedsDisplay:YES];
    }
}

- (float)ruleThickness
{
    return _ruleThickness;
}

- (void)setRuleThickness:(float)thickness
{
    if (_ruleThickness != thickness) {
        _ruleThickness = thickness;
        [_scrollView tile];
        [self setNeedsDisplay:YES];
    }
}

- (float)reservedThicknessForMarkers
{
    return _thicknessForMarkers;
}

- (void)setReservedThicknessForMarkers:(float)thickness
{
    if (_thicknessForMarkers != thickness) {
        _thicknessForMarkers = thickness;
        [_scrollView tile];
        [self setNeedsDisplay:YES];
    }
}

- (float)reservedThicknessForAccessoryView
{
    return _thicknessForAccessoryView;
}

- (void)setReservedThicknessForAccessoryView:(float)thickness
{
    if (_thicknessForAccessoryView != thickness) {
        _thicknessForAccessoryView = thickness;
        [_scrollView tile];
        [self setNeedsDisplay:YES];
    }
}

- (float)baselineLocation
{
    NSRect rulerFrame = [self frame];
    return _orientation == NSHorizontalRuler ? rulerFrame.origin.y : rulerFrame.origin.x;
}

- (float)requiredThickness
{
    return _thicknessForAccessoryView + _thicknessForMarkers + _ruleThickness;
}

- (BOOL)isFlipped
{
    if (_orientation == NSHorizontalRuler)
        return YES;
    return [[_scrollView documentView] isFlipped];
}

- (BOOL)isOpaque
{
    return YES;
}

- (void)invalidateHashMarks
{
    if (_cachedHashDict) {
        [_cachedHashDict release];
        _cachedHashDict = nil;
    }
}

- (void)dealloc
{
    SEL selector = @selector(rulerView:willSetClientView:);
    if (_clientView && [_clientView respondsToSelector:selector])
        [_clientView rulerView:self willSetClientView:nil];

    [_cachedHashDict release];
    [_markers release];
    [_units release];
    [super dealloc];
}

@end

