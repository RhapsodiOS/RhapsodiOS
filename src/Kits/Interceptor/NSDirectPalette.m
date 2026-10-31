#import "NSDirectPalette.h"
#import "InterceptorGlobals.h"
#import "NSFramebuffer.h"
#import "NSDirectScreen.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <math.h>
#import <string.h>

@interface NSColor (NSDirectPaletteBlend)
- (NSColor *)blendWithFraction:(float)fraction ofColor:(NSColor *)color;
@end

typedef struct {
    NSMutableArray *colors;
    NSData *rawMachinePalette;
} NSDirectPalettePrivate;

static const unsigned char NSDirectPaletteMacRamp[] = {
    0xEE, 0xDD, 0xBB, 0xAA, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11
};

static void NSDirectPaletteRGB(NSColor *color, float *red, float *green, float *blue)
{
    float alpha;
    [color getRed:red green:green blue:blue alpha:&alpha];
}

static NSColor *NSDirectPaletteColor(float red, float green, float blue)
{
    return [NSColor colorWithDeviceRed:red green:green blue:blue alpha:1.0];
}

static NSColor *NSDirectPaletteRGBColor(NSColor *color)
{
#if defined(__ppc__) || defined(__POWERPC__)
    NSString *rgbSpace = NSDeviceRGBColorSpace;
#else
    NSString *rgbSpace = NSCalibratedRGBColorSpace;
#endif
    if (![[color colorSpaceName] isEqual:rgbSpace])
        return [color colorUsingColorSpaceName:rgbSpace];
    return color;
}

@implementation NSDirectPalette

+ (NSDirectPalette *)defaultPalette
{
#if defined(__ppc__) || defined(__POWERPC__)
    return [self defaultColorPalette];
#else
    return [[[self alloc] init] autorelease];
#endif
}

#if defined(__ppc__) || defined(__POWERPC__)
+ (NSDirectPalette *)defaultColorPalette
{
    return [[[self alloc] init] autorelease];
}

+ (NSDirectPalette *)defaultGrayPalette
{
    NSMutableArray *colors = [NSMutableArray array];
    NSDirectPalette *palette;
    int index;

    for (index = 0; index < 256; ++index) {
        float value = (float)index / 255.0;
        [colors addObject:NSDirectPaletteColor(value, value, value)];
    }
    palette = [[self alloc] initWithArrayOfColors:colors];
    return [palette autorelease];
}
#endif

+ (NSDirectPalette *)currentPalette
{
#if defined(__ppc__) || defined(__POWERPC__)
    NSDirectScreen *screen = [[NSDirectScreen alloc] initWithScreen:[NSScreen mainScreen]];
    NSString *encoding = [screen pixelEncoding];
    NSDirectPalette *palette;

    if ([encoding isEqual:NSInterceptorEightBitPseudoColor])
        palette = [self defaultColorPalette];
    else if ([encoding isEqual:NSInterceptorEightBitGrey])
        palette = [self defaultGrayPalette];
    else {
        NSLog(@"No matching palette for screen encoding %@", encoding);
        palette = [self defaultPalette];
    }
    return palette;
#else
    NSFramebuffer *framebuffer = [[NSFramebuffer alloc] initWithScreen:[NSScreen mainScreen]];
    NSString *encoding = [framebuffer pixelEncoding];
    NSDirectPalette *palette;

    if ([encoding isEqual:NSInterceptorEightBitPseudoColor])
        palette = [self defaultPalette];
    else {
        NSLog(@"No matching palette for screen encoding %@", encoding);
        palette = [[self alloc] initWithArrayOfColors:[NSArray array]];
    }
    return palette;
#endif
}

- initWithArrayOfColors:(NSArray *)colorArray
{
    NSDirectPalettePrivate *state;
    self = [super init];
    if (!self)
        return nil;
    state = NSZoneMalloc([self zone], sizeof(*state));
    memset(state, 0, sizeof(*state));
    state->colors = [[NSMutableArray allocWithZone:[self zone]] initWithArray:colorArray];
    self->_private = state;
    return self;
}

- init
{
    static const unsigned char cubeLevels[] = { 255, 204, 153, 102, 51, 0 };
    NSMutableArray *colors = [NSMutableArray array];
    unsigned int red, green, blue, i;

    [colors addObject:NSDirectPaletteColor(0, 0, 0)];
    for (red = 0; red < 6; ++red) {
        for (green = 0; green < 6; ++green) {
            for (blue = 0; blue < 6; ++blue) {
                if ((red == 0 && green == 0 && blue == 0) ||
                    (red == 5 && green == 5 && blue == 5))
                    continue;
                [colors addObject:NSDirectPaletteColor(cubeLevels[red] / 255.0,
                    cubeLevels[green] / 255.0, cubeLevels[blue] / 255.0)];
            }
        }
    }
    for (i = 0; i < sizeof(NSDirectPaletteMacRamp); ++i)
        [colors addObject:NSDirectPaletteColor(NSDirectPaletteMacRamp[i] / 255.0, 0, 0)];
    for (i = 0; i < sizeof(NSDirectPaletteMacRamp); ++i)
        [colors addObject:NSDirectPaletteColor(0, NSDirectPaletteMacRamp[i] / 255.0, 0)];
    for (i = 0; i < sizeof(NSDirectPaletteMacRamp); ++i)
        [colors addObject:NSDirectPaletteColor(0, 0, NSDirectPaletteMacRamp[i] / 255.0)];
    for (i = 0; i < sizeof(NSDirectPaletteMacRamp); ++i) {
        float value = NSDirectPaletteMacRamp[i] / 255.0;
        [colors addObject:NSDirectPaletteColor(value, value, value)];
    }
    [colors addObject:NSDirectPaletteColor(1.0, 1.0, 1.0)];
    return [self initWithArrayOfColors:colors];
}

- (NSColor *)colorAtIndex:(int)index
{
    return [(NSDirectPalettePrivate *)self->_private colors] objectAtIndex:index];
}

- (int)indexForColor:(NSColor *)color
{
    NSMutableArray *colors = ((NSDirectPalettePrivate *)self->_private)->colors;
    NSColor *rgbColor = NSDirectPaletteRGBColor(color);
    float red, green, blue;
    double bestDistance = 1.0;
    int bestIndex = -1;
    int index;
    BOOL grayTarget;

    NSDirectPaletteRGB(rgbColor, &red, &green, &blue);
    grayTarget = red == green && green == blue;
    if (grayTarget) {
        for (index = 0; index < (int)[colors count]; ++index) {
            float candidateRed, candidateGreen, candidateBlue;
            double distance;
            NSDirectPaletteRGB([colors objectAtIndex:index], &candidateRed,
                               &candidateGreen, &candidateBlue);
            if (candidateRed != candidateGreen || candidateGreen != candidateBlue)
                continue;
            distance = (red - candidateRed) * (red - candidateRed) +
                       (green - candidateGreen) * (green - candidateGreen) +
                       (blue - candidateBlue) * (blue - candidateBlue);
            if (distance < 0.12 && distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
        }
    }
    if (bestIndex < 0) {
        for (index = 0; index < (int)[colors count]; ++index) {
            float candidateRed, candidateGreen, candidateBlue;
            double distance;
            NSDirectPaletteRGB([colors objectAtIndex:index], &candidateRed,
                               &candidateGreen, &candidateBlue);
            distance = (red - candidateRed) * (red - candidateRed) +
                       (green - candidateGreen) * (green - candidateGreen) +
                       (blue - candidateBlue) * (blue - candidateBlue);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
        }
    }
    return bestIndex;
}

- (unsigned)count
{
    return [((NSDirectPalettePrivate *)self->_private)->colors count];
}

- (void)dealloc
{
    NSDirectPalettePrivate *state = self->_private;
    [state->colors release];
    [state->rawMachinePalette release];
    NSZoneFree([self zone], state);
    [super dealloc];
}

- (NSEnumerator *)objectEnumerator
{
    return [((NSDirectPalettePrivate *)self->_private)->colors objectEnumerator];
}

- (NSData *)rawMachinePalette
{
    NSDirectPalettePrivate *state = self->_private;
    unsigned count = [state->colors count];
    unsigned int *packed;
    unsigned index;

    if (state->rawMachinePalette)
        return state->rawMachinePalette;
    packed = NSZoneMalloc([self zone], count * sizeof(*packed));
    for (index = 0; index < count; ++index) {
        float red, green, blue;
        int r, g, b, extra;
        double luminance;
        NSDirectPaletteRGB([state->colors objectAtIndex:index], &red, &green, &blue);
        luminance = 0.3 * red + 0.59 * green + 0.11 * blue;
        r = (int)(pow(red, 1.0 / 1.8) * 255.0 + 0.499999);
        g = (int)(pow(green, 1.0 / 1.8) * 255.0 + 0.499999);
        b = (int)(pow(blue, 1.0 / 1.8) * 255.0 + 0.499999);
#if defined(__ppc__) || defined(__POWERPC__)
        extra = (int)(pow(luminance, 1.0 / 1.8) * 255.0 + 0.499999);
#else
        extra = 255;
#endif
        packed[index] = ((unsigned int)r << 24) | ((unsigned int)g << 16) |
                        ((unsigned int)b << 8) | (unsigned int)extra;
    }
    state->rawMachinePalette = [[NSData dataWithBytes:packed
        length:count * sizeof(*packed)] retain];
    NSZoneFree([self zone], packed);
    return state->rawMachinePalette;
}

- (void)setColor:(NSColor *)color atIndex:(int)index
{
    NSDirectPalettePrivate *state = self->_private;
    NSColor *rgbColor;
    [state->rawMachinePalette release];
    state->rawMachinePalette = nil;
    rgbColor = NSDirectPaletteRGBColor(color);
    [state->colors replaceObjectAtIndex:index withObject:rgbColor];
}

- (void)setRed:(float)red green:(float)green blue:(float)blue atIndex:(int)index
{
    [self setColor:NSDirectPaletteColor(red, green, blue) atIndex:index];
}

- (void)getRed:(float *)red green:(float *)green blue:(float *)blue atIndex:(int)index
{
    float alpha;
    [[self colorAtIndex:index] getRed:red green:green blue:blue alpha:&alpha];
}

- (void)setColors:(NSColor **)colors atIndices:(NSRange)range
{
    NSDirectPalettePrivate *state = self->_private;
    unsigned index;
    [state->rawMachinePalette release];
    state->rawMachinePalette = nil;
    for (index = range.location; index < range.location + range.length; ++index) {
        (void)NSDirectPaletteRGBColor(colors[index - range.location]);
        [state->colors replaceObjectAtIndex:index withObject:colors[index - range.location]];
    }
}

- (NSDirectPalette *)copy
{
    return [self copyWithZone:[self zone]];
}

- (NSDirectPalette *)mutableCopy
{
    return [self mutableCopyWithZone:[self zone]];
}

- (NSDirectPalette *)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithArrayOfColors:
        ((NSDirectPalettePrivate *)self->_private)->colors];
}

- (NSDirectPalette *)mutableCopyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithArrayOfColors:
        ((NSDirectPalettePrivate *)self->_private)->colors];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:((NSDirectPalettePrivate *)self->_private)->colors];
}

- initWithCoder:(NSCoder *)coder
{
    NSDirectPalettePrivate *state;
    self = [super initWithCoder:coder];
    if (!self)
        return nil;
    state = NSZoneMalloc([self zone], sizeof(*state));
    memset(state, 0, sizeof(*state));
    state->colors = [[NSMutableArray allocWithZone:[self zone]] initWithArray:[coder decodeObject]];
    self->_private = state;
    return self;
}

- (BOOL)isEqual:(id)object
{
    unsigned index;
    if (object == self)
        return YES;
    if (![object isKindOfClass:[NSDirectPalette class]] || [self count] != [object count])
        return NO;
    for (index = 0; index < [self count]; ++index) {
        if (![[self colorAtIndex:index] isEqual:[object colorAtIndex:index]])
            return NO;
    }
    return YES;
}

- (NSDirectPalette *)blendedPaletteWithFraction:(float)fraction ofColor:(NSColor *)color
{
    NSDirectPalettePrivate *state = self->_private;
    NSMutableArray *colors = [NSMutableArray array];
    NSColor *rgbColor;
    unsigned index;

    if (fraction <= 0.0)
        return [[self copy] autorelease];
    rgbColor = NSDirectPaletteRGBColor(color);
    if (fraction >= 1.0) {
        for (index = 0; index < [state->colors count]; ++index)
            [colors addObject:rgbColor];
    } else {
        for (index = 0; index < [state->colors count]; ++index) {
            NSColor *source = [state->colors objectAtIndex:index];
            [colors addObject:[source blendWithFraction:fraction ofColor:rgbColor]];
        }
    }
    return [[[[self class] alloc] initWithArrayOfColors:colors] autorelease];
}

@end
