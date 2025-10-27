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
 * NXLock.m
 * NeXT Lock Interface
 */

#import "NXLock.h"
#import <stdlib.h>

/* External mutex/condition functions */
extern int mutex_try_lock(int *mutex);
extern void mutex_wait_lock(int *mutex);
extern void condition_wait(void *cond, int *mutex);
extern void cond_signal(void *cond);
extern void cond_broadcast(void *cond);
extern void spin_lock(void *lock);

/* Lock data structure (28 bytes / 0x1c) */
typedef struct {
    int mutex;           /* offset 0 */
    int reserved1;       /* offset 4 */
    void *condition;     /* offset 8 */
    int waiters;         /* offset 12 (0xc) */
    int reserved2;       /* offset 16 */
    int reserved3;       /* offset 20 */
    char locked;         /* offset 24 (0x18) */
} LockData;

@implementation NXLock

/*
 * Initialize lock
 */
- init
{
    LockData *data;

    [super init];

    /* Allocate lock data structure */
    data = (LockData *)malloc(sizeof(LockData));
    lockData = data;

    /* Initialize all fields to zero */
    data->mutex = 0;
    data->reserved1 = 0;
    data->condition = 0;
    data->waiters = 0;
    data->reserved2 = 0;
    data->reserved3 = 0;
    data->locked = 0;

    return self;
}

/*
 * Free lock
 */
- free
{
    LockData *data = (LockData *)lockData;

    /* Broadcast to any waiters if present */
    if (data->waiters != 0) {
        cond_broadcast(&data->condition);
    }

    /* Acquire spin lock before freeing */
    spin_lock(&data->condition);

    /* Free lock data */
    free(data);

    /* Call superclass free */
    return [super free];
}

/*
 * Acquire lock
 */
- lock
{
    LockData *data = (LockData *)lockData;
    int result;

    /* Try to acquire mutex */
    result = mutex_try_lock(&data->mutex);
    if (result == 0) {
        mutex_wait_lock(&data->mutex);
    }

    /* Wait while lock is held by another thread */
    while (data->locked != 0) {
        condition_wait(&data->condition, &data->mutex);
    }

    /* Mark lock as held */
    data->locked = 1;

    /* Release mutex */
    data->mutex = 0;

    return self;
}

/*
 * Release lock
 */
- unlock
{
    LockData *data = (LockData *)lockData;
    int result;

    /* Try to acquire mutex */
    result = mutex_try_lock(&data->mutex);
    if (result == 0) {
        mutex_wait_lock(&data->mutex);
    }

    /* Clear locked flag */
    data->locked = 0;

    /* Signal any waiting threads */
    if (data->waiters != 0) {
        cond_signal(&data->condition);
    }

    /* Release mutex */
    data->mutex = 0;

    return self;
}

@end
