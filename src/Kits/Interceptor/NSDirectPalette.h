/* 	Copyright (c) 1997 Apple Computer, Inc.  All rights reserved. 
 *
 * NSDirectPalette.h - Object representatioin of a pseudocolor palette
 *
 * HISTORY
 * 12 April 1997    Mike Paquette at Apple
 *      Created. 
 */

#import <Foundation/NSArray.h>
#import <AppKit/NSColor.h>

@interface NSDirectPalette : NSObject <NSCoding, NSCopying, NSMutableCopying>
{
@private
    void *		_private;
}

+ (NSDirectPalette *) defaultPalette;
+ (NSDirectPalette *) defaultColorPalette;
+ (NSDirectPalette *) defaultGrayPalette;
+ (NSDirectPalette *) currentPalette;

- initWithArrayOfColors:(NSArray *)colorArray;
- init;
- (NSColor *)colorAtIndex:(int)index;
- (int)indexForColor:(NSColor *)color;	// Find index for best color match
- (unsigned)count;
- (void)dealloc;
- (NSEnumerator *)objectEnumerator;
- (NSData *)rawMachinePalette;
- (void)setColor:(NSColor *)color atIndex:(int)index;
- (void)setRed:(float)r green:(float)g blue:(float)b atIndex:(int)index;
- (void)getRed:(float*)r green:(float*)g blue:(float*)b atIndex:(int)index;
- (void)setColors:(NSColor **)colors atIndices:(NSRange)indexRange;

- (NSDirectPalette *)blendedPaletteWithFraction:(float)fraction ofColor:(NSColor *)color;

@end
