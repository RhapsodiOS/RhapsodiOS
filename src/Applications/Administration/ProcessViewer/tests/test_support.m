#import "test_support.h"
#import <AppKit/NSPrintOperation.h>
#include <stdio.h>
#import <signal.h>

@interface NSPrintOperation (PVTestPrintOperation)
+ (NSPrintOperation *)printOperationWithView:(NSView *)view;
@end

@implementation NSPrintOperation (PVTestPrintOperation)
+ (NSPrintOperation *)printOperationWithView:(NSView *)aView
{
    PVTestRunPrintOperationWithView(aView);
    return nil;
}
@end

static int failureCount = 0;
static NSString *controllerTestUserName = nil;
static NSMutableArray *controllerTestAlerts = nil;
static NSMutableArray *controllerTestResponses = nil;
static NSMutableArray *controllerTestSignals = nil;
static unsigned int controllerTestBeepCount = 0;
static NSDictionary *controllerTestSystemInfoOptions = nil;
static SEL controllerTestSystemInfoCommand = NULL;
static id controllerTestSystemInfoSender = nil;
static NSDictionary *controllerTestRegisteredDefaults = nil;
static id controllerTestPrintOperationView = nil;

#ifndef PV_TEST_CONTROLLER_IMPLEMENTATION
id PVTestControllerSavePanel(void)
{
    return nil;
}
#endif

void PVTestControllerReset(NSString *userName)
{
    [controllerTestUserName release];
    controllerTestUserName = [userName copy];
    [controllerTestAlerts release];
    controllerTestAlerts = [[NSMutableArray alloc] init];
    [controllerTestResponses release];
    controllerTestResponses = [[NSMutableArray alloc] init];
    [controllerTestSignals release];
    controllerTestSignals = [[NSMutableArray alloc] init];
    [controllerTestSystemInfoOptions release];
    controllerTestSystemInfoOptions = nil;
    controllerTestSystemInfoCommand = NULL;
    [controllerTestSystemInfoSender release];
    controllerTestSystemInfoSender = nil;
    [controllerTestRegisteredDefaults release];
    controllerTestRegisteredDefaults = nil;
    [controllerTestPrintOperationView release];
    controllerTestPrintOperationView = nil;
}

void PVTestControllerQueueAlertResponse(int response)
{
    if (controllerTestResponses == nil)
        PVTestControllerReset(@"test-user");
    [controllerTestResponses addObject:[NSNumber numberWithInt:response]];
}

unsigned int PVTestControllerAlertCount(void)
{
    return [controllerTestAlerts count];
}

id PVTestControllerAlertAtIndex(unsigned int index)
{
    return [controllerTestAlerts objectAtIndex:index];
}

unsigned int PVTestControllerSignalCount(void)
{
    return [controllerTestSignals count];
}

pid_t PVTestControllerSignalPidAtIndex(unsigned int index)
{
    return (pid_t)[[[controllerTestSignals objectAtIndex:index]
        objectForKey:@"pid"] intValue];
}

int PVTestControllerSignalAtIndex(unsigned int index)
{
    return [[[controllerTestSignals objectAtIndex:index]
        objectForKey:@"signal"] intValue];
}

NSString *PVTestCurrentUserName(void)
{
    return controllerTestUserName != nil ? controllerTestUserName : @"test-user";
}

int PVTestRunAlertPanel(NSString *title, NSString *message,
                        NSString *defaultButton, NSString *alternateButton,
                        NSString *otherButton, id argument1, id argument2)
{
    NSMutableDictionary *alert;
    id response;
    if (controllerTestAlerts == nil)
        PVTestControllerReset(@"test-user");
    alert = [NSMutableDictionary dictionary];
    [alert setObject:(title != nil ? title : (id)@"(nil)") forKey:@"title"];
    [alert setObject:(message != nil ? message : (id)@"(nil)") forKey:@"message"];
    [alert setObject:(defaultButton != nil ? defaultButton : (id)@"(nil)") forKey:@"default"];
    [alert setObject:(alternateButton != nil ? alternateButton : (id)@"(nil)") forKey:@"alternate"];
    [alert setObject:(otherButton != nil ? otherButton : (id)@"(nil)") forKey:@"other"];
    [alert setObject:(argument1 != nil ? argument1 : (id)@"(nil)") forKey:@"argument1"];
    [alert setObject:(argument2 != nil ? argument2 : (id)@"(nil)") forKey:@"argument2"];
    [controllerTestAlerts addObject:alert];
    response = [controllerTestResponses count] != 0
        ? [[[controllerTestResponses objectAtIndex:0] retain] autorelease] : nil;
    if (response != nil)
        [controllerTestResponses removeObjectAtIndex:0];
    return response != nil ? [response intValue] : -1;
}

int PVTestSendSignal(pid_t pid, int signalNumber)
{
    NSDictionary *record = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:(int)pid], @"pid",
        [NSNumber numberWithInt:signalNumber], @"signal", nil];
    if (controllerTestSignals == nil)
        PVTestControllerReset(@"test-user");
    [controllerTestSignals addObject:record];
    return 0;
}

void PVTestBeep(void)
{
    ++controllerTestBeepCount;
}

unsigned int PVTestBeepCount(void)
{
    return controllerTestBeepCount;
}

void PVTestShowSystemInfoPanel(NSDictionary *options, SEL command, id sender)
{
    [controllerTestSystemInfoOptions release];
    controllerTestSystemInfoOptions = [options retain];
    controllerTestSystemInfoCommand = command;
    [controllerTestSystemInfoSender release];
    controllerTestSystemInfoSender = [sender retain];
}

NSDictionary *PVTestSystemInfoPanelOptions(void)
{
    return controllerTestSystemInfoOptions;
}

SEL PVTestSystemInfoPanelCommand(void)
{
    return controllerTestSystemInfoCommand;
}

id PVTestSystemInfoPanelSender(void)
{
    return controllerTestSystemInfoSender;
}

void PVTestRegisterDefaults(NSDictionary *defaults)
{
    [controllerTestRegisteredDefaults release];
    controllerTestRegisteredDefaults = [defaults copy];
}

NSDictionary *PVTestRegisteredDefaults(void)
{
    return controllerTestRegisteredDefaults;
}

void PVTestRunPrintOperationWithView(id view)
{
    [controllerTestPrintOperationView release];
    controllerTestPrintOperationView = [view retain];
}

id PVTestPrintOperationView(void)
{
    return controllerTestPrintOperationView;
}

void PVCheck(BOOL condition, const char *expression, const char *file, int line)
{
    if (!condition) {
        fprintf(stderr, "%s:%d: check failed: %s\n", file, line, expression);
        ++failureCount;
    }
}

void PVCheckObjectsEqual(id actual, id expected, const char *expression,
                         const char *file, int line)
{
    PVCheck(actual == expected || [actual isEqual:expected], expression, file, line);
}

int PVFinish(void)
{
    if (failureCount != 0)
        fprintf(stderr, "%d test check(s) failed\n", failureCount);
    return failureCount == 0 ? 0 : 1;
}
