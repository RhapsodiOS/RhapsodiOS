#import "DirtMonitor.h"

#import <Foundation/NSPort.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <AppKit/NSPanel.h>
#import <objc/objc-runtime.h>

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/mach_init.h>
#include <mach/mach_error.h>
#include <mach/mach_interface.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>

#include "ProcessIdentity.h"
#include "ProcessInfo.h"
#include "ProcessNames.h"
#include "ShellPolicy.h"

struct TerminalKnownTask {
    int portName;
    int pid;
    unsigned char device;
    unsigned char stateFlags;
    signed char threadCount;
    unsigned char reserved;
    unsigned int cachedThreadPorts[2];
    struct TerminalKnownTask *next;
    struct TerminalKnownTask *previous;
};

_Static_assert(sizeof(struct TerminalKnownTask) == 28,
    "Terminal task-record layout");

static signed char TerminalTaskThreadCount(struct TerminalKnownTask *task)
{
    return task->threadCount;
}

static void TerminalSetTaskThreadCount(struct TerminalKnownTask *task,
    signed char count)
{
    task->threadCount = count;
}

static int taskIsBlocked(struct TerminalKnownTask *task,
    char foreground, TerminalFlagMap *freePortNamesMap, char fastAudit,
    short numPorts)
{
    thread_array_t threads;
    mach_msg_type_number_t threadCount;
    mach_msg_type_number_t index;
    int threadIndex;
    integer_t info[11];
    int hasRunningThread = 0;
    int cached = TerminalTaskThreadCount(task) != -1 &&
        (task->stateFlags & 0x40) != 0 && fastAudit;

    if (cached) {
        threads = (thread_array_t)task->cachedThreadPorts;
    } else {
        if (task_threads(task->portName, &threads, &threadCount) !=
                KERN_SUCCESS)
            return 0;
        TerminalSetTaskThreadCount(task, (signed char)threadCount);
        if (threadCount <= 2 && fastAudit) {
            for (index = 0; index < threadCount; ++index) {
                task->cachedThreadPorts[index] = threads[index];
                if (threads[index] != MACH_PORT_NULL &&
                        threads[index] < (unsigned short)numPorts)
                    SetFlag(freePortNamesMap, threads[index], 0);
            }
            task->stateFlags |= 0x40;
        }
    }

    for (threadIndex = 0;
            threadIndex < TerminalTaskThreadCount(task); ++threadIndex) {
        mach_msg_type_number_t returnedInfoCount = 11;
        if (thread_info(threads[threadIndex], THREAD_BASIC_INFO, info,
                &returnedInfoCount) == KERN_SUCCESS) {
            if (!foreground) {
                if (info[7] == 1)
                    hasRunningThread = 1;
            } else if (info[7] == 1 || info[7] == 4 ||
                    (info[7] == 3 && info[10] <= 1)) {
                hasRunningThread = 1;
            }
        }
        if (hasRunningThread)
            break;
    }
    if (!cached)
        vm_deallocate(mach_task_self(), (vm_address_t)threads,
            sizeof(*threads) * TerminalTaskThreadCount(task));
    return !hasRunningThread;
}

static void TerminalMonitorAllocationFailure(DirtMonitor *monitor,
    const char *operation, int line)
{
    (void)monitor;
    (void)operation;
    (void)line;
    NSRunAlertPanel(@"Malloc botch",
        @"Can't allocate memory for processor set ports.", @"OK", nil, nil);
}

@implementation DirtMonitor

- (id)init
{
    unsigned int i;
    kern_return_t result;
    host_priv_t privilegedHost;
    processor_set_name_array_t processorSets;
    mach_port_t port;
    TerminalProcessInfo processInfo;

    numPtys = 4;
    knownDevices = NSZoneMalloc([self zone], sizeof(*knownDevices) * numPtys);
    if (knownDevices == NULL)
        TerminalMonitorAllocationFailure(self, "knownDevices", 61);
    fds = NSZoneMalloc([self zone], sizeof(*fds) * numPtys);
    if (fds == NULL)
        TerminalMonitorAllocationFailure(self, "fds", 63);
    for (i = 0; i < (unsigned short)numPtys; ++i)
        knownDevices[i] = (struct TerminalKnownTask *)-1;

    boringTasks = CreateFlagMapFromZone([self zone]);
    freePortNamesMap = CreateFlagMapFromZone([self zone]);
    numPorts = 96;
    goodTasks = NSZoneMalloc([self zone], sizeof(*goodTasks) * numPorts);
    if (goodTasks == NULL)
        TerminalMonitorAllocationFailure(self, "goodTasks", 73);
    freePortNames = NSZoneMalloc([self zone], sizeof(*freePortNames) * numPorts);
    if (freePortNames == NULL)
        TerminalMonitorAllocationFailure(self, "freePortNames", 75);
    for (i = 0; i < (unsigned short)numPorts; ++i) {
        goodTasks[i] = NULL;
        freePortNames[i] = (int)i;
        SetFlag(freePortNamesMap, i, 1);
    }

    numFreeTasks = 24;
    ftStack = 0;
    freeTasks = NSZoneMalloc([self zone], sizeof(*freeTasks) * numPorts);
    if (freeTasks == NULL)
        TerminalMonitorAllocationFailure(self, "freeTasks", 86);
    freePortNames[0] = freePortNames[1];
    fpnStack = numPorts;

    become_root();
    privilegedHost = host_priv_self();
    if (privilegedHost != MACH_PORT_NULL) {
        result = host_processor_sets(privilegedHost, &processorSets, &nPrivSets);
        if (result != KERN_SUCCESS) {
            mach_error("host_processor_sets", result);
            exit(0);
        }
        privSets = NSZoneMalloc([self zone], sizeof(*privSets) * nPrivSets);
        if (privSets == NULL)
            TerminalMonitorAllocationFailure(self, "privSets", 110);
        for (i = 0; i < nPrivSets; ++i) {
            if (host_processor_set_priv(privilegedHost, processorSets[i],
                (processor_set_t *)&privSets[i]) != KERN_SUCCESS)
                privSets[i] = processorSets[i];
            port_deallocate(mach_task_self(), processorSets[i]);
        }
        become_user();
        vm_deallocate(mach_task_self(), (vm_address_t)processorSets,
            sizeof(*processorSets) * nPrivSets);
        port_deallocate(mach_task_self(), privilegedHost);
        if (port_allocate(mach_task_self(), &port) != KERN_SUCCESS ||
            task_set_special_port(mach_task_self(), TASK_NOTIFY_PORT, port) !=
                KERN_SUCCESS) {
            monitorOK = 0;
        } else {
            NSPort *notifyPort;
            NSRunLoop *runLoop;

            get_process_info_from_pid(getpid(), &processInfo);
            strcpy(selfTaskName, processInfo.command);
            selfTaskName[sizeof(selfTaskName) - 1] = '\0';
            notifyPort = [[NSPort portWithMachPort:port] retain];
            [notifyPort setDelegate:self];
            runLoop = [NSRunLoop currentRunLoop];
            [runLoop addPort:notifyPort forMode:NSDefaultRunLoopMode];
            monitorOK = 1;
        }
    } else {
        monitorOK = 0;
        become_user();
    }
    return self;
}

- (void)registerDevice:(int)device withFD:(int)fileDescriptor
{
    unsigned int newCount;
    unsigned int i;
    struct TerminalKnownTask **newDevices;
    int *newFDs;

    if (!monitorOK)
        return;
    if (device >= numPtys) {
        newCount = (unsigned short)numPtys + 4;
        if ((unsigned int)device + 1 >= newCount)
            newCount = (unsigned int)device + 1;
        newDevices = NSZoneRealloc([self zone], knownDevices,
            sizeof(*knownDevices) * newCount);
        knownDevices = newDevices;
        if (knownDevices == NULL) {
            TerminalMonitorAllocationFailure(self, "knownDevices", 161);
        }
        newFDs = NSZoneRealloc([self zone], fds, sizeof(*fds) * newCount);
        fds = newFDs;
        if (fds == NULL)
            TerminalMonitorAllocationFailure(self, "fds", 163);
        for (i = (unsigned short)numPtys; i < newCount; ++i)
            knownDevices[i] = (struct TerminalKnownTask *)-1;
        numPtys = (short)newCount;
    }
    knownDevices[device] = NULL;
    fds[device] = fileDescriptor;
}

- (void)unregisterDevice:(int)device
{
    struct TerminalKnownTask *task;

    if (!monitorOK)
        return;
    if (device >= (unsigned short)numPtys || (device >= 0 &&
            knownDevices[device] == (struct TerminalKnownTask *)-1))
        NSRunAlertPanel(@"DirtMonitor.m",
            @"Invalid or unregistered device passed to unregisteredDevice.",
            @"OK", nil, nil);
    if (device < 0 || device >= (unsigned short)numPtys)
        return;
    if (knownDevices[device] == (struct TerminalKnownTask *)-1)
        return;
    task = knownDevices[device];
    while (task != NULL) {
        struct TerminalKnownTask *next = task->next;
        [self releaseKnownTask:task taskDied:0];
        task = next;
    }
    knownDevices[device] = (struct TerminalKnownTask *)-1;
}

- (void)setShellsClean:(char)newShellsClean
    runningBackgroundClean:(char)newBackgroundClean fastAudits:(char)newFastAudit
    cleanCommands:(const char **)newCommands
{
    unsigned int device;
    struct TerminalKnownTask *task;
    TerminalProcessInfo processInfo;
    unsigned char cleanBit;

    runningBkgndClean = newBackgroundClean;
    shellsClean = newShellsClean;
    fastAudit = newFastAudit;
    cleanCommands = newCommands;
    for (device = 0; device < (unsigned short)numPtys; ++device) {
        task = knownDevices[device];
        if (task == (struct TerminalKnownTask *)-1 || task == NULL)
            continue;
        do {
            get_process_info_from_pid(task->pid, &processInfo);
            if (strcmp(processInfo.command, selfTaskName) != 0) {
                cleanBit = isCommandClean(processInfo.command, newShellsClean,
                    newCommands) ? 0x80 : 0;
                task->stateFlags = (cleanBit & 0x80) |
                    (task->stateFlags & 0x7F);
            } else {
                task->stateFlags |= 0xA0;
            }
            if (!newFastAudit && (task->stateFlags & 0x40) != 0)
                [self releaseKnownTask:task taskDied:0];
            task = task->next;
        } while (task != NULL);
    }
}

- (id)getProcNames:(char (*)[17])names onDevice:(int)device
    howMany:(int *)count
{
    unsigned int setIndex;

    *count = 0;
    if (!monitorOK)
        return self;
    for (setIndex = 0; setIndex < nPrivSets; ++setIndex) {
        task_array_t tasks;
        mach_msg_type_number_t taskCount;
        mach_msg_type_number_t taskIndex;
        kern_return_t result;

        result = processor_set_tasks((processor_set_t)privSets[setIndex],
            &tasks, &taskCount);
        if (result != KERN_SUCCESS) {
            mach_error("processor_set_tasks", result);
            return self;
        }
        for (taskIndex = 0; taskIndex < taskCount; ++taskIndex) {
            int pid;
            TerminalProcessInfo processInfo;

            if (unix_pid(tasks[taskIndex], &pid) == KERN_SUCCESS) {
                get_process_info_from_pid(pid, &processInfo);
                terminal_append_process_name(&processInfo, device,
                    shellsClean, cleanCommands, names, count);
            }
            if (*count > 9) {
                vm_deallocate(mach_task_self(), (vm_address_t)tasks,
                    sizeof(*tasks) * taskCount);
                return self;
            }
        }
        vm_deallocate(mach_task_self(), (vm_address_t)tasks,
            sizeof(*tasks) * taskCount);
    }
    return self;
}

- (char)isDeviceDirty:(int)device
{
    struct TerminalKnownTask *task;
    TerminalProcessInfo processInfo;
    int foregroundProcessGroup;
    int extendedPorts = 0;
    unsigned int setIndex;

    if (!monitorOK)
        return 0;
    if (device >= (unsigned short)numPtys || (device >= 0 &&
            knownDevices[device] == (struct TerminalKnownTask *)-1))
        NSRunAlertPanel(@"DirtMonitor.m",
            @"Dirtiness information sought for invalid or unregistered device.",
            @"OK", nil, nil);
    if (device < 0 || device >= (unsigned short)numPtys ||
            knownDevices[device] == (struct TerminalKnownTask *)-1)
        return 0;

    ioctl(fds[device], 0x40047477u, &foregroundProcessGroup);
    for (task = knownDevices[device]; task != NULL; task = task->next) {
        if (kill(task->pid, 0) == -1)
            continue;
        if (!fastAudit || (task->stateFlags & 0x20) != 0) {
            unsigned char cleanBit;
            get_process_info_from_pid(task->pid, &processInfo);
            if (strcmp(processInfo.command, selfTaskName) != 0) {
                cleanBit = isCommandClean(processInfo.command, shellsClean,
                    cleanCommands) ? 0x80 : 0;
                task->stateFlags = (cleanBit & 0x80) |
                    (task->stateFlags & 0x7F);
            } else {
                task->stateFlags |= 0xA0;
            }
        }
        if (task->pid == foregroundProcessGroup) {
            if ((task->stateFlags & 0x80) == 0 ||
                    !taskIsBlocked(task, 0, freePortNamesMap, fastAudit,
                        numPorts))
                return 1;
        } else if ((task->stateFlags & 0x80) == 0 &&
                (!runningBkgndClean || taskIsBlocked(task, 1,
                    freePortNamesMap, fastAudit, numPorts))) {
            return 1;
        }
    }

    for (setIndex = 0; setIndex < nPrivSets; ++setIndex) {
        task_array_t tasks;
        mach_msg_type_number_t taskCount;
        mach_msg_type_number_t taskIndex;
        kern_return_t result = processor_set_tasks(
            (processor_set_t)privSets[setIndex], &tasks, &taskCount);

        if (result != KERN_SUCCESS) {
            mach_error("processor_set_tasks", result);
            return 0;
        }
        for (taskIndex = 0; taskIndex < taskCount; ++taskIndex) {
            mach_port_t taskPort = tasks[taskIndex];
            int pid;
            struct TerminalKnownTask *knownTask;
            unsigned int terminalDevice;
            unsigned int ptyDevice;

            if (taskPort == mach_task_self())
                continue;
            if (taskPort >= (unsigned short)numPorts) {
                mach_port_t renamedPort;
                kern_return_t renameResult;
                for (;;) {
                    if (fpnStack <= 0) {
                        [self compactFreePortStack];
                        if (fpnStack <= 0 || extendedPorts)
                            [self extendFreePortStack];
                        else
                            extendedPorts = 1;
                    }
                    if (fpnStack <= 0) {
                        vm_deallocate(mach_task_self(),
                            (vm_address_t)tasks, sizeof(*tasks) * taskCount);
                        return 0;
                    }
                    renamedPort = (mach_port_t)freePortNames[--fpnStack];
                    if (FlagIsSet(freePortNamesMap, renamedPort))
                        break;
                }
                renameResult = port_rename(mach_task_self(), taskPort,
                    renamedPort);
                if (renameResult == 4)
                    return 0;
                if (renameResult == 13) {
                    --taskIndex;
                    continue;
                }
                taskPort = renamedPort;
                tasks[taskIndex] = taskPort;
            } else if (FlagIsSet(boringTasks, taskPort) ||
                    goodTasks[taskPort] != NULL) {
                continue;
            }

            SetFlag(freePortNamesMap, taskPort, 0);
            memset(&processInfo, 0, sizeof(processInfo));
            if (unix_pid(taskPort, &pid) != KERN_SUCCESS) {
                SetFlag(boringTasks, taskPort, 1);
                continue;
            }
            get_process_info_from_pid(pid, &processInfo);
            terminalDevice = (unsigned int)processInfo.terminalDevice;
            ptyDevice = terminalDevice & 0xff;
            if (!processInfo.isRunnable || processInfo.pid <= 0 ||
                    ((terminalDevice >> 8) & 0xff) != 4 ||
                    ptyDevice >= (unsigned short)numPtys ||
                    knownDevices[ptyDevice] == (struct TerminalKnownTask *)-1) {
                SetFlag(boringTasks, taskPort, 1);
                continue;
            }
            if (ftStack <= 0) {
                char *records;
                unsigned int index;
                if (ftStack != 0)
                    NSRunAlertPanel(@"DirtMonitor.m",
                        @"Free task stack underflow.", @"OK", nil, nil);
                records = NSZoneMalloc([self zone], 8 *
                    sizeof(struct TerminalKnownTask));
                if (records == NULL)
                    NSRunAlertPanel(@"DirtMonitor.m",
                        @"Couldn't allocate space for more known tasks.",
                        @"OK", nil, nil);
                for (index = 0; index < 8; ++index) {
                    ftStack++;
                    freeTasks[ftStack - 1] =
                        (struct TerminalKnownTask *)(records +
                            index * sizeof(struct TerminalKnownTask));
                }
            }
            knownTask = freeTasks[--ftStack];
            memset(knownTask, 0, sizeof(*knownTask));
            knownTask->portName = taskPort;
            knownTask->pid = processInfo.pid;
            knownTask->device = (unsigned char)ptyDevice;
            knownTask->threadCount = -1;
            if (strcmp(processInfo.command, selfTaskName) != 0) {
                if (isCommandClean(processInfo.command, shellsClean,
                        cleanCommands))
                    knownTask->stateFlags |= 0x80;
            } else {
                knownTask->stateFlags |= 0xA0;
            }
            knownTask->next = knownDevices[knownTask->device];
            if (knownTask->next != NULL)
                knownTask->next->previous = knownTask;
            knownDevices[knownTask->device] = knownTask;
            goodTasks[taskPort] = knownTask;

            if (knownTask->device == device) {
                if (knownTask->pid == foregroundProcessGroup) {
                    if ((knownTask->stateFlags & 0x80) == 0 ||
                            !taskIsBlocked(knownTask, 0, freePortNamesMap,
                                fastAudit, numPorts)) {
                        vm_deallocate(mach_task_self(),
                            (vm_address_t)tasks, sizeof(*tasks) * taskCount);
                        return 1;
                    }
                } else if ((knownTask->stateFlags & 0x80) == 0 &&
                        (!runningBkgndClean || taskIsBlocked(knownTask, 1,
                            freePortNamesMap, fastAudit, numPorts))) {
                    vm_deallocate(mach_task_self(), (vm_address_t)tasks,
                        sizeof(*tasks) * taskCount);
                    return 1;
                }
            }
        }
        vm_deallocate(mach_task_self(), (vm_address_t)tasks,
            sizeof(*tasks) * taskCount);
    }
    return 0;
}

- (void)releaseKnownTask:(struct TerminalKnownTask *)task taskDied:(char)taskDied
{
    struct TerminalKnownTask *previous = task->previous;
    struct TerminalKnownTask *next = task->next;

    goodTasks[task->portName] = NULL;
    if (previous != NULL)
        previous->next = next;
    else
        knownDevices[task->device] = next;
    if (next != NULL)
        next->previous = previous;
    if (!taskDied)
        SetFlag(boringTasks, task->portName, 1);
    [self uncacheThreads:task];
    if (ftStack >= numFreeTasks) {
        numFreeTasks += 8;
        freeTasks = NSZoneRealloc([self zone], freeTasks,
            sizeof(*freeTasks) * (unsigned short)numFreeTasks);
        if (freeTasks == NULL)
            NSRunAlertPanel(@"DirtMonitor.m", @"Free task list overflow.",
                @"OK", nil, nil);
    }
    freeTasks[ftStack++] = task;
    if (ftStack > numFreeTasks)
        NSRunAlertPanel(@"DirtMonitor.m", @"Free task list overflow.",
            @"OK", nil, nil);
}

- (void)uncacheThreads:(struct TerminalKnownTask *)task
{
    signed char threadCount = TerminalTaskThreadCount(task);
    int index;

    if (threadCount == -1 || (task->stateFlags & 0x40) == 0)
        return;
    for (index = 0; index < threadCount; ++index) {
        unsigned int port = task->cachedThreadPorts[(unsigned char)index];
        port_deallocate(mach_task_self(), port);
        if (port != MACH_PORT_NULL && port < (unsigned short)numPorts &&
                !FlagIsSet(freePortNamesMap, port)) {
            if (fpnStack >= numPorts)
                [self compactFreePortStack];
            freePortNames[fpnStack++] = (int)port;
            SetFlag(freePortNamesMap, port, 1);
        }
    }
    task->stateFlags &= (unsigned char)~0x40;
    TerminalSetTaskThreadCount(task, -1);
}

- (void)compactFreePortStack
{
    unsigned int port;
    unsigned int count = 0;

    for (port = 1; port < (unsigned short)numPorts; ++port) {
        if (FlagIsSet(freePortNamesMap, port))
            freePortNames[count++] = (int)port;
    }
    fpnStack = (short)count;
}

- (void)extendFreePortStack
{
    unsigned int port;
    unsigned int oldCount = (unsigned short)numPorts;

    numPorts += 32;
    goodTasks = NSZoneRealloc([self zone], goodTasks,
        sizeof(*goodTasks) * (unsigned short)numPorts);
    if (goodTasks == NULL)
        TerminalMonitorAllocationFailure(self, "goodTasks", 747);
    freePortNames = NSZoneRealloc([self zone], freePortNames,
        sizeof(*freePortNames) * (unsigned short)numPorts);
    if (freePortNames == NULL)
        TerminalMonitorAllocationFailure(self, "freePortNames", 749);
    for (port = oldCount; port < (unsigned short)numPorts; ++port) {
        goodTasks[port] = NULL;
        freePortNames[fpnStack++] = (int)port;
        SetFlag(freePortNamesMap, port, 1);
    }
}

- (void)handleMachMessage:(void *)message
{
    unsigned int *words = (unsigned int *)message;
    unsigned int port;

    if (words[5] != 65)
        return;
    port = words[7];
    if (port >= (unsigned short)numPorts)
        return;
    if (FlagIsSet(boringTasks, port))
        SetFlag(boringTasks, port, 0);
    else if (goodTasks[port] != NULL)
        [self releaseKnownTask:goodTasks[port] taskDied:1];
    if (!FlagIsSet(freePortNamesMap, port)) {
        if (fpnStack >= numPorts)
            [self compactFreePortStack];
        freePortNames[fpnStack++] = (int)port;
        SetFlag(freePortNamesMap, port, 1);
    }
    port_deallocate(mach_task_self(), port);
    if (fpnStack > numPorts)
        NSRunAlertPanel(@"DirtMonitor.m", @"Port name free list overflow.",
            @"OK", nil, nil);
}

@end
