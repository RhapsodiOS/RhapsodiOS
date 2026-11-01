/*	NSColorPicker.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSColorPicker.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <Foundation/NSBundle.h>

@interface NSColorPicker (NSColorPickerPrivate)
- (id)_getTiffImage:(id)image ownedBy:(id)owner;
- (id)_getTiffImage:(id)image ownedBy:(id)owner asImageRep:(BOOL)asImageRep;
- (float)_insertionOrder;
@end

@implementation NSColorPicker

- (id)initWithPickerMask:(int)mask colorPanel:(NSColorPanel *)owningColorPanel
{
    self = [super init];
    if (self != nil)
        _colorPanel = owningColorPanel;
    return self;
}

- (NSColorPanel *)colorPanel
{
    return _colorPanel;
}

- (NSImage *)provideNewButtonImage
{
    if (_imageObject == nil) {
        id imageName = [[self class] performSelector:@selector(buttonImage)];
        _imageObject = [[self _getTiffImage:imageName ownedBy:[self class]] retain];
    }
    return _imageObject;
}

- (void)insertNewButtonImage:(NSImage *)newButtonImage in:(NSButtonCell *)buttonCell
{
    [buttonCell setImage:newButtonImage];
}

- (void)viewSizeChanged:(id)sender
{
}

- (void)alphaControlAddedOrRemoved:(id)sender
{
}

- (void)attachColorList:(NSColorList *)colorList
{
}

- (void)detachColorList:(NSColorList *)colorList
{
}

- (void)setMode:(int)mode
{
}

- (float)_insertionOrder
{
    return 0.0f;
}

- (id)_getTiffImage:(id)image ownedBy:(id)owner
{
    return [self _getTiffImage:image ownedBy:owner asImageRep:NO];
}

- (id)_getTiffImage:(id)image ownedBy:(id)owner asImageRep:(BOOL)asImageRep
{
    if (image == nil)
        return nil;

    NSData *imageData = nil;
    if ([image respondsToSelector:@selector(TIFFRepresentation)]) {
        imageData = [image TIFFRepresentation];
    } else if ([image isKindOfClass:[NSString class]]) {
        NSBundle *bundle = [NSBundle bundleForClass:owner];
        NSString *path = [bundle pathForImageResource:image];
        if (path == nil)
            path = [[NSBundle mainBundle] pathForImageResource:image];
        if (path != nil) {
            NSImage *loadedImage = [[NSImage alloc] initWithContentsOfFile:path];
            imageData = [loadedImage TIFFRepresentation];
            [loadedImage release];
        }
    }

    if (imageData == nil)
        return nil;
    if (asImageRep)
        return [NSBitmapImageRep imageRepWithData:imageData];
    return [[[NSImage alloc] initWithData:imageData] autorelease];
}

@end

