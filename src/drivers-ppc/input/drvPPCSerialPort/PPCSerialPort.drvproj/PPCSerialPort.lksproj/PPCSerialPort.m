/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * PPCSerialPort.m - Zilog 85C30 SCC serial port driver for PowerPC Macs.
 *
 * Reconstructed from the 1.2v3 PPCSerialPort_reloc (drvPPCSerialPort-5).
 * Functions appear in the binary's order.  Apple shipped it with MyIOLog
 * compiled to nothing; the calls are kept so it can be switched back on.
 * Places where this source deliberately differs from the binary are marked
 * "Divergence from 5.6".
 */

#import "PPCSerialPort.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <kernserv/prototypes.h>
#import <kernserv/ppc/spl.h>
#import <string.h>
#import <stdio.h>
#import <stdlib.h>

#define eieio()     __asm__ volatile("eieio")

extern boolean_t test_and_set(int bit, int *addr);

/* The layout must match the binary's ivar encoding byte for byte. */
typedef char PortSizeCheck[(sizeof(Port) == 364) ? 1 : -1];

static void         SetStructureDefaults(Port *port, BOOL full);
static IOReturn     activatePort(Port *port);
static void         deactivatePort(Port *port);
static void         dataLatTOHandler(Port *port);
static void         frameTOHandler(Port *port);
static void         delayTOHandler(Port *port);
static void         heartBeatTOHandler(Port *port);
static IOReturn     executeEvent(Port *port, unsigned int event, unsigned int data,
                        unsigned int *state, unsigned int *delta);
static void         freeRingBuffer(CirQueue *q);
static BOOL         allocateRingBuffer(CirQueue *q, unsigned int size);
static void         CheckQueues(Port *port);
static void         changeState(Port *port, unsigned int state, unsigned int mask);
static IOReturn     watchState(Port *port, unsigned long *state, unsigned long mask);
static void         MyIOLog(const char *format, ...);
static void         initChip(Port *port);
static void         programChip(Port *port);
static int          ProbeSccDevice(Port *port);
static int          OpenScc(Port *port);
static void         SccCloseChannel(Port *port);
static int          SccSetStopBits(Port *port, unsigned int bits);
static int          SccSetParity(Port *port, unsigned char parity);
static int          SccSetDataBits(Port *port, unsigned int bits);
static int          SccSetBaud(Port *port, unsigned int baud);
static unsigned char SccReadData(Port *port);
static unsigned char SccReadReg(Port *port, unsigned char reg);
static int          SccWriteReg(Port *port, unsigned char reg, unsigned char value);
static void         SccWriteIntSafe(Port *port, unsigned char reg, unsigned char value);
static void         PPCSerialRxDMAISR(void *identity, void *state, Port *port);
static void         PPCSerialTxDMAISR(void *identity, void *state, Port *port);
static void         PPCSerialISR(void *identity, void *state, Port *port);
static int          SccHandleExtInterrupt(Port *port);
static int          SccHandleRxInterrupt(Port *port);
static int          SccHandleTxInterrupt(Port *port);
static int          SetUpTransmit(Port *port);
static int          SuspendTX(Port *port);
static int          SccWriteByte(Port *port, unsigned char c);
static unsigned char SccDisableInterrupts(Port *port, unsigned int which);
static void         SccEnableInterrupts(Port *port, unsigned int which, unsigned char saved);
static void         InitQueue(CirQueue *q, char *buffer, unsigned int size);
static void         CloseQueue(CirQueue *q);
static unsigned int AddtoQueue(CirQueue *q, unsigned char *buffer, unsigned int size);
static unsigned int RemovefromQueue(CirQueue *q, unsigned char *buffer, unsigned int size);
static unsigned int FreeSpaceinQueue(CirQueue *q);
static unsigned int UsedSpaceinQueue(CirQueue *q);
static unsigned int GetQueueSize(CirQueue *q);
static int          AddBytetoQueue(CirQueue *q, unsigned char c);
static int          GetBytetoQueue(CirQueue *q, unsigned char *c);

/* SccEnableInterrupts / SccDisableInterrupts selectors */
#define kSccTxInt       4       /* WR5 transmit enable */
#define kSccRxInt       5       /* WR3 receiver enable */
#define kSccMasterInt   6       /* WR9 master interrupt enable */

/* OpenScc's register program: (register, value) pairs.  WR9's first value is
   the channel A reset, replaced by the channel B reset for ch-b. */
static const unsigned char sccInitTable[34] = {
     9, 0x80,   4, 0x44,   3, 0xc0,   5, 0xe2,   2, 0x00,  10, 0x00,
    11, 0x50,  12, 0x00,  13, 0x00,   3, 0xc1,   5, 0xea,  14, 0x01,
    15, 0x00,   0, 0x10,   0, 0x10,   1, 0x12,   9, 0x0a
};

/* WR3 receive and WR5 transmit bits-per-character, for 5..8 data bits. */
static unsigned char LocalDataBits[4] = { 0x00, 0x80, 0x40, 0xc0 };
static unsigned char LocalTxDataBits[4] = { 0x00, 0x40, 0x20, 0x60 };

@implementation PPCSerialPort

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    MyIOLog("************* In Probe ********************\n\r");
    return [[PPCSerialPort alloc]
        initFromDeviceDescription:deviceDescription] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    id              configTable;
    const char     *nodeName;
    const char     *value;
    char            name[32];
    IORange        *range;
    unsigned int    i;
    unsigned int    numInterrupts;
    id              result;

    MyIOLog("[initFromDeviceDescription:\n\r");
    port = &self->Port;
    port->Self = self;
    SetStructureDefaults(port, YES);
    port->WatchLock.lock_data[0] = 0;
    port->WatchLock.lock_data[1] = 0;
    port->WatchLock.lock_data[2] = 0;
    port->WatchLock.lock_data[3] = 0;

    configTable = [deviceDescription configTable];
    if (configTable == nil) {
        MyIOLog(" Invalid config table]");
        MyIOLog("PPCSerialPort: Invalid Config Table\n");
        return [self free];
    }

    nodeName = [(id)deviceDescription nodeName];
    if (strncmp(nodeName, "ch-a", 4) == 0)
        port->whichPort = 0;
    else if (strncmp(nodeName, "ch-b", 4) == 0)
        port->whichPort = 1;
    else
        MyIOLog("Invalid Channel Name %s\n\r", nodeName);
    port->Instance = port->whichPort;
    MyIOLog("Node Name %s %d\n\r", nodeName, port->whichPort);

    [configTable valueForStringKey:"Instance"];
    sprintf(name, "PPCSerialPort%d", port->Instance);
    [self setName:name];
    [self setDeviceKind:"Serial"];
    port->PortName = (char *)[self name];
    MyIOLog("ejk After Port Name %s [%d].\n\r", port->PortName, port->Instance);

    range = [deviceDescription memoryRangeList];
    for (i = 0; i < [deviceDescription numMemoryRanges]; i++)
        MyIOLog("%08x-%08x \n\r", range[i].start,
            range[i].start + range[i].size - 1);
    port->TxDMABase = (char *)range[1].start;
    port->TxDMALength = range[1].size;
    port->RxDMABase = (char *)range[2].start;
    port->RxDMALength = range[2].size;
    port->Base = range[0].start;
    port->ChipBaseAddress = range[0].start;

    numInterrupts = [deviceDescription numInterrupts];
    MyIOLog("Interrupt info %d %d\n\r", numInterrupts, 3);
    /* Divergence from 5.6: also accept a channel with only the SCC interrupt,
       as QEMU's g3beige OpenBIOS lists it; the DMA handlers only count. */
    if (numInterrupts != 3 && numInterrupts != 1) {
        MyIOLog(" Invalid config ");
        MyIOLog("%s: Invalid configuration\n", [self name]);
        return [self free];
    }
    MyIOLog("} Interrupts={ Num %d\n\r ", numInterrupts);
    for (i = 0; i < numInterrupts; i++) {
        MyIOLog("%d ", [deviceDescription interruptList][i]);
        port->InterruptNumbers[i] = [deviceDescription interruptList][i];
    }
    MyIOLog("}\n\r ");

    initChip(port);
    MyIOLog("initFromDeviceDescription: after InitChip \n\r");
    port->FrameTOEntry = thread_call_allocate(
        (thread_call_func_t)frameTOHandler, (thread_call_spec_t)port);
    port->DataLatTOEntry = thread_call_allocate(
        (thread_call_func_t)dataLatTOHandler, (thread_call_spec_t)port);
    port->DelayTOEntry = thread_call_allocate(
        (thread_call_func_t)delayTOHandler, (thread_call_spec_t)port);
    port->HeartBeatTOEntry = thread_call_allocate(
        (thread_call_func_t)heartBeatTOHandler, (thread_call_spec_t)port);
    MyIOLog("initFromDeviceDescription: after Thread Allocation\n\r");
    if (port->FrameTOEntry == NULL || port->DataLatTOEntry == NULL
     || port->DelayTOEntry == NULL || port->HeartBeatTOEntry == NULL) {
        MyIOLog("%s: Unable to allocate callout entries\n", [self name]);
        return [self free];
    }
    MyIOLog("initFromDeviceDescription: after Thread Check\n\r");

    value = [configTable valueForStringKey:"TX Buffer Size"];
    port->TXStats.BufferSize = 1200;
    if (value != NULL)
        port->TXStats.BufferSize = strtol(value, NULL, 10);
    value = [configTable valueForStringKey:"RX Buffer Size"];
    port->RXStats.BufferSize = 1200;
    if (value != NULL)
        port->RXStats.BufferSize = strtol(value, NULL, 10);

    result = [super initFromDeviceDescription:deviceDescription];
    if (result == nil)
        return [self free];
    MyIOLog("After Super Init\n\r");
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        MyIOLog(" Unable to enable interrupts]");
        MyIOLog("%s: Unable to enable interrupts\n", [self name]);
        return [self free];
    }
    [self registerDevice];
    MyIOLog("After register Self\n\r");
    return result;
}

static void
SetStructureDefaults(Port *port, BOOL full)
{
    unsigned int i;

    if (full) {
        port->Instance = 0;
        port->PortName = NULL;
        port->MasterClock = 1843200;
        port->DLRimage = 0;
        port->LCRimage = 0;
        port->FCRimage = 0;
        port->IERmask = 0;
        port->RBRmask = 0;
        port->Base = 0;
        port->DataLatInterval.tv_sec = 0;
        port->DataLatInterval.tv_nsec = 0;
        port->CharLatInterval.tv_sec = 0;
        port->CharLatInterval.tv_nsec = 0;
        port->HeartBeatInterval.tv_sec = 0;
        port->HeartBeatInterval.tv_nsec = 0;
        port->State = PD_S_TXQ_EMPTY | PD_S_TXQ_LOW_WATER
                    | PD_S_RXQ_EMPTY | PD_S_RXQ_LOW_WATER;
        port->WatchStateMask = 0;
        port->ourMachineType = 7;
    }
    port->BreakLength = 0;
    port->BaudRate = 0;
    port->CharLength = 0;
    port->BreakLength = 0;
    port->StopBits = 0;
    port->TX_Parity = 0;
    port->RX_Parity = 0;
    port->WaitingForTXIdle = 0;
    port->MinLatency = 0;
    port->XONchar = 0x11;
    port->XOFFchar = 0x13;
    port->FlowControl = 0;
    port->RXOstate = 0;
    port->TXOstate = 0;
    port->FrameTOEntry = NULL;
    port->DataLatTOEntry = NULL;
    port->FrameInterval.tv_sec = 0;
    port->FrameInterval.tv_nsec = 0;
    port->RXStats.BufferSize = 1200;
    port->RXStats.HighWater = 800;
    port->RXStats.LowWater = 400;
    port->TXStats.BufferSize = 1200;
    /* The binary derives the TX marks from the RX ones. */
    port->TXStats.HighWater = 2 * port->RXStats.BufferSize / 3;
    port->TXStats.LowWater = port->RXStats.HighWater >> 1;
    port->FlowControl = 0x126;
    port->AreTransmitting = 0;
    for (i = 0; i < 8; i++)
        port->SWspecial[i] = 0;
    port->Stats.ints = 0;
    port->Stats.txInts = 0;
    port->Stats.rxInts = 0;
    port->Stats.mdmInts = 0;
    port->Stats.txChars = 0;
    port->Stats.rxChars = 0;
}

- free
{
    unsigned int s;

    MyIOLog(" [free:");
    s = splpower();
    deactivatePort(port);
    [self disableAllInterrupts];
    if (port->ControlRegister != NULL)
        SccCloseChannel(port);
    if (port->FrameTOEntry != NULL) {
        thread_call_cancel(port->FrameTOEntry);
        thread_call_free(port->FrameTOEntry);
    }
    if (port->DataLatTOEntry != NULL) {
        thread_call_cancel(port->DataLatTOEntry);
        thread_call_free(port->DataLatTOEntry);
    }
    if (port->DelayTOEntry != NULL) {
        thread_call_cancel(port->DelayTOEntry);
        thread_call_free(port->DelayTOEntry);
    }
    if (port->HeartBeatTOEntry != NULL) {
        thread_call_cancel(port->HeartBeatTOEntry);
        thread_call_free(port->HeartBeatTOEntry);
    }
    MyIOLog("]\n\r");
    splx(s);
    return [super free];
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    MyIOLog("getHandler %d\n\r", localInterrupt);
    if (localInterrupt == 1) {
        MyIOLog("getHandler PPCSerialTxDMAISR\n\r");
        *handler = (IOInterruptHandler)PPCSerialTxDMAISR;
    } else if (localInterrupt == 0) {
        MyIOLog("getHandler PPCSerialISR\n\r");
        *handler = (IOInterruptHandler)PPCSerialISR;
    } else if (localInterrupt == 2) {
        MyIOLog("getHandler PPCSerialRxDMAISR\n\r");
        *handler = (IOInterruptHandler)PPCSerialRxDMAISR;
    }
    *ipl = 24;
    *arg = (unsigned int)port;
    return YES;
}

- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count
{
    const char *value;

    MyIOLog("getCharValue\n\r");
    if (parameterArray != NULL && count != NULL && *count != 0) {
        value = [[[self deviceDescription] configTable]
            valueForStringKey:parameterName];
        if (value != NULL) {
            strncpy((char *)parameterArray, value, *count - 1);
            parameterArray[*count - 1] = 0;
            *count = strlen((char *)parameterArray) + 1;
            return IO_R_SUCCESS;
        }
    }
    return [super getCharValues:parameterArray forParameter:parameterName
        count:count];
}

static IOReturn
activatePort(Port *port)
{
    MyIOLog(" activatePort\n\r");
    if (port->State & PD_S_ACTIVE)
        return IO_R_SUCCESS;
    if (allocateRingBuffer(&port->TX, port->TXStats.BufferSize)) {
        if (allocateRingBuffer(&port->RX, port->RXStats.BufferSize)) {
            SetStructureDefaults(port, NO);
            changeState(port, PD_S_ACTIVE, PD_S_ACTIVE);
            MyIOLog("End Act State %x\n\r", port->State);
            return IO_R_SUCCESS;
        }
    }
    freeRingBuffer(&port->TX);
    return IO_R_RESOURCE;
}

static void
deactivatePort(Port *port)
{
    MyIOLog("deactivatePort");
    if (port->State & PD_S_ACTIVE) {
        MyIOLog("deactivateport ChangeState");
        changeState(port, 0, PD_S_ACTIVE);
        freeRingBuffer(&port->TX);
        freeRingBuffer(&port->RX);
        SccCloseChannel(port);
    }
}

- (IOReturn)acquire:(BOOL)sleep
{
    unsigned long   state = 0;
    unsigned int    s;
    short           waits = 0;
    IOReturn        rc;

    MyIOLog("[acquire ");
    for (;;) {
        s = splpower();
        state = port->State & PD_S_ACQUIRED;
        if (state == 0) {
            /* Acquired, enabled and the modem lines up, as shipped. */
            changeState(port, 0xa0400018, 0xffffffff);
            break;
        }
        if (!sleep) {
            MyIOLog("Busy!]");
            splx(s);
            return IO_R_EXCLUSIVE_ACCESS;
        }
        state = 0;
        rc = [self watchState:&state mask:PD_S_ACQUIRED];
        if (rc != IO_R_IO && rc != IO_R_SUCCESS) {
            MyIOLog("Interrupted!]");
            splx(s);
            return rc;
        }
        splx(s);
        /* As shipped: after a second wait it opens the channel without
           taking the port. */
        if (++waits > 1)
            break;
    }
    OpenScc(port);
    MyIOLog("Early]\n\r");
    splx(s);
    return IO_R_SUCCESS;
}

- (IOReturn)release
{
    unsigned int s;
    unsigned int i;

    MyIOLog("[release ");
    s = splpower();
    if ((port->State & PD_S_ACQUIRED) == 0) {
        MyIOLog("NOT OPEN]");
        splx(s);
        return IO_R_NOT_OPEN;
    }
    thread_call_cancel(port->HeartBeatTOEntry);
    thread_call_cancel(port->DelayTOEntry);
    thread_call_cancel(port->DataLatTOEntry);
    thread_call_cancel(port->FrameTOEntry);
    for (i = 0; i < 8; i++)
        port->SWspecial[i] = 0;
    port->CharLength = 8;
    port->BreakLength = 1;
    port->XONchar = 0x11;
    port->XOFFchar = 0x13;
    port->StopBits = 2;
    port->TX_Parity = 1;
    port->RX_Parity = 0;
    port->RXOstate = 0;
    port->BaudRate = 9600;
    port->FlowControl = 0x126;
    deactivatePort(port);
    changeState(port, 0, 0xffffffff);
    MyIOLog("OK]\n\r");
    splx(s);
    return IO_R_SUCCESS;
}

- (IOReturn)setState:(unsigned long)state mask:(unsigned long)mask
{
    unsigned int s;

    MyIOLog("++>setState %d %x\n\r", state, mask);
    if (mask & (PD_S_ACQUIRED | PD_S_ACTIVE | PD_RS232_S_DELAY))
        return IO_R_INVALID_ARG;
    s = splpower();
    if ((port->State & PD_S_ACQUIRED) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    /* Lines under automatic flow control cannot be set by hand. */
    mask &= ~(port->FlowControl >> 16) | 0xffff0000;
    if (mask != 0)
        changeState(port, state, mask);
    MyIOLog("-->setState\n\r");
    splx(s);
    return IO_R_SUCCESS;
}

- (unsigned long)getState
{
    CheckQueues(port);
    return port->State & ~PD_RS232_S_DELAY;
}

- (IOReturn)watchState:(unsigned long *)state mask:(unsigned long)mask
{
    unsigned int    s;
    IOReturn        rc;

    MyIOLog("watchState\n\r");
    s = splpower();
    if ((port->State & PD_S_ACQUIRED) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    rc = watchState(port, state, mask & ~PD_RS232_S_DELAY);
    *state &= ~PD_RS232_S_DELAY;
    splx(s);
    return rc;
}

- (unsigned long)nextEvent
{
    unsigned int s;

    MyIOLog("nextEvent\n\r");
    s = splpower();
    splx(s);
    return 0;
}

- (IOReturn)executeEvent:(unsigned long)event data:(unsigned long)data
{
    IOReturn        rc = IO_R_SUCCESS;
    unsigned int    s;
    unsigned int    state;
    unsigned int    delta;
    unsigned int    usec;

    s = splpower();
    MyIOLog("executeEvent\n\r");
    if ((port->State & PD_S_ACQUIRED) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    switch (event) {
    case PD_E_TXQ_SIZE:
    case PD_E_RXQ_SIZE:
    case PD_E_FLOW_CONTROL:     /* as shipped: accepted and ignored here */
        break;
    case PD_E_DELAY:
        /* 1000 * data wraps at 32 bits, as in the binary, so 32-bit
           division gives its result without the 64-bit helpers. */
        usec = 1000 * data;
        port->CharLatInterval.tv_sec = usec / 1000000000;
        port->CharLatInterval.tv_nsec = usec % 1000000000;
        break;
    default:
        delta = 0;
        state = port->State;
        rc = executeEvent(port, event, data, &state, &delta);
        changeState(port, state, delta);
        break;
    }
    splx(s);
    return rc;
}

- (IOReturn)requestEvent:(unsigned long)event data:(unsigned long *)data
{
    tvalspec_t interval;

    MyIOLog("requestEvent2\n\r");
    if (data == NULL)
        return IO_R_INVALID_ARG;
    switch (event) {
    case PD_E_ACTIVE:
        *data = (port->State & PD_S_ACTIVE) != 0;
        break;
    case PD_E_TXQ_SIZE:
        *data = GetQueueSize(&port->TX);
        break;
    case PD_E_RXQ_SIZE:
        *data = GetQueueSize(&port->RX);
        break;
    case PD_E_TXQ_AVAILABLE:
        *data = FreeSpaceinQueue(&port->TX);
        break;
    case PD_E_RXQ_AVAILABLE:
        *data = UsedSpaceinQueue(&port->RX);
        break;
    case PD_E_DATA_RATE:
        *data = 2 * port->BaudRate;
        break;
    case PD_E_DATA_SIZE:
        *data = 2 * port->CharLength;
        break;
    case PD_RS232_E_STOP_BITS:
        *data = 2 * port->StopBits;
        break;
    case PD_E_RX_DATA_RATE:
    case PD_E_RX_DATA_SIZE:
    case PD_RS232_E_RX_STOP_BITS:
        *data = 0;
        break;
    case PD_E_DATA_INTEGRITY:
        *data = port->TX_Parity;
        break;
    case PD_E_RX_DATA_INTEGRITY:
        *data = port->RX_Parity;
        break;
    case PD_E_DELAY:
    case PD_E_DATA_LATENCY:
        interval = (event == PD_E_DELAY) ? port->CharLatInterval
                                         : port->DataLatInterval;
        /* Microseconds, truncated to 32 bits as the binary's 64-bit
           (tv_sec * 10^9 + tv_nsec) / 1000 is. */
        *data = interval.tv_sec * 1000000 + interval.tv_nsec / 1000;
        break;
    case PD_E_FLOW_CONTROL:
        *data = port->FlowControl;
        break;
    case PD_RS232_E_MIN_LATENCY:
        *data = port->MinLatency != 0;
        break;
    case PD_RS232_E_XOFF_BYTE:
        *data = port->XOFFchar;
        break;
    case PD_RS232_E_XON_BYTE:
        *data = port->XONchar;
        break;
    case PD_RS232_E_LINE_BREAK:
        *data = (port->State & PD_RS232_S_BRK) != 0;
        break;
    default:
        return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)enqueueEvent:(unsigned long)event
                    data:(unsigned long)data
                   sleep:(BOOL)sleep
{
    unsigned int s;

    MyIOLog("enqueueEvent\n\r", event, data, sleep);
    s = splpower();
    if ((port->State & PD_S_ACTIVE) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    splx(s);
    return IO_R_SUCCESS;
}

- (IOReturn)dequeueEvent:(unsigned long *)event
                    data:(unsigned long *)data
                   sleep:(BOOL)sleep
{
    unsigned int s;

    MyIOLog("dequeueEvent\n\r", event, data, sleep);
    if (event == NULL || data == NULL)
        return IO_R_INVALID_ARG;
    s = splpower();
    if ((port->State & PD_S_ACTIVE) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    splx(s);
    return IO_R_SUCCESS;
}

- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep
{
    unsigned long   state = PD_S_TXQ_LOW_WATER;
    unsigned int    remaining = size;
    unsigned int    done;
    unsigned int    s;
    IOReturn        rc;

    if (count == NULL || buffer == NULL)
        return IO_R_INVALID_ARG;
    MyIOLog("++>In Enqueue %d %d %d\n\r", size, *count, sleep);
    *count = 0;
    s = splpower();
    if ((port->State & PD_S_ACTIVE) == 0) {
        splx(s);
        return IO_R_NOT_OPEN;
    }
    *count = AddtoQueue(&port->TX, buffer, size);
    changeState(port, 0, PD_S_TXQ_EMPTY);
    done = *count;
    SetUpTransmit(port);
    while (done < size && sleep) {
        remaining -= *count;
        state = PD_S_TXQ_LOW_WATER;
        MyIOLog("TX Enqueue Entereing WatchState\n\r");
        rc = [self watchState:&state mask:PD_S_TXQ_LOW_WATER];
        if (rc != IO_R_SUCCESS) {
            MyIOLog("Interrupted!]");
            splx(s);
            return rc;
        }
        splx(s);
        *count = AddtoQueue(&port->TX, buffer + done, remaining);
        changeState(port, 0, PD_S_TXQ_EMPTY);
        done += *count;
        SetUpTransmit(port);
    }
    /* Divergence from 5.6: report the whole transfer; the binary leaves the
       last chunk's count, so a caller would resend what was already queued. */
    *count = done;
    MyIOLog("Enqueue Check %x\n\r", UsedSpaceinQueue(&port->TX));
    [self enableAllInterrupts];
    MyIOLog("-->Out Enqueue\n\r");
    splx(s);
    return IO_R_SUCCESS;
}

- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount
{
    unsigned long   state = 0;
    unsigned int    done;
    unsigned int    s;
    IOReturn        rc = IO_R_SUCCESS;

    if ((port->State & PD_S_ACTIVE) == 0)
        return IO_R_NOT_OPEN;
    if (count == NULL || buffer == NULL || minCount > size)
        return IO_R_INVALID_ARG;
    MyIOLog("++>In Dequeue %x %d %d %d\n\r", buffer, size, *count, minCount);
    s = splpower();
    *count = RemovefromQueue(&port->RX, buffer, size);
    changeState(port, PD_S_RXQ_EMPTY, PD_S_RXQ_EMPTY);
    done = *count;
    while (done < minCount) {
        state = 0;
        MyIOLog("dequeueData: Entering WatchState %d\n\r", done);
        rc = [self watchState:&state mask:PD_S_RXQ_EMPTY];
        if (rc != IO_R_SUCCESS) {
            MyIOLog("Interrupted!]");
            break;
        }
        splx(s);
        done += RemovefromQueue(&port->RX, buffer + done, size - done);
        changeState(port, PD_S_RXQ_EMPTY, PD_S_RXQ_EMPTY);
    }
    /* Divergence from 5.6: report the whole transfer, not the last chunk. */
    *count = done;
    if (rc == IO_R_SUCCESS) {
        MyIOLog("dequeueData: Exit from WatchState\n\r");
        if (port->RXOstate == -1
         && UsedSpaceinQueue(&port->RX) < port->RXStats.LowWater) {
            port->RXOstate = 0;
            /* Divergence from 5.6: resume the sender with XON; the binary
               queues XOFF here, which keeps it stopped. */
            AddBytetoQueue(&port->TX, port->XONchar);
            SetUpTransmit(port);
        }
        MyIOLog("-->Out Dequeue\n\r");
    }
    splx(s);
    return rc;
}

@end

static void
dataLatTOHandler(Port *port)
{
    unsigned int s;

    MyIOLog("dataLatTOHandler\n\r");
    s = splpower();
    splx(s);
}

static void
frameTOHandler(Port *port)
{
    unsigned int s;

    MyIOLog("frameToHandler\n\r");
    s = splpower();
    port->WaitingForTXIdle = 0;
    PPCSerialISR(NULL, NULL, port);
    splx(s);
}

static void
delayTOHandler(Port *port)
{
    unsigned int s;

    MyIOLog("delayTOHandler\n\r");
    s = splpower();
    port->State &= ~PD_RS232_S_DELAY;
    PPCSerialISR(NULL, NULL, port);
    splx(s);
}

static void
heartBeatTOHandler(Port *port)
{
    unsigned int s;

    MyIOLog("heartBeatTOHandler\n\r");
    s = splpower();
    PPCSerialISR(NULL, NULL, port);
    thread_call_enter_delayed(port->HeartBeatTOEntry,
        deadline_from_interval(port->HeartBeatInterval));
    splx(s);
}

static IOReturn
executeEvent(Port *port, unsigned int event, unsigned int data,
    unsigned int *state, unsigned int *delta)
{
    IOReturn        rc = IO_R_SUCCESS;
    unsigned int    usec;
    unsigned int    changed;
    tvalspec_t      interval;

    MyIOLog("ExecuteEvent5 %d %d\n\r", event, data);
    if ((port->State & PD_S_ACQUIRED) == 0)
        return IO_R_NOT_OPEN;

    switch (event) {
    case PD_E_ACTIVE:
        MyIOLog("-ExecuteEvent PD_E_ACTIVE\n\r");
        if ((unsigned char)data)
            rc = activatePort(port);
        else
            deactivatePort(port);
        break;

    case PD_E_TXQ_LOW_WATER:
    case PD_E_RXQ_LOW_WATER:
    case PD_E_TXQ_HIGH_WATER:
    case PD_E_RXQ_HIGH_WATER:
    case PD_E_TXQ_FLUSH:
    case PD_E_RXQ_FLUSH:
        break;

    case PD_E_DATA_RATE:
        data >>= 1;             /* half-bits per second */
        MyIOLog("-ExecuteEvent PD_E_DATA_RATE %d\n\r", data);
        if (data - 100 > 57500)
            rc = IO_R_INVALID_ARG;
        else {
            port->BaudRate = data;
            if (!SccSetBaud(port, data))
                rc = IO_R_INVALID_ARG;
        }
        break;

    case PD_E_RX_DATA_RATE:
    case PD_E_RX_DATA_SIZE:
    case PD_RS232_E_RX_STOP_BITS:
        if (data != 0)
            rc = IO_R_INVALID_ARG;
        break;

    case PD_E_DATA_SIZE:
        data >>= 1;             /* half-bits */
        MyIOLog("-ExecuteEvent PD_E_DATA_SIZE\n\r");
        if (data - 5 > 3)
            rc = IO_R_INVALID_ARG;
        else {
            port->CharLength = data;
            if (!SccSetDataBits(port, data))
                rc = IO_R_INVALID_ARG;
        }
        break;

    case PD_E_DATA_INTEGRITY:
        MyIOLog("-ExecuteEvent PD_E_DATA_INTEGRITY\n\r");
        if (data == 0 || data > 5)
            rc = IO_R_INVALID_ARG;
        else {
            port->TX_Parity = data;
            port->RX_Parity = 0;
            if (!SccSetParity(port, data))
                rc = IO_R_INVALID_ARG;
        }
        break;

    case PD_E_RX_DATA_INTEGRITY:
        if (data == 0 || data == 6)
            port->RX_Parity = data;
        else
            rc = IO_R_INVALID_ARG;
        break;

    case PD_E_DELAY:
        if (data != 0) {
            if (data > 4294967)
                data = 4294967;
            *state |= PD_RS232_S_DELAY;
            usec = 1000 * data;
            interval.tv_sec = usec / 1000000000;
            interval.tv_nsec = usec % 1000000000;
            thread_call_enter_delayed(port->DelayTOEntry,
                deadline_from_interval(interval));
        }
        break;

    case PD_E_DATA_LATENCY:
        usec = 1000 * data;     /* wraps at 32 bits, as in the binary */
        port->DataLatInterval.tv_sec = usec / 1000000000;
        port->DataLatInterval.tv_nsec = usec % 1000000000;
        break;

    case PD_E_FLOW_CONTROL:
        MyIOLog("-ExecuteEvent PD_E_FLOW_CONTROL\n\r");
        changed = ((data & 0x160000) >> 16) & ~port->FlowControl;
        *delta |= changed;
        *state = (changed & data) | (*state & ~changed);
        if (changed & PD_RS232_A_RXO)
            port->RXOstate = (data & PD_RS232_A_RXO) ? 2 : 1;
        break;

    case PD_E_VALID_DATA_BYTE:
        port->SWspecial[data >> 5] &= ~(1 << (data & 31));
        break;

    case PD_E_SPECIAL_BYTE:
        port->SWspecial[data >> 5] |= 1 << (data & 31);
        break;

    case PD_RS232_E_MIN_LATENCY:
        port->MinLatency = (data != 0);
        port->DLRimage = 0;
        programChip(port);
        break;

    case PD_RS232_E_XOFF_BYTE:
        port->XOFFchar = data;
        break;

    case PD_RS232_E_XON_BYTE:
        port->XONchar = data;
        break;

    case PD_RS232_E_STOP_BITS:
        MyIOLog("-ExecuteEvent PD_RS232_E_STOP_BITS\n\r");
        if (data > 20)
            rc = IO_R_INVALID_ARG;
        else {
            port->StopBits = data;
            if (!SccSetStopBits(port, data))
                rc = IO_R_INVALID_ARG;
        }
        break;

    case PD_RS232_E_LINE_BREAK:
        *state &= ~PD_RS232_S_BRK;
        *delta |= PD_RS232_S_BRK;
        break;

    default:
        rc = IO_R_INVALID_ARG;
        break;
    }
    return rc;
}

static void
freeRingBuffer(CirQueue *q)
{
    MyIOLog("In freeRingBuffer\n\r");
    IOFree(q->Start, q->Size);
    CloseQueue(q);
}

static BOOL
allocateRingBuffer(CirQueue *q, unsigned int size)
{
    char *buffer;

    MyIOLog("In allocateRingBuffer\n\r");
    /* As shipped: the buffer is always one page, whatever size asks for. */
    buffer = IOMalloc(4096);
    InitQueue(q, buffer, 4096);
    return buffer != NULL;
}

static void
CheckQueues(Port *port)
{
    unsigned long   state = port->State;
    unsigned int    size, free, used;

    size = GetQueueSize(&port->TX);
    free = FreeSpaceinQueue(&port->TX);
    used = size - free;
    if (free != 0)
        state &= ~PD_S_TXQ_FULL;
    else
        state |= PD_S_TXQ_FULL;
    /* As shipped: the binary updates PD_S_TXQ_FULL again here where the
       empty bit would be expected; kept, since PortServer works with it. */
    if (used != 0)
        state |= PD_S_TXQ_FULL;
    else
        state &= ~PD_S_TXQ_FULL;
    if (used < port->TXStats.LowWater)
        state |= PD_S_TXQ_LOW_WATER;
    else
        state &= ~PD_S_TXQ_LOW_WATER;
    if (used > port->TXStats.HighWater)
        state |= PD_S_TXQ_HIGH_WATER;
    else
        state &= ~PD_S_TXQ_HIGH_WATER;

    size = GetQueueSize(&port->RX);
    free = FreeSpaceinQueue(&port->RX);
    used = size - free;
    if (free != 0)
        state &= ~PD_S_RXQ_FULL;
    else
        state |= PD_S_RXQ_FULL;
    if (used != 0)
        state &= ~PD_S_RXQ_EMPTY;
    else
        state |= PD_S_RXQ_EMPTY;
    if (used < port->RXStats.LowWater)
        state |= PD_S_RXQ_LOW_WATER;
    else
        state &= ~PD_S_RXQ_LOW_WATER;
    if (used > port->RXStats.HighWater)
        state |= PD_S_RXQ_HIGH_WATER;
    else
        state &= ~PD_S_RXQ_HIGH_WATER;

    changeState(port, state, state ^ port->State);
}

static void
changeState(Port *port, unsigned int state, unsigned int mask)
{
    unsigned long old = port->State;

    MyIOLog("++>changeState(%x, %x, %x) %x\n\r", state, mask, port->State,
        port->WatchStateMask);
    port->State = (old & ~mask) | (state & mask);
    if ((port->State ^ old) & port->WatchStateMask) {
        MyIOLog("changeState Calling thread_wakeup\n\r");
        thread_wakeup_prim(&port->WatchStateMask, 0, 4);
    }
    MyIOLog("-->changeState %x \n\r", port->State);
}

/*
 * Sleep until one of the bits in mask matches *state.  Unless the caller is
 * watching PD_S_ACQUIRED or PD_S_ACTIVE itself, the port going inactive
 * also ends the wait, with IO_R_IO.
 */
static IOReturn
watchState(Port *port, unsigned long *state, unsigned long mask)
{
    unsigned long   ref = *state;
    unsigned long   matched;
    BOOL            watchingActive = NO;
    IOReturn        rc;

    if ((mask & (PD_S_ACQUIRED | PD_S_ACTIVE)) == 0) {
        ref &= ~PD_S_ACTIVE;
        mask |= PD_S_ACTIVE;
        watchingActive = YES;
    }
    for (;;) {
        matched = ~(port->State ^ ref) & mask;
        MyIOLog("WatchState %x\n\r", matched);
        if (matched != 0)
            break;
        while (test_and_set(0, (int *)&port->WatchLock))
            continue;
        port->WatchStateMask |= mask;
        thread_sleep(&port->WatchStateMask, (simple_lock_t)&port->WatchLock,
            TRUE);
        if (thread_wait_result() != 4) {        /* THREAD_RESTART */
            rc = IO_R_IPC_FAILURE;
            goto out;
        }
    }
    *state = port->State;
    rc = IO_R_SUCCESS;
    if (watchingActive && (matched & PD_S_ACTIVE))
        rc = IO_R_IO;
out:
    port->WatchStateMask = 0;
    thread_wakeup_prim(&port->WatchStateMask, 0, 4);
    return rc;
}

static void
MyIOLog(const char *format, ...)
{
}

static void
initChip(Port *port)
{
    MyIOLog("ejk In initChip()\n\r");
    port->TX_Parity = 1;
    port->RX_Parity = 0;
    port->DLRimage = 0;
    port->FCRimage = 0;
    ProbeSccDevice(port);
}

static void
programChip(Port *port)
{
}

static int
ProbeSccDevice(Port *port)
{
    MyIOLog("In ProbeSccDevice\n\r");
    switch (port->ourMachineType) {
    case 0: case 5: case 6: case 7: case 8:
        port->DataRegister = (char *)(port->ChipBaseAddress + 0x10);
        port->ControlRegister = (char *)port->ChipBaseAddress;
        break;
    case 1: case 2: case 3: case 4:
        port->DataRegister = (char *)(port->ChipBaseAddress + 4);
        port->ControlRegister = (char *)port->ChipBaseAddress;
        break;
    default:
        MyIOLog("** Undefined Machine Type\n\r");
        break;
    }
    /* RR2 is read through channel B, whose control register opens the chip. */
    port->ConfigWriteRegister = port->ChipBaseAddress & 0xffffff00;
    port->baudRateGeneratorEnable = 1;
    port->rtxcFrequency = 3686400;
    SccWriteReg(port, 1, 0);
    MyIOLog("SccProbe %x %x\n\r", port->DataRegister, port->ControlRegister);
    return 1;
}

static int
OpenScc(Port *port)
{
    unsigned char   program[34];
    unsigned int    i;

    memcpy(program, sccInitTable, sizeof(program));
    MyIOLog("In OpenSCC %d\n\r", port->whichPort);
    if (port->whichPort == 1)
        program[1] = 0x40;          /* WR9 channel B reset */
    for (i = 0; i < sizeof(program); i += 2)
        SccWriteReg(port, program[i], program[i + 1]);
    SccEnableInterrupts(port, kSccMasterInt, 0);
    SccEnableInterrupts(port, kSccRxInt, 0);
    SccWriteReg(port, 0, 0x20);
    MyIOLog("PPCSerOpen End \n\r");
    return 0;
}

static void
SccCloseChannel(Port *port)
{
    SccDisableInterrupts(port, kSccMasterInt);
    SccDisableInterrupts(port, kSccRxInt);
    SccDisableInterrupts(port, kSccTxInt);
    SccWriteReg(port, 1, 0);
    SccWriteReg(port, 11, 0);
    SccWriteReg(port, 14, 0);
    SccWriteReg(port, 15, 0x08);
    SccWriteReg(port, 0, 0x10);
    SccWriteReg(port, 0, 0x10);
    SccWriteReg(port, 1, 1);
    SccWriteReg(port, 9, 0x80);
    SccWriteReg(port, 9, 0x40);
    MyIOLog("In SccCloseChannel %d\n\r", port->whichPort);
}

static unsigned char
SccReadByte(Port *port)
{
    if ((SccReadReg(port, 0) & 0x01) == 0)
        return 0;
    eieio();
    return *port->DataRegister;
}

static int
SccWriteByte(Port *port, unsigned char c)
{
    if ((SccReadReg(port, 0) & 0x04) == 0)
        return 0;
    *port->DataRegister = c;
    eieio();
    return 1;
}

static int
SccSetStopBits(Port *port, unsigned int bits)
{
    unsigned char wr4;

    MyIOLog("SccSetStopBits %d\n\r", bits);
    switch (bits) {
    case 0: wr4 = 0x00; break;
    case 2: wr4 = 0x04; break;      /* 1 stop bit, in half bits */
    case 3: wr4 = 0x08; break;      /* 1.5 */
    case 4: wr4 = 0x0c; break;      /* 2 */
    default: return 0;
    }
    SccWriteReg(port, 4, wr4 | (port->lastWR[4] & 0xf3));
    return 1;
}

static int
SccSetParity(Port *port, unsigned char parity)
{
    MyIOLog("SccSetParity %d\n\r", parity);
    switch (parity) {
    case 1:     /* none */
        SccWriteReg(port, 4, port->lastWR[4] & 0xfe);
        return 1;
    case 2:     /* odd */
        SccWriteReg(port, 4, (port->lastWR[4] & 0xfd) | 0x01);
        return 1;
    case 3:     /* even */
        SccWriteReg(port, 4, port->lastWR[4] | 0x03);
        return 1;
    default:
        return 0;
    }
}

static int
SccSetDataBits(Port *port, unsigned int bits)
{
    unsigned int i;

    if (bits - 5 > 3)
        return 0;
    i = bits - 5;
    MyIOLog("In Set Data Bits %d Tx %x Rx %x\n\r", i, LocalTxDataBits[i],
        LocalDataBits[i]);
    SccWriteReg(port, 5, LocalTxDataBits[i] | (port->lastWR[5] & 0x9f));
    SccWriteReg(port, 3, LocalDataBits[i] | (port->lastWR[3] & 0x3f));
    return 1;
}

static void
SccChannelReset(Port *port)
{
    if (port->whichPort == 0)
        SccWriteReg(port, 9, 0x82);
    else if (port->whichPort == 1)
        SccWriteReg(port, 9, 0x42);
}

static int
SccSetBaud(Port *port, unsigned int baud)
{
    unsigned int tc;

    /* Time constant = rtxc / (2 * 16 * baud) - 2, rounded. */
    if (baud == 0
     || (tc = ((port->rtxcFrequency / (16 * baud) + 1) >> 1) - 2) > 0xffff)
        tc = 0xffff;
    port->baudRateGeneratorLo = tc;
    port->baudRateGeneratorHi = tc >> 8;
    SccWriteIntSafe(port, 12, port->baudRateGeneratorLo);
    SccWriteIntSafe(port, 13, port->baudRateGeneratorHi);
    SccWriteIntSafe(port, 14, 0x01);
    port->BaudRate = baud;
    MyIOLog("SetBaud %d %d %d\n\r", baud, port->baudRateGeneratorLo,
        port->baudRateGeneratorHi);
    return 1;
}

static unsigned char
SccReadData(Port *port)
{
    return *port->DataRegister;
}

static int
SccWriteData(Port *port, unsigned char c)
{
    *port->DataRegister = c;
    eieio();
    return 1;
}

static unsigned char
SccReadReg(Port *port, unsigned char reg)
{
    if (reg != 0) {
        *port->ControlRegister = reg;
        eieio();
    }
    eieio();
    return *port->ControlRegister;
}

static int
SccWriteReg(Port *port, unsigned char reg, unsigned char value)
{
    if (reg <= 15) {
        *port->ControlRegister = reg;
        eieio();
        *port->ControlRegister = value;
        eieio();
        port->lastWR[reg] = value;
    }
    return 1;
}

static void
SccWriteIntSafe(Port *port, unsigned char reg, unsigned char value)
{
    if (reg <= 15) {
        *port->ControlRegister = reg;
        eieio();
        *port->ControlRegister = value;
        eieio();
        port->lastWR[reg] = value;
    }
}

static void
PPCSerialRxDMAISR(void *identity, void *state, Port *port)
{
    port->Stats.ints++;
    IOEnableInterrupt(identity);
}

static void
PPCSerialTxDMAISR(void *identity, void *state, Port *port)
{
    port->Stats.ints++;
    IOEnableInterrupt(identity);
}

/*
 * Poll the interrupt vector in RR2 (read through channel B, status low) and
 * dispatch until it reports no transmit or receive work.
 */
static void
PPCSerialISR(void *identity, void *state, Port *port)
{
    unsigned short  tries = 100;
    unsigned char   vector = 0;
    BOOL            more = YES;

    port->Stats.ints++;
    do {
        if (tries-- == 0) {
            /* Divergence from 5.6: the binary closes the channel here.  A
               transmitter that empties as fast as it is fed (QEMU's ESCC)
               keeps the vector at "Tx" for 100 polls, so the port died
               after 101 bytes; stop polling and take the next interrupt. */
            MyIOLog("***** In PPCSerialISR TimeOut Failure %x\n\r", vector);
            break;
        }
        *(volatile unsigned char *)port->ConfigWriteRegister = 2;
        eieio();
        IODelay(50);
        vector = *(volatile unsigned char *)port->ConfigWriteRegister;
        eieio();
        IODelay(50);
        vector = (vector >> 1) & 3;
        switch (vector) {
        case 0:
            SccHandleTxInterrupt(port);
            break;
        case 1:
            SccHandleExtInterrupt(port);
            more = NO;
            MyIOLog("ExtStatusInterrupt Int %x\n\r", SccReadReg(port, 0));
            break;
        case 2:
            SccHandleRxInterrupt(port);
            break;
        case 3:
            MyIOLog("RecErrorStatus Int %x\n\r", SccReadReg(port, 0));
            SccWriteReg(port, 0, 0x30);     /* error reset */
            more = NO;
            break;
        }
    } while (more);
    IOEnableInterrupt(identity);
}

static int
SccHandleExtInterrupt(Port *port)
{
    unsigned char rr0 = SccReadReg(port, 0);

    if (rr0 & 0x01)
        MyIOLog("Ext-> kRxCharAvailable\n\r");
    if (rr0 & 0x02)
        MyIOLog("Ext-> kZeroCount\n\r");
    if (rr0 & 0x04)
        MyIOLog("Ext-> kTxBufferEmpty\n\r");
    if (rr0 & 0x08)
        MyIOLog("Ext-> kDCDAsserted\n\r");
    if (rr0 & 0x10)
        MyIOLog("Ext-> kSyncHunt\n\r");
    if (rr0 & 0x20)
        MyIOLog("Ext-> kCTSAsserted\n\r");
    if (rr0 & 0x40) {
        changeState(port, 0, PD_S_TX_BUSY);
        MyIOLog("Ext-> kTXUnderRun\n\r");
    }
    if (rr0 & 0x80)
        MyIOLog("Ext-> kBreakReceived\n\r");
    SccWriteReg(port, 0, 0x10);     /* reset external/status interrupts */
    return 0;
}

static int
SccHandleRxInterrupt(Port *port)
{
    unsigned short  tries = 100;
    unsigned char   c;

    port->Stats.rxChars++;
    port->Stats.rxInts++;
    while (SccReadReg(port, 0) & 0x01) {
        if (tries-- == 0)
            break;
        c = SccReadData(port);
        if (port->FlowControl & PD_RS232_A_RXO) {
            /* As shipped: under software flow control the XON and XOFF
               characters are consumed and nothing else is queued. */
            if (c == port->XOFFchar)
                SuspendTX(port);
            if (c == port->XONchar)
                SetUpTransmit(port);
        } else
            AddBytetoQueue(&port->RX, c);
        changeState(port, 0, PD_S_RXQ_EMPTY);
        if (UsedSpaceinQueue(&port->RX) > port->RXStats.HighWater) {
            port->RXOstate = 1;
            SetUpTransmit(port);
        }
        if (SccReadReg(port, 1) & 0x20) {
            port->OverRunChars++;
            SccWriteReg(port, 0, 0x30);
            SccWriteReg(port, 0, 0x30);
        }
    }
    SccEnableInterrupts(port, kSccRxInt, 0);
    return 0;
}

static int
SccHandleTxInterrupt(Port *port)
{
    unsigned char   saved;
    unsigned char   c;

    saved = SccDisableInterrupts(port, 0);
    port->Stats.txChars++;
    port->Stats.txInts++;
    SccWriteReg(port, 0, 0x28);     /* reset Tx interrupt pending */
    SccWriteReg(port, 0, 0x10);
    port->AreTransmitting = 1;
    changeState(port, PD_S_TX_BUSY, PD_S_TX_BUSY);
    if (port->RXOstate == 1) {
        SccWriteByte(port, port->XOFFchar);
        port->RXOstate = -1;
    } else if (port->RXOstate == 2) {
        SccWriteByte(port, port->XONchar);
        port->RXOstate = 0;
    } else if (GetBytetoQueue(&port->TX, &c) == 2) {
        port->AreTransmitting = 0;
        changeState(port, PD_S_TXQ_EMPTY, PD_S_TXQ_EMPTY);
        changeState(port, 0, PD_S_TX_BUSY);
        SccWriteReg(port, 5, port->lastWR[5] & 0xf7);
        MyIOLog("In Tx Interrupt Terminating\n\r");
    } else {
        SccWriteByte(port, c);
        CheckQueues(port);
    }
    SccEnableInterrupts(port, 0, saved);
    return 0;
}

static int
SetUpTransmit(Port *port)
{
    unsigned char c;

    MyIOLog("++> SetUpTransmit\n\r");
    if (port->AreTransmitting == 1) {
        MyIOLog("--> SetUpTransmit Already Set\n\r");
        return 0;
    }
    if (port->RXOstate == 1) {
        SccWriteByte(port, port->XOFFchar);
        port->RXOstate = -1;
    }
    if (port->RXOstate == 2) {
        SccWriteByte(port, port->XONchar);
        port->RXOstate = 0;
    }
    if (GetBytetoQueue(&port->TX, &c) != 2) {
        SccWriteReg(port, 1, port->lastWR[1] | 0x02);   /* Tx interrupt enable */
        SccEnableInterrupts(port, kSccMasterInt, 0);
        SccEnableInterrupts(port, kSccTxInt, 0);
        port->AreTransmitting = 1;
        changeState(port, PD_S_TX_BUSY, PD_S_TX_BUSY);
        SccWriteByte(port, c);
        MyIOLog("Write First byte. (%x)\n\r", c);
    }
    MyIOLog("--> SetUpTransmit\n\r");
    return 1;
}

static int
SuspendTX(Port *port)
{
    SccDisableInterrupts(port, kSccTxInt);
    return 1;
}

static int
SendNextChar(Port *port)
{
    return SccWriteReg(port, 1, 0x12);
}

/* Clear one enable and return the register's previous value. */
static unsigned char
SccDisableInterrupts(Port *port, unsigned int which)
{
    unsigned char saved = 0;

    switch (which) {
    case kSccTxInt:
        saved = port->lastWR[5];
        SccWriteReg(port, 5, saved & 0xf7);
        break;
    case kSccRxInt:
        saved = port->lastWR[3];
        SccWriteReg(port, 3, saved & 0xfe);
        break;
    case kSccMasterInt:
        saved = port->lastWR[9];
        SccWriteReg(port, 9, saved & 0xf5);
        break;
    }
    return saved;
}

static void
SccEnableInterrupts(Port *port, unsigned int which, unsigned char saved)
{
    switch (which) {
    case kSccTxInt:
        SccWriteReg(port, 5, port->lastWR[5] | 0x08);
        break;
    case kSccRxInt:
        SccWriteReg(port, 3, port->lastWR[3] | 0x01);
        SccWriteReg(port, 0, 0x20);     /* enable interrupt on next Rx char */
        break;
    case kSccMasterInt:
        SccWriteReg(port, 9, port->lastWR[9] | 0x0a);
        break;
    }
}

static void
SccSetDTR(Port *port, BOOL on)
{
    SccWriteReg(port, 5, on ? (port->lastWR[5] | 0x80)
                            : (port->lastWR[5] & 0x7f));
}

static void
SccSetRTS(Port *port, BOOL on)
{
    SccWriteReg(port, 5, on ? (port->lastWR[5] | 0x02)
                            : (port->lastWR[5] & 0xfd));
}

static unsigned char
SccGetDCD(Port *port)
{
    unsigned char dcd = SccReadReg(port, 0) & 0x08;

    if (dcd)
        port->State |= PD_RS232_S_DCD;
    else
        port->State &= ~PD_RS232_S_DCD;
    return dcd;
}

static unsigned char
SccGetCTS(Port *port)
{
    unsigned char cts = SccReadReg(port, 0) & 0x20;

    if (cts)
        port->State |= PD_RS232_S_CTS;
    else
        port->State &= ~PD_RS232_S_CTS;
    return cts;
}

static void
InitQueue(CirQueue *q, char *buffer, unsigned int size)
{
    q->Start = buffer;
    q->End = buffer + size;
    q->Size = size;
    q->NextChar = buffer;
    q->LastChar = buffer;
    q->InQueue = 0;
}

static void
CloseQueue(CirQueue *q)
{
    q->Start = NULL;
    q->End = NULL;
    q->NextChar = NULL;
    q->LastChar = NULL;
    q->Size = 0;
}

static unsigned int
AddtoQueue(CirQueue *q, unsigned char *buffer, unsigned int size)
{
    unsigned int i;

    for (i = 0; FreeSpaceinQueue(q) != 0 && i < size; i++)
        AddBytetoQueue(q, *buffer++);
    return i;
}

static unsigned int
RemovefromQueue(CirQueue *q, unsigned char *buffer, unsigned int size)
{
    unsigned int i;

    /* Divergence from 5.6: test the bound before taking a byte.  The binary
       takes one first and compares size >= i, so with more queued than asked
       for it writes one byte past the buffer and drops the next. */
    for (i = 0; i < size && GetBytetoQueue(q, buffer) == 0; i++)
        buffer++;
    return i;
}

static unsigned int
FreeSpaceinQueue(CirQueue *q)
{
    return q->Size - q->InQueue;
}

static unsigned int
UsedSpaceinQueue(CirQueue *q)
{
    return q->InQueue;
}

static unsigned int
GetQueueSize(CirQueue *q)
{
    return q->Size;
}

/* Returns 1 when the queue is full. */
static int
AddBytetoQueue(CirQueue *q, unsigned char c)
{
    if (q->NextChar == q->LastChar && q->InQueue != 0)
        return 1;
    *q->NextChar++ = c;
    q->InQueue++;
    if (q->NextChar >= q->End)
        q->NextChar = q->Start;
    return 0;
}

/* Returns 2 when the queue is empty. */
static int
GetBytetoQueue(CirQueue *q, unsigned char *c)
{
    if (q->NextChar == q->LastChar && q->InQueue == 0)
        return 2;
    *c = *q->LastChar++;
    q->InQueue--;
    if (q->LastChar >= q->End)
        q->LastChar = q->Start;
    return 0;
}
