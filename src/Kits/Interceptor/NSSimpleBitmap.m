#import "NSBitmap.h"
#import <AppKit/NSGraphics.h>

@implementation NSSimpleBitmap

- initWithBitmapDataPlanes:(unsigned char **)planes
    pixelsWide:(int)width
    pixelsHigh:(int)height
    bitsPerSample:(int)bps
    samplesPerPixel:(int)spp
    hasAlpha:(BOOL)alpha
    isPlanar:(BOOL)planar
    colorSpaceName:(NSString *)space
    bytesPerRow:(int)rowBytes
    bitsPerPixel:(int)pixelBits
{
    int plane;

    [super init];

    for (plane = 0; plane < spp; plane++)
        data[plane] = planes[plane];

    pixelsWide = width;
    pixelsHigh = height;
    bitsPerSample = bps;
    samplesPerPixel = spp;
    hasAlpha = alpha;
    isPlanar = planar;
    colorSpace = [space copy];
    bytesPerRow = rowBytes;
    bitsPerPixel = pixelBits;

    if ([colorSpace isEqual:NSDeviceRGBColorSpace])
        colorSpaceCode = NSRGBColorSpace;
    else if ([colorSpace isEqual:NSDeviceWhiteColorSpace])
        colorSpaceCode = NSOneIsWhiteColorSpace;
    else
        colorSpaceCode = NSOneIsBlackColorSpace;

    return self;
}

- (unsigned char *)bitmapData
{
    return data[0];
}

- (char *)data
{
    return (char *)[self bitmapData];
}

- (void)getBitmapDataPlanes:(unsigned char **)planes
{
    int plane;
    int count = [self numberOfPlanes];

    for (plane = 0; plane < count; plane++)
        planes[plane] = data[plane];
    for (; plane <= 4; plane++)
        planes[plane] = 0;
}

- (BOOL)isPlanar
{
    return isPlanar;
}

- (BOOL)hasAlpha
{
    return hasAlpha;
}

- (int)samplesPerPixel
{
    return samplesPerPixel;
}

- (int)bitsPerSample
{
    return bitsPerSample;
}

- (int)bitsPerPixel
{
    return bitsPerPixel;
}

- (int)bytesPerRow
{
    return bytesPerRow;
}

- (int)bytesPerPlane
{
    return bytesPerRow * pixelsHigh;
}

- (int)numberOfPlanes
{
    return isPlanar ? samplesPerPixel : 1;
}

- (NSString *)colorSpaceName
{
    return colorSpace;
}

- (NSString *)colorSpace
{
    return [self colorSpaceName];
}

- (int)pixelsWide
{
    return pixelsWide;
}

- (int)pixelsHigh
{
    return pixelsHigh;
}

- (void)dealloc
{
    [colorSpace release];
    [super dealloc];
}

@end
