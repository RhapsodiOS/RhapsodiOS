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
 * PnPArgStack.m
 * PnP Argument Stack Implementation
 */

#import "PnPArgStack.h"
#import <driverkit/generalFuncs.h>

#define MAX_STACK_DEPTH 32

typedef struct {
    void *items[MAX_STACK_DEPTH];
    int top;
} StackData;

@implementation PnPArgStack

- init
{
    [super init];

    _stackData = IOMalloc(sizeof(StackData));
    if (_stackData != NULL) {
        StackData *stack = (StackData *)_stackData;
        stack->top = -1;
        _depth = 0;
    }

    return self;
}

- free
{
    if (_stackData != NULL) {
        IOFree(_stackData, sizeof(StackData));
        _stackData = NULL;
    }
    return [super free];
}

- (BOOL)push:(void *)data
{
    if (_stackData == NULL) {
        return NO;
    }

    StackData *stack = (StackData *)_stackData;

    if (stack->top >= MAX_STACK_DEPTH - 1) {
        IOLog("PnPArgStack: Stack overflow\n");
        return NO;
    }

    stack->top++;
    stack->items[stack->top] = data;
    _depth = stack->top + 1;

    return YES;
}

- (void *)pop
{
    if (_stackData == NULL) {
        return NULL;
    }

    StackData *stack = (StackData *)_stackData;

    if (stack->top < 0) {
        IOLog("PnPArgStack: Stack underflow\n");
        return NULL;
    }

    void *data = stack->items[stack->top];
    stack->top--;
    _depth = stack->top + 1;

    return data;
}

- (int)depth
{
    return _depth;
}

@end
