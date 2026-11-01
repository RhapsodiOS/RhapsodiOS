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
 * PPCSerialPort.h - Zilog 85C30 SCC serial port driver for PowerPC Macs.
 *
 * The Port structure and its member names are the ones the shipped 1.2v3
 * binary publishes in its ivar type encoding; the offsets in comments are
 * from the start of Port, which sits at object offset 296.
 */

#ifndef _BSD_DEV_PPC_PPCSERIALPORT_H_
#define _BSD_DEV_PPC_PPCSERIALPORT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <sys/types.h>
#import <mach/boolean.h>
#import <kern/thread_call.h>

/* PortDevice events (IOSerialInterface numbering). */
#define PD_E_ACTIVE                 5
#define PD_E_TXQ_SIZE               11
#define PD_E_RXQ_SIZE               15
#define PD_E_TXQ_LOW_WATER          19
#define PD_E_RXQ_LOW_WATER          23
#define PD_E_TXQ_HIGH_WATER         27
#define PD_E_RXQ_HIGH_WATER         31
#define PD_E_TXQ_AVAILABLE          35
#define PD_E_RXQ_AVAILABLE          39
#define PD_E_TXQ_FLUSH              40
#define PD_E_RXQ_FLUSH              47
#define PD_E_DATA_RATE              51
#define PD_E_RX_DATA_RATE           55
#define PD_E_DATA_SIZE              59
#define PD_E_RX_DATA_SIZE           63
#define PD_E_DATA_INTEGRITY         67
#define PD_E_RX_DATA_INTEGRITY      71
#define PD_E_DELAY                  75
#define PD_E_DATA_LATENCY           79
#define PD_E_FLOW_CONTROL           83
#define PD_E_VALID_DATA_BYTE        85
#define PD_E_SPECIAL_BYTE           89
#define PD_RS232_E_MIN_LATENCY      229
#define PD_RS232_E_XOFF_BYTE        233
#define PD_RS232_E_XON_BYTE         237
#define PD_RS232_E_STOP_BITS        243
#define PD_RS232_E_RX_STOP_BITS     247
#define PD_RS232_E_LINE_BREAK       249

/* PortDevice state bits. */
#define PD_S_ACQUIRED               0x80000000
#define PD_S_ACTIVE                 0x40000000
#define PD_S_TX_BUSY                0x10000000
#define PD_S_TXQ_EMPTY              0x04000000
#define PD_S_TXQ_LOW_WATER          0x02000000
#define PD_S_TXQ_HIGH_WATER         0x01000000
#define PD_S_TXQ_FULL               0x00800000
#define PD_S_RXQ_EMPTY              0x00080000
#define PD_S_RXQ_LOW_WATER          0x00040000
#define PD_S_RXQ_HIGH_WATER         0x00020000
#define PD_S_RXQ_FULL               0x00010000
#define PD_RS232_S_DELAY            0x00001000  /* private: a PD_E_DELAY is running */
#define PD_RS232_S_BRK              0x00000800
#define PD_RS232_S_DCD              0x00000040
#define PD_RS232_S_CTS              0x00000020
#define PD_RS232_A_RXO              0x00000010  /* FlowControl: software receive flow */

/* One ring buffer.  NextChar is where the next byte goes in, LastChar where
   the next byte comes out. */
typedef struct {
    char           *Start;          /*  0 */
    char           *End;            /*  4 */
    char           *NextChar;       /*  8 */
    char           *LastChar;       /* 12 */
    unsigned int    Size;           /* 16 */
    unsigned int    InQueue;        /* 20 */
} CirQueue;                         /* 24 */

typedef struct {
    unsigned long   BufferSize;
    unsigned long   HighWater;
    unsigned long   LowWater;
    char            OverRun;
} QueueStats;                       /* 16 */

typedef struct {
    id              Self;                       /*   0 */
    unsigned int    Instance;                   /*   4 */
    char           *PortName;                   /*   8 */
    unsigned long   State;                      /*  12 */
    unsigned long   WatchStateMask;             /*  16 */
    struct { unsigned int lock_data[4]; } WatchLock;  /* 20 */
    CirQueue        RX;                         /*  36 */
    CirQueue        TX;                         /*  60 */
    QueueStats      RXStats;                    /*  84 */
    QueueStats      TXStats;                    /* 100 */
    unsigned int    Base;                       /* 116 */
    unsigned int    CharLength;                 /* 120 */
    unsigned int    StopBits;                   /* 124 */
    unsigned int    TX_Parity;                  /* 128 */
    unsigned int    RX_Parity;                  /* 132 */
    unsigned int    BreakLength;                /* 136 */
    unsigned long   BaudRate;                   /* 140 */
    unsigned short  DLRimage;                   /* 144 */
    unsigned char   LCRimage;                   /* 146 */
    unsigned char   FCRimage;                   /* 147 */
    unsigned char   IERmask;                    /* 148 */
    unsigned char   RBRmask;                    /* 149 */
    unsigned long   MasterClock;                /* 152 */
    char            MinLatency;                 /* 156 */
    char            WaitingForTXIdle;           /* 157 */
    unsigned char   XONchar;                    /* 158 */
    unsigned char   XOFFchar;                   /* 159 */
    unsigned long   SWspecial[8];               /* 160: 256-bit character map */
    unsigned long   FlowControl;                /* 192 */
    int             RXOstate;                   /* 196 */
    int             TXOstate;                   /* 200 */
    unsigned char   xOffSent;                   /* 204 */
    unsigned int    GlobalRecvChars;            /* 208 */
    unsigned int    OverRunChars;               /* 212 */
    void           *FrameTOEntry;               /* 216 */
    void           *DataLatTOEntry;             /* 220 */
    void           *DelayTOEntry;               /* 224 */
    void           *HeartBeatTOEntry;           /* 228 */
    tvalspec_t      FrameInterval;              /* 232 */
    tvalspec_t      DataLatInterval;            /* 240 */
    tvalspec_t      CharLatInterval;            /* 248 */
    tvalspec_t      HeartBeatInterval;          /* 256 */
    struct {
        unsigned long   ints;
        unsigned long   txInts;
        unsigned long   rxInts;
        unsigned long   mdmInts;
        unsigned long   txChars;
        unsigned long   rxChars;
    } Stats;                                    /* 264 */
    unsigned char   AreTransmitting;            /* 288 */
    unsigned char   baudRateGeneratorEnable;    /* 289 */
    unsigned char   baudRateGeneratorLo;        /* 290 */
    unsigned char   baudRateGeneratorHi;        /* 291 */
    unsigned int    rtxcFrequency;              /* 292 */
    unsigned char   lastWR[15];                 /* 296: last value written to each WR */
    char           *ControlRegister;            /* 312 */
    char           *DataRegister;               /* 316 */
    unsigned int    ChipBaseAddress;            /* 320 */
    unsigned int    ConfigWriteRegister;        /* 324: channel B control, read for RR2 */
    unsigned char   whichPort;                  /* 328: 0 = ch-a, 1 = ch-b */
    char           *DMABuffer;                  /* 332 */
    char           *TxDMABase;                  /* 336 */
    unsigned int    TxDMALength;                /* 340 */
    char           *RxDMABase;                  /* 344 */
    unsigned int    RxDMALength;                /* 348 */
    unsigned char   InterruptNumbers[3];        /* 352 */
    unsigned char   ourReceiveBits;             /* 355 */
    unsigned char   ourTransmitBits;            /* 356 */
    unsigned char   ourClockSource;             /* 357 */
    unsigned char   haveQueuedRxSIH;            /* 358 */
    unsigned char   haveQueuedTxSIH;            /* 359 */
    unsigned short  ourMachineType;             /* 360 */
} Port;                                         /* 364 */

@protocol PortDevices

- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount;
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep;
- (IOReturn)dequeueEvent:(unsigned long *)event
                    data:(unsigned long *)data
                   sleep:(BOOL)sleep;
- (IOReturn)enqueueEvent:(unsigned long)event
                    data:(unsigned long)data
                   sleep:(BOOL)sleep;
- (IOReturn)requestEvent:(unsigned long)event
                    data:(unsigned long *)data;
- (IOReturn)executeEvent:(unsigned long)event
                    data:(unsigned long)data;
- (unsigned long)nextEvent;
- (IOReturn)watchState:(unsigned long *)state
                  mask:(unsigned long)mask;
- (unsigned long)getState;
- (IOReturn)setState:(unsigned long)state
                mask:(unsigned long)mask;
- (IOReturn)release;
- (IOReturn)acquire:(BOOL)sleep;

@end

@interface PPCSerialPort : IODirectDevice <PortDevices>
{
@public
    Port  Port;         /* all per-port state, at object offset 296 */
    Port *port;         /* &self->Port, at object offset 660 */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt;
- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count;

@end

#endif /* _BSD_DEV_PPC_PPCSERIALPORT_H_ */
