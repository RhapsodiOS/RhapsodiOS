/*  Behavioural tests for NSMethodSignature, stage 2c.

    Every signature string below is one this toolchain actually emits,
    captured by probe on the guest (probe-encoding.m, this stage's
    journal): "v12@8:12@16" is a void method taking one object,
    "i12@8:12i16" is an int method taking one int, "d8@8:12" is a
    double-returning method with no extra arguments.  The layout is
    <return type><digits><arg type><digits>...  where the digits are
    position annotations this platform's runtime carries but neither
    objc-runtime's method_getSizeOfArguments nor the reference's
    +signatureWithObjCTypes: reads back as offsets -- frameLength is
    the sum of each argument's size rounded up to 4, and the offsets
    run 0/4/8..., both measured from the reference constructor's fill
    loop (journal, Task 1 Step 1).

    The accessor expectations are the reference's own semantics:
    -methodReturnType and -getArgumentTypeAtIndex: return exactly the
    span NSGetSizeAndAlignment consumes (one type token), -isOneway
    tests the first byte for the 'V' qualifier, and an out-of-range
    -getArgumentTypeAtIndex: raises NSInvalidArgumentException with
    "<method name>: index out of bounds" rather than returning NULL.  */

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSException.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <string.h>

/*  The by-value entry shape -_argumentInfoAtIndex: returns (identical
    to NSMethodSignature.m's own file-local definition -- no shared
    header declares it).  Declared at file scope so the casts below
    convert an id into the real struct type rather than relying on the
    method's declared return type (the guest cc1obj rejects a cast to
    a locally scoped struct tag).  */
struct NSMethodSignatureArgumentInfo {
    unsigned int offset;
    unsigned int size;
    const char *type;
    unsigned int unused0;
    unsigned int unused1;
};

@interface NSMethodSignature (TestArgumentInfo)
- (struct NSMethodSignatureArgumentInfo)_argumentInfoAtIndex:(unsigned)index;
@end

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  Stage 2b strings are NXConstantString-shaped records
    { Class isa; char *c_string; unsigned int len; } -- the same shape
    test_proxy.m reads for raise reasons.  */
static const char *
StringBytes(NSString *string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record =
        (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

static void
test_frameLength_and_argument_count_for_a_simple_selector(void)
{
    /*  "v12@8:12@16" -- void return, self, _cmd, one object argument.
        frameLength = round4(4) + round4(4) + round4(4) = 12, which for
        canonical toolchain encodings agrees with the leading digits.  */
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];

    CHECK(sig != nil);
    CHECK([sig numberOfArguments] == 3);
    CHECK([sig frameLength] == 12);
    CHECK(strcmp([sig methodReturnType], "v") == 0);
    CHECK([sig methodReturnLength] == 0);
    CHECK(![sig isOneway]);
}

static void
test_getArgumentTypeAtIndex_reports_self_cmd_and_each_argument(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i12@8:12i16"];

    CHECK(strcmp([sig getArgumentTypeAtIndex:0], "@") == 0);
    CHECK(strcmp([sig getArgumentTypeAtIndex:1], ":") == 0);
    CHECK(strcmp([sig getArgumentTypeAtIndex:2], "i") == 0);
}

static void
test_methodReturnLength_for_a_nonvoid_return(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"i12@8:12i16"];

    CHECK(strcmp([sig methodReturnType], "i") == 0);
    CHECK([sig methodReturnLength] == 4);
}

static void
test_struct_return_classification(void)
{
    /*  {_NSRange=II}: 8 bytes.  The reference's
        -_isReturnStructInRegisters (disassembled, 56 bytes at
        0x42574520) answers YES only for struct returns of size
        1, 2, 4 or 8; a 16-byte struct answers NO and goes through
        the hidden return-pointer slot.  */
    id smallStruct = [NSMethodSignature signatureWithObjCTypes:"{_NSRange=II}16@8:12"];
    id largeStruct = [NSMethodSignature signatureWithObjCTypes:"{_NSRect=ffff}16@8:12"];
    id scalarReturn = [NSMethodSignature signatureWithObjCTypes:"i12@8:12i16"];

    CHECK([scalarReturn methodReturnLength] == 4);
    CHECK([smallStruct methodReturnLength] == 8);
    CHECK([smallStruct _isReturnStructInRegisters] == YES);
    CHECK([largeStruct methodReturnLength] == 16);
    CHECK([largeStruct _isReturnStructInRegisters] == NO);
}

static void
test_getArgumentTypeAtIndex_out_of_range_raises(void)
{
    id sig = [NSMethodSignature signatureWithObjCTypes:"v8@8:12"];
    BOOL raised = NO;

    NS_DURING
        [sig getArgumentTypeAtIndex:5];
    NS_HANDLER
        raised = YES;
        CHECK(StringBytes([localException name]) != NULL);
        CHECK(strcmp(StringBytes([localException name]),
                     StringBytes(NSInvalidArgumentException)) == 0);
        CHECK(StringBytes([localException reason]) != NULL);
        CHECK(strstr(StringBytes([localException reason]),
                     "index out of bounds") != NULL);
    NS_ENDHANDLER

    CHECK(raised);
}

static void
test_argumentInfoAtIndex_returns_the_cached_entry(void)
{
    /*  -_argumentInfoAtIndex: (in the reference's method list, encoded
        {?=ii*^{_arginfo}i}12@8:12I16) RETURNS one 20-byte cache entry
        by value: { offset, size, const char *type, unused, unused }
        with offset the running round4 sum before this argument.  The
        constructor's fill loop writes only the first three fields --
        the walker's alignment output goes to a stack temporary and is
        never stored, so fields 4 and 5 read zero in the reference as
        well.  `type` is a pointer into the signature's own types copy,
        not a standalone token, so the tests read its first byte.  The
        by-value return is the Gate 1 (stage 2c) correction: the
        pointer-returning form compiled a ^v encoding and diverged.  */
    struct NSMethodSignatureArgumentInfo info;
    id sig = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];
    id charSig = [NSMethodSignature signatureWithObjCTypes:"c12@8:12c16"];

    info = (struct NSMethodSignatureArgumentInfo)
        [sig _argumentInfoAtIndex:0];
    CHECK(info.offset == 0);
    CHECK(info.size == 4);
    CHECK(info.type[0] == '@');

    info = (struct NSMethodSignatureArgumentInfo)
        [sig _argumentInfoAtIndex:1];
    CHECK(info.offset == 4);
    CHECK(info.type[0] == ':');

    info = (struct NSMethodSignatureArgumentInfo)
        [sig _argumentInfoAtIndex:2];
    CHECK(info.offset == 8);
    CHECK(info.size == 4);
    CHECK(info.type[0] == '@');

    /*  A char argument: size 1, but still occupying a round4 slot in
        the running offsets.  */
    info = (struct NSMethodSignatureArgumentInfo)
        [charSig _argumentInfoAtIndex:2];
    CHECK(info.offset == 8);
    CHECK(info.size == 1);
    CHECK(info.type[0] == 'c');
    CHECK(info.unused0 == 0);
    CHECK(info.unused1 == 0);
}

static void
test_isOneway_reads_the_qualifier(void)
{
    /*  The reference's -isOneway is a single-byte test of the first
        character of the type string against 'V' (cmp byte ptr [eax],
        0x56 at 0x42521415).  */
    id oneway = [NSMethodSignature signatureWithObjCTypes:"Vv12@8:12@16"];
    id plain = [NSMethodSignature signatureWithObjCTypes:"v12@8:12@16"];

    CHECK([oneway isOneway] == YES);
    CHECK([plain isOneway] == NO);
    /*  The qualifier IS part of the consumed span: the walker consumes
        'V' and 'v' as its steps over the return type, so the slice is
        "Vv" -- the same span the reference's own two-step walker
        yields for a qualified return.  */
    CHECK(strcmp([oneway methodReturnType], "Vv") == 0);
}

int main(void)
{
    test_frameLength_and_argument_count_for_a_simple_selector();
    test_getArgumentTypeAtIndex_reports_self_cmd_and_each_argument();
    test_methodReturnLength_for_a_nonvoid_return();
    test_struct_return_classification();
    test_getArgumentTypeAtIndex_out_of_range_raises();
    test_argumentInfoAtIndex_returns_the_cached_entry();
    test_isOneway_reads_the_qualifier();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
