#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>
#import "../Process.h"

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Process *process = [[Process alloc] initWithPid:(int)getpid()];
    NSArray *arguments = [process arguments];
    NSArray *statuses = [NSArray arrayWithObjects:
        @"Launching", @"Running", @"Sleeping", @"Suspended", @"Zombie", nil];
    int failed = 0;
    int index;

    if ([arguments count] != (unsigned int)argc) {
        fprintf(stderr, "expected %d process arguments, received %u\n",
                argc, (unsigned int)[arguments count]);
        failed = 1;
    }
    for (index = 0; index < argc && index < (int)[arguments count]; ++index) {
        NSString *expected = [NSString stringWithCString:argv[index]];
        id actual = [arguments objectAtIndex:(unsigned int)index];
        if (![actual isEqual:expected]) {
            fprintf(stderr, "argument %d mismatch: expected <%s>, got <%s>\n",
                    index, argv[index], [actual cString]);
            failed = 1;
        }
    }

    [process _update];
    if ([process processId] != (unsigned int)getpid()) {
        fprintf(stderr, "Process PID does not match the current process\n");
        failed = 1;
    }
    if ([process parentProcessId] != (unsigned int)getppid()) {
        fprintf(stderr, "Process PPID does not match getppid()\n");
        failed = 1;
    }
    if ([process processGroupId] != (unsigned int)getpgrp()) {
        fprintf(stderr, "Process PGID does not match getpgrp()\n");
        failed = 1;
    }
    if ([process savedUserId] != (unsigned int)geteuid()) {
        fprintf(stderr, "Process saved UID does not match geteuid()\n");
        failed = 1;
    }
    if ([process objectForKey:@"NAME"] == nil) {
        fprintf(stderr, "sysctl process name was not populated\n");
        failed = 1;
    }
    if (![[process objectForKey:@"USER"] isEqual:NSUserName()]) {
        fprintf(stderr, "sysctl UID did not resolve to the current username\n");
        failed = 1;
    }
    if (![statuses containsObject:[process objectForKey:@"STAT"]]) {
        fprintf(stderr, "sysctl process status was not mapped to a known state\n");
        failed = 1;
    }

    [process release];
    [pool release];
    return failed;
}
