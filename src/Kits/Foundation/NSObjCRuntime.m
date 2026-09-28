/*	NSObjCRuntime.m
	Language terminology and general utility
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <objc/objc-runtime.h>
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

const char *NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp) {
    // TODO: Implement this function
    return NULL;
}

void NSLog(NSString *format, ...) {
    // TODO: Implement this function
}

void NSLogv(NSString *format, va_list args) {
    // TODO: Implement this function
}
