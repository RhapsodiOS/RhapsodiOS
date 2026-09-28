/*	NSObjCRuntime.m
	Language terminology and general utility
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/objc-runtime.h>
#import <objc/Protocol.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

/*	Stage 2b has no NSString: NSString.m is stage 3.  What it does have is
	the layout the compiler already emits for every `@"..."` literal --
	this project's Objective-C frontend (src/cc-1/cc/objc/NXConstStr.h)
	lays one out as { Class isa; char *c_string; unsigned int len; }, with
	isa pointing at _NSConstantStringClassReference.  The two helpers below
	read and build that shape, so the four conversion functions can return
	and accept something a caller treats as a string, and so a test can read
	the result back.  Stage 3 replaces both with real NSString instances
	and -cString/+stringWithCString:length:; the exported ABI does not move
	when it does.  */

typedef struct {
    Class	isa;
    char	*c_string;
    unsigned	len;
} NSObjCRuntimeStringRecord;

/*	NSString.h declares this symbol `extern void *`; that header is this
	file's declaration of record for it, so the record builder below casts
	its address rather than re-declaring it with a struct type that would
	conflict.  */

static const char *
_NSObjCRuntimeStringBytes(NSString *string)
{
    if (string == nil)
        return NULL;
    return ((NSObjCRuntimeStringRecord *)string)->c_string;
}

static NSString *
_NSObjCRuntimeStringWithCString(const char *bytes)
{
    NSObjCRuntimeStringRecord *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = (NSObjCRuntimeStringRecord *)
        NSZoneMalloc(0, sizeof(NSObjCRuntimeStringRecord) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (NSString *)record;
}

NSString *
NSStringFromSelector(SEL aSelector)
{
    if (aSelector == NULL)
        return nil;
    return _NSObjCRuntimeStringWithCString(sel_getName(aSelector));
}

SEL
NSSelectorFromString(NSString *aSelectorName)
{
    const char *bytes = _NSObjCRuntimeStringBytes(aSelectorName);

    if (bytes == NULL)
        return NULL;
    return sel_registerName(bytes);
}

Class
NSClassFromString(NSString *aClassName)
{
    const char *bytes = _NSObjCRuntimeStringBytes(aClassName);

    if (bytes == NULL)
        return Nil;
    return objc_lookUpClass(bytes);
}

NSString *
NSStringFromClass(Class aClass)
{
    if (aClass == Nil)
        return nil;
    return _NSObjCRuntimeStringWithCString(aClass->name);
}

/*	Walks one type encoding and reports its size and alignment, returning
	a pointer just past the encoding it consumed -- so a caller can step
	through a whole method signature by feeding the return value back in.
	Sizes are this architecture's, taken from the compiler rather than
	assumed: gcc 2.7.2.1 on i386 gives int/long/pointer 4, short 2,
	char 1, float 4, double 8, long long 8.

	A struct's size is its members laid out in order, each padded up to
	its own alignment, with the whole padded up to the widest member's
	alignment; a union's is its widest member.  Qualifier prefixes
	(const, in, out, inout, bycopy, byref, oneway) carry no size and are
	skipped.  */
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
    align = 1;

    switch (*typePtr) {
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
    case 'B':
        size = sizeof(char); align = size; typePtr++; break;
    case 'v':
        size = 0; align = 1; typePtr++; break;
    case '*': case '@': case '#': case ':':
        size = sizeof(void *); align = size; typePtr++; break;
    case '?':
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
        if (*typePtr == ']')
            typePtr++;
        size = count * elementSize;
        align = elementAlign;
        break;
    }
    case '{': case '(': {
        char closing = (*typePtr == '{') ? '}' : ')';
        BOOL isUnion = (closing == ')');
        unsigned memberSize;
        unsigned memberAlign;

        typePtr++;
        while (*typePtr != '\0' && *typePtr != '=' && *typePtr != closing)
            typePtr++;
        if (*typePtr == '=')
            typePtr++;

        while (*typePtr != '\0' && *typePtr != closing) {
            typePtr = NSSizeAndAlignmentOfType(typePtr, &memberSize, &memberAlign);
            if (memberAlign > align)
                align = memberAlign;
            if (isUnion) {
                if (memberSize > size)
                    size = memberSize;
            } else {
                if (memberAlign != 0 && (size % memberAlign) != 0)
                    size += memberAlign - (size % memberAlign);
                size += memberSize;
            }
        }
        if (*typePtr == closing)
            typePtr++;
        if (align != 0 && (size % align) != 0)
            size += align - (size % align);
        break;
    }
    case 'b': {
        /*  A bitfield: bN, N bits.  Reported as the bits it occupies,
            which is what the runtime's own walkers do with it.  */
        unsigned bits = 0;

        typePtr++;
        while (*typePtr >= '0' && *typePtr <= '9')
            bits = (bits * 10) + (unsigned)(*typePtr++ - '0');
        size = (bits + 7) / 8;
        align = 1;
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
    if (typePtr == NULL)
        return NULL;
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

/*	The one place this module writes a finished log line.  The reference
	exports this symbol and routes its logging through it; keeping that
	shape means the later stages that add timestamping or a syslog route
	have one function to change rather than two.  */
void
_NSBasicStdErrLog(const char *message)
{
    if (message == NULL)
        return;
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}

/*	Formats `format` over `args` and hands the result to
	_NSBasicStdErrLog.  Stage 2b has no NSString, so this walks the
	format's own bytes and rebuilds a C format string as it goes,
	substituting %@ (whose argument is another NXConstantString-shaped
	record in this stage, see the helpers at the top of this file) with
	that record's bytes.  Every other specifier is handed to vsnprintf
	unchanged.

	PROVISIONAL: this covers the specifiers this stage's own callers use
	(%@, %s, %d, %u, %x, %c, %%) and no more.  Stage 3 replaces it with
	real NSString formatting.  Recorded in divergences.md.  */

#define NSLogMessageMax 1024

void
NSLogv(NSString *format, va_list args)
{
    const char *bytes;
    char message[NSLogMessageMax];
    unsigned out;
    unsigned i;

    bytes = _NSObjCRuntimeStringBytes(format);
    if (bytes == NULL)
        return;

    out = 0;
    i = 0;
    while (bytes[i] != '\0' && out < NSLogMessageMax - 1) {
        if (bytes[i] != '%') {
            message[out++] = bytes[i++];
            continue;
        }

        if (bytes[i + 1] == '%') {
            message[out++] = '%';
            i += 2;
            continue;
        }

        if (bytes[i + 1] == '@') {
            id object = va_arg(args, id);
            const char *text = _NSObjCRuntimeStringBytes((NSString *)object);

            if (text == NULL)
                text = "(null)";
            while (*text != '\0' && out < NSLogMessageMax - 1)
                message[out++] = *text++;
            i += 2;
            continue;
        }

        {
            /*  Copy this one specifier out and let vsprintf do it, so
                the platform's own conversions apply rather than a
                hand-rolled imitation of them.  */
            char specifier[16];
            char converted[NSLogMessageMax];
            unsigned length = 0;

            specifier[length++] = bytes[i++];
            while (bytes[i] != '\0' && length < sizeof(specifier) - 1) {
                specifier[length++] = bytes[i];
                if (strchr("diouxXeEfgGcsp", bytes[i]) != NULL) {
                    i++;
                    break;
                }
                i++;
            }
            specifier[length] = '\0';

            converted[0] = '\0';
            vsprintf(converted, specifier, args);
            /*  vsprintf consumed exactly one argument for this
                specifier; step args past it by re-reading the same
                width the specifier implies.  */
            if (strchr(specifier, 's') != NULL)
                (void)va_arg(args, char *);
            else if (strchr(specifier, 'f') != NULL ||
                     strchr(specifier, 'e') != NULL ||
                     strchr(specifier, 'g') != NULL)
                (void)va_arg(args, double);
            else
                (void)va_arg(args, int);

            {
                unsigned k = 0;

                while (converted[k] != '\0' && out < NSLogMessageMax - 1)
                    message[out++] = converted[k++];
            }
        }
    }
    message[out] = '\0';

    _NSBasicStdErrLog(message);
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

/*	The implementation aClass would run for aSelector, or the runtime's
	forwarding trampoline when it has none -- the sentinel
	-[NSObject implementsSelector:] compares against, rather than a null
	a caller might mistake for an error.  */
IMP
_NSIMPForSelector(Class aClass, SEL aSelector)
{
    struct objc_method *method;

    if (aClass == Nil || aSelector == NULL)
        return (IMP)_objc_msgForward;

    method = class_getInstanceMethod(aClass, aSelector);
    if (method == NULL)
        return (IMP)_objc_msgForward;

    return method->method_imp;
}

/*	The selector and type encoding of aClass's implementation, or NULL
	when it has none.  struct objc_method's first two fields are
	layout-compatible with struct objc_method_description (objc-class.h
	against objc/Protocol.h), which is how the runtime itself hands one
	out as the other.  */
struct objc_method_description *
_NSMethodDescriptionForSelector(Class aClass, SEL aSelector)
{
    struct objc_method *method;

    if (aClass == Nil || aSelector == NULL)
        return NULL;

    method = class_getInstanceMethod(aClass, aSelector);
    if (method == NULL)
        return NULL;

    return (struct objc_method_description *)method;
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

    if (aClass == Nil || aProtocol == nil)
        return NO;

    for (candidate = aClass; candidate != Nil; candidate = candidate->super_class) {
        struct objc_protocol_list *protocols;

        for (protocols = candidate->protocols; protocols != 0; protocols = protocols->next) {
            int index;

            for (index = 0; index < protocols->count; index++) {
                if (protocols->list[index] == aProtocol)
                    return YES;
            }
        }
    }

    return NO;
}

/*	NSDetailedDescription: two diagnostic categories the reference's
	__OBJC metadata carries but that no header in this tree declares, so
	both are declared here, the only place that implements them, and
	claimed by name in reconstruction/symbols.json.  The reference's exact
	output text is outside this stage's published analysis scope; what is
	reconstructed is the observable shape -- the name, and the methods it
	carries.  Recorded in divergences.md.  */

@interface Protocol (NSDetailedDescription)
- (NSString *)detailedDescription;
@end

@implementation Protocol (NSDetailedDescription)

- (NSString *)detailedDescription
{
    return _NSObjCRuntimeStringWithCString([self name]);
}

@end

@interface NSObject (NSDetailedDescription)
+ (NSString *)detailedDescriptionForClass:(Class)aClass;
@end

@implementation NSObject (NSDetailedDescription)

+ (NSString *)detailedDescriptionForClass:(Class)aClass
{
    char buffer[256];

    if (aClass == Nil)
        return nil;

    strncpy(buffer, aClass->name, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';

    return _NSObjCRuntimeStringWithCString(buffer);
}

@end
