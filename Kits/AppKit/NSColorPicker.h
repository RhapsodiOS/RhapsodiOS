/*
	NSColorPicker.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSColorPicking.h>
#import <AppKit/NSColorPanel.h>

@class NSButtonCell;

@interface NSColorPicker : NSObject <NSColorPickingDefault>
{
    /*All instance variables are private*/
    id _imageObject;
    NSColorPanel *_colorPanel;
    unsigned int reservedColorPicker;
}
- (id)initWithPickerMask:(int)mask colorPanel:(NSColorPanel *)owningColorPanel;
- (NSColorPanel *)colorPanel;
- (NSImage *)provideNewButtonImage;
- (void)insertNewButtonImage:(NSImage *)newButtonImage in:(NSButtonCell *)buttonCell;
- (void)viewSizeChanged:(id)sender;
- (void)attachColorList:(NSColorList *)colorList;
- (void)detachColorList:(NSColorList *)colorList;
- (void)setMode:(int)mode;

@end
