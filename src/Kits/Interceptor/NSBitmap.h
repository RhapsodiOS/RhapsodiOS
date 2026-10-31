/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved. 
 *
 * NXBitmap.h - Bitmap abstract class and category definitions.
 *
 * HISTORY
 * 28-July-93    Mike Paquette at NeXT
 *      Created. 
 */


#import <Foundation/NSObject.h>
#import <AppKit/NSGraphics.h>

/* Colorspace tokens matching the values used within the Window Server */
typedef enum {
	NSOneIsBlackColorSpace = 0,
	NSOneIsWhiteColorSpace = 1,
	NSRGBColorSpace = 2,
	NSCMYKColorSpace = 3
} NSColorSpaceToken;


/*
 * we define a protocol for bitmap information.
 * This protocol should be implemtned by objects which can provide bitmap
 * data.  It is implemented by the DirectBitmap and NSDirectScreen object.
 * A trivial class
 * (NSSimpleBitmap) is also provided to aid `consing' up objects that
 * obey this protocol from an arbitrary hunk of memory.
 */

@protocol NSDirectBitmapProtocol
- (unsigned char *)bitmapData;
- (void)getBitmapDataPlanes:(unsigned char **)data;
- (BOOL)isPlanar;
- (BOOL)hasAlpha;
- (int)samplesPerPixel;
- (int)bitsPerSample;
- (int)bitsPerPixel;
- (int)bytesPerRow;
- (int)bytesPerPlane;
- (int)numberOfPlanes;
- (NSString *)colorSpaceName;
- (int)pixelsWide;
- (int)pixelsHigh;
@end


#define NXSIMPLEBITMAP_MAXPLANES	5
@interface NSSimpleBitmap : NSObject <NSDirectBitmapProtocol>
{
    BOOL 	isPlanar;
    BOOL	hasAlpha;
    int 	bitsPerSample;
    int		samplesPerPixel;
    int		bitsPerPixel;
    int		bytesPerRow;
    int		bytesPerPlane;
    int		numPlanes;
    int		pixelsWide;
    int		pixelsHigh;
    NSString *  colorSpace;
    NSColorSpaceToken		colorSpaceCode;
    void 	*data[NXSIMPLEBITMAP_MAXPLANES];
    unsigned int	_bm_padding[8];
    void *	_bm_private;
}

- initWithBitmapDataPlanes:(unsigned char **)planes
	pixelsWide:(int)width
	pixelsHigh:(int)height
	bitsPerSample:(int)bps
	samplesPerPixel:(int)spp
	hasAlpha:(BOOL)alpha
	isPlanar:(BOOL)isPlanar
	colorSpaceName:(NSString *)colorSpace
	bytesPerRow:(int)rBytes
	bitsPerPixel:(int)pBits;
@end
