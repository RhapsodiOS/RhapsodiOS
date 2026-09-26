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
 * EISAKernBusInterrupt.m
 * EISA Kernel Bus Interrupt Handler Implementation
 */

#define KERNEL_PRIVATE 1

#import "EISAKernBusInterrupt.h"
#import <driverkit/KernLock.h>
#import <machdep/i386/intr_exported.h>

/*
 * Private ivar layout, needed so the C dispatch trampoline below (which
 * intr_register_irq calls directly, not via objc_msgSend) can reach the
 * @private instance variables -- the same pattern
 * driverkit/KernBusInterruptPrivate.h uses for the generic
 * KernBusInterruptDispatch().
 */
typedef struct EISAKernBusInterrupt_ {
    @defs(EISAKernBusInterrupt)
} EISAKernBusInterrupt_;

/*
 * _EISAKernBusInterruptDispatch - IRQ dispatch trampoline
 *
 * Registered with intr_register_irq() as the handler for this object's
 * IRQ. Calls the generic KernBusInterruptDispatch() to run any attached
 * device interrupt handlers; if none of them claim the interrupt, disables
 * the IRQ line to prevent an interrupt storm from an unclaimed/shared line
 * (see reconstruction/divergences.md Finding 5).
 */
static void _EISAKernBusInterruptDispatch(unsigned int which, void *state, int old_ipl)
{
    EISAKernBusInterrupt_ *interrupt = (EISAKernBusInterrupt_ *)which;

    if (!KernBusInterruptDispatch((KernBusInterrupt *)interrupt, state)) {
        KernLock *lock = (KernLock *)interrupt->_EISALock;

        [lock acquire];
        intr_disable_irq(interrupt->_irq);
        interrupt->_irqEnabled = NO;
        [lock release];
    }
}

@implementation EISAKernBusInterrupt

/*
 * Initialize an EISA interrupt resource
 *
 * Registers the dispatch trampoline for this IRQ (unless it is IRQ 2, the
 * 8259 slave/cascade line, which has no device behind it to dispatch to),
 * sets the trigger mode from the shareable argument, and allocates the
 * lock used to serialize IRQ enable/disable (see
 * reconstruction/divergences.md Finding 5).
 */
- initForResource:resource item:(unsigned int)item shareable:(BOOL)shareable
{
    [super initForResource:resource item:item shareable:shareable];

    _irq = (int)item;

    if (_irq != 2) {
        intr_register_irq(_irq, _EISAKernBusInterruptDispatch, (unsigned int)self, 3);
        intr_change_mode(_irq, shareable);
    }

    _EISALock = [[KernLock alloc] initWithLevel:7];

    return self;
}

- dealloc
{
    /* Unregister the IRQ */
    intr_unregister_irq(_irq);

    /* Free the lock */
    [_EISALock free];

    /* Call superclass dealloc */
    return [super dealloc];
}

/*
 * Attach a device interrupt handler at default priority
 */
- attachDeviceInterrupt:interrupt
{
    int result;
    KernLock *lock = (KernLock *)_EISALock;

    /* Check for NULL interrupt */
    if (interrupt == nil) {
        return nil;
    }

    /* Acquire lock */
    [lock acquire];

    /* Call superclass to attach the device interrupt */
    result = (int)[super attachDeviceInterrupt:interrupt];

    /* If attachment succeeded and IRQ is not enabled, enable it */
    if (result != 0 && !_irqEnabled) {
        intr_enable_irq(_irq);
        _irqEnabled = YES;
    }

    /* Release lock */
    [lock release];

    return self;
}

/*
 * Attach a device interrupt handler at specified priority level
 */
- attachDeviceInterrupt:interrupt atLevel:(int)level
{
    int result;
    KernLock *lock = (KernLock *)_EISALock;

    /* Check for NULL interrupt */
    if (interrupt == nil) {
        return nil;
    }

    /* Acquire lock */
    [lock acquire];

    /* Validate priority level - must be between current priority and 6 (IPL6) */
    if (level < _priorityLevel || level > 6) {
        [lock release];
        return nil;
    }

    /* If raising priority level, change IPL */
    if (_priorityLevel < level) {
        intr_change_ipl(_irq, level);
    }

    /* Update priority level */
    _priorityLevel = level;

    /* Call superclass to attach the device interrupt */
    result = (int)[super attachDeviceInterrupt:interrupt];

    /* If attachment succeeded and IRQ is not enabled, enable it */
    if (result != 0 && !_irqEnabled) {
        intr_enable_irq(_irq);
        _irqEnabled = YES;
    }

    /* Release lock */
    [lock release];

    return self;
}

/*
 * Detach a device interrupt handler
 */
- detachDeviceInterrupt:interrupt
{
    KernLock *lock = (KernLock *)_EISALock;

    [lock acquire];

    /* Call super to detach the device interrupt */
    if (![super detachDeviceInterrupt:interrupt]) {
        /* No more device interrupts attached, disable IRQ */
        if (_irqEnabled) {
            intr_disable_irq(_irq);
            _irqEnabled = NO;
        }
    }

    [lock release];
    return self;
}

/*
 * Suspend interrupt delivery
 */
- suspend
{
    KernLock *lock = (KernLock *)_EISALock;

    [lock acquire];

    /* Call super to increment suspend count */
    [super suspend];

    /* Disable the IRQ if it's enabled */
    if (_irqEnabled) {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [lock release];
    return self;
}

/*
 * Resume interrupt delivery
 */
- resume
{
    KernLock *lock = (KernLock *)_EISALock;

    [lock acquire];

    /* Call super to decrement suspend count and check if we should resume */
    if ([super resume] && !_irqEnabled) {
        /* Resume was successful and IRQ is not enabled, enable it now */
        intr_enable_irq(_irq);
        _irqEnabled = YES;
    }

    [lock release];
    return self;
}

@end
