/*  TestCoder.m -- the implementation extracted from test_coder.m
    (Task 2 Step 2, unchanged).  See TestCoder.h for the contract.  */

#import "TestCoder.h"
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <string.h>

@implementation TestCoder

- (id)init
{
    self = [super init];
    writeIndex = 0;
    readIndex = 0;
    zone = NULL;
    return self;
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr
{
    TestCoderEntry *entry = &entries[writeIndex++];
    unsigned size, align;

    NSGetSizeAndAlignment(type, &size, &align);
    strncpy(entry->type, type, sizeof(entry->type) - 1);
    entry->type[sizeof(entry->type) - 1] = '\0';
    memcpy(entry->bytes, addr, size);
    entry->length = size;
}

/*  Raises on a type mismatch against what was actually encoded, rather
    than silently copying the wrong number of bytes -- TestCoder is test
    scaffolding, not a shipped coder, and a caller decoding as the wrong
    type is a test bug worth catching loudly, not undefined behaviour.  */
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data
{
    TestCoderEntry *entry = &entries[readIndex++];

    if (type == NULL || strcmp(type, entry->type) != 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"TestCoder: decode type does not match the encoded type"];
        return;
    }
    memcpy(data, entry->bytes, entry->length);
}

- (void)encodeDataObject:(NSData *)data
{
    [NSException raise:NSInvalidArgumentException
                format:@"TestCoder: NSData not reconstructed"];
}

- (NSData *)decodeDataObject
{
    [NSException raise:NSInvalidArgumentException
                format:@"TestCoder: NSData not reconstructed"];
    return nil;
}

- (unsigned)versionForClassName:(NSString *)className
{
    return 0;
}

- (void)setObjectZone:(NSZone *)aZone
{
    zone = aZone;
}

- (NSZone *)objectZone
{
    return zone;
}

@end
