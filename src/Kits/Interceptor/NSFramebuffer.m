#import "Private/InterceptorCopy.h"
#import "NSFramebuffer.h"

@implementation NSFramebuffer

- (BOOL)isMappable
{
    return self->isMapped;
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
