#import "Private/InterceptorCopy.h"
#import "Private/NSInterceptedRect.h"
#import "Private/NSInterceptorClient.h"
#import "Private/InterceptorIPC.h"
#import "NSDirectBitmap.h"
#import "NSFramebuffer.h"
#import "NSShape.h"
#import "InterceptorGlobals.h"
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSZone.h>
#include <stdio.h>
#import <strings.h>

@interface NSDirectBitmap (ReconstructionPrivate)
- (BOOL)_isUnobscured;
- (BOOL)_canUseDirectMapping;
- (id)_mapFramebufferForScreen:(int)screenNumber;
- (id)_updateBackingStoreForRect:(NSRect)rect;
- (id)_initForRect:(NSRect)rect inWinNum:(int)windowNumber
              onScreen:(int)screenNumber;
- (void)_updateForRect:(NSRect)rect inWinNum:(int)windowNumber
              onScreen:(int)screenNumber;
- (id)_flushInShape:(NSShape *)shape;
- (id)_updateBuffer;
- (void)setBuffered:(BOOL)buffered;
- (void)updateState;
@end

static int NSDirectBitmapGrayBitsPerPixelMinimum;
static int NSDirectBitmapColorBitsPerPixelMinimum;
static int NSDirectBitmapMaximumScreens = -1;
typedef void (*NSBitmapCopyFunction)(const void *, int, void *, int, int, int);

@implementation NSDirectBitmap

+ (id)minDepthForGray:(int)grayDepth andColor:(int)colorDepth
{
    NSDirectBitmapGrayBitsPerPixelMinimum = grayDepth;
    NSDirectBitmapColorBitsPerPixelMinimum = colorDepth;
    return self;
}

- init
{
    [NSException raise:NSGenericException
                format:@"Use initForRect:inWindow: to create an NSDirectBitmap"];
    return nil;
}

- (int)bitsPerPixel
{
    return self->bitsPerPixel;
}

- (int)bitsPerSample
{
    return self->bitsPerSample;
}

- (int)bytesPerRow
{
    if (self->isLocked == NO)
        return 0;
    if (self->isBuffered == YES || self->drawToBuffer == YES)
        return self->bytesPerRow;
    return [(id)self->framebuffer bytesPerRow];
}

- (int)bytesPerPlane
{
    int rowBytes;

    if (self->isLocked == NO)
        return 0;
    if (self->isBuffered != YES && self->isUnobscured != NO)
        rowBytes = [(id)self->framebuffer bytesPerRow];
    else
        rowBytes = self->bytesPerRow;
    return rowBytes * self->pixelsHigh;
}

- (NSString *)colorSpaceName
{
    return self->colorSpace;
}

- (void *)conversionTable
{
    return [(id)self->framebuffer conversionTable];
}

- (void *)inverseConversionTable
{
    return [(id)self->framebuffer inverseConversionTable];
}

- (unsigned char *)_dataBuffer
{
    if (self->data[0] == 0) {
        self->data[0] = NSZoneMalloc([self zone],
                                    self->bytesPerRow * (self->pixelsHigh + 4));
        bzero(self->data[0],
              self->bytesPerRow * (self->pixelsHigh + 4));
    }
    return (unsigned char *)self->data[0];
}

- (unsigned char *)bitmapData
{
    NSRect screenRect;

    if (self->isLocked == NO)
        return 0;
    if (self->isBuffered == YES || self->drawToBuffer == YES)
        return [self _dataBuffer];

    screenRect = [self->interceptRect currentScreenRect];
    self->_screenIsDirty = YES;
    return (unsigned char *)[(NSFramebuffer *)self->framebuffer
        addressForPoint:screenRect.origin];
}

- (void)getBitmapDataPlanes:(unsigned char **)planes
{
    int plane;
    NSRect screenRect;

    if (self->isLocked == NO) {
        for (plane = 0; plane <= 4; plane++)
            planes[plane] = 0;
        return;
    }

    if (self->isBuffered == YES || self->drawToBuffer == YES) {
        planes[0] = [self _dataBuffer];
        for (plane = 1; plane < [self numberOfPlanes]; plane++)
            planes[plane] = (unsigned char *)self->data[plane];
        for (; plane <= 4; plane++)
            planes[plane] = 0;
        return;
    }

    screenRect = [self->interceptRect currentScreenRect];
    planes[0] = (unsigned char *)[(NSFramebuffer *)self->framebuffer
        addressForPoint:screenRect.origin];
    self->_screenIsDirty = YES;
    for (plane = 1; plane <= 4; plane++)
        planes[plane] = 0;
}

- (BOOL)hasAlpha
{
    return self->hasAlpha;
}

- (BOOL)isPlanar
{
    return self->isPlanar;
}

- (BOOL)isBuffered
{
    return self->isBuffered;
}

- (BOOL)isDirectMapped
{
    return self->isDirectMapped;
}

- (BOOL)_canUseDirectMapping
{
    if (NSDirectBitmapMaximumScreens == -1)
        NSDirectBitmapMaximumScreens = InterceptorScreenCount(
            [self->interceptClient _context]);

    return self->framebuffer != nil &&
           [(NSFramebuffer *)self->framebuffer isMappable] &&
           [(NSFramebuffer *)self->framebuffer bitsPerPixel] > 7 &&
           self->bitsPerPixel ==
               [(NSFramebuffer *)self->framebuffer bitsPerPixel] &&
           NSDirectBitmapMaximumScreens == 1;
}

- (id)_mapFramebufferForScreen:(int)screenNumber
{
    [self->framebuffer release];
    self->framebuffer = [[NSFramebuffer allocWithZone:[self zone]]
        initFromScreen:screenNumber andMapIfPossible:YES];
    self->currentScreen = screenNumber;

    if ([(NSFramebuffer *)self->framebuffer
            canLockWithMode:NSFramebufferReadWrite])
        self->fbMode = NSFramebufferReadWrite;
    else if ([(NSFramebuffer *)self->framebuffer
                 canLockWithMode:NSFramebufferWriteOnly])
        self->fbMode = NSFramebufferWriteOnly;
    else
        self->fbMode = NSFramebufferReadOnly;
    return self;
}

- (id)_initForRect:(NSRect)rect inWinNum:(int)windowNumber
              onScreen:(int)screenNumber
{
    unsigned char *planes[NXSIMPLEBITMAP_MAXPLANES] = { 0, 0, 0, 0, 0 };
    NSString *colorSpace;
    int bitsPerPixel, bitsPerSample, samplesPerPixel, rowBytes;

    if (NSIsEmptyRect(rect)) {
        [self release];
        return nil;
    }

    self->rect = rect;
    self->_flushOnExposure = YES;
    if (self->interceptClient == nil) {
        self->interceptClient = [[NSInterceptorClient allocWithZone:[self zone]]
            init];
        if (self->interceptClient == nil) {
            [self release];
            return nil;
        }
        [self->interceptClient startHandlingThread];
    }

    [self _mapFramebufferForScreen:screenNumber];
    self->isLocked = NO;
    self->isBuffered = self->fbMode != NSFramebufferReadWrite;
    self->newScreen = screenNumber;
    if (self->framebuffer == nil) {
        [self release];
        return nil;
    }

    bitsPerPixel = [(NSFramebuffer *)self->framebuffer bitsPerPixel];
    bitsPerSample = [(NSFramebuffer *)self->framebuffer bitsPerSample];
    samplesPerPixel = [(NSFramebuffer *)self->framebuffer samplesPerPixel];
    colorSpace = [(NSFramebuffer *)self->framebuffer colorSpaceName];
    if ([colorSpace isEqual:NSDeviceRGBColorSpace]) {
        if (bitsPerPixel < NSDirectBitmapColorBitsPerPixelMinimum) {
            bitsPerPixel = NSDirectBitmapColorBitsPerPixelMinimum;
            bitsPerSample = bitsPerPixel / 4;
            self->depthMismatch = YES;
        }
    } else if (bitsPerPixel < NSDirectBitmapGrayBitsPerPixelMinimum) {
        bitsPerPixel = NSDirectBitmapGrayBitsPerPixelMinimum;
        bitsPerSample = bitsPerPixel;
        self->depthMismatch = YES;
    }

    rowBytes = ((int)(rect.size.width * bitsPerPixel + 7) / 8 + 7) & ~7;
    [super initWithBitmapDataPlanes:planes
        pixelsWide:(int)rect.size.width
        pixelsHigh:(int)rect.size.height
        bitsPerSample:bitsPerSample
        samplesPerPixel:samplesPerPixel
        hasAlpha:NO
        isPlanar:NO
        colorSpaceName:colorSpace
        bytesPerRow:rowBytes
        bitsPerPixel:bitsPerPixel];

    switch (self->bitsPerPixel) {
    case 8:
        self->copyFunc = CopyByte;
        break;
    case 16:
        self->copyFunc = CopyShort;
        break;
    case 32:
        self->copyFunc = CopyLong;
        break;
    default:
        self->copyFunc = 0;
        break;
    }

    [self _updateForRect:rect inWinNum:windowNumber onScreen:screenNumber];
    return self;
}

- (id)_updateBackingStoreForRect:(NSRect)rect
{
    unsigned char *planes[NXSIMPLEBITMAP_MAXPLANES] = { 0, 0, 0, 0, 0 };
    int rowBytes;

    if (self->data[0] != 0)
        NSZoneFree([self zone], [self _dataBuffer]);

    rowBytes = ((int)(rect.size.width * self->bitsPerPixel + 7) / 8 + 7) & ~7;
    [super initWithBitmapDataPlanes:planes
        pixelsWide:(int)rect.size.width
        pixelsHigh:(int)rect.size.height
        bitsPerSample:self->bitsPerSample
        samplesPerPixel:self->samplesPerPixel
        hasAlpha:NO
        isPlanar:NO
        colorSpaceName:self->colorSpace
        bytesPerRow:rowBytes
        bitsPerPixel:self->bitsPerPixel];
    return self;
}

- (void)_updateForRect:(NSRect)rect inWinNum:(int)windowNumber
              onScreen:(int)screenNumber
{
    BOOL geometryChanged;

    if (NSIsEmptyRect(rect)) {
        [self release];
        return;
    }
    if (self->isLocked == YES)
        return;

    geometryChanged = !NSEqualRects(self->rect, rect) ||
                      self->gWinNum != windowNumber ||
                      self->currentScreen != screenNumber;
    if (self->interceptRect != nil && geometryChanged) {
        [self->interceptRect removeFromWindowServer];
        [self->interceptRect release];
        self->interceptRect = nil;
    }

    self->gWinNum = windowNumber;
    if (self->currentScreen != screenNumber) {
        [self _mapFramebufferForScreen:screenNumber];
        self->depthMismatch = self->data[0] != 0 &&
            (self->bitsPerSample != [(NSFramebuffer *)self->framebuffer bitsPerSample] ||
             self->bitsPerPixel != [(NSFramebuffer *)self->framebuffer bitsPerPixel] ||
             self->samplesPerPixel != [(NSFramebuffer *)self->framebuffer samplesPerPixel] ||
             ![[(NSFramebuffer *)self->framebuffer colorSpaceName]
                 isEqual:self->colorSpace]);
    }

    if ([self _canUseDirectMapping] && self->depthMismatch == NO) {
        self->isDirectMapped = YES;
        if (self->interceptRect == nil) {
            self->interceptRect = [[NSInterceptedRect allocWithZone:[self zone]]
                initForRect:rect inWindow:self->gWinNum
                onFramebuffer:self->framebuffer
                forClient:self->interceptClient];
            [self->interceptRect setTarget:self];
            [self->_dbm_private release];
            self->_dbm_private = [[NSShape allocWithZone:[self zone]] init];
            self->isUnobscured = [self->interceptRect isTotallyVisible];
            if (!NSEqualSizes(self->rect.size, rect.size))
                [self _updateBackingStoreForRect:rect];
            self->rect = rect;
            [self->interceptRect unlockRect];
        }
    } else {
        self->isUnobscured = NO;
        self->isDirectMapped = NO;
        self->isBuffered = YES;
        if (self->interceptRect != nil) {
            [self->interceptRect removeFromWindowServer];
            [self->interceptRect release];
            self->interceptRect = nil;
        }
        if (!NSEqualSizes(self->rect.size, rect.size))
            [self _updateBackingStoreForRect:rect];
        self->rect = rect;
    }
}

- (void)updateForRect:(NSRect)rect inWindow:(id)window
{
    unsigned int globalWindowNumber;
    int newScreen;
    id oldWindow;

    NSConvertWindowNumberToGlobal([window windowNumber], &globalWindowNumber);
    newScreen = [[[[window screen] deviceDescription]
        objectForKey:@"NSScreenNumber"] intValue];
    if (newScreen == self->currentScreen)
        newScreen = self->newScreen;

    oldWindow = self->window;
    self->window = [window retain];
    [oldWindow release];
    [self _updateForRect:rect
        inWinNum:(int)globalWindowNumber
        onScreen:newScreen];
}

- (void)setDirectMapped:(BOOL)directMapped
{
    BOOL wasDirectMapped = self->isDirectMapped;

    if (wasDirectMapped == directMapped)
        return;

    if (directMapped == YES) {
        self->isDirectMapped = [self _canUseDirectMapping];
        if (self->isDirectMapped == YES && self->window != nil &&
            [self->window backingType] == NSBackingStoreBuffered)
            self->isDirectMapped = NO;
    } else {
        self->isDirectMapped = NO;
    }

    if (self->isDirectMapped == wasDirectMapped)
        return;
    if (self->isDirectMapped == YES) {
        [self updateState];
    } else {
        if (self->interceptRect != nil) {
            [self->interceptRect removeFromWindowServer];
            [self->interceptRect release];
            self->interceptRect = nil;
        }
        self->isBuffered = YES;
        self->isUnobscured = NO;
    }
}

- (BOOL)_isUnobscured
{
    NSShape *screenShape = [self->interceptRect currentScreenRectShape];
    BOOL unobscured = [self->_dbm_private isEqual:screenShape];

    if (unobscured && self->_viewClip != nil)
        unobscured = [self->_dbm_private isEqual:self->_viewClip];
    return unobscured;
}

- (id)_updateBuffer
{
    NSRect screenRect = [self->interceptRect currentScreenRect];
    unsigned char *screenAddress = (unsigned char *)
        [(NSFramebuffer *)self->framebuffer addressForPoint:screenRect.origin];
    unsigned char *buffer;
    int rowBytes = (self->pixelsWide * self->bitsPerPixel + 7) / 8;
    int sourcePadding = [(NSFramebuffer *)self->framebuffer bytesPerRow] - rowBytes;
    int destinationPadding = self->bytesPerRow - rowBytes;

    [(NSFramebuffer *)self->framebuffer lockWithMode:self->fbMode];
    buffer = [self _dataBuffer];
    ((NSBitmapCopyFunction)self->copyFunc)(screenAddress, sourcePadding,
        buffer, destinationPadding, self->pixelsWide, self->pixelsHigh);
    self->_screenIsDirty = NO;
    [(NSFramebuffer *)self->framebuffer unlock];
    return self;
}

- (id)_flushInShape:(NSShape *)shape
{
    NSRect screenRect = [self->interceptRect currentScreenRect];
    id<NSShapeEnumerator> enumerator = [shape rectEnumerator];
    NSRect *piece;

    while ((piece = [enumerator nextRect]) != 0) {
        unsigned char *screenAddress = (unsigned char *)
            [(NSFramebuffer *)self->framebuffer addressForPoint:piece->origin];
        unsigned char *buffer, *source;
        int rowBytes = (piece->size.width * self->bitsPerPixel + 7) / 8;
        int sourceY = (int)(piece->origin.y - screenRect.origin.y);
        int sourceX = (int)(piece->origin.x - screenRect.origin.x);
        int sourcePadding = self->bytesPerRow - rowBytes;
        int destinationPadding =
            [(NSFramebuffer *)self->framebuffer bytesPerRow] - rowBytes;

        if (screenAddress == 0)
            return nil;
        buffer = [self _dataBuffer];
        source = buffer + sourceY * self->bytesPerRow +
            (sourceX * self->bitsPerPixel + 7) / 8;
        [(NSFramebuffer *)self->framebuffer lockWithMode:self->fbMode];
        ((NSBitmapCopyFunction)self->copyFunc)(source, sourcePadding,
            screenAddress, destinationPadding,
            (int)piece->size.width, (int)piece->size.height);
        [(NSFramebuffer *)self->framebuffer unlock];
    }
    return self;
}

- (void)flushIn:(NSRect)rect
{
    unsigned char *buffer;
    NSRect targetRect;

    if (self->isLocked == NO ||
        (self->isBuffered == NO && self->drawToBuffer == NO))
        return;

    buffer = [self _dataBuffer];
    if (self->isDirectMapped == YES) {
        NSRect screenRect = [self->interceptRect currentScreenRect];
        NSShape *shape = [[NSShape allocWithZone:[self zone]]
            initFromRect:NSOffsetRect(rect, screenRect.origin.x,
                                      screenRect.origin.y)];

        [shape intersectWithShape:self->_dbm_private];
        if (self->_viewClip != nil)
            [shape intersectWithShape:self->_viewClip];
        [self _flushInShape:shape];
        [shape release];
        return;
    }

    targetRect = rect;
    targetRect.origin.y = self->rect.size.height -
        (targetRect.origin.y + targetRect.size.height);
    targetRect = NSOffsetRect(targetRect, self->rect.origin.x,
                              self->rect.origin.y);
    targetRect = NSIntersectionRect(self->rect, targetRect);
    if (NSIsEmptyRect(targetRect))
        return;

    {
        int depth = self->bitsPerSample * self->samplesPerPixel;
        int status;

        if (self->bitsPerPixel == 8 &&
            [self->colorSpace isEqual:NSDeviceRGBColorSpace])
            depth = 8;
        status = InterceptorCompositeBits(
            [self->interceptClient _context], self->gWinNum,
            (int)targetRect.origin.x, (int)targetRect.origin.y, 1,
            buffer + (int)rect.origin.y * self->bytesPerRow +
                ((int)rect.origin.x * self->bitsPerPixel + 7) / 8,
            (int)targetRect.size.width, (int)targetRect.size.height, depth,
            self->bytesPerRow, self->colorSpaceCode);
        if (status != 0)
            printf("InterceptorCompositeBits() returns %d\n", status);
    }
}

- (void)flush
{
    [self flushIn:NSMakeRect(0, 0, self->pixelsWide, self->pixelsHigh)];
}

- (void)hideCursor
{
    InterceptorHideCursor([self->interceptClient _context]);
}

- (void)showCursor
{
    InterceptorShowCursor([self->interceptClient _context]);
}

- (void)setBuffered:(BOOL)buffered
{
    if (buffered == YES && self->isBuffered == NO) {
        [self hideCursor];
        [self lockBitmap];
        if (self->drawToBuffer == NO)
            [self _updateBuffer];
        [self unlockBitmap];
        [self showCursor];
    } else if (buffered == NO && self->isBuffered == YES) {
        [self lockBitmap];
        [self flush];
        [self unlockBitmap];
    }

    if (self->fbMode == NSFramebufferReadWrite && self->isDirectMapped == YES)
        self->isBuffered = buffered;
    else
        self->isBuffered = YES;
}

- (int)areaIsInvalid:(id)interceptedRect
{
    if (interceptedRect == self->interceptRect) {
        self->isUnobscured = NO;
        self->updateNeeded = YES;
    }
    return 0;
}

- (int)areaChangedScreen:(id)interceptedRect
                    from:(int)oldScreen to:(int)newScreen
{
    if (interceptedRect == self->interceptRect) {
        self->isUnobscured = NO;
        if (oldScreen == self->currentScreen && newScreen != oldScreen) {
            self->newScreen = newScreen;
            self->updateNeeded = YES;
        }
    }
    return 0;
}

- (int)areaWindowFreed:(id)interceptedRect
{
    if (interceptedRect == self->interceptRect) {
        self->isUnobscured = NO;
        self->updateNeeded = YES;
    }
    return 0;
}

- (int)areaDidChangeBuffering:(id)interceptedRect toType:(int)type
{
    (void)interceptedRect;
    (void)type;
    self->updateNeeded = YES;
    return 0;
}

- (id)initForRect:(NSRect)rect inWindow:(id)window
{
    unsigned int globalWindowNumber;
    NSNumber *screenNumberValue;
    int screenNumber;

    self->_naughtyFlags = 0;
    self->window = [window retain];
    NSConvertWindowNumberToGlobal([window windowNumber], &globalWindowNumber);
    screenNumberValue = [[[window screen] deviceDescription]
        objectForKey:@"NSScreenNumber"];
    screenNumber = [screenNumberValue intValue];

    self = [self _initForRect:rect
        inWinNum:(int)globalWindowNumber
        onScreen:screenNumber];
    if (self != nil && [window backingType] == NSBackingStoreBuffered)
        [self setDirectMapped:NO];
    return self;
}

- (void)updateState
{
    if (self->window != nil) {
        [self updateForRect:self->rect inWindow:self->window];
        if ([self->window backingType] == NSBackingStoreBuffered)
            [self setDirectMapped:NO];
    } else {
        [self _updateForRect:self->rect
            inWinNum:self->gWinNum
            onScreen:self->newScreen];
    }
}

- (void)lockBitmap
{
    if (self->interceptRect != nil)
        [self->interceptRect lockRect];
    if (self->updateNeeded == YES) {
        self->updateNeeded = NO;
        if (self->interceptRect != nil)
            [self->interceptRect unlockRect];
        [self updateState];
        if (self->interceptRect != nil)
            [self->interceptRect lockRect];
    }
    if (self->isUnobscured == NO && self->isDirectMapped != NO &&
        self->isBuffered == NO)
        self->isUnobscured = [self _isUnobscured];
    self->drawToBuffer = (self->isUnobscured == NO);
    if (self->isDirectMapped == NO && self->interceptRect != nil)
        [self->interceptRect unlockRect];
    self->isLocked = YES;
}

- (BOOL)tryLockBitmap
{
    if (self->isLocked == YES)
        return NO;
    [self lockBitmap];
    return self->isLocked;
}

- (void)unlockBitmap
{
    self->isLocked = NO;
    if (self->isDirectMapped != NO && self->interceptRect != nil)
        [self->interceptRect unlockRect];
}

- (int)numberOfPlanes
{
    return self->isPlanar ? self->samplesPerPixel : 1;
}

- (int)pixelsWide
{
    return self->pixelsWide;
}

- (int)pixelsHigh
{
    return self->pixelsHigh;
}

- (int)samplesPerPixel
{
    return self->samplesPerPixel;
}

- (NSString *)pixelEncoding
{
    int depth;

    if (self->depthMismatch == NO)
        return [(NSFramebuffer *)self->framebuffer pixelEncoding];

    depth = self->bitsPerSample * self->samplesPerPixel;
    switch (depth) {
    case 8:
        return NSInterceptorEightBitGrey;
    case 12:
        return NSInterceptorTwelveBitRGBColor;
    case 15:
        return NSInterceptorFifteenBitRGBColor;
    case 24:
        return NSInterceptorThirtyTwoBitRGBColor;
    default:
        return NSInterceptorTwoBitGrey;
    }
}

- (NSArray *)pixelEncodings
{
    NSMutableArray *encodings = [NSMutableArray array];
    [encodings addObject:[self pixelEncoding]];
    return [encodings copy];
}

- (void)dealloc
{
    if (self->interceptRect != nil)
        [self->interceptRect setTarget:nil];
    if (self->interceptClient != nil)
        [self->interceptClient release];
    if (self->framebuffer != nil)
        [self->framebuffer release];
    if (self->data[0] != 0)
        NSZoneFree([self zone], self->data[0]);
    [self->window release];
    [super dealloc];
}

@end

void CopyLong(const void *source, int sourcePadding, void *destination,
              int destinationPadding, int longCount, int rowCount)
{
    const unsigned int *sourceWords = (const unsigned int *)source;
    unsigned int *destinationWords = (unsigned int *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < longCount; column++)
            destinationWords[column] = sourceWords[column];
        sourceWords = (const unsigned int *)((const unsigned char *)sourceWords +
            longCount * sizeof(*sourceWords) + sourcePadding);
        destinationWords = (unsigned int *)((unsigned char *)destinationWords +
            longCount * sizeof(*destinationWords) + destinationPadding);
    }
}

void CopyShort(const void *source, int sourcePadding, void *destination,
               int destinationPadding, int shortCount, int rowCount)
{
    const unsigned short *sourceShorts = (const unsigned short *)source;
    unsigned short *destinationShorts = (unsigned short *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < shortCount; column++)
            destinationShorts[column] = sourceShorts[column];
        sourceShorts = (const unsigned short *)((const unsigned char *)sourceShorts +
            shortCount * sizeof(*sourceShorts) + sourcePadding);
        destinationShorts = (unsigned short *)((unsigned char *)destinationShorts +
            shortCount * sizeof(*destinationShorts) + destinationPadding);
    }
}

void CopyByte(const void *source, int sourcePadding, void *destination,
              int destinationPadding, int byteCount, int rowCount)
{
    const unsigned char *sourceBytes = (const unsigned char *)source;
    unsigned char *destinationBytes = (unsigned char *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < byteCount; column++)
            destinationBytes[column] = sourceBytes[column];
        sourceBytes += byteCount + sourcePadding;
        destinationBytes += byteCount + destinationPadding;
    }
}
