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
 * Copyright (c) 1993 NeXT Computer, Inc.
 *
 * Kernel EISA Bus Resource Object(s).
 *
 * HISTORY
 *
 * 11 Oct 2025 raynorpat
 *	Created proper EISA bus support for i386.
 */

#import <mach/mach_types.h>

#import <driverkit/KernLock.h>
#import <driverkit/i386/EISAKernBus.h>
#import <driverkit/i386/EISAKernBusPrivate.h>
#import <driverkit/KernDevice.h>
#import <kernserv/i386/spl.h>
#import <machdep/i386/intr_exported.h>

#define IO_NUM_EISA_INTERRUPTS	16


static void
EISAKernBusInterruptDispatch(int deviceIntr, void * ssp, int old_ipl, void *_interrupt)
{
    BOOL			leave_enabled;
    EISAKernBusInterrupt_ *	interrupt = (EISAKernBusInterrupt_ *)_interrupt;

    leave_enabled = KernBusInterruptDispatch(_interrupt, ssp);
    if (!leave_enabled) {
        KernLockAcquire(interrupt->_EISALock);
        intr_disable_irq(interrupt->_irq);
        interrupt->_irqEnabled = NO;
        KernLockRelease(interrupt->_EISALock);
    }
}

@implementation EISAKernBusInterrupt

- initForResource:	resource
	item:		(unsigned int)item
	shareable:	(BOOL)shareable
{
    [super initForResource:resource item:item shareable:shareable];

    _irq = item;
    _irqEnabled = NO;
    _EISALock = [[KernLock alloc] initWithLevel:IPLHIGH];
    _priorityLevel = IPLDEVICE;

    return self;
}

- dealloc
{
    [_EISALock free];
    return [super dealloc];
}

- attachDeviceInterrupt:	interrupt
{
    if (!interrupt)
    	return nil;

    [_EISALock acquire];

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)EISAKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }
    /*
     * -attachDeviceInterrupt will return nil
     * if the interrupt is suspended.
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_EISALock release];

    return self;
}

- attachDeviceInterrupt:	interrupt
		atLevel: 	(int)level
{
    if (!interrupt)
	return nil;

    [_EISALock acquire];

    if (level < _priorityLevel || level >  IPLSCHED) {
	[_EISALock release];
    	return nil;
    }

    if (level > _priorityLevel)
    	intr_change_ipl(_irq, level);

    _priorityLevel = level;

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)EISAKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }
    /*
     * -attachDeviceInterrupt will return nil
     * if the interrupt is suspended.
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_EISALock release];
    return self;
}

- detachDeviceInterrupt:	interrupt
{
    int			irq = [self item];

    [_EISALock acquire];

    if ( ![super detachDeviceInterrupt:interrupt]) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_EISALock release];
    return self;
}

- suspend
{
    [_EISALock acquire];

    [super suspend];

    if (_irqEnabled) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_EISALock release];

    return self;
}

- resume
{
    [_EISALock acquire];

    if ([super resume] && !_irqEnabled) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    }

    [_EISALock release];

    return self;
}

@end



@implementation EISAKernBus

static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    DMA_CHANNELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    NULL
};

+ initialize
{
    [self registerBusClass:self name:"EISA"];
    return self;
}

- init
{
    [super init];

    [self _insertResource:[[KernBusItemResource alloc]
				initWithItemCount:IO_NUM_EISA_INTERRUPTS
				itemKind:[EISAKernBusInterrupt class]
				owner:self]
		    withKey:IRQ_LEVELS_KEY];

    [self _insertResource:[[KernBusRangeResource alloc]
    					initWithExtent:RangeMAX
					kind:[KernBusMemoryRange class]
					owner:self]
		    withKey:MEM_MAPS_KEY];

    [[self class] registerBusInstance:self name:"EISA" busId:[self busId]];

    printf("ISA/EISA bus support enabled\n");
    return self;
}

- (const char **)resourceNames
{
    return resourceNameStrings;
}

- free
{

    if ([self areResourcesActive])
    	return self;

    [[self _deleteResourceWithKey:IRQ_LEVELS_KEY] free];
    [[self _deleteResourceWithKey:MEM_MAPS_KEY] free];

    return [super free];
}

@end
