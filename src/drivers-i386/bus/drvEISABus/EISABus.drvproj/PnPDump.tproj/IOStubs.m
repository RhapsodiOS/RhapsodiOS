/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * IOStubs.m
 * DriverKit I/O utility stubs for PnPDump
 */

#import <objc/objc-runtime.h>
#import "NXLock.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <stdarg.h>

extern void syslog(int priority, const char *format, ...);

static char noValue[64];

/* Verbose flag referenced by shared lksproj PnP classes */
char verbose = 0;

/* Mach/kernel functions */
extern int thread_suspend(int thread);
extern int thread_resume(int thread);
extern int msg_receive(void *msg, int option, int timeout);
extern int port_allocate(int task, int *port);
extern void kern_timestamp(unsigned long long *timestamp);

/* C thread functions */
extern int cthread_fork(void (*func)(void *), void *arg);
extern void cthread_exit(int result);

extern void calloutThread(void *arg);
extern void __IOCopyMemory(void *dest, const void *src, unsigned int count, unsigned int flags);
extern int *task_self_ptr;

typedef struct CalloutEntry {
    void (*func)(void *);
    void *arg;
    unsigned int timestamp_low;
    unsigned int timestamp_high;
    struct CalloutEntry *prev;
    struct CalloutEntry *next;
} CalloutEntry;

CalloutEntry *calloutChain;
id calloutLock;
int sleepPort;

/* C function implementations */

/*
 * IOMalloc
 * Allocate memory
 */
void *IOMalloc(unsigned int size)
{
    return malloc(size);
}

/*
 * IOFree
 * Free memory
 */
void IOFree(void *ptr, unsigned int size)
{
    free(ptr);
}

/*
 * IOLog
 * Log a message using syslog
 */
void IOLog(const char *format, ...)
{
    char buffer[300];
    va_list args;

    /* Get variadic arguments */
    va_start(args, format);

    /* Format the message */
    vsprintf(buffer, format, args);

    /* Clean up va_list */
    va_end(args);

    /* Log to syslog with priority 3 (LOG_ERR) */
    syslog(3, "%s", buffer);
}

/*
 * IOGetTimestamp
 * Get current timestamp in nanoseconds
 */
void IOGetTimestamp(unsigned int *timestamp)
{
    unsigned long long kern_ts;
    unsigned int ts_low;
    int ts_high;
    int temp;

    /* Get kernel timestamp as 64-bit value */
    kern_timestamp(&kern_ts);
    ts_low = (unsigned int)kern_ts;
    ts_high = (int)(kern_ts >> 32);

    /* Complex calculation to convert to nanoseconds */
    /* This is essentially: timestamp = ts * 1000 (to get nanoseconds) */
    /* The decompiled code shows multiplication by 1000 split into smaller operations */
    temp = (ts_high * 4 | ts_low >> 30) + ts_high + ((ts_low * 4 < ts_low) ? 1 : 0);
    temp = temp + (temp * 4 | (ts_low * 5) >> 30) + ((ts_low * 5 < ts_low * 20) ? 1 : 0);

    timestamp[0] = ts_low * 1000;
    timestamp[1] = ((temp * 4 | (ts_low * 25) >> 30) + temp +
                   ((ts_low * 100 < ts_low * 25) ? 1 : 0)) * 8 | (ts_low * 125) >> 29;
}

/*
 * IOInitGeneralFuncs
 * Initialize general I/O functions and callout chain
 */
void IOInitGeneralFuncs(void)
{
    Class nxLockClass;
    int result;
    CalloutEntry **chainTail;

    /* Initialize callout chain as empty circular list */
    chainTail = (CalloutEntry **)((char *)&calloutChain + 4);
    *chainTail = (CalloutEntry *)&calloutChain;
    calloutChain = (CalloutEntry *)&calloutChain;

    /* Create NXLock object for callout synchronization */
    nxLockClass = objc_getClass("NXLock");
    calloutLock = objc_msgSend(nxLockClass, sel_getUid("new"));

    /* Allocate sleep port */
    result = port_allocate(*task_self_ptr, &sleepPort);
    if (result != 0) {
        IOLog("IOInitGeneralFunc: port_allocate error\n");
    }

    /* Fork callout thread */
    IOForkThread(calloutThread, NULL);
}

/*
 * IOUnscheduleFunc
 * Remove a function from the callout chain
 */
void IOUnscheduleFunc(void (*func)(void *), void *arg)
{
    CalloutEntry *entry;
    CalloutEntry *prev;
    CalloutEntry *next;
    CalloutEntry *prevLink;
    CalloutEntry *nextLink;

    /* Lock the callout chain */
    [calloutLock lock];

    /* Walk the callout chain looking for matching entry */
    entry = calloutChain;
    if (entry != (CalloutEntry *)&calloutChain) {
        do {
            if ((entry->func == func) && (entry->arg == arg)) {
                /* Found matching entry, unlink it */
                prev = entry->prev;
                next = entry->next;

                /* Update prev's next pointer */
                prevLink = prev;
                if (prev != (CalloutEntry *)&calloutChain) {
                    prevLink = (CalloutEntry *)&prev->prev;
                }
                prevLink->next = next;

                /* Update next's prev pointer */
                nextLink = next;
                if (next != (CalloutEntry *)&calloutChain) {
                    nextLink = (CalloutEntry *)&next->prev;
                }
                nextLink->prev = prev;

                /* Free the entry */
                IOFree(entry, 0x18);
                break;
            }

            /* Move to next entry */
            entry = *(CalloutEntry **)&entry->prev;
        } while (entry != (CalloutEntry *)&calloutChain);
    }

    /* Unlock the callout chain */
    [calloutLock unlock];
}

/*
 * IOSuspendThread
 * Suspend a thread
 */
void IOSuspendThread(int *threadPtr)
{
    thread_suspend(threadPtr[1]);
}

/*
 * IOSleep
 * Sleep for specified timeout
 */
void IOSleep(unsigned int timeout)
{
    char msgBuf[4];
    int msgSize;
    int port;

    port = sleepPort;
    msgSize = 0x18;
    msg_receive(msgBuf, 0x500, timeout);
}

/*
 * IOScheduleFunc
 * Schedule a function to be called after a delay
 */
void IOScheduleFunc(void (*func)(void *), void *arg, unsigned int delayMS)
{
    CalloutEntry *entry;
    unsigned int timestamp[2];
    unsigned int origLow;
    unsigned long long delayNS;
    unsigned int delayNS_low;
    unsigned int delayNS_high;
    CalloutEntry **chainPtr;

    /* If no delay, call function immediately */
    if (delayMS == 0) {
        (*func)(arg);
        return;
    }

    /* Allocate callout entry */
    entry = (CalloutEntry *)IOMalloc(0x18);
    entry->func = func;
    entry->arg = arg;

    /* Get current timestamp */
    IOGetTimestamp(timestamp);

    /* Convert milliseconds to nanoseconds: delayMS * 1,000,000,000 */
    /* The decompiled code shows this as delayMS * 1000000000 with complex carry handling */
    delayNS = (unsigned long long)delayMS * 1000000000ULL;
    delayNS_low = (unsigned int)delayNS;
    delayNS_high = (unsigned int)(delayNS >> 32);

    /* Add delay to timestamp with carry handling */
    origLow = timestamp[0];
    timestamp[0] = timestamp[0] + delayNS_low;
    timestamp[1] = timestamp[1] + delayNS_high + ((timestamp[0] < origLow) ? 1 : 0);

    /* Store timestamp in entry */
    entry->timestamp_low = timestamp[0];
    entry->timestamp_high = timestamp[1];

    /* Lock the callout chain */
    [calloutLock lock];

    /* Insert at end of chain */
    if (calloutChain == (CalloutEntry *)&calloutChain) {
        /* Chain is empty */
        calloutChain = entry;
        chainPtr = (CalloutEntry **)((char *)&calloutChain + 4);
        *chainPtr = entry;
        entry->prev = (CalloutEntry *)&calloutChain;
        entry->next = (CalloutEntry *)&calloutChain;
    } else {
        /* Insert at tail */
        chainPtr = (CalloutEntry **)((char *)&calloutChain + 4);
        entry->next = (CalloutEntry *)*chainPtr;
        entry->prev = (CalloutEntry *)&calloutChain;
        (*chainPtr)->prev = entry;
        *chainPtr = entry;
    }

    /* Unlock the callout chain */
    [calloutLock unlock];
}

/*
 * IOResumeThread
 * Resume a suspended thread
 */
void IOResumeThread(int *threadPtr)
{
    thread_resume(threadPtr[1]);
}

/*
 * IOPanic
 * Print panic message and enter infinite loop
 */
void IOPanic(const char *message)
{
    IOLog(message);
    IOLog("waiting for debugger connection...");

    /* Infinite loop waiting for debugger */
    while (1) {
        /* Do nothing */
    }
}

/*
 * IOForkThread
 * Create a new thread
 */
void IOForkThread(void (*func)(void *), void *arg)
{
    cthread_fork(func, arg);
}

/*
 * IOFindValueForName
 * Look up a value by name in a name/value table
 * Table format: alternating int values and char* names, terminated by NULL name
 * Returns 0 on success, 0xfffffd3e (-706) on not found
 */
int IOFindValueForName(const char *name, int *table, int *outValue)
{
    char **namePtr;
    int *valuePtr;
    int result;

    /* Check if table has entries (second element is first name pointer) */
    if (table[1] != 0) {
        namePtr = (char **)(table + 1);
        valuePtr = table;

        /* Walk through table */
        do {
            result = strcmp(*namePtr, name);
            if (result == 0) {
                /* Found match */
                *outValue = *valuePtr;
                return 0;
            }

            /* Advance to next entry (skip value and name pointers) */
            namePtr += 2;
            valuePtr += 2;
        } while (*namePtr != NULL);
    }

    /* Not found */
    return 0xfffffd3e;
}

/*
 * IOFindNameForValue
 * Look up a name by value in a name/value table
 * Table format: alternating int values and char* names, terminated by NULL name
 * Returns pointer to name string, or formatted "N(d) (UNDEFINED)" if not found
 */
char *IOFindNameForValue(int value, int *table)
{
    int *valuePtr;
    char **namePtr;

    /* Check if table has entries */
    if (table[1] != 0) {
        valuePtr = table;
        namePtr = (char **)(table + 1);

        /* Walk through table */
        do {
            if (*valuePtr == value) {
                /* Found match */
                return *namePtr;
            }

            /* Advance to next entry */
            namePtr += 2;
            valuePtr += 2;
        } while (*namePtr != NULL);
    }

    /* Not found - format undefined value string */
    sprintf(noValue, "%d(d) (UNDEFINED)", value);
    return noValue;
}

/*
 * IOExitThread
 * Exit current thread with -1 result
 */
void IOExitThread(void)
{
    cthread_exit(0xffffffff);
}

/*
 * IODelay
 * Busy-wait delay for specified microseconds
 */
void IODelay(unsigned int microseconds)
{
    unsigned int currentTime[2];
    unsigned long long targetTime;
    unsigned int targetTime_low;
    unsigned long long delayNS;

    /* Get current timestamp */
    IOGetTimestamp(currentTime);

    /* Convert microseconds to nanoseconds and add to current time */
    delayNS = (unsigned long long)microseconds * 1000;
    targetTime = ((unsigned long long)currentTime[1] << 32) | currentTime[0];
    targetTime += delayNS;
    targetTime_low = (unsigned int)targetTime;

    /* Busy-wait until target time reached */
    do {
        IOGetTimestamp(currentTime);
    } while ((int)(targetTime_low - currentTime[0]) >= 0);
}

/*
 * IOCopyMemory
 * Copy memory with flags
 */
void IOCopyMemory(void *dest, const void *src, unsigned int count, unsigned int flags)
{
    __IOCopyMemory(dest, src, count, flags);
}
