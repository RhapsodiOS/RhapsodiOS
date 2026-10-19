/*	NSObjCRuntime.m
	Language terminology and general utility
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSZone.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <syslog.h>
#include <time.h>

#undef YES
#undef NO
#undef nil
#undef Nil
#ifdef NULL
#undef NULL
#endif

/* Synthetic compatibility definitions for legacy exports whose original
   translation unit and padding widths are unknown. */
const BOOL YES = (BOOL)1;
const char dummyPad1 = 0;
const BOOL NO = (BOOL)0;
const char dummyPad2 = 0;
id const nil = (id)0;
Class const Nil = (Class)0;
void *NULL = (void *)0;

#if defined(__ppc__) || defined(__POWERPC__)
unsigned int __NSObjectAllocatorLock = 0;
#endif

#define YES (BOOL)1
#define NO (BOOL)0
#define nil (id)0
#define Nil (Class)0
#define NULL 0

#if defined(__ppc__) || defined(__POWERPC__)
extern int _NSvsnprintf(char *buffer, size_t size, const char *format,
                        va_list arguments);
#endif
extern NSRecursiveLock *_NSLogLock;
extern int _NSProcessID(void);
extern char *_NSProcessName(void);
extern time_t _NSCurrentUNIXTime(void);
extern ssize_t _NSWriteToFileDescriptor(int descriptor, const void *buffer,
                                         size_t length);

static unsigned int NSLocalizeLogDate;

Class (*_NSAltClassNameFromString)(NSString *className) = NULL;

#if defined(__ppc__) || defined(__POWERPC__)
const char NSFoundationVersionString[] =
    "@(#)PROGRAM:Foundation  PROJECT:Foundation-298.81  DEVELOPER:root  BUILT:02/20/99 00:21:12\n";
const double NSFoundationVersionNumber = 298.81;
#else
const char NSFoundationVersionString[] =
    "@(#)PROGRAM:Foundation  PROJECT:Foundation-275  DEVELOPER:root  BUILT:03/28/98 06:22:40\n";
const double NSFoundationVersionNumber = 275.0;
#endif

int
_NSsnprintf(char *buffer, size_t size, char *format, ...)
{
    va_list arguments;

    va_start(arguments, format);
#if defined(__ppc__) || defined(__POWERPC__)
    return _NSvsnprintf(buffer, size, format, arguments);
#else
    return vsnprintf(buffer, size, format, arguments);
#endif
}

extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);

id
NSRequestConcreteImplementation(id object, SEL selector, Class abstractClass)
{
    Class objectClass;
    const char *selectorName;

    objectClass = [object class];
    selectorName = sel_getName(selector);

    if (objectClass == abstractClass) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -%s cannot be sent to an abstract object of class %s: Create a concrete instance!",
                          selectorName, objectClass->name];
    } else {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -%s only defined for abstract class.  Define -[%s %s]!",
                          selectorName, object->isa->name, selectorName];
    }

    return nil;
}

id
_NSRequestConcreteObject(id object, const char *selectorName)
{
    [NSException raise:NSInvalidArgumentException
                format:@"*** -%s cannot be sent to an abstract object of class %s: Create a concrete instance!",
                       selectorName, object->isa->name];
    return nil;
}

NSString *
NSStringFromSelector(SEL aSelector)
{
    const char *name;

    if (aSelector == NULL)
        [NSException raise:NSInvalidArgumentException
                    format:@"*** NSStringFromSelector(): 0 selector"];
    name = sel_getName(aSelector);
    return [NSString stringWithCString:name length:strlen(name)];
}

SEL
NSSelectorFromString(NSString *aSelectorName)
{
    return sel_getUid([aSelectorName cString]);
}

Class
NSClassFromString(NSString *aClassName)
{
    const char *bytes = [aClassName cString];
    Class aClass;

    aClass = objc_getClass(bytes);
    if (aClass == Nil && _NSAltClassNameFromString != NULL)
        aClass = _NSAltClassNameFromString(aClassName);
    return aClass;
}

NSString *
NSStringFromClass(Class aClass)
{
    return [NSString stringWithCString:aClass->name
                               length:strlen(aClass->name)];
}

/*	Walks one type encoding and reports its size and alignment, returning
	a pointer just past the encoding it consumed -- so a caller can step
	through a whole method signature by feeding the return value back in.
	Sizes are this architecture's, taken from the compiler rather than
	assumed: gcc 2.7.2.1 on i386 gives int/long/pointer 4, short 2,
	char 1, float 4, double 8, long long 8.

	A struct's size is its members laid out in order, each padded up to
	its own alignment, with the whole padded up to the widest member's
	alignment.  A union reports the largest member size tracked by the
	architecture's type walker.  Qualifier prefixes
	(const, in, out, inout, bycopy, byref, oneway) carry no size and are
	skipped.  */
static unsigned
NSBitfieldSizeAndAdvance(const char **typePtr, unsigned *alignp,
                         unsigned offset)
{
    const char *cursor = *typePtr;
    unsigned bitsUsed = 0;
    unsigned offsetBits = 8 * offset;
    unsigned bitsRemaining = 32 - (offsetBits % 32);

    *alignp = sizeof(int);
    if (*cursor == 'b') {
        unsigned width;

        do {
            const char *fieldStart = cursor;

            cursor++;
            width = 0;
            while (*cursor >= '0' && *cursor <= '9')
                width = (width * 10) + (unsigned)(*cursor++ - '0');
            if (width != 0) {
                if (bitsRemaining < width) {
                    bitsUsed += bitsRemaining;
                    bitsRemaining = 32;
                    cursor = fieldStart;
                } else {
                    bitsUsed += width;
                    bitsRemaining -= width;
                }
            } else {
                bitsUsed = 32 * ((bitsUsed + offsetBits + 31) / 32) -
                    offsetBits;
                bitsRemaining = 32 - ((bitsUsed + offsetBits) % 32);
            }
        } while (*cursor == 'b');
    }

    *typePtr = cursor;
    return (bitsUsed + 7) >> 3;
}

static const char *
NSSizeAndAlignmentOfType(const char *typePtr, unsigned *sizep, unsigned *alignp)
{
    unsigned size;
    unsigned align;

    while (*typePtr == 'r' || *typePtr == 'n' || *typePtr == 'N' ||
           *typePtr == 'o' || *typePtr == 'O' || *typePtr == 'R' ||
           *typePtr == 'V')
        typePtr++;

    size = 0;
    align = 0;

    switch (*typePtr) {
    case '!': case '%':
        size = sizeof(int); align = sizeof(int); typePtr++; break;
    case '$':
        size = sizeof(char); align = size; typePtr++; break;
    case 'c': case 'C':
        size = sizeof(char); align = size; typePtr++; break;
    case 's': case 'S':
        size = sizeof(short); align = size; typePtr++; break;
    case 'i': case 'I': case 'l': case 'L':
        size = sizeof(int); align = size; typePtr++; break;
    case 'q': case 'Q':
        size = 8; align = sizeof(int); typePtr++; break;
    case 'f':
        size = sizeof(float); align = size; typePtr++; break;
    case 'd':
        size = sizeof(double); align = sizeof(int); typePtr++; break;
    case '*': case '@': case '#': case ':':
        size = sizeof(void *); align = size; typePtr++; break;
    case '^':
        /*  A pointer is pointer-sized whatever it points at, but the
            pointee's encoding still has to be stepped over.  */
        typePtr = NSSizeAndAlignmentOfType(typePtr + 1, 0, 0);
        size = sizeof(void *); align = size;
        break;
    case '[': {
        unsigned count;
        unsigned elementSize;
        unsigned elementAlign;

        typePtr++;
        count = 0;
        while (*typePtr >= '0' && *typePtr <= '9')
            count = (count * 10) + (unsigned)(*typePtr++ - '0');
        typePtr = NSSizeAndAlignmentOfType(typePtr, &elementSize, &elementAlign);
        size = count * elementAlign *
            ((elementSize + elementAlign - 1) / elementAlign);
        align = elementAlign;
        if (*typePtr != ']') {
            typePtr++;
            if (alignp != 0)
                *alignp = align;
            [NSException raise:NSInvalidArgumentException
                        format:@"badly formed array description"];
        } else {
            typePtr++;
        }
        break;
    }
    case '{': case '(': {
        char closing = (*typePtr == '{') ? '}' : ')';
        BOOL isUnion = (closing == ')');
        unsigned memberSize;
        unsigned memberAlign;
        unsigned offset = 0;
        BOOL memberIsBitfield;
        const char *aggregateStart = typePtr;
#if defined(__ppc__) || defined(__POWERPC__)
        BOOL firstMember = YES;
        unsigned doubleAlign = sizeof(int);
#endif

        align = 1;
        typePtr++;
        while (*typePtr != '\0' && *typePtr != '=' && *typePtr != closing)
            typePtr++;
        if (*typePtr == closing) {
            typePtr++;
            if (sizep != 0 || alignp != 0)
                [NSException raise:NSInvalidArgumentException
                            format:@"can't determine size of struct/union (inadequate ObjC runtime information) for: %s (forward use?)",
                                  aggregateStart];
            break;
        }
        if (*typePtr == '\0')
            [NSException raise:NSInvalidArgumentException
                        format:@"can't determine size of struct/union: %s (parsing error)",
                              aggregateStart];
        else
            typePtr++;

        while (*typePtr != '\0' && *typePtr != closing) {
#if defined(__ppc__) || defined(__POWERPC__)
            BOOL memberIsDouble = NO;
#endif
            memberIsBitfield = (*typePtr == 'b');
            if (memberIsBitfield) {
                memberSize = NSBitfieldSizeAndAdvance(&typePtr, &memberAlign,
                                                     offset);
            } else {
#if defined(__ppc__) || defined(__POWERPC__)
                const char *alignmentType = typePtr;

                while (*alignmentType == 'N' || *alignmentType == 'O' ||
                       *alignmentType == 'R' || *alignmentType == 'V' ||
                       *alignmentType == 'n' || *alignmentType == 'o' ||
                       *alignmentType == 'r')
                    alignmentType++;
                memberIsDouble = (*alignmentType == 'd');
                if (memberIsDouble) {
                    if (firstMember)
                        doubleAlign = 8;
                    typePtr = NSSizeAndAlignmentOfType(typePtr, &memberSize, 0);
                    memberAlign = doubleAlign;
                } else {
                    typePtr = NSSizeAndAlignmentOfType(typePtr, &memberSize,
                                                       &memberAlign);
                }
#else
                typePtr = NSSizeAndAlignmentOfType(typePtr, &memberSize,
                                                   &memberAlign);
#endif
            }
            if (!memberIsBitfield && memberAlign != 0 &&
                (offset % memberAlign) != 0)
                offset += memberAlign - (offset % memberAlign);
            offset += memberSize;
#if defined(__ppc__) || defined(__POWERPC__)
            firstMember = NO;
#endif
            if (memberAlign > align)
                align = memberAlign;
            if (isUnion) {
                if (!memberIsBitfield && memberSize > size)
                    size = memberSize;
            } else {
                size = offset;
            }
        }
        typePtr++;
        if (!isUnion && align != 0 && (size % align) != 0)
            size += align - (size % align);
        break;
    }
    default:
        if (*typePtr != '\0')
            typePtr++;
        break;
    }

    if (sizep != 0)
        *sizep = size;
    if (alignp != 0)
        *alignp = align;

    return typePtr;
}

const char *
NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)
{
    return NSSizeAndAlignmentOfType(typePtr, sizep, alignp);
}

/*	The reference exports a second, private entry point alongside the
	public one (__NSGetSizeAndAlignment beside _NSGetSizeAndAlignment).
	No header declares it and no caller in this stage's modules reaches
	it; both walk the same encodings, so this shares the implementation
	rather than guessing at a difference the disassembly does not show.
	Recorded in divergences.md.  */
const char *
_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp)
{
    return NSGetSizeAndAlignment(typePtr, sizep, alignp);
}

/* Prefix the process identity and write the formatted message to stderr. */
void
_NSBasicStdErrLog(const char *format, ...)
{
    char *buffer;
    va_list arguments;
    char *processName;
    int processID;
    unsigned prefixLength;
    size_t length;

    va_start(arguments, format);
    buffer = NSZoneMalloc(NULL, 1024);
#if defined(__ppc__) || defined(__POWERPC__)
    processName = _NSProcessName();
    processID = _NSProcessID();
#else
    processID = _NSProcessID();
    processName = _NSProcessName();
#endif
    _NSsnprintf(buffer, 1024, "%s[%d] ", processName, processID);
    prefixLength = (unsigned)strlen(buffer);
#if defined(__ppc__) || defined(__POWERPC__)
    _NSvsnprintf(buffer + prefixLength, 1024 - prefixLength, format,
                 arguments);
#else
    vsnprintf(buffer + prefixLength, 1024 - prefixLength, format, arguments);
#endif
    va_end(arguments);
    length = strlen(buffer);
    _NSWriteToFileDescriptor(2, buffer, length);
    NSZoneFree(NULL, buffer);
}

typedef int (*NSLogCStringFunction)(const char *bytes, unsigned length,
                                    char display);

static int
NSDefaultLogCString(const char *bytes, unsigned length, char display)
{
    NSProcessInfo *processInfo;
    NSString *processName;
    NSString *message;
    NSString *date;
    const char *processNameBytes;
    char *messageBytes;
    unsigned messageLength;
    int processID;
    BOOL writeFailed;

    if (bytes == NULL || length > 0x3fffffffU)
        return 0;
    processInfo = [NSProcessInfo processInfo];
    processName = [processInfo processName];
    processNameBytes = [processName cString];
    if (_NSLogLock != nil)
        [_NSLogLock lock];
    ++NSLocalizeLogDate;
    if (display) {
        if (NSLocalizeLogDate == 1) {
#if defined(__ppc__) || defined(__POWERPC__)
            date = [[NSDate date]
                descriptionWithCalendarFormat:@"%b %d %H:%M:%S" locale:nil];
            processID = _NSProcessID();
#else
            processID = _NSProcessID();
            date = [[NSDate date]
                descriptionWithCalendarFormat:@"%b %d %H:%M:%S" locale:nil];
#endif
            message = [NSString stringWithFormat:
                @"%@ %s[%d] %s  ", date, processNameBytes, processID, bytes];
        } else {
            time_t now = _NSCurrentUNIXTime();
            char *date = ctime(&now);

            date += 4;
            date[15] = '\0';
            processID = _NSProcessID();
            message = [NSString stringWithFormat:
                @"%s %s[%d] %s  ", date, processNameBytes, processID, bytes];
        }
    } else {
        message = [NSString stringWithFormat:@"%s  ", bytes];
    }
    messageBytes = (char *)[message cString];
    messageLength = (unsigned)strlen(messageBytes);
    if (messageBytes[messageLength - 3] != '\n') {
        messageBytes[messageLength - 2] = '\n';
        messageLength--;
    } else
        messageLength -= 2;
    messageBytes[messageLength] = '\0';
    writeFailed = fcntl(2, F_GETFL) == -1;
    if (!writeFailed)
        writeFailed = _NSWriteToFileDescriptor(2, messageBytes,
                                               messageLength) == -1;
    if (writeFailed) {
        openlog(processNameBytes, LOG_PID | LOG_CONS, LOG_USER);
        syslog(LOG_ERR, "%s", bytes);
        closelog();
    }
    --NSLocalizeLogDate;
    if (_NSLogLock != nil)
        [_NSLogLock unlock];
    return 0;
}

static NSLogCStringFunction NSLogCStringSink = NSDefaultLogCString;

NSLogCStringFunction
_NSLogCStringFunction(void)
{
    return NSLogCStringSink;
}

NSLogCStringFunction
_NSSetLogCStringFunction(NSLogCStringFunction function)
{
    if (function == NULL)
        NSLogCStringSink = NSDefaultLogCString;
    else
        NSLogCStringSink = function;
    return function;
}

void
NSLogv(NSString *format, va_list args)
{
    unsigned pool;
    NSString *message;
    const char *bytes;
    unsigned length;
    NSLogCStringFunction logFunction;

    if (format == nil)
        return;
    pool = NSPushAutoreleasePool();
    message = [[NSString allocWithZone:NULL]
        initWithFormat:format locale:nil arguments:args];
    message = [message autorelease];
    bytes = [[message displayableString] lossyCString];
    length = (unsigned)strlen(bytes);
    logFunction = _NSLogCStringFunction();
    logFunction(bytes, length, 1);
    NSPopAutoreleasePool(pool);
}

void
NSLog(NSString *format, ...)
{
    va_list args;

    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}

/*	Introspection helpers the reference exports but no header declares.
	NSObject.m and NSProxy.m both call them directly (extern declarations
	in each), which is why they live here rather than in either: this
	module is the runtime's general-utility home, and both callers link
	against it.  Claimed by name in reconstruction/symbols.json.  */

extern id _objc_msgForward(id self, SEL op, ...);
extern IMP class_lookupMethod(Class aClass, SEL aSelector);
extern struct objc_method_list *class_nextMethodList(Class aClass,
                                                       void **cursor);

/*	The implementation aClass would run for aSelector, or the runtime's
	forwarding trampoline when it has none -- the sentinel
	-[NSObject implementsSelector:] compares against, rather than a null
	a caller might mistake for an error.  */
IMP
_NSIMPForSelector(Class aClass, SEL aSelector)
{
    return class_lookupMethod(aClass, aSelector);
}

IMP
_NSIMPForObjectAndSelector(id object, SEL aSelector)
{
    IMP implementation = class_lookupMethod(*(Class *)object, aSelector);

    return implementation == (IMP)_objc_msgForward
        ? (IMP)objc_msgSend : implementation;
}

IMP
_NSImplementationForObjectAndSelector(id object, const char *selectorName)
{
    SEL aSelector = sel_registerName(selectorName);
    IMP implementation = class_lookupMethod(*(Class *)object, aSelector);

    return implementation == (IMP)_objc_msgForward ? (IMP)0 : implementation;
}

NSString *
_NSFullMethodName(id object, char *selectorName)
{
    char buffer[1024];
    Class objectClass = *(Class *)object;

    strcpy(buffer, object == [object class] ? "+[" : "-[");
    strcat(buffer, objectClass->name);
    strcat(buffer, " ");
    strcat(buffer, selectorName);
    strcat(buffer, "]");
    return [NSString stringWithCString:buffer length:strlen(buffer)];
}

/*	The selector and type encoding of aClass's implementation, or NULL
	when it has none.  struct objc_method's first two fields are
	layout-compatible with struct objc_method_description (objc-class.h
	against objc/Protocol.h), which is how the runtime itself hands one
	out as the other.  */
struct objc_method_description *
_NSMethodDescriptionForSelector(Class aClass, SEL aSelector)
{
    Class candidate;

    for (candidate = aClass; candidate != Nil;
         candidate = candidate->super_class) {
        if (candidate->isa->version > 2) {
            struct objc_protocol_list *protocols = candidate->protocols;

            while (protocols != NULL) {
                int index;

                for (index = 0; index < protocols->count; index++) {
                    struct objc_method_description *description;

                    if ((candidate->info & CLS_META) != 0)
                        description = [protocols->list[index]
                            descriptionForClassMethod:aSelector];
                    else
                        description = [protocols->list[index]
                            descriptionForInstanceMethod:aSelector];
                    if (description != NULL)
                        return description;
                }
                if (candidate->isa->version <= 4)
                    break;
                protocols = protocols->next;
            }
        }
    }

    for (candidate = aClass; candidate != Nil;
         candidate = candidate->super_class) {
        void *cursor = NULL;
        struct objc_method_list *methods;

        while ((methods = class_nextMethodList(candidate, &cursor)) != NULL) {
            int index;

            for (index = 0; index < methods->method_count; index++) {
                if (methods->method_list[index].method_name == aSelector)
                    return (struct objc_method_description *)
                        &methods->method_list[index];
            }
        }
    }

    return NULL;
}

/*	Whether aClass, or anything it inherits from, adopts aProtocol.
	This runtime has no class_conformsTo entry point, so the walk up
	super_class is done directly over each class's protocols list --
	conformance is inherited, and a caller asking "does this class
	conform" means the whole chain.  */
BOOL
_NSClassConformsToProtocol(Class aClass, Protocol *aProtocol)
{
    Class candidate;

    if (aClass == Nil)
        return NO;

    for (candidate = aClass; candidate != Nil; candidate = candidate->super_class) {
        struct objc_protocol_list *protocols;

        for (protocols = candidate->protocols; protocols != 0; protocols = protocols->next) {
            int index;

            for (index = 0; index < protocols->count; index++) {
                if ([protocols->list[index] conformsTo:aProtocol])
                    return YES;
            }
        }
    }

    return NO;
}

/*	NSDetailedDescription is present in the reference metadata but has no
	public declaration in this tree.  Its two methods are kept local to this
	module and claimed by name in reconstruction/symbols.json.  */

struct NSProtocolDescriptionStorage {
    Class isa;
    char *name;
    struct objc_protocol_list *protocols;
    struct objc_method_description_list *instanceMethods;
    struct objc_method_description_list *classMethods;
};

@interface Protocol (NSDetailedDescription)
- (NSString *)detailedDescription;
@end

@implementation Protocol (NSDetailedDescription)

- (NSString *)detailedDescription
{
    struct NSProtocolDescriptionStorage *storage =
        (struct NSProtocolDescriptionStorage *)self;
    NSMutableString *description =
        [NSMutableString stringWithCapacity:300];
    struct objc_protocol_list *protocols = storage->protocols;
    struct objc_method_description_list *methods;
    int index;

    [description appendFormat:@"Protocol: %s  self:%x\n", storage->name,
                              self];
    if (protocols != NULL) {
        for (index = protocols->count - 1; index >= 0; index--) {
            Protocol *protocol = protocols->list[index];

            [description appendFormat:@" %s %x", [protocol name], protocol];
        }
        [description appendString:@"\n"];
    }

    methods = storage->instanceMethods;
    if (methods != NULL) {
        for (index = methods->count - 1; index >= 0; index--) {
            struct objc_method_description *method = &methods->list[index];

            [description appendFormat:@"-sel:%s %x types:%s\n",
                                      method->name, method->name,
                                      method->types];
        }
        [description appendString:@"\n"];
    }

    methods = storage->classMethods;
    if (methods != NULL) {
        for (index = methods->count - 1; index >= 0; index--) {
            struct objc_method_description *method = &methods->list[index];

            [description appendFormat:@"+sel:%s %x types:%s\n",
                                      method->name, method->name,
                                      method->types];
        }
        [description appendString:@"\n"];
    }
    [description appendString:@"\n"];
    return description;
}

@end

@interface NSObject (NSDetailedDescription)
+ (NSString *)detailedDescriptionForClass:(Class)aClass;
@end

@implementation NSObject (NSDetailedDescription)

+ (NSString *)detailedDescriptionForClass:(Class)aClass
{
    NSMutableString *description =
        [NSMutableString stringWithCapacity:300];
    char methodKind = (aClass->info & 2) != 0 ? '+' : '-';
    void *cursor = NULL;
    struct objc_method_list *methods;
    int index;

    [description appendFormat:
        @"Class: %s version %d isize: %d self:%x super:%x isa:%x info:",
        aClass->name, aClass->version, aClass->instance_size, aClass,
        aClass->super_class, aClass->isa];
    if ((aClass->info & 1) != 0)
        [description appendString:@" CLASS"];
    if ((aClass->info & 2) != 0)
        [description appendString:@" META"];
    if ((aClass->info & 4) != 0)
        [description appendString:@" INITIALIZED"];
    if ((aClass->info & 8) != 0)
        [description appendString:@" POSING"];
    if ((aClass->info & 0x10) != 0)
        [description appendString:@" MAPPED"];
    if ((aClass->info & 0x20) != 0)
        [description appendString:@" FLUSH_CACHE"];
    [description appendString:@"\n"];

    if (aClass->protocols != NULL) {
        [description appendString:@"conforms to Protocols:"];
        for (index = aClass->protocols->count - 1; index >= 0; index--) {
            Protocol *protocol = aClass->protocols->list[index];

            [description appendFormat:@" %s %x", [protocol name], protocol];
        }
        [description appendString:@"\n"];
    }

    while ((methods = class_nextMethodList(aClass, &cursor)) != NULL) {
        for (index = methods->method_count - 1; index >= 0; index--) {
            struct objc_method *method = &methods->method_list[index];

            [description appendFormat:
                @"%csel:%s %x types:%s implementation:%x\n",
                methodKind, method->method_name, method->method_name,
                method->method_types, method->method_imp];
        }
        [description appendString:@"\n"];
    }
    [description appendString:@"\n"];

    if (aClass->super_class != NULL && aClass->super_class != aClass) {
        NSString *superDescription =
            [self detailedDescriptionForClass:aClass->super_class];

        [description appendFormat:@"%@\n", superDescription];
    }
    return description;
}

@end
