/*	NSImageCell.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSImageCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/psops.h>
#import <Foundation/NSException.h>

static NSRect NSImageCellInsetRect(NSRect rect, NSImageFrameStyle style, BOOL flipped)
{
    if (style == NSImageFramePhoto) {
        rect.origin.x += 1.0f;
        rect.origin.y += flipped ? 1.0f : 2.0f;
        rect.size.width -= 3.0f;
        rect.size.height -= 3.0f;
    } else if (style != NSImageFrameNone && style <= NSImageFrameButton) {
        rect = NSInsetRect(rect, 2.0f, 2.0f);
    }
    return rect;
}

static NSImageAlignment NSImageCellFlippedAlignment(NSImageAlignment alignment, BOOL flipped)
{
    if (!flipped)
        return alignment;
    switch (alignment) {
        case NSImageAlignTop: return NSImageAlignBottom;
        case NSImageAlignTopLeft: return NSImageAlignBottomLeft;
        case NSImageAlignTopRight: return NSImageAlignBottomRight;
        case NSImageAlignBottom: return NSImageAlignTop;
        case NSImageAlignBottomLeft: return NSImageAlignTopLeft;
        case NSImageAlignBottomRight: return NSImageAlignTopRight;
        default: return alignment;
    }
}

@implementation NSImageCell

- (NSImage *)image
{
    return (NSImage *)_contents;
}

- (void)setImage:(NSImage *)image
{
    [self setObjectValue:image];
}

- (void)setObjectValue:(id)objectValue
{
    if (objectValue && ![objectValue isKindOfClass:[NSImage class]])
        [NSException raise:NSInvalidArgumentException
                    format:@"NSImageCell's object value must be an NSImage."];

    [_scaledImage release];
    _scaledImage = nil;
    [super setObjectValue:objectValue];
}

- (NSImageAlignment)imageAlignment
{
    return _align;
}

- (void)setImageAlignment:(NSImageAlignment)imageAlignment
{
    _align = imageAlignment;
}

- (NSImageScaling)imageScaling
{
    return _scale;
}

- (void)setImageScaling:(NSImageScaling)imageScaling
{
    _scale = imageScaling;
}

- (NSImageFrameStyle)imageFrameStyle
{
    return _style;
}

- (void)setImageFrameStyle:(NSImageFrameStyle)imageFrameStyle
{
    _style = imageFrameStyle;
}

- (BOOL)isOpaque
{
    return _style == NSImageFrameGrayBezel
        || _style == NSImageFrameGroove
        || _style == NSImageFrameButton;
}

- (NSSize)cellSizeForBounds:(NSRect)bounds
{
    if (_style == NSImageFramePhoto)
        return NSMakeSize(6.0f, 6.0f);
    if (_style > NSImageFrameNone && _style <= NSImageFrameButton)
        return NSMakeSize(4.0f, 4.0f);
    return NSMakeSize(0.0f, 0.0f);
}

- (NSRect)drawingRectForBounds:(NSRect)bounds
{
    CGFloat inset = 0.0f;
    if (_style == NSImageFramePhoto)
        inset = 3.0f;
    else if (_style > NSImageFrameNone && _style <= NSImageFrameButton)
        inset = 2.0f;
    return NSMakeRect(bounds.origin.x + inset, bounds.origin.y + inset,
                      bounds.size.width - inset * 2.0f,
                      bounds.size.height - inset * 2.0f);
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    switch (_style) {
        case NSImageFramePhoto: {
            CGFloat x = frame.origin.x;
            CGFloat y = frame.origin.y;
            CGFloat width = frame.size.width;
            CGFloat height = frame.size.height;
            NSRect rects[5] = {
                NSMakeRect(x, y, width, 1.0f),
                NSMakeRect(x, y + 1.0f, 1.0f, height - 1.0f),
                NSMakeRect(x + width - 1.0f, y, 1.0f, height),
                NSMakeRect(x, y + height - 1.0f, width, 1.0f),
                NSMakeRect(x + 1.0f, y + 1.0f, width - 2.0f, 1.0f)
            };
            NSColor *colors[5] = {
                [NSColor controlHighlightColor],
                [NSColor controlDarkShadowColor],
                [NSColor controlShadowColor],
                [NSColor controlShadowColor],
                [NSColor controlHighlightColor]
            };
            NSRectFillListWithColors(rects, colors, 5);
            break;
        }
        case NSImageFrameGrayBezel:
            NSDrawDarkBezel(frame, frame);
            break;
        case NSImageFrameGroove:
            NSDrawGroove(frame, frame);
            break;
        case NSImageFrameButton:
            NSDrawButton(frame, frame);
            break;
        default:
            break;
    }
    [self drawInteriorWithFrame:frame inView:view];
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    if (!_contents)
        return;

    BOOL flipped = [view isFlipped];
    NSRect imageRect = NSImageCellInsetRect(frame, _style, flipped);
    PSgsave();
    NSRectClip(imageRect);

    NSSize imageSize = [_contents size];
    NSSize drawSize = imageSize;
    BOOL resize = NO;
    if (_scale == NSScaleToFit) {
        drawSize = imageRect.size;
        resize = YES;
    } else if (_scale == NSScaleProportionally
               && (imageSize.width > imageRect.size.width
                   || imageSize.height > imageRect.size.height)) {
        CGFloat factor = imageRect.size.height / imageSize.height;
        CGFloat widthFactor = imageRect.size.width / imageSize.width;
        if (widthFactor < factor)
            factor = widthFactor;
        drawSize.width *= factor;
        drawSize.height *= factor;
        resize = YES;
    }

    NSImage *image = _contents;
    if (resize) {
        if (!_scaledImage || !NSEqualSizes([_scaledImage size], drawSize)) {
            [_scaledImage release];
            _scaledImage = [_contents copyWithZone:NULL];
            [_scaledImage setScalesWhenResized:YES];
            [_scaledImage setSize:drawSize];
        }
        image = _scaledImage;
    }

    NSImageAlignment alignment = NSImageCellFlippedAlignment(_align, flipped);
    NSPoint point;
    switch (alignment) {
        case NSImageAlignTop:
            point = NSMakePoint(imageRect.origin.x + (imageRect.size.width - drawSize.width) / 2.0f,
                                NSMaxY(imageRect) - drawSize.height);
            break;
        case NSImageAlignTopLeft:
            point = NSMakePoint(imageRect.origin.x, NSMaxY(imageRect) - drawSize.height);
            break;
        case NSImageAlignTopRight:
            point = NSMakePoint(NSMaxX(imageRect) - drawSize.width,
                                NSMaxY(imageRect) - drawSize.height);
            break;
        case NSImageAlignLeft:
            point = NSMakePoint(imageRect.origin.x,
                                imageRect.origin.y + (imageRect.size.height - drawSize.height) / 2.0f);
            break;
        case NSImageAlignBottom:
            point = NSMakePoint(imageRect.origin.x + (imageRect.size.width - drawSize.width) / 2.0f,
                                imageRect.origin.y);
            break;
        case NSImageAlignBottomLeft:
            point = imageRect.origin;
            break;
        case NSImageAlignBottomRight:
            point = NSMakePoint(NSMaxX(imageRect) - drawSize.width, imageRect.origin.y);
            break;
        case NSImageAlignRight:
            point = NSMakePoint(NSMaxX(imageRect) - drawSize.width,
                                imageRect.origin.y + (imageRect.size.height - drawSize.height) / 2.0f);
            break;
        case NSImageAlignCenter:
        default:
            point = NSMakePoint(imageRect.origin.x + (imageRect.size.width - drawSize.width) / 2.0f,
                                imageRect.origin.y + (imageRect.size.height - drawSize.height) / 2.0f);
            break;
    }

    if (flipped) {
        NSSize convertedSize = [view convertSize:drawSize toView:nil];
        if (convertedSize.height < 0.0f)
            convertedSize.height = -convertedSize.height;
        point.y += convertedSize.height;
    }

    [image compositeToPoint:point operation:NSCompositeSourceOver];
    PSgrestore();
}

- (NSRect)imageRectForBounds:(NSRect)bounds
{
    return bounds;
}

- (NSRect)titleRectForBounds:(NSRect)bounds
{
    return bounds;
}

- (BOOL)_highlightsWithHighlightRect
{
    return NO;
}

- (void)highlight:(BOOL)flag withFrame:(NSRect)frame inView:(NSView *)view
{
}

- (BOOL)trackMouse:(NSEvent *)event
             inRect:(NSRect)cellFrame
             ofView:(NSView *)controlView
      untilMouseUp:(BOOL)untilMouseUp
{
    return NO;
}

- (void)setFormatter:(NSFormatter *)formatter
{
}

- (void)_setContents:(id)contents
{
    if (_contents == contents)
        return;
    [_contents release];
    _contents = [contents retain];
}

@end

