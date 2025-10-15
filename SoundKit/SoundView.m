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
#ifdef SHLIB
#include "shlib.h"
#endif SHLIB

/*
 *	SoundView.m
 *	Written by Lee Boynton
 *	Copyright 1988-91 NeXT, Inc.
 *
 */
#import <stdlib.h>
#import <string.h>
#import <objc/zone.h>
#import <sound.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSEvent_Private.h>
#import <AppKit/NSPasteboard.h>
#import "NXSoundThreshold_Private.h"
#import <AppKit/obsoleteGraphics.h>
#import <AppKit/psopsOpenStep.h>
#import <AppKit/psopsNeXT.h>		// for instancing wraps
#import <AppKit/NSDPSContextPrivate.h>	//TEMP for TimedEntries
#import <architecture/byte_order.h>

#import "obsolete.h"
#import "Sound.h"
#import "SoundView.h"

#define DEFAULT_PIXELS_PER_SECOND (184.0)
#define MIN_FRAME_WIDTH (32.0)


@implementation SoundView

typedef struct {
    @defs (Sound)
} *soundId;


/*
 * Caret support (only used when the view is the first responder)
 */

#define CURSOR_FLASH_RATE (0.5)
static _NSSKTimedEntry _timedEntry = 0;
static BOOL cursorOn = 0;
static int cursorState = 0;

static void draw_cursor(SoundView *self) {
    [[NSColor lightGrayColor] set];
    PSsetlinewidth(0.0);
    PSmoveto(self->selectionRect.origin.x, self->selectionRect.origin.y);
    PSrlineto(0.0, self->selectionRect.size.height);
    PSstroke();
}

static void toggle_cursor(_NSSKTimedEntry te, double now, void *userData)
{
    SoundView *self = userData;

    [self lockFocus];
    PSsetinstance(1);
    PSnewinstance();
    if (cursorState = !cursorState)
	draw_cursor(self);
    [self unlockFocus];
}

static void startCaret(SoundView *self)
{
    if (!cursorOn) {
	[self lockFocus];
	PSsetinstance(1);
	PSnewinstance();
	draw_cursor(self);
	[self unlockFocus];
	cursorOn = cursorState = 1;
	_timedEntry = _NSSKAddTimedEntry(CURSOR_FLASH_RATE, toggle_cursor, 
					self, NSBaseThreshhold);
    }
}

static void stopCaret(SoundView *self)
{
    if (cursorOn) {
	cursorOn = 0;
	_NSSKRemoveTimedEntry(_timedEntry);
        [self lockFocus];
	PSsetinstance(1);
	PSnewinstance();
	[self unlockFocus];
    }
}

/*
 * Drawing functions
 */

static inline int calcSampleSize(int format)
{
    if (format == SND_FORMAT_LINEAR_16 || format == SND_FORMAT_EMPHASIZED)
	return 2;
    else if (format == SND_FORMAT_MULAW_8 || format == SND_FORMAT_LINEAR_8)
	return 1;
    else if (format == SND_FORMAT_FLOAT || format == SND_FORMAT_LINEAR_32)
	return 4;
    else if (format == SND_FORMAT_DOUBLE)
	return 8;
    else
	return 0;
}

static BOOL _isDisplayable(int fmt)
{
    return (fmt == SND_FORMAT_LINEAR_16 
	    || fmt == SND_FORMAT_EMPHASIZED
	    || fmt == SND_FORMAT_MULAW_8 
	    || fmt == SND_FORMAT_LINEAR_8
	    || fmt == SND_FORMAT_FLOAT
	    || fmt == SND_FORMAT_LINEAR_32
	    || fmt == SND_FORMAT_DOUBLE);
}

static inline short convertSampToShort(int format, void *theSamp)
{
    float scale = 32767.0;

    if (format == SND_FORMAT_LINEAR_16 || format == SND_FORMAT_EMPHASIZED)
	return((short)NXSwapBigShortToHost(*(short *)theSamp));
    else if (format == SND_FORMAT_MULAW_8)
	return(SNDiMulaw(*(unsigned char *)theSamp));
    else if (format == SND_FORMAT_LINEAR_8)
	return((short)(*(char *)theSamp));
    else if (format == SND_FORMAT_FLOAT)
	return((short)(scale *
		       NXSwapBigFloatToHost(*(NXSwappedFloat *)theSamp)));
    else if (format == SND_FORMAT_LINEAR_32)
	return((short)NXSwapBigIntToHost(*(int *)theSamp));
    else if (format == SND_FORMAT_DOUBLE)
	return((short)(scale *
		       NXSwapBigDoubleToHost(*(NXSwappedDouble *)theSamp)));
    else
	return 0;
}

static void screenDrawSamples(int startX, int endX, int *coords)
{
    #define USERPATHSIZE (1024-2)
    char userPathOps[USERPATHSIZE+2];
    int userPathBBox[4];
    int i, *p;
    int xmin = startX, xmax = xmin + USERPATHSIZE-1;
    char *op = userPathOps;

    if (xmax > endX) xmax = endX;

    *op++ = dps_setbbox;
    *op++ = dps_moveto;
    for (i = 0; i < (USERPATHSIZE-1); i++)
        *op++ = dps_lineto;

    p = coords;
    while (xmax <= endX) {
	int count = xmax - xmin;
	userPathBBox[0] = xmin<<1;
	userPathBBox[1] = (-32768)<<1;
	userPathBBox[2] = (xmax<<1)+1;
	userPathBBox[3] = 65535<<1;
	PSDoUserPathWithMatrix(p, count*2, dps_long+1, userPathOps, count+1, userPathBBox, dps_ustroke, NULL);
	if (xmax == endX) break;
	xmin = xmax;
	xmax += USERPATHSIZE-1;
	p += 2*(USERPATHSIZE-1);
	if (xmax > endX) xmax = endX;
    }
}

static void drawSamples(int startX, int endX, int *coords)
{
    int count = endX - startX;
    if (count > 0) {
	float x = (*coords++)/2.0;
	float y = (*coords++)/2.0;
	int i = count-1;
	PSnewpath();
	PSmoveto(x,y);
	while (i--) {
	    x = (*coords++)/2.0;
	    y = (*coords++)/2.0;
	    PSlineto(x,y);
	}
	PSstroke();
    }
}

static int calcResolution(int sampleSize, int channelCount, int reductionFactor)
{
    int i;
    if (reductionFactor < 10)
	return 1;
    i = reductionFactor / 50 + 1;
    return i*sampleSize;
}

static void drawMinMax(Sound *sound, int iReductionFactor, int startX, int endX, BOOL optimize)
{
    static int *minValues=NULL, *maxValues=NULL;
    static int maxPixels = 0;
    SNDSoundStruct *s = [sound soundStruct];
    int startSample = startX * iReductionFactor;
    int channelCount = [sound channelCount];
    int dataFormat = [sound dataFormat];
    int sampleCount = [sound sampleCount];
    int sampleSize = calcSampleSize(dataFormat);
    char *samplePtr = [sound data];
    int resolution = optimize? calcResolution(sampleSize, channelCount, iReductionFactor) : 1;
    int coordCount = 0;
    PSsetlinewidth(0.0);
    if ((endX - startX) > maxPixels) {
	maxPixels = (endX - startX) + 1;
	if (maxPixels < 1024) maxPixels = 1024;
	if (minValues) {
	    minValues = (int *)realloc(minValues, maxPixels*2*sizeof(int));
	    maxValues = (int *)realloc(maxValues, maxPixels*2*sizeof(int));
	} else {
	    minValues = (int *)malloc(maxPixels*2*sizeof(int));
	    maxValues = (int *)malloc(maxPixels*2*sizeof(int));
	}
    }
    
    if (s->dataFormat == SND_FORMAT_INDIRECT) {
	int remainingSamples = sampleCount - startSample - 1;
	int x = (startX<<1) + 1;
	int *minP = minValues, *maxP = maxValues;
	int k = endX - startX + 1;
	char *samplePtrBreak;
	int s2Size;
	SNDSoundStruct *s2, **iBlock = (SNDSoundStruct **)s->dataLocation;
	int temp = startSample;
	s2 = *iBlock++;
	s2Size = s2->dataSize/(sampleSize*channelCount);
	while (temp >= s2Size) {
	    temp -= s2Size;
	    s2 = *iBlock++;
	    s2Size = s2->dataSize/(sampleSize*channelCount);
	}
	samplePtr = (char *)((int)s2+s2->dataLocation);
	samplePtrBreak = (char *)((int)samplePtr + s2->dataSize);
	samplePtr += (temp*channelCount*sampleSize);

	if (k > remainingSamples) k = remainingSamples;
	while (k-- && remainingSamples > 0) {
	    int ch, sample;
	    int min = 32767, max = -32768;
	    int i = iReductionFactor;
	    if (remainingSamples < i) i = remainingSamples;
	    while (i--) {
		ch = channelCount;
		while (ch--) {
		    sample = convertSampToShort(dataFormat,samplePtr);
		    if (sample < min) min = sample;
		    if (sample > max) max = sample;
		    samplePtr += sampleSize;
		}
		if (samplePtr >= samplePtrBreak) {
		    if (s2 = *iBlock++) {
			samplePtr = (char *)((int)s2+s2->dataLocation);
			samplePtrBreak = samplePtr + s2->dataSize;
		    } else {
			iBlock--;
			samplePtr -= sampleSize*channelCount;
		    }
		}
		ch = resolution-1;
		if (ch > i) ch = i;
		while (ch--) {
		    samplePtr += sampleSize*channelCount;
		    i--;
		    if (samplePtr >= samplePtrBreak) {
			if (s2 = *iBlock++) {
			    samplePtr = (char *)((int)s2+s2->dataLocation);
			    samplePtrBreak = samplePtr + s2->dataSize;
			} else {
			    iBlock--;
			    samplePtr -= sampleSize*channelCount;
			}
		    }
		}
	    }
	    *minP++ = x;
	    *minP++ = ((int)min)<<1;
	    *maxP++ = x;
	    *maxP++ = ((int)max)<<1;
	    coordCount++;
	    x += 2;
	    remainingSamples -= iReductionFactor;
	    if (remainingSamples < 0) remainingSamples = 0;
	}
    } else {
	int remainingSamples = sampleCount - startSample - 1;
	int x = (startX<<1) + 1;
	int *minP = minValues, *maxP = maxValues;
	int k = endX - startX + 1;
	samplePtr += (startSample*channelCount*sampleSize);
	if (k > remainingSamples) k = remainingSamples;
	while (k-- && remainingSamples > 0) {
	    int ch, sample;
	    int min = 32767, max = -32768;
	    int i = iReductionFactor;
	    if (remainingSamples < i) i = remainingSamples;
	    while (i-- > 0) {
		ch = channelCount;
		while (ch--) {
		    sample = convertSampToShort(dataFormat,samplePtr);
		    if (sample < min) min = sample;
		    if (sample > max) max = sample;
		    samplePtr += sampleSize;
		}
		ch = resolution-1;
		if (ch > i) ch = i;
		samplePtr += sampleSize*channelCount*ch;
		i -= ch;
	    }
	    *minP++ = x;
	    *minP++ = ((int)min)<<1;
	    *maxP++ = x;
	    *maxP++ = ((int)max)<<1;
	    coordCount++;
	    x += 2;
	    remainingSamples -= iReductionFactor;
	}
    }
    if ([[NSDPSContext currentContext] isDrawingToScreen]) {
	screenDrawSamples(startX, startX+coordCount, minValues);
	screenDrawSamples(startX, startX+coordCount, maxValues);
    } else {
	drawSamples(startX, startX+coordCount, minValues);
	drawSamples(startX, startX+coordCount, maxValues);
    }
}

static void drawWave(Sound *sound, float iReductionFactor, int startX, int endX, BOOL optimize)
{
    static int *values=NULL;
    static int maxPixels = 0;
    SNDSoundStruct *s = [sound soundStruct];
    int startSample = startX * iReductionFactor;
    int channelCount = [sound channelCount];
    int dataFormat = [sound dataFormat];
    int sampleCount = [sound sampleCount];
    int sampleSize = calcSampleSize(dataFormat);
    char *samplePtr = [sound data];
    int resolution = optimize? calcResolution(sampleSize, channelCount, iReductionFactor) : 1;

    PSsetlinewidth(0.0);
    if ((endX - startX) > maxPixels) {
	maxPixels = (endX - startX) + 1;
	if (maxPixels < 1024) maxPixels = 1024;
	if (values) {
	    values = (int *)realloc(values, maxPixels*2*sizeof(int));
	} else {
	    values = (int *)malloc(maxPixels*2*sizeof(int));
	}
    }
    
    if (s->dataFormat == SND_FORMAT_INDIRECT) {
	int remainingSamples = sampleCount - startSample - 1;
	BOOL useMin = YES;
	int x = (startX<<1) + 1;
	int *p = values;
	int k = endX - startX + 1;
	char *samplePtrBreak;
	int s2Size;
	SNDSoundStruct *s2, **iBlock = (SNDSoundStruct **)s->dataLocation;
	int temp = startSample;
	s2 = *iBlock++;
	s2Size = s2->dataSize/(sampleSize*channelCount);
	while (temp >= s2Size) {
	    temp -= s2Size;
	    s2 = *iBlock++;
	    s2Size = s2->dataSize/(sampleSize*channelCount);
	}
	samplePtr = (char *)((int)s2+s2->dataLocation);
	samplePtrBreak = (char *)((int)samplePtr + s2->dataSize);
	samplePtr += (temp*channelCount*sampleSize);

	if (k > remainingSamples) k = remainingSamples;
	while (k-- && remainingSamples > 0) {
	    int ch, sample;
	    int min = 32767, max = -32768;
	    int i = iReductionFactor;
	    if (remainingSamples < i) i = remainingSamples;
	    while (i--) {
		ch = channelCount;
		while (ch--) {
		    sample = convertSampToShort(dataFormat,samplePtr);
		    if (sample < min) min = sample;
		    if (sample > max) max = sample;
		    samplePtr += sampleSize;
		}
		if (samplePtr >= samplePtrBreak) {
		    if (s2 = *iBlock++) {
			samplePtr = (char *)((int)s2+s2->dataLocation);
			samplePtrBreak = samplePtr + s2->dataSize;
		    } else {
			iBlock--;
			samplePtr -= sampleSize*channelCount;
		    }
		}
		ch = resolution-1;
		if (ch > i) ch = i;
		while (ch--) {
		    samplePtr += sampleSize*channelCount;
		    i--;
		    if (samplePtr >= samplePtrBreak) {
			if (s2 = *iBlock++) {
			    samplePtr = (char *)((int)s2+s2->dataLocation);
			    samplePtrBreak = samplePtr + s2->dataSize;
			} else {
			    iBlock--;
			    samplePtr -= sampleSize*channelCount;
			}
		    }
		}
	    }
	    *p++ = x;
	    *p++ = ((int)(useMin? min : max))<<1;
	    useMin = !useMin;
	    x += 2;
	    remainingSamples -= iReductionFactor;
	    if (remainingSamples < 0) remainingSamples = 0;
	}
    } else {
	BOOL useMin = YES;
	int remainingSamples = sampleCount - startSample - 1;
	int x = (startX<<1) + 1;
	int *p = values;
	int k = endX - startX + 1;
	samplePtr += (startSample*channelCount*sampleSize);
	if (k > remainingSamples) k = remainingSamples;
	while (k-- && remainingSamples > 0) {
	    int ch, sample;
	    int min = 32767, max = -32768;
	    int i = iReductionFactor;
	    if (remainingSamples < i) i = remainingSamples;
	    while (i-- > 0) {
		ch = channelCount;
		while (ch--) {
		    sample = convertSampToShort(dataFormat,samplePtr);
		    if (sample < min) min = sample;
		    if (sample > max) max = sample;
		    samplePtr += sampleSize;
		}
		ch = resolution-1;
		if (ch > i) ch = i;
		samplePtr += sampleSize*channelCount*ch;
		i -= ch;
	    }
	    *p++ = x;
	    *p++ = ((int)(useMin? min : max))<<1;
	    useMin = !useMin;
	    x += 2;
	    remainingSamples -= iReductionFactor;
	    if (remainingSamples < 0) remainingSamples = 0;
	}
    }
    if ([[NSDPSContext currentContext] isDrawingToScreen])
	screenDrawSamples(startX, endX, values);
    else
	drawSamples(startX, endX, values);
}


/*
 * Editing functions
 */
static int replaceSelection(SoundView *self, Sound *newSound, BOOL selectIt)
{
    int err;
    int firstSample = (int)(self->selectionRect.origin.x * 
    					(int)self->reductionFactor);
    int sampleCount= (int)(self->selectionRect.size.width * 
    					(int)self->reductionFactor);
    int deltaSampleCount = [newSound sampleCount];
    [self hideCursor];
    [[self window] disableFlushWindow];
    if (self->sound && [self->sound sampleCount]) {
	if (sampleCount) {
	    err = [self->sound deleteSamplesAt:firstSample 
						    count:sampleCount];
	    if (err) goto cannot_delete;
	}
	if ([newSound sampleCount]) {
	    id s;
	    s = [newSound copy];
	    if (![self->sound compatibleWith:s]) {
		err = [s convertToFormat:[self->sound dataFormat]
				  samplingRate:[self->sound samplingRate]
				  channelCount:[self->sound channelCount]];
		if (err) goto cannot_insert;
		deltaSampleCount = [s sampleCount];
	    } else {
		s = newSound;
	    }
	    err = [self->sound insertSamples:s at:firstSample];
	    if (err)
		goto cannot_insert;
	}
    } else {
	if (self->sound) 
	    [self->sound copySound:newSound];
	else
	    self->sound = [newSound copy];
	if (!self->svFlags.autoscale)
	    self->reductionFactor = [self->sound samplingRate] / DEFAULT_PIXELS_PER_SECOND;
	firstSample = 0;
    }
    if (self->svFlags.autoscale)
	[self scaleToFit];
    else
	[self sizeToFit];
    [self tellDelegate:@selector(soundDidChange:)];
    if (selectIt)
	[self setSelection:firstSample size:deltaSampleCount];
    else
	[self setSelection:firstSample+deltaSampleCount size:0];
    err = 0;
 normal_exit:
    [[self window] enableFlushWindow];
    [self setNeedsDisplay:YES];
    return err;
 cannot_insert:
    if (self->svFlags.autoscale)
	[self scaleToFit];
    else
	[self sizeToFit];
    [self tellDelegate:@selector(soundDidChange:)];
 cannot_delete:
    goto normal_exit;
}

/*
 * Methods
 */

+ newFrame:(NSRect)aRect
{
    return [[self allocFromZone:NXDefaultMallocZone()] initWithFrame:aRect];
}

+ (void)initialize {
    if (self == [SoundView class]) {
	NSArray * types = [[NSArray alloc] initWithObjects:NXSoundPboardType, nil];
	[NSApp registerServicesMenuSendTypes:types returnTypes:types];
	[types release];
	[SoundView setVersion:1];
    }
}

- (id)initWithFrame:(NSRect)aRect {
    [super initWithFrame:aRect];
    [self setForegroundColor:[NSColor blackColor]];
    [self setBackgroundColor:[NSColor whiteColor]];
    reductionFactor = 1;
    displayMode = SK_DISPLAY_MINMAX;
    [self setBoundsSize:(NSSize){ [self bounds].size.width, 65536 }];
    [self setBoundsOrigin:(NSPoint){ 0, -32768.0 }];
    selectionRect.origin.x = 0.0;
    selectionRect.origin.y = -32768.0;
    selectionRect.size.width = 0.0;
    selectionRect.size.height = 65536.0;
    return self;
}

- (void)dealloc
{
    [backgroundColor release];
    [foregroundColor release];
    [_scratchSound stop];
    [self stop:nil];
    [self hideCursor];
    [self tellDelegate:@selector(willFree:)];
    if (_scratchSound)  [_scratchSound release];
    [super dealloc];

}

- (void)encodeWithCoder:(NSCoder *)stream {
    [super encodeWithCoder:stream];
    [stream encodeValuesOfObjCTypes:"@@is", &sound, &delegate, &displayMode, &svFlags];
    [stream encodeValuesOfObjCTypes:"@@", &backgroundColor, &foregroundColor];
    [stream encodeArrayOfObjCType:"c" count:sizeof(NXRect) at:&selectionRect];

}

- (id)initWithCoder:(NSCoder *)stream {
    int version;
    self = [super initWithCoder:stream];
    version = [stream versionForClassName:@"SoundView"];
    [stream decodeValuesOfObjCTypes:"@@is", &sound, &delegate, &displayMode, &svFlags];
    if (version == 0) {
	float backgroundGray, foregroundGray;
	[stream decodeValuesOfObjCTypes:"ff", &backgroundGray, &foregroundGray];
	[self setBackgroundColor:[NSColor colorWithCalibratedWhite:backgroundGray alpha:1.0]];
	[self setForegroundColor:[NSColor colorWithCalibratedWhite:foregroundGray alpha:1.0]];
    } else if (version >= 1) {
	[stream decodeValuesOfObjCTypes:"@@", &backgroundColor, &foregroundColor];
    }
    [stream decodeArrayOfObjCType:"c" count:sizeof(NXRect) at:&selectionRect];
    if (sound && [self frame].size.width) {
	reductionFactor = [sound sampleCount] / [self frame].size.width;
	if (reductionFactor < 1) reductionFactor = 1;
    } else
	reductionFactor = 1;
    svFlags.selectionDirty = YES;
    _scratchSound = nil;
    return self;

}

- (BOOL)isEnabled
{
    return (svFlags.disabled ? NO : YES);
}

- (void)setEnabled:(BOOL)aFlag
{
    [self hideCursor];
    svFlags.disabled = (aFlag ? NO : YES);
    [self showCursor];
}

- (BOOL)isEditable
{
    return (svFlags.notEditable ? NO : YES);
}

- (BOOL)isPlayable
{
    return [sound isPlayable];
}

- (void)setEditable:(BOOL)aFlag
{
    if (svFlags.disabled) return;
    [self hideCursor];
    svFlags.notEditable = (aFlag ? NO : YES);
    [self showCursor];
}

- (void)setOptimizedForSpeed:(BOOL)aFlag {
    svFlags.notOptimizedForSpeed = (aFlag ? NO : YES);
    [self setNeedsDisplay:YES];
}

- (BOOL)isOptimizedForSpeed {
    return (svFlags.notOptimizedForSpeed ? NO : YES);
}

- (BOOL)isContinuous
{
    return svFlags.continuous;
}

- (void)setContinuous:(BOOL)aFlag
{
    svFlags.continuous = (aFlag ? YES : NO);
}

- (BOOL)isBezeled
{
    return svFlags.bezeled;
}

- (void)setBezeled:(BOOL)aFlag
{
    BOOL oldFlag = svFlags.bezeled;
    svFlags.bezeled = (aFlag ? YES : NO);
    if (!oldFlag && aFlag) {
	NXRect temp = [self frame];
	temp = NSInsetRect(temp, 2.0, 2.0);
	[self setFrame:temp];
    } else if (oldFlag && !aFlag) {
	NXRect temp = [self frame];
	temp = NSInsetRect(temp, -2.0, -2.0);
	[self setFrame:temp];
    }
    [self setNeedsDisplay:YES];
}

- (void)setBackgroundColor:(NSColor *)color;
{
    [backgroundColor autorelease];
    backgroundColor = [color copyWithZone:[self zone]];
    [self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
    return backgroundColor;
}

- (void)setForegroundColor:(NSColor *)color;
{
    [foregroundColor autorelease];
    foregroundColor = [color copyWithZone:[self zone]];
    [self setNeedsDisplay:YES];
}

- (NSColor *)foregroundColor;
{
    return foregroundColor;
}

- (int)displayMode
{
    return displayMode;
}

- (void)setDisplayMode:(int)aMode
{
    displayMode = aMode;
    [self setNeedsDisplay:YES];
}

- (BOOL)isAutoScale
{
    return svFlags.autoscale;
}

- (void)setAutoscale:(BOOL)aFlag
{
    svFlags.autoscale = aFlag? YES : NO;
}

- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)anObject
{
    delegate = anObject;
}

- (Sound *)sound
{
    return sound;
}

- (void)setSound:(Sound *)aSound // Should be BOOL; but affects NSButton
{
    [[self window] disableFlushWindow];
    sound = aSound;
    svFlags.selectionDirty = YES;
    if (svFlags.autoscale)
	[self scaleToFit];
    else {
	reductionFactor = [sound samplingRate] / DEFAULT_PIXELS_PER_SECOND;
	if (reductionFactor < 1) reductionFactor = 1;
	[self sizeToFit];
    }
    [[self window] enableFlushWindow];
    [self setNeedsDisplay:YES];
    if (sound && [sound soundStruct] && !_isDisplayable([sound dataFormat]))
      return /* NO */;
//    return YES;
}

- (float)reductionFactor
{
    return reductionFactor;
}

- (BOOL)setReductionFactor:(float)theReductionFactor
{
    if (theReductionFactor == reductionFactor) return YES;
    if (!svFlags.autoscale && (theReductionFactor >= 1.0)) {
	[[self window] disableFlushWindow];
    	reductionFactor = theReductionFactor;
	if (svFlags.autoscale)
	    [self scaleToFit];
	else
	    [self sizeToFit];
	[[self window] enableFlushWindow];
	[self setNeedsDisplay:YES];
	return YES;
    } else
	return NO;
}

- (void)sizeToFit
{
    float sampCount, theWidth = MIN_FRAME_WIDTH;
    if (sound && [sound soundStruct]) {
	sampCount = (float)[sound sampleCount];
	if (sampCount && (sampCount > MIN_FRAME_WIDTH))
	    theWidth = sampCount / reductionFactor;
    }
    [super setFrameSize:(NSSize){ theWidth, [self frame].size.height }];
    selectionRect.size.width = 0.0;
}

- (void)scaleToFit
{
    float samples = (float)[sound sampleCount];
    float newFactor;
    if (samples > 0.0)
	newFactor = samples / [self frame].size.width;
    else
	newFactor = 1.0;
    if (newFactor != reductionFactor) {
	reductionFactor = newFactor;
	if (reductionFactor < 1) reductionFactor = 1;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:(NSSize){ newSize.width, newSize.height }];
    [self setBoundsSize:(NSSize){ [self bounds].size.width, 65536 }];
    [self setBoundsOrigin:(NSPoint){ 0, -32768.0 }];
    [self setNeedsDisplay:YES];
}

- (BOOL)drawSamplesFrom:(int)startX to:(int)endX
{
    if ([sound dataSize] && [sound sampleCount] > 0
	&& _isDisplayable([sound dataFormat])) {
	int iReductionFactor = (int)reductionFactor;
	BOOL optimize = !svFlags.notOptimizedForSpeed;
	if (displayMode == SK_DISPLAY_MINMAX) {
	    drawMinMax(sound,iReductionFactor, startX, endX, optimize);
	    return YES;
	} else if (displayMode == SK_DISPLAY_WAVE) {
	    drawWave(sound,iReductionFactor,startX, endX, optimize);
	    return YES;
	}
    }
    return NO;
}

- (void)drawRect:(NSRect)rect
{
    int begin, end;
    NXRect theRect;
    if (NSIsEmptyRect(theRect = [self visibleRect])) return;
    theRect = NSIntegralRect(NSIntersectionRect(rect, theRect));
    begin = (int)theRect.origin.x;
    end = begin + (int)theRect.size.width + 1;
    if (begin > 0) begin--;
    if ([[NSDPSContext currentContext] isDrawingToScreen]) {
	if (!selectionRect.size.width)
	    [self hideCursor];
	else
	    NSHighlightRect(selectionRect);
    }
    if (svFlags.bezeled) {
	NXRect temp = [self frame];
	[[self superview] lockFocus];
	temp = NSInsetRect(temp, -2.0, -2.0);
	NSDrawGrayBezel(temp, temp);	/* ??? The second arg wants to be NULL (cliprect) */
	[backgroundColor set];
	NSRectFill([self frame]);
	[[self superview] unlockFocus];
    } else {
	[backgroundColor set];
	NSRectFill(theRect);
    }
    if (sound) {
	[foregroundColor set];
	[self drawSamplesFrom:begin to:end];
    }
    if ([[NSDPSContext currentContext] isDrawingToScreen]) {
	if (!selectionRect.size.width)
	    [self showCursor];
	else
	    NSHighlightRect(selectionRect);
    }
}

static int extendSelection(SoundView *self, NXPoint *curPoint,
						 NXPoint *basePoint)
{
    static NXPoint lastPoint = {0,0};
    if (lastPoint.x == curPoint->x)
	return 0;
    lastPoint = *curPoint;
    NSHighlightRect(self->selectionRect);
    if (curPoint->x < basePoint->x) {
	self->selectionRect.origin.x = curPoint->x;
	self->selectionRect.size.width = basePoint->x - curPoint->x;
    } else {
	self->selectionRect.origin.x = basePoint->x;
	self->selectionRect.size.width = curPoint->x - basePoint->x;
    }
    NSHighlightRect(self->selectionRect);
    [[self window] flushWindow];
    return 1;
}

static void fixX(SoundView *self, NXPoint *aPoint)
{
    int temp, max = [self->sound sampleCount];
    if (aPoint->x < 0)
	temp = 0;
    else if (aPoint->x > max)
	temp = max;
    else
	temp = (int)aPoint->x;
    aPoint->x = (float)temp;
}

- (void)hideCursor
{
    stopCaret(self);
}

- (void)showCursor
{
    NXRect temp = selectionRect;
    if (temp.size.width || !sound || svFlags.disabled || svFlags.notEditable)
	stopCaret(self);
    else
	startCaret(self);
}

- (void)mouseDown:(NSEvent *)theEvent
{
    #define SVEVENTMASK (NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSPeriodicMask)
    NSEvent *lastRealEvent = theEvent, *event = theEvent;
    NXPoint curPoint, basePoint, mouseLocation;
    NXRect vRect;
    int notDone = 1;

    	/* timer events used for auto scroll */

    if (svFlags.disabled) return;
    [self lockFocus];
    if (selectionRect.size.width)
	NSHighlightRect(selectionRect);
    else
	[self hideCursor];
    selectionRect.size.height = [self bounds].size.height;
    selectionRect.origin.y = [self bounds].origin.y;
    vRect = [self visibleRect];
    curPoint = [event locationInWindow];
    curPoint = [self convertPoint:curPoint fromView:nil];
    mouseLocation = curPoint;
    fixX(self,&curPoint);
    if (NSShiftKeyMask & [event modifierFlags]) {
	basePoint.y = curPoint.y;
	if (curPoint.x < 
		(selectionRect.origin.x + (selectionRect.size.width/2))) {
	    basePoint.x = selectionRect.origin.x + selectionRect.size.width;
	    selectionRect.size.width = basePoint.x - curPoint.x;
	    selectionRect.origin.x = curPoint.x;
	} else {
	    basePoint.x = selectionRect.origin.x;
	    selectionRect.size.width = curPoint.x - selectionRect.origin.x;
	}
    } else {
	basePoint = curPoint;
	selectionRect.origin.x = curPoint.x;
	selectionRect.size.width = 0.0;
    }
    NSHighlightRect(selectionRect);
    [[self window] flushWindow];
    [NSEvent startPeriodicEventsAfterDelay:0.1 withPeriod:0.1];
    while (notDone) {
	switch ([event type]) {
	    case NSLeftMouseUp:
		notDone = 0;
	        break;
	    case NSLeftMouseDragged:
		curPoint = [event locationInWindow];
		curPoint = [self convertPoint:curPoint fromView:nil];
		fixX(self,&curPoint);
		lastRealEvent = event;
		if (extendSelection(self,&curPoint,&basePoint) &&
							svFlags.continuous)
		    [self tellDelegate:@selector(selectionChanged:)];
		break;
	    case NSPeriodic:
		if (!NSPointInRect(curPoint, vRect)) {
		    [self autoscroll:lastRealEvent];
		    PSWait();
		    vRect = [self visibleRect];
		    curPoint = [lastRealEvent locationInWindow];
		    curPoint = [self convertPoint:curPoint fromView:nil];
		    fixX(self,&curPoint);
		    if (extendSelection(self,&curPoint,&basePoint) &&
							    svFlags.continuous)
			[self tellDelegate:@selector(selectionChanged:)];
		    }
		break;
	    default: break;
	}
	event = [[self window] nextEventMatchingMask:SVEVENTMASK];
    }
    svFlags.selectionDirty = YES;
    [self tellDelegate:@selector(selectionChanged:)];
    [NSEvent stopPeriodicEvents];
    [self unlockFocus];
    _DPSDiscardEvents(DPSGetCurrentContext(), (NSKeyDownMask | NSKeyUpMask | SVEVENTMASK), [event _nxeventTime]);
    if (!selectionRect.size.width) {
	[self showCursor];
    }
    [[self window] flushWindow];
    PSWait();
}

- (void)tellDelegate:(SEL)theMessage
{
    if (theMessage && delegate && [delegate respondsToSelector:theMessage])
	[delegate performSelector:theMessage withObject:self];
}

- (void)getSelection:(int *)firstSample size:(int *)sampleCount
{
    int iReductionFactor = (int)reductionFactor;
    *firstSample = (int)(selectionRect.origin.x * iReductionFactor);
    *sampleCount = (int)(selectionRect.size.width * iReductionFactor);
}


- (void)setSelection:(int)firstSample size:(int)sampleCount
{
    int iReductionFactor = (int)reductionFactor;
    int max = [sound sampleCount];
    int offset=firstSample, count=sampleCount;
    if (!sound) return;
    if (offset < 0) offset = 0;
    else if (offset > max) offset = max;
    if ((firstSample+sampleCount) > max) count = max - offset;
    selectionRect.origin.x = offset/iReductionFactor;
    selectionRect.size.width = count/iReductionFactor;
    svFlags.selectionDirty = YES;
    [self setNeedsDisplay:YES];
    [[self window] makeFirstResponder:self];
    [self tellDelegate:@selector(selectionChanged:)];
}

- (void)play:sender
{
    int iReductionFactor = (int)reductionFactor;
    int err;
    int firstSample = (int)(selectionRect.origin.x * iReductionFactor);
    int sampleCount = (int)(selectionRect.size.width * iReductionFactor);
    [self stop:sender];
    if (sound) {
	if (!sampleCount) {
	    if (!_scratchSound) {
		_scratchSound = [Sound new];
		[_scratchSound setDelegate:self];
	    }
	    [_scratchSound copySound:sound];
	    svFlags.selectionDirty = YES;
	} else {
	    if (!_scratchSound) {
		_scratchSound = [Sound new];
		[_scratchSound setDelegate:self];
		svFlags.selectionDirty = YES;
	    }
	    if (svFlags.selectionDirty) {
		err = [_scratchSound copySamples:sound at:firstSample 
							    count:sampleCount];
		svFlags.selectionDirty = NO;
	    }
	}
	[_scratchSound play:nil];
    } else {
	[self willPlay:nil];
	[self didPlay:nil];
    }
}


- (void)stop:(id)sender
{
    int err = [_scratchSound stop];
    if (err)
	[self tellDelegate:@selector(hadError:)];
}

- (void)record:sender
{
    int err;
    [self stop:sender];
    if (!_scratchSound) {
	_scratchSound = [Sound new];
	[_scratchSound setDelegate:self];
	svFlags.selectionDirty = YES;
    }
    err = [_scratchSound record];
}

- (void)pause:sender
{
    if (!_scratchSound || ![_scratchSound status]) return /* nil */;
    [_scratchSound pause:self];
}

- (void)resume:sender
{
    if (!_scratchSound || ![_scratchSound status]) return /* nil */;
    [_scratchSound resume:self];
}


/*
 * Editing methods
 */

- (BOOL)acceptsFirstResponder
{
    return svFlags.disabled? NO : YES;
}

- (BOOL)becomeFirstResponder
{
    [self showCursor];
    return YES;
}

- (BOOL)resignFirstResponder
{
    [self hideCursor];
    return YES;
}

- (void)selectAll:(id)sender
{
    if (sound)
	[self setSelection:0 size:[sound sampleCount]];
}

- (void)delete:(id)sender
{
    if (svFlags.notEditable) return;
    replaceSelection(self,nil,NO);
}

- (void)cut:(id)sender
{
    if (svFlags.notEditable) return;
    [self copy:sender];
    [self delete:sender];
}

static Sound *copiedSound=nil;
static int copiedRefnum=0;

- (void)pasteboard:(NSPasteboard *)thePasteboard provideData:(NSString *)type
{
    int err;
    if ([type isEqualToString:NXSoundPboardType]) {
	err = [copiedSound compactSamples];
	[thePasteboard setData:[NSData dataWithBytes:(char *)[copiedSound soundStruct] length:[copiedSound soundStructSize]] forType:NXSoundPboardType];
    }
}

- copyTo:(NSPasteboard *)thePboard
{
    int iReductionFactor = (int)reductionFactor;
    int err;
    int rFirstSample = (int)selectionRect.origin.x;
    int rSampleCount = (int)selectionRect.size.width;
    int firstSample = rFirstSample*iReductionFactor;
    int sampleCount = rSampleCount*iReductionFactor;
    if (!copiedSound) copiedSound = [Sound new];
    err = [copiedSound copySamples:sound
    			   at:firstSample count:sampleCount];
#ifdef DEBUG
    if (err) printf("Cannot copy sound : %s\n", SNDSoundError(err));//
#endif
    [thePboard declareTypes:[[[NSArray alloc] initWithObjects:NXSoundPboardType, nil] autorelease] owner:self];
    copiedRefnum = [thePboard changeCount];
    return self;
}

- (void)copy:(id)sender
{
    [self copyTo:[NSPasteboard generalPasteboard]];
}

static id replaceSoundStruct(id theSound, const char *s, int slen)
{
    id sound;
    if (!slen) {
	if (theSound)  [theSound release];
	return nil;
    }
    sound = theSound? theSound : [Sound new];
    [sound setSoundStruct:(SNDSoundStruct *)s soundStructSize:slen];
    return sound;
}

- pasteFrom:(NSPasteboard *)thePboard
{
    int err;
    int changeCount;

    if (svFlags.notEditable) return self;
    if (!thePboard) return self;
    changeCount = [thePboard changeCount];
    if (![[thePboard types] containsObject:NXSoundPboardType]) return self;
    if (!copiedSound || (changeCount != copiedRefnum)) {
	NSData *data;
	copiedRefnum = changeCount;
	if ((data = [thePboard dataForType:NXSoundPboardType]) == nil) {
	    NSLog(@"SoundView - cannot read data from pasteboard\n");
	    return self;
	}
	copiedSound = replaceSoundStruct(copiedSound, [data bytes], [data length]);
    }
    if (copiedSound) {
	if (sound && ![sound compatibleWith:copiedSound]) {
	    err = [copiedSound convertToFormat:[sound dataFormat]
		       samplingRate:[sound samplingRate]
		       channelCount:[sound channelCount]];
	}
	replaceSelection(self,copiedSound,NO);
    } else {
	NSLog(@"SoundView - cannot get data from pasteboard\n");
    }
    return self;
}

- (void)paste:(id)sender
{
    [self pasteFrom:[NSPasteboard generalPasteboard]];
}

/*** Begin services support ***/

- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType {
    int firstSample, sampleCount;
    BOOL sendOK, retOK;
    
    if (!sendType) {
	sendOK = YES;
    } else if ([sendType isEqualToString:NXSoundPboardType]) {
	[self getSelection:&firstSample size:&sampleCount];
	sendOK = sampleCount > 0;
    } else {
      sendOK = NO;
    }
    retOK = !returnType || [returnType isEqualToString:NXSoundPboardType];
    return (sendOK && retOK) ? self : nil;
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types {
    /* put the selection in the given pasteboard */
    return ([self copyTo:pboard]==self);
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard {
    /* replace the selection with the sound data in the given pasteboard */
    [self pasteFrom:pboard];
    return YES;
}

/*** End services support ***/


- (void)didPlay:sender
{
    [self tellDelegate:@selector(didPlay:)];
}

- (void)willPlay:sender
{
    [self tellDelegate:@selector(willPlay:)];
}

- (void)didRecord:sender
{
    replaceSelection(self,_scratchSound,YES);
    [self tellDelegate:@selector(didRecord:)];
}

- (void)willRecord:sender
{
    [self tellDelegate:@selector(willRecord:)];
}

- (void)hadError:sender
{
    [self tellDelegate:@selector(hadError:)];
}

- soundBeingProcessed
{
    return _scratchSound;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [self hideCursor];
    [super viewWillMoveToWindow:newWindow];
}

@end

/*

Modification History:

soundkit-25
=======================================================================================
5 Sept 91 (lboynton)	Fixed bugs.
4 Sept 91 (lboynton)	Rewrote drawing code, eliminated display reduction.
11 Sept 90 (wot)	Changed drawing of caret to use zero width lines rather than a
			NXFillRect on a 1 pixel wide rect.
12 Sept 90 (wot)	Implemented "windowChanged:" to hide the caret.

20 Sept 90 (wot)	Added support for SND_FORMAT_EMPHASIZED.  Made it do the same
			things as SND_FORMAT_LINEAR_16.
 8 Oct	90 (wot)	Changed NXSoundPboard to NXSoundPboardType.
 4 Jan	92 (jos)	Added copyTo:, pasteFrom:, 
 			writeSelectionToPasteboard:types:,
			readSelectionFromPasteboard:
			isPlayable;
24 Jan	92 (jos)	setSound returns nil if sound format not displayable.
25 Jan	92 (jos)	Discovered Services did not work.  Changed
			provideData: to pasteboard:provideData: and it worked!
20 Feb  92  (mtm)	Get rid of static data in screenDrawSamples.
19 Mar	92 (jos)	Fixed paste bug where pasting is into a NULL sound.
			Fixed paste bug in the case doing format conversion.
02 Jul	92 (mtm)	Allow setSound to accept null sounds.
02/06/93 mtm		byte swap stuff.
 10/7/93 aozer		NSString/NSRect kit conversion
			Removed obsolete methods reduction, setReduction:, calcDrawInfo

*/
