/*  Behavioural tests for NSException and the handler stack, stage 2b.
    These use the real NS_DURING / NS_HANDLER macros from NSException.h,
    so the macros are under test alongside the functions they call.  */

#import <Foundation/NSException.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

extern unsigned _NSExceptionHandlerCount(void);
extern void _NSClearExceptionStack(void);

static void test_handler_stack_starts_empty(void)
{
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_adding_and_removing_a_handler_balances(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 1);
    _NSRemoveHandler2(&handler);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_handlers_nest(void)
{
    NSHandler2 outer;
    NSHandler2 inner;

    _NSAddHandler2(&outer);
    _NSAddHandler2(&inner);
    CHECK(_NSExceptionHandlerCount() == 2);
    _NSRemoveHandler2(&inner);
    _NSRemoveHandler2(&outer);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_a_handler_with_no_exception_reports_nil(void)
{
    NSHandler2 handler;

    _NSAddHandler2(&handler);
    CHECK(_NSExceptionObjectFromHandler2(&handler) == nil);
    _NSRemoveHandler2(&handler);
}

static void test_NS_DURING_normal_path_skips_the_handler(void)
{
    int ranBody = 0;
    int ranHandler = 0;

    NS_DURING
        ranBody = 1;
    NS_HANDLER
        ranHandler = 1;
    NS_ENDHANDLER

    CHECK(ranBody == 1);
    CHECK(ranHandler == 0);
    CHECK(_NSExceptionHandlerCount() == 0);
}

extern void _NSAddAltHandler2(NSHandler2 *handler);
extern void _NSRemoveAltHandler2(NSHandler2 *handler);

static void test_alt_handlers_do_not_disturb_the_main_chain(void)
{
    NSHandler2 main;
    NSHandler2 alternate;
    unsigned before;

    _NSAddHandler2(&main);
    before = _NSExceptionHandlerCount();

    _NSAddAltHandler2(&alternate);
    _NSRemoveAltHandler2(&alternate);

    CHECK(_NSExceptionHandlerCount() == before);
    _NSRemoveHandler2(&main);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void raise_from_depth(int depth)
{
    if (depth > 0) {
        raise_from_depth(depth - 1);
        return;
    }
    [NSException raise:NSGenericException format:@"from depth"];
}

static const char *TestStringBytes(id string)
{
    struct { Class isa; char *c_string; unsigned int len; } *record = (void *)string;

    return (string == nil) ? NULL : record->c_string;
}

static void test_raise_transfers_to_the_enclosing_handler(void)
{
    int reachedHandler = 0;
    id caught = nil;

    NS_DURING
        [NSException raise:NSInvalidArgumentException format:@"boom"];
        CHECK(0);  /* unreachable: raise does not return */
    NS_HANDLER
        reachedHandler = 1;
        caught = localException;
    NS_ENDHANDLER

    CHECK(reachedHandler == 1);
    CHECK(caught != nil);
    CHECK([caught name] == NSInvalidArgumentException);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_the_exception_carries_its_reason(void)
{
    id caught = nil;

    NS_DURING
        [NSException raise:NSGenericException format:@"a specific reason"];
    NS_HANDLER
        caught = localException;
    NS_ENDHANDLER

    CHECK(caught != nil);
    CHECK(strstr(TestStringBytes([caught reason]), "a specific reason") != NULL);
}

static void test_exceptionWithName_populates_all_three_accessors(void)
{
    id exception = [NSException exceptionWithName:NSRangeException
                                           reason:@"out of range"
                                         userInfo:nil];

    CHECK(exception != nil);
    CHECK([exception name] == NSRangeException);
    CHECK(strstr(TestStringBytes([exception reason]), "out of range") != NULL);
    CHECK([exception userInfo] == nil);
}

static void test_raising_an_exception_object_directly(void)
{
    id made = [NSException exceptionWithName:NSMallocException
                                      reason:@"no memory"
                                    userInfo:nil];
    id caught = nil;

    NS_DURING
        [made raise];
    NS_HANDLER
        caught = localException;
    NS_ENDHANDLER

    CHECK(caught == made);
}

static void test_an_inner_handler_catches_before_the_outer_one(void)
{
    int innerCaught = 0;
    int outerCaught = 0;

    NS_DURING
        NS_DURING
            [NSException raise:NSGenericException format:@"inner"];
        NS_HANDLER
            innerCaught = 1;
        NS_ENDHANDLER
    NS_HANDLER
        outerCaught = 1;
    NS_ENDHANDLER

    CHECK(innerCaught == 1);
    CHECK(outerCaught == 0);
    CHECK(_NSExceptionHandlerCount() == 0);
}

static void test_a_raise_from_a_nested_call_unwinds(void)
{
    int caught = 0;

    NS_DURING
        raise_from_depth(6);
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    CHECK(caught == 1);
}

static void test_isEqual_compares_name_and_reason(void)
{
    id a = [NSException exceptionWithName:NSGenericException reason:@"same" userInfo:nil];
    id b = [NSException exceptionWithName:NSGenericException reason:@"same" userInfo:nil];
    id c = [NSException exceptionWithName:NSRangeException reason:@"same" userInfo:nil];

    CHECK([a isEqual:b]);
    CHECK(![a isEqual:c]);
}

/*  The uncaught path, observed without dying: the suite installs its own
    handler, which records the exception and jumps back here.  */
static jmp_buf uncaughtReturn;
static id uncaughtException = nil;

static void TestUncaughtHandler(NSException *exception)
{
    uncaughtException = exception;
    _longjmp(uncaughtReturn, 1);
}

static void test_an_uncaught_raise_reaches_the_uncaught_handler(void)
{
    NSUncaughtExceptionHandler *previous = NSGetUncaughtExceptionHandler();

    NSSetUncaughtExceptionHandler(TestUncaughtHandler);
    CHECK(NSGetUncaughtExceptionHandler() == TestUncaughtHandler);

    uncaughtException = nil;
    if (!_setjmp(uncaughtReturn)) {
        [NSException raise:NSGenericException format:@"nobody is catching"];
        CHECK(0);  /* unreachable */
    }

    CHECK(uncaughtException != nil);
    CHECK([uncaughtException name] == NSGenericException);

    NSSetUncaughtExceptionHandler(previous);
}

extern id _NSMethodExceptionProem(id object, SEL aSelector);

static void test_method_exception_proem_names_an_instance_method(void)
{
    id object = [[NSObject alloc] init];
    id proem = _NSMethodExceptionProem(object, @selector(hash));

    CHECK(proem != nil);
    CHECK(strcmp(TestStringBytes(proem), "-[NSObject hash]") == 0);
    [object release];
}

static void test_method_exception_proem_names_a_class_method(void)
{
    id proem = _NSMethodExceptionProem([NSObject class], @selector(alloc));

    CHECK(proem != nil);
    CHECK(strcmp(TestStringBytes(proem), "+[NSObject alloc]") == 0);
}

/*  NSAssert's expansion calls +[NSString stringWithCString:] for __FILE__.
    Stage 2b has no NSString; this gives the macro something that works
    over the same NXConstantString-shaped records the rest of the stage
    uses, so the assert path is testable here.  Stage 3 removes it.  */

@interface TestAssertString : NSObject
+ (id)stringWithCString:(const char *)bytes;
@end

@implementation TestAssertString

+ (void)initialize {}

+ (id)stringWithCString:(const char *)bytes
{
    struct { Class isa; char *c_string; unsigned int len; } *record;
    unsigned length;

    if (bytes == NULL)
        return nil;

    length = strlen(bytes);
    record = malloc(sizeof(*record) + length + 1);
    record->isa = (Class)&_NSConstantStringClassReference;
    record->c_string = (char *)(record + 1);
    record->len = length;
    memcpy(record->c_string, bytes, length + 1);

    return (id)record;
}

@end

/*  NSAssert names NSString literally, so point that name at the class
    above for the duration of the assert tests only -- the expansion also
    sends _cmd and self, so the asserts must run inside a method body;
    this runner supplies one.  */
#define NSString TestAssertString

@interface TestAssertRunner : NSObject
- (void)runFailingAssert;
- (void)runPassingAssert;
@end

@implementation TestAssertRunner

+ (void)initialize {}

- (void)runFailingAssert { NSAssert(1 == 2, @"one is not two"); }
- (void)runPassingAssert { NSAssert(1 == 1, @"one is one"); }

@end

#undef NSString

static void test_assertion_handler_is_a_shared_instance(void)
{
    id first = [NSAssertionHandler currentHandler];
    id second = [NSAssertionHandler currentHandler];

    CHECK(first != nil);
    CHECK(first == second);
}

static void test_a_failing_NSAssert_raises(void)
{
    int caught = 0;
    id runner = [[TestAssertRunner alloc] init];

    NS_DURING
        [runner runFailingAssert];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    [runner release];
    CHECK(caught == 1);
}

static void test_a_passing_NSAssert_does_not_raise(void)
{
    int caught = 0;
    id runner = [[TestAssertRunner alloc] init];

    NS_DURING
        [runner runPassingAssert];
    NS_HANDLER
        caught = 1;
    NS_ENDHANDLER

    [runner release];
    CHECK(caught == 0);
}

int main(void)
{
    test_handler_stack_starts_empty();
    test_adding_and_removing_a_handler_balances();
    test_handlers_nest();
    test_a_handler_with_no_exception_reports_nil();
    test_NS_DURING_normal_path_skips_the_handler();
    test_alt_handlers_do_not_disturb_the_main_chain();
    test_raise_transfers_to_the_enclosing_handler();
    test_the_exception_carries_its_reason();
    test_exceptionWithName_populates_all_three_accessors();
    test_raising_an_exception_object_directly();
    test_an_inner_handler_catches_before_the_outer_one();
    test_a_raise_from_a_nested_call_unwinds();
    test_isEqual_compares_name_and_reason();
    test_an_uncaught_raise_reaches_the_uncaught_handler();
    test_method_exception_proem_names_an_instance_method();
    test_method_exception_proem_names_a_class_method();
    test_assertion_handler_is_a_shared_instance();
    test_a_failing_NSAssert_raises();
    test_a_passing_NSAssert_does_not_raise();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
