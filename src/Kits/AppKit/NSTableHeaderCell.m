/*	NSTableHeaderCell.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSTableHeaderCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>

@interface NSTextFieldCell (NSTableHeaderCellPrivate)
- (id)_convertToText:(id)object;
- (void)_drawContents:(NSRect)frame faceColor:(NSColor *)faceColor
            textColor:(NSColor *)textColor inView:(NSView *)controlView;
@end

@implementation NSTableHeaderCell

- (id)_convertToText:(id)object
{
    [super _convertToText:object];
    [self setFont:[NSFont titleBarFontOfSize:-1.0f]];
    return self;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [self _drawContents:cellFrame
              faceColor:[NSColor headerColor]
              textColor:[NSColor headerTextColor]
                 inView:controlView];
}

- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    (void)flag;
    NSColor *faceColor = [[NSColor headerColor] shadowWithLevel:0.2f];
    [self _drawContents:cellFrame
              faceColor:faceColor
              textColor:[NSColor headerTextColor]
                 inView:controlView];
}

- (void)_drawContents:(NSRect)frame
            faceColor:(NSColor *)faceColor
            textColor:(NSColor *)textColor
               inView:(NSView *)controlView
{
    CGFloat x = frame.origin.x;
    CGFloat y = frame.origin.y;
    CGFloat width = frame.size.width;
    CGFloat height = frame.size.height;
    NSRect rects[7] = {
        {{x + 1.0f, y + 1.0f}, {width - 3.0f, height - 3.0f}},
        {{x, y}, {width - 1.0f, 1.0f}},
        {{x, y + 1.0f}, {1.0f, height - 2.0f}},
        {{x + width - 1.0f, y}, {1.0f, height - 1.0f}},
        {{x, y + height - 1.0f}, {width, 1.0f}},
        {{x + width - 2.0f, y + 1.0f}, {1.0f, height - 3.0f}},
        {{x + 1.0f, y + height - 2.0f}, {width - 2.0f, 1.0f}}
    };
    NSColor *colors[7] = {
        faceColor,
        [faceColor highlightWithLevel:2.0f / 3.0f],
        [faceColor highlightWithLevel:2.0f / 3.0f],
        [NSColor blackColor],
        [NSColor blackColor],
        [faceColor shadowWithLevel:0.2f],
        [faceColor shadowWithLevel:0.2f]
    };

    NSRectFillListWithColors(rects, colors, 7);
    [self setTextColor:textColor];
    [self drawInteriorWithFrame:frame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if ([self type] == NSImageCellType) {
        NSImage *image = [self image];
        if (image != nil) {
            NSImageRep *imageRep = [image bestRepresentationForDevice:nil];
            [image drawRepresentation:imageRep inRect:[self imageRectForBounds:cellFrame]];
        }
    } else {
        [super drawInteriorWithFrame:cellFrame inView:controlView];
    }
}

@end

