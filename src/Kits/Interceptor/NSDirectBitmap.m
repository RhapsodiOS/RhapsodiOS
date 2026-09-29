#import "Private/InterceptorCopy.h"
#import "Private/NSInterceptedRect.h"
#import "NSDirectBitmap.h"
#import "NSFramebuffer.h"
#import <Foundation/NSZone.h>
#import <strings.h>

@interface NSDirectBitmap (ReconstructionPrivate)
- (BOOL)_isUnobscured;
@end

@implementation NSDirectBitmap

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

@end

void CopyLong(const void *source, int sourceStride, void *destination,
              int destinationStride, int longCount, int rowCount)
{
    const unsigned int *sourceWords = (const unsigned int *)source;
    unsigned int *destinationWords = (unsigned int *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < longCount; column++)
            destinationWords[column] = sourceWords[column];
        sourceWords = (const unsigned int *)((const unsigned char *)sourceWords + sourceStride);
        destinationWords = (unsigned int *)((unsigned char *)destinationWords + destinationStride);
    }
}

void CopyShort(const void *source, int sourceStride, void *destination,
               int destinationStride, int shortCount, int rowCount)
{
    const unsigned short *sourceShorts = (const unsigned short *)source;
    unsigned short *destinationShorts = (unsigned short *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < shortCount; column++)
            destinationShorts[column] = sourceShorts[column];
        sourceShorts = (const unsigned short *)((const unsigned char *)sourceShorts + sourceStride);
        destinationShorts = (unsigned short *)((unsigned char *)destinationShorts + destinationStride);
    }
}

void CopyByte(const void *source, int sourceStride, void *destination,
              int destinationStride, int byteCount, int rowCount)
{
    const unsigned char *sourceBytes = (const unsigned char *)source;
    unsigned char *destinationBytes = (unsigned char *)destination;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        for (column = 0; column < byteCount; column++)
            destinationBytes[column] = sourceBytes[column];
        sourceBytes += sourceStride;
        destinationBytes += destinationStride;
    }
}
