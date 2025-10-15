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

/**
 * ISASerialPortKernelServerInstance.m
 * Kernel Server Instance Implementation for ISA Serial Port Driver
 */

#import "ISASerialPortKernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
#import <mach/mach_interface.h>
#import <string.h>

/* Stub classes for compatibility */
@interface I0bInDevice : Object
@end

@implementation I0bInDevice
@end

@interface I0bjcet : Object
@end

@implementation I0bjcet
@end

@interface Protocol_I0Tree : Object
@end

@implementation Protocol_I0Tree
@end

@implementation ISASerialPortKernelServerInstance

/*
 * Allocate kernel instance
 */
+ (id) allocKernelInstance
{
    return [[self alloc] init];
}

/*
 * Initialize from machine and source
 */
- (id) initFromMachine : (void *) machine fromSource : (void *) source
{
    self = [super init];
    if (self) {
        kernelInstance = machine;
        deviceInstance = nil;
        packetBuffer = NULL;
        packetBufferSize = 0;
        bytesTransferred = 0;

        /* Initialize queue */
        queue_init(&dataQueue);
        queueLock = [[NXLock alloc] init];

        /* Initialize thread call */
        threadCall = NULL;
        delayedThreadCall = NULL;
        threadCallPending = 0;
        threadCallDelayed = 0;

        /* Initialize event data */
        eventType = EVENT_TYPE_DATA;
        eventData = 0;
        eventMask = NULL;

        /* Initialize FIFO handler */
        fifoHandler = nil;

        /* Initialize resources */
        ioResourceState = 0;
        ioResourceMask = 0;

        namedController = nil;
        threadSleep = 0;
        handlerLevel = 0;
        handlerValues = NULL;
        interruptCount = 0;
    }
    return self;
}

/*
 * Free instance
 */
- (void) free
{
    if (packetBuffer) {
        IOFree(packetBuffer, packetBufferSize);
        packetBuffer = NULL;
    }

    if (queueLock) {
        [queueLock free];
        queueLock = nil;
    }

    if (threadCall) {
        IOFree(threadCall, sizeof(thread_call_t));
        threadCall = NULL;
    }

    if (delayedThreadCall) {
        IOFree(delayedThreadCall, sizeof(thread_call_t));
        delayedThreadCall = NULL;
    }

    [super free];
}

/*
 * Allocate packet buffer from machine/source
 */
- (void *) allocPacketBuffer : (UInt32) size fromMachine : (void *) machine fromSource : (void *) source
{
    if (packetBuffer) {
        IOFree(packetBuffer, packetBufferSize);
    }

    packetBufferSize = size;
    packetBuffer = IOMalloc(size);

    if (packetBuffer) {
        memset(packetBuffer, 0, size);
    }

    return packetBuffer;
}

/*
 * Allocate network packet event
 */
- (IOReturn) allocNetworkPacketEvent : (event_type_t) eventType
{
    self->eventType = eventType;
    return IO_R_SUCCESS;
}

/*
 * Data queue management
 */
- (IOReturn) dataQueue : (void *) data bytesTransferred : (UInt32) bytes
{
    [queueLock lock];
    bytesTransferred = bytes;
    /* Queue data processing would go here */
    [queueLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Enqueue data ASAP with buffer size
 */
- (IOReturn) enqueueAsap : (void *) buffer bufferSize : (UInt32) size
{
    [queueLock lock];
    /* Enqueue buffer for ASAP processing */
    [queueLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Enqueue data ASAP with priority
 */
- (IOReturn) enqueueAsap : (void *) buffer withPriority : (int) priority for : (UInt32) size
{
    [queueLock lock];
    /* Enqueue buffer with priority */
    [queueLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Enqueue data ASAP for size
 */
- (IOReturn) enqueueAsap : (void *) buffer forSize : (UInt32) size
{
    [queueLock lock];
    /* Enqueue buffer for specified size */
    [queueLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Deliver thread call
 */
- (IOReturn) deliverThreadCall : (thread_call_t *) call thread : (void *) thread
{
    if (call && call->func) {
        call->func(call->param);
    }
    return IO_R_SUCCESS;
}

/*
 * Deliver thread call on client
 */
- (IOReturn) deliverThreadCall : (thread_call_t *) call thread : (void *) thread on_client : (int) client
{
    if (call && call->func) {
        call->func(call->param);
    }
    return IO_R_SUCCESS;
}

/*
 * Deliver thread call on order 01
 */
- (IOReturn) deliverThreadCall : (thread_call_t *) call on_01 : (int) order
{
    if (call && call->func) {
        call->func(call->param);
    }
    return IO_R_SUCCESS;
}

/*
 * Deliver thread call with order and delayed thread
 */
- (IOReturn) deliverThreadCall : (thread_call_t *) call order : (int) order thread_call_order : (int) callOrder delayed_thread : (thread_call_t *) delayed
{
    if (call && call->func) {
        call->func(call->param);
    }

    if (delayed && delayed->func) {
        delayed->func(delayed->param);
    }

    return IO_R_SUCCESS;
}

/*
 * Destroy pending call
 */
- (IOReturn) destroyPendingCall
{
    threadCallPending = 0;
    return IO_R_SUCCESS;
}

/*
 * Thread call pending by delayed thread
 */
- (IOReturn) threadCallPending : (int) pending by_delayed_thread : (thread_call_t *) delayed
{
    threadCallPending = pending;
    delayedThreadCall = delayed;
    return IO_R_SUCCESS;
}

/*
 * Identify event
 */
- (IOReturn) identEvent : (event_type_t) type
{
    eventType = type;
    return IO_R_SUCCESS;
}

/*
 * Get next event
 */
- (IOReturn) nextEvent : (void *) data
{
    /* Return next event data */
    return IO_R_SUCCESS;
}

/*
 * New data from object with event
 */
- (IOReturn) newDataFromObject : (id) object event : (event_type_t) type
{
    eventType = type;
    return IO_R_SUCCESS;
}

/*
 * New data state with mask
 */
- (IOReturn) newDataState : (UInt32) state mask : (UInt32) mask
{
    ioResourceState = state;
    ioResourceMask = mask;
    return IO_R_SUCCESS;
}

/*
 * Enqueue unsigned long event
 */
- (IOReturn) enqueueULongEvent : (UInt32) value
{
    eventData = value;
    return IO_R_SUCCESS;
}

/*
 * Non-FIFO handler
 */
- (id) NonFIFOHandler
{
    return nil;
}

/*
 * FIFO handler probe
 */
- (IOReturn) FIFOHandler : (id) handler probe : (void *) probeData
{
    fifoHandler = handler;
    return IO_R_SUCCESS;
}

/*
 * Initialize from kernel object script
 */
- (IOReturn) INITFromKernelObjectcript : (void *) data
{
    return IO_R_SUCCESS;
}

/*
 * I/O thread call free
 */
- (IOReturn) IOThreadCallFree : (thread_call_t *) call
{
    if (call) {
        IOFree(call, sizeof(thread_call_t));
    }
    return IO_R_SUCCESS;
}

/*
 * I/O thread sleep
 */
- (IOReturn) Ion_thread_sleep : (void *) thread
{
    threadSleep = 1;
    return IO_R_SUCCESS;
}

/*
 * I/O thread
 */
- (IOReturn) Ion_thread : (void *) thread
{
    return IO_R_SUCCESS;
}

/*
 * ISA Serial Port got handler
 */
- (IOReturn) ISASerialPort_gotHandler : (void *) handler level : (int) level
{
    handlerLevel = level;
    return IO_R_SUCCESS;
}

/*
 * C for interrupt
 */
- (IOReturn) C_forInterrupt : (void *) data gotHandlerValues : (void *) values forFR : (int) fr
{
    handlerValues = values;
    return IO_R_SUCCESS;
}

/*
 * Named controller
 */
- (IOReturn) namedCont : (id) controller
{
    namedController = controller;
    return IO_R_SUCCESS;
}

/*
 * Name in device
 */
- (id) nameInDevice
{
    return deviceInstance;
}

/*
 * Resolve interrupt with sleep
 */
- (IOReturn) resolveInterrupt : (void *) data sleep : (int) shouldSleep
{
    threadSleep = shouldSleep;
    interruptCount++;
    return IO_R_SUCCESS;
}

/*
 * Resolve interrupt by delayed thread
 */
- (IOReturn) resolveInterrupt : (void *) data by_delayed_thread : (thread_call_t *) delayed
{
    delayedThreadCall = delayed;
    interruptCount++;
    return IO_R_SUCCESS;
}

/*
 * Identity method i0M1
 */
- (int) i0M1
{
    return 0x01;
}

/*
 * Identity method ABj88iNt
 */
- (int) ABj88iNt
{
    return 0x88;
}

/*
 * Identity method ident
 */
- (int) ident
{
    return 0x01;
}

/*
 * Identity method instanceRX
 */
- (int) instanceRX
{
    return bytesTransferred;
}

/*
 * Identity method identEvent
 */
- (int) identEvent
{
    return (int)eventType;
}

/*
 * Identity method i2M_thread
 */
- (int) i2M_thread
{
    return threadCallPending;
}

@end
