/*  Behavioural tests for NSObjCRuntime, stage 2b.  */

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <objc/objc-runtime.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  Reads an NSString the way this stage builds one: stage 2b has no real
    NSString, so both literals and the strings these functions return are
    NXConstantString-shaped records (see NSObjCRuntime.m's own comment).  */
static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

#define CHECK_STRING(actual, expected) \
    do { \
        const char *bytes = TestStringBytes(actual); \
        if (bytes == NULL || strcmp(bytes, (expected)) != 0) { \
            printf("FAIL %s:%d expected \"%s\", got \"%s\"\n", \
                   __FILE__, __LINE__, (expected), bytes ? bytes : "(null)"); \
            failures++; \
        } \
    } while (0)

extern const char *_NSGetSizeAndAlignment(const char *typePtr, unsigned int *sizep, unsigned int *alignp);

static void test_NSStringFromClass_gives_the_class_name(void)
{
    CHECK_STRING(NSStringFromClass([NSObject class]), "NSObject");
}

static void test_NSStringFromClass_of_Nil_is_nil(void)
{
    CHECK(NSStringFromClass(Nil) == nil);
}

static void test_NSClassFromString_finds_a_registered_class(void)
{
    CHECK(NSClassFromString(@"NSObject") == [NSObject class]);
}

static void test_NSClassFromString_of_an_unknown_name_is_Nil(void)
{
    CHECK(NSClassFromString(@"NSNoSuchClassExistsHere") == Nil);
}

static void test_NSStringFromSelector_gives_the_selector_name(void)
{
    CHECK_STRING(NSStringFromSelector(@selector(description)), "description");
    CHECK_STRING(NSStringFromSelector(@selector(isEqual:)), "isEqual:");
}

static void test_NSSelectorFromString_round_trips(void)
{
    SEL selector = NSSelectorFromString(@"isEqual:");

    CHECK(selector == @selector(isEqual:));
    CHECK_STRING(NSStringFromSelector(selector), "isEqual:");
}

static void test_NSSelectorFromString_registers_an_unseen_name(void)
{
    SEL selector = NSSelectorFromString(@"aSelectorNoOneHasUsedYet:");

    CHECK(selector != NULL);
    CHECK_STRING(NSStringFromSelector(selector), "aSelectorNoOneHasUsedYet:");
}

static void test_conversions_of_nil_are_safe(void)
{
    CHECK(NSClassFromString(nil) == Nil);
    CHECK(NSSelectorFromString(nil) == NULL);
    CHECK(NSStringFromSelector(NULL) == nil);
}

/*  Type encodings are i386's: int/long/pointer 4, short 2, char 1,
    float 4, double 8, and a struct is laid out from its members.  */
static void test_NSGetSizeAndAlignment_scalars(void)
{
    unsigned size;
    unsigned align;
    const char *rest;

    rest = NSGetSizeAndAlignment("i", &size, &align);
    CHECK(size == 4); CHECK(align == 4); CHECK(rest != NULL && *rest == '\0');

    rest = NSGetSizeAndAlignment("c", &size, &align);
    CHECK(size == 1); CHECK(align == 1);

    rest = NSGetSizeAndAlignment("s", &size, &align);
    CHECK(size == 2); CHECK(align == 2);

    rest = NSGetSizeAndAlignment("d", &size, &align);
    CHECK(size == 8);

    rest = NSGetSizeAndAlignment("@", &size, &align);
    CHECK(size == 4); CHECK(align == 4);

    rest = NSGetSizeAndAlignment(":", &size, &align);
    CHECK(size == 4);

    rest = NSGetSizeAndAlignment("^v", &size, &align);
    CHECK(size == 4); CHECK(rest != NULL && *rest == '\0');
}

static void test_NSGetSizeAndAlignment_advances_through_a_signature(void)
{
    unsigned size;
    unsigned align;
    const char *cursor = "i@:c";

    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 4);
    cursor = NSGetSizeAndAlignment(cursor, &size, &align);
    CHECK(size == 1);
    CHECK(cursor != NULL && *cursor == '\0');
}

static void test_NSGetSizeAndAlignment_arrays_and_structs(void)
{
    unsigned size;
    unsigned align;
    const char *rest;

    rest = NSGetSizeAndAlignment("[8i]", &size, &align);
    CHECK(size == 32);
    CHECK(rest != NULL && *rest == '\0');

    /*  NSRange-shaped: two unsigned ints.  */
    rest = NSGetSizeAndAlignment("{_NSRange=II}", &size, &align);
    CHECK(size == 8); CHECK(align == 4);
    CHECK(rest != NULL && *rest == '\0');

    /*  Mixed alignment: char then int pads to 8.  */
    rest = NSGetSizeAndAlignment("{mixed=ci}", &size, &align);
    CHECK(size == 8); CHECK(align == 4);
}

static void test_NSGetSizeAndAlignment_tolerates_null_out_params(void)
{
    const char *rest = NSGetSizeAndAlignment("i", NULL, NULL);

    CHECK(rest != NULL && *rest == '\0');
}

static void test_private_NSGetSizeAndAlignment_agrees_with_the_public_one(void)
{
    unsigned publicSize, publicAlign;
    unsigned privateSize, privateAlign;

    NSGetSizeAndAlignment("{_NSRange=II}", &publicSize, &publicAlign);
    _NSGetSizeAndAlignment("{_NSRange=II}", &privateSize, &privateAlign);
    CHECK(publicSize == privateSize);
    CHECK(publicAlign == privateAlign);
}

/*  Runs `body` with stderr redirected to a temp file, then returns its
    contents in `buffer`.  NSLog writes to stderr, and this is the only
    way to assert on what it produced without a real NSString.  */
static void CaptureStdErr(void (*body)(void), char *buffer, unsigned size)
{
    const char *path = "/tmp/test_objcruntime_stderr.txt";
    int savedFd = dup(2);
    FILE *captured = fopen(path, "w");
    FILE *readBack;
    unsigned got;

    fflush(stderr);
    dup2(fileno(captured), 2);
    body();
    fflush(stderr);
    dup2(savedFd, 2);
    close(savedFd);
    fclose(captured);

    buffer[0] = '\0';
    readBack = fopen(path, "r");
    if (readBack != NULL) {
        got = fread(buffer, 1, size - 1, readBack);
        buffer[got] = '\0';
        fclose(readBack);
    }
    remove(path);
}

static void emit_plain(void)    { NSLog(@"a plain message"); }
static void emit_decimal(void)  { NSLog(@"count is %d", 42); }
static void emit_cstring(void)  { NSLog(@"name is %s", "NSObject"); }
static void emit_object(void)   { NSLog(@"%@: selector not recognized", @"-[NSObject foo]"); }
static void emit_percent(void)  { NSLog(@"100%% done"); }
static void emit_nil_format(void) { NSLog(nil); }

static void test_NSLog_writes_its_message_to_stderr(void)
{
    char buffer[512];

    CaptureStdErr(emit_plain, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "a plain message") != NULL);
}

static void test_NSLog_substitutes_c_format_specifiers(void)
{
    char buffer[512];

    CaptureStdErr(emit_decimal, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "count is 42") != NULL);

    CaptureStdErr(emit_cstring, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "name is NSObject") != NULL);
}

static void test_NSLog_substitutes_an_object_with_percent_at(void)
{
    char buffer[512];

    CaptureStdErr(emit_object, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "-[NSObject foo]: selector not recognized") != NULL);
}

static void test_NSLog_passes_a_literal_percent_through(void)
{
    char buffer[512];

    CaptureStdErr(emit_percent, buffer, sizeof(buffer));
    CHECK(strstr(buffer, "100% done") != NULL);
}

static void test_NSLog_of_nil_does_not_crash(void)
{
    char buffer[512];

    CaptureStdErr(emit_nil_format, buffer, sizeof(buffer));
}

int main(void)
{
    test_NSStringFromClass_gives_the_class_name();
    test_NSStringFromClass_of_Nil_is_nil();
    test_NSClassFromString_finds_a_registered_class();
    test_NSClassFromString_of_an_unknown_name_is_Nil();
    test_NSStringFromSelector_gives_the_selector_name();
    test_NSSelectorFromString_round_trips();
    test_NSSelectorFromString_registers_an_unseen_name();
    test_conversions_of_nil_are_safe();
    test_NSGetSizeAndAlignment_scalars();
    test_NSGetSizeAndAlignment_advances_through_a_signature();
    test_NSGetSizeAndAlignment_arrays_and_structs();
    test_NSGetSizeAndAlignment_tolerates_null_out_params();
    test_private_NSGetSizeAndAlignment_agrees_with_the_public_one();
    test_NSLog_writes_its_message_to_stderr();
    test_NSLog_substitutes_c_format_specifiers();
    test_NSLog_substitutes_an_object_with_percent_at();
    test_NSLog_passes_a_literal_percent_through();
    test_NSLog_of_nil_does_not_crash();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
