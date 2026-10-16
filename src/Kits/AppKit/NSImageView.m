/*	NSImageView.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSImageView.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSDragging.h>

@interface NSImageView (NSImageViewPrivate)
- (void)registerForDrags;
@end

@implementation NSImageView

+ (void)initialize
{
    if (self == [NSImageView class]) {
        [self setCellClass:[NSImageCell class]];
        [self setVersion:26];
    }
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _editable = YES;
        [self registerForDrags];
    }
    return self;
}

- (NSImage *)image
{
    return [[self cell] image];
}

- (void)setImage:(NSImage *)image
{
    [[self cell] setImage:image];
    [self setNeedsDisplay:YES];
}

- (NSImageAlignment)imageAlignment
{
    return [(NSImageCell *)[self cell] imageAlignment];
}

- (void)setImageAlignment:(NSImageAlignment)alignment
{
    [(NSImageCell *)[self cell] setImageAlignment:alignment];
    [self setNeedsDisplay:YES];
}

- (NSImageScaling)imageScaling
{
    return [(NSImageCell *)[self cell] imageScaling];
}

- (void)setImageScaling:(NSImageScaling)scaling
{
    [(NSImageCell *)[self cell] setImageScaling:scaling];
    [self setNeedsDisplay:YES];
}

- (NSImageFrameStyle)imageFrameStyle
{
    return [(NSImageCell *)[self cell] imageFrameStyle];
}

- (void)setImageFrameStyle:(NSImageFrameStyle)style
{
    [(NSImageCell *)[self cell] setImageFrameStyle:style];
    [self setNeedsDisplay:YES];
}

- (BOOL)isEditable
{
    return _editable;
}

- (void)setEditable:(BOOL)editable
{
    _editable = editable;
}

- (BOOL)isOpaque
{
    NSCell *cell = [self cell];
    return cell ? [cell isOpaque] : NO;
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

- (unsigned int)draggingEntered:(id<NSDraggingInfo>)sender
{
    if (!_editable)
        return NSDragOperationNone;

    NSPasteboard *pasteboard = [sender draggingPasteboard];
    if (![NSImage canInitWithPasteboard:pasteboard])
        return NSDragOperationNone;

    return [sender draggingSourceOperationMask]
        & (NSDragOperationCopy | NSDragOperationGeneric);
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    return ([sender draggingSourceOperationMask]
        & (NSDragOperationCopy | NSDragOperationGeneric)) != 0;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender
{
    unsigned int operation = [sender draggingSourceOperationMask];
    if (!(operation & (NSDragOperationCopy | NSDragOperationGeneric)))
        return;

    NSImage *image = [[[NSImage alloc] initWithPasteboard:[sender draggingPasteboard]] autorelease];
    if (image) {
        [self setImage:image];
        [self sendAction:_action to:_target];
    }
}

@end

@implementation NSImageView (NSImageViewPrivate)

- (void)registerForDrags
{
    [self registerForDraggedTypes:[NSImage imagePasteboardTypes]];
}

@end
