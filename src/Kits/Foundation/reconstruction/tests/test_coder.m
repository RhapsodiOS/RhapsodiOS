/*  Behavioural tests for NSCoder, stage 2c.  NSCoder itself has zero
    ivars in the reference (instance_size 4) -- its five primitives have
    compiled bodies but nowhere to store anything, so they raise
    "subclass responsibility" (the reference's reason literal,
    "<method>: subclass should override ...", read from
    __OBJC,__cstring_object).  TestCoder below is this stage's own
    minimal concrete backing: an in-memory array of {type, bytes}
    entries, written and read back in order.  Every later coding test in
    this stage (NSCoder's own concrete methods, NSInvocation's
    -encodeWithCoder:/-initWithCoder:) uses this same class.  */

#import <Foundation/NSCoder.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

#define TestCoderCapacity 64

typedef struct {
    char type[16];
    char bytes[64];
    unsigned length;
} TestCoderEntry;

@interface TestCoder : NSCoder
{
    TestCoderEntry entries[TestCoderCapacity];
    unsigned writeIndex;
    unsigned readIndex;
    NSZone *zone;
}
@end

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

static void test_a_subclass_can_override_the_five_primitives(void)
{
    id coder = [[TestCoder alloc] init];
    int written = 42;
    int read = 0;

    [coder encodeValueOfObjCType:"i" at:&written];
    [coder decodeValueOfObjCType:"i" at:&read];
    CHECK(read == 42);
    [coder release];
}

static void test_the_base_class_primitives_raise(void)
{
    id coder = [[NSCoder alloc] init];
    int value = 1;
    int caught = 0;

    NS_DURING
        [coder encodeValueOfObjCType:"i" at:&value];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

/*  Review Focus item 3: a NULL type string.  The base class raises
    regardless of type -- it never reads `type` before raising -- so
    this is already well-defined; this test pins that rather than
    assuming it.  */
static void test_the_base_class_primitives_raise_even_with_a_null_type(void)
{
    id coder = [[NSCoder alloc] init];
    int value = 1;
    int caught = 0;

    NS_DURING
        [coder encodeValueOfObjCType:NULL at:&value];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

/*  Review Focus item 3: a type/data mismatch between the encode and
    the matching decode call.  TestCoder records the type it was given
    at encode time and checks the decode call's own type against it,
    raising on a mismatch rather than silently copying the wrong number
    of bytes.  */
static void test_decoding_with_a_type_that_does_not_match_the_encoded_one_raises(void)
{
    id coder = [[TestCoder alloc] init];
    int written = 42;
    double readBack;
    int caught = 0;

    [coder encodeValueOfObjCType:"i" at:&written];

    NS_DURING
        [coder decodeValueOfObjCType:"d" at:&readBack];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
    [coder release];
}

static void test_versionForClassName_and_object_zone_round_trip(void)
{
    id coder = [[TestCoder alloc] init];

    CHECK([coder versionForClassName:@"Anything"] == 0);
    [coder setObjectZone:NSDefaultMallocZone()];
    CHECK([coder objectZone] == NSDefaultMallocZone());
    [coder release];
}

static void test_encodeObject_and_decodeObject_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeObject:sent];
    received = [coder decodeObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeConditionalObject_round_trips_like_encodeObject(void)
{
    /*  NSCoder's own base implementation of -encodeConditionalObject:
        (conditional-object graph tracking) is real NSArchiver machinery
        this stage does not have; the reference's generic NSCoder-level
        fallback, confirmed from the disassembly, is to encode it the
        same as -encodeObject: unconditionally -- a real coder overrides
        this to actually track conditionality.  */
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeConditionalObject:sent];
    received = [coder decodeObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeArrayOfObjCType_and_decode_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    int sent[3] = { 1, 2, 3 };
    int received[3] = { 0, 0, 0 };

    [coder encodeArrayOfObjCType:"i" count:3 at:sent];
    [coder decodeArrayOfObjCType:"i" count:3 at:received];
    CHECK(received[0] == 1 && received[1] == 2 && received[2] == 3);
    [coder release];
}

static void test_encodeValuesOfObjCTypes_and_decode_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    int intValue = 7;
    char charValue = 'x';
    int readInt = 0;
    char readChar = 0;

    [coder encodeValuesOfObjCTypes:"ic", intValue, charValue];
    [coder decodeValuesOfObjCTypes:"ic", &readInt, &readChar];
    CHECK(readInt == 7);
    CHECK(readChar == 'x');
    [coder release];
}

static void test_encodeBytes_and_decodeBytesWithReturnedLength_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    const char *sent = "hello";
    unsigned returnedLength = 0;
    void *received;

    [coder encodeBytes:sent length:5];
    received = [coder decodeBytesWithReturnedLength:&returnedLength];
    CHECK(returnedLength == 5);
    CHECK(memcmp(received, sent, 5) == 0);
    [coder release];
}

static void test_systemVersion_is_the_confirmed_constant(void)
{
    /*  Confirmed from the reference's raw bytes at 0x4257385c:
        mov eax, 0x3e8 -- 1000, the coding format revision the
        typedstream machinery identifies itself with.  */
    id coder = [[NSCoder alloc] init];

    CHECK([coder systemVersion] == 1000);
    [coder release];
}

static void test_encodePropertyList_and_decodePropertyList_round_trip_a_string(void)
{
    /*  With no real NSString/NSDictionary/NSArray yet, this test's
        "property list" is the one shape TestCoder's primitives already
        carry end to end: an object reference.  A future stage with real
        collection classes should extend this test to a nested
        dictionary/array.  */
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodePropertyList:sent];
    received = [coder decodePropertyList];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_encodeNXObject_and_decodeNXObject_round_trip(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeNXObject:sent];
    received = [coder decodeNXObject];
    CHECK(received == sent);
    [sent release];
    [coder release];
}

static void test_NXReadNSObjectFromCoder_matches_decodeObject(void)
{
    id coder = [[TestCoder alloc] init];
    id sent = [[NSObject alloc] init];
    id received;

    [coder encodeObject:sent];
    received = NXReadNSObjectFromCoder(coder);
    CHECK(received == sent);
    [sent release];
    [coder release];
}

int main(void)
{
    /*  The guest's stdio block-buffers pipes; a crash mid-suite would
        otherwise swallow every FAIL line printed before it.  */
    setvbuf(stdout, NULL, _IONBF, 0);

    test_a_subclass_can_override_the_five_primitives();
    test_the_base_class_primitives_raise();
    test_the_base_class_primitives_raise_even_with_a_null_type();
    test_decoding_with_a_type_that_does_not_match_the_encoded_one_raises();
    test_versionForClassName_and_object_zone_round_trip();
    test_encodeObject_and_decodeObject_round_trip();
    test_encodeConditionalObject_round_trips_like_encodeObject();
    test_encodeArrayOfObjCType_and_decode_round_trip();
    test_encodeValuesOfObjCTypes_and_decode_round_trip();
    test_encodeBytes_and_decodeBytesWithReturnedLength_round_trip();
    test_systemVersion_is_the_confirmed_constant();
    test_encodePropertyList_and_decodePropertyList_round_trip_a_string();
    test_encodeNXObject_and_decodeNXObject_round_trip();
    test_NXReadNSObjectFromCoder_matches_decodeObject();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
