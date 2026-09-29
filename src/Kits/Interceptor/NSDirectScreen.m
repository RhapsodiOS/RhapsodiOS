#import "NSDirectScreen.h"
#import "NSFramebuffer.h"
#import "Private/InterceptorIPC.h"
#import "Private/InterceptorCopy.h"
#import <driverkit/driverServer.h>
#import <driverkit/displayDefs.h>
#import <Foundation/NSException.h>
#import <Foundation/NSData.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSRunLoop.h>
#import <AppKit/dpsOpenStep.h>
#import <AppKit/psops.h>
#import <AppKit/psopsNeXT.h>
#import <mach/mach.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

NSString *NSDirectScreenHeight = @"NSDirectScreenHeight";
NSString *NSDirectScreenWidth = @"NSDirectScreenWidth";
NSString *NSDirectScreenDepth = @"NSDirectScreenDepth";
NSString *NSDirectScreenColorSpace = @"NSDirectScreenColorSpace";
NSString *NSDirectScreenPixelEncoding = @"NSDirectScreenPixelEncoding";
NSString *NSDirectScreenModeNumber = @"NSDirectScreenModeNumber";
NSString *NSDirectScreenFrequency = @"NSDirectScreenFrequency";
NSString *NSDirectScreenFrequencyRange = @"NSDirectScreenFrequencyRange";
NSString *NSDirectScreenRowBytes = @"NSDirectScreenRowBytes";
NSString *NSDirectScreenBitsPerPixel = @"NSDirectScreenBitsPerPixel";
NSString *NSDirectScreenBitsPerSample = @"NSDirectScreenBitsPerSample";
NSString *NSDirectScreenSamplesPerPixel = @"NSDirectScreenSamplesPerPixel";
NSString *NSDirectScreenSafeMode = @"NSDirectScreenSafeMode";
NSString *NSDirectScreenDefaultMode = @"NSDirectScreenDefaultMode";

NSString *NSDirectScreenDisplayIsUnshieldedException =
    @"NSDirectScreenDisplayIsUnshieldedException";
NSString *NSDirectScreenDisplayCannotSetPaletteException =
    @"NSDirectScreenDisplayCannotSetPaletteException";

NSString *NSDirectScreenWillStartFadeInNotification =
    @"NSDirectScreenWillStartFadeInNotification";
NSString *NSDirectScreenDidFinishFadeInNotification =
    @"NSDirectScreenDidFinishFadeInNotification";
NSString *NSDirectScreenWillStartFadeOutNotification =
    @"NSDirectScreenWillStartFadeOutNotification";
NSString *NSDirectScreenDidFinishFadeOutNotification =
    @"NSDirectScreenDidFinishFadeOutNotification";
NSString *NSDirectScreenDidChangePaletteNotification =
    @"NSDirectScreenDidChangePaletteNotification";
NSString *NSDirectScreenDidChangeDisplayModeNotification =
    @"NSDirectScreenDidChangeDisplayModeNotification";

static NSString *UnshieldedExceptionFormat =
    @"*** -%@ called with display unshielded.";
static NSString *NoPaletteExceptionFormat =
    @"*** -%@ called when display doesn't support palettes.";

@interface NSDirectScreen (Private)
- (void)_loadPalette:(NSDirectPalette *)palette;
@end
extern vm_size_t vm_page_size;

typedef void *NXEventHandle;
extern NXEventHandle NXOpenEventStatus(void);
extern void NXCloseEventStatus(NXEventHandle handle);
extern double NXScreenBrightness(NXEventHandle handle);
extern double NXAutoDimBrightness(NXEventHandle handle);
extern void NXSetAutoDimBrightness(NXEventHandle handle, double brightness);

@interface NSDirectScreen (Private)
- (void)_clearModeInfo;
- (BOOL)_canLockWithMode:(NSFramebufferAccessMode)mode;
- (void)_lockWithMode:(NSFramebufferAccessMode)mode;
- (void)_unlock;
#if defined(__ppc__) || defined(__POWERPC__)
- (void)setGamma:(double)gamma;
- (void)setGammaRed:(double)red green:(double)green blue:(double)blue;
#else
- (void)setGamma:(float)gamma;
- (void)setGammaRed:(float)red green:(float)green blue:(float)blue;
#endif
- (void)setGammaTableOfSize:(int)size
                        red:(unsigned short *)red
                      green:(unsigned short *)green
                       blue:(unsigned short *)blue;
- (void)_fadeIn:(NSTimer *)timer;
- (void)_fadeOut:(NSTimer *)timer;
@end

static unsigned int *NSDirectScreenWords(void *privateData)
{
    return (unsigned int *)privateData;
}

static void NSDirectScreenCreateBackingStore(NSDirectScreen *screen,
                                             unsigned int *words)
{
    NSFramebuffer *framebuffer = (NSFramebuffer *)words[2];
    unsigned int alignment = (unsigned int)vm_page_size;
    unsigned int bytesPerRow;
    unsigned int size;
    unsigned char *base;
    unsigned char *backingStore;
    unsigned char *source;

#if defined(__ppc__) || defined(__POWERPC__)
    if (words[19] != 0)
        free((void *)(words[19] - alignment));
#else
    if (words[19] != 0)
        free((void *)words[19]);
#endif

    bytesPerRow = (((unsigned int)[screen pixelsWide] *
                    (unsigned int)[screen bitsPerPixel] + 63) >> 3) &
                  0x1ffffff8;
    words[20] = bytesPerRow;
    size = bytesPerRow * (unsigned int)[screen pixelsHigh];
#if defined(__ppc__) || defined(__POWERPC__)
    base = (unsigned char *)malloc(size + 2 * alignment);
    backingStore = base + alignment;
#else
    base = (unsigned char *)malloc(size);
    backingStore = base;
#endif
    words[19] = (unsigned int)backingStore;

    source = [framebuffer bitmapData];
    if (source != 0) {
        (void)InterceptorHideCursor((InterceptorClientContext *)words[0]);
        CopySrcToDst(source, [framebuffer bytesPerRow], backingStore,
                     bytesPerRow, [screen pixelsHigh]);
        (void)InterceptorShowCursor((InterceptorClientContext *)words[0]);
    }
}

static void NSDirectScreenDestroyBackingStore(unsigned int *words)
{
    if (words[19] != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        free((void *)(words[19] - (unsigned int)vm_page_size));
#else
        free((void *)words[19]);
#endif
    }
    words[19] = 0;
    words[20] = 0;
}

static void NSDirectScreenSetPalette(NSDirectScreen *screen,
                                     NSDirectPalette *palette,
                                     SEL selector,
                                     unsigned int *words)
{
    NSString *selectorName = NSStringFromSelector(selector);

    if (![screen displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    if (![screen canSetPalette])
        [NSException raise:NSDirectScreenDisplayCannotSetPaletteException
                    format:NoPaletteExceptionFormat, selectorName];
    [(id)words[8] release];
    words[8] = (unsigned int)[palette retain];
    [screen _loadPalette:palette];
}

static void NSDirectScreenDiscardFade(unsigned int *words)
{
    [(NSTimer *)words[9] invalidate];
    [(id)words[10] release];
    words[10] = 0;
    [(id)words[11] release];
    words[11] = 0;
    [(id)words[9] release];
    words[9] = 0;
}

@implementation NSDirectScreen

- initWithScreen:(NSScreen *)screen
{
    unsigned int *words;
    NSFramebuffer *framebuffer;
    InterceptorClientContext *context;
    port_t masterPort = PORT_NULL;
    port_t devicePort = PORT_NULL;
    IOObjectNumber objectNumber = 0;
    unsigned int values[5];
    unsigned int valueCount = 5;
    NSZone *zone;

    self = [super init];
    if (self == nil)
        return nil;

    zone = [self zone];
    self->_private = NSZoneMalloc(zone, 0x7c);
    memset(self->_private, 0, 0x7c);
    words = NSDirectScreenWords(self->_private);
    [self _clearModeInfo];

    framebuffer = [[NSFramebuffer alloc] initWithScreen:screen];
    words[2] = (unsigned int)framebuffer;
    if (framebuffer == nil || ![framebuffer isMappable])
        goto failure;

    context = InterceptorCreateContext();
    words[0] = (unsigned int)context;
    if (context == 0 ||
        InterceptorGetDeviceAccessTokens(
            context, [framebuffer screenNumber], &masterPort, &objectNumber,
            &devicePort) != 0)
        goto failure;

    words[17] = (unsigned int)masterPort;
    words[18] = objectNumber;
    words[1] = [framebuffer screenNumber];
    words[8] = (unsigned int)[[NSDirectPalette alloc] init];
    ((double *)self->_private)[6] = 1.0;

    if (_IOGetIntValues(masterPort, objectNumber,
                        "IO_Framebuffer_Dimensions", 5, values,
                        &valueCount) == IO_R_SUCCESS)
        words[27] = values[4];
    return self;

failure:
    [self release];
    return nil;
}

- (void)_clearModeInfo
{
    unsigned int *words = NSDirectScreenWords(self->_private);

    words[21] = 0;
    words[22] = (unsigned int)-1;
    words[23] = 0;
    words[24] = 0;
    words[25] = 0;
    words[26] = 0;
#if defined(__ppc__) || defined(__POWERPC__)
    ((float *)self->_private)[28] = 0.7f;
    ((float *)self->_private)[29] = 0.7f;
#else
    ((float *)self->_private)[28] = 0.0f;
    ((float *)self->_private)[29] = 0.0f;
#endif
    ((unsigned char *)self->_private)[66] = 0xff;
}

- (void)dealloc
{
    unsigned int *words;
    id object;
    int index;
    NSZone *zone;

    if (self->_private == 0) {
        [super dealloc];
        return;
    }

    words = NSDirectScreenWords(self->_private);
    if (((unsigned char *)self->_private)[120] != 0)
        [self unshieldDisplay];
    NSDirectScreenDestroyBackingStore(words);

    for (index = 2; index <= 11; index++) {
        if (index != 5 && index != 6 && index != 7 &&
            (object = (id)words[index]) != nil) {
            if (index == 9)
                [object invalidate];
            [object release];
        }
    }
    if (words[0] != 0)
        InterceptorDestroyContext((InterceptorClientContext *)words[0]);
    zone = [self zone];
    NSZoneFree(zone, self->_private);
    self->_private = 0;
    [super dealloc];
}

- (NSSize)screenSize
{
    float *size = (float *)self->_private + 28;

#if defined(__ppc__) || defined(__POWERPC__)
    if (size[0] == 0.7f) {
#else
    if (size[0] <= 0.0f) {
#endif
        NSArray *screens = [NSScreen screens];
        NSScreen *screen = [screens objectAtIndex:[self screenNumber]];
        NSRect frame = [screen frame];
        NSSize frameSize = frame.size;
        size[0] = frameSize.width;
        size[1] = frameSize.height;
    }
    return *(NSSize *)size;
}

- (int)pixelsWide
{
    return (int)[self screenSize].width;
}

- (int)pixelsHigh
{
    return (int)[self screenSize].height;
}

- (void *)addressForPoint:(NSPoint)location
{
    NSFramebuffer *framebuffer = (NSFramebuffer *)NSDirectScreenWords(self->_private)[2];
    unsigned char *base = [framebuffer bitmapData];
    unsigned int x = (unsigned int)location.x;
    unsigned int y = (unsigned int)location.y;

    if (![self displayIsShielded]) {
        NSString *selectorName = NSStringFromSelector(_cmd);
#if defined(__i386__)
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
#else
        NSLog(UnshieldedExceptionFormat, selectorName);
#endif
    }
    return base + [self bytesPerRow] * y +
           (([self bitsPerPixel] * x) >> 3);
}

- (int)bitsPerPixel
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    if (words[23] == 0)
        words[23] = (unsigned int)[(NSFramebuffer *)words[2] bitsPerPixel];
    return (int)words[23];
}

- (int)bitsPerSample
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    if (words[24] == 0)
        words[24] = (unsigned int)[(NSFramebuffer *)words[2] bitsPerSample];
    return (int)words[24];
}

- (int)bytesPerRow
{
    unsigned int *words = NSDirectScreenWords(self->_private);

    if (((unsigned char *)self->_private)[120] != 0) {
        if (words[25] == 0)
            words[25] = (unsigned int)[(NSFramebuffer *)words[2] bytesPerRow];
        return (int)words[25];
    }
    if (words[19] == 0)
        NSDirectScreenCreateBackingStore(self, words);
    return (int)words[20];
}

- (int)bytesPerPlane
{
    return [self bytesPerRow] * [self pixelsHigh];
}

- (int)numberOfPlanes
{
    return 1;
}

- (NSString *)colorSpaceName
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] colorSpaceName];
}

- (unsigned char *)bitmapData
{
    unsigned int *words = NSDirectScreenWords(self->_private);

    if (((unsigned char *)self->_private)[120] != 0)
        return [(NSFramebuffer *)words[2] bitmapData];
    if (words[19] == 0)
        NSDirectScreenCreateBackingStore(self, words);
    return (unsigned char *)words[19];
}

- (void)getBitmapDataPlanes:(unsigned char **)planes
{
    int index;
    planes[0] = [self bitmapData];
    for (index = 1; index < NXSIMPLEBITMAP_MAXPLANES; index++)
        planes[index] = 0;
}

- (BOOL)isPlanar
{
    return NO;
}

- (BOOL)hasAlpha
{
    return NO;
}

- (int)deviceSlot
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] deviceSlot];
}

- (int)deviceUnit
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] deviceUnit];
}

- (BOOL)displayIsShielded
{
    return ((unsigned char *)self->_private)[120] != 0;
}

- (NSString *)driver
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] driver];
}

- (NSString *)pixelEncoding
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] pixelEncoding];
}

- (int)samplesPerPixel
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2]
            samplesPerPixel];
}

- (int)screenNumber
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] screenNumber];
}

- (NSArray *)availableDisplayModes
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    NSFramebuffer *framebuffer = (NSFramebuffer *)words[2];

    if (words[4] == 0) {
        unsigned int currentMode = 0;
        unsigned int modeCount = 0;
        unsigned int returnedCount = 1;

        if (_IOGetIntValues((port_t)words[17], words[18],
                            IO_GET_CURRENT_DISPLAY_MODE, 1,
                            &currentMode, &returnedCount) == IO_R_SUCCESS) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            unsigned int index;
            NSMutableArray *modes;

            returnedCount = 1;
            (void)_IOGetIntValues((port_t)words[17], words[18],
                                  IO_GET_DISPLAY_MODE_NUM, 1,
                                  &modeCount, &returnedCount);
            modes = [[NSMutableArray alloc] initWithCapacity:modeCount];
            words[4] = (unsigned int)modes;
            for (index = 0; index < modeCount; ++index) {
                char parameterName[32];
                unsigned int info[IO_DISPLAY_MODE_INFO_SIZE];
                int bitsPerPixel;
                unsigned int bytesPerRow;
                unsigned int colorSpace;
                unsigned int connectFlags;
                unsigned int infoCount = IO_DISPLAY_MODE_INFO_SIZE;
                NSMutableDictionary *mode;

                sprintf(parameterName, "%s%u", IO_GET_DISPLAY_MODE_INFO,
                        index);
                if (_IOGetIntValues((port_t)words[17], words[18],
                                    parameterName, IO_DISPLAY_MODE_INFO_SIZE,
                                    info, &infoCount) != IO_R_SUCCESS ||
                    info[IO_DISPLAY_MODE_INFO_UNAVAIL_FLAG] != 0)
                    continue;

                switch (info[IO_DISPLAY_MODE_INFO_DEPTH]) {
                case IO_2BitsPerPixel:
                    bitsPerPixel = 2;
                    break;
                case IO_8BitsPerPixel:
                    bitsPerPixel = 8;
                    break;
                case IO_12BitsPerPixel:
                    bitsPerPixel = 16;
                    break;
                case IO_15BitsPerPixel:
                    bitsPerPixel = 16;
                    break;
                case IO_24BitsPerPixel:
                    bitsPerPixel = 32;
                    break;
                default:
                    continue;
                }
                bytesPerRow = info[IO_DISPLAY_MODE_INFO_ROW_BYTES];
                if (bytesPerRow == 0)
                    bytesPerRow = (info[IO_DISPLAY_MODE_INFO_WIDTH] *
                                   (unsigned int)bitsPerPixel + 7) >> 3;
                colorSpace = info[IO_DISPLAY_MODE_INFO_CSPACE];
                connectFlags = info[IO_DISPLAY_MODE_INFO_CONNECT_FLAGS];
                mode = [[NSMutableDictionary alloc] initWithCapacity:9];
                [mode setObject:[NSNumber numberWithInt:(int)info[IO_DISPLAY_MODE_INFO_WIDTH]]
                         forKey:NSDirectScreenWidth];
                [mode setObject:[NSNumber numberWithInt:(int)info[IO_DISPLAY_MODE_INFO_HEIGHT]]
                         forKey:NSDirectScreenHeight];
                [mode setObject:[NSNumber numberWithInt:bitsPerPixel]
                         forKey:NSDirectScreenBitsPerPixel];
                [mode setObject:[NSNumber numberWithInt:(int)index]
                         forKey:NSDirectScreenModeNumber];
                [mode setObject:[NSNumber numberWithInt:(int)bytesPerRow]
                         forKey:NSDirectScreenRowBytes];
                if (info[IO_DISPLAY_MODE_INFO_REFRESH_RATE] != 0)
                    [mode setObject:[NSNumber numberWithInt:(int)info[IO_DISPLAY_MODE_INFO_REFRESH_RATE]]
                             forKey:NSDirectScreenFrequency];
                if (connectFlags & IO_DISPLAY_MODE_SAFE)
                    [mode setObject:[NSNumber numberWithBool:YES]
                             forKey:NSDirectScreenSafeMode];
                if (connectFlags & IO_DISPLAY_MODE_DEFAULT)
                    [mode setObject:[NSNumber numberWithBool:YES]
                             forKey:NSDirectScreenDefaultMode];
                if (colorSpace == IO_RGBColorSpace)
                    [mode setObject:NSDeviceRGBColorSpace
                             forKey:NSDirectScreenColorSpace];
                else if (colorSpace == IO_OneIsBlackColorSpace)
                    [mode setObject:NSDeviceBlackColorSpace
                             forKey:NSDirectScreenColorSpace];
                else if (colorSpace == IO_OneIsWhiteColorSpace)
                    [mode setObject:NSDeviceWhiteColorSpace
                             forKey:NSDirectScreenColorSpace];
                [modes addObject:mode];
                [mode release];
            }
            [pool release];
        }

        if (words[4] == 0) {
            NSMutableArray *modes = [[NSMutableArray alloc] initWithCapacity:1];
            NSMutableDictionary *mode = [[NSMutableDictionary alloc] initWithCapacity:11];

            [mode setObject:[framebuffer driver] forKey:@"driver"];
            [mode setObject:[framebuffer pixelEncoding]
                     forKey:NSDirectScreenPixelEncoding];
            [mode setObject:[NSNumber numberWithInt:[self pixelsWide]]
                     forKey:NSDirectScreenWidth];
            [mode setObject:[NSNumber numberWithInt:[self pixelsHigh]]
                     forKey:NSDirectScreenHeight];
            [mode setObject:[NSNumber numberWithInt:[self bitsPerPixel]]
                     forKey:NSDirectScreenBitsPerPixel];
            [mode setObject:[NSNumber numberWithInt:[self bitsPerSample]]
                     forKey:NSDirectScreenBitsPerSample];
            [mode setObject:[NSNumber numberWithInt:[self samplesPerPixel]]
                     forKey:NSDirectScreenSamplesPerPixel];
            [mode setObject:[framebuffer colorSpaceName]
                     forKey:NSDirectScreenColorSpace];
            [mode setObject:[NSNumber numberWithInt:[self bytesPerRow]]
                     forKey:NSDirectScreenRowBytes];
            [mode setObject:[NSNumber numberWithInt:0]
                     forKey:NSDirectScreenModeNumber];
            [modes addObject:mode];
            [mode release];
            words[4] = (unsigned int)modes;
        }
    }
    return (NSArray *)words[4];
}

- (NSDictionary *)currentMode
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    int currentMode;
    unsigned int returnedCount = 1;
    NSMutableDictionary *options;

    if (words[22] == (unsigned int)-1) {
        currentMode = -1;
        if (_IOGetIntValues((port_t)words[17], words[18],
                            IO_GET_CURRENT_DISPLAY_MODE, 1,
                            (unsigned int *)&currentMode,
                            &returnedCount) != IO_R_SUCCESS || currentMode == -1)
            currentMode = 0;
        words[22] = (unsigned int)currentMode;
    }
    if (words[21] == 0) {
        options = [NSMutableDictionary dictionary];
        [options setObject:[NSNumber numberWithInt:(int)words[22]]
                     forKey:NSDirectScreenModeNumber];
        words[21] = (unsigned int)[self bestModeForOptions:options];
    }
    return (NSDictionary *)words[21];
}

- (NSArray *)availableDisplayModesForOptions:(NSDictionary *)options
{
    NSArray *modes = [self availableDisplayModes];
    NSArray *keys = [options allKeys];
    NSMutableArray *matches = [NSMutableArray array];
    NSEnumerator *modeEnumerator = [modes objectEnumerator];
    NSDictionary *mode;

    while ((mode = [modeEnumerator nextObject]) != nil) {
        NSEnumerator *keyEnumerator = [keys objectEnumerator];
        id key;
        BOOL matchesOptions = YES;

        while ((key = [keyEnumerator nextObject]) != nil) {
            id value = [mode objectForKey:key];
            if (value == nil || ![value isEqual:[options objectForKey:key]]) {
                matchesOptions = NO;
                break;
            }
        }
        if (matchesOptions)
            [matches addObject:mode];
    }
    return matches;
}

- (NSDictionary *)bestModeForOptions:(NSDictionary *)options
{
    NSArray *matches = [self availableDisplayModesForOptions:options];
    if ([matches count] == 0)
        matches = [self availableDisplayModes];
    return [matches count] == 0 ? nil : [matches objectAtIndex:0];
}

- (NSDictionary *)bestModeForFormat:(NSString *)format
                              width:(int)width
                             height:(int)height
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSArray *matches;
    NSDictionary *best = nil;
    int bestWidth = 0x7fffffff;
    int bestHeight = 0x7fffffff;
    NSEnumerator *enumerator;
    NSDictionary *mode;

    [options setObject:[NSNumber numberWithBool:YES]
                forKey:NSDirectScreenSafeMode];
    matches = [self availableDisplayModesForOptions:options];
    if ([matches count] == 0)
        [options removeObjectForKey:NSDirectScreenSafeMode];

    [options setObject:format forKey:NSDirectScreenPixelEncoding];
    [options setObject:[NSNumber numberWithInt:width]
                forKey:NSDirectScreenWidth];
    [options setObject:[NSNumber numberWithInt:height]
                forKey:NSDirectScreenHeight];
    matches = [self availableDisplayModesForOptions:options];
    if ([matches count] != 0)
        return [matches objectAtIndex:0];

    [options removeObjectForKey:NSDirectScreenWidth];
    [options removeObjectForKey:NSDirectScreenHeight];
    matches = [self availableDisplayModesForOptions:options];
    enumerator = [matches objectEnumerator];
    while ((mode = [enumerator nextObject]) != nil) {
        int modeWidth = [[mode objectForKey:NSDirectScreenWidth] intValue];
        int modeHeight = [[mode objectForKey:NSDirectScreenHeight] intValue];
        if (modeWidth >= width && modeHeight >= height &&
            modeWidth < bestWidth && modeWidth < bestHeight) {
            best = mode;
            bestWidth = modeWidth;
            bestHeight = modeHeight;
        }
    }
    if (best != nil)
        return best;
    if ([matches count] != 0)
        return [matches objectAtIndex:0];

    [options removeObjectForKey:NSDirectScreenPixelEncoding];
    [options setObject:[NSNumber numberWithInt:width]
                forKey:NSDirectScreenWidth];
    [options setObject:[NSNumber numberWithInt:height]
                forKey:NSDirectScreenHeight];
    matches = [self availableDisplayModes];
    {
        NSArray *exactMatches = [self availableDisplayModesForOptions:options];
        if ([exactMatches count] != 0)
            return [exactMatches objectAtIndex:0];
    }
    bestWidth = 0x7fffffff;
    bestHeight = 0x7fffffff;
    enumerator = [matches objectEnumerator];
    while ((mode = [enumerator nextObject]) != nil) {
        int modeWidth = [[mode objectForKey:NSDirectScreenWidth] intValue];
        int modeHeight = [[mode objectForKey:NSDirectScreenHeight] intValue];
        if (modeWidth >= width && modeHeight >= height &&
            modeWidth < bestWidth && modeWidth < bestHeight) {
            best = mode;
            bestWidth = modeWidth;
            bestHeight = modeHeight;
        }
    }
    if (best != nil)
        return best;
    return [matches count] == 0 ? nil : [matches objectAtIndex:0];
}

- (void)switchToDisplayMode:(NSDictionary *)mode
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    NSFramebuffer *framebuffer = (NSFramebuffer *)words[2];
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSArray *modes;
    unsigned int modeNumber;
    unsigned char commit = 1;
    unsigned int dimensions[5];
    unsigned int dimensionCount = 5;

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    modes = [self availableDisplayModes];
    if ([modes count] == 0)
        return;

    [self _clearModeInfo];
    modeNumber = (unsigned int)[[mode objectForKey:NSDirectScreenModeNumber]
                                intValue];
    [self hideCursor];
    [framebuffer unmapScreen];
    if (_IOSetIntValues((port_t)words[17], words[18],
                        IO_SET_PENDING_DISPLAY_MODE, &modeNumber, 1) ==
        IO_R_SUCCESS &&
        _IOSetCharValues((port_t)words[17], words[18],
                         IO_COMMIT_TO_PENDING_DISPLAY_MODE,
                         &commit, 1) == IO_R_SUCCESS &&
        _IOGetIntValues((port_t)words[17], words[18],
                        "IO_Framebuffer_Dimensions", 5, dimensions,
                        &dimensionCount) == IO_R_SUCCESS)
        words[27] = dimensions[4];

    words[21] = (unsigned int)mode;
    words[22] = modeNumber;
    [framebuffer remapScreen];
    [self showCursor];
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSNumber *gamma = [defaults objectForKey:@"NSScreenGammaValue"];
        float gammaValue = [gamma floatValue];
        if (gammaValue <= 0.0f)
            gammaValue = 1.6f;
        [self setGamma:gammaValue];
    }
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSDirectScreenDidChangeDisplayModeNotification
                      object:self];
}

- (void)shieldDisplay
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    NSFramebuffer *framebuffer = (NSFramebuffer *)words[2];
    unsigned char *privateBytes = (unsigned char *)self->_private;
    NXEventHandle eventStatus;
    double brightness;

    if ([self displayIsShielded])
        return;
    if (words[3] == 0) {
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:[framebuffer screenBounds]
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [window setLevel:0x7fff];
        PSsetautofill(1, [window windowNumber]);
        PSgsave();
        PSwindowdeviceround([window windowNumber]);
        PSsetrgbcolor(0.0f, 0.0f, 0.0f);
        PSsetexposurecolor();
        PSgrestore();
        words[3] = (unsigned int)window;
    }
    [(NSWindow *)words[3] makeKeyAndOrderFront:nil];
    PSWait();

    eventStatus = NXOpenEventStatus();
    ((double *)self->_private)[7] = NXAutoDimBrightness(eventStatus);
    brightness = NXScreenBrightness(eventStatus);
    NXSetAutoDimBrightness(eventStatus, brightness);
    NXCloseEventStatus(eventStatus);

    if ([self canSetPalette])
        [self _loadPalette:(NSDirectPalette *)words[8]];
    privateBytes[120] = 1;
    words[6] = (unsigned int)[self currentMode];
    if (words[7] == 0)
        words[7] = words[6];
    if (words[6] != words[7])
        [self switchToDisplayMode:(NSDictionary *)words[7]];

    if (words[19] != 0) {
        (void)InterceptorHideCursor((InterceptorClientContext *)words[0]);
        CopySrcToDst((void *)words[19], words[20],
                     [framebuffer bitmapData], [framebuffer bytesPerRow],
                     [self pixelsHigh]);
        (void)InterceptorShowCursor((InterceptorClientContext *)words[0]);
        NSDirectScreenDestroyBackingStore(words);
    }
}

- (void)unshieldDisplay
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    unsigned char *privateBytes = (unsigned char *)self->_private;
    NXEventHandle eventStatus;

    if (![self displayIsShielded])
        return;
    PSWait();
    NSDirectScreenCreateBackingStore(self, words);
    words[7] = (unsigned int)[self currentMode];
    if (words[7] != words[6])
        [self switchToDisplayMode:(NSDictionary *)words[6]];
    if ([self canSetPalette])
        [self _loadPalette:[NSDirectPalette defaultPalette]];
    [(NSWindow *)words[3] orderOut:nil];
    privateBytes[120] = 0;
    PSWait();

    eventStatus = NXOpenEventStatus();
    NXSetAutoDimBrightness(eventStatus, ((double *)self->_private)[7]);
    NXCloseEventStatus(eventStatus);
}

#if defined(__ppc__) || defined(__POWERPC__)
- (void)setGamma:(double)gamma
#else
- (void)setGamma:(float)gamma
#endif
{
    if ((NSDirectScreenWords(self->_private)[27] & 0x10) != 0)
        [self setGammaRed:gamma green:gamma blue:gamma];
}

#if defined(__ppc__) || defined(__POWERPC__)
- (void)setGammaRed:(double)red green:(double)green blue:(double)blue
#else
- (void)setGammaRed:(float)red green:(float)green blue:(float)blue
#endif
{
    unsigned short redTable[256];
    unsigned short greenTable[256];
    unsigned short blueTable[256];
    int index;

    if ((NSDirectScreenWords(self->_private)[27] & 0x10) == 0)
        return;
    for (index = 0; index < 256; ++index) {
        double value = (double)index / 255.0;
        redTable[index] = (unsigned short)(pow(value, 1.0 / red) * 65535.0);
        greenTable[index] = (unsigned short)(pow(value, 1.0 / green) * 65535.0);
        blueTable[index] = (unsigned short)(pow(value, 1.0 / blue) * 65535.0);
    }
    [self setGammaTableOfSize:256 red:redTable green:greenTable blue:blueTable];
}

- (void)setGammaTableOfSize:(int)size
                        red:(unsigned short *)red
                      green:(unsigned short *)green
                       blue:(unsigned short *)blue
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    unsigned int transferCount;
    unsigned int index;
    int bitsPerPixel = [self bitsPerPixel];
    int bitsPerSample = [self bitsPerSample];
    int tableKind;
    unsigned int values[256];
    NSString *selectorName = NSStringFromSelector(_cmd);

    if ((words[27] & 0x10) == 0)
        return;
    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];

    if (bitsPerPixel == 8 && bitsPerSample == 8) {
        transferCount = 256;
        tableKind = 0;
    } else if (bitsPerPixel == 8 && bitsPerSample == 2) {
        transferCount = 256;
        tableKind = 2;
    } else if (bitsPerPixel == 16 && bitsPerSample == 4) {
        transferCount = 16;
        tableKind = 1;
    } else if (bitsPerPixel == 16 && bitsPerSample == 5) {
        transferCount = 32;
        tableKind = 1;
    } else if (bitsPerPixel == 32 && bitsPerSample == 8) {
        transferCount = 256;
        tableKind = 1;
    } else {
        NSLog(@"Unable to set gamma table for %@", self);
        return;
    }

    if (tableKind == 2) {
        NSDirectPalette *palette = (NSDirectPalette *)words[8];
        if (palette == nil)
            palette = [NSDirectPalette defaultPalette];
        if (transferCount > [palette count])
            transferCount = [palette count];
        if (transferCount == 0) {
            NSLog(@"Unable to set gamma table for %@", self);
            return;
        }
        for (index = 0; index < transferCount; ++index) {
            float r, g, b;
            unsigned int rIndex, gIndex, bIndex;
            [palette getRed:&r green:&g blue:&b atIndex:index];
            rIndex = (unsigned int)((size - 1) * r + 0.4999999);
            gIndex = (unsigned int)((size - 1) * g + 0.4999999);
            bIndex = (unsigned int)((size - 1) * b + 0.4999999);
            values[index] = ((unsigned int)(red[rIndex] >> 8) << 24) |
                            ((unsigned int)(green[gIndex] >> 8) << 16) |
                            ((unsigned int)(blue[bIndex] >> 8) << 8) | 0xff;
        }
    } else if (tableKind == 1) {
        for (index = 0; index < transferCount; ++index) {
            unsigned int sourceIndex = index * (unsigned int)(size - 1) /
                                       (transferCount - 1);
#if defined(__ppc__) || defined(__POWERPC__)
            values[index] = ((unsigned int)(red[sourceIndex] & 0xff) << 24) |
                            ((unsigned int)(green[sourceIndex] & 0xff) << 16) |
                            ((unsigned int)(blue[sourceIndex] & 0xff) << 8) |
                            0xff;
#else
            values[index] = ((unsigned int)(red[sourceIndex] >> 8) << 24) |
                            ((unsigned int)(green[sourceIndex] >> 8) << 16) |
                            ((unsigned int)(blue[sourceIndex] >> 8) << 8) |
                            0xff;
#endif
        }
    } else {
        for (index = 0; index < transferCount; ++index) {
            unsigned int sourceIndex = index * (unsigned int)(size - 1) /
                                       (transferCount - 1);
            values[index] = red[sourceIndex] >> 8;
        }
    }

    if (_IOSetIntValues((port_t)words[17], words[18], "IOSetTransferTable",
                        values, transferCount) == IO_R_SUCCESS)
        (void)InterceptorDamagedPalette((InterceptorClientContext *)words[0]);
}

- (NSTimeInterval)fadeDuration
{
    return ((double *)self->_private)[6];
}

- (void)setFadeDuration:(NSTimeInterval)seconds
{
    if (seconds < 0.0)
        seconds = 0.0;
    ((double *)self->_private)[6] = seconds;
}

- (void)fadeDisplay:(float)intensity toColor:(NSColor *)color
{
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSDirectPalette *palette;

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    if (![self canSetPalette])
        [NSException raise:NSDirectScreenDisplayCannotSetPaletteException
                    format:NoPaletteExceptionFormat, selectorName];
    palette = [[self currentPalette]
               blendedPaletteWithFraction:1.0f - intensity ofColor:color];
    [self _loadPalette:palette];
}

- (void)_fadeIn:(NSTimer *)timer
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    double elapsed = -[(NSDate *)words[10] timeIntervalSinceNow];
    double duration = [self fadeDuration];

    (void)timer;
    if (elapsed < duration) {
#if defined(__ppc__) || defined(__POWERPC__)
        [self fadeDisplay:(float)(elapsed / duration)
                  toColor:(NSColor *)words[11]];
#endif
        return;
    }
    [self fadeDisplay:1.0f toColor:(NSColor *)words[11]];
    NSDirectScreenDiscardFade(words);
    ((unsigned char *)self->_private)[65] = 0;
    ((unsigned char *)self->_private)[64] = 0;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSDirectScreenDidFinishFadeInNotification
                      object:self];
}

- (void)_fadeOut:(NSTimer *)timer
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    double elapsed = -[(NSDate *)words[10] timeIntervalSinceNow];
    double duration = [self fadeDuration];

    (void)timer;
    if (elapsed < duration) {
#if defined(__ppc__) || defined(__POWERPC__)
        [self fadeDisplay:(float)(1.0 - elapsed / duration)
                  toColor:(NSColor *)words[11]];
#endif
        return;
    }
    [self fadeDisplay:0.0f toColor:(NSColor *)words[11]];
    NSDirectScreenDiscardFade(words);
    ((unsigned char *)self->_private)[65] = 1;
    ((unsigned char *)self->_private)[64] = 0;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSDirectScreenDidFinishFadeOutNotification
                      object:self];
}

- (void)fadeDisplayInFromColor:(NSColor *)color
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSRunLoop *runLoop;
    NSTimer *timer;
    NSDate *endDate;
    double interval;

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    if (![self canSetPalette])
        [NSException raise:NSDirectScreenDisplayCannotSetPaletteException
                    format:NoPaletteExceptionFormat, selectorName];
    if ([self fadeInProgress])
        NSDirectScreenDiscardFade(words);

    words[10] = (unsigned int)[[NSDate date] retain];
    words[11] = (unsigned int)[color retain];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSDirectScreenWillStartFadeInNotification
                      object:self];
    if (![self fadeApplied])
        [self fadeDisplay:0.0f toColor:color];
    ((unsigned char *)self->_private)[64] = 1;

    runLoop = [NSRunLoop currentRunLoop];
    interval = [self fadeDuration] / 20.0;
    if (interval < 0.05)
        interval = 0.05;
    endDate = [NSDate dateWithTimeIntervalSinceNow:
               [self fadeDuration] + interval];
    timer = [NSTimer timerWithTimeInterval:interval target:self
                                   selector:@selector(_fadeIn:)
                                   userInfo:nil repeats:YES];
    words[9] = (unsigned int)[timer retain];
    [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
    while ([self fadeInProgress])
        [runLoop runUntilDate:endDate];
}

- (void)fadeDisplayOutToColor:(NSColor *)color
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    NSString *selectorName = NSStringFromSelector(_cmd);
    NSRunLoop *runLoop;
    NSTimer *timer;
    NSDate *endDate;
    double interval;

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    if (![self canSetPalette])
        [NSException raise:NSDirectScreenDisplayCannotSetPaletteException
                    format:NoPaletteExceptionFormat, selectorName];
    if ([self fadeInProgress])
        NSDirectScreenDiscardFade(words);

    words[10] = (unsigned int)[[NSDate date] retain];
    words[11] = (unsigned int)[color retain];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSDirectScreenWillStartFadeOutNotification
                      object:self];
    if ([self fadeApplied])
        [self fadeDisplay:1.0f toColor:color];
    ((unsigned char *)self->_private)[64] = 1;

    runLoop = [NSRunLoop currentRunLoop];
    interval = [self fadeDuration] / 20.0;
    if (interval < 0.05)
        interval = 0.05;
    endDate = [NSDate dateWithTimeIntervalSinceNow:
               [self fadeDuration] + interval];
    timer = [NSTimer timerWithTimeInterval:interval target:self
                                   selector:@selector(_fadeOut:)
                                   userInfo:nil repeats:YES];
    words[9] = (unsigned int)[timer retain];
    [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
    while ([self fadeInProgress])
        [runLoop runUntilDate:endDate];
}

- (BOOL)fadeInProgress
{
    return ((unsigned char *)self->_private)[64] != 0;
}

- (BOOL)fadeApplied
{
    return ((unsigned char *)self->_private)[65] != 0;
}

- (BOOL)canSetPalette
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    unsigned char *bytes = (unsigned char *)self->_private;

    if (bytes[66] == 0xff) {
        bytes[66] = [self bitsPerPixel] == 8;
        if (bytes[66] != 0)
            (void)InterceptorDamagedPalette(
                (InterceptorClientContext *)words[0]);
    }
    return bytes[66] != 0;
}

- (NSDirectPalette *)currentPalette
{
    return (NSDirectPalette *)NSDirectScreenWords(self->_private)[8];
}

- (NSWindow *)shieldingWindow
{
    return (NSWindow *)NSDirectScreenWords(self->_private)[3];
}

- (void)_loadPalette:(NSDirectPalette *)palette
{
    unsigned int *words = NSDirectScreenWords(self->_private);
    unsigned char *bytes = (unsigned char *)self->_private;
    NSData *machinePalette;

    if (bytes[66] == 0xff) {
        bytes[66] = [self bitsPerPixel] == 8;
        if (bytes[66] != 0)
            (void)InterceptorDamagedPalette(
                (InterceptorClientContext *)words[0]);
    }
    if (bytes[66] == 0)
        return;

    machinePalette = [palette rawMachinePalette];
    if (_IOSetIntValues((port_t)words[17], words[18], "IOSetTransferTable",
                        (unsigned int *)[machinePalette bytes],
                        [machinePalette length] / sizeof(unsigned int)) !=
        IO_R_SUCCESS) {
        NSLog(@"Unable to load palette: %@", palette);
    } else if (((unsigned char *)self->_private)[64] == 0) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NSDirectScreenDidChangePaletteNotification
                          object:self];
    }
}

- (void)setPalette:(NSDirectPalette *)palette
{
    NSDirectScreenSetPalette(self, palette, _cmd,
                             NSDirectScreenWords(self->_private));
}

- (void)setPaletteAtNextBlankingInterval:(NSDirectPalette *)palette
{
    NSDirectScreenSetPalette(self, palette, _cmd,
                             NSDirectScreenWords(self->_private));
}

- (void)hideCursor
{
    (void)InterceptorHideCursor((InterceptorClientContext *)NSDirectScreenWords(self->_private)[0]);
}

- (void)showCursor
{
    (void)InterceptorShowCursor((InterceptorClientContext *)NSDirectScreenWords(self->_private)[0]);
}

- (BOOL)_canLockWithMode:(NSFramebufferAccessMode)mode
{
    return [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2]
            canLockWithMode:mode];
}

- (void)_lockWithMode:(NSFramebufferAccessMode)mode
{
    NSString *selectorName = NSStringFromSelector(_cmd);

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2]
        lockWithMode:mode];
}

- (void)_unlock
{
    NSString *selectorName = NSStringFromSelector(_cmd);

    if (![self displayIsShielded])
        [NSException raise:NSDirectScreenDisplayIsUnshieldedException
                    format:UnshieldedExceptionFormat, selectorName];
    [(NSFramebuffer *)NSDirectScreenWords(self->_private)[2] unlock];
}

@end
