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

#import "EISAKernBusInterrupt.h"
#import <driverkit/KernLock.h>
#import <driverkit/KernBusInterruptPrivate.h>
#import <machdep/i386/intr_exported.h>

/*
 * Interrupt dispatch wrapper
 * Called by the low-level interrupt handler
 */
static void
EISAKernBusInterruptDispatch(unsigned int which, void *state, int old_ipl)
{
    BOOL leave_enabled;
    EISAKernBusInterrupt *interrupt = (EISAKernBusInterrupt *)which;

    /* Dispatch to registered device interrupt handlers */
    leave_enabled = KernBusInterruptDispatch(interrupt, state);

    /* If handlers want interrupt disabled, disable it */
    if (!leave_enabled) {
        [interrupt->_EISALock acquire];
        if (interrupt->_irqEnabled) {
            intr_disable_irq(interrupt->_irq);
            interrupt->_irqEnabled = NO;
        }
        [interrupt->_EISALock release];
    }
}

/*
 * ============================================================================
 * EISAKernBusInterrupt Implementation
 * ============================================================================
 */

@implementation EISAKernBusInterrupt

- initForResource:resource
             item:(unsigned int)item
        shareable:(BOOL)shareable
{
    [super initForResource:resource item:item shareable:shareable];

    _irq = item;
    _irqEnabled = NO;
    _irqAttached = NO;
    _EISALock = [[KernLock alloc] initWithLevel:INTR_IPL7];
    _priorityLevel = INTR_IPL3;  /* Default to IPL3 for device interrupts */

    return self;
}

- dealloc
{
    /* Make sure interrupt is disabled and detached */
    if (_irqAttached) {
        [_EISALock acquire];
        if (_irqEnabled) {
            intr_disable_irq(_irq);
            _irqEnabled = NO;
        }
        intr_unregister_irq(_irq);
        _irqAttached = NO;
        [_EISALock release];
    }

    [_EISALock free];
    _EISALock = nil;

    return [super dealloc];
}

/*
 * Attach a device interrupt handler at default priority
 */
- attachDeviceInterrupt:interrupt
{
    if (interrupt == nil) {
        return nil;
    }

    [_EISALock acquire];

    /* Register the interrupt with the system if not already done */
    if (!_irqAttached) {
        if (!intr_register_irq(_irq, EISAKernBusInterruptDispatch,
                               (unsigned int)self, _priorityLevel)) {
            IOLog("EISAKernBusInterrupt: Failed to register IRQ %d\n", _irq);
            [_EISALock release];
            return nil;
        }
        _irqAttached = YES;
    }

    /*
     * Call super to attach the device interrupt
     * Returns nil if interrupt is suspended
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        /* Enable the IRQ if not already enabled */
        if (!_irqEnabled) {
            intr_enable_irq(_irq);
            _irqEnabled = YES;
        }
    } else {
        /* Interrupt is suspended, keep IRQ disabled */
        if (_irqEnabled) {
            intr_disable_irq(_irq);
            _irqEnabled = NO;
        }
    }

    [_EISALock release];
    return self;
}

/*
 * Attach a device interrupt handler at specified priority level
 */
- attachDeviceInterrupt:interrupt atLevel:(int)level
{
    if (interrupt == nil) {
        return nil;
    }

    [_EISALock acquire];

    /* Validate priority level */
    if (level < INTR_IPL0 || level > INTR_IPL7) {
        IOLog("EISAKernBusInterrupt: Invalid priority level %d\n", level);
        [_EISALock release];
        return nil;
    }

    /* Update priority level if changed */
    if (_irqAttached && level != _priorityLevel) {
        /* Change the IPL for this IRQ */
        if (!intr_change_ipl(_irq, level)) {
            IOLog("EISAKernBusInterrupt: Failed to change IPL for IRQ %d\n", _irq);
            [_EISALock release];
            return nil;
        }
    }

    _priorityLevel = level;

    /* Register the interrupt with the system if not already done */
    if (!_irqAttached) {
        if (!intr_register_irq(_irq, EISAKernBusInterruptDispatch,
                               (unsigned int)self, _priorityLevel)) {
            IOLog("EISAKernBusInterrupt: Failed to register IRQ %d\n", _irq);
            [_EISALock release];
            return nil;
        }
        _irqAttached = YES;
    }

    /*
     * Call super to attach the device interrupt
     * Returns nil if interrupt is suspended
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        /* Enable the IRQ if not already enabled */
        if (!_irqEnabled) {
            intr_enable_irq(_irq);
            _irqEnabled = YES;
        }
    } else {
        /* Interrupt is suspended, keep IRQ disabled */
        if (_irqEnabled) {
            intr_disable_irq(_irq);
            _irqEnabled = NO;
        }
    }

    [_EISALock release];
    return self;
}

/*
 * Detach a device interrupt handler
 */
- detachDeviceInterrupt:interrupt
{
    [_EISALock acquire];

    /* Call super to detach the device interrupt */
    if (![super detachDeviceInterrupt:interrupt]) {
        /* No more device interrupts attached, disable IRQ */
        if (_irqEnabled) {
            intr_disable_irq(_irq);
            _irqEnabled = NO;
        }
    }

    [_EISALock release];
    return self;
}

/*
 * Suspend interrupt delivery
 */
- suspend
{
    [_EISALock acquire];

    /* Call super to increment suspend count */
    [super suspend];

    /* Disable the IRQ if it's enabled */
    if (_irqEnabled) {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_EISALock release];
    return self;
}

/*
 * Resume interrupt delivery
 */
- resume
{
    [_EISALock acquire];

    /* Call super to decrement suspend count and check if we should resume */
    if ([super resume] && !_irqEnabled) {
        /* Resume was successful and IRQ is not enabled, enable it now */
        intr_enable_irq(_irq);
        _irqEnabled = YES;
    }

    [_EISALock release];
    return self;
}

@end
