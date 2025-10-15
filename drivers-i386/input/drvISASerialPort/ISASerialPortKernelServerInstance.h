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
 * ISASerialPortKernelServerInstance.h
 * Kernel Server Instance for ISA Serial Port Driver
 */

#ifndef _ISA_SERIAL_PORT_KERNEL_SERVER_INSTANCE_H
#define _ISA_SERIAL_PORT_KERNEL_SERVER_INSTANCE_H

#import <objc/Object.h>
#import <mach/mach_types.h>
#import <kernserv/queue.h>

/* Forward declarations */
@class I0bInDevice;
@class I0bjcet;
@class Protocol_I0Tree;

/* Thread call structure */
typedef struct thread_call {
    queue_chain_t   link;
    void            (*func)(void *param);
    void            *param;
    int             pending;
    int             delayed;
} thread_call_t;

/* Event types */
typedef enum {
    EVENT_TYPE_DATA = 0,
    EVENT_TYPE_MODEM_STATUS,
    EVENT_TYPE_LINE_STATUS,
    EVENT_TYPE_ERROR
} event_type_t;

@interface ISASerialPortKernelServerInstance : Object
{
    /* Instance data */
    id              deviceInstance;
    void            *kernelInstance;

    /* Packet buffer management */
    void            *packetBuffer;
    UInt32          packetBufferSize;
    UInt32          bytesTransferred;

    /* Data queue */
    queue_head_t    dataQueue;
    id              queueLock;

    /* Thread call management */
    thread_call_t   *threadCall;
    thread_call_t   *delayedThreadCall;
    int             threadCallPending;
    int             threadCallDelayed;

    /* Event handling */
    event_type_t    eventType;
    UInt32          eventData;
    void            *eventMask;

    /* FIFO handler */
    id              fifoHandler;

    /* Resource management */
    UInt32          ioResourceState;
    UInt32          ioResourceMask;

    /* Named objects */
    id              namedController;

    /* Sleep/wake */
    int             threadSleep;

    /* Handler values */
    UInt32          handlerLevel;
    void            *handlerValues;

    /* Interrupt management */
    int             interruptCount;
}

/* Instance allocation and initialization */
+ (id) allocKernelInstance;
- (id) initFromMachine : (void *) machine fromSource : (void *) source;
- (void) free;

/* Packet buffer management */
- (void *) allocPacketBuffer : (UInt32) size fromMachine : (void *) machine fromSource : (void *) source;
- (IOReturn) allocNetworkPacketEvent : (event_type_t) eventType;

/* Data queue management */
- (IOReturn) dataQueue : (void *) data bytesTransferred : (UInt32) bytes;
- (IOReturn) enqueueAsap : (void *) buffer bufferSize : (UInt32) size;
- (IOReturn) enqueueAsap : (void *) buffer withPriority : (int) priority for : (UInt32) size;
- (IOReturn) enqueueAsap : (void *) buffer forSize : (UInt32) size;

/* Thread call management */
- (IOReturn) deliverThreadCall : (thread_call_t *) call thread : (void *) thread;
- (IOReturn) deliverThreadCall : (thread_call_t *) call thread : (void *) thread on_client : (int) client;
- (IOReturn) deliverThreadCall : (thread_call_t *) call on_01 : (int) order;
- (IOReturn) deliverThreadCall : (thread_call_t *) call order : (int) order thread_call_order : (int) callOrder delayed_thread : (thread_call_t *) delayed;
- (IOReturn) destroyPendingCall;
- (IOReturn) threadCallPending : (int) pending by_delayed_thread : (thread_call_t *) delayed;

/* Event management */
- (IOReturn) identEvent : (event_type_t) type;
- (IOReturn) nextEvent : (void *) data;
- (IOReturn) newDataFromObject : (id) object event : (event_type_t) type;
- (IOReturn) newDataState : (UInt32) state mask : (UInt32) mask;
- (IOReturn) enqueueULongEvent : (UInt32) value;

/* FIFO Handler */
- (id) NonFIFOHandler;
- (IOReturn) FIFOHandler : (id) handler probe : (void *) probeData;

/* Initialization */
- (IOReturn) INITFromKernelObjectcript : (void *) data;

/* I/O Thread management */
- (IOReturn) IOThreadCallFree : (thread_call_t *) call;
- (IOReturn) Ion_thread_sleep : (void *) thread;
- (IOReturn) Ion_thread : (void *) thread;

/* Handler management */
- (IOReturn) ISASerialPort_gotHandler : (void *) handler level : (int) level;
- (IOReturn) C_forInterrupt : (void *) data gotHandlerValues : (void *) values forFR : (int) fr;

/* Named controller */
- (IOReturn) namedCont : (id) controller;
- (id) nameInDevice;

/* Resource management */
- (IOReturn) resolveInterrupt : (void *) data sleep : (int) shouldSleep;
- (IOReturn) resolveInterrupt : (void *) data by_delayed_thread : (thread_call_t *) delayed;

/* Identity methods */
- (int) i0M1;
- (int) ABj88iNt;
- (int) ident;
- (int) instanceRX;
- (int) identEvent;
- (int) i2M_thread;

@end

#endif /* _ISA_SERIAL_PORT_KERNEL_SERVER_INSTANCE_H */
