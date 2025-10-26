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
 * PPCSerialPort.h - Interface for PowerPC Serial Port driver.
 *
 * This driver supports the Zilog 85C30 SCC (Serial Communications Controller)
 * commonly found in PowerPC-based Macintosh systems.
 */

#ifndef _BSD_DEV_PPC_PPCSERIALPORT_H_
#define _BSD_DEV_PPC_PPCSERIALPORT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <sys/types.h>

// SCC Register addresses (write register select)
#define SCC_WR0         0   // Transmit/Receive buffer and External status
#define SCC_WR1         1   // Transmit/Receive interrupt and data transfer mode
#define SCC_WR2         2   // Interrupt vector
#define SCC_WR3         3   // Receive parameters and control
#define SCC_WR4         4   // Transmit/Receive miscellaneous parameters
#define SCC_WR5         5   // Transmit parameters and controls
#define SCC_WR6         6   // Sync characters or SDLC address field
#define SCC_WR7         7   // Sync character or SDLC flag
#define SCC_WR8         8   // Transmit buffer
#define SCC_WR9         9   // Master interrupt control and reset
#define SCC_WR10        10  // Miscellaneous transmit/receive control bits
#define SCC_WR11        11  // Clock mode control
#define SCC_WR12        12  // Lower byte of baud rate generator time constant
#define SCC_WR13        13  // Upper byte of baud rate generator time constant
#define SCC_WR14        14  // Miscellaneous control bits
#define SCC_WR15        15  // External/Status interrupt control

// SCC Read register addresses
#define SCC_RR0         0   // Transmit/Receive buffer status and External status
#define SCC_RR1         1   // Special Receive Condition status
#define SCC_RR2         2   // Modified interrupt vector (channel B only)
#define SCC_RR3         3   // Interrupt pending bits (channel A only)
#define SCC_RR8         8   // Receive buffer
#define SCC_RR10        10  // Miscellaneous status
#define SCC_RR12        12  // Lower byte of baud rate generator time constant
#define SCC_RR13        13  // Upper byte of baud rate generator time constant
#define SCC_RR15        15  // External/Status interrupt information

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
#define STATE_CTS           0x00000010  // CTS signal state
#define STATE_DCD           0x00000020  // DCD signal state
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
#define RX_STATE_ABOVE_HIGH 0x00020000  // Above high watermark
#define RX_STATE_CRITICAL   0x00030000  // Critical level

// Event type markers
#define EVENT_OVERFLOW      0x6C        // Queue overflow event
#define EVENT_STATE_CHANGE  0x53        // State change event

// Ring buffer size limits
#define MIN_RING_BUFFER_SIZE    0x12        // 18 bytes minimum
#define MAX_RING_BUFFER_SIZE    0x40000     // 256KB maximum

// DMA buffer sizes
#define DMA_RX_BUFFER_SIZE      0x1000      // 4KB RX DMA buffer
#define DMA_TX_BUFFER_SIZE      0x1000      // 4KB TX DMA buffer

@interface PPCSerialPort : IODevice
{
    IOPPCDeviceDescription *deviceDescription;
    void *sccBaseAddress;           // SCC base address (memory-mapped)
    void *sccControlReg;            // SCC control register address
    void *sccDataReg;               // SCC data register address
    unsigned int sccChannel;        // SCC channel (A or B)
    unsigned int dataBits;          // Data bits: 5/6/7/8 bits
    unsigned int stopBits;          // Stop bits: 1 or 2
    unsigned int parity;            // Parity type
    unsigned int flowControl;       // Flow control setting
    unsigned int baudRate;          // Baud rate in bps
    unsigned int clockRate;         // SCC clock rate
    unsigned int charTimeNS;        // Character time in nanoseconds
    unsigned int charTimeFracNS;    // Character time fractional ns
    unsigned char flags;            // Driver flags
    unsigned int currentState;      // Current port state
    unsigned char statusFlags;      // Status flags
    unsigned int watchStateMask;    // Watch state mask for waiting
    int watchStateLock;             // Lock for watch state operations

    // RX (Receive) Ring Buffer
    unsigned int rxQueueCapacity;   // RX queue capacity
    unsigned int rxQueueUsed;       // RX queue used count
    unsigned int rxQueueHighWater;  // RX queue high watermark
    unsigned int rxQueueLowWater;   // RX queue low watermark
    unsigned int rxQueueTarget;     // RX queue target level
    unsigned int rxQueueWatermark;  // RX queue current watermark
    void *rxQueueStart;             // RX queue start pointer
    void *rxQueueEnd;               // RX queue end pointer
    void *rxQueueWrite;             // RX queue write pointer
    void *rxQueueRead;              // RX queue read pointer
    unsigned int rxQueueOverflow;   // RX queue overflow flag

    // TX (Transmit) Ring Buffer
    unsigned int txQueueCapacity;   // TX queue capacity
    unsigned int txQueueUsed;       // TX queue used count
    unsigned int txQueueLowWater;   // TX queue low watermark
    unsigned int txQueueMedWater;   // TX queue medium watermark
    unsigned int txQueueHighWater;  // TX queue high watermark
    unsigned int txQueueTarget;     // TX queue target level
    void *txQueueStart;             // TX queue start pointer
    void *txQueueEnd;               // TX queue end pointer
    void *txQueueWrite;             // TX queue write pointer
    void *txQueueRead;              // TX queue read pointer

    unsigned int defaultRingBufferSize; // Default ring buffer size
    unsigned char xonChar;          // XON character for flow control
    unsigned char xoffChar;         // XOFF character for flow control
    unsigned int charFilterBitmap[8]; // Character filter bitmap 256 bits
    unsigned char flowControlMode;  // Flow control mode flags
    unsigned char controlFlags;     // Additional control flags
    unsigned short stateEventMask;  // State change event mask
    int flowControlState;           // Flow control state

    // DMA support
    BOOL useDMA;                    // Use DMA for transfers
    void *rxDMABuffer;              // RX DMA buffer
    void *txDMABuffer;              // TX DMA buffer
    unsigned int rxDMASize;         // RX DMA buffer size
    unsigned int txDMASize;         // TX DMA buffer size

    // Interrupt handling
    void *interruptPort;            // Interrupt port
    unsigned int interruptLevel;    // Interrupt level
    unsigned int interruptCount;    // Total interrupt count
    unsigned int rxInterruptCount;  // RX interrupt count
    unsigned int txInterruptCount;  // TX interrupt count
    unsigned int extInterruptCount; // External/Status interrupt count

    // SCC register cache values
    unsigned char ierValue;         // Interrupt Enable Register value (WR1)
    unsigned char txPendingFlag;    // TX transmission pending flag
    unsigned char reserved[2];      // Padding for alignment
}

/*
 * Probe for device presence.
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/*
 * Acquire the serial port.
 */
- (IOReturn)acquire:(void *)refCon;

/*
 * Release the serial port.
 */
- (IOReturn)release;

/*
 * Initialize from device description.
 */
- (id)initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/*
 * Free the instance.
 */
- (void)free;

/*
 * Dequeue data from the serial port.
 */
- (IOReturn)dequeueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
               minCount:(unsigned int)minCount;

/*
 * Dequeue an event from the serial port.
 */
- (IOReturn)dequeueEvent:(unsigned int *)event
                    data:(unsigned int *)data
                   sleep:(BOOL)sleep;

/*
 * Enqueue data to the serial port.
 */
- (IOReturn)enqueueData:(unsigned char *)buffer
             bufferSize:(unsigned int)size
          transferCount:(unsigned int *)count
                  sleep:(BOOL)sleep;

/*
 * Enqueue an event to the serial port.
 */
- (IOReturn)enqueueEvent:(unsigned int)event
                    data:(unsigned int)data
                   sleep:(BOOL)sleep;

/*
 * Execute an event.
 */
- (IOReturn)executeEvent:(unsigned int)event
                    data:(unsigned int)data;

/*
 * Request an event.
 */
- (IOReturn)requestEvent:(unsigned int)event
                    data:(unsigned int *)data;

/*
 * Get the next event.
 */
- (unsigned int)nextEvent;

/*
 * Get the current state.
 */
- (unsigned int)getState;

/*
 * Set the state with mask.
 */
- (IOReturn)setState:(unsigned int)state
                mask:(unsigned int)mask;

/*
 * Watch state with mask.
 */
- (IOReturn)watchState:(unsigned int *)state
                  mask:(unsigned int)mask;

/*
 * Get character values for a parameter.
 */
- (IOReturn)getCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameter
                    count:(unsigned int *)count;

/*
 * Get interrupt handler information.
 */
- (IOReturn)getHandler:(IOInterruptHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)argument
          forInterrupt:(unsigned int)interruptType;

@end

#endif /* _BSD_DEV_PPC_PPCSERIALPORT_H_ */
