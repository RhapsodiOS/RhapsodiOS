#import "NSDirectScreen.h"
#import "NSFramebuffer.h"
#import "Private/InterceptorIPC.h"
#import "Private/InterceptorCopy.h"
#import <driverkit/driverServer.h>
#import <Foundation/NSException.h>
#import <Foundation/NSData.h>
#import <Foundation/NSNotification.h>
#import <mach/mach.h>
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

@interface NSDirectScreen (Private)
- (void)_clearModeInfo;
- (BOOL)_canLockWithMode:(NSFramebufferAccessMode)mode;
- (void)_lockWithMode:(NSFramebufferAccessMode)mode;
- (void)_unlock;
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
                [object setDelegate:nil];
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
