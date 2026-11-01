/*	NSCell.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSFormatter.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSValue.h>

extern int _NSAppKitGlobalLock;
extern void _NSAppKitLock(int line, const char *file);
extern void _NSAppKitUnlock(int line, const char *file);

static NSMapTable *NSCellFormatters;

@implementation NSCell

- (NSView *)controlView
{
    return nil;
}

- (SEL)action
{
    return nil;
}

- (void)_setControlView:(NSView *)view
{
}

- (NSString *)keyEquivalent
{
    return @"";
}

- (NSCellType)type
{
    return _cFlags.type;
}

- (void)setType:(NSCellType)type
{
    if (_cFlags.type == type)
        return;
    if (type == NSTextCellType)
        [self _convertToText:@"Cell"];
    else if (type == NSImageCellType)
        [self setImage:nil];
    else
        _cFlags.type = type;
}

- (id)_convertToText:(id)string
{
    if (_cFlags.type != NSTextCellType) {
        [_support release];
        _support = nil;
        _cFlags.type = NSTextCellType;
        [self setFont:[NSFont messageFontOfSize:12.0f]];
        [self setObjectValue:string];
    }
    return self;
}

- (int)state
{
    if (_cFlags.allowsMixedState && _cFlags.inMixedState)
        return NSMixedState;
    return _cFlags.state;
}

- (void)setState:(int)state
{
    if (_cFlags.allowsMixedState)
        _cFlags.inMixedState = state == NSMixedState;
    _cFlags.state = state != NSOffState;
}

- (BOOL)isEnabled
{
    return !_cFlags.disabled;
}

- (void)setEnabled:(BOOL)enabled
{
    BOOL wasEnabled = !_cFlags.disabled;
    _cFlags.disabled = !enabled;
    if (wasEnabled != enabled)
        [(NSControl *)[self controlView] updateCell:self];
}

- (BOOL)isEditable
{
    return _cFlags.editable;
}

- (void)setEditable:(BOOL)editable
{
    _cFlags.editable = editable;
    if (editable)
        _cFlags.selectable = YES;
    else if (!_cFlags.wasSelectable)
        _cFlags.selectable = NO;
}

- (BOOL)isSelectable
{
    return _cFlags.selectable || _cFlags.editable;
}

- (void)setSelectable:(BOOL)selectable
{
    _cFlags.selectable = selectable;
    if (!selectable)
        _cFlags.editable = NO;
    _cFlags.wasSelectable = selectable;
}

- (BOOL)isHighlighted
{
    return _cFlags.highlighted;
}

- (BOOL)isContinuous
{
    return _cFlags.continuous;
}

- (void)setContinuous:(BOOL)continuous
{
    _cFlags.continuous = continuous;
}

- (BOOL)isScrollable
{
    return _cFlags.scrollable;
}

- (BOOL)wraps
{
    return !_cFlags.noWrap;
}

- (BOOL)isBordered
{
    return _cFlags.bordered;
}

- (void)setBordered:(BOOL)bordered
{
    if (_cFlags.bordered == bordered && !_cFlags.bezeled)
        return;
    _cFlags.bordered = bordered;
    _cFlags.bezeled = NO;
    [(NSControl *)[self controlView] updateCell:self];
}

- (BOOL)isBezeled
{
    return _cFlags.bezeled;
}

- (void)setBezeled:(BOOL)bezeled
{
    if (_cFlags.bezeled == bezeled && !_cFlags.bordered)
        return;
    _cFlags.bezeled = bezeled;
    _cFlags.bordered = NO;
    [(NSControl *)[self controlView] updateCell:self];
}

- (BOOL)allowsEditingTextAttributes
{
    return _cFlags.allowsEditingTextAttributes;
}

- (void)setAllowsEditingTextAttributes:(BOOL)allowsEditingTextAttributes
{
    _cFlags.allowsEditingTextAttributes = allowsEditingTextAttributes;
    if (!allowsEditingTextAttributes)
        _cFlags.importsGraphics = NO;
}

- (BOOL)importsGraphics
{
    return _cFlags.importsGraphics;
}

- (void)setImportsGraphics:(BOOL)importsGraphics
{
    _cFlags.importsGraphics = importsGraphics;
    if (importsGraphics)
        _cFlags.allowsEditingTextAttributes = YES;
}

- (BOOL)sendsActionOnEndEditing
{
    return _cFlags.sendsActionOnEndEditing;
}

- (void)setSendsActionOnEndEditing:(BOOL)sendsActionOnEndEditing
{
    _cFlags.sendsActionOnEndEditing = sendsActionOnEndEditing;
}

- (BOOL)refusesFirstResponder
{
    return _cFlags.refusesFirstResponder;
}

- (void)setRefusesFirstResponder:(BOOL)refusesFirstResponder
{
    _cFlags.refusesFirstResponder = refusesFirstResponder;
}

- (BOOL)showsFirstResponder
{
    return _cFlags.showsFirstResponder;
}

- (void)setShowsFirstResponder:(BOOL)showsFirstResponder
{
    _cFlags.showsFirstResponder = showsFirstResponder;
}

- (NSUInteger)mnemonicLocation
{
    return _cFlags.mnemonicLocation == 0xFF
        ? (NSUInteger)0x7FFFFFFF
        : _cFlags.mnemonicLocation;
}

- (void)setMnemonicLocation:(NSUInteger)location
{
    _cFlags.mnemonicLocation =
        (location == (NSUInteger)0x7FFFFFFF || location > 0xFE) ? 0xFF : location;
}

- (BOOL)acceptsFirstResponder
{
    return !_cFlags.refusesFirstResponder && [self isEnabled];
}

- (NSFormatter *)formatter
{
    return NSCellFormatters ? NSMapGet(NSCellFormatters, self) : nil;
}

- (void)setFormatter:(NSFormatter *)formatter
{
    NSFormatter *oldFormatter = [self formatter];
    if (formatter == oldFormatter)
        return;

    if (formatter) {
        id objectValue = [self objectValue];
        if (_NSAppKitGlobalLock)
            _NSAppKitLock(1386, "NSCell.m");
        if (!NSCellFormatters)
            NSCellFormatters = NSCreateMapTableWithZone(
                NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 0,
                NSDefaultMallocZone());
        if (_NSAppKitGlobalLock)
            _NSAppKitUnlock(1394, "NSCell.m");
        NSMapInsert(NSCellFormatters, self, formatter);

        if (objectValue && ![formatter stringForObjectValue:objectValue]) {
            if (oldFormatter)
                [self setObjectValue:[oldFormatter stringForObjectValue:objectValue]];
            else
                _cFlags.hasInvalidObject = YES;
        }
    } else if (NSCellFormatters) {
        NSMapRemove(NSCellFormatters, self);
    }
}

- (BOOL)isEntryAcceptable:(NSString *)string
{
    id objectValue = nil;
    NSFormatter *formatter = [self formatter];
    if (formatter)
        return [formatter getObjectValue:&objectValue forString:string errorDescription:NULL];
    return YES;
}

- (id)_formatObjectValue:(id)objectValue invalid:(BOOL)invalid
{
    if (invalid) {
        if ([objectValue isKindOfClass:[NSString class]])
            return objectValue;
        if ([objectValue isKindOfClass:[NSAttributedString class]])
            return [objectValue string];
        if (!objectValue)
            return @"";
        NSLog(@"NSCell cannot format invalid object value %@", objectValue);
        return @"";
    }

    if (!objectValue)
        return @"";
    NSFormatter *formatter = [self formatter];
    if (formatter)
        return [formatter stringForObjectValue:objectValue] ?: @"";
    if ([objectValue isKindOfClass:[NSString class]])
        return objectValue;
    if ([objectValue isKindOfClass:[NSAttributedString class]])
        return [objectValue string];
    return [objectValue description];
}

- (BOOL)_objectValue:(id *)objectValue forString:(NSString *)string
{
    if (objectValue)
        *objectValue = nil;
    if (!string)
        return NO;

    NSFormatter *formatter = [self formatter];
    if (formatter)
        return [formatter getObjectValue:objectValue forString:string errorDescription:NULL];
    if (objectValue)
        *objectValue = [[string copy] autorelease];
    return YES;
}

- (NSString *)stringValue
{
    return [self _formatObjectValue:_contents invalid:_cFlags.hasInvalidObject];
}

- (void)setStringValue:(NSString *)stringValue
{
    id objectValue = nil;
    BOOL valid = [self _objectValue:&objectValue forString:stringValue];
    id contents = valid ? objectValue : stringValue;

    if (_cFlags.type == NSTextCellType)
        [self _setContents:contents];
    else
        [self setObjectValue:contents];
    _cFlags.hasInvalidObject = !valid;
}

- (int)intValue
{
    if (_cFlags.type != NSTextCellType)
        return 0;
    if ([_contents isKindOfClass:[NSNumber class]])
        return [_contents intValue];
    return [[self stringValue] intValue];
}

- (void)setIntValue:(int)intValue
{
    NSNumber *number;
    if (_cFlags.type != NSTextCellType)
        return;
    number = [NSNumber numberWithInt:intValue];
    if (![number isEqual:_contents])
        [self setObjectValue:number];
}

- (double)doubleValue
{
    if (_cFlags.type != NSTextCellType)
        return 0.0;
    if ([_contents isKindOfClass:[NSNumber class]])
        return [_contents doubleValue];
    return [[self stringValue] doubleValue];
}

- (void)setDoubleValue:(double)doubleValue
{
    NSNumber *number;
    if (_cFlags.type != NSTextCellType)
        return;
    number = [NSNumber numberWithDouble:doubleValue];
    if (![number isEqual:_contents])
        [self setObjectValue:number];
}

- (float)floatValue
{
    return [self doubleValue];
}

- (void)setFloatValue:(float)floatValue
{
    [self setDoubleValue:floatValue];
}

- (void)takeIntValueFrom:(id)sender
{
    [self setIntValue:[sender intValue]];
}

- (void)takeFloatValueFrom:(id)sender
{
    [self setFloatValue:[sender floatValue]];
}

- (void)takeDoubleValueFrom:(id)sender
{
    [self setDoubleValue:[sender doubleValue]];
}

- (void)takeStringValueFrom:(id)sender
{
    [self setStringValue:[sender stringValue]];
}

- (void)takeObjectValueFrom:(id)sender
{
    [self setObjectValue:[sender objectValue]];
}

- (NSDictionary *)_textAttributes
{
    NSFont *font = [self font];
    if (!font)
        font = [NSFont messageFontOfSize:12.0f];

    NSColor *color = [self isEnabled]
        ? [NSColor controlTextColor]
        : [NSColor disabledControlTextColor];
    NSMutableParagraphStyle *paragraphStyle =
        [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [paragraphStyle setAlignment:[self alignment]];
    [paragraphStyle setLineBreakMode:[self wraps]
        ? NSLineBreakByWordWrapping : NSLineBreakByClipping];

    id objects[] = { font, color, paragraphStyle };
    id keys[] = {
        NSFontAttributeName,
        NSForegroundColorAttributeName,
        NSParagraphStyleAttributeName
    };
    NSDictionary *attributes =
        [NSDictionary dictionaryWithObjects:objects forKeys:keys count:3];
    [paragraphStyle release];
    return attributes;
}

- (NSAttributedString *)_unformattedAttributedStringValue:(id)objectValue
{
    if (!objectValue)
        objectValue = @"";
    if ([objectValue isKindOfClass:[NSAttributedString class]])
        return objectValue;

    NSString *string = [objectValue isKindOfClass:[NSString class]]
        ? objectValue : [NSString stringWithFormat:@"%@", objectValue];
    return [[[NSAttributedString alloc] initWithString:string
        attributes:[self _textAttributes]] autorelease];
}

- (NSAttributedString *)_attributedStringValue:(id)objectValue invalid:(BOOL)invalid
{
    if (!objectValue || invalid)
        return [self _unformattedAttributedStringValue:objectValue];

    NSFormatter *formatter = [self formatter];
    if (!formatter)
        return [self _unformattedAttributedStringValue:objectValue];

    NSAttributedString *attributedString =
        [formatter attributedStringForObjectValue:objectValue
            withDefaultAttributes:[self _textAttributes]];
    if (attributedString)
        return attributedString;

    NSString *editingString = [formatter editingStringForObjectValue:objectValue];
    if (!editingString)
        return [self _unformattedAttributedStringValue:objectValue];
    return [[[NSAttributedString alloc] initWithString:editingString
        attributes:[self _textAttributes]] autorelease];
}

- (NSAttributedString *)attributedStringValue
{
    return [self _attributedStringValue:_contents invalid:_cFlags.hasInvalidObject];
}

- (void)setAttributedStringValue:(NSAttributedString *)attributedStringValue
{
    id objectValue = attributedStringValue;
    NSFormatter *formatter = [self formatter];
    if (formatter) {
        BOOL valid = [self _objectValue:&objectValue
            forString:[attributedStringValue string]];
        _cFlags.hasInvalidObject = !valid;
        if (!valid)
            objectValue = attributedStringValue;
    } else {
        _cFlags.hasInvalidObject = NO;
    }

    if (_cFlags.type == NSTextCellType)
        [self _setContents:objectValue];
    else
        [self setObjectValue:objectValue];
}

- (BOOL)hasValidObjectValue
{
    return !_cFlags.hasInvalidObject;
}

- (id)objectValue
{
    if (_cFlags.hasInvalidObject)
        return nil;
    return [self _contents];
}

- (void)setObjectValue:(id)objectValue
{
    _cFlags.hasInvalidObject = NO;
    [self _setContents:objectValue];
}

- (NSImage *)image
{
    if (_cFlags.type == NSImageCellType)
        return (NSImage *)_support;
    return nil;
}

- (void)setImage:(NSImage *)image
{
    if (image) {
        if (_cFlags.type != NSImageCellType || ![[self image] isEqual:image]) {
            _cFlags.type = NSImageCellType;
            [_support release];
            _support = [image retain];
        }
    } else if (_cFlags.type == NSImageCellType) {
        [_support release];
        _support = nil;
    }
}

- (NSFont *)font
{
    return _cFlags.type == NSTextCellType ? (NSFont *)_support : nil;
}

- (void)setFont:(NSFont *)font
{
    NSFont *defaultFont;

    if (font) {
        if (_cFlags.type != NSTextCellType || !_support) {
            [_support release];
            _support = nil;
            _cFlags.type = NSTextCellType;
        }
        if (![_support isEqual:font]) {
            [_support release];
            _support = [font retain];
        }
    } else if (_cFlags.type == NSTextCellType) {
        defaultFont = [NSFont messageFontOfSize:12.0f];
        if (![_support isEqual:defaultFont]) {
            [_support release];
            _support = [defaultFont retain];
        }
    }
}

- (BOOL)isOpaque
{
    return _cFlags.bezeled;
}

- (NSRect)drawingRectForBounds:(NSRect)bounds
{
    CGFloat inset = 0.0f;
    if (_cFlags.bordered || _cFlags.bezeled)
        inset = _cFlags.bezeled ? 2.0f : 3.0f;
    return NSInsetRect(bounds, inset, inset);
}

- (NSRect)titleRectForBounds:(NSRect)bounds
{
    CGFloat inset = 0.0f;
    if (_cFlags.bordered || _cFlags.bezeled)
        inset = _cFlags.bezeled ? 2.0f : 3.0f;
    if (_cFlags.type == NSTextCellType)
        return NSInsetRect(bounds, inset, inset);
    return bounds;
}

- (NSRect)imageRectForBounds:(NSRect)bounds
{
    NSImage *image = [self image];
    NSSize imageSize;
    NSRect contentRect;
    CGFloat inset = 0.0f;

    if (!image)
        return bounds;
    if (_cFlags.bordered || _cFlags.bezeled)
        inset = _cFlags.bezeled ? 2.0f : 3.0f;

    contentRect = NSInsetRect(bounds, inset, inset);
    imageSize = [image size];
    return NSMakeRect(contentRect.origin.x + (contentRect.size.width - imageSize.width) / 2.0f,
        contentRect.origin.y + (contentRect.size.height - imageSize.height) / 2.0f,
        imageSize.width, imageSize.height);
}

- (void)calcDrawInfo:(NSRect)rect
{
}

- (NSTextAlignment)alignment
{
    return _cFlags.alignment;
}

- (BOOL)_allowsContextMenus
{
    return YES;
}

- (id)_contents
{
    return _contents;
}

- (void)_setContents:(id)contents
{
    if (_contents == contents)
        return;

    if (_NSAppKitGlobalLock)
        _NSAppKitLock(872, "NSCell.m");
    id oldContents = _contents;
    _contents = contents ? [contents copyWithZone:[self zone]] : nil;
    [oldContents release];
    if (_NSAppKitGlobalLock)
        _NSAppKitUnlock(882, "NSCell.m");
}

- (BOOL)_highlightsWithHighlightRect
{
    return YES;
}

- (BOOL)_prefersTrackingWhenDisabled
{
    return NO;
}

- (id)_useUserKeyEquivalent
{
    _cFlags.useUserKeyEquivalent = YES;
    return self;
}

- (BOOL)_usesUserKeyEquivalent
{
    return _cFlags.useUserKeyEquivalent;
}

@end

@implementation NSCell (NSCellMixedState)

- (BOOL)allowsMixedState
{
    return _cFlags.allowsMixedState;
}

- (void)setAllowsMixedState:(BOOL)allowsMixedState
{
    _cFlags.allowsMixedState = allowsMixedState;
}

@end

