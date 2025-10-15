/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
	SoundView.h
	Sound Kit, Release 3.0
	Copyright (c) 1988, 1989, 1990, 1991, NeXT, Inc.  All rights reserved. 
*/

#import <AppKit/NSView.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/Foundation.h>

@class NSEvent;

@interface SoundView : NSView {
    Sound *sound;
    id _private;		/* 3.0 */
    id delegate;
    NSRect selectionRect;
    int displayMode;
    NSColor *backgroundColor;
    NSColor *foregroundColor;
    float reductionFactor;
    struct {
	unsigned int disabled:1;
	unsigned int continuous:1;
	unsigned int calcDrawInfo:1;
	unsigned int selectionDirty:1;
	unsigned int autoscale:1;
	unsigned int bezeled:1;
	unsigned int notEditable:1;
	unsigned int notOptimizedForSpeed:1;	/* 3.0 */
	unsigned int _reservedFlags:8;
    } svFlags;
    Sound *_scratchSound;
    int _currentSample;
}

/*
 * Display modes
 */
#define NX_SOUNDVIEW_MINMAX 0
#define NX_SOUNDVIEW_WAVE 1

/*
 * OBSOLETE display modes - use the NX ones above.
 */
#define SK_DISPLAY_MINMAX 0
#define SK_DISPLAY_WAVE 1

+ (void)initialize;
- (id)initWithFrame:(NSRect)aRect;
- (void)dealloc;
- (void)encodeWithCoder:(NSCoder *)stream;
- (id)initWithCoder:(NSCoder *)stream;
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
- (void)pasteboard:(NSPasteboard *)sender provideData:(NSString *)type;
- (Sound *)sound;
- (void)setSound:(Sound *)aSound; // Should be BOOL; affects NSButton
- (BOOL)setReductionFactor:(float)reductionFactor;
- (float)reductionFactor;
- (void)setFrameSize:(NSSize)newSize;
- (id)delegate;
- (void)setDelegate:(id)anObject;
- (void)tellDelegate:(SEL)theMessage;
- (void)getSelection:(int *)firstSample size:(int *)sampleCount;
- (void)setSelection:(int)firstSample size:(int)sampleCount;
- (void)hideCursor;
- (void)showCursor;
- (void)setBackgroundColor:(NSColor *)color;
- (NSColor *)backgroundColor;
- (void)setForegroundColor:(NSColor *)color;
- (NSColor *)foregroundColor;
- (int)displayMode;
- (void)setDisplayMode:(int)aMode;
- (BOOL)isContinuous;
- (void)setContinuous:(BOOL)aFlag;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)aFlag;
- (BOOL)isEditable;
- (void)setEditable:(BOOL)aFlag;
- (BOOL)isPlayable;
- (BOOL)isBezeled;
- (void)setBezeled:(BOOL)aFlag;
- (BOOL)isAutoScale;
- (void)setAutoscale:(BOOL)aFlag;
- (BOOL)isOptimizedForSpeed;		/* 3.0 */
- (void)setOptimizedForSpeed:(BOOL)aFlag;	/* 3.0 */
- (void)scaleToFit;
- (void)sizeToFit;
- (BOOL)drawSamplesFrom:(int)startX to:(int)endX;	/* 3.0 */
- (void)drawRect:(NSRect)rects;
- (void)mouseDown:(NSEvent *)theEvent;
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder; 
- (BOOL)resignFirstResponder; 
- (void)selectAll:(id)sender;
- (void)delete:(id)sender;
- (void)cut:(id)sender;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)play:(id)sender;
- (void)record:(id)sender;
- (void)stop:(id)sender;
- (void)pause:(id)sender;
- (void)resume:(id)sender;
- (id)soundBeingProcessed;
- (void)willPlay:(id)sender;
- (void)didPlay:(id)sender;
- (void)willRecord:(id)sender;
- (void)didRecord:(id)sender;
- (void)hadError:(id)sender;
@end

@interface SoundViewDelegate : NSObject
- (void)soundDidChange:(id)sender;
- (void)selectionDidChange:(id)sender;
- (void)willRecord:(id)sender;
- (void)didRecord:(id)sender;
- (void)willPlay:(id)sender;
- (void)didPlay:(id)sender;
- (void)hadError:(id)sender;
- (void)willFree:(id)sender;
@end

