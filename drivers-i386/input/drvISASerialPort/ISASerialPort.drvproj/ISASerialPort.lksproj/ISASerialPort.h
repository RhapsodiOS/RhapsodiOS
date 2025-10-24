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
 * ISASerialPort.h - Interface for ISA Serial Port driver.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_ISASERIALPORT_H_
#define _BSD_DEV_I386_ISASERIALPORT_H_

#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <sys/types.h>

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

// Flow control mode flags (offset 0xe0)
#define FLOW_DTR_ENABLED    0x02        // DTR flow control enabled
#define FLOW_RTS_ENABLED    0x04        // RTS flow control enabled
#define FLOW_HW_ENABLED     0x10        // Hardware flow control enabled

// Ring buffer size limits
#define MIN_RING_BUFFER_SIZE    0x12        // 18 bytes minimum
#define MAX_RING_BUFFER_SIZE    0x40000     // 256KB maximum

@interface ISASerialPort : IODevice
{
    IOEISADeviceDescription *deviceDescription;
    unsigned short basePort;        // Base I/O port address (offset 0x88)
    unsigned int chipType;          // Detected UART chip type (offset 0x90)
    unsigned int dataBits;          // Data bits: 10/12/14/16 (5/6/7/8 bits) (offset 0x94)
    unsigned int stopBits;          // Stop bits: 2 or 3+ (1 or 2 stop bits) (offset 0x98)
    unsigned int parity;            // Parity type (offset 0x9c)
    unsigned int flowControl;       // Flow control setting (offset 0xa0)
    unsigned int baudRate;          // Baud rate in bps (offset 0xa8)
    unsigned short divisor;         // Baud rate divisor (offset 0xac)
    unsigned char lcrValue;         // Line Control Register value (offset 0xae)
    unsigned char fcrValue;         // FIFO Control Register value (offset 0xaf)
    unsigned char ierValue;         // Interrupt Enable Register value (offset 0xb0)
    unsigned char rxFIFOMask;       // RX FIFO size mask (offset 0xb1)
    unsigned int clockRate;         // UART clock rate (offset 0xb4)
    unsigned char forceFIFODisable; // Force FIFO disable flag (offset 0xb8)
    unsigned int charTimeNS;        // Character time in nanoseconds (offset 0xf8)
    unsigned int charTimeFracNS;    // Character time fractional ns (offset 0xfc)
    unsigned char flags;            // Driver flags (offset 0xd)
    unsigned int currentState;      // Current port state (offset 0xc)
    unsigned char statusFlags;      // Status flags (offset 0xf)
    unsigned int watchStateMask;    // Watch state mask for waiting (offset 0x10)
    int watchStateLock;             // Lock for watch state operations (offset 0x14)

    // RX (Receive) Ring Buffer
    unsigned int rxQueueCapacity;   // RX queue capacity (offset 0x18)
    unsigned int rxQueueUsed;       // RX queue used count (offset 0x1c)
    unsigned int rxQueueHighWater;  // RX queue high watermark (offset 0x20)
    unsigned int rxQueueLowWater;   // RX queue low watermark (offset 0x24)
    unsigned int rxQueueTarget;     // RX queue target level (offset 0x28)
    unsigned int rxQueueWatermark;  // RX queue current watermark (offset 0x2c)
    void *rxQueueStart;             // RX queue start pointer (offset 0x30)
    void *rxQueueEnd;               // RX queue end pointer (offset 0x34)
    void *rxQueueWrite;             // RX queue write pointer (offset 0x38)
    void *rxQueueRead;              // RX queue read pointer (offset 0x3c)
    unsigned int rxQueueOverflow;   // RX queue overflow flag (offset 0x40)

    // TX (Transmit) Ring Buffer
    unsigned int txQueueCapacity;   // TX queue capacity (offset 0x50)
    unsigned int txQueueUsed;       // TX queue used count (offset 0x54)
    unsigned int txQueueLowWater;   // TX queue low watermark (offset 0x58)
    unsigned int txQueueMedWater;   // TX queue medium watermark (offset 0x5c)
    unsigned int txQueueHighWater;  // TX queue high watermark (offset 0x60)
    unsigned int txQueueTarget;     // TX queue target level (offset 0x64)
    void *txQueueStart;             // TX queue start pointer (offset 0x68)
    void *txQueueEnd;               // TX queue end pointer (offset 0x6c)
    void *txQueueWrite;             // TX queue write pointer (offset 0x70)
    void *txQueueRead;              // TX queue read pointer (offset 0x74)

    unsigned int defaultRingBufferSize; // Default ring buffer size (offset 0x2c)
    unsigned char timerPending;     // Timer pending flag (offset 0xb9)
    unsigned char heartBeatPending; // Heartbeat pending flag (offset 0xba)
    unsigned char pcmciaDetect;     // PCMCIA detection enabled (offset 0xbb)
    unsigned char pcmciaYanked;     // PCMCIA card removed flag (offset 0xbc)
    unsigned char xonChar;          // XON character for flow control (offset 0xbd)
    unsigned char xoffChar;         // XOFF character for flow control (offset 0xbe)
    unsigned int charFilterBitmap[8]; // Character filter bitmap 256 bits (offset 0xc0)
    unsigned char flowControlMode;  // Flow control mode flags (offset 0xe0)
    unsigned char controlFlags;     // Additional control flags (offset 0xe1)
    unsigned short stateEventMask;  // State change event mask (offset 0xe2)
    int flowControlState;           // Flow control state (offset 0xe4)
    void *timerCallout;             // Timer callout handle (offset 0xe8)
    void *delayTimeoutCallout;      // Delay timeout callout (offset 0xf0)
    void *heartBeatCallout;         // Heartbeat timer callout (offset 0xf4)
    unsigned int charTimeOverrideLow;  // Character time override low (offset 0x100)
    unsigned int charTimeOverrideHigh; // Character time override high (offset 0x104)
    unsigned long long heartBeatInterval; // Heartbeat interval in ns (offset 0x110)
    unsigned int interruptCount;    // Total interrupt count (offset 0x118)
    unsigned int thrEmptyIntCount;  // THR empty interrupt count (offset 0x11c)
    unsigned int dataReadyIntCount; // Data ready interrupt count (offset 0x120)
    unsigned int msrIntCount;       // MSR change interrupt count (offset 0x124)
    unsigned int bytesTransmitted;  // Bytes transmitted count (offset 0x128)
    unsigned int bytesReceived;     // Bytes received count (offset 0x12c)
    BOOL hasFIFO;                   // TRUE if UART has working FIFO
    // Additional instance variables will be added here
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

#endif /* _BSD_DEV_I386_ISASERIALPORT_H_ */
