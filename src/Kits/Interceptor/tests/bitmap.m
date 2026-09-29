#import <Foundation/NSObject.h>
#import <Foundation/NSAutoreleasePool.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import "../NSBitmap.h"
#import "../Interceptor_types.h"
#import "../InterceptorGlobals.h"
#import "test_support.h"

static int LoadSelectedFramework(void)
{
    const char *root = getenv("FRAMEWORK_ROOT");
    char path[4096];
    if (!root || !*root || strlen(root) + sizeof("/Versions/A/Interceptor") >= sizeof(path))
        return 0;
    strcpy(path, root);
    strcat(path, "/Versions/A/Interceptor");
    if (!dlopen(path, RTLD_NOW | RTLD_GLOBAL)) {
        fprintf(stderr, "cannot load %s: %s\n", path, dlerror());
        return 0;
    }
    return 1;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    unsigned char red[32], green[32], blue[32];
    unsigned char *planes[3];
    unsigned char *reported[5];
    NSSimpleBitmap *bitmap;

    memset(red, 0x13, sizeof(red));
    memset(green, 0x57, sizeof(green));
    memset(blue, 0x9B, sizeof(blue));
    planes[0] = red;
    planes[1] = green;
    planes[2] = blue;

    TestCheck(LoadSelectedFramework(), "loads selected framework for bitmap checks");
    TestCheck([NSInterceptorEightBitPseudoColor isEqual:@"PPPPPPPP"] &&
              [NSInterceptorEightBitGrey isEqual:@"WWWWWWWW"] &&
              [NSInterceptorTwoBitGrey isEqual:@"KK"], "published 2/8-bit encodings");
    TestCheck([NSInterceptorFifteenBitRGBColor isEqual:@"-RRRRRGGGGGBBBBB"] &&
              [NSInterceptorSixteenBitRGBColor isEqual:@"RRRRRGGGGGGBBBBB"] &&
              [NSInterceptorTwelveBitRGBColor isEqual:@"RRRRGGGGBBBB----"] &&
              [NSInterceptorThirtyTwoBitRGBColor isEqual:@"RRRRRRRRGGGGGGGGBBBBBBBB--------"],
              "published RGB encodings");
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
