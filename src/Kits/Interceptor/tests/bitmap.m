#import <Foundation/NSObject.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "../NSBitmap.h"
#import "../NSDirectBitmap.h"
#import "../Interceptor_types.h"
#import "../InterceptorGlobals.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    unsigned char red[32], green[32], blue[32];
    unsigned char *planes[3];
    unsigned char *reported[5];
    NSSimpleBitmap *bitmap;
    NSDirectBitmap *directBitmap;
    BOOL directInitRejected = NO;

    memset(red, 0x13, sizeof(red));
    memset(green, 0x57, sizeof(green));
    memset(blue, 0x9B, sizeof(blue));
    planes[0] = red;
    planes[1] = green;
    planes[2] = blue;

    TestCheck(TestLoadSelectedFramework() != 0, "loads selected framework for bitmap checks");
    TestCheck([NSInterceptorEightBitPseudoColor isEqual:@"PPPPPPPP"] &&
              [NSInterceptorEightBitGrey isEqual:@"WWWWWWWW"] &&
              [NSInterceptorTwoBitGrey isEqual:@"KK"], "published 2/8-bit encodings");
    TestCheck([NSInterceptorFifteenBitRGBColor isEqual:@"-RRRRRGGGGGBBBBB"] &&
              [NSInterceptorSixteenBitRGBColor isEqual:@"RRRRRGGGGGGBBBBB"] &&
              [NSInterceptorTwelveBitRGBColor isEqual:@"RRRRGGGGBBBB----"] &&
              [NSInterceptorThirtyTwoBitRGBColor isEqual:@"RRRRRRRRGGGGGGGGBBBBBBBB--------"],
              "published RGB encodings");
    NS_DURING
        [[NSDirectBitmap alloc] init];
    NS_HANDLER
        directInitRejected = [[localException name] isEqual:NSGenericException];
    NS_ENDHANDLER
    TestCheck(directInitRejected,
              "plain init rejects direct bitmaps without a rectangle and window");
    directBitmap = [NSDirectBitmap alloc];
    TestCheck(directBitmap != nil, "allocates direct bitmap metadata object");
    if (directBitmap) {
        TestCheck([directBitmap bitsPerPixel] == 0 &&
                  [directBitmap bitsPerSample] == 0 &&
                  [directBitmap samplesPerPixel] == 0 &&
                  [directBitmap pixelsWide] == 0 &&
                  [directBitmap pixelsHigh] == 0,
                  "direct bitmap exposes its inherited zeroed sample metadata");
        TestCheck([directBitmap bytesPerRow] == 0 &&
                  [directBitmap bytesPerPlane] == 0 &&
                  [directBitmap numberOfPlanes] == 1 &&
                  ![directBitmap hasAlpha] && ![directBitmap isPlanar] &&
                  ![directBitmap isBuffered] &&
                  ![directBitmap isDirectMapped],
                  "unlocked direct bitmap reports zero row storage and one plane");
        TestCheck([directBitmap bitmapData] == 0,
                  "unlocked direct bitmap does not expose pixel storage");
        memset(reported, 0x5A, sizeof(reported));
        [directBitmap getBitmapDataPlanes:reported];
        TestCheck(reported[0] == 0 && reported[1] == 0 &&
                  reported[2] == 0 && reported[3] == 0 && reported[4] == 0,
                  "unlocked direct bitmap clears all plane outputs");
        TestCheck([directBitmap conversionTable] == 0 &&
                  [directBitmap inverseConversionTable] == 0,
                  "unattached direct bitmap has no conversion tables");
        TestCheck([directBitmap pixelEncoding] == nil,
                  "unattached direct bitmap forwards pixel encoding to nil");
        TestCheck([directBitmap tryLockBitmap] &&
                  [directBitmap bytesPerRow] == 0 &&
                  ![directBitmap tryLockBitmap],
                  "direct bitmap locks once and rejects a nested try-lock");
        [directBitmap unlockBitmap];
        TestCheck([directBitmap tryLockBitmap],
                  "direct bitmap can be locked again after unlock");
        [directBitmap unlockBitmap];
        [directBitmap release];
    }
    bitmap = [[NSSimpleBitmap alloc] initWithBitmapDataPlanes:planes
        pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:3
        hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:16 bitsPerPixel:24];
    TestCheck(bitmap != nil, "creates interleaved bitmap");
    TestCheck([bitmap bitmapData] == red, "bitmapData returns the first supplied plane");
    TestCheck([bitmap pixelsWide] == 3 && [bitmap pixelsHigh] == 2, "pixel dimensions");
    TestCheck([bitmap bitsPerSample] == 8 && [bitmap samplesPerPixel] == 3 &&
              [bitmap bitsPerPixel] == 24, "sample and pixel depths");
    TestCheck([bitmap bytesPerRow] == 16 && [bitmap bytesPerPlane] == 32,
              "explicit row bytes and computed plane size");
    TestCheck([bitmap numberOfPlanes] == 1 && ![bitmap isPlanar] && ![bitmap hasAlpha],
              "interleaved plane count and flags");
    TestCheck([[bitmap colorSpaceName] isEqual:NSDeviceRGBColorSpace], "color space name");
    [bitmap getBitmapDataPlanes:reported];
    TestCheck(reported[0] == red && reported[1] == 0 && reported[2] == 0 &&
              reported[3] == 0 && reported[4] == 0,
              "interleaved plane list and cleared unused entries");
    [bitmap release];

    bitmap = [[NSSimpleBitmap alloc] initWithBitmapDataPlanes:planes
        pixelsWide:3 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:3
        hasAlpha:YES isPlanar:YES colorSpaceName:NSDeviceWhiteColorSpace
        bytesPerRow:7 bitsPerPixel:8];
    TestCheck(bitmap != nil, "creates planar bitmap");
    TestCheck([bitmap numberOfPlanes] == 3 && [bitmap isPlanar] && [bitmap hasAlpha],
              "planar plane count and flags");
    TestCheck([bitmap bytesPerRow] == 7 && [bitmap bytesPerPlane] == 14,
              "planar row bytes and plane size");
    [bitmap getBitmapDataPlanes:reported];
    TestCheck(reported[0] == red && reported[1] == green && reported[2] == blue &&
              reported[3] == 0 && reported[4] == 0,
              "planar plane list and cleared unused entries");
    [bitmap release];

    [pool release];
    return TestFinish();
}
