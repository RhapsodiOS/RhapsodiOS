/*  NSStringEncodings.m
    String encoding and conversion support
*/

#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCharacterSet.h>
#import <objc/objc-load.h>

#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cthreads.h>

extern NSStringEncoding _NSDefaultCStringEncoding(void);
#if defined(__ppc__) || defined(__POWERPC__)
extern unsigned int _NSCStringToUnsignedLong(char *string, char **endPointer);
#endif
extern NSBundle *_NSFoundationBundle(void);
extern id _NSMethodExceptionProem(id object, SEL selector);
char _NSFoundationResourceCPath(char *path);

NSStringEncoding _NSCStringEncoding = NSMacOSRomanStringEncoding;

const unsigned int kReplacementCharacter = 0xfffd;
const unsigned int kMaximumUCS2 = 0xffff;
const unsigned int kMaximumUTF16 = 0x10ffff;
const unsigned int kMaximumUCS4 = 0x7fffffff;

unichar
NSMacOSRomanToPrecompUnicode(unsigned char byte)
{
    static const unichar highBytes[128] = {
        0x00c4, 0x00c5, 0x00c7, 0x00c9, 0x00d1, 0x00d6, 0x00dc, 0x00e1,
        0x00e0, 0x00e2, 0x00e4, 0x00e3, 0x00e5, 0x00e7, 0x00e9, 0x00e8,
        0x00ea, 0x00eb, 0x00ed, 0x00ec, 0x00ee, 0x00ef, 0x00f1, 0x00f3,
        0x00f2, 0x00f4, 0x00f6, 0x00f5, 0x00fa, 0x00f9, 0x00fb, 0x00fc,
        0x2020, 0x00b0, 0x00a2, 0x00a3, 0x00a7, 0x2022, 0x00b6, 0x00df,
        0x00ae, 0x00a9, 0x2122, 0x00b4, 0x00a8, 0x2260, 0x00c6, 0x00d8,
        0x221e, 0x00b1, 0x2264, 0x2265, 0x00a5, 0x00b5, 0x2202, 0x2211,
        0x220f, 0x03c0, 0x222b, 0x00aa, 0x00ba, 0x2126, 0x00e6, 0x00f8,
        0x00bf, 0x00a1, 0x00ac, 0x221a, 0x0192, 0x2248, 0x2206, 0x00ab,
        0x00bb, 0x2026, 0x00a0, 0x00c0, 0x00c3, 0x00d5, 0x0152, 0x0153,
        0x2013, 0x2014, 0x201c, 0x201d, 0x2018, 0x2019, 0x00f7, 0x25ca,
        0x00ff, 0x0178, 0x2044, 0x00a4, 0x2039, 0x203a, 0xfb01, 0xfb02,
        0x2021, 0x00b7, 0x201a, 0x201e, 0x2030, 0x00c2, 0x00ca, 0x00c1,
        0x00cb, 0x00c8, 0x00cd, 0x00ce, 0x00cf, 0x00cc, 0x00d3, 0x00d4,
        0xf8ff, 0x00d2, 0x00da, 0x00db, 0x00d9, 0x0131, 0x02c6, 0x02dc,
        0x00af, 0x02d8, 0x02d9, 0x02da, 0x00b8, 0x02dd, 0x02db, 0x02c7
    };

    if (byte <= 0x7f)
        return byte;
    return highBytes[byte - 0x80];
}

unichar (*_NSCStringCharToUnichar)(unsigned char byte) =
    NSMacOSRomanToPrecompUnicode;

typedef int (*NSUserEncodingToUnicode)(unsigned char **bytes, unsigned remaining,
                                       unichar *characters);
typedef int (*NSUserUnicodeToEncoding)(unichar character, unsigned char *bytes);

static NSUserEncodingToUnicode NSProprietaryEncodingToUnicode;
static NSUserUnicodeToEncoding NSProprietaryUnicodeToEncoding;
static const char *NSProprietaryEncodingName;
extern NSString *__NSEmptyString;

int
_NSInitProprietaryCStringEncoding(NSUserEncodingToUnicode toUnicode,
                                  NSUserUnicodeToEncoding fromUnicode,
                                  const char *name)
{
    if (toUnicode == 0 || fromUnicode == 0 || name == 0)
        return 0;
    NSProprietaryEncodingToUnicode = toUnicode;
    NSProprietaryUnicodeToEncoding = fromUnicode;
    NSProprietaryEncodingName = name;
    return 1;
}

NSString *
_NSProprietaryEncodingName(void)
{
    if (NSProprietaryEncodingName != 0)
        return [NSString stringWithCString:NSProprietaryEncodingName];
    return __NSEmptyString;
}

int
_NSProprietaryEncodingToUnicode(unsigned char **bytes, unsigned remaining,
                                unichar *characters)
{
    return NSProprietaryEncodingToUnicode(bytes, remaining, characters);
}

static int NSDefaultCStringEncoding = -1;
static int NSDefaultFileSystemEncoding = -1;

extern int _NSOpenFileDescriptor(char *path, int flags, int mode);
static Class NSProprietaryEncodingClass;

static void
NSProprietaryEncodingLoadCallback(Class classObject, Category category)
{
    (void)category;
    NSProprietaryEncodingClass = classObject;
}

static NSStringEncoding
NSLoadProprietaryEncodingFunctions(char *path)
{
    char *moduleList[2];

    moduleList[0] = path;
    moduleList[1] = 0;
    if (objc_loadModules(moduleList, 0, NSProprietaryEncodingLoadCallback, 0, 0) == 0)
        return NSProprietaryStringEncoding;
    NSProprietaryEncodingClass = Nil;
    return NSISOLatin1StringEncoding;
}

NSStringEncoding
_NSDefaultCStringEncoding(void)
{
    char path[1024];
#if defined(__ppc__) || defined(__POWERPC__)
    char value[16];
#else
    char value[20];
#endif
    int descriptor;

    if (NSDefaultCStringEncoding < 0) {
        _NSFoundationResourceCPath(path);
        strcat(path, "/CStringEncoding");
        descriptor = open(path, O_RDONLY, 0);
        if (descriptor >= 0) {
            memset(value, 0, sizeof(value));
#if defined(__ppc__) || defined(__POWERPC__)
            if (read(descriptor, value, sizeof(value) - 1) > 0)
                NSDefaultCStringEncoding =
                    (int)_NSCStringToUnsignedLong(value, NULL);
#else
            if (read(descriptor, value, sizeof(value) - 1) > 0)
                NSDefaultCStringEncoding = (int)strtoul(value, 0, 10);
#endif
            close(descriptor);
        }
        if (NSDefaultCStringEncoding <= 0)
            NSDefaultCStringEncoding = _NSCStringEncoding;
        if (NSDefaultCStringEncoding == NSProprietaryStringEncoding) {
            _NSFoundationResourceCPath(path);
            strcat(path, "/CStringEncoding.obj");
            NSDefaultCStringEncoding = NSLoadProprietaryEncodingFunctions(path);
        }
    }
    return NSDefaultCStringEncoding;
}

NSStringEncoding
_NSDefaultFileSystemEncoding(void)
{
    char path[1024];
#if defined(__ppc__) || defined(__POWERPC__)
    char value[16];
#else
    char value[24];
#endif
    int descriptor;

    if (NSDefaultFileSystemEncoding < 0) {
        _NSFoundationResourceCPath(path);
        strcat(path, "/FileSystemEncoding");
        descriptor = _NSOpenFileDescriptor(path, O_RDONLY, 0);
        if (descriptor >= 0) {
            memset(value, 0, sizeof(value));
#if defined(__ppc__) || defined(__POWERPC__)
            if (read(descriptor, value, 15) > 0)
                NSDefaultFileSystemEncoding =
                    (int)_NSCStringToUnsignedLong(value, NULL);
#else
            if (read(descriptor, value, 20) > 0)
                NSDefaultFileSystemEncoding = (int)strtoul(value, 0, 10);
#endif
            close(descriptor);
        }
        if (NSDefaultFileSystemEncoding <= 0) {
#if defined(__ppc__) || defined(__POWERPC__)
            NSDefaultFileSystemEncoding = NSUTF8StringEncoding;
#else
            NSDefaultFileSystemEncoding = _NSDefaultCStringEncoding();
#endif
        }
    }
    return NSDefaultFileSystemEncoding;
}

@interface _NSAutoreleasedMallocMemory : NSObject
+ (void *)mallocMemoryWithCapacity:(unsigned)capacity;
@end

typedef struct {
    unsigned short unicode;
    unsigned char nextStep;
} NSNextStepMapping;

static const NSNextStepMapping NSNextStepMappings[] = {
    { 0x00a0, 0x80 }, { 0x00a1, 0xa1 }, { 0x00a2, 0xa2 }, { 0x00a3, 0xa3 },
    { 0x00a4, 0xa8 }, { 0x00a5, 0xa5 }, { 0x00a6, 0xb5 }, { 0x00a7, 0xa7 },
    { 0x00a8, 0xc8 }, { 0x00a9, 0xa0 }, { 0x00aa, 0xe3 }, { 0x00ab, 0xab },
    { 0x00ac, 0xbe }, { 0x00ae, 0xb0 }, { 0x00af, 0xc5 }, { 0x00b1, 0xd1 },
    { 0x00b2, 0xc9 }, { 0x00b3, 0xcc }, { 0x00b4, 0xc2 }, { 0x00b5, 0x9d },
    { 0x00b6, 0xb6 }, { 0x00b7, 0xb4 }, { 0x00b8, 0xcb }, { 0x00b9, 0xc0 },
    { 0x00ba, 0xeb }, { 0x00bb, 0xbb }, { 0x00bc, 0xd2 }, { 0x00bd, 0xd3 },
    { 0x00be, 0xd4 }, { 0x00bf, 0xbf }, { 0x00c0, 0x81 }, { 0x00c1, 0x82 },
    { 0x00c2, 0x83 }, { 0x00c3, 0x84 }, { 0x00c4, 0x85 }, { 0x00c5, 0x86 },
    { 0x00c6, 0xe1 }, { 0x00c7, 0x87 }, { 0x00c8, 0x88 }, { 0x00c9, 0x89 },
    { 0x00ca, 0x8a }, { 0x00cb, 0x8b }, { 0x00cc, 0x8c }, { 0x00cd, 0x8d },
    { 0x00ce, 0x8e }, { 0x00cf, 0x8f }, { 0x00d0, 0x90 }, { 0x00d1, 0x91 },
    { 0x00d2, 0x92 }, { 0x00d3, 0x93 }, { 0x00d4, 0x94 }, { 0x00d5, 0x95 },
    { 0x00d6, 0x96 }, { 0x00d7, 0x9e }, { 0x00d8, 0xe9 }, { 0x00d9, 0x97 },
    { 0x00da, 0x98 }, { 0x00db, 0x99 }, { 0x00dc, 0x9a }, { 0x00dd, 0x9b },
    { 0x00de, 0x9c }, { 0x00df, 0xfb }, { 0x00e0, 0xd5 }, { 0x00e1, 0xd6 },
    { 0x00e2, 0xd7 }, { 0x00e3, 0xd8 }, { 0x00e4, 0xd9 }, { 0x00e5, 0xda },
    { 0x00e6, 0xf1 }, { 0x00e7, 0xdb }, { 0x00e8, 0xdc }, { 0x00e9, 0xdd },
    { 0x00ea, 0xde }, { 0x00eb, 0xdf }, { 0x00ec, 0xe0 }, { 0x00ed, 0xe2 },
    { 0x00ee, 0xe4 }, { 0x00ef, 0xe5 }, { 0x00f0, 0xe6 }, { 0x00f1, 0xe7 },
    { 0x00f2, 0xec }, { 0x00f3, 0xed }, { 0x00f4, 0xee }, { 0x00f5, 0xef },
    { 0x00f6, 0xf0 }, { 0x00f7, 0x9f }, { 0x00f8, 0xf9 }, { 0x00f9, 0xf2 },
    { 0x00fa, 0xf3 }, { 0x00fb, 0xf4 }, { 0x00fc, 0xf6 }, { 0x00fd, 0xf7 },
    { 0x00fe, 0xfc }, { 0x00ff, 0xfd }, { 0x0131, 0xf5 }, { 0x0141, 0xe8 },
    { 0x0142, 0xf8 }, { 0x0152, 0xea }, { 0x0153, 0xfa }, { 0x0192, 0xa6 },
    { 0x02c6, 0xc3 }, { 0x02c7, 0xcf }, { 0x02cb, 0xc1 }, { 0x02d8, 0xc6 },
    { 0x02d9, 0xc7 }, { 0x02da, 0xca }, { 0x02db, 0xce }, { 0x02dc, 0xc4 },
    { 0x02dd, 0xcd }, { 0x2013, 0xb1 }, { 0x2014, 0xd0 }, { 0x2019, 0xa9 },
    { 0x201a, 0xb8 }, { 0x201c, 0xaa }, { 0x201d, 0xba }, { 0x201e, 0xb9 },
    { 0x2020, 0xb2 }, { 0x2021, 0xb3 }, { 0x2022, 0xb7 }, { 0x2026, 0xbc },
    { 0x2029, 0x0a }, { 0x2030, 0xbd }, { 0x2039, 0xac }, { 0x203a, 0xad },
    { 0x2044, 0xa4 }, { 0xfb01, 0xae }, { 0xfb02, 0xaf }, { 0xfffd, 0xff }
};

int
NSPrecompUnicodeToNEXTSTEP(unichar character, unsigned char *byte)
{
    int first;
    int last;
    int middle;

    if (character <= 0x7f) {
        *byte = (unsigned char)character;
        return 1;
    }

    first = 0;
    last = sizeof(NSNextStepMappings) / sizeof(NSNextStepMappings[0]) - 1;
    while (first <= last) {
        middle = first + (last - first) / 2;
        if (character < NSNextStepMappings[middle].unicode) {
            last = middle - 1;
        } else if (character > NSNextStepMappings[middle].unicode) {
            first = middle + 1;
        } else {
            *byte = NSNextStepMappings[middle].nextStep;
            return 1;
        }
    }
    return 0;
}

static const NSNextStepMapping NSAdobeCyrillicMappings[] = {
    { 0x00a0, 0xa0 }, { 0x00a4, 0xa4 }, { 0x00a6, 0xa6 }, { 0x00a7, 0xa7 },
    { 0x00a9, 0xa9 }, { 0x00ab, 0xab }, { 0x00ac, 0xac }, { 0x00ad, 0xad },
    { 0x00ae, 0xae }, { 0x00b0, 0xb0 }, { 0x00b1, 0xb1 }, { 0x00b5, 0xb5 },
    { 0x00b6, 0xb6 }, { 0x00b7, 0xb7 }, { 0x00bb, 0xbb }, { 0x0401, 0xa8 },
    { 0x0402, 0x80 }, { 0x0403, 0x81 }, { 0x0404, 0xaa }, { 0x0405, 0xbd },
    { 0x0406, 0xb2 }, { 0x0407, 0xaf }, { 0x0408, 0xa3 }, { 0x0409, 0x8a },
    { 0x040a, 0x8c }, { 0x040b, 0x8e }, { 0x040c, 0x8d }, { 0x040e, 0xa1 },
    { 0x040f, 0x8f }, { 0x0410, 0xc0 }, { 0x0411, 0xc1 }, { 0x0412, 0xc2 },
    { 0x0413, 0xc3 }, { 0x0414, 0xc4 }, { 0x0415, 0xc5 }, { 0x0416, 0xc6 },
    { 0x0417, 0xc7 }, { 0x0418, 0xc8 }, { 0x0419, 0xc9 }, { 0x041a, 0xca },
    { 0x041b, 0xcb }, { 0x041c, 0xcc }, { 0x041d, 0xcd }, { 0x041e, 0xce },
    { 0x041f, 0xcf }, { 0x0420, 0xd0 }, { 0x0421, 0xd1 }, { 0x0422, 0xd2 },
    { 0x0423, 0xd3 }, { 0x0424, 0xd4 }, { 0x0425, 0xd5 }, { 0x0426, 0xd6 },
    { 0x0427, 0xd7 }, { 0x0428, 0xd8 }, { 0x0429, 0xd9 }, { 0x042a, 0xda },
    { 0x042b, 0xdb }, { 0x042c, 0xdc }, { 0x042d, 0xdd }, { 0x042e, 0xde },
    { 0x042f, 0xdf }, { 0x0430, 0xe0 }, { 0x0431, 0xe1 }, { 0x0432, 0xe2 },
    { 0x0433, 0xe3 }, { 0x0434, 0xe4 }, { 0x0435, 0xe5 }, { 0x0436, 0xe6 },
    { 0x0437, 0xe7 }, { 0x0438, 0xe8 }, { 0x0439, 0xe9 }, { 0x043a, 0xea },
    { 0x043b, 0xeb }, { 0x043c, 0xec }, { 0x043d, 0xed }, { 0x043e, 0xee },
    { 0x043f, 0xef }, { 0x0440, 0xf0 }, { 0x0441, 0xf1 }, { 0x0442, 0xf2 },
    { 0x0443, 0xf3 }, { 0x0444, 0xf4 }, { 0x0445, 0xf5 }, { 0x0446, 0xf6 },
    { 0x0447, 0xf7 }, { 0x0448, 0xf8 }, { 0x0449, 0xf9 }, { 0x044a, 0xfa },
    { 0x044b, 0xfb }, { 0x044c, 0xfc }, { 0x044d, 0xfd }, { 0x044e, 0xfe },
    { 0x044f, 0xff }, { 0x0451, 0xb8 }, { 0x0452, 0x90 }, { 0x0453, 0x83 },
    { 0x0454, 0xba }, { 0x0455, 0xbe }, { 0x0456, 0xb3 }, { 0x0457, 0xbf },
    { 0x0458, 0xbc }, { 0x0459, 0x9a }, { 0x045a, 0x9c }, { 0x045b, 0x9e },
    { 0x045c, 0x9d }, { 0x045e, 0xa2 }, { 0x045f, 0x9f }, { 0x0490, 0xa5 },
    { 0x0491, 0xb4 }, { 0x2013, 0x96 }, { 0x2014, 0x97 }, { 0x2018, 0x91 },
    { 0x2019, 0x92 }, { 0x201a, 0x82 }, { 0x201c, 0x93 }, { 0x201d, 0x94 },
    { 0x201e, 0x84 }, { 0x2020, 0x86 }, { 0x2021, 0x87 }, { 0x2022, 0x95 },
    { 0x2026, 0x85 }, { 0x2029, 0x0a }, { 0x2030, 0x89 }, { 0x2039, 0x8b },
    { 0x203a, 0x9b },
#if defined(__ppc__) || defined(__POWERPC__)
    { 0x20ac, 0x88 }, { 0x2116, 0xb9 }
#else
    { 0x2116, 0xb9 }, { 0x2122, 0x99 }
#endif
};

static const NSNextStepMapping NSISOLatin2Mappings[] = {
    { 0x00a0, 0xa0 }, { 0x00a4, 0xa4 }, { 0x00a7, 0xa7 }, { 0x00a8, 0xa8 },
    { 0x00ad, 0xad }, { 0x00b0, 0xb0 }, { 0x00b4, 0xb4 }, { 0x00b8, 0xb8 },
    { 0x00c1, 0xc1 }, { 0x00c2, 0xc2 }, { 0x00c4, 0xc4 }, { 0x00c7, 0xc7 },
    { 0x00c9, 0xc9 }, { 0x00cb, 0xcb }, { 0x00cd, 0xcd }, { 0x00ce, 0xce },
    { 0x00d3, 0xd3 }, { 0x00d4, 0xd4 }, { 0x00d6, 0xd6 }, { 0x00d7, 0xd7 },
    { 0x00da, 0xda }, { 0x00dc, 0xdc }, { 0x00dd, 0xdd }, { 0x00df, 0xdf },
    { 0x00e1, 0xe1 }, { 0x00e2, 0xe2 }, { 0x00e4, 0xe4 }, { 0x00e7, 0xe7 },
    { 0x00e9, 0xe9 }, { 0x00eb, 0xeb }, { 0x00ed, 0xed }, { 0x00ee, 0xee },
    { 0x00f3, 0xf3 }, { 0x00f4, 0xf4 }, { 0x00f6, 0xf6 }, { 0x00f7, 0xf7 },
    { 0x00fa, 0xfa }, { 0x00fc, 0xfc }, { 0x00fd, 0xfd }, { 0x0102, 0xc3 },
    { 0x0103, 0xe3 }, { 0x0104, 0xa1 }, { 0x0105, 0xb1 }, { 0x0106, 0xc6 },
    { 0x0107, 0xe6 }, { 0x010c, 0xc8 }, { 0x010d, 0xe8 }, { 0x010e, 0xcf },
    { 0x010f, 0xef }, { 0x0110, 0xd0 }, { 0x0111, 0xf0 }, { 0x0118, 0xca },
    { 0x0119, 0xea }, { 0x011a, 0xcc }, { 0x011b, 0xec }, { 0x0139, 0xc5 },
    { 0x013a, 0xe5 }, { 0x013d, 0xa5 }, { 0x013e, 0xb5 }, { 0x0141, 0xa3 },
    { 0x0142, 0xb3 }, { 0x0143, 0xd1 }, { 0x0144, 0xf1 }, { 0x0147, 0xd2 },
    { 0x0148, 0xf2 }, { 0x0150, 0xd5 }, { 0x0151, 0xf5 }, { 0x0154, 0xc0 },
    { 0x0155, 0xe0 }, { 0x0158, 0xd8 }, { 0x0159, 0xf8 }, { 0x015a, 0xa6 },
    { 0x015b, 0xb6 }, { 0x015e, 0xaa }, { 0x015f, 0xba }, { 0x0160, 0xa9 },
    { 0x0161, 0xb9 }, { 0x0162, 0xde }, { 0x0163, 0xfe }, { 0x0164, 0xab },
    { 0x0165, 0xbb }, { 0x016e, 0xd9 }, { 0x016f, 0xf9 }, { 0x0170, 0xdb },
    { 0x0171, 0xfb }, { 0x0179, 0xac }, { 0x017a, 0xbc }, { 0x017b, 0xaf },
    { 0x017c, 0xbf }, { 0x017d, 0xae }, { 0x017e, 0xbe }, { 0x02c7, 0xb7 },
    { 0x02d8, 0xa2 }, { 0x02d9, 0xff }, { 0x02db, 0xb2 }, { 0x02dd, 0xbd },
    { 0x2029, 0x0a }
};

static const NSNextStepMapping NSSymbolMappings[] = {
    { 0x0020, 0x20 }, { 0x0021, 0x21 }, { 0x0023, 0x23 }, { 0x0025, 0x25 },
    { 0x0026, 0x26 }, { 0x0028, 0x28 }, { 0x0029, 0x29 }, { 0x002b, 0x2b },
    { 0x002c, 0x2c }, { 0x002e, 0x2e }, { 0x002f, 0x2f }, { 0x0030, 0x30 },
    { 0x0031, 0x31 }, { 0x0032, 0x32 }, { 0x0033, 0x33 }, { 0x0034, 0x34 },
    { 0x0035, 0x35 }, { 0x0036, 0x36 }, { 0x0037, 0x37 }, { 0x0038, 0x38 },
    { 0x0039, 0x39 }, { 0x003a, 0x3a }, { 0x003b, 0x3b }, { 0x003c, 0x3c },
    { 0x003d, 0x3d }, { 0x003e, 0x3e }, { 0x003f, 0x3f }, { 0x005b, 0x5b },
    { 0x005d, 0x5d }, { 0x005f, 0x5f }, { 0x007b, 0x7b }, { 0x007c, 0x7c },
    { 0x007d, 0x7d }, { 0x00a9, 0xe3 }, { 0x00ac, 0xd8 }, { 0x00ae, 0xe2 },
    { 0x00b0, 0xb0 }, { 0x00b1, 0xb1 }, { 0x00d7, 0xb4 }, { 0x00f7, 0xb8 },
    { 0x0192, 0xa6 }, { 0x0391, 0x41 }, { 0x0392, 0x42 }, { 0x0393, 0x47 },
    { 0x0394, 0x44 }, { 0x0395, 0x45 }, { 0x0396, 0x5a }, { 0x0397, 0x48 },
    { 0x0398, 0x51 }, { 0x0399, 0x49 }, { 0x039a, 0x4b }, { 0x039b, 0x4c },
    { 0x039c, 0x4d }, { 0x039d, 0x4e }, { 0x039e, 0x58 }, { 0x039f, 0x4f },
    { 0x03a0, 0x50 }, { 0x03a1, 0x52 }, { 0x03a3, 0x53 }, { 0x03a4, 0x54 },
    { 0x03a5, 0x55 }, { 0x03a6, 0x46 }, { 0x03a7, 0x43 }, { 0x03a8, 0x59 },
    { 0x03a9, 0x57 }, { 0x03b1, 0x61 }, { 0x03b2, 0x62 }, { 0x03b3, 0x67 },
    { 0x03b4, 0x64 }, { 0x03b5, 0x65 }, { 0x03b6, 0x7a }, { 0x03b7, 0x68 },
    { 0x03b8, 0x71 }, { 0x03b9, 0x69 }, { 0x03ba, 0x6b }, { 0x03bb, 0x6c },
    { 0x03bc, 0x6d }, { 0x03bd, 0x6e }, { 0x03be, 0x78 }, { 0x03bf, 0x6f },
    { 0x03c0, 0x70 }, { 0x03c1, 0x72 }, { 0x03c2, 0x56 }, { 0x03c3, 0x73 },
    { 0x03c4, 0x74 }, { 0x03c5, 0x75 }, { 0x03c6, 0x66 }, { 0x03c7, 0x63 },
    { 0x03c8, 0x79 }, { 0x03c9, 0x77 }, { 0x03d1, 0x4a }, { 0x03d2, 0xa1 },
    { 0x03d5, 0x6a }, { 0x03d6, 0x76 }, { 0x2022, 0xb7 }, { 0x2026, 0xbc },
    { 0x2029, 0x0a }, { 0x2032, 0xa2 }, { 0x2033, 0xb2 }, { 0x203e, 0x60 },
    { 0x2111, 0xc1 }, { 0x2118, 0xc3 }, { 0x211c, 0xc2 }, { 0x2122, 0xe4 },
    { 0x2135, 0xc0 }, { 0x2190, 0xac }, { 0x2191, 0xad }, { 0x2192, 0xae },
    { 0x2193, 0xaf }, { 0x2194, 0xab }, { 0x21b5, 0xbf }, { 0x21d0, 0xdc },
    { 0x21d1, 0xdd }, { 0x21d2, 0xde }, { 0x21d3, 0xdf }, { 0x21d4, 0xdb },
    { 0x2200, 0x22 }, { 0x2202, 0xb6 }, { 0x2203, 0x24 }, { 0x2205, 0xc6 },
    { 0x2207, 0xd1 }, { 0x2208, 0xce }, { 0x2209, 0xcf }, { 0x220b, 0x27 },
    { 0x220f, 0xd5 }, { 0x2211, 0xe5 }, { 0x2212, 0x2d }, { 0x2215, 0xa4 },
    { 0x2217, 0x2a }, { 0x221a, 0xd6 }, { 0x221d, 0xb5 }, { 0x221e, 0xa5 },
    { 0x2220, 0xd0 }, { 0x2227, 0xd9 }, { 0x2228, 0xda }, { 0x2229, 0xc7 },
    { 0x222a, 0xc8 }, { 0x222b, 0xf2 }, { 0x2234, 0x5c }, { 0x223c, 0x7e },
    { 0x2245, 0x40 }, { 0x2248, 0xbb }, { 0x2260, 0xb9 }, { 0x2261, 0xba },
    { 0x2264, 0xa3 }, { 0x2265, 0xb3 }, { 0x2282, 0xcc }, { 0x2283, 0xc9 },
    { 0x2284, 0xcb }, { 0x2286, 0xcd }, { 0x2287, 0xca }, { 0x2295, 0xc5 },
    { 0x2297, 0xc4 }, { 0x22a5, 0x5e }, { 0x22c5, 0xd7 }, { 0x2320, 0xf3 },
    { 0x2321, 0xf5 }, { 0x2329, 0xe1 }, { 0x232a, 0xf1 }, { 0x25ca, 0xe0 },
    { 0x2660, 0xaa }, { 0x2663, 0xa7 }, { 0x2665, 0xa9 }, { 0x2666, 0xa8 }
};

static const NSNextStepMapping NSAdobeStandardMappings[] = {
    { 0x00a1, 0xa1 }, { 0x00a2, 0xa2 }, { 0x00a3, 0xa3 }, { 0x00a4, 0xa8 },
    { 0x00a5, 0xa5 }, { 0x00a7, 0xa7 }, { 0x00a8, 0xc8 }, { 0x00aa, 0xe3 },
    { 0x00ab, 0xab }, { 0x00af, 0xc5 }, { 0x00b4, 0xc2 }, { 0x00b6, 0xb6 },
    { 0x00b7, 0xb4 }, { 0x00b8, 0xcb }, { 0x00ba, 0xeb }, { 0x00bb, 0xbb },
    { 0x00bf, 0xbf }, { 0x00c6, 0xe1 }, { 0x00d8, 0xe9 }, { 0x00df, 0xfb },
    { 0x00e6, 0xf1 }, { 0x00f8, 0xf9 }, { 0x0131, 0xf5 }, { 0x0141, 0xe8 },
    { 0x0142, 0xf8 }, { 0x0152, 0xea }, { 0x0153, 0xfa }, { 0x0192, 0xa6 },
    { 0x02c6, 0xc3 }, { 0x02c7, 0xcf }, { 0x02cb, 0xc1 }, { 0x02d8, 0xc6 },
    { 0x02d9, 0xc7 }, { 0x02da, 0xca }, { 0x02db, 0xce }, { 0x02dc, 0xc4 },
    { 0x02dd, 0xcd }, { 0x2013, 0xb1 }, { 0x2014, 0xd0 }, { 0x2019, 0xa9 },
    { 0x201a, 0xb8 }, { 0x201c, 0xaa }, { 0x201d, 0xba }, { 0x201e, 0xb9 },
    { 0x2020, 0xb2 }, { 0x2021, 0xb3 }, { 0x2022, 0xb7 }, { 0x2026, 0xbc },
    { 0x2029, 0x0a }, { 0x2030, 0xbd }, { 0x2039, 0xac }, { 0x203a, 0xad },
    { 0x2044, 0xa4 }, { 0xfb01, 0xae }, { 0xfb02, 0xaf }
};

static const NSNextStepMapping NSDingbatMappings[] = {
    { 0x2029, 0x0a }, { 0x2192, 0xd5 }, { 0x2194, 0xd6 }, { 0x2195, 0xd7 },
    { 0x2460, 0xac }, { 0x2461, 0xad }, { 0x2462, 0xae }, { 0x2463, 0xaf },
    { 0x2464, 0xb0 }, { 0x2465, 0xb1 }, { 0x2466, 0xb2 }, { 0x2467, 0xb3 },
    { 0x2468, 0xb4 }, { 0x2469, 0xb5 }, { 0x25a0, 0x6e }, { 0x25b2, 0x73 },
    { 0x25bc, 0x74 }, { 0x25c6, 0x75 }, { 0x25cf, 0x6c }, { 0x25d7, 0x77 },
    { 0x2605, 0x48 }, { 0x260e, 0x25 }, { 0x261b, 0x2a }, { 0x261e, 0x2b },
    { 0x2660, 0xab }, { 0x2663, 0xa8 }, { 0x2665, 0xaa }, { 0x2666, 0xa9 },
    { 0x2701, 0x21 }, { 0x2702, 0x22 }, { 0x2703, 0x23 }, { 0x2704, 0x24 },
    { 0x2706, 0x26 }, { 0x2707, 0x27 }, { 0x2708, 0x28 }, { 0x2709, 0x29 },
    { 0x270c, 0x2c }, { 0x270d, 0x2d }, { 0x270e, 0x2e }, { 0x270f, 0x2f },
    { 0x2710, 0x30 }, { 0x2711, 0x31 }, { 0x2712, 0x32 }, { 0x2713, 0x33 },
    { 0x2714, 0x34 }, { 0x2715, 0x35 }, { 0x2716, 0x36 }, { 0x2717, 0x37 },
    { 0x2718, 0x38 }, { 0x2719, 0x39 }, { 0x271a, 0x3a }, { 0x271b, 0x3b },
    { 0x271c, 0x3c }, { 0x271d, 0x3d }, { 0x271e, 0x3e }, { 0x271f, 0x3f },
    { 0x2720, 0x40 }, { 0x2721, 0x41 }, { 0x2722, 0x42 }, { 0x2723, 0x43 },
    { 0x2724, 0x44 }, { 0x2725, 0x45 }, { 0x2726, 0x46 }, { 0x2727, 0x47 },
    { 0x2729, 0x49 }, { 0x272a, 0x4a }, { 0x272b, 0x4b }, { 0x272c, 0x4c },
    { 0x272d, 0x4d }, { 0x272e, 0x4e }, { 0x272f, 0x4f }, { 0x2730, 0x50 },
    { 0x2731, 0x51 }, { 0x2732, 0x52 }, { 0x2733, 0x53 }, { 0x2734, 0x54 },
    { 0x2735, 0x55 }, { 0x2736, 0x56 }, { 0x2737, 0x57 }, { 0x2738, 0x58 },
    { 0x2739, 0x59 }, { 0x273a, 0x5a }, { 0x273b, 0x5b }, { 0x273c, 0x5c },
    { 0x273d, 0x5d }, { 0x273e, 0x5e }, { 0x273f, 0x5f }, { 0x2740, 0x60 },
    { 0x2741, 0x61 }, { 0x2742, 0x62 }, { 0x2743, 0x63 }, { 0x2744, 0x64 },
    { 0x2745, 0x65 }, { 0x2746, 0x66 }, { 0x2747, 0x67 }, { 0x2748, 0x68 },
    { 0x2749, 0x69 }, { 0x274a, 0x6a }, { 0x274b, 0x6b }, { 0x274d, 0x6d },
    { 0x274f, 0x6f }, { 0x2750, 0x70 }, { 0x2751, 0x71 }, { 0x2752, 0x72 },
    { 0x2756, 0x76 }, { 0x2758, 0x78 }, { 0x2759, 0x79 }, { 0x275a, 0x7a },
    { 0x275b, 0x7b }, { 0x275c, 0x7c }, { 0x275d, 0x7d }, { 0x275e, 0x7e },
    { 0x2761, 0xa1 }, { 0x2762, 0xa2 }, { 0x2763, 0xa3 }, { 0x2764, 0xa4 },
    { 0x2765, 0xa5 }, { 0x2766, 0xa6 }, { 0x2767, 0xa7 }, { 0x2776, 0xb6 },
    { 0x2777, 0xb7 }, { 0x2778, 0xb8 }, { 0x2779, 0xb9 }, { 0x277a, 0xba },
    { 0x277b, 0xbb }, { 0x277c, 0xbc }, { 0x277d, 0xbd }, { 0x277e, 0xbe },
    { 0x277f, 0xbf }, { 0x2780, 0xc0 }, { 0x2781, 0xc1 }, { 0x2782, 0xc2 },
    { 0x2783, 0xc3 }, { 0x2784, 0xc4 }, { 0x2785, 0xc5 }, { 0x2786, 0xc6 },
    { 0x2787, 0xc7 }, { 0x2788, 0xc8 }, { 0x2789, 0xc9 }, { 0x278a, 0xca },
    { 0x278b, 0xcb }, { 0x278c, 0xcc }, { 0x278d, 0xcd }, { 0x278e, 0xce },
    { 0x278f, 0xcf }, { 0x2790, 0xd0 }, { 0x2791, 0xd1 }, { 0x2792, 0xd2 },
    { 0x2793, 0xd3 }, { 0x2794, 0xd4 }, { 0x2798, 0xd8 }, { 0x2799, 0xd9 },
    { 0x279a, 0xda }, { 0x279b, 0xdb }, { 0x279c, 0xdc }, { 0x279d, 0xdd },
    { 0x279e, 0xde }, { 0x279f, 0xdf }, { 0x27a0, 0xe0 }, { 0x27a1, 0xe1 },
    { 0x27a2, 0xe2 }, { 0x27a3, 0xe3 }, { 0x27a4, 0xe4 }, { 0x27a5, 0xe5 },
    { 0x27a6, 0xe6 }, { 0x27a7, 0xe7 }, { 0x27a8, 0xe8 }, { 0x27a9, 0xe9 },
    { 0x27aa, 0xea }, { 0x27ab, 0xeb }, { 0x27ac, 0xec }, { 0x27ad, 0xed },
    { 0x27ae, 0xee }, { 0x27af, 0xef }, { 0x27b1, 0xf1 }, { 0x27b2, 0xf2 },
    { 0x27b3, 0xf3 }, { 0x27b4, 0xf4 }, { 0x27b5, 0xf5 }, { 0x27b6, 0xf6 },
    { 0x27b7, 0xf7 }, { 0x27b8, 0xf8 }, { 0x27b9, 0xf9 }, { 0x27ba, 0xfa },
    { 0x27bb, 0xfb }, { 0x27bc, 0xfc }, { 0x27bd, 0xfd }, { 0x27be, 0xfe }
};

static const NSNextStepMapping NSWin1250Mappings[] = {
    { 0x00a0, 0xa0 }, { 0x00a4, 0xa4 }, { 0x00a6, 0xa6 }, { 0x00a7, 0xa7 },
    { 0x00a8, 0xa8 }, { 0x00a9, 0xa9 }, { 0x00ab, 0xab }, { 0x00ac, 0xac },
    { 0x00ad, 0xad }, { 0x00ae, 0xae }, { 0x00b0, 0xb0 }, { 0x00b1, 0xb1 },
    { 0x00b4, 0xb4 }, { 0x00b5, 0xb5 }, { 0x00b6, 0xb6 }, { 0x00b7, 0xb7 },
    { 0x00b8, 0xb8 }, { 0x00bb, 0xbb }, { 0x00c1, 0xc1 }, { 0x00c2, 0xc2 },
    { 0x00c4, 0xc4 }, { 0x00c7, 0xc7 }, { 0x00c9, 0xc9 }, { 0x00cb, 0xcb },
    { 0x00cd, 0xcd }, { 0x00ce, 0xce }, { 0x00d3, 0xd3 }, { 0x00d4, 0xd4 },
    { 0x00d6, 0xd6 }, { 0x00d7, 0xd7 }, { 0x00da, 0xda }, { 0x00dc, 0xdc },
    { 0x00dd, 0xdd }, { 0x00df, 0xdf }, { 0x00e1, 0xe1 }, { 0x00e2, 0xe2 },
    { 0x00e4, 0xe4 }, { 0x00e7, 0xe7 }, { 0x00e9, 0xe9 }, { 0x00eb, 0xeb },
    { 0x00ed, 0xed }, { 0x00ee, 0xee }, { 0x00f3, 0xf3 }, { 0x00f4, 0xf4 },
    { 0x00f6, 0xf6 }, { 0x00f7, 0xf7 }, { 0x00fa, 0xfa }, { 0x00fc, 0xfc },
    { 0x00fd, 0xfd }, { 0x0102, 0xc3 }, { 0x0103, 0xe3 }, { 0x0104, 0xa5 },
    { 0x0105, 0xb9 }, { 0x0106, 0xc6 }, { 0x0107, 0xe6 }, { 0x010c, 0xc8 },
    { 0x010d, 0xe8 }, { 0x010e, 0xcf }, { 0x010f, 0xef }, { 0x0110, 0xd0 },
    { 0x0111, 0xf0 }, { 0x0118, 0xca }, { 0x0119, 0xea }, { 0x011a, 0xcc },
    { 0x011b, 0xec }, { 0x0139, 0xc5 }, { 0x013a, 0xe5 }, { 0x013d, 0xbc },
    { 0x013e, 0xbe }, { 0x0141, 0xa3 }, { 0x0142, 0xb3 }, { 0x0143, 0xd1 },
    { 0x0144, 0xf1 }, { 0x0147, 0xd2 }, { 0x0148, 0xf2 }, { 0x0150, 0xd5 },
    { 0x0151, 0xf5 }, { 0x0154, 0xc0 }, { 0x0155, 0xe0 }, { 0x0158, 0xd8 },
    { 0x0159, 0xf8 }, { 0x015a, 0x8c }, { 0x015b, 0x9c }, { 0x015e, 0xaa },
    { 0x015f, 0xba }, { 0x0160, 0x8a }, { 0x0161, 0x9a }, { 0x0162, 0xde },
    { 0x0163, 0xfe }, { 0x0164, 0x8d }, { 0x0165, 0x9d }, { 0x016e, 0xd9 },
    { 0x016f, 0xf9 }, { 0x0170, 0xdb }, { 0x0171, 0xfb }, { 0x0179, 0x8f },
    { 0x017a, 0x9f }, { 0x017b, 0xaf }, { 0x017c, 0xbf }, { 0x017d, 0x8e },
    { 0x017e, 0x9e }, { 0x02c7, 0xa1 }, { 0x02d8, 0xa2 }, { 0x02d9, 0xff },
    { 0x02db, 0xb2 }, { 0x02dd, 0xbd }, { 0x2013, 0x96 }, { 0x2014, 0x97 },
    { 0x2018, 0x91 }, { 0x2019, 0x92 }, { 0x201a, 0x82 }, { 0x201c, 0x93 },
    { 0x201d, 0x94 }, { 0x201e, 0x84 }, { 0x2020, 0x86 }, { 0x2021, 0x87 },
    { 0x2022, 0x95 }, { 0x2026, 0x85 }, { 0x2029, 0x0a }, { 0x2030, 0x89 },
    { 0x2039, 0x8b }, { 0x203a, 0x9b },
#if defined(__ppc__) || defined(__POWERPC__)
    { 0x20ac, 0x80 }
#else
    { 0x2122, 0x99 }
#endif
};

static const NSNextStepMapping NSWin1253Mappings[] = {
    { 0x00a0, 0xa0 }, { 0x00a3, 0xa3 }, { 0x00a4, 0xa4 }, { 0x00a5, 0xa5 },
    { 0x00a6, 0xa6 }, { 0x00a7, 0xa7 }, { 0x00a8, 0xa8 }, { 0x00a9, 0xa9 },
    { 0x00ab, 0xab }, { 0x00ac, 0xac }, { 0x00ad, 0xad }, { 0x00ae, 0xae },
    { 0x00b0, 0xb0 }, { 0x00b1, 0xb1 }, { 0x00b2, 0xb2 }, { 0x00b3, 0xb3 },
    { 0x00b5, 0xb5 }, { 0x00b6, 0xb6 }, { 0x00b7, 0xb7 }, { 0x00bb, 0xbb },
    { 0x00bd, 0xbd }, { 0x0192, 0x83 }, { 0x0384, 0xb4 }, { 0x0385, 0xa1 },
    { 0x0386, 0xa2 }, { 0x0388, 0xb8 }, { 0x0389, 0xb9 }, { 0x038a, 0xba },
    { 0x038c, 0xbc }, { 0x038e, 0xbe }, { 0x038f, 0xbf }, { 0x0390, 0xc0 },
    { 0x0391, 0xc1 }, { 0x0392, 0xc2 }, { 0x0393, 0xc3 }, { 0x0394, 0xc4 },
    { 0x0395, 0xc5 }, { 0x0396, 0xc6 }, { 0x0397, 0xc7 }, { 0x0398, 0xc8 },
    { 0x0399, 0xc9 }, { 0x039a, 0xca }, { 0x039b, 0xcb }, { 0x039c, 0xcc },
    { 0x039d, 0xcd }, { 0x039e, 0xce }, { 0x039f, 0xcf }, { 0x03a0, 0xd0 },
    { 0x03a1, 0xd1 }, { 0x03a3, 0xd3 }, { 0x03a4, 0xd4 }, { 0x03a5, 0xd5 },
    { 0x03a6, 0xd6 }, { 0x03a7, 0xd7 }, { 0x03a8, 0xd8 }, { 0x03a9, 0xd9 },
    { 0x03aa, 0xda }, { 0x03ab, 0xdb }, { 0x03ac, 0xdc }, { 0x03ad, 0xdd },
    { 0x03ae, 0xde }, { 0x03af, 0xdf }, { 0x03b0, 0xe0 }, { 0x03b1, 0xe1 },
    { 0x03b2, 0xe2 }, { 0x03b3, 0xe3 }, { 0x03b4, 0xe4 }, { 0x03b5, 0xe5 },
    { 0x03b6, 0xe6 }, { 0x03b7, 0xe7 }, { 0x03b8, 0xe8 }, { 0x03b9, 0xe9 },
    { 0x03ba, 0xea }, { 0x03bb, 0xeb }, { 0x03bc, 0xec }, { 0x03bd, 0xed },
    { 0x03be, 0xee }, { 0x03bf, 0xef }, { 0x03c0, 0xf0 }, { 0x03c1, 0xf1 },
    { 0x03c2, 0xf2 }, { 0x03c3, 0xf3 }, { 0x03c4, 0xf4 }, { 0x03c5, 0xf5 },
    { 0x03c6, 0xf6 }, { 0x03c7, 0xf7 }, { 0x03c8, 0xf8 }, { 0x03c9, 0xf9 },
    { 0x03ca, 0xfa }, { 0x03cb, 0xfb }, { 0x03cc, 0xfc }, { 0x03cd, 0xfd },
    { 0x03ce, 0xfe }, { 0x2013, 0x96 }, { 0x2014, 0x97 }, { 0x2015, 0xaf },
    { 0x2018, 0x91 }, { 0x2019, 0x92 }, { 0x201a, 0x82 }, { 0x201c, 0x93 },
    { 0x201d, 0x94 }, { 0x201e, 0x84 }, { 0x2020, 0x86 }, { 0x2021, 0x87 },
    { 0x2022, 0x95 }, { 0x2026, 0x85 }, { 0x2029, 0x0a }, { 0x2030, 0x89 },
    { 0x2039, 0x8b }, { 0x203a, 0x9b },
#if defined(__ppc__) || defined(__POWERPC__)
    { 0x20ac, 0x80 },
#endif
    { 0x2122, 0x99 }, { 0xf8f9, 0xaa }, { 0xf8fa, 0xd2 },
#if !defined(__ppc__) && !defined(__POWERPC__)
    { 0xf8fb, 0xff }
#endif
};

static const NSNextStepMapping NSWin1254Mappings[] = {
    { 0x00a0, 0xa0 }, { 0x00a1, 0xa1 }, { 0x00a2, 0xa2 }, { 0x00a3, 0xa3 },
    { 0x00a4, 0xa4 }, { 0x00a5, 0xa5 }, { 0x00a6, 0xa6 }, { 0x00a7, 0xa7 },
    { 0x00a8, 0xa8 }, { 0x00a9, 0xa9 }, { 0x00aa, 0xaa }, { 0x00ab, 0xab },
    { 0x00ac, 0xac }, { 0x00ad, 0xad }, { 0x00ae, 0xae }, { 0x00af, 0xaf },
    { 0x00b0, 0xb0 }, { 0x00b1, 0xb1 }, { 0x00b2, 0xb2 }, { 0x00b3, 0xb3 },
    { 0x00b4, 0xb4 }, { 0x00b5, 0xb5 }, { 0x00b6, 0xb6 }, { 0x00b7, 0xb7 },
    { 0x00b8, 0xb8 }, { 0x00b9, 0xb9 }, { 0x00ba, 0xba }, { 0x00bb, 0xbb },
    { 0x00bc, 0xbc }, { 0x00bd, 0xbd }, { 0x00be, 0xbe }, { 0x00bf, 0xbf },
    { 0x00c0, 0xc0 }, { 0x00c1, 0xc1 }, { 0x00c2, 0xc2 }, { 0x00c3, 0xc3 },
    { 0x00c4, 0xc4 }, { 0x00c5, 0xc5 }, { 0x00c6, 0xc6 }, { 0x00c7, 0xc7 },
    { 0x00c8, 0xc8 }, { 0x00c9, 0xc9 }, { 0x00ca, 0xca }, { 0x00cb, 0xcb },
    { 0x00cc, 0xcc }, { 0x00cd, 0xcd }, { 0x00ce, 0xce }, { 0x00cf, 0xcf },
    { 0x00d1, 0xd1 }, { 0x00d2, 0xd2 }, { 0x00d3, 0xd3 }, { 0x00d4, 0xd4 },
    { 0x00d5, 0xd5 }, { 0x00d6, 0xd6 }, { 0x00d7, 0xd7 }, { 0x00d8, 0xd8 },
    { 0x00d9, 0xd9 }, { 0x00da, 0xda }, { 0x00db, 0xdb }, { 0x00dc, 0xdc },
    { 0x00df, 0xdf }, { 0x00e0, 0xe0 }, { 0x00e1, 0xe1 }, { 0x00e2, 0xe2 },
    { 0x00e3, 0xe3 }, { 0x00e4, 0xe4 }, { 0x00e5, 0xe5 }, { 0x00e6, 0xe6 },
    { 0x00e7, 0xe7 }, { 0x00e8, 0xe8 }, { 0x00e9, 0xe9 }, { 0x00ea, 0xea },
    { 0x00eb, 0xeb }, { 0x00ec, 0xec }, { 0x00ed, 0xed }, { 0x00ee, 0xee },
    { 0x00ef, 0xef }, { 0x00f1, 0xf1 }, { 0x00f2, 0xf2 }, { 0x00f3, 0xf3 },
    { 0x00f4, 0xf4 }, { 0x00f5, 0xf5 }, { 0x00f6, 0xf6 }, { 0x00f7, 0xf7 },
    { 0x00f8, 0xf8 }, { 0x00f9, 0xf9 }, { 0x00fa, 0xfa }, { 0x00fb, 0xfb },
    { 0x00fc, 0xfc }, { 0x00ff, 0xff }, { 0x011e, 0xd0 }, { 0x011f, 0xf0 },
    { 0x0130, 0xdd }, { 0x0131, 0xfd }, { 0x0152, 0x8c }, { 0x0153, 0x9c },
    { 0x015e, 0xde }, { 0x015f, 0xfe }, { 0x0160, 0x8a }, { 0x0161, 0x9a },
    { 0x0178, 0x9f }, { 0x0192, 0x83 }, { 0x02c6, 0x88 }, { 0x02dc, 0x98 },
    { 0x2013, 0x96 }, { 0x2014, 0x97 }, { 0x2018, 0x91 }, { 0x2019, 0x92 },
    { 0x201a, 0x82 }, { 0x201c, 0x93 }, { 0x201d, 0x94 }, { 0x201e, 0x84 },
    { 0x2020, 0x86 }, { 0x2021, 0x87 }, { 0x2022, 0x95 }, { 0x2026, 0x85 },
    { 0x2029, 0x0a }, { 0x2030, 0x89 }, { 0x2039, 0x8b }, { 0x203a, 0x9b },
#if defined(__ppc__) || defined(__POWERPC__)
    { 0x20ac, 0x80 }
#else
    { 0x2122, 0x99 }
#endif
};

static const NSNextStepMapping NSWinLatin1Mappings[] = {
    { 0x0152, 0x8c }, { 0x0153, 0x9c }, { 0x0160, 0x8a }, { 0x0161, 0x9a },
    { 0x0178, 0x9f }, { 0x0192, 0x83 }, { 0x02c6, 0x88 }, { 0x02dc, 0x98 },
    { 0x2013, 0x96 }, { 0x2014, 0x97 }, { 0x2018, 0x91 }, { 0x2019, 0x92 },
    { 0x201a, 0x82 }, { 0x201c, 0x93 }, { 0x201d, 0x94 }, { 0x201e, 0x84 },
    { 0x2020, 0x86 }, { 0x2021, 0x87 }, { 0x2022, 0x95 }, { 0x2026, 0x85 },
    { 0x2029, 0x0a }, { 0x2030, 0x89 }, { 0x2039, 0x8b }, { 0x203a, 0x9b },
#if defined(__ppc__) || defined(__POWERPC__)
    { 0x20ac, 0x80 }
#else
    { 0x2122, 0x99 }
#endif
};

static const NSNextStepMapping NSMacRomanMappings[] = {
    { 0x00a0, 0xca }, { 0x00a1, 0xc1 }, { 0x00a2, 0xa2 }, { 0x00a3, 0xa3 },
    { 0x00a4, 0xdb }, { 0x00a5, 0xb4 }, { 0x00a7, 0xa4 }, { 0x00a8, 0xac },
    { 0x00a9, 0xa9 }, { 0x00aa, 0xbb }, { 0x00ab, 0xc7 }, { 0x00ac, 0xc2 },
    { 0x00ae, 0xa8 }, { 0x00af, 0xf8 }, { 0x00b0, 0xa1 }, { 0x00b1, 0xb1 },
    { 0x00b4, 0xab }, { 0x00b5, 0xb5 }, { 0x00b6, 0xa6 }, { 0x00b7, 0xe1 },
    { 0x00b8, 0xfc }, { 0x00ba, 0xbc }, { 0x00bb, 0xc8 }, { 0x00bf, 0xc0 },
    { 0x00c0, 0xcb }, { 0x00c1, 0xe7 }, { 0x00c2, 0xe5 }, { 0x00c3, 0xcc },
    { 0x00c4, 0x80 }, { 0x00c5, 0x81 }, { 0x00c6, 0xae }, { 0x00c7, 0x82 },
    { 0x00c8, 0xe9 }, { 0x00c9, 0x83 }, { 0x00ca, 0xe6 }, { 0x00cb, 0xe8 },
    { 0x00cc, 0xed }, { 0x00cd, 0xea }, { 0x00ce, 0xeb }, { 0x00cf, 0xec },
    { 0x00d1, 0x84 }, { 0x00d2, 0xf1 }, { 0x00d3, 0xee }, { 0x00d4, 0xef },
    { 0x00d5, 0xcd }, { 0x00d6, 0x85 }, { 0x00d8, 0xaf }, { 0x00d9, 0xf4 },
    { 0x00da, 0xf2 }, { 0x00db, 0xf3 }, { 0x00dc, 0x86 }, { 0x00df, 0xa7 },
    { 0x00e0, 0x88 }, { 0x00e1, 0x87 }, { 0x00e2, 0x89 }, { 0x00e3, 0x8b },
    { 0x00e4, 0x8a }, { 0x00e5, 0x8c }, { 0x00e6, 0xbe }, { 0x00e7, 0x8d },
    { 0x00e8, 0x8f }, { 0x00e9, 0x8e }, { 0x00ea, 0x90 }, { 0x00eb, 0x91 },
    { 0x00ec, 0x93 }, { 0x00ed, 0x92 }, { 0x00ee, 0x94 }, { 0x00ef, 0x95 },
    { 0x00f1, 0x96 }, { 0x00f2, 0x98 }, { 0x00f3, 0x97 }, { 0x00f4, 0x99 },
    { 0x00f5, 0x9b }, { 0x00f6, 0x9a }, { 0x00f7, 0xd6 }, { 0x00f8, 0xbf },
    { 0x00f9, 0x9d }, { 0x00fa, 0x9c }, { 0x00fb, 0x9e }, { 0x00fc, 0x9f },
    { 0x00ff, 0xd8 }, { 0x0131, 0xf5 }, { 0x0152, 0xce }, { 0x0153, 0xcf },
    { 0x0178, 0xd9 }, { 0x0192, 0xc4 }, { 0x02c6, 0xf6 }, { 0x02c7, 0xff },
    { 0x02d8, 0xf9 }, { 0x02d9, 0xfa }, { 0x02da, 0xfb }, { 0x02db, 0xfe },
    { 0x02dc, 0xf7 }, { 0x02dd, 0xfd }, { 0x03c0, 0xb9 }, { 0x2013, 0xd0 },
    { 0x2014, 0xd1 }, { 0x2018, 0xd4 }, { 0x2019, 0xd5 }, { 0x201a, 0xe2 },
    { 0x201c, 0xd2 }, { 0x201d, 0xd3 }, { 0x201e, 0xe3 }, { 0x2020, 0xa0 },
    { 0x2021, 0xe0 }, { 0x2022, 0xa5 }, { 0x2026, 0xc9 }, { 0x2030, 0xe4 },
    { 0x2039, 0xdc }, { 0x203a, 0xdd }, { 0x2044, 0xda }, { 0x2122, 0xaa },
    { 0x2126, 0xbd }, { 0x2202, 0xb6 }, { 0x2206, 0xc6 }, { 0x220f, 0xb8 },
    { 0x2211, 0xb7 }, { 0x221a, 0xc3 }, { 0x221e, 0xb0 }, { 0x222b, 0xba },
    { 0x2248, 0xc5 }, { 0x2260, 0xad }, { 0x2264, 0xb2 }, { 0x2265, 0xb3 },
    { 0x25ca, 0xd7 }, { 0xf8ff, 0xf0 }, { 0xfb01, 0xde }, { 0xfb02, 0xdf }
};

static int _NSConvertToLowerCase(unichar character, unichar *result);
static int _NSConvertToTitleCase(unichar character, unichar *result);
static int _NSConvertToUpperCase(unichar character, unichar *result);

static unsigned short *_NSCaseTableStart;
static unsigned short *_NSToLowerTable;
static unsigned short *_NSToUpperTable;
static unsigned short *_NSToTitleTable;
static unsigned _NSLowerTableCount;
static unsigned _NSUpperTableCount;
static unsigned _NSTitleTableCount;
static id _hasNonSelfLower;
static id _hasNonSelfUpper;
static id _hasNonSelfTitle;

char
_NSFoundationResourceCPath(char *path)
{
    static const char resourcePath[] = "/System/Library/Frameworks/Foundation.framework/Resources";
    const char *source = resourcePath;

    while ((*path++ = *source++) != '\0')
        ;
    return '\0';
}

static id
NSLoadNonSelfCaseMappingSet(NSString *name)
{
    char path[1024];
    char *tail;
    static const char directory[] = "/CharacterSets";
    const char *source;
    NSString *resourcePath;

    _NSFoundationResourceCPath(path);
    tail = path;
    while (*tail != '\0')
        ++tail;
    source = directory;
    while ((*tail++ = *source++) != '\0')
        ;
    resourcePath = [NSString stringWithCString:path length:(unsigned)strlen(path)];
    return [[NSCharacterSet characterSetWithContentsOfFile:
        [resourcePath stringByAppendingPathComponent:name]] retain];
}

int
_NSReadBytesFromFile(char *path, void **bytes, unsigned *length, NSZone *zone
#if defined(__ppc__) || defined(__POWERPC__)
                     , char allocatePages
#endif
                     )
{
    struct stat status;
    int descriptor;
    int savedError;

    *bytes = NULL;
    descriptor = open(path, O_RDONLY, 0666);
    if (descriptor < 0)
        return 0;

    if (fstat(descriptor, &status) < 0) {
        savedError = cthread_errno();
        close(descriptor);
        cthread_set_errno_self(savedError);
        errno = savedError;
        return 0;
    }

    if (!S_ISREG(status.st_mode)) {
        close(descriptor);
        cthread_set_errno_self(EACCES);
        errno = EACCES;
        return 0;
    }

    if (status.st_size == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        if (allocatePages)
            *bytes = NSAllocateMemoryPages(4);
        else
            *bytes = NSZoneMalloc(NULL, 4);
        *length = 0;
#else
        static char emptyFile;
        *bytes = &emptyFile;
        *length = 0;
#endif
        close(descriptor);
        return 1;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (allocatePages)
        *bytes = NSAllocateMemoryPages((unsigned)status.st_size);
    else
        *bytes = NSZoneMalloc(zone, (unsigned)status.st_size);
#else
    *bytes = NSZoneMalloc(zone, (unsigned)status.st_size);
#endif
    if (read(descriptor, *bytes, status.st_size) < 0) {
        savedError = cthread_errno();
#if defined(__ppc__) || defined(__POWERPC__)
        if (allocatePages)
            NSDeallocateMemoryPages(*bytes, (unsigned)status.st_size);
        else
            NSZoneFree(zone, *bytes);
#else
        NSZoneFree(zone, *bytes);
#endif
        close(descriptor);
        cthread_set_errno_self(savedError);
        errno = savedError;
        *bytes = NULL;
        return 0;
    }
    *length = (unsigned)status.st_size;
    close(descriptor);
    return 1;
}

unsigned
_loadConvTable(unsigned short **table, const char *name)
{
    char path[1024];
    char *tail;
    char *suffixStart;
    void *bytes;
    unsigned length;
    const char *suffix;

    _NSFoundationResourceCPath(path);
    tail = path;
    while (*tail != '\0')
        ++tail;
    {
        static const char directory[] = "/CharacterSets/";
        const char *source = directory;
        while ((*tail++ = *source++) != '\0')
            ;
        --tail;
    }
    while ((*tail++ = *name++) != '\0')
        ;
    --tail;
#if defined(__ppc__) || defined(__POWERPC__) || defined(__BIG_ENDIAN__)
    suffix = "-B.data";
#else
    suffix = "-L.data";
#endif
    suffixStart = tail;
    while ((*tail++ = *suffix++) != '\0')
        ;

#if defined(__ppc__) || defined(__POWERPC__)
    if (!_NSReadBytesFromFile(path, &bytes, &length, 0, 0)) {
#else
    if (!_NSReadBytesFromFile(path, &bytes, &length, 0)) {
#endif
        *suffixStart = '\0';
#if defined(__ppc__) || defined(__POWERPC__)
        if (!_NSReadBytesFromFile(path, &bytes, &length, 0, 0))
#else
        if (!_NSReadBytesFromFile(path, &bytes, &length, 0))
#endif
            return 0;
    }

    *table = (unsigned short *)bytes;
    return length >> 2;
}

static void
_NSLoadCaseConversionTables(void)
{
    unsigned tableLength;

    if (_NSCaseTableStart != 0)
        return;
    tableLength = _loadConvTable(&_NSCaseTableStart, "CaseMapping");
    if (tableLength == 0 || _NSCaseTableStart == 0 || tableLength < 2)
        return;

    _NSLowerTableCount = _NSCaseTableStart[1];
    _NSUpperTableCount = _NSCaseTableStart[2];
    _NSTitleTableCount = _NSCaseTableStart[3];
    _NSToLowerTable = _NSCaseTableStart + 4;
    _NSToUpperTable = _NSToLowerTable + 2 * _NSLowerTableCount;
    _NSToTitleTable = _NSToUpperTable + 2 * _NSUpperTableCount;
    _hasNonSelfLower = NSLoadNonSelfCaseMappingSet(
        @"hasNonSelfLowercaseMapping.bitmap");
    _hasNonSelfUpper = NSLoadNonSelfCaseMappingSet(
        @"hasNonSelfUppercaseMapping.bitmap");
    _hasNonSelfTitle = NSLoadNonSelfCaseMappingSet(
        @"hasNonSelfTitlecaseMapping.bitmap");
}

unsigned short
NS16To16BitEncoding(unsigned short *table, unsigned count, unichar character)
{
    unsigned first = 0;
    unsigned last = count;

    while (first < last) {
        unsigned middle = first + (last - first) / 2;
        unsigned short key = table[middle * 2];

        if (character < key) {
            last = middle;
        } else if (character > key) {
            first = middle + 1;
        } else {
            return table[middle * 2 + 1];
        }
    }
    return 0;
}

static int
_NSConvertToLowerCase(unichar character, unichar *result)
{
    unsigned short mapped;

    if (_NSToLowerTable == 0)
        _NSLoadCaseConversionTables();
    mapped = _hasNonSelfLower == nil ||
        ![_hasNonSelfLower characterIsMember:character] || _NSToLowerTable == 0 ? 0 :
        NS16To16BitEncoding(_NSToLowerTable, _NSLowerTableCount, character);
    *result = mapped == 0 ? character : mapped;
    return 1;
}

static int
_NSConvertToTitleCase(unichar character, unichar *result)
{
    unsigned short mapped;

    if (_NSToTitleTable == 0)
        _NSLoadCaseConversionTables();
    mapped = _hasNonSelfTitle == nil ||
        ![_hasNonSelfTitle characterIsMember:character] || _NSToTitleTable == 0 ? 0 :
        NS16To16BitEncoding(_NSToTitleTable, _NSTitleTableCount, character);
    *result = mapped == 0 ? character : mapped;
    return 1;
}

static int
_NSConvertToUpperCase(unichar character, unichar *result)
{
    unsigned short mapped;

    if (_NSToUpperTable == 0)
        _NSLoadCaseConversionTables();
    mapped = _hasNonSelfUpper == nil ||
        ![_hasNonSelfUpper characterIsMember:character] || _NSToUpperTable == 0 ? 0 :
        NS16To16BitEncoding(_NSToUpperTable, _NSUpperTableCount, character);
    *result = mapped == 0 ? character : mapped;
    return 1;
}

int
NSConvertToUpper(unichar character, unichar *result, char flags)
{
    if ((flags & 1) != 0) {
        if (character == 'i') {
            *result = 304;
            return 1;
        }
        if (character == 305) {
            *result = 'I';
            return 1;
        }
    }

    if (character == 64257) {
        result[0] = 'F';
        result[1] = 'I';
        return 2;
    }
    if (character == 64260) {
        result[0] = 'F';
        result[1] = 'F';
        result[2] = 'L';
        return 3;
    }
    if (character == 64261 || character == 64262) {
        result[0] = 'S';
        result[1] = 't';
        return 2;
    }
    if (character == 64258) {
        result[0] = 'F';
        result[1] = 'L';
        return 2;
    }
    if (character == 64259) {
        result[0] = 'F';
        result[1] = 'F';
        result[2] = 'I';
        return 3;
    }
    if (character == 322) {
        *result = 321;
        return 1;
    }
    if (character == 339) {
        *result = 338;
        return 1;
    }
    if (character == 64256) {
        result[0] = 'F';
        result[1] = 'F';
        return 2;
    }
    if (character == 223) {
        result[0] = 'S';
        result[1] = 'S';
        return 2;
    }
    if (character > 0xff)
        return _NSConvertToUpperCase(character, result);

    if ((character >= 'a' && character <= 'z') ||
        (character >= 0x00e0 && character <= 0x00f6) ||
        (character >= 0x00f8 && character <= 0x00fe)) {
        *result = character - 32;
    } else if (character == 0x00ff) {
        *result = 0x0178;
    } else {
        *result = character;
    }
    return 1;
}

int
NSConvertToLower(unichar character, unichar *result, char flags)
{
    if ((flags & 1) != 0) {
        if (character == 304) {
            *result = 'i';
            return 1;
        }
        if (character == 'I') {
            *result = 305;
            return 1;
        }
    }

    if (character == 338) {
        *result = 339;
        return 1;
    }
    if (character == 376) {
        *result = 255;
        return 1;
    }
    if (character == 321) {
        *result = 322;
        return 1;
    }
    if (character > 0xff)
        return _NSConvertToLowerCase(character, result);

    if ((character >= 'A' && character <= 'Z') ||
        (character >= 0x00c0 && character <= 0x00d6) ||
        (character >= 0x00d8 && character <= 0x00de)) {
        *result = character + 32;
    } else {
        *result = character;
    }
    return 1;
}

int
NSConvertToTitle(unichar character, unichar *result, char flags)
{
    int convertedLength;

    if ((flags & 1) != 0) {
        if (character == 'i') {
            *result = 304;
            return 1;
        }
        if (character == 305) {
            *result = 'I';
            return 1;
        }
    }

    if (character == 64258) {
        result[0] = 'F';
        result[1] = 'l';
        return 2;
    }
    if (character == 64260) {
        result[0] = 'F';
        result[1] = 'f';
        result[2] = 'l';
        return 3;
    }
    if (character == 64259) {
        result[0] = 'F';
        result[1] = 'f';
        result[2] = 'i';
        return 3;
    }
    if (character == 64261 || character == 64262) {
        result[0] = 'S';
        result[1] = 't';
        return 2;
    }
    if (character == 64256) {
        result[0] = 'F';
        result[1] = 'f';
        return 2;
    }
    if (character == 64257) {
        result[0] = 'F';
        result[1] = 'i';
        return 2;
    }
    if (character == 223) {
        result[0] = 'S';
        result[1] = 's';
        return 2;
    }
    if (character <= 0x7f)
        return NSConvertToUpper(character, result, flags);

    convertedLength = _NSConvertToTitleCase(character, result);
    if (convertedLength == 0)
        return NSConvertToUpper(character, result, flags);
    return convertedLength;
}

@interface NSString (NSStringOtherEncodings)
- (id)_newSubstringWithRange:(NSRange)range zone:(NSZone *)zone;
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy range:(NSRange)range remainingRange:(NSRangePointer)remainingRange;
- (void)_getBytesInJISEncoding:(char *)buffer range:(NSRange)range usedBytes:(unsigned *)usedBytes lossy:(BOOL)lossy;
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy;
- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding;
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding;
- (NSStringEncoding)smallestEncoding;
- (NSStringEncoding)fastestEncoding;
- (const char *)lossyCString;
- (unsigned)cStringLength;
- (const char *)cString;
- (void)getCString:(char *)bytes;
- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength;
- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength range:(NSRange)range remainingRange:(NSRangePointer)remainingRange;
+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)encoding;
+ (const NSStringEncoding *)availableStringEncodings;
+ (NSStringEncoding)defaultCStringEncoding;
@end

typedef struct {
    unsigned chunkLength;
    unsigned chunkIndex;
    NSString *string;
    unsigned rangeEnd;
    unsigned chunkLocation;
    unichar characters[32];
    unichar character;
} NSStringEncodingReader;

typedef int (*NSStringEncodingConverter)(NSStringEncodingReader *, unsigned char *);

int NSUnicodeToASCII(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToAdobeStandardCyrillic(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToAdobeStandard(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToISOLatin1(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToISOLatin2(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToLossyASCII(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToMacOSRoman(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToNEXTSTEP(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToNextEUC(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToShiftJIS(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToSymbol(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToDingbat(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToUTF8(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToWinCodePage1250(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToWinCodePage1253(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToWinCodePage1254(NSStringEncodingReader *reader, unsigned char *bytes);
int NSUnicodeToWinLatin1(NSStringEncodingReader *reader, unsigned char *bytes);
int _NSUnicodeToProprietaryEncoding(NSStringEncodingReader *reader, unsigned char *bytes);

const unsigned int lossyNEXTSTEPToASCIITable[128] = {
#if defined(__ppc__) || defined(__POWERPC__)
#define NSLOSSYASCII_WORD(value) \
    (((value & 0x000000ffU) << 24) | ((value & 0x0000ff00U) << 8) | \
     ((value & 0x00ff0000U) >> 8) | ((value & 0xff000000U) >> 24))
#else
#define NSLOSSYASCII_WORD(value) (value)
#endif

    NSLOSSYASCII_WORD(0x00000020U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000041U), NSLOSSYASCII_WORD(0x00000043U),
    NSLOSSYASCII_WORD(0x00000045U), NSLOSSYASCII_WORD(0x00000045U), NSLOSSYASCII_WORD(0x00000045U), NSLOSSYASCII_WORD(0x00000045U), NSLOSSYASCII_WORD(0x00000049U), NSLOSSYASCII_WORD(0x00000049U), NSLOSSYASCII_WORD(0x00000049U), NSLOSSYASCII_WORD(0x00000049U),
    NSLOSSYASCII_WORD(0x00004854U), NSLOSSYASCII_WORD(0x0000004eU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x00000055U),
    NSLOSSYASCII_WORD(0x00000055U), NSLOSSYASCII_WORD(0x00000055U), NSLOSSYASCII_WORD(0x00000055U), NSLOSSYASCII_WORD(0x00000059U), NSLOSSYASCII_WORD(0x00006874U), NSLOSSYASCII_WORD(0x00000075U), NSLOSSYASCII_WORD(0x00000078U), NSLOSSYASCII_WORD(0x0000002fU),
    NSLOSSYASCII_WORD(0x00294328U), NSLOSSYASCII_WORD(0x00000021U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x0000004cU), NSLOSSYASCII_WORD(0x0000002fU), NSLOSSYASCII_WORD(0x00000059U), NSLOSSYASCII_WORD(0x00000066U), NSLOSSYASCII_WORD(0x00000000U),
    NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000027U), NSLOSSYASCII_WORD(0x00000022U), NSLOSSYASCII_WORD(0x00003c3cU), NSLOSSYASCII_WORD(0x0000003cU), NSLOSSYASCII_WORD(0x0000003eU), NSLOSSYASCII_WORD(0x00006966U), NSLOSSYASCII_WORD(0x00006c66U),
    NSLOSSYASCII_WORD(0x00295228U), NSLOSSYASCII_WORD(0x0000002dU), NSLOSSYASCII_WORD(0x0000002bU), NSLOSSYASCII_WORD(0x00002b2bU), NSLOSSYASCII_WORD(0x0000002eU), NSLOSSYASCII_WORD(0x0000007cU), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x0000002aU),
    NSLOSSYASCII_WORD(0x00000027U), NSLOSSYASCII_WORD(0x00000022U), NSLOSSYASCII_WORD(0x00000022U), NSLOSSYASCII_WORD(0x00003e3eU), NSLOSSYASCII_WORD(0x002e2e2eU), NSLOSSYASCII_WORD(0x30302f30U), NSLOSSYASCII_WORD(0x0000002dU), NSLOSSYASCII_WORD(0x0000003fU),
    NSLOSSYASCII_WORD(0x00000031U), NSLOSSYASCII_WORD(0x00000060U), NSLOSSYASCII_WORD(0x00000027U), NSLOSSYASCII_WORD(0x0000005eU), NSLOSSYASCII_WORD(0x0000007eU), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U),
    NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000032U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000033U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U),
    NSLOSSYASCII_WORD(0x00002d2dU), NSLOSSYASCII_WORD(0x00002d2bU), NSLOSSYASCII_WORD(0x00003431U), NSLOSSYASCII_WORD(0x00003231U), NSLOSSYASCII_WORD(0x00003433U), NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000061U),
    NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000063U), NSLOSSYASCII_WORD(0x00000065U), NSLOSSYASCII_WORD(0x00000065U), NSLOSSYASCII_WORD(0x00000065U), NSLOSSYASCII_WORD(0x00000065U),
    NSLOSSYASCII_WORD(0x00000069U), NSLOSSYASCII_WORD(0x00004541U), NSLOSSYASCII_WORD(0x00000069U), NSLOSSYASCII_WORD(0x00000061U), NSLOSSYASCII_WORD(0x00000069U), NSLOSSYASCII_WORD(0x00000069U), NSLOSSYASCII_WORD(0x00004854U), NSLOSSYASCII_WORD(0x0000006eU),
    NSLOSSYASCII_WORD(0x0000004cU), NSLOSSYASCII_WORD(0x0000004fU), NSLOSSYASCII_WORD(0x0000454fU), NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x0000006fU),
    NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x00006561U), NSLOSSYASCII_WORD(0x00000075U), NSLOSSYASCII_WORD(0x00000075U), NSLOSSYASCII_WORD(0x00000075U), NSLOSSYASCII_WORD(0x00000069U), NSLOSSYASCII_WORD(0x00000075U), NSLOSSYASCII_WORD(0x00000079U),
    NSLOSSYASCII_WORD(0x0000006cU), NSLOSSYASCII_WORD(0x0000006fU), NSLOSSYASCII_WORD(0x0000656fU), NSLOSSYASCII_WORD(0x00007373U), NSLOSSYASCII_WORD(0x00006874U), NSLOSSYASCII_WORD(0x00000079U), NSLOSSYASCII_WORD(0x00000000U), NSLOSSYASCII_WORD(0x00000000U),
};
#undef NSLOSSYASCII_WORD

static void
NSStringEncodingReaderNext(NSStringEncodingReader *reader)
{
    if (reader->chunkIndex < reader->chunkLength) {
        reader->character = reader->characters[reader->chunkIndex++];
        return;
    }

    reader->chunkLocation += reader->chunkLength;
    if (reader->chunkLocation >= reader->rangeEnd) {
        reader->chunkIndex = reader->chunkLength + 1;
        reader->character = 0xffff;
        return;
    }

    reader->chunkLength = reader->rangeEnd - reader->chunkLocation;
    if (reader->chunkLength > 32)
        reader->chunkLength = 32;
    [reader->string getCharacters:reader->characters
                            range:NSMakeRange(reader->chunkLocation, reader->chunkLength)];
    reader->chunkIndex = 1;
    reader->character = reader->characters[0];
}

int
_NSUnicodeToProprietaryEncoding(NSStringEncodingReader *reader, unsigned char *bytes)
{
    int length;

    length = NSProprietaryUnicodeToEncoding(reader->character, bytes);
    NSStringEncodingReaderNext(reader);
    return length;
}

static unsigned
NSStringEncodingReaderLocation(const NSStringEncodingReader *reader)
{
    return reader->chunkLocation + reader->chunkIndex - 1;
}

static int
NSUnicodeTo8BitEncoding(const NSNextStepMapping *table, unsigned count,
                        NSStringEncodingReader *reader, unsigned char *bytes)
{
    unsigned first = 0;
    unsigned last = count;
    unichar character = reader->character;

    while (first < last) {
        unsigned middle = first + (last - first) / 2;
        if (character < table[middle].unicode) {
            last = middle;
        } else if (character > table[middle].unicode) {
            first = middle + 1;
        } else {
            bytes[0] = table[middle].nextStep;
            NSStringEncodingReaderNext(reader);
            return 1;
        }
    }
    return 0;
}

int
NSUnicodeToASCII(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unichar character = reader->character;

    if (character > 0x7f && character != 0x2029)
        return 0;
    bytes[0] = character == 0x2029 ? '\n' : (unsigned char)character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToNEXTSTEP(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unsigned char converted;

    if (!NSPrecompUnicodeToNEXTSTEP(reader->character, &converted))
        return 0;
    bytes[0] = converted;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToAdobeStandardCyrillic(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x9f)
        return NSUnicodeTo8BitEncoding(NSAdobeCyrillicMappings,
            sizeof(NSAdobeCyrillicMappings) / sizeof(NSAdobeCyrillicMappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToISOLatin1(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unichar character = reader->character;

    if (character > 0xff && character != 0x2029)
        return 0;
    bytes[0] = character == 0x2029 ? '\n' : (unsigned char)character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToISOLatin2(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x9f)
        return NSUnicodeTo8BitEncoding(NSISOLatin2Mappings,
            sizeof(NSISOLatin2Mappings) / sizeof(NSISOLatin2Mappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToWinCodePage1250(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x9f)
        return NSUnicodeTo8BitEncoding(NSWin1250Mappings,
            sizeof(NSWin1250Mappings) / sizeof(NSWin1250Mappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToWinCodePage1253(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x9f)
        return NSUnicodeTo8BitEncoding(NSWin1253Mappings,
            sizeof(NSWin1253Mappings) / sizeof(NSWin1253Mappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToWinCodePage1254(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x9f)
        return NSUnicodeTo8BitEncoding(NSWin1254Mappings,
            sizeof(NSWin1254Mappings) / sizeof(NSWin1254Mappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToWinLatin1(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unichar character = reader->character;

    if (character > 0x7f && character < 0xa0)
        return NSUnicodeTo8BitEncoding(NSWinLatin1Mappings,
            sizeof(NSWinLatin1Mappings) / sizeof(NSWinLatin1Mappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToMacOSRoman(NSStringEncodingReader *reader, unsigned char *bytes)
{
    if (reader->character > 0x7f)
        return NSUnicodeTo8BitEncoding(NSMacRomanMappings,
            sizeof(NSMacRomanMappings) / sizeof(NSMacRomanMappings[0]),
            reader, bytes);
    bytes[0] = (unsigned char)reader->character;
    NSStringEncodingReaderNext(reader);
    return 1;
}

int
NSUnicodeToSymbol(NSStringEncodingReader *reader, unsigned char *bytes)
{
    return NSUnicodeTo8BitEncoding(NSSymbolMappings,
        sizeof(NSSymbolMappings) / sizeof(NSSymbolMappings[0]), reader, bytes);
}

int
NSUnicodeToDingbat(NSStringEncodingReader *reader, unsigned char *bytes)
{
    return NSUnicodeTo8BitEncoding(NSDingbatMappings,
        sizeof(NSDingbatMappings) / sizeof(NSDingbatMappings[0]), reader, bytes);
}

int
NSUnicodeToAdobeStandard(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unichar character = reader->character;

    if (character <= 0x9f) {
        bytes[0] = (unsigned char)character;
        NSStringEncodingReaderNext(reader);
        return 1;
    }
    if (character == 0x2029) {
        bytes[0] = '\n';
        NSStringEncodingReaderNext(reader);
        return 1;
    }
    return NSUnicodeTo8BitEncoding(NSAdobeStandardMappings,
        sizeof(NSAdobeStandardMappings) / sizeof(NSAdobeStandardMappings[0]),
        reader, bytes);
}

int
NSUnicodeToLossyASCII(NSStringEncodingReader *reader, unsigned char *bytes)
{
    const unsigned char *mapping;
    int length;
    int converted;

    if (NSUnicodeToASCII(reader, bytes))
        return 1;
    converted = NSUnicodeToNEXTSTEP(reader, bytes);
    if (converted && bytes[0] >= 0x80) {
        mapping = (const unsigned char *)&lossyNEXTSTEPToASCIITable
            [bytes[0] - 0x80];
        if (mapping[0] != 0) {
            bytes[0] = mapping[0];
            length = 1;
            if (mapping[1] != 0) {
                bytes[1] = mapping[1];
                length = 2;
            }
            if (mapping[2] != 0) {
                bytes[2] = mapping[2];
                ++length;
            }
            if (mapping[3] != 0) {
                bytes[3] = mapping[3];
                ++length;
            }
            return length;
        }
    }
    if (!converted)
        NSStringEncodingReaderNext(reader);
    bytes[0] = '_';
    return 1;
}
static unsigned short *NSUnicodeToEUCTable;
static unsigned NSUnicodeToEUCTableCount;
static unsigned char NSUnicodeToEUCTableLoadWarned;

int
NSUnicodeToNextEUC(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unsigned tableCount;
    unsigned short mapped;
    unichar character;

    if (NSUnicodeToEUCTable == 0) {
        tableCount = _loadConvTable(&NSUnicodeToEUCTable, "UnicodeToEUC");
        if (tableCount == 0) {
            if (!NSUnicodeToEUCTableLoadWarned) {
                NSUnicodeToEUCTableLoadWarned = 1;
                NSLog(@"NSCharConversion: could not load UnicodeToEUC conversion table.\n");
            }
            return 0;
        }
        NSUnicodeToEUCTableCount = tableCount;
    }
    character = reader->character;
    mapped = NS16To16BitEncoding(NSUnicodeToEUCTable,
                                  NSUnicodeToEUCTableCount, character);
    if (mapped != 0) {
        bytes[0] = (unsigned char)(mapped >> 8);
        bytes[1] = (unsigned char)mapped;
        NSStringEncodingReaderNext(reader);
        return 2;
    }
    if (character <= 0x7f) {
        bytes[0] = (unsigned char)character;
        NSStringEncodingReaderNext(reader);
        return 1;
    }
    if (character >= 0xff61 && character <= 0xff9f) {
        bytes[0] = 0x8e;
        bytes[1] = (unsigned char)(character + 0x40);
        NSStringEncodingReaderNext(reader);
        return 2;
    }
    if (character == 0x2029) {
        bytes[0] = '\n';
        NSStringEncodingReaderNext(reader);
        return 1;
    }
    if (NSUnicodeToNEXTSTEP(reader, bytes + 1)) {
        bytes[0] = 0xa0;
        return 2;
    }
    return 0;
}

int
NSEUCToShiftJIS(const unsigned char *euc, unsigned char *bytes,
               unsigned int *consumed)
{
    static const struct {
        unsigned char eucTrail;
        unsigned char shiftJISTrail;
    } nextVendorMappings[] = {
        { 0xdc, 0x97 }, { 0xdd, 0x96 }, { 0xe1, 0x91 },
        { 0xe2, 0x90 }, { 0xe5, 0x95 }, { 0xe9, 0x92 }
    };
    unsigned char row;
    unsigned char cell;
    unsigned char lead;
    unsigned char trail;

    if (euc[0] < 0x80) {
        bytes[0] = euc[0];
        *consumed = 1;
        return 1;
    }
    if (euc[0] == 0x8e && euc[1] >= 0xa1 && euc[1] <= 0xfe) {
        bytes[0] = euc[1];
        *consumed = 2;
        return 1;
    }
    if (euc[0] < 0xa1 || euc[0] > 0xfe ||
        euc[1] < 0xa1 || euc[1] > 0xfe) {
        bytes[0] = '?';
        *consumed = 1;
        return 1;
    }
    if (euc[0] == 0xfe && euc[1] >= 0xa2 && euc[1] <= 0xf9) {
        bytes[0] = 0x87;
        bytes[1] = (unsigned char)(euc[1] - (euc[1] <= 0xd6 ? 0x61 : 0x60));
        *consumed = 2;
        return 2;
    }
    if (euc[0] == 0xa2 && euc[1] > 0xd0) {
        unsigned i;

        bytes[0] = 0x87;
        /* The target leaves the second byte unchanged for unmapped trails. */
        for (i = 0; i < sizeof(nextVendorMappings) / sizeof(nextVendorMappings[0]); ++i) {
            if (euc[1] == nextVendorMappings[i].eucTrail) {
                bytes[1] = nextVendorMappings[i].shiftJISTrail;
                break;
            }
        }
        *consumed = 2;
        return 2;
    }
    row = euc[0] & 0x7f;
    cell = euc[1] & 0x7f;
    lead = (unsigned char)(((row - 0x21) >> 1) + 0x81);
    if (lead > 0x9f)
        lead += 0x40;
    trail = (unsigned char)(cell + ((row & 1) ? 0x1f : 0x7d));
    if (trail > 0x7e)
        ++trail;
    bytes[0] = lead;
    bytes[1] = trail;
    *consumed = 2;
    return 2;
}

int
NSUnicodeToShiftJIS(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unsigned char euc[2];
    unsigned int consumed;

    if (NSUnicodeToNextEUC(reader, euc) == 0)
        return 0;
    return NSEUCToShiftJIS(euc, bytes, &consumed);
}

int
NSUnicodeToUTF8(NSStringEncodingReader *reader, unsigned char *bytes)
{
    unsigned int scalar = reader->character;
    unsigned char *output = bytes;
    int length;

    NSStringEncodingReaderNext(reader);
    if (scalar >= 0xd800 && scalar <= 0xdbff && reader->character >= 0xdc00 &&
        reader->character <= 0xdfff) {
        scalar = 0x10000 + ((scalar - 0xd800) << 10) + (reader->character - 0xdc00);
        NSStringEncodingReaderNext(reader);
    }
    if (scalar <= 0x7f) {
        output[0] = (unsigned char)scalar;
        return 1;
    }
    if (scalar <= 0x7ff) {
        output[0] = 0xc0 | (scalar >> 6);
        output[1] = 0x80 | (scalar & 0x3f);
        return 2;
    }
    if (scalar <= 0xffff) {
        output[0] = 0xe0 | (scalar >> 12);
        output[1] = 0x80 | ((scalar >> 6) & 0x3f);
        output[2] = 0x80 | (scalar & 0x3f);
        return 3;
    }
    if (scalar <= 0x1fffff) {
        output[0] = 0xf0 | (scalar >> 18);
        output[1] = 0x80 | ((scalar >> 12) & 0x3f);
        output[2] = 0x80 | ((scalar >> 6) & 0x3f);
        output[3] = 0x80 | (scalar & 0x3f);
        return 4;
    }
    if (scalar <= 0x3ffffff) {
        length = 5;
        output[0] = 0xf8 | (scalar >> 24);
    } else {
        length = 6;
        output[0] = 0xfc | (scalar >> 30);
    }
    {
        int i;
        for (i = length - 1; i > 0; --i) {
            output[i] = 0x80 | (scalar & 0x3f);
            scalar >>= 6;
        }
        output[0] |= scalar;
    }
    return length;
}

#if defined(__ppc__) || defined(__POWERPC__)
static const char *bytesInEncoding(NSString *string,
                                   NSStringEncoding encoding) {
    char stackBuffer[1000];
    unsigned characterLength = [string length];
    unsigned byteLength = 0;
    unsigned bytesWritten = 0;
    NSRange range = NSMakeRange(0, characterLength);
    char *bytes;

    if (characterLength <= 0xa5
        && [string getBytes:stackBuffer maxLength:sizeof(stackBuffer)
               filledLength:&byteLength encoding:encoding
      allowLossyConversion:NO range:range remainingRange:NULL]) {
        bytes = [_NSAutoreleasedMallocMemory mallocMemoryWithCapacity:byteLength + 1];
        memmove(bytes, stackBuffer, byteLength);
        bytes[byteLength] = '\0';
        return bytes;
    }

    if (![string getBytes:NULL maxLength:INT_MAX - 1 filledLength:&byteLength
                 encoding:encoding allowLossyConversion:NO range:range
           remainingRange:NULL]) {
        NSString *displayString = string;
        NSString *reason;
        NSDictionary *userInfo;

        if (characterLength > 23)
            displayString = [[string substringToIndex:20]
                stringByAppendingString:@"..."];
        reason = [NSString stringWithFormat:
            @"Conversion to encoding %d failed for string \"%@\"",
            encoding, displayString];
        userInfo = [NSDictionary dictionaryWithObject:string forKey:@"_NSString"];
        [[NSException exceptionWithName:NSCharacterConversionException
                                  reason:reason userInfo:userInfo] raise];
    }

    bytes = [_NSAutoreleasedMallocMemory mallocMemoryWithCapacity:byteLength + 1];
    if (![string getBytes:bytes maxLength:byteLength filledLength:&bytesWritten
                 encoding:encoding allowLossyConversion:NO range:range
           remainingRange:NULL] || bytesWritten != byteLength)
        [NSException raise:NSCharacterConversionException
                    format:@"Conversion to encoding %d", encoding];
    bytes[bytesWritten] = '\0';
    return bytes;
}
#endif

static const unsigned char NSJISAlternateCharacters[128] = {
    0x3f, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x43, 0x45, 0x45, 0x45, 0x45, 0x49, 0x49, 0x49, 0x49,
    0x44, 0x4e, 0x4f, 0x4f, 0x4f, 0x4f, 0x4f, 0x55, 0x55, 0x55, 0x55, 0x59, 0x50, 0x75, 0x78, 0x2f,
    0x43, 0x69, 0x63, 0x4c, 0x2f, 0x59, 0x66, 0x53, 0x6f, 0x27, 0x22, 0x3c, 0x3c, 0x3e, 0x66, 0x66,
    0x52, 0x2d, 0x2b, 0x2b, 0x2a, 0x7c, 0x71, 0x2a, 0x2c, 0x2c, 0x27, 0x3e, 0x2e, 0x2f, 0x7e, 0x3f,
    0x31, 0x60, 0x27, 0x5e, 0x7e, 0x7e, 0x7e, 0x27, 0x22, 0x32, 0x6f, 0x2c, 0x33, 0x22, 0x2c, 0x7e,
    0x2d, 0x2b, 0x2f, 0x2f, 0x2f, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x63, 0x65, 0x65, 0x65, 0x65,
    0x69, 0x41, 0x69, 0x61, 0x69, 0x69, 0x64, 0x6e, 0x4c, 0x4f, 0x43, 0x2d, 0x6f, 0x6f, 0x6f, 0x6f,
    0x6f, 0x61, 0x75, 0x3f, 0x75, 0x69, 0x75, 0x79, 0x6c, 0x6f, 0x6f, 0x62, 0x62, 0x79, 0x3f, 0x3f,
};

@implementation NSString (NSStringOtherEncodings)

- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength filledLength:(unsigned *)filledLength encoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy range:(NSRange)range remainingRange:(NSRangePointer)remainingRange {
    NSStringEncodingConverter converter = 0;
    NSStringEncodingReader reader;
    unsigned bytesWritten = 0;
    unsigned rangeEnd = range.location + range.length;
    unsigned consumed = 0;
    unsigned i;

    if (encoding == 1) {
        converter = NSUnicodeToASCII;
    } else if (encoding == 2) {
        converter = NSUnicodeToNEXTSTEP;
    } else if (encoding == 3) {
        converter = NSUnicodeToNextEUC;
    } else if (encoding == 4) {
        converter = NSUnicodeToUTF8;
    } else if (encoding == 5) {
        converter = NSUnicodeToISOLatin1;
    } else if (encoding == 6) {
        converter = NSUnicodeToSymbol;
    } else if (encoding == 8) {
        converter = NSUnicodeToShiftJIS;
    } else if (encoding == 9) {
        converter = NSUnicodeToISOLatin2;
    } else if (encoding == 11) {
        converter = NSUnicodeToAdobeStandardCyrillic;
    } else if (encoding == 12) {
        converter = NSUnicodeToWinLatin1;
    } else if (encoding == 13) {
        converter = NSUnicodeToWinCodePage1253;
    } else if (encoding == 14) {
        converter = NSUnicodeToWinCodePage1254;
    } else if (encoding == 15) {
        converter = NSUnicodeToWinCodePage1250;
    } else if (encoding == 30) {
        converter = NSUnicodeToMacOSRoman;
    } else if (encoding == 0x10000) {
        converter = _NSUnicodeToProprietaryEncoding;
    } else if (encoding != 0 && encoding != 7 && encoding != 10 && encoding != 21) {
        return NO;
    }

    reader.string = self;
    reader.rangeEnd = rangeEnd;
    reader.chunkLocation = range.location;
    reader.chunkIndex = 1;
    reader.chunkLength = range.length;
    if (reader.chunkLength > 32)
        reader.chunkLength = 32;
    if (reader.chunkLength != 0) {
        [self getCharacters:reader.characters
                      range:NSMakeRange(reader.chunkLocation, reader.chunkLength)];
        reader.character = reader.characters[0];
    } else {
        reader.character = 0xffff;
    }

    if (converter != 0) {
        while (reader.character != 0xffff && consumed < range.length) {
            NSStringEncodingReader nextReader = reader;
            unsigned char converted[8];
            int convertedLength = converter(&nextReader, converted);

            if (convertedLength == 0) {
                if (!lossy)
                    return NO;
                if (encoding == 1) {
                    nextReader = reader;
                    convertedLength = NSUnicodeToLossyASCII(&nextReader, converted);
                    if (convertedLength == 0)
                        return NO;
                } else {
                    nextReader = reader;
                    converted[0] = '_';
                    convertedLength = 1;
                    NSStringEncodingReaderNext(&nextReader);
                }
            }
            if (maxLength < bytesWritten + (unsigned)convertedLength)
                break;
            if (buffer != 0) {
                for (i = 0; i < (unsigned)convertedLength; ++i)
                    buffer[bytesWritten + i] = converted[i];
            }
            bytesWritten += convertedLength;
            reader = nextReader;
            ++consumed;
        }
    } else if (encoding == 7) {
        static const char hexDigits[] = "0123456789abcdef";

        while (reader.character != 0xffff && bytesWritten < maxLength) {
            unsigned char converted[6];
            unsigned convertedLength;
            unichar character = reader.character;

            if (((character - 32) <= 0x5e && character != '\\') ||
                character == '\n' || character == '\r' || character == '\t') {
                converted[0] = character;
                convertedLength = 1;
            } else if (character == '\\') {
                converted[0] = '\\';
                converted[1] = '\\';
                convertedLength = 2;
            } else if (character > 0xff) {
                converted[0] = '\\';
                converted[1] = 'U';
                converted[2] = hexDigits[(character >> 12) & 0xf];
                converted[3] = hexDigits[(character >> 8) & 0xf];
                converted[4] = hexDigits[(character >> 4) & 0xf];
                converted[5] = hexDigits[character & 0xf];
                convertedLength = 6;
            } else {
                converted[0] = '\\';
                converted[1] = '0' + ((character >> 6) & 7);
                converted[2] = '0' + ((character >> 3) & 7);
                converted[3] = '0' + (character & 7);
                convertedLength = 4;
            }

            if (maxLength < bytesWritten + convertedLength)
                break;
            if (buffer != 0) {
                for (i = 0; i < convertedLength; ++i)
                    buffer[bytesWritten + i] = converted[i];
            }
            bytesWritten += convertedLength;
            NSStringEncodingReaderNext(&reader);
        }
    } else if (encoding == 21) {
        [self _getBytesInJISEncoding:buffer range:range usedBytes:&bytesWritten lossy:lossy];
        reader.chunkLocation = rangeEnd;
        reader.chunkIndex = reader.chunkLength + 1;
        reader.character = 0xffff;
    } else {
        consumed = range.length;
        if (maxLength < 2 * range.length + 2) {
            if (maxLength <= 2)
                consumed = 0;
            else
                consumed = (maxLength - 2) >> 1;
        }
        bytesWritten = 2 * consumed + 2;
        if (buffer != 0) {
#if defined(__ppc__) || defined(__POWERPC__)
            buffer[0] = (char)0xfe;
            buffer[1] = (char)0xff;
#else
            buffer[0] = (char)0xff;
            buffer[1] = (char)0xfe;
#endif
            [self getCharacters:(unichar *)(buffer + 2)
                          range:NSMakeRange(range.location, consumed)];
        }
        reader.chunkLocation = range.location + consumed;
        reader.chunkLength = 0;
        reader.chunkIndex = 1;
        reader.character = 0xffff;
    }

    if (filledLength != 0)
        *filledLength = bytesWritten;
    if (remainingRange != 0) {
        unsigned location = converter != 0
            ? range.location + consumed
            : NSStringEncodingReaderLocation(&reader);
        if (location > rangeEnd)
            location = rangeEnd;
        remainingRange->location = location;
        remainingRange->length = rangeEnd - location;
    }
    return YES;
}

- (void)_getBytesInJISEncoding:(char *)buffer range:(NSRange)range usedBytes:(unsigned *)usedBytes lossy:(BOOL)lossy {
    static const char asciiSequence[] = "(B";
    static const char katakanaSequence[] = "(I";
    static const char kanjiSequence[] = "$B";
    NSData *data;
    NSString *substring;
    const unsigned char *source;
    unsigned sourceLength;
    unsigned inputIndex = 0;
    unsigned outputLength = 0;
    unsigned state = 0;
    unsigned char *output = (unsigned char *)buffer;

    substring = [self _newSubstringWithRange:range zone:[self zone]];
    data = [substring dataUsingEncoding:3 allowLossyConversion:lossy];
    [substring release];
    if (data == nil) {
        if (usedBytes != 0)
            *usedBytes = 0;
        return;
    }
    source = (const unsigned char *)[data bytes];
    sourceLength = [data length];

    while (inputIndex < sourceLength) {
        unsigned char byte = source[inputIndex];

        if (byte < 0x80) {
            if (state != 0) {
                output[outputLength++] = 0x1b;
                output[outputLength++] = asciiSequence[0];
                output[outputLength++] = asciiSequence[1];
                state = 0;
            }
            output[outputLength++] = byte;
            ++inputIndex;
        } else if (byte == 0x8e && inputIndex + 1 < sourceLength) {
            if (state != 1) {
                output[outputLength++] = 0x1b;
                output[outputLength++] = katakanaSequence[0];
                output[outputLength++] = katakanaSequence[1];
                state = 1;
            }
            output[outputLength++] = source[inputIndex + 1] & 0x7f;
            inputIndex += 2;
        } else if (byte != 0xa0 && inputIndex + 1 < sourceLength) {
            if (state != 2) {
                output[outputLength++] = 0x1b;
                output[outputLength++] = kanjiSequence[0];
                output[outputLength++] = kanjiSequence[1];
                state = 2;
            }
            output[outputLength++] = byte & 0x7f;
            output[outputLength++] = source[inputIndex + 1] & 0x7f;
            inputIndex += 2;
        } else if (byte == 0xa0 && inputIndex + 1 < sourceLength && !lossy) {
            if (state != 0) {
                output[outputLength++] = 0x1b;
                output[outputLength++] = asciiSequence[0];
                output[outputLength++] = asciiSequence[1];
                state = 0;
            }
            {
                unsigned char nextStepByte = source[inputIndex + 1];

                output[outputLength++] = nextStepByte < 0x80
                    ? '?' : NSJISAlternateCharacters[nextStepByte - 0x80];
            }
            inputIndex += 2;
        } else {
            inputIndex += inputIndex + 1 < sourceLength ? 2 : 1;
        }
    }

    if (state != 0) {
        output[outputLength++] = 0x1b;
        output[outputLength++] = asciiSequence[0];
        output[outputLength++] = asciiSequence[1];
    }
    if (usedBytes != 0)
        *usedBytes = outputLength;
}

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding allowLossyConversion:(BOOL)lossy {
    unsigned length = [self length];
    unsigned capacity;
    unsigned filledLength = 0;
    unsigned remainingLength = 0;
    NSRange remainingRange;
    NSMutableData *data;

    switch (encoding) {
        case 0:
        case 10:
            capacity = 2 * length + 2;
            break;
        case 1:
            capacity = (lossy ? 4 : 1) * length;
            break;
        case 2:
        case 5:
        case 6:
        case 9:
        case 11:
        case 12:
        case 13:
        case 14:
        case 15:
        case 30:
            capacity = length;
            break;
        case 3:
        case 8:
            capacity = 2 * length;
            break;
        case 7:
        case 4:
        case 0x10000:
            capacity = 6 * length;
            break;
        case 21:
            capacity = 12 * length;
            break;
        default:
            NSLog(@"NSString: unknown string encoding %u", encoding);
            return nil;
    }

    data = [[NSMutableData allocWithZone:NULL] initWithLength:capacity];
    if (capacity == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        return [data autorelease];
#else
        return data;
#endif
    }
    if (capacity != 0) {
        remainingRange = NSMakeRange(0, length);
        if (![self getBytes:[data mutableBytes] maxLength:capacity
                filledLength:&filledLength encoding:encoding
          allowLossyConversion:lossy range:NSMakeRange(0, length)
             remainingRange:&remainingRange]) {
            [data release];
            return nil;
        }
        remainingLength = remainingRange.length;
        if (remainingLength != 0)
            [NSException raise:NSCharacterConversionException
                        format:@"%@: didn't convert all characters",
                               _NSMethodExceptionProem(self, _cmd)];
        [data setLength:filledLength];
    }
    return [data autorelease];
}

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {
    return [self dataUsingEncoding:encoding allowLossyConversion:NO];
}

- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)encoding {
    NSStringEncodingConverter converter = 0;
    NSStringEncodingReader reader;
    unsigned char converted[40];
    int convertedLength;

    if (encoding == 0 || encoding == 4 || encoding == 7 || encoding == 10)
        return YES;
    if (encoding == 1)
        converter = NSUnicodeToASCII;
    else if (encoding == 2)
        converter = NSUnicodeToNEXTSTEP;
    else if (encoding == 3 || encoding == 8 || encoding == 21)
        converter = NSUnicodeToNextEUC;
    else if (encoding == 5 || encoding == 12)
        converter = encoding == 5 ? NSUnicodeToISOLatin1 : NSUnicodeToWinLatin1;
    else if (encoding == 6)
        converter = NSUnicodeToSymbol;
    else if (encoding == 9)
        converter = NSUnicodeToISOLatin2;
    else if (encoding == 11)
        converter = NSUnicodeToAdobeStandardCyrillic;
    else if (encoding == 13)
        converter = NSUnicodeToWinCodePage1253;
    else if (encoding == 14)
        converter = NSUnicodeToWinCodePage1254;
    else if (encoding == 15)
        converter = NSUnicodeToWinCodePage1250;
    else if (encoding == 30)
        converter = NSUnicodeToMacOSRoman;
    else if (encoding == 0x10000)
        converter = _NSUnicodeToProprietaryEncoding;
    else
        return NO;

    reader.string = self;
    reader.rangeEnd = [self length];
    reader.chunkLocation = 0;
    reader.chunkIndex = 1;
    reader.chunkLength = reader.rangeEnd;
    if (reader.chunkLength > 32)
        reader.chunkLength = 32;
    if (reader.chunkLength == 0) {
        reader.character = 0xffff;
    } else {
        [self getCharacters:reader.characters
                      range:NSMakeRange(0, reader.chunkLength)];
        reader.character = reader.characters[0];
    }

    while (reader.character != 0xffff) {
        convertedLength = converter(&reader, converted);
        if (convertedLength == 0)
            return NO;
#if defined(__ppc__) || defined(__POWERPC__)
        if ((encoding == 8 || encoding == 21) && converted[0] == 0xa0)
            return NO;
#endif
    }
    return YES;
}

- (NSStringEncoding)smallestEncoding {
    NSStringEncoding encoding;

    if ([self canBeConvertedToEncoding:1])
        return 1;
    encoding = _NSDefaultCStringEncoding();
    if ([self canBeConvertedToEncoding:encoding])
        return _NSDefaultCStringEncoding();
    return 10;
}

- (NSStringEncoding)fastestEncoding {
    return 10;
}

#if defined(__ppc__) || defined(__POWERPC__)
- (const char *)UTF8String {
    return bytesInEncoding(self, NSUTF8StringEncoding);
}
#endif

- (const char *)lossyCString {
    char stackBuffer[500];
    unsigned capacity = sizeof(stackBuffer);
    unsigned bytesWritten = 0;
    unsigned filledLength = 0;
    unsigned length = [self length];
    NSStringEncoding encoding = _NSDefaultCStringEncoding();
    NSRange remainingRange;
    NSMutableData *data = nil;

    if (length == 0)
        return [__NSEmptyString cString];

    remainingRange = NSMakeRange(0, length);
    [self getBytes:stackBuffer
         maxLength:capacity
      filledLength:&filledLength
          encoding:encoding
 allowLossyConversion:YES
             range:remainingRange
     remainingRange:&remainingRange];
    bytesWritten = filledLength;

    while (remainingRange.length != 0) {
        unsigned consumedLength = length - remainingRange.length;
        unsigned newCapacity;
        char *buffer;

        if (consumedLength <= 1)
            consumedLength = 1;
        newCapacity = capacity +
            ((remainingRange.length + 1) * capacity) / consumedLength + 100;
        capacity = newCapacity;

        if (data == nil) {
            data = [NSMutableData dataWithLength:capacity];
            memmove([data mutableBytes], stackBuffer, bytesWritten);
        } else {
            [data setLength:capacity];
        }

        buffer = (char *)[data mutableBytes] + bytesWritten;
        filledLength = 0;
        [self getBytes:buffer
             maxLength:capacity - bytesWritten
          filledLength:&filledLength
              encoding:encoding
 allowLossyConversion:YES
                 range:remainingRange
         remainingRange:&remainingRange];
        bytesWritten += filledLength;
    }

    if (data == nil) {
        char *result = [_NSAutoreleasedMallocMemory mallocMemoryWithCapacity:bytesWritten + 1];
        memmove(result, stackBuffer, bytesWritten);
        result[bytesWritten] = '\0';
        return result;
    }

    [data setLength:bytesWritten + 1];
    ((char *)[data mutableBytes])[bytesWritten] = '\0';
    return [data mutableBytes];
}

- (unsigned)cStringLength {
    unsigned length = 0;

    if (![self getBytes:0
              maxLength:INT_MAX - 1
           filledLength:&length
               encoding:_NSDefaultCStringEncoding()
      allowLossyConversion:NO
                  range:NSMakeRange(0, [self length])
          remainingRange:0])
        return 0;
    return length;
}

- (const char *)cString {
#if defined(__ppc__) || defined(__POWERPC__)
    return bytesInEncoding(self, _NSDefaultCStringEncoding());
#else
    unsigned length = 0;
    unsigned bytesWritten = 0;
    NSStringEncoding encoding = _NSDefaultCStringEncoding();
    NSRange range = NSMakeRange(0, [self length]);
    char *buffer;

    if (![self getBytes:0 maxLength:INT_MAX - 1 filledLength:&length
               encoding:encoding allowLossyConversion:NO range:range
         remainingRange:0])
        [NSException raise:NSCharacterConversionException
                    format:@"*** -[NSString cString] cannot convert %@ to the default C string encoding", self];

    buffer = [_NSAutoreleasedMallocMemory mallocMemoryWithCapacity:length + 1];
    [self getBytes:buffer maxLength:length filledLength:&bytesWritten
           encoding:encoding allowLossyConversion:NO range:range
     remainingRange:0];
    buffer[bytesWritten] = '\0';
    return buffer;
#endif
}

- (void)getCString:(char *)bytes {
    [self getCString:bytes maxLength:INT_MAX - 1];
}

- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength {
    [self getCString:bytes maxLength:maxLength
               range:NSMakeRange(0, [self length]) remainingRange:0];
}

- (void)getCString:(char *)bytes maxLength:(unsigned)maxLength range:(NSRange)range remainingRange:(NSRangePointer)remainingRange {
    unsigned bytesWritten = 0;
    NSString *displayString;
    NSString *reason;
    NSDictionary *userInfo;

    if ([self getBytes:bytes maxLength:maxLength filledLength:&bytesWritten
              encoding:_NSDefaultCStringEncoding() allowLossyConversion:NO
                 range:range remainingRange:remainingRange]) {
        bytes[bytesWritten] = '\0';
        return;
    }

    displayString = self;
    if ([self length] > 0x17)
        displayString = [[self substringWithRange:NSMakeRange(0, 20)]
            stringByAppendingString:@"..."];
#if defined(__ppc__) || defined(__POWERPC__)
    reason = [NSString stringWithFormat:
        @"Conversion to cString failed for string \"%@\"", displayString];
    userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        self, @"_NSString", nil];
#else
    userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        self, @"_NSString", nil];
    reason = [NSString stringWithFormat:
        @"Conversion to cString failed for string \"%@\"", displayString];
#endif
    [[NSException exceptionWithName:NSCharacterConversionException
                              reason:reason userInfo:userInfo] raise];
}

+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)encoding {
    NSString *key;

    switch (encoding) {
        case NSASCIIStringEncoding:
            key = @"ASCII";
            break;
        case NSNEXTSTEPStringEncoding:
            key = @"NEXTSTEP";
            break;
        case NSJapaneseEUCStringEncoding:
            key = @"Japanese EUC";
            break;
        case NSUTF8StringEncoding:
            key = @"UTF-8";
            break;
        case NSISOLatin1StringEncoding:
            key = @"ISO Latin-1";
            break;
        case NSSymbolStringEncoding:
            key = @"Symbol";
            break;
        case NSNonLossyASCIIStringEncoding:
            key = @"Non-lossy ASCII";
            break;
        case NSShiftJISStringEncoding:
            key = @"Shift JIS";
            break;
        case NSISOLatin2StringEncoding:
            key = @"ISO Latin-2";
            break;
        case NSUnicodeStringEncoding:
            key = @"Unicode";
            break;
        case NSWindowsCP1251StringEncoding:
            key = @"Adobe Cyrillic";
            break;
        case NSWindowsCP1252StringEncoding:
            key = @"Windows Latin-1";
            break;
        case NSWindowsCP1250StringEncoding:
            key = @"Windows Latin-2 (Code Page 1250)";
            break;
        case NSWindowsCP1253StringEncoding:
            key = @"Windows Greek (Code Page 1253)";
            break;
        case NSWindowsCP1254StringEncoding:
            key = @"Windows Turkish (Code Page 1254)";
            break;
        case NSISO2022JPStringEncoding:
            key = @"JIS (ISO 2022 JP)";
            break;
        case NSMacOSRomanStringEncoding:
            key = @"MacOS Roman";
            break;
        case NSProprietaryStringEncoding:
            return _NSProprietaryEncodingName();
        default:
            return __NSEmptyString;
    }

    return [_NSFoundationBundle() localizedStringForKey:key value:@"" table:@"EncodingNames"];
}

+ (const NSStringEncoding *)availableStringEncodings {
    static const NSStringEncoding standardEncodings[] = {
        NSUnicodeStringEncoding, NSNEXTSTEPStringEncoding, NSASCIIStringEncoding,
        NSISOLatin1StringEncoding, NSISOLatin2StringEncoding,
        NSJapaneseEUCStringEncoding, NSShiftJISStringEncoding, NSUTF8StringEncoding,
        NSSymbolStringEncoding, NSNonLossyASCIIStringEncoding,
        NSWindowsCP1251StringEncoding, NSWindowsCP1252StringEncoding,
        NSWindowsCP1250StringEncoding, NSWindowsCP1253StringEncoding,
        NSWindowsCP1254StringEncoding, NSISO2022JPStringEncoding,
        NSMacOSRomanStringEncoding, 0
    };
    static const NSStringEncoding extendedEncodings[] = {
        NSUnicodeStringEncoding, NSNEXTSTEPStringEncoding, NSASCIIStringEncoding,
        NSISOLatin1StringEncoding, NSISOLatin2StringEncoding,
        NSJapaneseEUCStringEncoding, NSShiftJISStringEncoding, NSUTF8StringEncoding,
        NSSymbolStringEncoding, NSNonLossyASCIIStringEncoding,
        NSWindowsCP1251StringEncoding, NSWindowsCP1252StringEncoding,
        NSWindowsCP1250StringEncoding, NSWindowsCP1253StringEncoding,
        NSWindowsCP1254StringEncoding, NSISO2022JPStringEncoding,
        NSMacOSRomanStringEncoding, NSProprietaryStringEncoding, 0
    };

    if (_NSDefaultCStringEncoding() == NSProprietaryStringEncoding)
        return extendedEncodings;
    return standardEncodings;
}

+ (NSStringEncoding)defaultCStringEncoding {
    return _NSDefaultCStringEncoding();
}

@end
