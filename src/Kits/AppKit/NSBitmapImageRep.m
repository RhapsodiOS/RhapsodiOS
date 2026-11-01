/*	NSBitmapImageRep.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSZone.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSErrors.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <zlib.h>

APPKIT_EXTERN int _NSAppKitGlobalLock;
APPKIT_EXTERN void _NSAppKitLock(int line, const char *file);
APPKIT_EXTERN void _NSAppKitUnlock(int line, const char *file);
APPKIT_EXTERN void freeVm(void *address, unsigned size);

static NSArray *bitmapImageRepFileTypes;
static NSArray *bitmapImageRepPasteboardTypes;
static const NSTIFFCompression bitmapTIFFCompressionTypes[] = {
    NSTIFFCompressionNone,
    NSTIFFCompressionLZW,
    NSTIFFCompressionJPEG,
    NSTIFFCompressionPackBits,
    NSTIFFCompressionCCITTFAX3,
    NSTIFFCompressionCCITTFAX4
};

static void badBMPFileError(void)
{
    [NSException raise:NSBadBitmapParametersException format:@"Can't read BMP file"];
}

static int DetermineImageDataFormat(NSData *data)
{
    const unsigned char *bytes = [data bytes];
    unsigned length = [data length];

    if (length <= 3)
        return 0;
    if ((bytes[0] == 'I' || bytes[0] == 'M') && bytes[1] == bytes[0])
        return 1;
    if (bytes[0] == 'B' && bytes[1] == 'M')
        return 2;
    if (bytes[0] == 0 && bytes[1] == 0 && bytes[3] == 0 &&
        (bytes[2] == 1 || bytes[2] == 2))
        return 4;
    if (bytes[0] == 40 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0)
        return 3;
    if (length > 5 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' &&
        bytes[3] == '8' && (bytes[4] == '7' || bytes[4] == '9') && bytes[5] == 'a')
        return 5;
    if (length > 7 && bytes[0] == 137 && bytes[1] == 'P' && bytes[2] == 'N' &&
        bytes[3] == 'G' && bytes[4] == 13 && bytes[5] == 10 &&
        bytes[6] == 26 && bytes[7] == 10)
        return 6;
    if (length > 9 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255 &&
        bytes[3] == 224 && bytes[6] == 'J' && bytes[7] == 'F' &&
        bytes[8] == 'I' && bytes[9] == 'F')
        return 7;
    return 0;
}

static int colorSpaceNumber(NSString *name)
{
    if ([name isEqual:NSCalibratedRGBColorSpace] || [name isEqual:NSDeviceRGBColorSpace])
        return 2;
    if ([name isEqual:NSCalibratedWhiteColorSpace] || [name isEqual:NSDeviceWhiteColorSpace])
        return 1;
    if ([name isEqual:NSCalibratedBlackColorSpace] || [name isEqual:NSDeviceBlackColorSpace])
        return 0;
    if ([name isEqual:NSDeviceCMYKColorSpace])
        return 5;
    if ([name isEqual:NSCustomColorSpace])
        return -1;
    return -2;
}

static BOOL validateBitmapParams(int width, int height, int bitsPerSample,
    int samplesPerPixel, int pixelBits, int bytesPerRow, BOOL planar,
    BOOL hasAlpha, int colorSpace)
{
    static const short samplesForColorSpace[] = { 1, 1, 3, 1, -1, 4 };
    int samples = samplesPerPixel;

    if (bitsPerSample != 1 && bitsPerSample != 2 && bitsPerSample != 4 &&
        bitsPerSample != 8 && bitsPerSample != 12)
        return NO;
    if (bitsPerSample == 12 && colorSpace > 1)
        return NO;
    if (width <= 0 || height <= 0 || samplesPerPixel < 1 || samplesPerPixel > 5 ||
        colorSpace < -1 || colorSpace > 5)
        return NO;
    if (colorSpace != -1) {
        int expectedSamples = samplesForColorSpace[colorSpace];
        if (hasAlpha)
            --samples;
        if (samples != expectedSamples)
            return NO;
    }
    if (planar ? pixelBits == bitsPerSample : pixelBits == bitsPerSample * samplesPerPixel)
        return YES;
    return colorSpace == 2 &&
        ((bitsPerSample == 4 && pixelBits == 16) ||
         (bitsPerSample == 8 && pixelBits == 32));
}

@interface NSImageReader : NSObject {
@public
    NSData *data;
    const unsigned char *bytes;
    unsigned length;
    unsigned location;
    int pixelsWide;
    int pixelsHigh;
    int bitsPerPixel;
    int bitsPerSample;
    int samplesPerPixel;
    int numberOfPlanes;
    int bytesPerRow;
    int bytesPerPlane;
    NSString *colorSpaceName;
    NSSize size;
    BOOL hasAlpha;
    BOOL isPlanar;
    BOOL loadError;
    unsigned char *planes[5];
}
- (id)initWithData:(NSData *)imageData;
- (BOOL)loadImageHeader;
- (BOOL)loadImage:(unsigned char **)imagePlanes;
- (unsigned char **)bitmapDataPlanes;
- (int)bitsPerPixel;
- (int)bitsPerSample;
- (int)bytesPerPlane;
- (int)bytesPerRow;
- (NSString *)colorSpaceName;
- (BOOL)hasAlpha;
- (BOOL)isPlanar;
- (int)numberOfPlanes;
- (int)pixelsHigh;
- (int)pixelsWide;
- (int)samplesPerPixel;
- (NSSize)size;
@end

@implementation NSImageReader

- (id)initWithData:(NSData *)imageData
{
    BOOL loaded = NO;
    self = [super init];
    if (self == nil)
        return nil;

    NS_DURING
        data = [imageData copyWithZone:[self zone]];
        bytes = [data bytes];
        length = [data length];
        location = 0;
        loaded = [self loadImageHeader];
    NS_HANDLER
        loaded = NO;
    NS_ENDHANDLER
    if (!loaded) {
        [self release];
        return nil;
    }
    return self;
}

- (BOOL)loadImageHeader
{
    return NO;
}

- (BOOL)loadImage:(unsigned char **)imagePlanes
{
    return NO;
}

- (unsigned char **)bitmapDataPlanes
{
    if (loadError)
        return NULL;

    if (planes[0] == NULL) {
        int i;
        NS_DURING
            for (i = 0; i < numberOfPlanes && i < 5; ++i)
                planes[i] = NSZoneMalloc([self zone], bytesPerPlane);
            loadError = ![self loadImage:planes];
        NS_HANDLER
            loadError = YES;
        NS_ENDHANDLER

        if (loadError) {
            for (i = 0; i < numberOfPlanes && i < 5; ++i) {
                NSZoneFree([self zone], planes[i]);
                planes[i] = NULL;
            }
        }
        [data release];
        data = nil;
        bytes = NULL;
        length = 0;
    }

    return loadError ? NULL : planes;
}

- (int)bitsPerPixel { return bitsPerPixel; }
- (int)bitsPerSample { return bitsPerSample; }
- (int)bytesPerPlane { return bytesPerPlane; }
- (int)bytesPerRow { return bytesPerRow; }
- (NSString *)colorSpaceName { return colorSpaceName; }
- (BOOL)hasAlpha { return hasAlpha; }
- (BOOL)isPlanar { return isPlanar; }
- (int)numberOfPlanes { return numberOfPlanes; }
- (int)pixelsHigh { return pixelsHigh; }
- (int)pixelsWide { return pixelsWide; }
- (int)samplesPerPixel { return samplesPerPixel; }
- (NSSize)size { return size; }

- (void)dealloc
{
    unsigned i;
    for (i = 0; i < numberOfPlanes && i < 5; ++i) {
        NSZoneFree([self zone], planes[i]);
        planes[i] = NULL;
    }
    [data release];
    [super dealloc];
}

@end

@interface NSBMPImageReader : NSImageReader {
@public
    int dibFormat;
    BOOL isFromOS2;
    unsigned imageLocation;
    unsigned colorTableLocation;
    unsigned actualImageSize;
    unsigned actualBitsPerPixel;
    unsigned numberOfPaletteEntries;
    unsigned numberOfSamplesPerPaletteEntry;
}
- (id)initWithData:(NSData *)imageData DIBFormat:(BOOL)isDIB;
- (unsigned char)getByte;
- (unsigned short)getLEWord;
- (unsigned)getLELong;
- (BOOL)loadBitmapFileHeader;
- (BOOL)loadBitmapInfoHeader;
- (unsigned)numberOfPaletteEntries;
- (unsigned)numberOfSamplesPerPaletteEntry;
- (const unsigned short *)palette;
@end

@implementation NSBMPImageReader

- (id)initWithData:(NSData *)imageData DIBFormat:(BOOL)isDIB
{
    dibFormat = isDIB;
    self = [super initWithData:imageData];
    if (self != nil)
        dibFormat = isDIB;
    return self;
}

- (unsigned char)getByte
{
    if (location >= length)
        badBMPFileError();
    return bytes[location++];
}

- (unsigned short)getLEWord
{
    if (location + 2 >= length)
        badBMPFileError();
    unsigned value = bytes[location] | ((unsigned)bytes[location + 1] << 8);
    location += 2;
    return (unsigned short)value;
}

- (unsigned)getLELong
{
    if (location + 4 >= length)
        badBMPFileError();
    unsigned value = bytes[location] |
        ((unsigned)bytes[location + 1] << 8) |
        ((unsigned)bytes[location + 2] << 16) |
        ((unsigned)bytes[location + 3] << 24);
    location += 4;
    return value;
}

- (BOOL)loadBitmapFileHeader
{
    if (dibFormat)
        return YES;
    if ([self getByte] != 'B' || [self getByte] != 'M')
        return NO;
    location += 8;
    imageLocation = [self getLELong];
    return YES;
}

- (BOOL)loadBitmapInfoHeader
{
    unsigned headerStart = location;
    unsigned headerSize = [self getLELong];
    colorTableLocation = headerStart + headerSize;
    unsigned planes;
    unsigned compression = 0;
    unsigned xPixelsPerMeter = 0;
    unsigned yPixelsPerMeter = 0;

    if (headerSize == 12) {
        isFromOS2 = YES;
        pixelsWide = [self getLEWord];
        pixelsHigh = [self getLEWord];
        planes = [self getLEWord];
        actualBitsPerPixel = [self getLEWord];
        numberOfPaletteEntries = 0;
    } else {
        if (headerSize < 40)
            return NO;
        int signedHeight;
        pixelsWide = (int)[self getLELong];
        signedHeight = (int)[self getLELong];
        if (signedHeight <= 0)
            return NO;
        pixelsHigh = signedHeight;
        planes = [self getLEWord];
        actualBitsPerPixel = [self getLEWord];
        compression = [self getLELong];
        actualImageSize = [self getLELong];
        xPixelsPerMeter = [self getLELong];
        yPixelsPerMeter = [self getLELong];
        numberOfPaletteEntries = [self getLELong];
        [self getLELong];
    }

    if (planes != 1 || pixelsWide <= 0 || pixelsHigh <= 0)
        return NO;
    if (actualBitsPerPixel != 4 && actualBitsPerPixel != 8 &&
        actualBitsPerPixel != 16 && actualBitsPerPixel != 24 &&
        actualBitsPerPixel != 32)
        return NO;
    if (compression != 0 && compression != 3)
        return NO;
    if (compression == 3) {
        if ((actualBitsPerPixel != 16 && actualBitsPerPixel != 32) || headerSize != 40)
            return NO;
        location = colorTableLocation;
        unsigned redMask = [self getLELong];
        unsigned greenMask = [self getLELong];
        unsigned blueMask = [self getLELong];
        if (actualBitsPerPixel == 16) {
            if (redMask != 0x7C00 || greenMask != 0x03E0 || blueMask != 0x001F)
                return NO;
        } else if (redMask != 0x00FF0000 || greenMask != 0x0000FF00 ||
                blueMask != 0x000000FF) {
            return NO;
        }
    }

    samplesPerPixel = 3;
    bitsPerSample = 8;
    bitsPerPixel = 24;
    numberOfPlanes = 1;
    bytesPerRow = ((24 * pixelsWide + 31) >> 5) << 2;
    bytesPerPlane = bytesPerRow * pixelsHigh;
    colorSpaceName = NSDeviceRGBColorSpace;
    hasAlpha = NO;
    isPlanar = NO;
    size = NSMakeSize(pixelsWide, pixelsHigh);
    numberOfSamplesPerPaletteEntry = isFromOS2 ? 3 : 4;

    unsigned inputRowBytes = ((actualBitsPerPixel * pixelsWide + 31) >> 5) << 2;
    if (actualImageSize == 0)
        actualImageSize = inputRowBytes * pixelsHigh;

    if (numberOfPaletteEntries == 0 && actualBitsPerPixel <= 8)
        numberOfPaletteEntries = 1U << actualBitsPerPixel;
    if (dibFormat) {
        imageLocation = colorTableLocation;
        if (numberOfPaletteEntries != 0)
            imageLocation += numberOfPaletteEntries * numberOfSamplesPerPaletteEntry;
        else if (compression == 3 && (actualBitsPerPixel == 16 || actualBitsPerPixel == 32))
            imageLocation += 12;
    }

    if (xPixelsPerMeter != 0 && yPixelsPerMeter != 0) {
        size.width = (float)(pixelsWide * 72.0 / xPixelsPerMeter);
        size.height = (float)(pixelsHigh * 72.0 / yPixelsPerMeter);
    }
    return length >= imageLocation + actualImageSize;
}

- (BOOL)loadImageHeader
{
    return [self loadBitmapFileHeader] && [self loadBitmapInfoHeader];
}

- (BOOL)loadImage:(unsigned char **)imagePlanes
{
    if (pixelsHigh == 0 || imagePlanes == NULL || imagePlanes[0] == NULL)
        return pixelsHigh == 0;

    unsigned inputRowBytes = ((actualBitsPerPixel * pixelsWide + 31) >> 5) << 2;
    unsigned char *paletteBytes = (unsigned char *)bytes + colorTableLocation;
    unsigned entryBytes = numberOfSamplesPerPaletteEntry;
    int y, x;

    for (y = 0; y < pixelsHigh; ++y) {
        const unsigned char *src = bytes + imageLocation + (pixelsHigh - y - 1) * inputRowBytes;
        unsigned char *dst = imagePlanes[0] + y * bytesPerRow;
        for (x = 0; x < pixelsWide; ++x) {
            if (actualBitsPerPixel == 4 || actualBitsPerPixel == 8) {
                unsigned index;
                if (actualBitsPerPixel == 4)
                    index = (src[x >> 1] >> ((x & 1) ? 0 : 4)) & 0xF;
                else
                    index = src[x];
                const unsigned char *entry = paletteBytes + index * entryBytes;
                dst[x * 3] = entry[2];
                dst[x * 3 + 1] = entry[1];
                dst[x * 3 + 2] = entry[0];
            } else if (actualBitsPerPixel == 16) {
                unsigned pixel = src[x * 2] | ((unsigned)src[x * 2 + 1] << 8);
                unsigned red = (pixel >> 10) & 31;
                unsigned green = (pixel >> 5) & 31;
                unsigned blue = pixel & 31;
                dst[x * 3] = (red << 3) | (red >> 2);
                dst[x * 3 + 1] = (green << 3) | (green >> 2);
                dst[x * 3 + 2] = (blue << 3) | (blue >> 2);
            } else if (actualBitsPerPixel == 24) {
                dst[x * 3] = src[x * 3 + 2];
                dst[x * 3 + 1] = src[x * 3 + 1];
                dst[x * 3 + 2] = src[x * 3];
            } else if (actualBitsPerPixel == 32) {
                dst[x * 3] = src[x * 4 + 1];
                dst[x * 3 + 1] = src[x * 4 + 2];
                dst[x * 3 + 2] = src[x * 4 + 3];
            } else {
                return NO;
            }
        }
    }
    return YES;
}

- (unsigned)numberOfPaletteEntries { return numberOfPaletteEntries; }
- (unsigned)numberOfSamplesPerPaletteEntry { return numberOfSamplesPerPaletteEntry; }
- (const unsigned short *)palette
{
    return (const unsigned short *)(bytes + colorTableLocation);
}

- (void)dealloc
{
    [super dealloc];
}

@end

typedef struct {
    int width;
    int height;
    int left;
    int top;
    int frameWidth;
    int frameHeight;
    int interlaced;
    int transparentIndex;
    int backgroundIndex;
    int paletteEntries;
    unsigned char palette[256 * 3];
} NSGIFFrameInfo;

static unsigned gifReadWord(const unsigned char *bytes)
{
    return bytes[0] | ((unsigned)bytes[1] << 8);
}

static BOOL gifSkipSubBlocks(const unsigned char *bytes, unsigned length, unsigned *offset)
{
    while (*offset < length) {
        unsigned count = bytes[(*offset)++];
        if (count == 0)
            return YES;
        if (count > length - *offset)
            return NO;
        *offset += count;
    }
    return NO;
}

static BOOL gifReadFrame(const unsigned char *bytes, unsigned length, int frameNumber,
    NSGIFFrameInfo *info, unsigned char *pixels, int components)
{
    unsigned offset = 13;
    unsigned char globalPalette[256 * 3];
    int globalEntries = 0;
    int screenWidth;
    int screenHeight;
    int backgroundIndex;
    int transparentIndex = -1;
    int frame = 0;

    if (length < 13 || memcmp(bytes, "GIF", 3) != 0)
        return NO;
    screenWidth = gifReadWord(bytes + 6);
    screenHeight = gifReadWord(bytes + 8);
    backgroundIndex = bytes[11];
    if (screenWidth <= 0 || screenHeight <= 0 ||
        (unsigned)screenWidth > 0x7fffffffU / 4 / (unsigned)screenHeight)
        return NO;
    if (bytes[10] & 0x80) {
        globalEntries = 2 << (bytes[10] & 7);
        if ((unsigned)(globalEntries * 3) > length - offset)
            return NO;
        memcpy(globalPalette, bytes + offset, globalEntries * 3);
        offset += globalEntries * 3;
    }

    while (offset < length) {
        unsigned char marker = bytes[offset++];
        if (marker == 0x3b)
            return NO;
        if (marker == 0x21) {
            if (offset >= length)
                return NO;
            unsigned char label = bytes[offset++];
            if (label == 0xf9) {
                if (offset + 6 > length || bytes[offset] < 4)
                    return NO;
                unsigned size = bytes[offset++];
                if (size != 4 || offset + 5 > length)
                    return NO;
                unsigned char flags = bytes[offset++];
                offset += 2;
                unsigned char index = bytes[offset++];
                if (flags & 1)
                    transparentIndex = index;
                else
                    transparentIndex = -1;
                if (bytes[offset++] != 0)
                    return NO;
            } else if (!gifSkipSubBlocks(bytes, length, &offset)) {
                return NO;
            }
            continue;
        }
        if (marker != 0x2c || offset + 9 > length)
            return NO;

        unsigned char packed = bytes[offset + 8];
        int left = gifReadWord(bytes + offset);
        int top = gifReadWord(bytes + offset + 2);
        int frameWidth = gifReadWord(bytes + offset + 4);
        int frameHeight = gifReadWord(bytes + offset + 6);
        int interlaced = (packed & 0x40) != 0;
        offset += 9;
        const unsigned char *palette = globalPalette;
        int paletteEntries = globalEntries;
        if (packed & 0x80) {
            paletteEntries = 2 << (packed & 7);
            if ((unsigned)(paletteEntries * 3) > length - offset)
                return NO;
            palette = bytes + offset;
            offset += paletteEntries * 3;
        }
        if (offset >= length || paletteEntries == 0)
            return NO;
        unsigned char minimumCodeSize = bytes[offset++];
        unsigned char *compressed = NULL;
        unsigned compressedLength = 0;
        unsigned compressedCapacity = 0;
        while (offset < length) {
            unsigned count = bytes[offset++];
            if (count == 0)
                break;
            if (count > length - offset) {
                free(compressed);
                return NO;
            }
            if (compressedLength + count > compressedCapacity) {
                unsigned capacity = compressedCapacity ? compressedCapacity * 2 : 256;
                while (capacity < compressedLength + count)
                    capacity *= 2;
                unsigned char *grown = (unsigned char *)realloc(compressed, capacity);
                if (grown == NULL) {
                    free(compressed);
                    return NO;
                }
                compressed = grown;
                compressedCapacity = capacity;
            }
            memcpy(compressed + compressedLength, bytes + offset, count);
            compressedLength += count;
            offset += count;
        }

        if (frame++ != frameNumber) {
            free(compressed);
            transparentIndex = -1;
            continue;
        }
        if (frameWidth <= 0 || frameHeight <= 0 ||
            (unsigned)frameWidth > 0x7fffffffU / (unsigned)frameHeight) {
            free(compressed);
            return NO;
        }
        info->width = screenWidth;
        info->height = screenHeight;
        info->left = left;
        info->top = top;
        info->frameWidth = frameWidth;
        info->frameHeight = frameHeight;
        info->interlaced = interlaced;
        info->transparentIndex = transparentIndex;
        info->backgroundIndex = backgroundIndex;
        info->paletteEntries = paletteEntries;
        memcpy(info->palette, palette, paletteEntries * 3);
        if (pixels == NULL) {
            free(compressed);
            return YES;
        }
        if (minimumCodeSize < 2 || minimumCodeSize > 8 ||
            (unsigned)frameWidth * (unsigned)frameHeight > 0x7fffffffU ||
            left > screenWidth || top > screenHeight ||
            frameWidth > screenWidth - left || frameHeight > screenHeight - top ||
            (unsigned)screenWidth * (unsigned)screenHeight > 0x7fffffffU) {
            free(compressed);
            return NO;
        }

        unsigned char *indices = (unsigned char *)malloc(frameWidth * frameHeight);
        if (indices == NULL) {
            free(compressed);
            return NO;
        }
        unsigned short prefix[4096];
        unsigned char suffix[4096];
        unsigned char stack[4097];
        int clearCode = 1 << minimumCodeSize;
        int endCode = clearCode + 1;
        int nextCode = endCode + 1;
        int codeSize = minimumCodeSize + 1;
        unsigned bitOffset = 0;
        int oldCode = -1;
        int first = 0;
        unsigned outputCount = 0;
        int i;
        for (i = 0; i < clearCode; ++i)
            suffix[i] = i;
        while (bitOffset + codeSize <= compressedLength * 8 &&
            outputCount < (unsigned)frameWidth * frameHeight) {
            unsigned code = 0;
            for (i = 0; i < codeSize; ++i)
                code |= ((compressed[(bitOffset + i) >> 3] >> ((bitOffset + i) & 7)) & 1) << i;
            bitOffset += codeSize;
            if ((int)code == clearCode) {
                codeSize = minimumCodeSize + 1;
                nextCode = endCode + 1;
                oldCode = -1;
                continue;
            }
            if ((int)code == endCode)
                break;
            if ((int)code > nextCode || code >= 4096)
                break;
            int inputCode = code;
            unsigned stackCount = 0;
            if ((int)code == nextCode) {
                if (oldCode < 0)
                    break;
                stack[stackCount++] = first;
                code = oldCode;
            }
            while ((int)code >= clearCode && code < 4096 && stackCount < 4096) {
                stack[stackCount++] = suffix[code];
                code = prefix[code];
            }
            if (code >= (unsigned)clearCode || stackCount >= 4096)
                break;
            first = suffix[code];
            stack[stackCount++] = first;
            while (stackCount != 0 && outputCount < (unsigned)frameWidth * frameHeight)
                indices[outputCount++] = stack[--stackCount];
            if (oldCode >= 0 && nextCode < 4096) {
                prefix[nextCode] = oldCode;
                suffix[nextCode++] = first;
                if (nextCode == (1 << codeSize) && codeSize < 12)
                    ++codeSize;
            }
            oldCode = inputCode;
        }
        free(compressed);
        if (outputCount != (unsigned)frameWidth * frameHeight) {
            free(indices);
            return NO;
        }

        unsigned row = 0;
        unsigned x;
        unsigned char *dst = pixels;
        int pass;
        unsigned char *background = dst;
        unsigned screenPixel;
        unsigned backgroundColor = backgroundIndex < paletteEntries ? backgroundIndex : 0;
        for (screenPixel = 0; screenPixel < (unsigned)screenWidth * screenHeight; ++screenPixel) {
            background[screenPixel * components] = palette[backgroundColor * 3];
            background[screenPixel * components + 1] = palette[backgroundColor * 3 + 1];
            background[screenPixel * components + 2] = palette[backgroundColor * 3 + 2];
            if (components == 4)
                background[screenPixel * components + 3] = 255;
        }
        for (pass = 0; pass < (interlaced ? 4 : 1); ++pass) {
            unsigned y;
            unsigned start = interlaced ? (pass == 0 ? 0 : pass == 1 ? 4 : pass == 2 ? 2 : 1) : 0;
            unsigned step = interlaced ? (pass == 0 ? 8 : pass == 1 ? 8 : pass == 2 ? 4 : 2) : 1;
            for (y = start; y < (unsigned)frameHeight; y += step) {
                for (x = 0; x < (unsigned)frameWidth; ++x) {
                    unsigned index = indices[row * frameWidth + x];
                    unsigned char *pixel = dst +
                        (((unsigned)top + y) * screenWidth + (unsigned)left + x) * components;
                    if (index >= (unsigned)paletteEntries) {
                        free(indices);
                        return NO;
                    }
                    pixel[0] = palette[index * 3];
                    pixel[1] = palette[index * 3 + 1];
                    pixel[2] = palette[index * 3 + 2];
                    if (components == 4)
                        pixel[3] = index == (unsigned)transparentIndex ? 0 : 255;
                }
                ++row;
            }
        }
        free(indices);
        return YES;
    }
    return NO;
}

static int gifFrameCount(const unsigned char *bytes, unsigned length)
{
    unsigned offset = 13;
    int count = 0;
    if (length < 13 || memcmp(bytes, "GIF", 3) != 0)
        return 0;
    if (bytes[10] & 0x80) {
        unsigned paletteBytes = (2 << (bytes[10] & 7)) * 3;
        if (paletteBytes > length - offset)
            return 0;
        offset += paletteBytes;
    }
    while (offset < length) {
        unsigned char marker = bytes[offset++];
        if (marker == 0x3b)
            break;
        if (marker == 0x21) {
            if (offset >= length)
                break;
            ++offset;
            if (!gifSkipSubBlocks(bytes, length, &offset))
                break;
        } else if (marker == 0x2c) {
            if (offset + 9 > length)
                break;
            unsigned char packed = bytes[offset + 8];
            offset += 9;
            if (packed & 0x80) {
                unsigned paletteBytes = (2 << (packed & 7)) * 3;
                if (paletteBytes > length - offset)
                    break;
                offset += paletteBytes;
            }
            if (offset >= length)
                break;
            ++offset;
            if (!gifSkipSubBlocks(bytes, length, &offset))
                break;
            ++count;
        } else {
            break;
        }
    }
    return count;
}

@interface NSGIFImageReader : NSImageReader {
    int _imageNumber;
    unsigned char _colorTable[256 * 3];
    unsigned _colorTableLength;
}
- (BOOL)loadImageHeader;
- (BOOL)loadImage:(unsigned char **)imagePlanes;
- (NSData *)colorTable;
- (void)setImageNumber:(int)imageNumber;
@end

@implementation NSGIFImageReader

- (BOOL)loadImageHeader
{
    NSGIFFrameInfo info;
    if (!gifReadFrame(bytes, length, _imageNumber, &info, NULL, 0))
        return NO;
    pixelsWide = info.width;
    pixelsHigh = info.height;
    hasAlpha = info.transparentIndex >= 0;
    samplesPerPixel = hasAlpha ? 4 : 3;
    bitsPerSample = 8;
    bitsPerPixel = samplesPerPixel * bitsPerSample;
    bytesPerRow = pixelsWide * samplesPerPixel;
    bytesPerPlane = bytesPerRow * pixelsHigh;
    colorSpaceName = NSDeviceRGBColorSpace;
    size = NSMakeSize(pixelsWide, pixelsHigh);
    numberOfPlanes = 1;
    isPlanar = NO;
    _colorTableLength = info.paletteEntries;
    memcpy(_colorTable, info.palette, _colorTableLength * 3);
    return YES;
}

- (BOOL)loadImage:(unsigned char **)imagePlanes
{
    NSGIFFrameInfo info;
    if (imagePlanes == NULL || imagePlanes[0] == NULL)
        return NO;
    return gifReadFrame(bytes, length, _imageNumber, &info, imagePlanes[0], samplesPerPixel);
}

- (NSData *)colorTable
{
    return [NSData dataWithBytes:_colorTable length:_colorTableLength * 3];
}

- (void)setImageNumber:(int)imageNumber
{
    NSGIFFrameInfo info;
    _imageNumber = imageNumber;
    if (gifReadFrame(bytes, length, imageNumber, &info, NULL, 0)) {
        pixelsWide = info.width;
        pixelsHigh = info.height;
        hasAlpha = info.transparentIndex >= 0;
        samplesPerPixel = hasAlpha ? 4 : 3;
        bitsPerSample = 8;
        bitsPerPixel = samplesPerPixel * bitsPerSample;
        bytesPerRow = pixelsWide * samplesPerPixel;
        bytesPerPlane = bytesPerRow * pixelsHigh;
        size = NSMakeSize(pixelsWide, pixelsHigh);
        _colorTableLength = info.paletteEntries;
        memcpy(_colorTable, info.palette, _colorTableLength * 3);
    }
}

@end

typedef struct {
    unsigned width;
    unsigned height;
    int bitDepth;
    int colorType;
    int interlace;
    int hasAlpha;
    int samplesPerPixel;
    float fileGamma;
    unsigned paletteEntries;
    unsigned transparencyLength;
    unsigned short transparentGray;
    unsigned short transparentRed;
    unsigned short transparentGreen;
    unsigned short transparentBlue;
    unsigned char palette[256 * 3];
    unsigned char transparency[256];
    unsigned char *imageData;
    unsigned imageDataLength;
} NSPNGInfo;

static unsigned pngReadLong(const unsigned char *bytes)
{
    return ((unsigned)bytes[0] << 24) | ((unsigned)bytes[1] << 16) |
        ((unsigned)bytes[2] << 8) | bytes[3];
}

static int pngSourceSamples(int colorType)
{
    switch (colorType) {
    case 0: return 1;
    case 2: return 3;
    case 3: return 1;
    case 4: return 2;
    case 6: return 4;
    }
    return 0;
}

static int pngValidBitDepth(int colorType, int bitDepth)
{
    if (colorType == 0)
        return bitDepth == 1 || bitDepth == 2 || bitDepth == 4 || bitDepth == 8 || bitDepth == 16;
    if (colorType == 3)
        return bitDepth == 1 || bitDepth == 2 || bitDepth == 4 || bitDepth == 8;
    if (colorType == 2 || colorType == 4 || colorType == 6)
        return bitDepth == 8 || bitDepth == 16;
    return 0;
}

static void freePNGInfo(NSPNGInfo *info)
{
    free(info->imageData);
    info->imageData = NULL;
    info->imageDataLength = 0;
}

static BOOL readPNGInfo(const unsigned char *bytes, unsigned length, NSPNGInfo *info)
{
    unsigned offset = 8;
    unsigned imageCapacity = 0;
    BOOL hasHeader = NO;
    BOOL hasEnd = NO;

    memset(info, 0, sizeof(*info));
    info->fileGamma = 0.45f;
    if (length < 8 || memcmp(bytes, "\x89PNG\r\n\x1a\n", 8) != 0)
        return NO;

    while (offset <= length && length - offset >= 12) {
        unsigned chunkLength = pngReadLong(bytes + offset);
        const unsigned char *type = bytes + offset + 4;
        const unsigned char *chunk = bytes + offset + 8;
        unsigned crcOffset;
        if (chunkLength > length - offset - 12)
            goto fail;
        crcOffset = offset + 8 + chunkLength;
        if ((unsigned)crc32(crc32(0L, Z_NULL, 0), type, chunkLength + 4) !=
            pngReadLong(bytes + crcOffset))
            goto fail;

        if (memcmp(type, "IHDR", 4) == 0) {
            if (hasHeader || chunkLength != 13)
                goto fail;
            info->width = pngReadLong(chunk);
            info->height = pngReadLong(chunk + 4);
            info->bitDepth = chunk[8];
            info->colorType = chunk[9];
            info->interlace = chunk[12];
            if (info->width == 0 || info->height == 0 ||
                info->width > 0x7fffffffU / 4 / info->height ||
                !pngValidBitDepth(info->colorType, info->bitDepth) ||
                chunk[10] != 0 || chunk[11] != 0 || info->interlace > 1)
                goto fail;
            hasHeader = YES;
        } else if (memcmp(type, "PLTE", 4) == 0) {
            if (!hasHeader || chunkLength == 0 || chunkLength > sizeof(info->palette) ||
                chunkLength % 3 != 0)
                goto fail;
            info->paletteEntries = chunkLength / 3;
            memcpy(info->palette, chunk, chunkLength);
        } else if (memcmp(type, "tRNS", 4) == 0) {
            if (!hasHeader)
                goto fail;
            if (info->colorType == 3) {
                if (chunkLength > sizeof(info->transparency))
                    goto fail;
                info->transparencyLength = chunkLength;
                memcpy(info->transparency, chunk, chunkLength);
            } else if (info->colorType == 0 && chunkLength == 2) {
                info->transparentGray = (chunk[0] << 8) | chunk[1];
                info->transparencyLength = 1;
            } else if (info->colorType == 2 && chunkLength == 6) {
                info->transparentRed = (chunk[0] << 8) | chunk[1];
                info->transparentGreen = (chunk[2] << 8) | chunk[3];
                info->transparentBlue = (chunk[4] << 8) | chunk[5];
                info->transparencyLength = 1;
            } else {
                goto fail;
            }
        } else if (memcmp(type, "gAMA", 4) == 0) {
            if (!hasHeader || chunkLength != 4)
                goto fail;
            unsigned gamma = pngReadLong(chunk);
            if (gamma != 0)
                info->fileGamma = gamma / 100000.0f;
        } else if (memcmp(type, "IDAT", 4) == 0) {
            if (!hasHeader || chunkLength > 0x7fffffffU - info->imageDataLength)
                goto fail;
            if (info->imageDataLength + chunkLength > imageCapacity) {
                unsigned capacity = imageCapacity ? imageCapacity : 1024;
                while (capacity < info->imageDataLength + chunkLength) {
                    if (capacity > 0x3fffffffU) {
                        capacity = info->imageDataLength + chunkLength;
                        break;
                    }
                    capacity *= 2;
                }
                unsigned char *grown = (unsigned char *)realloc(info->imageData, capacity);
                if (grown == NULL)
                    goto fail;
                info->imageData = grown;
                imageCapacity = capacity;
            }
            memcpy(info->imageData + info->imageDataLength, chunk, chunkLength);
            info->imageDataLength += chunkLength;
        } else if (memcmp(type, "IEND", 4) == 0) {
            if (chunkLength != 0)
                goto fail;
            hasEnd = YES;
            break;
        } else if ((type[0] & 0x20) == 0 && memcmp(type, "IHDR", 4) != 0) {
            goto fail;
        }
        offset = crcOffset + 4;
    }

    if (!hasHeader || !hasEnd || info->imageDataLength == 0 ||
        (info->colorType == 3 && (info->paletteEntries == 0 ||
            info->paletteEntries > (1U << info->bitDepth) ||
            info->transparencyLength > info->paletteEntries)))
        goto fail;
    info->hasAlpha = info->colorType == 4 || info->colorType == 6 ||
        info->transparencyLength != 0;
    info->samplesPerPixel = info->colorType == 0 ? 1 :
        info->colorType == 4 ? 2 : info->colorType == 6 ? 4 :
        info->colorType == 3 ? 3 : 3;
    if (info->hasAlpha && info->colorType != 4 && info->colorType != 6)
        ++info->samplesPerPixel;
    return YES;

fail:
    freePNGInfo(info);
    return NO;
}

static unsigned pngSample(const unsigned char *row, unsigned sample, int bitDepth)
{
    if (bitDepth == 16)
        return ((unsigned)row[sample * 2] << 8) | row[sample * 2 + 1];
    if (bitDepth == 8)
        return row[sample];
    unsigned bit = sample * bitDepth;
    unsigned shift = 8 - bitDepth - bit % 8;
    return (row[bit / 8] >> shift) & ((1U << bitDepth) - 1);
}

static unsigned char pngScaleSample(unsigned sample, int bitDepth)
{
    if (bitDepth == 16)
        return sample >> 8;
    if (bitDepth == 8)
        return sample;
    return (sample * 255) / ((1U << bitDepth) - 1);
}

static unsigned char pngCorrectSample(unsigned char sample, float fileGamma)
{
    if (sample == 0 || sample == 255)
        return sample;
    double corrected = pow((double)sample / 255.0, fileGamma * 2.222) * 255.0 + 0.5;
    return corrected > 255.0 ? 255 : (unsigned char)corrected;
}

static unsigned char pngPaeth(unsigned char left, unsigned char above, unsigned char upperLeft)
{
    int estimate = left + above - upperLeft;
    int leftDistance = estimate - left;
    int aboveDistance = estimate - above;
    int upperLeftDistance = estimate - upperLeft;
    if (leftDistance < 0) leftDistance = -leftDistance;
    if (aboveDistance < 0) aboveDistance = -aboveDistance;
    if (upperLeftDistance < 0) upperLeftDistance = -upperLeftDistance;
    if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance)
        return left;
    return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

static BOOL inflatePNGImage(const unsigned char *bytes, unsigned length,
    unsigned char *image, int outputSamples, unsigned bytesPerRow)
{
    static const unsigned char xStart[7] = { 0, 4, 0, 2, 0, 1, 0 };
    static const unsigned char yStart[7] = { 0, 0, 4, 0, 2, 0, 1 };
    static const unsigned char xStep[7] = { 8, 8, 4, 4, 2, 2, 1 };
    static const unsigned char yStep[7] = { 8, 8, 8, 4, 4, 2, 2 };
    NSPNGInfo info;
    unsigned rawLength = 0;
    unsigned char *raw = NULL;
    uLongf outputLength;
    unsigned passCount;
    unsigned pass;
    unsigned rawOffset = 0;
    int sourceSamples;
    unsigned filterBytesPerPixel;
    BOOL success = NO;

    if (!readPNGInfo(bytes, length, &info))
        return NO;
    sourceSamples = pngSourceSamples(info.colorType);
    filterBytesPerPixel = (sourceSamples * info.bitDepth + 7) / 8;
    if (filterBytesPerPixel == 0)
        filterBytesPerPixel = 1;
    passCount = info.interlace ? 7 : 1;
    for (pass = 0; pass < passCount; ++pass) {
        unsigned xs = info.interlace ? xStart[pass] : 0;
        unsigned ys = info.interlace ? yStart[pass] : 0;
        unsigned dx = info.interlace ? xStep[pass] : 1;
        unsigned dy = info.interlace ? yStep[pass] : 1;
        unsigned passWidth = info.width > xs ? (info.width - xs + dx - 1) / dx : 0;
        unsigned passHeight = info.height > ys ? (info.height - ys + dy - 1) / dy : 0;
        if (passWidth > (0x7fffffffU - 7) / (unsigned)(sourceSamples * info.bitDepth))
            goto done;
        unsigned rowBytes = (passWidth * sourceSamples * info.bitDepth + 7) / 8;
        if (passWidth != 0 && passHeight > (0x7fffffffU - rawLength) / (rowBytes + 1))
            goto done;
        rawLength += passHeight * (rowBytes + 1);
    }
    raw = (unsigned char *)malloc(rawLength);
    if (raw == NULL)
        goto done;
    outputLength = rawLength;
    if (uncompress(raw, &outputLength, info.imageData, info.imageDataLength) != Z_OK ||
        outputLength != rawLength)
        goto done;

    rawOffset = 0;
    for (pass = 0; pass < passCount; ++pass) {
        unsigned xs = info.interlace ? xStart[pass] : 0;
        unsigned ys = info.interlace ? yStart[pass] : 0;
        unsigned dx = info.interlace ? xStep[pass] : 1;
        unsigned dy = info.interlace ? yStep[pass] : 1;
        unsigned passWidth = info.width > xs ? (info.width - xs + dx - 1) / dx : 0;
        unsigned passHeight = info.height > ys ? (info.height - ys + dy - 1) / dy : 0;
        if (passWidth > (0x7fffffffU - 7) / (unsigned)(sourceSamples * info.bitDepth))
            goto done;
        unsigned rowBytes = (passWidth * sourceSamples * info.bitDepth + 7) / 8;
        unsigned char *previous;
        unsigned rowIndex;
        if (passWidth == 0 || passHeight == 0)
            continue;
        previous = (unsigned char *)calloc(rowBytes, 1);
        if (previous == NULL)
            goto done;
        for (rowIndex = 0; rowIndex < passHeight; ++rowIndex) {
            unsigned char filter = raw[rawOffset++];
            unsigned char *row = raw + rawOffset;
            unsigned byteIndex;
            for (byteIndex = 0; byteIndex < rowBytes; ++byteIndex) {
                unsigned char left = byteIndex >= filterBytesPerPixel ? row[byteIndex - filterBytesPerPixel] : 0;
                unsigned char above = previous[byteIndex];
                unsigned char upperLeft = byteIndex >= filterBytesPerPixel ?
                    previous[byteIndex - filterBytesPerPixel] : 0;
                if (filter == 1)
                    row[byteIndex] = (unsigned char)(row[byteIndex] + left);
                else if (filter == 2)
                    row[byteIndex] = (unsigned char)(row[byteIndex] + above);
                else if (filter == 3)
                    row[byteIndex] = (unsigned char)(row[byteIndex] + ((left + above) >> 1));
                else if (filter == 4)
                    row[byteIndex] = (unsigned char)(row[byteIndex] + pngPaeth(left, above, upperLeft));
                else if (filter != 0) {
                    free(previous);
                    goto done;
                }
            }
            unsigned column;
            for (column = 0; column < passWidth; ++column) {
                unsigned x = xs + column * dx;
                unsigned y = ys + rowIndex * dy;
                unsigned char *pixel = image + y * bytesPerRow + x * outputSamples;
                unsigned value[4] = { 0, 0, 0, 255 };
                if (info.colorType == 0) {
                    value[0] = pngSample(row, column, info.bitDepth);
                    value[1] = value[0];
                    value[2] = value[0];
                    value[0] = pngScaleSample(value[0], info.bitDepth);
                    value[3] = (info.transparencyLength &&
                        pngSample(row, column, info.bitDepth) == info.transparentGray) ? 0 : 255;
                } else if (info.colorType == 2) {
                    int c;
                    for (c = 0; c < 3; ++c)
                        value[c] = pngSample(row, column * 3 + c, info.bitDepth);
                    value[3] = info.transparencyLength &&
                        value[0] == info.transparentRed && value[1] == info.transparentGreen &&
                        value[2] == info.transparentBlue ? 0 : 255;
                    for (c = 0; c < 3; ++c)
                        value[c] = pngScaleSample(value[c], info.bitDepth);
                } else if (info.colorType == 3) {
                    unsigned index = pngSample(row, column, info.bitDepth);
                    if (index >= info.paletteEntries) {
                        free(previous);
                        goto done;
                    }
                    value[0] = info.palette[index * 3];
                    value[1] = info.palette[index * 3 + 1];
                    value[2] = info.palette[index * 3 + 2];
                    value[3] = index < info.transparencyLength ? info.transparency[index] : 255;
                } else if (info.colorType == 4) {
                    unsigned gray = pngSample(row, column * 2, info.bitDepth);
                    value[0] = pngScaleSample(gray, info.bitDepth);
                    value[1] = value[0];
                    value[2] = value[0];
                    value[3] = pngScaleSample(pngSample(row, column * 2 + 1, info.bitDepth), info.bitDepth);
                } else {
                    int c;
                    for (c = 0; c < 3; ++c)
                        value[c] = pngScaleSample(pngSample(row, column * 4 + c, info.bitDepth), info.bitDepth);
                    value[3] = pngScaleSample(pngSample(row, column * 4 + 3, info.bitDepth), info.bitDepth);
                }
                pixel[0] = value[0];
                if (info.colorType == 0 || info.colorType == 4) {
                    if (outputSamples > 1) {
                        pixel[1] = value[3];
                    }
                } else {
                    pixel[1] = value[1];
                    pixel[2] = value[2];
                    if (outputSamples == 4)
                        pixel[3] = value[3];
                }
            }
            memcpy(previous, row, rowBytes);
            rawOffset += rowBytes;
        }
        free(previous);
    }
    if (rawOffset == rawLength) {
        unsigned y;
        unsigned colorSamples = outputSamples == 2 ? 1 :
            outputSamples == 4 ? 3 : outputSamples;
        for (y = 0; y < info.height; ++y) {
            unsigned x;
            unsigned char *row = image + y * bytesPerRow;
            for (x = 0; x < info.width; ++x) {
                unsigned char *pixel = row + x * outputSamples;
                unsigned channel;
                for (channel = 0; channel < colorSamples; ++channel)
                    pixel[channel] = pngCorrectSample(pixel[channel], info.fileGamma);
            }
        }
        if (outputSamples == 2 || outputSamples == 4) {
            for (y = 0; y < info.height; ++y) {
                unsigned x;
                unsigned char *row = image + y * bytesPerRow;
                for (x = 0; x < info.width; ++x) {
                    unsigned char *pixel = row + x * outputSamples;
                    unsigned char alpha = pixel[outputSamples - 1];
                    int c;
                    for (c = 0; c < outputSamples - 1; ++c)
                        pixel[c] = (pixel[c] * alpha) / 255;
                }
            }
        }
        success = YES;
    }

done:
    free(raw);
    freePNGInfo(&info);
    return success;
}

@interface NSPNGImageReader : NSImageReader
- (BOOL)loadImageHeader;
- (BOOL)loadImage:(unsigned char **)imagePlanes;
@end

@implementation NSPNGImageReader

- (BOOL)loadImageHeader
{
    NSPNGInfo info;
    if (!readPNGInfo(bytes, length, &info))
        return NO;
    pixelsWide = info.width;
    pixelsHigh = info.height;
    hasAlpha = info.hasAlpha;
    samplesPerPixel = info.samplesPerPixel;
    bitsPerSample = 8;
    bitsPerPixel = samplesPerPixel * 8;
    bytesPerRow = pixelsWide * samplesPerPixel;
    bytesPerPlane = bytesPerRow * pixelsHigh;
    colorSpaceName = (info.colorType == 0 || info.colorType == 4) ?
        NSDeviceWhiteColorSpace : NSDeviceRGBColorSpace;
    size = NSMakeSize(pixelsWide, pixelsHigh);
    numberOfPlanes = 1;
    isPlanar = NO;
    freePNGInfo(&info);
    return YES;
}

- (BOOL)loadImage:(unsigned char **)imagePlanes
{
    if (imagePlanes == NULL || imagePlanes[0] == NULL)
        return NO;
    return inflatePNGImage(bytes, length, imagePlanes[0], samplesPerPixel, bytesPerRow);
}

@end

@interface NSBitmapImageRep (Private)
- (BOOL)_loadData;
- (id)_initWithDIB:(NSData *)dibData;
- (id)_initWithImageReader:(NSImageReader *)reader;
+ (NSArray *)_imagesWithData:(NSData *)data zone:(NSZone *)zone;
@end

@implementation NSBitmapImageRep

+ (void)initialize
{
    if (self == [NSBitmapImageRep class])
        [self setVersion:17];
}

+ (NSArray *)imageUnfilteredFileTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(2037, "NSBitmapImageRep.m");

    if (bitmapImageRepFileTypes == nil)
        bitmapImageRepFileTypes = [[NSArray alloc] initWithObjects:
            @"tiff", @"TIFF", @"TIF", @"bmp", @"BMP", @"ico", @"ICO",
            @"cur", @"CUR", @"jpeg", @"JPEG", @"jpg", @"JPG", @"gif",
            @"GIF", @"png", @"PNG", nil];
    NSArray *types = bitmapImageRepFileTypes;

    if (locked)
        _NSAppKitUnlock(2068, "NSBitmapImageRep.m");
    return types;
}

+ (BOOL)canInitWithData:(NSData *)data
{
    return DetermineImageDataFormat(data) != 0;
}

+ (NSArray *)imageRepsWithData:(NSData *)data
{
    NSData *imageData = [data copyWithZone:NULL];
    NSArray *images = [self _imagesWithData:imageData zone:NULL];
    [imageData release];
    return images;
}

+ (id)imageRepWithData:(NSData *)data
{
    NSArray *images = [self imageRepsWithData:data];
    return [images count] == 0 ? nil : [images objectAtIndex:0];
}

- (id)initWithData:(NSData *)imageData
{
    NSZone *zone = [self zone];
    Class repClass = [self class];
    [self release];

    NSData *copy = [imageData copyWithZone:NULL];
    NSArray *images = [repClass _imagesWithData:copy zone:zone];
    [copy release];
    if ([images count] == 0)
        return nil;
    return [[images objectAtIndex:0] retain];
}

+ (NSArray *)_imagesWithData:(NSData *)data zone:(NSZone *)zone
{
    int format = DetermineImageDataFormat(data);
    NSMutableArray *images = [[NSMutableArray allocWithZone:zone] initWithCapacity:1];

    if (format == 2) {
        NSBMPImageReader *reader = [[NSBMPImageReader allocWithZone:zone]
            initWithData:data DIBFormat:NO];
        if (reader != nil) {
            NSBitmapImageRep *image = [[self allocWithZone:zone] _initWithImageReader:reader];
            [reader release];
            if (image != nil) {
                [images addObject:image];
                [image release];
            }
        }
    } else if (format == 3) {
        NSBitmapImageRep *image = [[self allocWithZone:zone] _initWithDIB:data];
        if (image != nil) {
            [images addObject:image];
            [image release];
        }
    } else if (format == 5) {
        int frameCount = gifFrameCount([data bytes], [data length]);
        int frameNumber;
        for (frameNumber = 0; frameNumber < frameCount; ++frameNumber) {
            NSGIFImageReader *reader = [[NSGIFImageReader allocWithZone:zone] initWithData:data];
            if (reader != nil) {
                [reader setImageNumber:frameNumber];
                NSBitmapImageRep *image = [[self allocWithZone:zone] _initWithImageReader:reader];
                if (image != nil) {
                    [image setProperty:NSImageRGBColorTable withValue:[reader colorTable]];
                    [images addObject:image];
                    [image release];
                }
                [reader release];
            }
        }
    } else if (format == 6) {
        NSPNGImageReader *reader = [[NSPNGImageReader allocWithZone:zone] initWithData:data];
        if (reader != nil) {
            NSBitmapImageRep *image = [[self allocWithZone:zone] _initWithImageReader:reader];
            [reader release];
            if (image != nil) {
                [images addObject:image];
                [image release];
            }
        }
    }

    return [images autorelease];
}

+ (void)getTIFFCompressionTypes:(const NSTIFFCompression **)list count:(int *)numTypes
{
    *list = bitmapTIFFCompressionTypes;
    *numTypes = 6;
}

+ (NSString *)localizedNameForTIFFCompressionType:(NSTIFFCompression)compression
{
    static const NSTIFFCompression types[] = {
        NSTIFFCompressionNone,
        NSTIFFCompressionLZW,
        NSTIFFCompressionJPEG,
        NSTIFFCompressionPackBits,
        NSTIFFCompressionCCITTFAX3,
        NSTIFFCompressionCCITTFAX4,
        NSTIFFCompressionNEXT,
        NSTIFFCompressionOldJPEG
    };
    static NSString *names[] = {
        @"None",
        @"Lempel-Ziv & Welch",
        @"JPEG",
        @"PackBits",
        @"CCITT Group 3",
        @"CCITT Group 4",
        @"Obsolete NeXT 2bit",
        @"Obsolete JPEG"
    };
    int index;

    for (index = 0; index < 8; index++) {
        if (types[index] == compression)
            break;
    }
    if (index == 8)
        return nil;

    NSString *name = names[index];
    return [[NSBundle bundleForClass:self] localizedStringForKey:name value:name table:@"TIFFCompression"];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(2076, "NSBitmapImageRep.m");

    if (bitmapImageRepPasteboardTypes == nil)
        bitmapImageRepPasteboardTypes = [[NSArray alloc] initWithObjects:NSTIFFPboardType, nil];
    NSArray *types = bitmapImageRepPasteboardTypes;

    if (locked)
        _NSAppKitUnlock(2080, "NSBitmapImageRep.m");
    return types;
}

- (BOOL)canBeCompressedUsing:(NSTIFFCompression)compression
{
    if ([_colorSpaceName isEqual:NSNamedColorSpace])
        return NO;

    if (compression == NSTIFFCompressionCCITTFAX3 ||
        compression == NSTIFFCompressionCCITTFAX4) {
        if ([self bitsPerSample] != 1)
            return NO;
        int colors = _moreRepFlags.numColors;
        if (colors == 0) {
            colors = NSNumberOfColorComponents(_colorSpaceName);
            _moreRepFlags.numColors = colors;
        }
        return [self hasAlpha] ? colors == 0 : colors == 1;
    }

    if (compression == NSTIFFCompressionJPEG) {
        if ([self bitsPerSample] > 8)
            return NO;
        int colors = _moreRepFlags.numColors;
        if (colors == 0) {
            colors = NSNumberOfColorComponents(_colorSpaceName);
            _moreRepFlags.numColors = colors;
        }
        return colors + [self hasAlpha] <= 4;
    }

    if (compression > NSTIFFCompressionCCITTFAX4)
        return compression < NSTIFFCompressionJPEG || compression == NSTIFFCompressionPackBits;
    return compression == NSTIFFCompressionNone;
}

- (id)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(int)width
    pixelsHigh:(int)height bitsPerSample:(int)bps samplesPerPixel:(int)spp
    hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar colorSpaceName:(NSString *)spaceName
    bytesPerRow:(int)rowBytes bitsPerPixel:(int)pixelBits
{
    int space = colorSpaceNumber(spaceName);
    if (pixelBits == 0)
        pixelBits = planar ? bps : bps * spp;
    if (rowBytes == 0)
        rowBytes = (pixelBits * width + 7) / 8;
    if (!validateBitmapParams(width, height, bps, spp, pixelBits, rowBytes,
            planar, alpha, space)) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _moreRepFlags.dataLoaded = YES;
    _bytesPerRow = rowBytes;
    _moreRepFlags.bitsPerPixel = pixelBits;
    _moreRepFlags.isPlanar = planar;
    _moreRepFlags.isUnpacked = pixelBits != bps * (planar ? 1 : spp) ||
        rowBytes != (pixelBits * width + 7) / 8;
    _pixelsWide = width;
    _pixelsHigh = height;
    _repFlags.bitsPerSample = bps;
    _repFlags.hasAlpha = alpha;
    _colorSpaceName = [spaceName copyWithZone:NULL];

    [self setSize:NSMakeSize(width, height)];

    if (planes != NULL && planes[0] != NULL) {
        _moreRepFlags.memory = 0;
        if (planar && planes[1] != NULL) {
            _data = (unsigned char *)NSZoneCalloc([self zone], 5, sizeof(unsigned char *));
            _moreRepFlags.explicitPlanes = YES;
            int count = alpha ? spp - 1 : spp;
            int i;
            for (i = 0; i < count && i < 5; ++i)
                ((unsigned char **)_data)[i] = planes[i];
        } else {
            _data = planes[0];
        }
    } else {
        _data = NSZoneMalloc([self zone], rowBytes * height * [self numberOfPlanes]);
        _moreRepFlags.memory = 1;
    }
    return self;
}

- (id)_initWithImageReader:(NSImageReader *)reader
{
    self = [self initWithBitmapDataPlanes:NULL
        pixelsWide:[reader pixelsWide]
        pixelsHigh:[reader pixelsHigh]
        bitsPerSample:[reader bitsPerSample]
        samplesPerPixel:[reader samplesPerPixel]
        hasAlpha:[reader hasAlpha]
        isPlanar:[reader isPlanar]
        colorSpaceName:[reader colorSpaceName]
        bytesPerRow:[reader bytesPerRow]
        bitsPerPixel:[reader bitsPerPixel]];
    if (self == nil)
        return nil;

    unsigned char *planes[5] = { NULL, NULL, NULL, NULL, NULL };
    [self getBitmapDataPlanes:planes];
    if (![reader loadImage:planes]) {
        [self release];
        return nil;
    }
    return self;
}

- (id)_initWithDIB:(NSData *)dibData
{
    NSBMPImageReader *reader = [[NSBMPImageReader allocWithZone:[self zone]]
        initWithData:dibData DIBFormat:YES];
    if (reader == nil) {
        [self release];
        return nil;
    }

    id image = [self _initWithImageReader:reader];
    [reader release];
    return image;
}

- (void)prepareGState
{
}

- (BOOL)_canDrawOutsideOfItsBounds
{
    return NO;
}

- (void)_freeImage
{
    unsigned bytesPerPlane = _bytesPerRow * [self pixelsHigh];
    int planes = [self isPlanar] ? [self numberOfPlanes] : 1;
    unsigned char *planeData[5] = { NULL, NULL, NULL, NULL, NULL };
    int i;

    for (i = 0; i < planes && i < 5; ++i) {
        if (_moreRepFlags.isPlanar) {
            if (_moreRepFlags.explicitPlanes)
                planeData[i] = ((unsigned char **)_data)[i];
            else
                planeData[i] = _data + bytesPerPlane * i;
        } else {
            planeData[i] = _data;
        }
    }

    if (_moreRepFlags.explicitPlanes)
        NSZoneFree(NSZoneFromPointer(_data), _data);
    _data = NULL;

    if (_moreRepFlags.memory == 1) {
        NSZoneFree(NSZoneFromPointer(planeData[0]), planeData[0]);
    } else if (_moreRepFlags.memory == 2) {
        if (_moreRepFlags.explicitPlanes) {
            for (i = 0; i < planes && i < 5; ++i)
                freeVm(planeData[i], bytesPerPlane);
        } else {
            freeVm(planeData[0], bytesPerPlane * planes);
        }
    }

    _moreRepFlags.explicitPlanes = 0;
    _moreRepFlags.memory = 0;
}

- (void)dealloc
{
    [_tiffData release];
    [_properties release];
    [self _freeImage];
    [super dealloc];
}

- (BOOL)isPlanar
{
    return _moreRepFlags.isPlanar;
}

- (int)samplesPerPixel
{
    if (_moreRepFlags.numColors == 0)
        _moreRepFlags.numColors = NSNumberOfColorComponents([self colorSpaceName]);
    return _moreRepFlags.numColors + [self hasAlpha];
}

- (int)bitsPerPixel
{
    return _moreRepFlags.bitsPerPixel;
}

- (int)bytesPerRow
{
    return _bytesPerRow;
}

- (int)bytesPerPlane
{
    return _bytesPerRow * [self pixelsHigh];
}

- (int)numberOfPlanes
{
    return [self isPlanar] ? [self samplesPerPixel] : 1;
}

- (void)getBitmapDataPlanes:(unsigned char **)data
{
    if (!_moreRepFlags.dataLoaded && ![self _loadData])
        return;

    unsigned bytesPerPlane = [self bytesPerPlane];
    int planes = [self numberOfPlanes];
    int i;
    for (i = 0; i < 5; ++i) {
        if (i >= planes) {
            data[i] = NULL;
        } else if (!_moreRepFlags.isPlanar) {
            data[i] = _data;
        } else if (_moreRepFlags.explicitPlanes) {
            data[i] = ((unsigned char **)_data)[i];
        } else {
            data[i] = _data + bytesPerPlane * i;
        }
    }
}

- (unsigned char *)bitmapData
{
    unsigned char *planes[5] = { NULL, NULL, NULL, NULL, NULL };
    [self getBitmapDataPlanes:planes];
    return planes[0];
}

- (void)setCompression:(NSTIFFCompression)compression factor:(float)factor
{
    if (compression <= 0xFFFFF) {
        _moreRepFlags.compression = compression;
        _moreRepFlags.compressionFactor = (int)factor;
    }
}

- (void)getCompression:(NSTIFFCompression *)compression factor:(float *)factor
{
    if (_moreRepFlags.compression != 0) {
        if (compression != NULL)
            *compression = _moreRepFlags.compression;
        if (factor != NULL)
            *factor = _moreRepFlags.compressionFactor;
    } else {
        if (compression != NULL)
            *compression = NSTIFFCompressionNone;
        if (factor != NULL)
            *factor = 0.0;
    }
}

- (id)valueForProperty:(NSString *)property
{
    return [_properties objectForKey:property];
}

- (void)setProperty:(NSString *)property withValue:(id)value
{
    if (_properties == nil)
        _properties = [[NSMutableDictionary alloc] initWithCapacity:1];
    [_properties setObject:value forKey:property];
}

@end

