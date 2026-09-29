#import "Private/InterceptorCopy.h"
#import "Private/InterceptorIPC.h"
#import "Private/NSInterceptorClient.h"
#import "NSFramebuffer.h"
#include <stdlib.h>
#include <strings.h>

static NSFramebuffer **NSFramebufferInstances;
static int NSFramebufferScreenCount;

static void NSFramebufferSetInstanceForScreen(NSFramebuffer *framebuffer,
                                               int screenNumber,
                                               NSInterceptorClient *client)
{
    if (NSFramebufferInstances == 0) {
        NSFramebufferScreenCount =
            InterceptorScreenCount([client _context]);
        NSFramebufferInstances = (NSFramebuffer **)malloc(
            sizeof(NSFramebuffer *) * NSFramebufferScreenCount);
        bzero((char *)NSFramebufferInstances,
              sizeof(NSFramebuffer *) * NSFramebufferScreenCount);
    }

    if (screenNumber >= 0 && screenNumber < NSFramebufferScreenCount)
        NSFramebufferInstances[screenNumber] = framebuffer;
}

static NSFramebuffer *NSFramebufferInstanceForScreen(int screenNumber)
{
    if (NSFramebufferInstances != 0 && screenNumber >= 0 &&
        screenNumber < NSFramebufferScreenCount)
        return NSFramebufferInstances[screenNumber];
    return nil;
}

@implementation NSFramebuffer

- initWithScreen:(NSScreen *)screen
{
    return [self initWithScreen:screen andMapIfPossible:YES];
}

- initWithScreen:(NSScreen *)screen andMapIfPossible:(BOOL)map
{
    NSDictionary *deviceDescription;
    NSNumber *screenNumberValue;

    if (screen != nil && [screen isKindOfClass:[NSScreen class]]) {
        deviceDescription = [screen deviceDescription];
        screenNumberValue = [deviceDescription objectForKey:@"NSScreenNumber"];
        return [self initFromScreen:[screenNumberValue intValue]
                  andMapIfPossible:map];
    }

    [self release];
    return nil;
}

- initFromScreen:(int)screenNumber andMapIfPossible:(BOOL)map
{
    NSFramebuffer *cachedFramebuffer;
    unsigned char *planes[1];
    void *mappedAddress = 0;
    int pixelsWide, pixelsHigh, bitsPerPixel, bytesPerRow;
    int colorSpaceCode, reserved;
    int bitsPerSample, samplesPerPixel;
    NSString *colorSpaceName;

    cachedFramebuffer = NSFramebufferInstanceForScreen(screenNumber);
    if (cachedFramebuffer != nil) {
        [self release];
        return cachedFramebuffer;
    }

    self->interceptorClient = [[NSInterceptorClient alloc] init];
    if (self->interceptorClient == nil)
        goto failure;

    self->screenNumber = screenNumber;
    if (InterceptorFrameBufferInfo(
            [self->interceptorClient _context], screenNumber, self->driver,
            &self->deviceSlot, &self->deviceUnit, &pixelsWide, &pixelsHigh,
            &bitsPerPixel, &bytesPerRow, &colorSpaceCode,
            self->pixelEncoding, &reserved) != 0)
        goto failure;

    self->isMapped = NO;
    if (map == YES && InterceptorMapFrameBuffer(
                   [self->interceptorClient _context], screenNumber,
                   &mappedAddress) == 0)
        self->isMapped = YES;

    if (colorSpaceCode == 0) {
        colorSpaceName = NSDeviceBlackColorSpace;
        samplesPerPixel = 1;
    } else if (colorSpaceCode == 1) {
        colorSpaceName = NSDeviceWhiteColorSpace;
        samplesPerPixel = 1;
    } else if (colorSpaceCode == 2) {
        colorSpaceName = NSDeviceRGBColorSpace;
        samplesPerPixel = 3;
    } else {
        NSLog(@"NSFramebuffer received unsupported color-space code %d",
              colorSpaceCode);
        goto failure;
    }

    switch (bitsPerPixel) {
    case 2:
        bitsPerSample = 2;
        break;
    case 8:
        bitsPerSample = 8;
        break;
    case 12:
    case 16:
        bitsPerSample = 4;
        bitsPerPixel = 16;
        break;
    case 15:
        bitsPerSample = 5;
        bitsPerPixel = 16;
        break;
    case 24:
    case 32:
        bitsPerSample = 8;
        bitsPerPixel = 32;
        break;
    default:
        NSLog(@"NSFramebuffer received unsupported pixel depth %d",
              bitsPerPixel);
        goto failure;
    }

    planes[0] = (unsigned char *)mappedAddress;
    (void)[self initWithBitmapDataPlanes:planes
                              pixelsWide:pixelsWide
                              pixelsHigh:pixelsHigh
                            bitsPerSample:bitsPerSample
                          samplesPerPixel:samplesPerPixel
                                hasAlpha:NO
                                isPlanar:NO
                           colorSpaceName:colorSpaceName
                              bytesPerRow:bytesPerRow
                             bitsPerPixel:bitsPerPixel];
    NSFramebufferSetInstanceForScreen(self, screenNumber,
                                      self->interceptorClient);
    return self;

failure:
    [self release];
    return nil;
}

- (BOOL)isMappable
{
    return self->isMapped;
}

- (void)unmapScreen
{
    if (self->data[0] != 0)
        (void)InterceptorUnmapFrameBuffer([self->interceptorClient _context],
                                          self->screenNumber, self->data[0]);
    self->data[0] = 0;
}

- (void)remapScreen
{
    void *mappedAddress = 0;
    int wasMapped = self->isMapped;
    int pixelsWide = 0, pixelsHigh = 0, bitsPerPixel = 0, bytesPerRow = 0;
    int colorSpaceCode = 0, reserved = 0;
    int bitsPerSample = 0, samplesPerPixel = 0;
    NSString *colorSpaceName = NSDeviceBlackColorSpace;

    [self unmapScreen];
    (void)InterceptorFrameBufferInfo(
        [self->interceptorClient _context], self->screenNumber, self->driver,
        &self->deviceSlot, &self->deviceUnit, &pixelsWide, &pixelsHigh,
        &bitsPerPixel, &bytesPerRow, &colorSpaceCode,
        self->pixelEncoding, &reserved);

    self->isMapped = NO;
    if (wasMapped == YES && InterceptorMapFrameBuffer(
                                [self->interceptorClient _context],
                                self->screenNumber, &mappedAddress) == 0)
        self->isMapped = YES;

    if (colorSpaceCode == 0) {
        colorSpaceName = NSDeviceBlackColorSpace;
        samplesPerPixel = 1;
    } else if (colorSpaceCode == 1) {
        colorSpaceName = NSDeviceWhiteColorSpace;
        samplesPerPixel = 1;
    } else if (colorSpaceCode == 2) {
        colorSpaceName = NSDeviceRGBColorSpace;
        samplesPerPixel = 3;
    } else {
        NSLog(@"NSFramebuffer received unsupported color-space code %d",
              colorSpaceCode);
    }

    switch (bitsPerPixel) {
    case 2:
        bitsPerSample = 2;
        break;
    case 8:
        bitsPerSample = 8;
        break;
    case 12:
    case 16:
        bitsPerSample = 4;
        bitsPerPixel = 16;
        break;
    case 15:
        bitsPerSample = 5;
        bitsPerPixel = 16;
        break;
    case 24:
    case 32:
        bitsPerSample = 8;
        bitsPerPixel = 32;
        break;
    default:
        NSLog(@"NSFramebuffer received unsupported pixel depth %d",
              bitsPerPixel);
        break;
    }

    self->data[0] = mappedAddress;
    self->pixelsWide = pixelsWide;
    self->pixelsHigh = pixelsHigh;
    self->bitsPerSample = bitsPerSample;
    self->samplesPerPixel = samplesPerPixel;
    self->colorSpace = colorSpaceName;
    self->colorSpaceCode = colorSpaceCode;
    self->bytesPerRow = bytesPerRow;
    self->bitsPerPixel = bitsPerPixel;
}

- (int)screenNumber
{
    return self->screenNumber;
}

- (int)deviceUnit
{
    return self->deviceUnit;
}

- (int)deviceSlot
{
    return self->deviceSlot;
}

- (NSString *)pixelEncoding
{
    if (self->publicPixelEncoding == nil)
        self->publicPixelEncoding = [NSString stringWithCString:self->pixelEncoding];
    return self->publicPixelEncoding;
}

- (NSString *)driver
{
    if (self->publicDriver == nil)
        self->publicDriver = [NSString stringWithCString:self->driver];
    return self->publicDriver;
}

- (NSRect)screenBounds
{
#if defined(__ppc__) || defined(__POWERPC__)
    return NSMakeRect(1.0, 1.0, self->pixelsWide, self->pixelsHigh);
#else
    return NSMakeRect(0.0, 0.0, self->pixelsWide, self->pixelsHigh);
#endif
}

- (void *)addressForPoint:(NSPoint)location
{
    if (!self->isMapped)
        return 0;

    return (unsigned char *)self->data[0] + self->bytesPerRow * (int)location.y +
           (int)location.x * self->bitsPerPixel / 8;
}

- (void *)conversionTable
{
    if (self->conversionTable == 0) {
        if (self->bitsPerSample == 5 && self->colorSpaceCode == 2)
            (void)InterceptorGetBM34ToBM35Table(
                [self->interceptorClient _context], &self->conversionTable);
        else if (self->bitsPerSample == 8 && self->colorSpaceCode == 2)
            (void)InterceptorGetBM38ToBM256Table(
                [self->interceptorClient _context], &self->conversionTable);
    }
    return self->conversionTable;
}

- (void *)inverseConversionTable
{
    if (self->inverseConversionTable == 0) {
        if (self->bitsPerSample == 5 && self->colorSpaceCode == 2)
            (void)InterceptorGetBM35ToBM34Table(
                [self->interceptorClient _context],
                &self->inverseConversionTable);
        else if (self->bitsPerSample == 8 && self->colorSpaceCode == 2)
            (void)InterceptorGetBM256ToBM38Table(
                [self->interceptorClient _context],
                &self->inverseConversionTable);
    }
    return self->inverseConversionTable;
}

- (BOOL)canLockWithMode:(NSFramebufferAccessMode)mode
{
    (void)mode;
    return YES;
}

- (void)lockWithMode:(NSFramebufferAccessMode)mode
{
    (void)mode;
}

- (void)unlock
{
}

- (id)retain
{
    return self;
}

- (oneway void)release
{
}

- (unsigned int)retainCount
{
    return (unsigned int)-1;
}

- (void)dealloc
{
}

- (id)_interceptorClient
{
    return self->interceptorClient;
}

@end

void CopySrcToDst(const void *source, int sourceStride, void *destination,
                  int destinationStride, int rowCount)
{
    const unsigned char *sourceBytes = (const unsigned char *)source;
    unsigned char *destinationBytes = (unsigned char *)destination;
    int copyBytes = sourceStride < destinationStride ? sourceStride : destinationStride;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < copyBytes; column++)
            destinationBytes[column] = sourceBytes[column];
        sourceBytes += sourceStride;
        destinationBytes += destinationStride;
    }
}
