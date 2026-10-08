/* 	Copyright (c) 1997 Apple Computer, Inc.  All rights reserved. 
 *
 * NSDirectScreen.h - Bitmap class used to map and describe a framebuffer.
 *
 * HISTORY
 * 26 March 1997    Mike Paquette at Apple
 *      Created. 
 */

#import "NSDirectPalette.h"
#import "NSBitmap.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <AppKit/NSWindow.h>

/* Keys for mode dictionaries */
extern NSString * NSDirectScreenHeight;
extern NSString * NSDirectScreenWidth;
extern NSString * NSDirectScreenDepth;
extern NSString * NSDirectScreenColorSpace;
extern NSString * NSDirectScreenPixelEncoding;
extern NSString * NSDirectScreenModeNumber;
extern NSString * NSDirectScreenFrequency;
extern NSString * NSDirectScreenFrequencyRange;
extern NSString * NSDirectScreenRowBytes;
extern NSString * NSDirectScreenBitsPerPixel;
extern NSString * NSDirectScreenBitsPerSample;
extern NSString * NSDirectScreenSamplesPerPixel;
extern NSString * NSDirectScreenSafeMode;
extern NSString * NSDirectScreenDefaultMode;

/* Exception names */
extern NSString * NSDirectScreenDisplayIsUnshieldedException;
extern NSString * NSDirectScreenDisplayCannotSetPaletteException;

/* NSNotification names */
extern NSString *NSDirectScreenWillStartFadeInNotification;
extern NSString *NSDirectScreenDidFinishFadeInNotification;
extern NSString *NSDirectScreenWillStartFadeOutNotification;
extern NSString *NSDirectScreenDidFinishFadeOutNotification;
extern NSString *NSDirectScreenDidChangePaletteNotification;
extern NSString *NSDirectScreenDidChangeDisplayModeNotification;

@interface NSDirectScreen: NSObject <NSDirectBitmapProtocol>
{
@private
    void *		_private;
}

- initWithScreen:(NSScreen *) screen;
- (NSSize)screenSize;
- (int)pixelsWide;
- (int)pixelsHigh;

- (void *)addressForPoint:(NSPoint)location;
- (NSArray *) availableDisplayModes;
- (NSArray *) availableDisplayModesForOptions:(NSDictionary *)options;
- (NSDictionary *)bestModeForFormat:(NSString *)format width:(int)width height:(int)height;
- (NSDictionary *)bestModeForOptions:(NSDictionary *)options;
- (NSDictionary *)currentMode;
- (int)bitsPerPixel;
- (int)bitsPerSample;
- (int)bytesPerRow;
- (NSString *)colorSpaceName;
- (unsigned char *)bitmapData;
- (int)deviceSlot;
- (int)deviceUnit;
- (BOOL)displayIsShielded;
- (NSString *)driver;
- (void)dealloc;
- (void)fadeDisplay:(float)intensity toColor:(NSColor *)color;
- (void)fadeDisplayInFromColor:(NSColor *)color;
- (void)fadeDisplayOutToColor:(NSColor *)color;
- (NSTimeInterval)fadeDuration;
- (BOOL)fadeInProgress;
- (BOOL)fadeApplied;
- (NSString *)pixelEncoding;
- (int)samplesPerPixel;
- (int)screenNumber;
- (void)setFadeDuration:(NSTimeInterval)seconds;
- (void)shieldDisplay;
- (NSWindow *)shieldingWindow;
- (void)switchToDisplayMode:(NSDictionary *)mode;
- (void)unshieldDisplay;

- (void)hideCursor;	/* Hide cursor over our screen */
- (void)showCursor;	/* Reveal cursor over our screen */

- (BOOL) canSetPalette;
- (NSDirectPalette *) currentPalette;
- (void)setPalette:(NSDirectPalette *)palette;
- (void)setPaletteAtNextBlankingInterval:(NSDirectPalette *)palette;

@end
