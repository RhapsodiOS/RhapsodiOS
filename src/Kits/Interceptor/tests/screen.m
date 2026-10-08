#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSTimer.h>
#import <AppKit/NSColor.h>
#import <stdlib.h>
#import <string.h>
#import "../NSDirectScreen.h"
#import "../Private/InterceptorDisplayMode.h"
#import "test_support.h"

@interface NSDirectScreen (FadeTest)
- (void)_fadeIn:(NSTimer *)timer;
- (void)_fadeOut:(NSTimer *)timer;
@end

@interface TestDirectScreen : NSDirectScreen
{
@public
    float lastFadeIntensity;
    int fadeCallCount;
    NSColor *lastFadeColor;
}
@end

@implementation TestDirectScreen
- (void)fadeDisplay:(float)intensity toColor:(NSColor *)color
{
    lastFadeIntensity = intensity;
    lastFadeColor = color;
    fadeCallCount++;
}
@end

typedef struct {
    void *isa;
    void *privateState;
} DirectScreenObjectPrefix;

typedef struct {
    int colorSpace;
    int depth;
    int displayDepth;
    int bitsPerPixel;
    int bitsPerSample;
    int samplesPerPixel;
    int encoding;
    const char *encodingString;
} ExpectedModeFormat;

static const ExpectedModeFormat expectedModeFormats[] = {
    { 0, 0, 2, 2, 2, 1, NSDirectScreenModeTwoBitGrey, "KK" },
    { 0, 1, 8, 8, 8, 1, NSDirectScreenModeBlackEightBit, "KKKKKKKK" },
    { 0, 2, 12, 16, 12, 1, NSDirectScreenModeBlackTwelveBit, "KKKKKKKKKKKK----" },
    { 0, 3, 15, 16, 15, 1, NSDirectScreenModeBlackFifteenBit, "-KKKKKKKKKKKKKKK" },
    { 0, 4, 24, 32, 24, 1, NSDirectScreenModeBlackTwentyFourBit,
      "KKKKKKKKKKKKKKKKKKKKKKKK--------" },
    { 1, 0, 2, 2, 2, 1, NSDirectScreenModeEightBitGrey, "WWWWWWWW" },
    { 1, 1, 8, 8, 8, 1, NSDirectScreenModeEightBitGrey, "WWWWWWWW" },
    { 1, 2, 12, 16, 12, 1, NSDirectScreenModeWhiteTwelveBit, "WWWWWWWWWWWW----" },
    { 1, 3, 15, 16, 15, 1, NSDirectScreenModeWhiteFifteenBit,
      "-WWWWWWWWWWWWWWW" },
    { 1, 4, 24, 32, 24, 1, NSDirectScreenModeWhiteTwentyFourBit,
      "WWWWWWWWWWWWWWWWWWWWWWWW--------" },
    { 2, 0, 2, 2, 1, 3, NSDirectScreenModeTwoBitPseudoColor, "PP" },
    { 2, 1, 8, 8, 2, 3, NSDirectScreenModeEightBitPseudoColor, "PPPPPPPP" },
    { 2, 2, 12, 16, 4, 3, NSDirectScreenModeTwelveBitRGB, "RRRRGGGGBBBB----" },
    { 2, 3, 15, 16, 5, 3, NSDirectScreenModeFifteenBitRGB, "-RRRRRGGGGGBBBBB" },
    { 2, 4, 24, 32, 8, 3, NSDirectScreenModeThirtyTwoBitRGB,
      "RRRRRRRRGGGGGGGGBBBBBBBB--------" }
};

static void CheckModeFormatTable(void)
{
    unsigned int index;
    for (index = 0; index < sizeof(expectedModeFormats) /
                            sizeof(expectedModeFormats[0]); ++index) {
        const ExpectedModeFormat *expected = &expectedModeFormats[index];
        NSDirectScreenModeFormat actual;
        TestCheck(NSDirectScreenModeFormatForCodes(expected->colorSpace,
                    expected->depth, &actual) &&
                  actual.depth == expected->displayDepth &&
                  actual.bitsPerPixel == expected->bitsPerPixel &&
                  actual.bitsPerSample == expected->bitsPerSample &&
                  actual.samplesPerPixel == expected->samplesPerPixel &&
                  actual.encoding == expected->encoding &&
                  strcmp(NSDirectScreenPixelEncodingForCode(actual.encoding),
                         expected->encodingString) == 0,
                  "display mode color-space/depth maps to reference format metadata");
    }
    {
        NSDirectScreenModeFormat ignored;
        TestCheck(!NSDirectScreenModeFormatForCodes(3, 0, &ignored) &&
                  !NSDirectScreenModeFormatForCodes(0, 5, &ignored),
                  "unsupported display mode formats are rejected");
    }
}

static TestDirectScreen *NewFadeTestScreen(NSColor **colorOut)
{
    TestDirectScreen *screen = [[TestDirectScreen alloc] init];
    unsigned int *state = calloc(31, sizeof(*state));
    NSDate *start = [[NSDate dateWithTimeIntervalSinceNow:-0.25] retain];
    NSColor *color = [[NSColor blackColor] retain];

    ((double *)state)[6] = 10.0;
    state[10] = (unsigned int)start;
    state[11] = (unsigned int)color;
    ((DirectScreenObjectPrefix *)screen)->privateState = state;
    *colorOut = color;
    return screen;
}

static void FreeFadeTestScreen(TestDirectScreen *screen)
{
    unsigned int *state = (unsigned int *)
        ((DirectScreenObjectPrefix *)screen)->privateState;
    [(id)state[10] release];
    [(id)state[11] release];
    free(state);
    ((DirectScreenObjectPrefix *)screen)->privateState = 0;
    [screen release];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    TestDirectScreen *fadeScreen;
    NSColor *fadeColor;
    unsigned int *state;
    double elapsed, duration, expectedIntensity, intensityDifference;

    TestCheck(TestLoadSelectedFramework() != 0,
              "loads selected framework for direct-screen checks");
    CheckModeFormatTable();
    TestCheck([[NSDirectScreen alloc] initWithScreen:nil] == nil,
              "rejects a missing screen");

    fadeScreen = NewFadeTestScreen(&fadeColor);
    state = (unsigned int *)
        ((DirectScreenObjectPrefix *)fadeScreen)->privateState;
    elapsed = -[(NSDate *)state[10] timeIntervalSinceNow];
    duration = ((double *)state)[6];
    expectedIntensity = elapsed / duration;
    [fadeScreen _fadeIn:nil];
    intensityDifference = fadeScreen->lastFadeIntensity - expectedIntensity;
    if (intensityDifference < 0.0)
        intensityDifference = -intensityDifference;
    TestCheck(fadeScreen->fadeCallCount == 1 &&
              intensityDifference < 0.01 &&
              fadeScreen->lastFadeColor == fadeColor,
              "fade-in callback applies its intermediate intensity");
    FreeFadeTestScreen(fadeScreen);

    fadeScreen = NewFadeTestScreen(&fadeColor);
    state = (unsigned int *)
        ((DirectScreenObjectPrefix *)fadeScreen)->privateState;
    elapsed = -[(NSDate *)state[10] timeIntervalSinceNow];
    duration = ((double *)state)[6];
    expectedIntensity = 1.0 - elapsed / duration;
    [fadeScreen _fadeOut:nil];
    intensityDifference = fadeScreen->lastFadeIntensity - expectedIntensity;
    if (intensityDifference < 0.0)
        intensityDifference = -intensityDifference;
    TestCheck(fadeScreen->fadeCallCount == 1 &&
              intensityDifference < 0.01 &&
              fadeScreen->lastFadeColor == fadeColor,
              "fade-out callback applies its intermediate intensity");
    FreeFadeTestScreen(fadeScreen);

    [pool release];
    return TestFinish();
}
