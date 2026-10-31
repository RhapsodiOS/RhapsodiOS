#import <Foundation/Foundation.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#import "../Process.h"
#import "test_support.h"

static Process *findChildProcess(NSArray *processes, pid_t parentPid)
{
    unsigned int index;
    for (index = 0; index < [processes count]; ++index) {
        Process *process = [processes objectAtIndex:index];
        if ([process parentProcessId] == (unsigned int)parentPid &&
            [[process objectForKey:@"NAME"] isEqual:@"sleep"])
            return process;
    }
    return nil;
}

static Process *findProcessWithPid(NSArray *processes, pid_t pid)
{
    unsigned int index;
    for (index = 0; index < [processes count]; ++index) {
        Process *process = [processes objectAtIndex:index];
        if ([process processId] == (unsigned int)pid)
            return process;
    }
    return nil;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSArray *processes;
    Process *process = nil;
    Process *stableProcess = nil;
    pid_t childPid;
    NSArray *keys;
    unsigned int index;
    BOOL enumerationSucceeded = YES;

    childPid = fork();
    if (childPid == 0) {
        execl("/bin/sleep", "sleep", "30", (char *)0);
        _exit(127);
    }
    PV_CHECK(childPid > 0);

    if (childPid > 0) {
        NS_DURING
            processes = [Process enumerateProcessesAndFetch:YES];
            process = findChildProcess(processes, getpid());
            stableProcess = findProcessWithPid(processes, 1);
            PV_CHECK(process != nil);
            PV_CHECK(stableProcess != nil);
            if (process != nil)
                childPid = (pid_t)[process processId];
        NS_HANDLER
            NSLog(@"Live process enumeration raised %@", localException);
            PV_CHECK(NO);
            enumerationSucceeded = NO;
        NS_ENDHANDLER
    }

    if (process != nil) {
        PV_CHECK_OBJECTS_EQUAL([process objectForKey:@"NAME"], @"sleep");
        PV_CHECK_OBJECTS_EQUAL([process objectForKey:@"USER"], NSUserName());
        keys = [NSArray arrayWithObjects:
            @"%CPU", @"%MEM", @"VSIZE", @"RSIZE", @"TTY", @"STAT",
            @"TIME", nil];
        for (index = 0; index < [keys count]; ++index) {
            id key = [keys objectAtIndex:index];
            PV_CHECK([process objectForKey:key] != nil);
        }
        PV_CHECK([[process objectForKey:@"TIME"] rangeOfString:@":"].location
                 != NSNotFound);
        PV_CHECK([process objectForKey:@"START"] == nil);
        PV_CHECK([process objectForKey:@"COMMAND"] == nil);
    }

    if (childPid > 0)
        (void)kill(childPid, SIGTERM);
    if (childPid > 0)
        (void)waitpid(childPid, NULL, 0);

    if (childPid > 0 && enumerationSucceeded) {
        NS_DURING
            processes = [Process enumerateProcessesAndFetch:NO];
            PV_CHECK(findProcessWithPid(processes, childPid) == process);
            processes = [Process enumerateProcessesAndFetch:YES];
            PV_CHECK(findProcessWithPid(processes, childPid) == nil);
            PV_CHECK(findProcessWithPid(processes, 1) == stableProcess);
        NS_HANDLER
            NSLog(@"Live stale-process refresh raised %@", localException);
            PV_CHECK(NO);
        NS_ENDHANDLER
    }

    [pool release];
    return PVFinish();
}
