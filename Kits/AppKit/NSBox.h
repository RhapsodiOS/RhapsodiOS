/*
	NSBox.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSView.h>

@class NSCell;
@class NSFont;

typedef enum _NSTitlePosition {
    NSNoTitle				= 0,
    NSAboveTop				= 1,
    NSAtTop				= 2,
    NSBelowTop				= 3,
    NSAboveBottom			= 4,
    NSAtBottom				= 5,
    NSBelowBottom			= 6
} NSTitlePosition;

@interface NSBox : NSView
{
    /*All instance variables are private*/
    id                  _titleCell;
    id                  _contentView;
    NSSize              _offsets;
    NSRect              _borderRect;
    NSRect              _titleRect;
    struct __bFlags {
	NSBorderType	borderType:2;
	NSTitlePosition	titlePosition:3;
	unsigned int	transparent:1;
	unsigned int	_RESERVED:26;
    } _bFlags;
    id			_unused;
}

- (NSBorderType)borderType;
- (NSTitlePosition)titlePosition;
- (void)setBorderType:(NSBorderType)aType;
- (void)setTitlePosition:(NSTitlePosition)aPosition;
- (NSString *)title;
- (void)setTitle:(NSString *)aString;
- (NSFont *)titleFont;
- (void)setTitleFont:(NSFont *)fontObj;
- (NSRect)borderRect;
- (NSRect)titleRect;
- (id)titleCell;
- (void)sizeToFit;
- (NSSize)contentViewMargins;
- (void)setContentViewMargins:(NSSize)offsetSize;
- (void)setFrameFromContentFrame:(NSRect)contentFrame;
- (id)contentView;
- (void)setContentView:(NSView *)aView;

@end

@interface NSBox(NSKeyboardUI)
- (void)setTitleWithMnemonic:(NSString *)stringWithAmpersand;
@end
