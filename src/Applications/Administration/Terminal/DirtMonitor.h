#ifndef TERMINAL_DIRTMONITOR_H
#define TERMINAL_DIRTMONITOR_H

#import <Foundation/NSObject.h>

#include "FlagMap.h"

struct TerminalKnownTask;

@interface DirtMonitor : NSObject
{
    short numPtys;
    char _padding0[2];
    struct TerminalKnownTask **knownDevices;
    int *fds;
    short numPorts;
    char _padding1[2];
    struct TerminalKnownTask **goodTasks;
    int *freePortNames;
    short fpnStack;
    short numFreeTasks;
    short ftStack;
    char _padding2[2];
    struct TerminalKnownTask **freeTasks;
    TerminalFlagMap *boringTasks;
    TerminalFlagMap *freePortNamesMap;
    char runningBkgndClean;
    char shellsClean;
    char fastAudit;
    char _padding3;
    const char **cleanCommands;
    unsigned int *privSets;
    unsigned int nPrivSets;
    char selfTaskName[17];
    char monitorOK;
    char _padding4[2];
}
- (id)init;
- (void)registerDevice:(int)device withFD:(int)fileDescriptor;
- (void)setShellsClean:(char)shellsClean
    runningBackgroundClean:(char)backgroundClean fastAudits:(char)fastAudits
    cleanCommands:(const char **)commands;
- (id)getProcNames:(char (*)[17])names onDevice:(int)device
    howMany:(int *)count;
- (void)compactFreePortStack;
- (void)extendFreePortStack;
- (void)handleMachMessage:(void *)message;
- (void)uncacheThreads:(struct TerminalKnownTask *)task;
- (void)unregisterDevice:(int)device;
- (char)isDeviceDirty:(int)device;
- (void)releaseKnownTask:(struct TerminalKnownTask *)task taskDied:(char)taskDied;
@end

#endif
