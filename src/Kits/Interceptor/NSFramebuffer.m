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
