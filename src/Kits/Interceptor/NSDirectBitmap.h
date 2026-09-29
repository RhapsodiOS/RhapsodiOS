/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved. 
 *
 * NXDirectBitmap.h - Direct mapped framebuffer bitmap interface.
 *
 * HISTORY
 * 28-July-93    Mike Paquette at NeXT
 *      Created. 
 */

#import "NSBitmap.h"
#import "NSDirectPalette.h"


@interface NSDirectBitmap : NSSimpleBitmap <NSDirectBitmapProtocol>
{
@private
	BOOL	isBuffered;
	BOOL	isDirectMapped;
	BOOL	isUnobscured;
	BOOL	isLocked;
	BOOL	depthMismatch;
	BOOL	drawToBuffer;
	BOOL	updateNeeded;
	
	id	framebuffer;
	int	currentScreen;
	int	newScreen;
	id	interceptRect;
	id	interceptClient;

	void	(*copyFunc)();

	id	window;
	int	gWinNum;
	NSRect	rect;
        int 	_flushOnExposure;
	id	_delegate;
        id	_viewClip;
	int 	processingDelegate;
	int	fbMode;
	int	_naughtyFlags;
	BOOL	_screenIsDirty;
	BOOL	_dbm_pad2;
	BOOL	_dbm_pad3;
	BOOL	_dbm_pad4;
	unsigned int	_dbm_padding[2];
	void *		_dbm_private;

}

- (int)bytesPerPlane;
- (int)bytesPerRow;
- (void *)conversionTable;
- (void *)inverseConversionTable;
- (unsigned char *)bitmapData;
- (void)flush;
- (void)flushIn:(NSRect)rect;
- (void)getBitmapDataPlanes:(unsigned char **)thePlanes;
- (NSArray *)pixelEncodings;
- initForRect:(NSRect)rect inWindow:(id)window;
- (BOOL)isBuffered;
- (BOOL)isDirectMapped;
- (void)lockBitmap;
- (NSString *)pixelEncoding;
- (void)setBuffered:(BOOL)buffered;
- (void)setDirectMapped:(BOOL)directMapped;
- (BOOL) tryLockBitmap;
- (void)unlockBitmap;
- (void)updateForRect:(NSRect)rectp inWindow:(id)window;
- (void)updateState;
- (void)hideCursor;	/* Hide cursor over our rect */
- (void)showCursor;	/* Reveal cursor over our rect */

- (NSDirectPalette *) currentPalette;
@end
