/*	NSRulerMarker.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSRulerMarker.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSImage.h>

@implementation NSRulerMarker

- (id)initWithRulerView:(NSRulerView *)ruler markerLocation:(float)location image:(NSImage *)image imageOrigin:(NSPoint)imageOrigin
{
    self = [super init];
    if (self) {
        _ruler = ruler;
        _location = location;
        _image = [image retain];
        _imageOrigin = imageOrigin;
        _rFlags.movable = YES;
        _representedObject = nil;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSRulerMarker *copy = NSCopyObject(self, 0, zone);
    copy->_image = [_image retain];
    copy->_representedObject = [_representedObject copyWithZone:zone];
    return copy;
}

- (void)dealloc
{
    [_image release];
    [_representedObject release];
    [super dealloc];
}

- (NSRulerView *)ruler
{
    return _ruler;
}

- (float)markerLocation
{
    return _location;
}

- (void)setMarkerLocation:(float)markerLocation
{
    _location = markerLocation;
}

- (NSImage *)image
{
    return _image;
}

- (void)setImage:(NSImage *)image
{
    [_image release];
    _image = [image retain];
}

- (NSPoint)imageOrigin
{
    return _imageOrigin;
}

- (void)setImageOrigin:(NSPoint)imageOrigin
{
    _imageOrigin = imageOrigin;
}

- (BOOL)isMovable
{
    return _rFlags.movable;
}

- (void)setMovable:(BOOL)movable
{
    _rFlags.movable = movable;
}

- (BOOL)isRemovable
{
    return _rFlags.removable;
}

- (void)setRemovable:(BOOL)removable
{
    _rFlags.removable = removable;
}

- (BOOL)isDragging
{
    return _rFlags.dragging;
}

- (id)representedObject
{
    return _representedObject;
}

- (void)setRepresentedObject:(id)representedObject
{
    [_representedObject release];
    _representedObject = [representedObject copy];
}

- (NSPoint)_originPointInRuler
{
    NSPoint clientPoint;
    if ([_ruler orientation] == NSVerticalRuler)
        clientPoint = NSMakePoint(0.0f, _location);
    else
        clientPoint = NSMakePoint(_location, 0.0f);

    NSPoint rulerPoint = [[_ruler clientView] convertPoint:clientPoint toView:_ruler];
    if ([_ruler orientation] == NSVerticalRuler)
        return NSMakePoint([_ruler baselineLocation], rulerPoint.y);
    return NSMakePoint(rulerPoint.x, [_ruler baselineLocation]);
}

- (NSPoint)_compositePointInRuler
{
    NSPoint origin = [self _originPointInRuler];
    origin.x -= _imageOrigin.x;
    if ([_image isFlipped] == [_ruler isFlipped])
        origin.y -= _imageOrigin.y;
    else
        origin.y += _imageOrigin.y;
    return origin;
}

- (NSRect)imageRectInRuler
{
    NSPoint origin = [self _compositePointInRuler];
    NSSize imageSize = [_image size];
    if (!_ruler || [_ruler isFlipped])
        origin.y -= imageSize.height;
    return NSMakeRect(origin.x, origin.y, imageSize.width, imageSize.height);
}

- (float)thicknessRequiredInRuler
{
    if ([_ruler orientation] == NSVerticalRuler)
        return _imageOrigin.x;
    return [_image size].height - _imageOrigin.y;
}

@end

