/*	NSImageRep.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSImageRep.h>
#import <AppKit/psops.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSPathUtilities.h>

APPKIT_EXTERN int _NSAppKitGlobalLock;
APPKIT_EXTERN void _NSAppKitLock(int line, const char *file);
APPKIT_EXTERN void _NSAppKitUnlock(int line, const char *file);

NSString *NSImageRepRegistryDidChangeNotification = @"NSImageRepRegistryDidChangeNotification";

static NSMutableArray *imageHandlers;
static NSArray *emptyImageRepFileTypes;
static NSArray *emptyImageRepPasteboardTypes;
static NSMutableDictionary *imageFileTypesTable;
static NSMutableDictionary *imagePasteboardTypesTable;

static Class imageRepForType(NSString *type, SEL typeSelector, SEL fallbackSelector)
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(608, "NSImageRep.m");

    Class result = Nil;
    SEL selector = typeSelector;
    while (selector != NULL) {
        unsigned count = [imageHandlers count];
        while (count > 0) {
            Class imageClass = [imageHandlers objectAtIndex:--count];
            NSArray *types = [imageClass performSelector:selector];
            if ([types containsObject:type]) {
                result = imageClass;
                goto finished;
            }
        }
        selector = selector == typeSelector ? fallbackSelector : NULL;
    }

finished:
    if (locked)
        _NSAppKitUnlock(615, "NSImageRep.m");
    return result;
}

static NSData *newDataOnImageFromFile(NSString *filename, Class imageClass)
{
    NSData *data = [[NSData alloc] initWithContentsOfFile:filename];
    if (data != nil && imageClass != Nil && ![imageClass canInitWithData:data]) {
        NSString *fileType = [filename pathExtension];
        NSString *pasteboardType = fileType != nil ? NSCreateFilenamePboardType(fileType) : nil;
        [data release];
        data = nil;

        if (pasteboardType != nil && [[imageClass imagePasteboardTypes] containsObject:pasteboardType]) {
            NSPasteboard *pasteboard = [NSPasteboard pasteboardByFilteringFile:filename];
            NSString *matchingType = [[pasteboard types]
                firstObjectCommonWithArray:[imageClass imageUnfilteredPasteboardTypes]];
            if (matchingType != nil)
                data = [[pasteboard dataForType:matchingType] retain];
        }
    }
    return data;
}

static BOOL imageCanInitFromPasteboard(NSArray *pasteboardTypes, NSArray *fileTypes,
    NSPasteboard *pasteboard)
{
    NSArray *types = [pasteboard types];
    if ([types firstObjectCommonWithArray:pasteboardTypes] != nil)
        return YES;

    NSPasteboard *filteredPasteboard =
        [NSPasteboard pasteboardByFilteringTypesInPasteboard:pasteboard];
    if (filteredPasteboard == nil)
        return NO;

    types = [filteredPasteboard types];
    if ([types firstObjectCommonWithArray:pasteboardTypes] != nil)
        return YES;
    if (![types containsObject:NSFilenamesPboardType])
        return NO;

    NSArray *filenames = [filteredPasteboard propertyListForType:NSFilenamesPboardType];
    if ([filenames count] == 0)
        return NO;
    NSString *fileType = [[filenames objectAtIndex:0] pathExtension];
    return [fileTypes containsObject:fileType];
}

static id initImageFromPasteboard(Class imageClass, NSPasteboard *pasteboard, BOOL multiple)
{
    NSPasteboard *filteredPasteboard = pasteboard;
    NSArray *types = [filteredPasteboard types];
    NSString *selectedType = [types
        firstObjectCommonWithArray:[imageClass imageUnfilteredPasteboardTypes]];

    if (selectedType == nil) {
        filteredPasteboard = [NSPasteboard pasteboardByFilteringTypesInPasteboard:pasteboard];
        if (filteredPasteboard != nil) {
            types = [filteredPasteboard types];
            selectedType = [types
                firstObjectCommonWithArray:[imageClass imageUnfilteredPasteboardTypes]];
            if (selectedType == nil && [types containsObject:NSFilenamesPboardType])
                selectedType = NSFilenamesPboardType;
        }
    }
    if (selectedType == nil)
        return nil;

    NSData *data = nil;
    if (![selectedType isEqual:NSFilenamesPboardType] && NSGetFileType(selectedType) == nil) {
        if (imageClass == [NSImageRep class])
            imageClass = [NSImageRep imageRepClassForPasteboardType:selectedType];
        data = [[filteredPasteboard dataForType:selectedType] retain];
    } else {
        NSArray *filenames = [filteredPasteboard propertyListForType:selectedType];
        NSString *filename = [filenames count] > 0 ? [filenames objectAtIndex:0] : nil;
        NSString *fileType = [filename pathExtension];
        if (filename != nil && [[imageClass imageFileTypes] containsObject:fileType]) {
            if (imageClass == [NSImageRep class])
                imageClass = [NSImageRep imageRepClassForFileType:fileType];
            if (imageClass != Nil)
                data = newDataOnImageFromFile(filename, imageClass);
        }
    }

    if (data == nil)
        return nil;

    id result;
    if (multiple && [imageClass respondsToSelector:@selector(imageRepsWithData:)]) {
        result = [imageClass performSelector:@selector(imageRepsWithData:) withObject:data];
    } else {
        id imageRep = [imageClass performSelector:@selector(imageRepWithData:) withObject:data];
        result = multiple && imageRep != nil ? [NSArray arrayWithObject:imageRep] : imageRep;
    }
    [data release];
    return result;
}

@implementation NSImageRep

+ (void)initialize
{
    if (self == [NSImageRep class])
        [self setVersion:17];
}

+ (void)registerImageRepClass:(Class)imageRepClass
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(567, "NSImageRep.m");

    if (imageHandlers == nil)
        imageHandlers = [[NSMutableArray allocWithZone:NSDefaultMallocZone()] initWithCapacity:3];

    BOOL added = ([imageHandlers indexOfObject:imageRepClass] == NSNotFound);
    if (added)
        [imageHandlers addObject:imageRepClass];

    if (locked)
        _NSAppKitUnlock(575, "NSImageRep.m");

    if (added)
        [[NSNotificationCenter defaultCenter]
            postNotificationName:NSImageRepRegistryDidChangeNotification object:self];
}

+ (void)unregisterImageRepClass:(Class)imageRepClass
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(582, "NSImageRep.m");

    [imageHandlers removeObject:imageRepClass];

    if (locked)
        _NSAppKitUnlock(584, "NSImageRep.m");

    [[NSNotificationCenter defaultCenter]
        postNotificationName:NSImageRepRegistryDidChangeNotification object:self];
}

+ (NSArray *)registeredImageRepClasses
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(593, "NSImageRep.m");

    if (imageHandlers == nil)
        imageHandlers = [[NSMutableArray allocWithZone:NSDefaultMallocZone()] initWithCapacity:3];
    NSArray *classes = imageHandlers;

    if (locked)
        _NSAppKitUnlock(596, "NSImageRep.m");
    return classes;
}

+ (Class)imageRepClassForFileType:(NSString *)type
{
    return imageRepForType(type, @selector(imageUnfilteredFileTypes),
        @selector(imageFileTypes));
}

+ (Class)imageRepClassForPasteboardType:(NSString *)type
{
    return imageRepForType(type, @selector(imageUnfilteredPasteboardTypes),
        @selector(imagePasteboardTypes));
}

+ (Class)imageRepClassForData:(NSData *)data
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(636, "NSImageRep.m");

    Class result = Nil;
    unsigned count = [imageHandlers count];
    while (count > 0) {
        Class imageClass = [imageHandlers objectAtIndex:--count];
        if ([imageClass canInitWithData:data]) {
            result = imageClass;
            break;
        }
    }

    if (locked)
        _NSAppKitUnlock(641, "NSImageRep.m");
    return result;
}

+ (BOOL)canInitWithData:(NSData *)data
{
    return NO;
}

+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pasteboard
{
    return imageCanInitFromPasteboard([self imageUnfilteredPasteboardTypes],
        [self imageFileTypes], pasteboard);
}

+ (NSArray *)imageUnfilteredFileTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(340, "NSImageRep.m");

    if (emptyImageRepFileTypes == nil)
        emptyImageRepFileTypes = [[NSArray allocWithZone:NSDefaultMallocZone()] init];
    NSArray *types = emptyImageRepFileTypes;

    if (locked)
        _NSAppKitUnlock(342, "NSImageRep.m");
    return types;
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(348, "NSImageRep.m");

    if (emptyImageRepPasteboardTypes == nil)
        emptyImageRepPasteboardTypes = [[NSArray allocWithZone:NSDefaultMallocZone()] init];
    NSArray *types = emptyImageRepPasteboardTypes;

    if (locked)
        _NSAppKitUnlock(350, "NSImageRep.m");
    return types;
}

+ (NSArray *)imageFileTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(400, "NSImageRep.m");

    NSArray *types = [imageFileTypesTable objectForKey:self];
    if (types == nil) {
        types = [NSGetFileTypes([self imagePasteboardTypes]) copyWithZone:NSDefaultMallocZone()];
        if (imageFileTypesTable == nil)
            imageFileTypesTable = [[NSMutableDictionary allocWithZone:NSDefaultMallocZone()]
                initWithCapacity:8];
        [imageFileTypesTable setObject:types forKey:self];
        [types release];
        types = [imageFileTypesTable objectForKey:self];
    }

    if (locked)
        _NSAppKitUnlock(409, "NSImageRep.m");
    return types;
}

+ (NSArray *)imagePasteboardTypes
{
    BOOL locked = (_NSAppKitGlobalLock != 0);
    if (locked)
        _NSAppKitLock(362, "NSImageRep.m");

    NSArray *types = [imagePasteboardTypesTable objectForKey:self];
    if (types == nil) {
        NSArray *fileTypes = [self imageUnfilteredFileTypes];
        NSArray *pasteboardTypes = [self imageUnfilteredPasteboardTypes];
        NSZone *zone = NSDefaultMallocZone();
        NSMutableArray *mutableTypes = [[NSMutableArray allocWithZone:zone]
            initWithCapacity:3 * [fileTypes count] + [pasteboardTypes count]];

        unsigned i;
        for (i = 0; i < [fileTypes count]; ++i) {
            NSString *fileType = [fileTypes objectAtIndex:i];
            [mutableTypes addObject:NSCreateFilenamePboardType(fileType)];
        }
        for (i = 0; i < [pasteboardTypes count]; ++i) {
            NSString *type = [pasteboardTypes objectAtIndex:i];
            [mutableTypes addObjectsFromArray:[NSPasteboard typesFilterableTo:type]];
        }

        types = [mutableTypes copyWithZone:zone];
        [mutableTypes release];
        if (imagePasteboardTypesTable == nil)
            imagePasteboardTypesTable = [[NSMutableDictionary allocWithZone:zone]
                initWithCapacity:8];
        [imagePasteboardTypesTable setObject:types forKey:self];
        [types release];
        types = [imagePasteboardTypesTable objectForKey:self];
    }

    if (locked)
        _NSAppKitUnlock(392, "NSImageRep.m");
    return types;
}

+ (NSArray *)imageRepsWithContentsOfURL:(NSURL *)url
{
    if (![url isFileURL])
        return nil;
    return [self imageRepsWithContentsOfFile:[url path]];
}

+ (id)imageRepWithContentsOfURL:(NSURL *)url
{
    if (![url isFileURL])
        return nil;
    return [self imageRepWithContentsOfFile:[url path]];
}

+ (NSArray *)imageRepsWithContentsOfFile:(NSString *)filename
{
    NSString *fileType = [filename pathExtension];
    NSString *filenamePboardType = fileType != nil ? NSCreateFilenamePboardType(fileType) : nil;
    Class classForImage = Nil;
    if (self == [NSImageRep class]) {
        classForImage = [self imageRepClassForFileType:fileType];
    } else if ([[self imageFileTypes] containsObject:fileType] ||
        [[self imagePasteboardTypes] containsObject:filenamePboardType]) {
        classForImage = self;
    }

    if (classForImage == Nil)
        return nil;

    NSData *data = newDataOnImageFromFile(filename, classForImage);
    if (data == nil)
        return nil;

    NSArray *imageReps = nil;
    if ([classForImage respondsToSelector:@selector(imageRepsWithData:)]) {
        imageReps = [classForImage performSelector:@selector(imageRepsWithData:) withObject:data];
    } else {
        id imageRep = [classForImage performSelector:@selector(imageRepWithData:) withObject:data];
        if (imageRep != nil)
            imageReps = [NSArray arrayWithObject:imageRep];
    }
    [data release];
    return imageReps;
}

+ (id)imageRepWithContentsOfFile:(NSString *)filename
{
    NSString *fileType = [filename pathExtension];
    NSString *filenamePboardType = fileType != nil ? NSCreateFilenamePboardType(fileType) : nil;
    Class classForImage = Nil;
    if (self == [NSImageRep class]) {
        classForImage = [self imageRepClassForFileType:fileType];
    } else if ([[self imageFileTypes] containsObject:fileType] ||
        [[self imagePasteboardTypes] containsObject:filenamePboardType]) {
        classForImage = self;
    }

    if (classForImage == Nil)
        return nil;

    NSData *data = newDataOnImageFromFile(filename, classForImage);
    id imageRep = nil;
    if (data != nil) {
        imageRep = [classForImage performSelector:@selector(imageRepWithData:) withObject:data];
        [data release];
    }
    return imageRep;
}

+ (NSArray *)imageRepsWithPasteboard:(NSPasteboard *)pasteboard
{
    return initImageFromPasteboard(self, pasteboard, YES);
}

+ (id)imageRepWithPasteboard:(NSPasteboard *)pasteboard
{
    return initImageFromPasteboard(self, pasteboard, NO);
}

- (void)setSize:(NSSize)size
{
    _size = size;
}

- (NSSize)size
{
    return _size;
}

- (void)setAlpha:(BOOL)alpha
{
    _repFlags.hasAlpha = alpha;
}

- (BOOL)hasAlpha
{
    return _repFlags.hasAlpha;
}

- (void)setOpaque:(BOOL)opaque
{
    _repFlags.isOpaque = opaque;
}

- (BOOL)isOpaque
{
    return _repFlags.isOpaque;
}

- (void)setColorSpaceName:(NSString *)string
{
    [_colorSpaceName release];
    _colorSpaceName = [string copyWithZone:[self zone]];
}

- (NSString *)colorSpaceName
{
    return _colorSpaceName != nil ? _colorSpaceName : NSDeviceRGBColorSpace;
}

- (void)setBitsPerSample:(int)anInt
{
    _repFlags.bitsPerSample = anInt;
}

- (int)bitsPerSample
{
    return _repFlags.bitsPerSample;
}

- (void)setPixelsWide:(int)anInt
{
    _pixelsWide = anInt;
}

- (int)pixelsWide
{
    return _pixelsWide;
}

- (void)setPixelsHigh:(int)anInt
{
    _pixelsHigh = anInt;
}

- (int)pixelsHigh
{
    return _pixelsHigh;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    BOOL alpha = [self hasAlpha];
    BOOL opaque = [self isOpaque];
    int bitsPerSample = [self bitsPerSample];

    [coder encodeSize:_size];
    [coder encodeValueOfObjCType:@encode(BOOL) at:&alpha];
    [coder encodeValueOfObjCType:@encode(BOOL) at:&opaque];
    [coder encodeValuesOfObjCTypes:"iii@", &_pixelsWide, &_pixelsHigh,
        &bitsPerSample, &_colorSpaceName];
}

- (id)initWithCoder:(NSCoder *)coder
{
    unsigned version = [coder versionForClassName:@"NSImageRep"];
    self = [super initWithCoder:coder];
    if (self == nil)
        return nil;

    _size = [coder decodeSize];

    if (version > 16) {
        BOOL alpha;
        BOOL opaque;
        int bitsPerSample;

        [coder decodeValueOfObjCType:@encode(BOOL) at:&alpha];
        [coder decodeValueOfObjCType:@encode(BOOL) at:&opaque];
        [coder decodeValuesOfObjCTypes:"iii@", &_pixelsWide, &_pixelsHigh,
            &bitsPerSample, &_colorSpaceName];
        [self setAlpha:alpha];
        [self setOpaque:opaque];
        [self setBitsPerSample:bitsPerSample];
    } else if (version > 2) {
        short alpha;
        short bitsPerSample;
        short opaque;

        [coder decodeValuesOfObjCTypes:"iis@ss", &_pixelsWide, &_pixelsHigh,
            &alpha, &_colorSpaceName, &bitsPerSample, &opaque];
        [self setAlpha:alpha];
        [self setBitsPerSample:bitsPerSample];
        [self setOpaque:opaque];
    } else {
        short alpha;
        short colorSpace;
        short bitsPerSample;
        short reserved;
        short opaque = 0;

        if (version == 2) {
            [coder decodeValuesOfObjCTypes:"iisssss", &_pixelsWide, &_pixelsHigh,
                &alpha, &colorSpace, &bitsPerSample, &reserved, &opaque];
        } else {
            [coder decodeValuesOfObjCTypes:"iissss", &_pixelsWide, &_pixelsHigh,
                &alpha, &colorSpace, &bitsPerSample, &reserved];
        }

        switch (colorSpace) {
        case 1:
            [self setColorSpaceName:NSDeviceCMYKColorSpace];
            break;
        case 3:
            [self setColorSpaceName:NSCalibratedWhiteColorSpace];
            break;
        case 4:
            [self setColorSpaceName:NSCalibratedRGBColorSpace];
            break;
        default:
            [self setColorSpaceName:nil];
            break;
        }
        [self setAlpha:alpha];
        [self setBitsPerSample:bitsPerSample];
        [self setOpaque:opaque];
    }

    return self;
}

- (BOOL)draw
{
    return YES;
}

- (BOOL)drawAtPoint:(NSPoint)point
{
    if (_size.width <= 0.0 || _size.height <= 0.0)
        return NO;

    BOOL translated = point.x != 0.0 || point.y != 0.0;
    if (translated) {
        [self _gsave];
        PStranslate(point.x, point.y);
    }

    BOOL result = [self draw];
    if (translated)
        [self _grestore];
    return result;
}

- (BOOL)drawInRect:(NSRect)rect
{
    if (_size.width <= 0.0 || _size.height <= 0.0)
        return NO;

    BOOL translated = rect.origin.x != 0.0 || rect.origin.y != 0.0;
    BOOL scaled = rect.size.width != _size.width || rect.size.height != _size.height;
    if (translated || scaled) {
        [self _gsave];
        if (translated)
            PStranslate(rect.origin.x, rect.origin.y);
        if (scaled)
            PSscale(rect.size.width / _size.width, rect.size.height / _size.height);
    }

    BOOL result = [self draw];
    if (translated || scaled)
        [self _grestore];
    return result;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSImageRep *copy = NSCopyObject(self, 0, zone);
    copy->_colorSpaceName = [_colorSpaceName copyWithZone:zone];
    return copy;
}

- (void)dealloc
{
    while (_repFlags.gsaved != 0)
        [self _grestore];
    [_colorSpaceName release];
    [super dealloc];
}

- (void)_gsave
{
    ++_repFlags.gsaved;
    if (_repFlags.gsaved == 1)
        PSgsave();
}

- (void)_grestore
{
    --_repFlags.gsaved;
    if (_repFlags.gsaved == 0)
        PSgrestore();
}

- (BOOL)_canDrawOutsideOfItsBounds
{
    return YES;
}

@end
