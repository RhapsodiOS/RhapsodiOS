#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <AppKit/NSColor.h>
#import "../NSDirectPalette.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSColor *red = [NSColor colorWithDeviceRed:1.0 green:0.0 blue:0.0 alpha:1.0];
    NSColor *green = [NSColor colorWithDeviceRed:0.0 green:1.0 blue:0.0 alpha:1.0];
    NSColor *blue = [NSColor colorWithDeviceRed:0.0 green:0.0 blue:1.0 alpha:1.0];
    NSArray *colors = [NSArray arrayWithObjects:red, green, blue, nil];
    NSDirectPalette *palette;
    NSData *raw;
    NSData *changedRaw;
    NSDirectPalette *copy;
    const unsigned char *rawBytes;
    float r, g, b;

    TestCheck(TestLoadSelectedFramework() != 0, "loads selected framework for palette checks");
    palette = [[NSDirectPalette alloc] initWithArrayOfColors:colors];
    TestCheck(palette != nil && [palette count] == 3,
              "palette owns a mutable copy of its color array");
    TestCheck([palette colorAtIndex:0] == red && [palette objectEnumerator] != nil,
              "palette exposes colors and enumeration in array order");
    [palette getRed:&r green:&g blue:&b atIndex:1];
    TestCheck(r == 0.0 && g == 1.0 && b == 0.0,
              "palette component accessor reads the selected color");
    TestCheck([palette indexForColor:green] == 1,
              "exact color match returns its palette index");
    copy = [palette copy];
    TestCheck(copy != palette && [copy isEqual:palette],
              "copy creates an equal independent palette");
    [copy release];

    raw = [[palette rawMachinePalette] retain];
    TestCheck([raw length] == 12 && [palette rawMachinePalette] == raw,
              "raw machine palette is four bytes per color and cached");
    rawBytes = [raw bytes];
#if defined(__ppc__) || defined(__POWERPC__)
    TestCheck(rawBytes[0] == 255 && rawBytes[1] == 0 && rawBytes[2] == 0 &&
              rawBytes[3] == 131,
              "PowerPC palette word ends with gamma-corrected luminance");
#else
    TestCheck(rawBytes[0] == 255 && rawBytes[1] == 0 && rawBytes[2] == 0 &&
              rawBytes[3] == 255,
              "i386 palette word ends with the opaque byte");
#endif
    [palette setColor:blue atIndex:0];
    changedRaw = [palette rawMachinePalette];
    TestCheck(changedRaw != raw && [changedRaw length] == 12,
              "editing a color invalidates the cached raw palette");
    [raw release];
    [palette release];

    palette = [[NSDirectPalette alloc] init];
    TestCheck([palette count] == 256,
              "default palette contains the classic 256-color table");
    [palette getRed:&r green:&g blue:&b atIndex:0];
    TestCheck(r == 0.0 && g == 0.0 && b == 0.0,
              "default palette begins with black");
    [palette getRed:&r green:&g blue:&b atIndex:1];
    TestCheck(r == 1.0 && g == 1.0 && b > 0.8 && b < 0.81,
              "default palette follows the reference color-cube order");
    [palette getRed:&r green:&g blue:&b atIndex:255];
    TestCheck(r == 1.0 && g == 1.0 && b == 1.0,
              "default palette ends with white");
    [palette release];

#if defined(__ppc__) || defined(__POWERPC__)
    palette = [NSDirectPalette defaultGrayPalette];
    TestCheck([palette count] == 256,
              "PowerPC default grayscale palette has 256 entries");
#endif

    [pool release];
    return TestFinish();
}
