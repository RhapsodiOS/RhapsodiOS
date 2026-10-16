/*	NSPathUtilities.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSZone.h>

#include <pwd.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>

extern int _NSFileAccessibleForMode(NSString *path, int mode);
extern char *_NSGetEnvironmentVariable(const char *name);
extern id __NSEmptyArray;
extern NSString *__NSEmptyString;
extern Class __NSPathStore2Class;
extern unsigned int NSStartSearchPathEnumeration(
    NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask);
extern unsigned int NSGetNextSearchPathEnumeration(unsigned int state,
                                                    char *path);

@interface NSPathStore2 : NSString {
    unsigned _lengthAndRefCount;
}
#if !defined(__ppc__) && !defined(__POWERPC__)
+ (id)pathStoreWithCString:(const char *)bytes;
#endif
+ (id)pathWithComponents:(NSArray *)components;
+ (id)pathStoreWithCharacters:(const unichar *)characters length:(unsigned)length;
@end

typedef struct {
    unsigned char isCString;
    unsigned char allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[1008];
} NSPathStoreConversionBuffer;

extern int _NSConvertToASCIIorUnicode2(const void *bytes, unsigned size,
                                       NSStringEncoding encoding, BOOL flag,
                                       void *buffer, NSZone *zone);
extern NSStringEncoding _NSDefaultCStringEncoding(void);
extern NSStringEncoding _NSDefaultFileSystemEncoding(void);
extern id _NSMethodExceptionProem(id object, SEL aSelector);
extern IMP _NSIMPForObjectAndSelector(id object, SEL aSelector);
extern unsigned NSHashCharacters(const unichar *characters, unsigned length);
extern int NSCompareCharacters(const unichar *left, const unichar *right,
                               unsigned leftLength, unsigned rightLength,
                               unsigned options);
extern NSLock *_NSGlobalRetainLock;
extern BOOL _NSFileExistsAtPath(NSFileManager *manager,
                                const unichar *characters,
                                unsigned length, struct stat *status);

typedef id (*NSPathObjectAtIndexIMP)(id, SEL, unsigned);

static unichar *NSPathStoreCharacters(NSPathStore2 *string) {
    return (unichar *)((char *)string + sizeof(NSPathStore2));
}

static void NSPathStoreStripTrailingSlashes(unichar *characters,
                                             unsigned *length) {
    unsigned size = *length;
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL drivePrefix = size > 1 && characters[1] == ':'
#else
    BOOL drivePrefix = characters[1] == ':'
#endif
        && ((unsigned short)(characters[0] - 'A') <= 25
            || (unsigned short)(characters[0] - 'a') <= 25);

    while (size > 1 && characters[size - 1] == '/') {
        if (size == 3 && drivePrefix)
            break;
        size--;
    }
    *length = size;
}

static BOOL NSPathStoreIsASCIIAlpha(unichar character) {
    return (unsigned short)(character - 'A') <= 25
        || (unsigned short)(character - 'a') <= 25;
}

static BOOL NSPathStoreHasDrivePrefix(const unichar *characters,
                                     unsigned length) {
    return length >= 2 && characters[1] == ':'
        && NSPathStoreIsASCIIAlpha(characters[0]);
}

static void NSPathStoreTransmuteSlashes(unichar *characters,
                                        unsigned *length,
                                        unichar separator) {
    unsigned source = 0;
    unsigned destination = 0;
    unsigned count = *length;

#if defined(__ppc__) || defined(__POWERPC__)
    if (count > 1 && characters[0] == '\\' && characters[1] == '\\')
#else
    if (characters[0] == '\\' && characters[1] == '\\')
#endif
        destination = 2;
    source = destination;
    while (source < count) {
        if (characters[source] != '/') {
            characters[destination++] = characters[source++];
        } else {
            characters[destination++] = separator;
            while (++source < count && characters[source] == '/')
                ;
        }
    }
    *length = destination;
}

static unsigned NSPathStoreStartOfExtension(const unichar *characters,
                                            unsigned length) {
    unsigned index;

    if (length <= 1)
        return 0;
    index = length - 1;
    while (characters[index - 1] != '/') {
        if (characters[index] == '.') {
            if (index != 2 || !NSPathStoreHasDrivePrefix(characters, length))
                return index;
            return 0;
        }
        if (--index == 0)
            return 0;
    }
    return 0;
}

static unsigned NSPathStoreStartOfLastComponent(const unichar *characters,
                                                 unsigned length) {
    unsigned index;

    if (length <= 1)
        return 0;
    index = length - 1;
    while (characters[index - 1] != '/') {
        if (--index == 0)
            return length > 2 && NSPathStoreHasDrivePrefix(characters, length)
                ? 2 : 0;
    }
    return index;
}

static unsigned NSPathStoreLengthAfterDeletingLastComponent(
    const unichar *characters, unsigned length) {
    unsigned start;

    if (length <= 1)
        return 0;
    start = length - 1;
    while (characters[start - 1] != '/') {
        if (--start == 0)
            return length > 2 && NSPathStoreHasDrivePrefix(characters, length)
                ? 2 : 0;
    }
    if (start == 1 || (NSPathStoreHasDrivePrefix(characters, length)
                       && start == 3))
        return start;
    return start - 1;
}

static BOOL NSPathStoreAppendComponent(unichar *path, unsigned *pathLength,
                                       unsigned capacity,
                                       const unichar *component,
                                       unsigned componentLength) {
    unsigned pathSize = *pathLength;

    if (componentLength == 0)
        return YES;
    if (capacity < pathSize + componentLength + 1)
        return NO;
#if !defined(__ppc__) && !defined(__POWERPC__)
    if (pathSize != 0 && componentLength > 1
        && (NSPathStoreHasDrivePrefix(component, componentLength)
            || (component[0] == '\\' && component[1] == '\\')))
        return NO;
#endif
    if (pathSize != 0 && !(pathSize == 1 && path[0] == '/')
        && !(pathSize == 2 && (NSPathStoreHasDrivePrefix(path, pathSize)
                               || (path[0] == '\\' && path[1] == '\\'))))
        path[(*pathLength)++] = '/';
    memmove(path + *pathLength, component,
            componentLength * sizeof(unichar));
    *pathLength += componentLength;
    return YES;
}

static BOOL NSPathStoreAppendExtension(unichar *path, unsigned *pathLength,
                                      unsigned capacity,
                                      const unichar *extension,
                                      unsigned extensionLength) {
    unsigned length = *pathLength;

    if (capacity < length + extensionLength + 1
        || (extensionLength != 0 && extension[0] == '/')
        || (extensionLength > 1
            && NSPathStoreHasDrivePrefix(extension, extensionLength)))
        return NO;
    NSPathStoreStripTrailingSlashes(path, pathLength);
    length = *pathLength;
    if (length <= 3) {
        if (length == 0 || (length == 1 && (path[0] == '/' || path[0] == '~'))
            || (length == 2 && (NSPathStoreHasDrivePrefix(path, length)
                                || (path[0] == '\\' && path[1] == '\\')))
            || (length == 3 && NSPathStoreHasDrivePrefix(path, length)
                && path[2] == '/'))
            return NO;
    }
    if (length != 0 && path[0] == '~') {
        unsigned index = 1;
        while (index < length && path[index] != '/')
            index++;
        if (index == length)
            return NO;
    }
    path[(*pathLength)++] = '.';
    if (extensionLength != 0)
        memmove(path + *pathLength, extension,
                extensionLength * sizeof(unichar));
    *pathLength += extensionLength;
    return YES;
}

static NSArray *NSPathStoreComponents(const unichar *characters,
                                      unsigned length);
static void NSPathStoreExpandTilde(unichar *characters, unsigned *length,
                                   unsigned capacity);
static BOOL NSPathStoreAbbreviateTilde(unichar *characters, unsigned *length);

int _NSStripTrailingPathSlashes(unichar *characters, unsigned *length) {
    unsigned originalLength = *length;

    NSPathStoreStripTrailingSlashes(characters, length);
    return *length != originalLength;
}

unsigned _NSStartOfPathExtension(const unichar *characters, unsigned length) {
    return NSPathStoreStartOfExtension(characters, length);
}

unsigned _NSStartOfLastPathComponent(const unichar *characters,
                                     unsigned length) {
    return NSPathStoreStartOfLastComponent(characters, length);
}

unsigned _NSLengthAfterDeletingLastPathComponent(const unichar *characters,
                                                  unsigned length) {
    return NSPathStoreLengthAfterDeletingLastComponent(characters, length);
}

unsigned _NSLengthAfterDeletingPathExtension(const unichar *characters,
                                             unsigned length) {
    unsigned extensionStart = NSPathStoreStartOfExtension(characters, length);

    return extensionStart == 0 ? length : extensionStart;
}

int _NSAppendPathComponent(unichar *path, unsigned *pathLength,
                           unsigned capacity, const unichar *component,
                           unsigned componentLength) {
    return NSPathStoreAppendComponent(path, pathLength, capacity,
                                      component, componentLength);
}

int _NSAppendPathExtension(unichar *path, unsigned *pathLength,
                           unsigned capacity, const unichar *extension,
                           unsigned extensionLength) {
    return NSPathStoreAppendExtension(path, pathLength, capacity,
                                      extension, extensionLength);
}

int _NSTransmutePathSlashes(unichar *characters, unsigned *length,
                            unichar separator) {
    unsigned originalLength = *length;

    NSPathStoreTransmuteSlashes(characters, length, separator);
    return *length != originalLength;
}

int _NSIsAbsolutePath(const unichar *characters, unsigned length) {
    if (length == 0)
        return NO;
    return characters[0] == '~' || characters[0] == '/';
}

int _NSExpandTildeInPath(unichar *characters, unsigned *length,
                         unsigned capacity) {
    NSPathStoreExpandTilde(characters, length, capacity);
    return 0;
}

NSArray *_NSPathComponents(const unichar *characters, unsigned length) {
    return NSPathStoreComponents(characters, length);
}

int _NSAbbreviatePathWithTilde(unichar *characters, unsigned *length) {
    return NSPathStoreAbbreviateTilde(characters, length);
}

static NSArray *NSPathStoreComponents(const unichar *characters,
                                      unsigned length) {
    NSMutableArray *components = [NSMutableArray array];
    unsigned index = 0;

    if (length > 1 && NSPathStoreHasDrivePrefix(characters, length)) {
        [components addObject:[NSString stringWithCharacters:characters length:2]];
        index = 2;
    }
    if (index < length && characters[index] == '/') {
        [components addObject:[NSString stringWithCharacters:characters + index
                                                     length:1]];
        index++;
    }
    while (index < length) {
        unsigned start;
        while (index < length && characters[index] == '/')
            index++;
        if (index == length)
            break;
        start = index;
        while (index < length && characters[index] != '/')
            index++;
        [components addObject:[NSString stringWithCharacters:characters + start
                                                     length:index - start]];
    }
    return components;
}

static void NSPathStoreExpandTilde(unichar *characters, unsigned *length,
                                   unsigned capacity) {
    unsigned userEnd;
    NSString *home;
    unsigned homeLength;

    if (*length == 0 || characters[0] != '~')
        return;
    for (userEnd = 1; userEnd < *length && characters[userEnd] != '/'; userEnd++)
        ;
    if (userEnd == 1)
        home = NSHomeDirectory();
    else {
        NSString *user = [NSString stringWithCharacters:characters + 1
                                                  length:userEnd - 1];
        home = NSHomeDirectoryForUser(user);
    }
    if (home == nil)
        return;
    homeLength = [home length];
    if (capacity < homeLength + *length - userEnd)
        return;
    if (*length > userEnd)
        memmove(characters + homeLength, characters + userEnd,
                (*length - userEnd) * sizeof(unichar));
    [home getCharacters:characters range:NSMakeRange(0, homeLength)];
    *length = homeLength + *length - userEnd;
}

static BOOL NSPathStoreAbbreviateTilde(unichar *characters,
                                       unsigned *length) {
    NSString *home;
    unsigned homeLength;
    unichar *homeCharacters;
    unsigned index;

    if (*length == 0 || (*length == 1 && characters[0] == '/'))
        return NO;
    home = NSHomeDirectory();
    homeLength = [home length];
    homeCharacters = (unichar *)__builtin_alloca((homeLength + 1) * sizeof(unichar));
    if (*length < homeLength)
        return NO;
    [home getCharacters:homeCharacters range:NSMakeRange(0, homeLength)];
    for (index = 0; index < homeLength; index++)
        if (homeCharacters[index] != characters[index])
            return NO;
    if (*length == homeLength) {
        characters[0] = '~';
        *length = 1;
        return YES;
    }
    if (characters[homeLength] != '/')
        return NO;
    memmove(characters + 1, characters + homeLength,
            (*length - homeLength) * sizeof(unichar));
    characters[0] = '~';
    *length = *length - homeLength + 1;
    return YES;
}

static BOOL NSPathStoreHasAbsoluteDotDot(const unichar *characters,
                                        unsigned length) {
    unsigned start = 0;
    unsigned index;

    if (length <= 1 || (characters[0] != '/' && characters[0] != '~'))
        return NO;
    if (length > 1 && characters[0] == '\\' && characters[1] == '\\') {
        for (start = 3; start < length && characters[start] != '/'; start++)
            ;
        for (start++; start < length && characters[start] != '/'; start++)
            ;
        start++;
    }
    for (index = start; index + 1 < length; index++) {
        if (characters[index] != '.' || characters[index + 1] != '.')
            continue;
        if (index != 0 && characters[index - 1] != '/')
            continue;
        if (index + 2 == length || characters[index + 2] == '/')
            return YES;
    }
    return NO;
}

@interface NSCheapMutableString : NSMutableString
- (void)setContentsNoCopy:(void *)characters length:(unsigned)length
    freeWhenDone:(BOOL)freeWhenDone isUnicode:(BOOL)isUnicode;
@end

static BOOL NSPathStoreConvertToFileSystemRepresentation(
    const unichar *characters, unsigned length, char *filePath,
    unsigned *filePathLength) {
    NSCheapMutableString *path =
        [[NSCheapMutableString allocWithZone:NULL] init];

    [path setContentsNoCopy:(void *)characters length:length
                  freeWhenDone:NO isUnicode:YES];
    if ([[NSFileManager defaultManager]
            getFileSystemRepresentation:filePath
                                   maxLength:*filePathLength withPath:path]) {
        *filePathLength = (unsigned)strlen(filePath);
        [path release];
        return YES;
    }
    [path release];
    return NO;
}

static BOOL NSPathStoreResolveSymlinks(unichar *characters, unsigned *length,
                                       unsigned capacity) {
    char filePath[1028];
    char resolved[1028];
    struct stat status;
    unsigned filePathLength = 1026;
    unsigned index;
    NSString *path;

    if (*length == 0)
        return NO;
    if (!NSPathStoreConvertToFileSystemRepresentation(characters, *length,
                                                      filePath, &filePathLength))
        return NO;
    for (index = 0; ; index++) {
        char saved;

        while (filePath[index] == '/')
            index++;
        while (filePath[index] != '\0' && filePath[index] != '/')
            index++;
        saved = filePath[index];
        filePath[index] = '\0';
        if (lstat(filePath, &status) < 0 || S_ISLNK(status.st_mode)) {
            filePath[index] = saved;
            break;
        }
        filePath[index] = saved;
        if (saved == '\0')
            return NO;
    }
    if (realpath(filePath, resolved) == NULL)
        return NO;
    path = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:resolved
                                    length:(unsigned)strlen(resolved)];
    if (path == nil) {
        *length = 0;
        return YES;
    }
    *length = [path length];
    if (*length > capacity)
        *length = capacity;
    if (*length != 0)
        [path getCharacters:characters range:NSMakeRange(0, *length)];
    return YES;
}

int _NSResolveSymlinksInPath(unichar *characters, unsigned *length,
                             int capacity) {
    return NSPathStoreResolveSymlinks(characters, length,
                                      (unsigned)capacity);
}

int _NSConvertPathToLongFileSystemName(void) {
    return 0;
}

int _NSStandardizePath(unichar *characters, unsigned *length, int capacity) {
    unsigned originalLength;
    unsigned index;
    unsigned j;
    unsigned v9;
    unsigned v10;
    unsigned v11;
    unsigned v12;
    unsigned temporaryLength;
    unsigned temporaryCopyLength;
    unichar temporaryPath[1024];
    int initialChange;
    BOOL unc;
    BOOL hasDotDot;
    struct stat status;

    initialChange = _NSTransmutePathSlashes(characters, length, '/');
    originalLength = *length;
    NSPathStoreStripTrailingSlashes(characters, length);
    if (*length != originalLength)
        initialChange = 1;

    unc = *length > 1 && characters[0] == '\\' && characters[1] == '\\';
    hasDotDot = NSPathStoreHasAbsoluteDotDot(characters, *length);
    if (hasDotDot) {
        temporaryLength = *length;
        temporaryCopyLength = temporaryLength < 1024
            ? temporaryLength : 1024;
        memmove(temporaryPath, characters,
                temporaryCopyLength * sizeof(unichar));
        (void)NSPathStoreResolveSymlinks(temporaryPath, &temporaryLength, 1024);
        if (temporaryLength > (unsigned)capacity)
            return initialChange;
        memmove(characters, temporaryPath,
                temporaryLength * sizeof(unichar));
        *length = temporaryLength;
    }

    while (1) {
        if (unc) {
            if (*length <= 4)
                break;
        } else if (*length <= 2) {
            break;
        }
        if (characters[*length - 2] != '/' || characters[*length - 1] != '.')
            break;
        *length -= 2;
    }

    if (!unc) {
        unsigned leadingLength = 0;

        if (*length > 1 && characters[1] == '/') {
            do {
                if (characters[leadingLength] != '.')
                    break;
                leadingLength += 2;
                if (*length <= 1)
                    break;
            } while (characters[leadingLength + 1] == '/');
        }
        if (leadingLength != 0) {
            *length -= leadingLength;
            memmove(characters, characters + leadingLength,
                    *length * sizeof(unichar));
        }
    }

    index = unc ? 3 : 0;
    if (*length > 2) {
        do {
            if (index >= *length - 2)
                break;
            if (characters[index] == '/' && characters[index + 1] == '.'
                && characters[index + 2] == '/') {
                memmove(characters + index + 1, characters + index + 3,
                        (*length - index - 3) * sizeof(unichar));
                *length -= 2;
                --index;
            }
            ++index;
        } while (*length > 2);

        while (*length > 2 && hasDotDot) {
            unsigned i;

            j = 0;
            if (unc) {
                for (i = 3; *length > i; ++i) {
                    if (characters[i] == '/')
                        break;
                }
                for (j = i + 1; *length > j; ++j) {
                    if (characters[j] == '/')
                        break;
                }
            }
            v9 = j;
            if (*length > 2) {
                if (j >= *length - 2)
                    goto reduce_parent_components;
                while (1) {
                    if (j != v9)
                        goto reduce_parent_components;
                    if (*length > 3 && j < *length - 4
                        && characters[j] == '/' && characters[j + 1] == '.'
                        && characters[j + 2] == '.'
                        && characters[j + 3] == '/') {
                        memmove(characters + j + 1, characters + j + 4,
                                (*length - j - 4) * sizeof(unichar));
                        *length -= 3;
                        v9 = j - 1;
                    }
                    if (*length > 2 && v9 == *length - 3
                        && characters[v9] == '/' && characters[v9 + 1] == '.'
                        && characters[v9 + 2] == '.')
                        *length -= 2;
                    ++v9;
                    if (*length <= 2)
                        break;
                    if (v9 >= *length - 2) {
reduce_parent_components:
                        while (*length > 2 && *length > j) {
                            v10 = j + 1;
                            if (*length > 2) {
                                v11 = *length - 2;
                                while (v10 < v11) {
                                    if (characters[v10] == '/')
                                        break;
                                    ++v10;
                                    if (*length <= 2)
                                        goto reduce_parent_component_check;
                                }
                                if (*length > 2 && *length - 2 <= v10)
                                    break;
                            }
reduce_parent_component_check:
                            if (*length > 3 && v10 < *length - 4
                                && characters[v10] == '/'
                                && characters[v10 + 1] == '.'
                                && characters[v10 + 2] == '.'
                                && characters[v10 + 3] == '/') {
                                v12 = *length - (v10 - (j - 3));
                                *length = v12;
                                memmove(characters + j + 1,
                                        characters + v10 + 4,
                                        v12 * sizeof(unichar));
                                goto parent_components_done;
                            }
                            if (*length > 2 && v10 == *length - 3
                                && characters[v10] == '/'
                                && characters[v10 + 1] == '.'
                                && characters[v10 + 2] == '.') {
                                *length = j + 1;
                                goto parent_components_done;
                            }
                            j = v10;
                        }
                        break;
                    }
                }
            }
parent_components_done:
            hasDotDot = NSPathStoreHasAbsoluteDotDot(characters, *length);
        }
    }

    NSPathStoreTransmuteSlashes(characters, length, '/');
    NSPathStoreStripTrailingSlashes(characters, length);
    if (*length > 8 && characters[0] == '/' && characters[1] == 'p'
        && characters[2] == 'r' && characters[3] == 'i'
        && characters[4] == 'v' && characters[5] == 'a'
        && characters[6] == 't' && characters[7] == 'e'
        && characters[8] == '/') {
        NSFileManager *manager = [NSFileManager defaultManager];

        if (_NSFileExistsAtPath(manager, characters + 8, *length - 8,
                                &status)) {
            *length -= 8;
            memmove(characters, characters + 8,
                    *length * sizeof(unichar));
        }
    }
    return 1;
}

@interface NSFileManager (NSPathUtilitiesInternal)
- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max withPath:(NSString *)path;
@end

@interface NSString (NSURLPathUtilities)
- (NSString *)stringByAddingPercentEscapes;
- (NSString *)stringByRemovingPercentEscapes;
- (NSString *)standardizedURLPath;
- (NSString *)standardizedNativePath;
#if defined(__ppc__) || defined(__POWERPC__)
- (NSString *)urlPathByAppendingComponent:(NSString *)component;
- (NSString *)urlPathByDeletingLastComponent;
- (NSString *)urlPathRelativeToPath:(NSString *)path;
#endif
@end

NSString *_NSURLEscapeSequenceForCharacter(unichar character) {
    static const char hex[] = "0123456789ABCDEF";
    unichar escaped[3];
    unsigned char byte = (unsigned char)character;

    escaped[0] = '%';
    escaped[1] = hex[byte >> 4];
    escaped[2] = hex[byte & 0x0f];
    return [NSString stringWithCharacters:escaped length:3];
}

static int NSURLHexValue(unichar character) {
    if ((unsigned short)(character - '0') <= 9)
        return character - '0';
    if ((unsigned short)(character - 'a') <= 5)
        return character - 'a' + 10;
    return character - 'A' + 10;
}

static NSArray *NSDirectoryContentsMatchingPrefixAndSuffixes(NSFileManager *manager,
                                                              NSString *directory,
                                                              NSString *prefix,
                                                              NSArray *filterTypes) {
    NSArray *contents;
    NSMutableArray *matches;
    unsigned int contentsCount;
    unsigned int index;
    BOOL matchAllPrefixes;
    BOOL filterExtensions;

    directory = [directory stringByExpandingTildeInPath];
    contents = [manager directoryContentsAtPath:directory];
    contentsCount = [contents count];
    matches = [NSMutableArray array];
    matchAllPrefixes = prefix == nil || [prefix isEqualToString:@""];
    filterExtensions = filterTypes == nil || [filterTypes count] == 0;
    for (index = 0; index < contentsCount; index++) {
        NSString *name = [contents objectAtIndex:index];
        NSString *extension;

        if (!matchAllPrefixes && ![name hasPrefix:prefix])
            continue;
        extension = [name pathExtension];
        if (filterExtensions || [filterTypes containsObject:extension]) {
            [matches addObject:[directory stringByAppendingPathComponent:name]];
        } else if ([extension isEqualToString:@""]) {
            NSString *path = [directory stringByAppendingPathComponent:name];
            BOOL isDirectory = NO;
            if ([manager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
                [matches addObject:path];
        }
    }
    return matches;
}

static NSString *NSFindCommonPrefixInStringArray(NSArray *strings, BOOL caseSensitive) {
    unsigned int count = [strings count];
    NSString *first;
    unsigned int index;
    unsigned int prefixLength;
    id localObjects[256];
    id *objects = localObjects;
    NSString *commonPrefix = @"";

    if (count == 0)
        return @"";
    if (count == 1)
        return [strings objectAtIndex:0];
    if (count > 256)
        objects = NSZoneMalloc(NULL, count * sizeof(id));
    [strings getObjects:objects range:NSMakeRange(0, count)];
    first = objects[0];
    prefixLength = 0;
    while (prefixLength < [first length]) {
        NSRange sequence = [first rangeOfComposedCharacterSequenceAtIndex:prefixLength];
        unsigned int end = sequence.location + sequence.length;
        NSString *candidatePrefix = [first substringWithRange:
            NSMakeRange(0, end)];
        unsigned int candidateIndex;
        BOOL shared = YES;

        for (candidateIndex = 1; candidateIndex < count; candidateIndex++) {
            NSString *candidate = objects[candidateIndex];
            unsigned int options = NSAnchoredSearch;
            NSRange found;

            if (!caseSensitive)
                options |= NSCaseInsensitiveSearch;
            found = [candidate rangeOfString:candidatePrefix
                                     options:options
                                       range:NSMakeRange(0, [candidate length])];
            if (found.location != 0) {
                shared = NO;
                break;
            }
        }
        if (!shared)
            break;
        commonPrefix = candidatePrefix;
        prefixLength = end;
    }
    if (objects != localObjects)
        NSZoneFree(NULL, objects);
    return commonPrefix;
}

static BOOL NSURLCharacterNeedsEscaping(unichar character) {
    return !((character >= 'a' && character <= 'z')
             || (character >= 'A' && character <= 'Z')
             || (character >= '-' && character <= '.')
             || character == '+'
             || (character >= '0' && character <= '9')
             || character == '$' || character == '_' || character == '!'
             || character == '*' || character == '\'' || character == '('
             || character == ')' || character == ',');
}

static NSString *NSURLTransformPath(NSString *path, BOOL encode) {
    NSArray *components = encode ? [path pathComponents]
                                 : [path componentsSeparatedByString:@"/"];
    unsigned int componentCount = [components count];
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned int length = 0;
    BOOL absolute = NO;
#endif
    BOOL trailingSlash = NO;
    BOOL leadingSlash = NO;
    NSString *body = nil;
    NSMutableArray *transformed = nil;
    unsigned int index, firstComponent = 0;

    if (componentCount == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        if (encode)
            return @"";
#endif
        return path;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    if (encode) {
        length = [path length];
        if (length == 0)
            return @"";
        absolute = [[components objectAtIndex:0] isEqualToString:@"/"];
        leadingSlash = absolute;
        trailingSlash = length > (absolute ? 1 : 0)
            && [path characterAtIndex:length - 1] == '/';
    }
    if (encode && [components count] != 0) {
        NSString *first = [components objectAtIndex:0];
        if ([first isEqualToString:@"/"] || [first isEqualToString:@"~"]) {
            transformed = [[NSMutableArray alloc] initWithArray:components];
            firstComponent = 1;
        }
        if (trailingSlash && transformed == nil)
            transformed = [[NSMutableArray alloc] initWithArray:components];
    }
#else
    if (encode)
        trailingSlash = NO;
#endif
    for (index = firstComponent; index < [components count]; index++) {
        NSString *component = [components objectAtIndex:index];
        NSString *replacement = encode ? [component stringByAddingPercentEscapes]
                                       : [component stringByRemovingPercentEscapes];
#if defined(__ppc__) || defined(__POWERPC__)
        if (replacement == nil) {
            [transformed release];
            return nil;
        }
#endif
        if (replacement != component) {
            if (transformed == nil)
                transformed = [[NSMutableArray alloc] initWithArray:components];
            [transformed replaceObjectAtIndex:index withObject:replacement];
        }
    }
    if (transformed == nil)
        return path;
    if (!encode) {
        body = [transformed componentsJoinedByString:@"/"];
        [transformed release];
        return body;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    leadingSlash = absolute;
#else
    leadingSlash = [transformed count] != 0
        && [[transformed objectAtIndex:0] isEqualToString:@"/"];
#endif
    if (leadingSlash && [transformed count] != 0
        && [[transformed objectAtIndex:0] isEqualToString:@"/"])
        [transformed removeObjectAtIndex:0];
    body = [transformed componentsJoinedByString:@"/"];
    [transformed release];
    if (leadingSlash)
        body = [@"/" stringByAppendingString:body];
    if (trailingSlash)
        body = [body stringByAppendingString:@"/"];
    return body;
}

static BOOL NSPathHasDrivePrefix(NSString *path) {
    unichar first;
    unichar second;

    if ([path length] < 2)
        return NO;
    first = [path characterAtIndex:0];
    second = [path characterAtIndex:1];
    return second == ':' && ((first >= 'A' && first <= 'Z')
                             || (first >= 'a' && first <= 'z'));
}

static unsigned int NSPathStartOfExtension(NSString *path) {
    unsigned int length = [path length];
    unsigned int index;

    if (length <= 1)
        return 0;
    index = length - 1;
    while (index > 0) {
        if ([path characterAtIndex:index - 1] == '/')
            return 0;
        if ([path characterAtIndex:index] == '.') {
            if (index == 2 && NSPathHasDrivePrefix(path))
                return 0;
            return index;
        }
        index--;
    }
    return 0;
}

@implementation NSPathStore2

+ (id)pathWithComponents:(NSArray *)components {
    unichar path[1026];
    unsigned pathLength = 0;
    unsigned count = [components count];
    unsigned maximumComponentLength = 0;
    unsigned componentBufferSize;
    id *componentObjects = __builtin_alloca((count != 0 ? count : 1)
                                             * sizeof(id));
    unsigned *componentLengths = __builtin_alloca((count != 0 ? count : 1)
                                                   * sizeof(unsigned));
    unichar *componentCharacters;
    SEL objectAtIndexSelector = @selector(objectAtIndex:);
    NSPathObjectAtIndexIMP objectAtIndex =
        (NSPathObjectAtIndexIMP)_NSIMPForObjectAndSelector(components,
                                                           objectAtIndexSelector);
    unsigned index;

    for (index = 0; index < count; index++) {
        id component = objectAtIndex(components, objectAtIndexSelector, index);
        unsigned componentLength = [component length];

        componentObjects[index] = component;
        componentLengths[index] = componentLength;
        if (componentLength > maximumComponentLength)
            maximumComponentLength = componentLength;
    }

    componentBufferSize = (maximumComponentLength * sizeof(unichar) + 18)
                          & ~15;
    componentCharacters = __builtin_alloca(componentBufferSize);
    for (index = 0; index < count; index++) {
        NSString *component = componentObjects[index];
        unsigned componentLength = componentLengths[index];

        [component getCharacters:componentCharacters
                           range:NSMakeRange(0, componentLength)];
        if (componentLength + pathLength > 1018) {
            NSPathStoreTransmuteSlashes(path, &pathLength, '/');
            NSPathStoreStripTrailingSlashes(path, &pathLength);
        }
        if (!NSPathStoreAppendComponent(path, &pathLength, 1026,
                                        componentCharacters, componentLength))
            NSLog(@"%@: cannot append path '%@' to path '%@'",
                  _NSMethodExceptionProem(self, _cmd), component,
                  [self pathStoreWithCharacters:path length:pathLength]);
    }
    NSPathStoreTransmuteSlashes(path, &pathLength, '/');
    NSPathStoreStripTrailingSlashes(path, &pathLength);
    return [self pathStoreWithCharacters:path length:pathLength];
}

+ (id)pathStoreWithCharacters:(const unichar *)characters length:(unsigned)length {
    NSPathStore2 *string = NSAllocateObject(__NSPathStore2Class,
                                            length * sizeof(unichar), NULL);
    unichar *storedCharacters = NSPathStoreCharacters(string);
    unsigned storedLength = length;

    if (length != 0) {
        memmove(storedCharacters, characters, length * sizeof(unichar));
        NSPathStoreStripTrailingSlashes(storedCharacters, &storedLength);
    }
    string->_lengthAndRefCount = (storedLength << 20)
                                 | (string->_lengthAndRefCount & 0x000fffff);
    return [string autorelease];
}

#if !defined(__ppc__) && !defined(__POWERPC__)
+ (id)pathStoreWithCString:(const char *)bytes {
    unsigned byteLength = bytes != NULL ? (unsigned)strlen(bytes) : 0;
    NSPathStoreConversionBuffer buffer;
    NSPathStore2 *string;
    unichar *storedCharacters;
    unsigned storedLength;

    if (!_NSConvertToASCIIorUnicode2(bytes, byteLength,
                                     _NSDefaultCStringEncoding(), YES,
                                     &buffer, NULL))
        return nil;
    string = NSAllocateObject(__NSPathStore2Class,
                              byteLength * sizeof(unichar), NULL);
    if (buffer.isCString) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: Didn't get Unicode",
                           _NSMethodExceptionProem(self, _cmd)];
        [string release];
        if (buffer.allocated)
            NSZoneFree(NULL, buffer.characters);
        return nil;
    }
    storedCharacters = NSPathStoreCharacters(string);
    storedLength = buffer.length;
    if (storedLength != 0) {
        memmove(storedCharacters, buffer.characters,
                storedLength * sizeof(unichar));
        if (buffer.allocated)
            NSZoneFree(NULL, buffer.characters);
        NSPathStoreStripTrailingSlashes(storedCharacters, &storedLength);
    }
    string->_lengthAndRefCount = (storedLength << 20)
                                 | (string->_lengthAndRefCount & 0x000fffff);
    return [string autorelease];
}
#endif

- (unsigned)length {
    return _lengthAndRefCount >> 20;
}

- (unichar)characterAtIndex:(unsigned)index {
    unsigned length = _lengthAndRefCount >> 20;

    if (index >= length) {
        [NSException raise:NSRangeException
                    format:@"%@: index (%d) beyond bounds (%d)",
                           _NSMethodExceptionProem(self, _cmd), index, length];
        return 0;
    }
    return NSPathStoreCharacters(self)[index];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    unsigned length = _lengthAndRefCount >> 20;

    if (length + 1 <= range.location + range.length) {
        [NSException raise:NSRangeException
                    format:@"%@: index (%d) beyond bounds (%d)",
                           _NSMethodExceptionProem(self, _cmd),
                           range.location + range.length, length + 1];
        return;
    }
    if (range.length != 0)
        memmove(buffer, NSPathStoreCharacters(self) + range.location,
                range.length * sizeof(unichar));
}

- (BOOL)isEqualToString:(NSString *)otherString {
    unsigned length;
    unsigned otherLength;
    unichar localCharacters[0x410];
    unichar *otherCharacters = localCharacters;
    int comparison;

    if (otherString == (NSString *)self)
        return YES;
    if (otherString == nil)
        return NO;
    length = _lengthAndRefCount >> 20;
    if (((struct objc_object *)otherString)->isa == __NSPathStore2Class) {
        NSPathStore2 *otherPath = (NSPathStore2 *)otherString;
        otherLength = otherPath->_lengthAndRefCount >> 20;
        return NSCompareCharacters(NSPathStoreCharacters(self),
                                   NSPathStoreCharacters(otherPath), length,
                                   otherLength, 0) == 0;
    }
    otherLength = [otherString length];
    if (otherLength > 0x410)
        otherCharacters = NSZoneMalloc(NULL, otherLength * sizeof(unichar));
    [otherString getCharacters:otherCharacters
                         range:NSMakeRange(0, otherLength)];
    comparison = NSCompareCharacters(NSPathStoreCharacters(self),
                                     otherCharacters, length, otherLength, 0);
    if (otherCharacters != localCharacters)
        NSZoneFree(NULL, otherCharacters);
    return comparison == 0;
}

- (unsigned)hash {
    return NSHashCharacters(NSPathStoreCharacters(self),
                            _lengthAndRefCount >> 20);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

- (id)retain {
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if ((_lengthAndRefCount & 0x000fffff) != 0x000fffff)
        _lengthAndRefCount++;
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (void)release {
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if ((_lengthAndRefCount & 0x000fffff) == 0) {
        if (_NSGlobalRetainLock != nil)
            [_NSGlobalRetainLock unlock];
#if defined(__ppc__) || defined(__POWERPC__)
        [self dealloc];
#else
        [super dealloc];
#endif
        return;
    }
    if ((_lengthAndRefCount & 0x000fffff) != 0x000fffff)
        _lengthAndRefCount--;
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
}

- (unsigned)retainCount {
    return (_lengthAndRefCount & 0x000fffff) + 1;
}

- (BOOL)isAbsolutePath {
    return _NSIsAbsolutePath(NSPathStoreCharacters(self),
                             _lengthAndRefCount >> 20);
}

- (NSArray *)pathComponents {
    return _NSPathComponents(NSPathStoreCharacters(self),
                             _lengthAndRefCount >> 20);
}

- (NSString *)pathExtension {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned start = NSPathStoreStartOfExtension(NSPathStoreCharacters(self),
                                                  length);

    if (start == 0)
        return @"";
    return [self substringWithRange:NSMakeRange(start + 1,
                                                 length - start - 1)];
}

- (NSString *)lastPathComponent {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned start = NSPathStoreStartOfLastComponent(NSPathStoreCharacters(self),
                                                      length);

    if (start == 0)
        return self;
    return [NSPathStore2 pathStoreWithCharacters:
                NSPathStoreCharacters(self) + start
                                            length:length - start];
}

- (NSString *)stringByDeletingLastPathComponent {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned prefixLength = NSPathStoreLengthAfterDeletingLastComponent(
        NSPathStoreCharacters(self), length);

    return [NSPathStore2 pathStoreWithCharacters:NSPathStoreCharacters(self)
                                           length:prefixLength];
}

- (NSString *)stringByDeletingPathExtension {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned prefixLength = NSPathStoreStartOfExtension(
        NSPathStoreCharacters(self), length);

    if (prefixLength == 0)
        prefixLength = length;
    return [NSPathStore2 pathStoreWithCharacters:NSPathStoreCharacters(self)
                                           length:prefixLength];
}

- (NSString *)stringByExpandingTildeInPath {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        memmove(characters, NSPathStoreCharacters(self),
                copyLength * sizeof(unichar));
    NSPathStoreExpandTilde(characters, &length, 1024);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByAbbreviatingWithTildeInPath {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        memmove(characters, NSPathStoreCharacters(self),
                copyLength * sizeof(unichar));
    NSPathStoreAbbreviateTilde(characters, &length);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByStandardizingPath {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        memmove(characters, NSPathStoreCharacters(self),
                copyLength * sizeof(unichar));
    NSPathStoreExpandTilde(characters, &length, 1024);
    (void)_NSStandardizePath(characters, &length, 1024);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByResolvingSymlinksInPath {
    unsigned length = _lengthAndRefCount >> 20;
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        memmove(characters, NSPathStoreCharacters(self),
                copyLength * sizeof(unichar));
    NSPathStoreExpandTilde(characters, &length, 1024);
    (void)NSPathStoreResolveSymlinks(characters, &length, 1024);
    (void)_NSStandardizePath(characters, &length, 1024);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByAppendingPathComponent:(NSString *)component {
    unsigned pathLength = _lengthAndRefCount >> 20;
    unsigned componentLength;
    unsigned capacity;
    unichar stackComponent[0x410];
    unichar *componentCharacters = stackComponent;
    BOOL allocated = NO;
    unichar *path;
    id result;

    if (component == nil)
        return self;
    if (((NSPathStore2 *)component)->isa == __NSPathStore2Class) {
        NSPathStore2 *componentStore = (NSPathStore2 *)component;

        componentLength = componentStore->_lengthAndRefCount >> 20;
        componentCharacters = NSPathStoreCharacters(componentStore);
    } else {
        componentLength = [component length];
        if (componentLength > 0x410) {
            componentCharacters = NSZoneMalloc(NULL,
                componentLength * sizeof(unichar));
            allocated = YES;
        }
        [component getCharacters:componentCharacters
                           range:NSMakeRange(0, componentLength)];
    }
    capacity = pathLength + componentLength + 1;
    path = __builtin_alloca(capacity * sizeof(unichar) + 4);
    if (pathLength != 0)
        memmove(path, NSPathStoreCharacters(self), pathLength * sizeof(unichar));
    if (!NSPathStoreAppendComponent(path, &pathLength, capacity,
                                    componentCharacters, componentLength)) {
        NSLog(@"%@: cannot append path '%@' to path '%@'",
              _NSMethodExceptionProem(self, _cmd), component, self);
        result = self;
    } else {
        NSPathStoreTransmuteSlashes(path, &pathLength, '/');
        NSPathStoreStripTrailingSlashes(path, &pathLength);
        result = [NSPathStore2 pathStoreWithCharacters:path length:pathLength];
    }
    if (allocated)
        NSZoneFree(NULL, componentCharacters);
    return result;
}

- (NSString *)stringByAppendingPathExtension:(NSString *)extension {
    unsigned pathLength = _lengthAndRefCount >> 20;
    unsigned extensionLength = [extension length];
    unsigned capacity = pathLength + extensionLength + 1;
    unichar *extensionCharacters = __builtin_alloca(
        extensionLength * sizeof(unichar) + 4);
    unichar *path = __builtin_alloca(capacity * sizeof(unichar) + 4);
    id result;

    [extension getCharacters:extensionCharacters
                       range:NSMakeRange(0, extensionLength)];
    if (pathLength != 0)
        memmove(path, NSPathStoreCharacters(self), pathLength * sizeof(unichar));
    if (!NSPathStoreAppendExtension(path, &pathLength, capacity,
                                    extensionCharacters, extensionLength)) {
        NSLog(@"%@: cannot append extension '%@' to path '%@'",
              _NSMethodExceptionProem(self, _cmd), extension, self);
        result = self;
    } else {
        NSPathStoreTransmuteSlashes(path, &pathLength, '/');
        NSPathStoreStripTrailingSlashes(path, &pathLength);
        result = [NSPathStore2 pathStoreWithCharacters:path length:pathLength];
    }
    return result;
}

@end

@implementation NSString (NSPathUtilities)
+ (NSString *)pathWithComponents:(NSArray *)components {
    return [NSPathStore2 pathWithComponents:components];
}

- (NSArray *)pathComponents {
    unsigned length = [self length];
    unichar stackCharacters[1024];
    unichar *characters = stackCharacters;
    BOOL allocated = NO;
    NSArray *components;

    if (length > 1024) {
        characters = NSZoneMalloc(NULL, length * sizeof(unichar));
        allocated = YES;
    }
    if (length != 0)
        [self getCharacters:characters range:NSMakeRange(0, length)];
    components = _NSPathComponents(characters, length);
    if (allocated)
        NSZoneFree(NULL, characters);
    return components;
}

- (BOOL)isAbsolutePath {
    unsigned length = [self length];
    unichar characters[3];

    if (length > 3)
        length = 3;
    if (length != 0)
        [self getCharacters:characters range:NSMakeRange(0, length)];
    return _NSIsAbsolutePath(characters, length);
}

- (NSString *)lastPathComponent {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];
    unsigned start;

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);
    start = _NSStartOfLastPathComponent(characters, length);
    return [NSPathStore2 pathStoreWithCharacters:characters + start
                                           length:length - start];
}

- (NSString *)stringByDeletingLastPathComponent {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];
    unsigned prefixLength;

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);
    prefixLength = _NSLengthAfterDeletingLastPathComponent(characters, length);
    return [NSPathStore2 pathStoreWithCharacters:characters
                                           length:prefixLength];
}

- (NSString *)stringByAppendingPathComponent:(NSString *)str {
    unsigned pathLength = [self length];
    unsigned componentLength = [str length];
    unichar path[1024];
    unichar inlineComponent[1024];
    unichar *component = inlineComponent;
    BOOL allocated = NO;
    id result;

    if (pathLength > 1024)
        pathLength = 1024;
    if (componentLength > 1024) {
        component = NSZoneMalloc(NULL, componentLength * sizeof(unichar));
        allocated = YES;
    }
    if (pathLength != 0)
        [self getCharacters:path range:NSMakeRange(0, pathLength)];
    if (componentLength != 0)
        [str getCharacters:component range:NSMakeRange(0, componentLength)];
    if (!_NSAppendPathComponent(path, &pathLength, 1024,
                                component, componentLength)) {
        NSLog(@"%@: cannot append path '%@' to path '%@'",
              _NSMethodExceptionProem(self, _cmd), str, self);
        result = self;
    } else {
        (void)_NSTransmutePathSlashes(path, &pathLength, '/');
        (void)_NSStripTrailingPathSlashes(path, &pathLength);
        result = [NSPathStore2 pathStoreWithCharacters:path length:pathLength];
    }
    if (allocated)
        NSZoneFree(NULL, component);
    return result;
}

- (NSString *)pathExtension {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];
    unsigned dot;

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);
    dot = _NSStartOfPathExtension(characters, length);
    if (dot == 0)
        return @"";
    return [self substringWithRange:NSMakeRange(dot + 1, length - dot - 1)];
}

- (NSString *)stringByDeletingPathExtension {
    unsigned length = [self length];
    unichar *characters = __builtin_alloca(length * sizeof(unichar) + 16);
    unsigned prefixLength;

    if (length != 0)
        [self getCharacters:characters range:NSMakeRange(0, length)];
    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);
    prefixLength = _NSLengthAfterDeletingPathExtension(characters, length);
    return [NSPathStore2 pathStoreWithCharacters:characters length:prefixLength];
}

- (NSString *)stringByAppendingPathExtension:(NSString *)str {
    unsigned extensionLength = [str length];
    unsigned pathLength = [self length];
    unsigned capacity = pathLength + extensionLength + 1;
    unichar stackExtension[0x410];
    unichar *extensionCharacters = stackExtension;
    unichar *path = NSZoneMalloc(NULL, capacity * sizeof(unichar));
    BOOL allocated = NO;
    id result;

    if (extensionLength > 0x410) {
        extensionCharacters = NSZoneMalloc(NULL,
                                            extensionLength * sizeof(unichar));
        allocated = YES;
    }
    if (pathLength != 0)
        [self getCharacters:path range:NSMakeRange(0, pathLength)];
    if (extensionLength != 0)
        [str getCharacters:extensionCharacters
                     range:NSMakeRange(0, extensionLength)];
    if (!NSPathStoreAppendExtension(path, &pathLength, capacity,
                                    extensionCharacters, extensionLength)) {
        NSLog(@"%@: cannot append extension '%@' to path '%@'",
              _NSMethodExceptionProem(self, _cmd), str, self);
        result = self;
    } else {
        NSPathStoreTransmuteSlashes(path, &pathLength, '/');
        NSPathStoreStripTrailingSlashes(path, &pathLength);
        result = [NSPathStore2 pathStoreWithCharacters:path length:pathLength];
    }
    NSZoneFree(NULL, path);
    if (allocated)
        NSZoneFree(NULL, extensionCharacters);
    return result;
}

- (NSString *)stringByAbbreviatingWithTildeInPath {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);
    (void)_NSAbbreviatePathWithTilde(characters, &length);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByExpandingTildeInPath {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    (void)_NSExpandTildeInPath(characters, &length, 1024);

    (void)_NSTransmutePathSlashes(characters, &length, '/');
    (void)_NSStripTrailingPathSlashes(characters, &length);

    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByStandardizingPath {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    NSPathStoreExpandTilde(characters, &length, 1024);
    (void)_NSStandardizePath(characters, &length, 1024);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSString *)stringByResolvingSymlinksInPath {
    unsigned length = [self length];
    unsigned copyLength = length < 1024 ? length : 1024;
    unichar characters[1024];

    if (copyLength != 0)
        [self getCharacters:characters range:NSMakeRange(0, copyLength)];
    length = copyLength;
    NSPathStoreExpandTilde(characters, &length, 1024);
    (void)NSPathStoreResolveSymlinks(characters, &length, 1024);
    (void)_NSStandardizePath(characters, &length, 1024);
    return [NSPathStore2 pathStoreWithCharacters:characters length:length];
}

- (NSArray *)stringsByAppendingPaths:(NSArray *)paths {
    unsigned count;
    unsigned index;
    NSMutableArray *results;

    if ([self isEqualToString:@""])
        return [[paths copyWithZone:[self zone]] autorelease];
    count = [paths count];
    results = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++)
        [results addObject:[self stringByAppendingPathComponent:
                            [paths objectAtIndex:index]]];
    return results;
}

- (unsigned)completePathIntoString:(NSString **)outputName caseSensitive:(BOOL)flag matchesIntoArray:(NSArray **)outputArray filterTypes:(NSArray *)filterTypes {
    NSFileManager *manager = [NSFileManager defaultManager];

    if ([self hasPrefix:@"~"]
        && [self rangeOfString:@"/" options:0
                         range:NSMakeRange(0, [self length])].location
            == NSNotFound) {
        NSMutableSet *userSet = [[NSMutableSet allocWithZone:NULL]
            initWithCapacity:32];
        NSArray *users;
        unsigned int length = [self length];
        NSString *userPrefix = [self substringWithRange:NSMakeRange(1, length - 1)];
        BOOL matchAllUsers = [userPrefix isEqualToString:@""];
        struct passwd *entry;

        setpwent();
        while ((entry = getpwent()) != NULL) {
            NSString *userName = [NSString stringWithCString:entry->pw_name
                length:(unsigned)strlen(entry->pw_name)];
            if (matchAllUsers || [userName hasPrefix:userPrefix])
                [userSet addObject:[@"~" stringByAppendingString:userName]];
        }
        endpwent();
        users = [userSet allObjects];
        [userSet release];
        if (outputName != NULL)
            *outputName = NSFindCommonPrefixInStringArray(users, flag);
        if (outputArray != NULL)
            *outputArray = users;
        return [users count];
    } else {
        NSString *directory;
        NSString *prefix;
        NSString *candidate = nil;
        NSArray *matches;

        if ([self hasSuffix:@"/"] || [self hasSuffix:@"\\"]) {
            directory = self;
            prefix = @"";
        } else {
            directory = [self stringByDeletingLastPathComponent];
            prefix = [self lastPathComponent];
        }

        for (;;) {
            BOOL isDirectory = NO;
            matches = NSDirectoryContentsMatchingPrefixAndSuffixes(manager,
                                                                    directory,
                                                                    prefix,
                                                                    filterTypes);
            if ([matches count] == 0 && candidate == nil)
                return 0;
            if ([matches count] > 1) {
                if (outputName != NULL)
                    *outputName = NSFindCommonPrefixInStringArray(matches, flag);
                if (outputArray != NULL)
                    *outputArray = matches;
                return [matches count];
            }
            if ([matches count] == 1)
                candidate = [matches objectAtIndex:0];
            if ([matches count] == 0
                || ([manager fileExistsAtPath:candidate isDirectory:&isDirectory]
                    && !isDirectory))
                break;
            directory = candidate;
            prefix = @"";
        }
        if (outputName != NULL)
            *outputName = candidate;
        if (outputArray != NULL)
            *outputArray = [NSArray arrayWithObject:candidate];
        return 1;
    }
}

- (const char *)fileSystemRepresentation {
    return [[NSFileManager defaultManager] fileSystemRepresentationWithPath:self];
}

- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max {
    return [[NSFileManager defaultManager]
        getFileSystemRepresentation:cname maxLength:max withPath:self];
}

- (NSString *)stringByConvertingPathToURL {
    NSString *standardizedPath = [self stringByStandardizingPath];

    return [@"file://localhost" stringByAppendingString:standardizedPath];
}

- (NSString *)stringByConvertingURLToPath {
    NSString *path;

    if ([self hasPrefix:@"file:"]) {
        NSString *suffix = [self substringFromIndex:5];

        path = [suffix hasPrefix:@"//"]
            ? [self substringFromIndex:2]
            : nil;
        if (path == nil)
            return nil;
        if ([path characterAtIndex:0] != '/') {
            if (![path hasPrefix:@"localhost"])
                return nil;
            path = [self substringFromIndex:9];
        }
    } else {
        path = self;
        if ([self rangeOfString:@":"].location != NSNotFound)
            path = nil;
    }
    if (path != nil)
        return [path stringByStandardizingPath];
    return nil;
}

@end

@implementation NSString (NSURLPathUtilities)

- (NSString *)stringByAddingPercentEscapes {
#if defined(__ppc__) || defined(__POWERPC__)
    static const char hex[] = "0123456789ABCDEF";
    NSStringEncoding encoding = _NSDefaultFileSystemEncoding();
    NSData *data = [self dataUsingEncoding:encoding allowLossyConversion:NO];
    const unsigned char *bytes;
    unsigned length;
    unsigned index;
    unsigned start = 0;
    NSMutableData *escaped = nil;
    NSString *result;

    if (data == nil)
        return nil;
    bytes = [data bytes];
    length = [data length];
    for (index = 0; index < length; index++) {
        unsigned char character = bytes[index];
        unsigned char sequence[3];

        if (!NSURLCharacterNeedsEscaping(character))
            continue;
        if (escaped == nil) {
            escaped = [[NSMutableData allocWithZone:NULL]
                initWithBytes:bytes length:index];
        } else if (index > start) {
            [escaped appendBytes:bytes + start length:index - start];
        }
        sequence[0] = '%';
        sequence[1] = hex[character >> 4];
        sequence[2] = hex[character & 0x0f];
        [escaped appendBytes:sequence length:sizeof(sequence)];
        start = index + 1;
    }
    if (escaped == nil)
        return self;
    if (start < length)
        [escaped appendBytes:bytes + start length:length - start];
    result = [[[NSString allocWithZone:NULL] initWithData:escaped
        encoding:encoding] autorelease];
    [escaped release];
    return result;
#else
    unsigned int length = [self length];
    unsigned int index;
    unsigned int start = 0;
    NSMutableString *result = nil;

    for (index = 0; index < length; index++) {
        unichar character = [self characterAtIndex:index];
        if (!NSURLCharacterNeedsEscaping(character))
            continue;
        if (result == nil)
            result = [NSMutableString stringWithCapacity:length + 2];
        if (index > start)
            [result appendString:[self substringWithRange:NSMakeRange(start, index - start)]];
        [result appendString:_NSURLEscapeSequenceForCharacter(character)];
        start = index + 1;
    }
    if (result == nil)
        return self;
    if (start < length)
        [result appendString:[self substringWithRange:NSMakeRange(start, length - start)]];
    return [NSString stringWithString:result];
#endif
}

- (NSString *)stringByRemovingPercentEscapes {
#if defined(__ppc__) || defined(__POWERPC__)
    NSStringEncoding encoding = _NSDefaultFileSystemEncoding();
    NSData *data = [self dataUsingEncoding:encoding allowLossyConversion:NO];
    const unsigned char *bytes;
    unsigned length;
    unsigned index;
    unsigned start = 0;
    NSMutableData *unescaped = nil;
    NSString *result;

    if (data == nil)
        return nil;
    bytes = [data bytes];
    length = [data length];
    for (index = 0; index + 2 < length; index++) {
        if (bytes[index] != '%')
            continue;
        if (unescaped == nil)
            unescaped = [[NSMutableData allocWithZone:NULL]
                initWithCapacity:length];
        if (index > start)
            [unescaped appendBytes:bytes + start length:index - start];
        {
            unsigned char decoded = (unsigned char)(
                NSURLHexValue(bytes[index + 1]) * 16
                + NSURLHexValue(bytes[index + 2]));
            [unescaped appendBytes:&decoded length:1];
        }
        index += 2;
        start = index + 1;
    }
    if (unescaped == nil)
        return self;
    if (start < length)
        [unescaped appendBytes:bytes + start length:length - start];
    result = [[[NSString allocWithZone:NULL] initWithData:unescaped
        encoding:encoding] autorelease];
    [unescaped release];
    return result;
#else
    unsigned int length = [self length];
    unsigned int index;
    unsigned int start = 0;
    NSMutableString *result = nil;

    for (index = 0; index + 2 < length; index++) {
        if ([self characterAtIndex:index] != '%')
            continue;
        if (result == nil)
            result = [NSMutableString stringWithCapacity:length];
        if (index > start)
            [result appendString:[self substringWithRange:NSMakeRange(start, index - start)]];
        {
            unichar decoded = NSURLHexValue([self characterAtIndex:index + 1]) * 16
                              + NSURLHexValue([self characterAtIndex:index + 2]);
            [result appendString:[NSString stringWithCharacters:&decoded length:1]];
        }
        index += 2;
        start = index + 1;
    }
    if (result == nil)
        return self;
    if (start < length)
        [result appendString:[self substringWithRange:NSMakeRange(start, length - start)]];
    return [NSString stringWithString:result];
#endif
}

- (NSString *)standardizedURLPath {
    return NSURLTransformPath(self, YES);
}

- (NSString *)standardizedNativePath {
    return NSURLTransformPath(self, NO);
}

#if defined(__ppc__) || defined(__POWERPC__)
- (NSString *)urlPathByDeletingLastComponent {
    unsigned length = [self length];
    NSRange range;

    if ([self hasSuffix:@"/"])
        length--;
    range = [self rangeOfString:@"/" options:NSBackwardsSearch
                          range:NSMakeRange(0, length)];
    if (range.length != 0)
        return [self substringToIndex:NSMaxRange(range)];
    return @"";
}

- (NSString *)urlPathByAppendingComponent:(NSString *)component {
    NSString *prefix = self;

    if (![prefix hasSuffix:@"/"])
        prefix = [prefix urlPathByDeletingLastComponent];
    while ([component hasPrefix:@"../"]) {
        if ([component length] <= 3)
            component = @"/";
        else
            component = [component substringFromIndex:3];
        prefix = [prefix urlPathByDeletingLastComponent];
    }
    if ([component hasPrefix:@"/"])
        component = [component substringFromIndex:1];
    if ([component hasPrefix:@"/"])
        component = [component substringFromIndex:1];
    return [NSString stringWithFormat:@"%@%@", prefix, component];
}

- (NSString *)urlPathRelativeToPath:(NSString *)path {
    NSArray *baseComponents;
    NSArray *targetComponents;
    NSMutableArray *relativeComponents;
    unsigned baseCount;
    unsigned targetCount;
    unsigned common = 0;
    unsigned index;

    baseComponents = [[path standardizedURLPath]
        componentsSeparatedByString:@"/"];
    targetComponents = [[self standardizedURLPath]
        componentsSeparatedByString:@"/"];
    baseCount = [baseComponents count];
    targetCount = [targetComponents count];
    relativeComponents = [NSMutableArray array];
    if (path == nil || baseComponents == nil)
        return self;
    while (common < baseCount && common < targetCount
            && [[baseComponents objectAtIndex:common]
                isEqualToString:[targetComponents objectAtIndex:common]])
        common++;
    if (common == baseCount && common == targetCount)
        return self;
    if (common == 0)
        return self;
    if (common == 1 && [[baseComponents objectAtIndex:1]
            isEqualToString:@""])
        return self;

    for (index = common; index < baseCount - 1; index++)
        [relativeComponents addObject:@".."];
    for (index = common; index < targetCount; index++)
        [relativeComponents addObject:[targetComponents objectAtIndex:index]];
    return [relativeComponents componentsJoinedByString:@"/"];
}
#endif

@end

@implementation NSArray (NSArrayPathExtensions)

- (NSArray *)stringsByAppendingPathComponent:(NSString *)component {
    unsigned count = [self count];
    unsigned index;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];

    for (index = 0; index < count; index++) {
        NSString *path = [self objectAtIndex:index];

        [result addObject:[path stringByAppendingPathComponent:component]];
    }
    return result;
}

- (NSArray *)pathsMatchingExtensions:(NSArray *)filterTypes {
    unsigned count = [self count];
    unsigned index;
    NSMutableArray *matches = [NSMutableArray arrayWithCapacity:count];

    for (index = 0; index < count; index++) {
        NSString *path = [self objectAtIndex:index];
        NSString *extension = [path pathExtension];

        if (![extension isEqualToString:@""] && [filterTypes containsObject:extension])
            [matches addObject:path];
    }
    return matches;
}

@end

static BOOL NSPathUserCacheInitialized;
static uid_t NSPathCachedEUID;
static uid_t NSPathCachedUID;
static NSString *NSPathCachedUserName;
static NSString *NSPathCachedFullUserName;
static NSString *NSPathCachedHomeDirectory;

static void NSPathRefreshUserCache(void) {
    uid_t effectiveUID = geteuid();
    uid_t realUID = getuid();

    if (NSPathUserCacheInitialized && effectiveUID == NSPathCachedEUID
        && realUID == NSPathCachedUID)
        return;
    NSPathCachedEUID = effectiveUID;
    NSPathCachedUID = realUID;
    NSPathUserCacheInitialized = YES;
    [NSPathCachedHomeDirectory release];
    NSPathCachedHomeDirectory = nil;
    [NSPathCachedUserName release];
    NSPathCachedUserName = nil;
    [NSPathCachedFullUserName release];
    NSPathCachedFullUserName = nil;
}

static uid_t NSPathUserIDForLookup(void) {
    return geteuid() != 0 ? geteuid() : getuid();
}

NSString *NSUserName(void) {
    struct passwd *account;
    const char *name;

    NSPathRefreshUserCache();
    if (NSPathCachedUserName != nil)
        return NSPathCachedUserName;
    account = getpwuid(NSPathUserIDForLookup());
    name = account != NULL ? account->pw_name : NULL;
    if (name == NULL)
        name = _NSGetEnvironmentVariable("USER");
    if (name != NULL)
        NSPathCachedUserName = [[NSString alloc]
            initWithCString:name length:(unsigned)strlen(name)];
    if (NSPathCachedUserName == nil)
        NSPathCachedUserName = __NSEmptyString;
    return NSPathCachedUserName;
}

NSString *NSFullUserName(void) {
    struct passwd *account;
    const char *name;

    NSPathRefreshUserCache();
    if (NSPathCachedFullUserName != nil)
        return NSPathCachedFullUserName;
    account = getpwuid(NSPathUserIDForLookup());
    name = account != NULL ? account->pw_gecos : NULL;
    if (name != NULL)
        NSPathCachedFullUserName = [[NSString alloc]
            initWithCString:name length:(unsigned)strlen(name)];
    if (NSPathCachedFullUserName == nil)
        NSPathCachedFullUserName = __NSEmptyString;
    return NSPathCachedFullUserName;
}

NSString *NSHomeDirectoryForUser(NSString *userName) {
    struct passwd *account = NULL;
    const char *home = NULL;
    NSString *path = nil;

    NSPathRefreshUserCache();
    if (userName == nil && NSPathCachedHomeDirectory != nil)
        return NSPathCachedHomeDirectory;
    if (userName != nil)
        account = getpwnam([userName cString]);
    else
        account = getpwuid(NSPathUserIDForLookup());
    if (account != NULL && account->pw_dir != NULL) {
        home = account->pw_dir;
#if defined(__ppc__) || defined(__POWERPC__)
        path = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:(char *)home
                                        length:(unsigned)strlen(home)];
#else
        path = [NSPathStore2 pathStoreWithCString:home];
#endif
    }
    if (path == nil &&
        (userName == nil || [userName isEqualToString:NSUserName()])) {
        home = _NSGetEnvironmentVariable("HOME");
        if (home != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
            path = [[NSFileManager defaultManager]
                stringWithFileSystemRepresentation:(char *)home
                                            length:(unsigned)strlen(home)];
#else
            path = [NSPathStore2 pathStoreWithCString:home];
#endif
        }
    }
    path = [path stringByStandardizingPath];
    if (userName != nil)
        return path;
    NSPathCachedHomeDirectory = [path copy];
    return NSPathCachedHomeDirectory;
}

NSString *NSHomeDirectory(void) {
    return NSHomeDirectoryForUser(nil);
}

NSString *NSOpenStepDirectoryForUser(NSString *userName,
                                     BOOL createIfNeeded) {
    NSString *homeDirectory = NSHomeDirectoryForUser(userName);
    NSString *directory;

    if (homeDirectory == nil)
        return nil;
    directory = [homeDirectory stringByAppendingPathComponent:@".OpenStep"];
    if (!_NSFileAccessibleForMode(directory, 0) && createIfNeeded) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSFileManager *manager = [NSFileManager defaultManager];
#else
        NSFileManager *manager;
#endif
        NSString *owner = userName != nil ? userName : NSUserName();
        NSNumber *permissions = [NSNumber numberWithUnsignedLong:0755];
        NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:owner, NSFileOwnerAccountName,
                                         permissions, NSFilePosixPermissions,
                                         nil];

#if !defined(__ppc__) && !defined(__POWERPC__)
        manager = [NSFileManager defaultManager];
#endif
        [manager createDirectoryAtPath:directory attributes:attributes];
    }
    return directory;
}

int _NSTempDirectory(char *path) {
    strcpy(path, "/tmp");
    return 1;
}

NSString *NSTemporaryDirectory(void) {
#if defined(__ppc__) || defined(__POWERPC__)
    char temporaryPath[1044];
    unsigned length;
    NSString *directory;

    if (!_NSTempDirectory(temporaryPath))
        return nil;
    for (length = 0; temporaryPath[length] != '\0'; length++)
        ;
    directory = [[NSFileManager defaultManager]
        stringWithFileSystemRepresentation:temporaryPath length:length];
    return [directory stringByStandardizingPath];
#else
    char temporaryPath[1028];

    if (!_NSTempDirectory(temporaryPath))
        return nil;
    return [[NSPathStore2 pathStoreWithCString:temporaryPath]
        stringByStandardizingPath];
#endif
}

NSString *NSOpenStepRootDirectory(void) {
    const char *root = _NSGetEnvironmentVariable("NEXT_ROOT");

    if (root == NULL || *root == 0)
        return @"/";
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned length;

        for (length = 0; root[length] != '\0'; length++)
            ;
        return [[[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:root length:length]
            stringByStandardizingPath];
    }
#else
    return [[NSPathStore2 pathStoreWithCString:root]
        stringByStandardizingPath];
#endif
}

NSString *NSNeXTRootDirectory(void) {
    return NSOpenStepRootDirectory();
}

NSArray *NSStandardApplicationPaths(void) {
    NSString *path = [@"~/Applications" stringByExpandingTildeInPath];

#if defined(__ppc__) || defined(__POWERPC__)
    return [NSArray arrayWithObjects:path, @"/Local/Applications",
                                     @"/System/Applications", nil];
#else
    return [NSArray arrayWithObjects:path, nil];
#endif
}

NSArray *NSStandardLibraryPaths(void) {
    NSString *path = [@"~/Library" stringByExpandingTildeInPath];

#if defined(__ppc__) || defined(__POWERPC__)
    return [NSArray arrayWithObjects:path, @"/Local/Library",
                                     @"/System/Library", nil];
#else
    return [NSArray arrayWithObjects:path, nil];
#endif
}

NSArray *NSSearchPathForDirectoriesInDomains(
    NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask,
    BOOL expandTilde) {
    NSMutableArray *paths = [NSMutableArray array];
    unsigned int state = NSStartSearchPathEnumeration(directory, domainMask);
#if defined(__ppc__) || defined(__POWERPC__)
    char pathBuffer[1044];
#else
    char pathBuffer[1028];
#endif

    while ((state = NSGetNextSearchPathEnumeration(state, pathBuffer)) != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        unsigned length;
        NSString *path;

        for (length = 0; pathBuffer[length] != '\0'; length++)
            ;
        path = [[NSFileManager defaultManager]
            stringWithFileSystemRepresentation:pathBuffer length:length];
#else
        NSString *path = [NSString stringWithCString:pathBuffer];
#endif

        if (expandTilde && [path hasPrefix:@"~"])
            path = [path stringByExpandingTildeInPath];
        [paths addObject:path];
    }
    if ([paths count] != 0)
        return [NSArray arrayWithArray:paths];
    return __NSEmptyArray;
}
