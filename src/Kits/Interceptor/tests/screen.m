#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSTimer.h>
#import <AppKit/NSColor.h>
#import <stdlib.h>
#import "../NSDirectScreen.h"
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
