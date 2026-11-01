/*	NSButtonCell.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSButtonCell.h>
#import <AppKit/NSView.h>

@interface NSButtonCell (NSButtonCellPrivate)
- (void)_setAltContents:(NSString *)contents;
@end

@implementation NSButtonCell

- (int)nextState
{
    if ([self buttonType] == NSRadioButton)
        return NSOnState;
    return [super nextState];
}

- (BOOL)_highlightsWithHighlightRect
{
    return NO;
}

- (BOOL)_shouldSetHighlightToFlag:(BOOL)flag
{
    if (_bcFlags.transparent)
        return NO;
    return [super _shouldSetHighlightToFlag:flag];
}

- (NSSound *)sound
{
    return (NSSound *)_sound;
}

- (void)setSound:(NSSound *)sound
{
    if (sound != nil && [_sound isEqual:sound])
        return;
    [_sound release];
    _sound = [sound retain];
}

- (id)_sound
{
    return _sound;
}

- (void)_setSound:(id)sound
{
    if (sound != nil && [_sound isEqual:sound])
        return;
    [_sound release];
    _sound = [sound retain];
}

- (id)_altContents
{
    return _altContents;
}

- (void)_setAltContents:(NSString *)contents
{
    if (_altContents == contents)
        return;
    [_altContents release];
    _altContents = [contents copy];
}

- (NSString *)keyEquivalent
{
    return _keyEquivalent != nil ? _keyEquivalent : @"";
}

- (void)setKeyEquivalent:(NSString *)keyEquivalent
{
    if (_keyEquivalent == keyEquivalent || [_keyEquivalent isEqual:keyEquivalent])
        return;
    [_keyEquivalent release];
    _keyEquivalent = [keyEquivalent copy];
    [[self controlView] setNeedsDisplay:YES];
}

- (unsigned int)keyEquivalentModifierMask
{
    unsigned int mask = _bcFlags2.keyEquivalentModifierMask;
    return mask == 0xFFFFFF ? (unsigned int)-1 : mask;
}

- (void)setKeyEquivalentModifierMask:(unsigned int)mask
{
    if ((mask & 0x40000) != 0)
        mask = (mask & 0xFFEBFFFF) | 0x100000;
    _bcFlags2.keyEquivalentModifierMask = mask;
}

- (NSString *)title
{
    return _contents != nil ? (NSString *)_contents : @"";
}

- (void)setTitle:(NSString *)title
{
    if (_contents == title)
        return;
    [_contents release];
    _contents = [title copy];
    [[self controlView] setNeedsDisplay:YES];
}

- (NSString *)alternateTitle
{
    return _altContents != nil ? _altContents : @"";
}

- (void)setAlternateTitle:(NSString *)alternateTitle
{
    [self _setAltContents:alternateTitle];
    [[self controlView] setNeedsDisplay:YES];
}

- (NSCellImagePosition)imagePosition
{
    if (_bcFlags.imageOverlaps)
        return _bcFlags.imageAndText ? NSImageOverlaps : NSImageOnly;
    if (!_bcFlags.imageAndText)
        return NSNoImage;
    if (_bcFlags.horizontal)
        return _bcFlags.bottomOrLeft ? NSImageLeft : NSImageRight;
    return _bcFlags.bottomOrLeft ? NSImageBelow : NSImageAbove;
}

- (void)setImagePosition:(NSCellImagePosition)position
{
    BOOL oldImageAndText = _bcFlags.imageAndText;
    BOOL oldImageOverlaps = _bcFlags.imageOverlaps;
    BOOL oldHorizontal = _bcFlags.horizontal;
    BOOL oldBottomOrLeft = _bcFlags.bottomOrLeft;

    _bcFlags.imageAndText = position > NSImageOnly;
    _bcFlags.imageOverlaps = position == NSImageOnly || position == NSImageOverlaps;
    if (position == NSImageLeft || position == NSImageRight) {
        _bcFlags.horizontal = YES;
        _bcFlags.bottomOrLeft = position == NSImageLeft;
    } else if (position == NSImageBelow || position == NSImageAbove) {
        _bcFlags.horizontal = NO;
        _bcFlags.bottomOrLeft = position == NSImageBelow;
    }

    if (oldImageAndText != _bcFlags.imageAndText
        || oldImageOverlaps != _bcFlags.imageOverlaps
        || oldHorizontal != _bcFlags.horizontal
        || oldBottomOrLeft != _bcFlags.bottomOrLeft)
        [[self controlView] setNeedsDisplay:YES];
}

- (NSUInteger)alternateMnemonicLocation
{
    return _bcFlags.alternateMnemonicLocation == 0xFF
        ? (NSUInteger)0x7FFFFFFF
        : _bcFlags.alternateMnemonicLocation;
}

- (void)setAlternateMnemonicLocation:(NSUInteger)location
{
    _bcFlags.alternateMnemonicLocation =
        (location == (NSUInteger)0x7FFFFFFF || location > 0xFE) ? 0xFF : location;
}

- (BOOL)isTransparent
{
    return _bcFlags.transparent;
}

- (BOOL)isBordered
{
    return _bcFlags.bordered;
}

- (void)setTransparent:(BOOL)transparent
{
    BOOL wasTransparent = _bcFlags.transparent;
    _bcFlags.transparent = transparent;
    if (wasTransparent && !transparent)
        [[self controlView] setNeedsDisplay:YES];
}

- (void)setBordered:(BOOL)bordered
{
    if (_bcFlags.bordered == bordered)
        return;
    _bcFlags.bordered = bordered;
    [[self controlView] setNeedsDisplay:YES];
}

- (NSCellStyleMask)highlightsBy
{
    NSCellStyleMask mask = 0;
    if (_bcFlags.pushIn)
        mask |= 2;
    if (_bcFlags.lightByContents)
        mask |= 1;
    if (_bcFlags.lightByBackground)
        mask |= 4;
    if (_bcFlags.lightByGray)
        mask |= 8;
    return mask;
}

- (void)setHighlightsBy:(NSCellStyleMask)mask
{
    _bcFlags.pushIn = (mask & 2) != 0;
    _bcFlags.lightByContents = (mask & 1) != 0;
    _bcFlags.lightByBackground = (mask & 4) != 0;
    _bcFlags.lightByGray = (mask & 8) != 0;
    [[self controlView] setNeedsDisplay:YES];
}

- (NSCellStyleMask)showsStateBy
{
    NSCellStyleMask mask = 0;
    if (_bcFlags.changeContents)
        mask |= 1;
    if (_bcFlags.changeBackground)
        mask |= 4;
    if (_bcFlags.changeGray)
        mask |= 8;
    return mask;
}

- (void)setShowsStateBy:(NSCellStyleMask)mask
{
    _bcFlags.changeContents = (mask & 1) != 0;
    _bcFlags.changeBackground = (mask & 4) != 0;
    _bcFlags.changeGray = (mask & 8) != 0;
    [[self controlView] setNeedsDisplay:YES];
}

- (NSGradientType)gradientType
{
    return (NSGradientType)_bcFlags.gradientType;
}

- (void)setGradientType:(NSGradientType)gradientType
{
    if (_bcFlags.gradientType == gradientType)
        return;
    _bcFlags.gradientType = gradientType;
    [[self controlView] setNeedsDisplay:YES];
}

@end

@implementation NSButtonCell (NSButtonCellBezelStyles)

- (NSBezelStyle)bezelStyle
{
    return (NSBezelStyle)_bcFlags2.bezelStyle;
}

- (void)setBezelStyle:(NSBezelStyle)bezelStyle
{
    _bcFlags2.bezelStyle = bezelStyle;
    [[self controlView] setNeedsDisplay:YES];
}

@end

@implementation NSButtonCell (NSButtonCellPrivate)

- (BOOL)_canBecomeDefaultButtonCell
{
    return _bcFlags.useButtonImageSource;
}

- (BOOL)imageDimsWhenDisabled
{
    return !_bcFlags.doesNotDimImage;
}

- (BOOL)_hasImage
{
    return _bcFlags.imageOverlaps || _bcFlags.imageAndText;
}

- (BOOL)_hasTitle
{
    return !_bcFlags.imageOverlaps || _bcFlags.imageAndText;
}

- (void)setImageDimsWhenDisabled:(BOOL)imageDimsWhenDisabled
{
    _bcFlags.doesNotDimImage = !imageDimsWhenDisabled;
}

- (BOOL)showsBorderOnlyWhileMouseInside
{
    return _bcFlags2.showsBorderOnlyWhileMouseInside;
}

- (void)setShowsBorderOnlyWhileMouseInside:(BOOL)showsBorderOnlyWhileMouseInside
{
    if (_bcFlags2.showsBorderOnlyWhileMouseInside == showsBorderOnlyWhileMouseInside)
        return;
    _bcFlags2.showsBorderOnlyWhileMouseInside = showsBorderOnlyWhileMouseInside;
    if (!showsBorderOnlyWhileMouseInside)
        _bcFlags2.mouseInside = NO;
    [[self controlView] setNeedsDisplay:YES];
}

- (void)mouseEntered:(NSEvent *)event
{
    if (_bcFlags2.showsBorderOnlyWhileMouseInside) {
        _bcFlags2.mouseInside = YES;
        [[self controlView] setNeedsDisplay:YES];
    }
}

- (void)mouseExited:(NSEvent *)event
{
    if (_bcFlags2.showsBorderOnlyWhileMouseInside) {
        _bcFlags2.mouseInside = NO;
        [[self controlView] setNeedsDisplay:YES];
    }
}

@end
