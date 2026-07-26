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
 * ISASerialPortInternal.h - state and entry points shared between the
 * driver's four translation units.
 *
 * All per-port state lives in one Port struct, embedded in the
 * ISASerialPort object as its first instance variable and pointed at by
 * its second.  The driver exports exactly eleven functions from
 * __TEXT,__text; every one of them reaches state through a Port * or a
 * Queue * and never through the object, which is what lets them live in
 * plain C translation units.  Nothing in this header may depend on the
 * @interface.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_ISASERIALPORTINTERNAL_H_
#define _BSD_DEV_I386_ISASERIALPORTINTERNAL_H_

#import <objc/objc.h>
#import <driverkit/return.h>
#import <kern/thread_call.h>

// UART Register Offsets
#define UART_RBR        0   // Receive Buffer Register (read)
#define UART_THR        0   // Transmit Holding Register (write)
#define UART_DLL        0   // Divisor Latch Low (DLAB=1)
#define UART_DLM        1   // Divisor Latch High (DLAB=1)
#define UART_IER        1   // Interrupt Enable Register (DLAB=0)
#define UART_IIR        2   // Interrupt Identification Register (read)
#define UART_FCR        2   // FIFO Control Register (write)
#define UART_LCR        3   // Line Control Register
#define UART_MCR        4   // Modem Control Register
#define UART_LSR        5   // Line Status Register
#define UART_MSR        6   // Modem Status Register
#define UART_SCR        7   // Scratch Register

// Line Control Register bits
#define LCR_DLAB        0x80    // Divisor Latch Access Bit

// FIFO Control Register bits
#define FCR_FIFO_ENABLE 0x01
#define FCR_RCVR_RESET  0x02
#define FCR_XMIT_RESET  0x04
#define FCR_TRIGGER_1   0x00
#define FCR_TRIGGER_4   0x40
#define FCR_TRIGGER_8   0x80
#define FCR_TRIGGER_14  0xC0

// UART Chip Types
#define CHIP_UNKNOWN    0
#define CHIP_8250       1
#define CHIP_16450      2
#define CHIP_16550      3
#define CHIP_UNKNOWN_FIFO 4
#define CHIP_16550A     5
#define CHIP_16650      6
#define CHIP_16750      7
#define CHIP_16950      8

// Parity types
#define PARITY_NONE     1
#define PARITY_ODD      2
#define PARITY_EVEN     3
#define PARITY_MARK     4
#define PARITY_SPACE    5

// State bit flags
#define STATE_ACTIVE        0x40000000  // Port is active/open
#define STATE_TX_ENABLED    0x00800000  // Transmit enabled
#define STATE_RX_ENABLED    0x00080000  // Receive enabled

// DTR/RTS flow control bits
#define STATE_DTR           0x00000002  // DTR signal state
#define STATE_RTS           0x00000004  // RTS signal state
#define STATE_FLOW_MASK     0x00000006  // Flow control mask

// TX queue state levels (bits 24-27 in state)
#define TX_STATE_MASK       0x07800000
#define TX_STATE_EMPTY      0x06000000  // Queue empty
#define TX_STATE_BELOW_LOW  0x04000000  // Below low watermark
#define TX_STATE_BELOW_MED  0x02000000  // Below medium watermark
#define TX_STATE_BELOW_HIGH 0x00000000  // Below high watermark
#define TX_STATE_ABOVE_HIGH 0x01000000  // Above high watermark

// RX queue state levels (bits 16-19 in state)
#define RX_STATE_MASK       0x000F0000
#define RX_STATE_EMPTY      0x000C0000  // Queue empty
#define RX_STATE_BELOW_LOW  0x00040000  // Below low watermark
#define RX_STATE_ABOVE_HIGH 0x00020000  // Above high watermark (need flow control)
#define RX_STATE_CRITICAL   0x00030000  // Critical level (above capacity-3)

// Modem Control Register bits
#define MCR_DTR             0x01        // Data Terminal Ready
#define MCR_RTS             0x02        // Request To Send
#define MCR_OUT1            0x04        // Output 1
#define MCR_OUT2            0x08        // Output 2 (interrupt enable)
#define MCR_LOOP            0x10        // Loopback mode

// Event type markers
#define EVENT_OVERFLOW      0x6C        // Queue overflow event
#define EVENT_STATE_CHANGE  0x53        // State change event

// FlowControl bits
#define FLOW_DTR_ENABLED    0x02        // DTR flow control enabled
#define FLOW_RTS_ENABLED    0x04        // RTS flow control enabled
#define FLOW_HW_ENABLED     0x10        // Hardware flow control enabled

// Ring buffer size limits
#define MIN_RING_BUFFER_SIZE    0x12        // 18 cells minimum
#define MAX_RING_BUFFER_SIZE    0x40000     // 256K cells maximum

/*
 * One ring buffer, 56 bytes.  Size, Count, HighWater, LowWater, Enqueue and
 * Dequeue count 2-byte cells, not bytes: AllocSize is Size * 2 + 2 and End is
 * Base + Size * 2.  Enqueue and Dequeue are the next queue levels at which a
 * state change must be reported, not pointers.
 */
typedef struct {
    unsigned int    Size;           /*  0 */
    unsigned int    Count;          /*  4 */
    unsigned int    HighWater;      /*  8 */
    unsigned int    LowWater;       /* 12 */
    unsigned int    Enqueue;        /* 16 */
    unsigned int    Dequeue;        /* 20 */
    char           *Base;           /* 24 */
    char           *End;            /* 28 */
    char           *Input;          /* 32 */
    char           *Output;         /* 36 */
    unsigned int    OverRun;        /* 40 */
    unsigned int    DefaultSize;    /* 44 */
    unsigned int    AllocSize;      /* 48 */
    char           *AllocBase;      /* 52 */
} Queue;                            /* 56 */

/*
 * Everything the driver knows about one port, 304 bytes.  State is a single
 * 32-bit word and FlowControl likewise; Self points back at the owning
 * Objective-C object, which is how a C translation unit reaches the object
 * when it genuinely must.
 */
typedef struct {
    id              Self;               /*   0 */
    unsigned int    Instance;           /*   4 */
    char           *PortName;           /*   8 */
    unsigned int    State;              /*  12 */
    unsigned int    WatchStateMask;     /*  16 */
    struct { unsigned int locked; } WatchLock;   /* 20 */
    Queue           RX;                 /*  24 */
    Queue           TX;                 /*  80 */
    unsigned int    Base;               /* 136 */
    unsigned int    IRQ;                /* 140 */
    unsigned int    Type;               /* 144 */
    unsigned int    CharLength;         /* 148 - half-bit units, 16 == 8 data bits */
    unsigned int    StopBits;           /* 152 - half-bit units, 2 == 1 stop bit */
    unsigned int    TX_Parity;          /* 156 */
    unsigned int    RX_Parity;          /* 160 */
    unsigned int    BreakLength;        /* 164 */
    unsigned int    BaudRate;           /* 168 - half-bits/s, 19200 == 9600 bps */
    unsigned short  DLRimage;           /* 172 */
    unsigned char   LCRimage;           /* 174 */
    unsigned char   FCRimage;           /* 175 */
    unsigned char   IERmask;            /* 176 */
    unsigned char   RBRmask;            /* 177 */
    unsigned int    MasterClock;        /* 180 */
    signed char     MinLatency;         /* 184 */
    signed char     WaitingForTXIdle;   /* 185 */
    signed char     JustDoneInterrupt;  /* 186 */
    signed char     PCMCIA;             /* 187 */
    signed char     PCMCIA_yanked;      /* 188 */
    unsigned char   XONchar;            /* 189 */
    unsigned char   XOFFchar;           /* 190 */
    unsigned int    SWspecial[8];       /* 192 - 256-bit character bitmap */
    unsigned int    FlowControl;        /* 224 */
    int             RXOstate;           /* 228 */
    void           *FrameTOEntry;       /* 232 */
    void           *DataLatTOEntry;     /* 236 */
    void           *DelayTOEntry;       /* 240 */
    void           *HeartBeatTOEntry;   /* 244 */
    tvalspec_t      FrameInterval;      /* 248 */
    tvalspec_t      DataLatInterval;    /* 256 */
    tvalspec_t      CharLatInterval;    /* 264 */
    tvalspec_t      HeartBeatInterval;  /* 272 */
    struct {
        unsigned int    ints;           /* 280 */
        unsigned int    txInts;         /* 284 */
        unsigned int    rxInts;         /* 288 */
        unsigned int    mdmInts;        /* 292 */
        unsigned int    txChars;        /* 296 */
        unsigned int    rxChars;        /* 300 */
    } Stats;
} Port;                                 /* 304 */

/* ISASerialPortChip.c */
extern int identifyChip(Port *port);
extern void initChip(Port *port);
extern void programChip(Port *port);

/* ISASerialPortQueue.c */
extern IOReturn TX_enqueueEvent(Port *port, unsigned char event,
                                unsigned int data, BOOL sleep);
extern IOReturn RX_dequeueEvent(Port *port, unsigned char *eventType,
                                unsigned int *eventData, BOOL sleep);
extern IOReturn RX_dequeueData(Port *port, unsigned char *byteOut, BOOL sleep);
extern unsigned int validateRingBufferSize(unsigned int requestedSize, Queue *q);
extern void freeRingBuffer(Queue *q);
extern int allocateRingBuffer(Queue *q);

/* ISASerialPortFlow.c */
extern unsigned int flowMachine(Port *port);
extern IOReturn watchState(Port *port, unsigned int *state, unsigned int mask);

#endif /* _BSD_DEV_I386_ISASERIALPORTINTERNAL_H_ */
