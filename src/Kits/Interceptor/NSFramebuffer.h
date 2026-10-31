/* 	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved. 
 *
 * NXFramebuffer.h - Bitmap subclass used to map and describe a framebuffer.
 *
 * HISTORY
 * 28-July-93    Mike Paquette at NeXT
 *      Created. 
 */

#import "NSBitmap.h"
#import "Interceptor_types.h"
#import <Foundation/NSRange.h>
#import <AppKit/NSScreen.h>

typedef enum {
	NSFramebufferReadWrite,
	NSFramebufferWriteOnly,
	NSFramebufferReadOnly
} NSFramebufferAccessMode;

/* Palette data types */
typedef struct {
	unsigned short red;
	unsigned short green;
	unsigned short blue;
} NSPaletteEntry;

/*
 * Notification of Window Server death
 */
extern NSString * NTWindowServerDeathNotification;

@interface NSFramebuffer : NSSimpleBitmap
{
@private
    id			interceptorClient;
    int			screenNumber;
    NSRect		bounds;
    pixel_encoding_t	pixelEncoding;
    NSString *		publicPixelEncoding;
    driver_name_t	driver;
    NSString *		publicDriver;
    int			deviceSlot;
    int			deviceUnit;
    void *		conversionTable;
    void *		inverseConversionTable;
    BOOL		isMapped;
#if hppa //[
    void		*hpfbs;
#else
    unsigned int	_fb_padding1;
#endif //]
    NSPaletteEntry *	_palette;
    int			_paletteSize;
    unsigned int	_fb_padding[5];
    void *		_fb_private;
}

- initWithScreen:(NSScreen *) screen;
- initWithScreen:(NSScreen *) screen andMapIfPossible: (BOOL) map;

/* designated initializer */
- initFromScreen:(int) screenNumber andMapIfPossible: (BOOL) map ;
- (void)remapScreen;
- (void)unmapScreen;
- (BOOL) isMappable;
- (NSRect)screenBounds;
- (void *) conversionTable;
- (void *) inverseConversionTable;
- (void *)addressForPoint:(NSPoint)location;
- (NSString *)pixelEncoding;
- (NSString *)driver;
- (int)deviceUnit;
- (int)deviceSlot;
- (int) screenNumber;
- (BOOL)canLockWithMode:(NSFramebufferAccessMode)mode;
- (void)lockWithMode:(NSFramebufferAccessMode)mode;
- (void)unlock;

/*
 * C function used to force correct mapping of MegaPixel display in
 * a multi-threaded environment.  Strictly speaking, this only applies to
 * NEXTSTEP running on NeXT's m68k hardware.
 */
void NSRemapMegaPixelDisplayForCurrentThread(void);

@end
