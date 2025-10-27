/* GNicEnet.m - PowerPC GNic Ethernet Driver */

#define MACH_USER_API	1

#import <driverkit/generalFuncs.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/ppc/PCI.h>
#import <driverkit/ppc/IOPCIDeviceDescription.h>
#import <driverkit/ppc/IOPCIDirectDevice.h>

#import "GNicEnet.h"

#import <kernserv/kern_server_types.h>
#import <kernserv/clock_timer.h>
#import <kernserv/prototypes.h>

// GNic register offsets (format: (size << 16) | offset)
// TODO: Define actual register offsets for GNic hardware
#define kGNicRegExample		0x40000		// Example register

//
// Utility functions for GNic register access
// The offset_and_size parameter encodes both the register offset (lower 16 bits)
// and the access size (upper 16 bits: 1=byte, 2=word, 4=dword)
//

static inline void enforceInOrderExecutionIO(void)
{
    __asm__ __volatile__ ("eieio" : : : "memory");
}

unsigned int _ReadGNicRegister(int base, unsigned int offset_and_size)
{
    unsigned int size = offset_and_size >> 16;
    unsigned int value;
    unsigned short temp16;
    unsigned char byte_lo, byte_hi;

    if (size == 2) {
        // 16-bit word access with byte swap
        temp16 = *(volatile unsigned short *)(base + (offset_and_size & 0xFFFE));
        byte_hi = (unsigned char)temp16;
        byte_lo = (unsigned char)(temp16 >> 8);
        value = (unsigned int)((byte_hi << 8) | byte_lo);
    }
    else if (size < 3) {
        if (size == 1) {
            // Byte access - no swapping needed
            return (unsigned int)*(volatile unsigned char *)(base + (offset_and_size & 0xFFFF));
        }
        value = 0;
    }
    else if (size == 4) {
        // 32-bit dword access with byte swap
        value = *(volatile unsigned int *)(base + (offset_and_size & 0xFFFC));
        return (value << 0x18) | ((value >> 8 & 0xFF) << 0x10) |
               ((value >> 0x10 & 0xFF) << 8) | (value >> 0x18);
    }
    else {
        value = 0;
    }

    return value;
}

void _WriteGNicRegister(int base, unsigned int offset_and_size, unsigned int value)
{
    unsigned int size = offset_and_size >> 16;
    unsigned char byte_lo;

    if (size == 2) {
        // 16-bit word access with byte swap
        byte_lo = (unsigned char)(value >> 8);
        *(volatile unsigned short *)(base + (offset_and_size & 0xFFFE)) =
            (unsigned short)(((unsigned char)value << 8) | byte_lo);
    }
    else if (size < 3) {
        if (size == 1) {
            // Byte access - no swapping needed
            *(volatile unsigned char *)(base + (offset_and_size & 0xFFFF)) = (unsigned char)value;
        }
    }
    else if (size == 4) {
        // 32-bit dword access with byte swap
        *(volatile unsigned int *)(base + (offset_and_size & 0xFFFC)) =
            (value << 0x18) | ((value >> 8 & 0xFF) << 0x10) |
            ((value >> 0x10 & 0xFF) << 8) | (value >> 0x18);
    }

    // Ensure writes complete in order (PowerPC eieio instruction)
    enforceInOrderExecutionIO();
}

@implementation GNicEnet

//
// Class method to probe for the device
// This is the entry point called by the system to detect the device
//
+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    GNicEnet *instance;

    // Allocate an instance and try to initialize it
    instance = [[self alloc] initFromDeviceDescription:devDesc];

    // Return success if initialization succeeded
    return (instance != nil);
}

//
// Initialize from device description
//
- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    int memoryRanges;
    BOOL result;
    struct ifnet *ifp;
    enet_addr_t macAddress;

    // Call superclass initialization
    if ([super initFromDeviceDescription:devDesc] == nil) {
        IOLog("Ethernet(GNic): [super initFromDeviceDescription] failed\n");
        return nil;
    }

    // Check that device has at least 2 memory ranges
    memoryRanges = [devDesc numMemoryRanges];
    if (memoryRanges < 2) {
        IOLog("Ethernet(GNic): Incorrect deviceDescription - 1\n\r");
        return nil;
    }

    // Configure PCI device
    // Enable bus mastering and memory access (offset 4, value 0x16)
    [devDesc configWriteLong:4 value:0x16];

    // Set cache line size and latency (offset 0xc, value 0x10208)
    [devDesc configWriteLong:0xc value:0x10208];

    // Map memory range 1 to memBase
    [self mapMemoryRange:1 to:&memBase findSpace:YES cache:IO_CacheOff];

    // Initialize configuration values
    initValue3 = 6;
    initValue1 = 0x14;
    initValue2 = 0xff;

    // Reset chip (disable)
    result = [self resetAndEnable:NO];
    if (!result) {
        [self free];
        return nil;
    }

    // Get MAC address from hardware
    [self _getStationAddress:&myAddress];

    // Allocate DMA memory
    result = [self _allocateMemory];
    if (!result) {
        [self free];
        return nil;
    }

    // Enable chip
    result = [self resetAndEnable:YES];
    if (!result) {
        [self free];
        return nil;
    }

    // Initialize mode flags
    promiscuousMode = NO;
    multicastEnabled = NO;

    // Copy MAC address for network attachment
    macAddress.ea_byte[0] = myAddress.ea_byte[0];
    macAddress.ea_byte[1] = myAddress.ea_byte[1];
    macAddress.ea_byte[2] = myAddress.ea_byte[2];
    macAddress.ea_byte[3] = myAddress.ea_byte[3];
    macAddress.ea_byte[4] = myAddress.ea_byte[4];
    macAddress.ea_byte[5] = myAddress.ea_byte[5];

    // Attach to network with our MAC address
    network = [super attachToNetworkWithAddress:&macAddress];

    // Configure network interface flags
    ifp = [network getIONetworkIfnet];
    ifp->if_flags |= 0x20;  // Set flag (likely IFF_SIMPLEX or similar)

    return self;
}

//
// Free resources
//
- free
{
    unsigned int i;

    // Clear any pending timeout
    [self clearTimeout];

    // Reset the chip hardware
    [self _resetChip];

    // Free the network object if allocated
    if (network != nil) {
        [network free];
    }

    // Free all RX netbufs
    for (i = 0; i < txDMACommandsSize; i++) {
        if (rxNetbufs[i] != NULL) {
            nb_free(rxNetbufs[i]);
        }
    }

    // Free all TX netbufs
    for (i = 0; i < rxDMACommandsSize; i++) {
        if (txNetbufs[i] != NULL) {
            nb_free(txNetbufs[i]);
        }
    }

    // Call superclass free
    return [super free];
}

//
// Reset and enable the adapter
//
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL result;

    // Mark driver as not ready during reset
    ready = NO;

    // Clear any pending timeouts
    [self clearTimeout];

    // Disable all interrupts
    [self disableAllInterrupts];

    // Reset the chip hardware
    [self _resetChip];

    // If disabling, just set running state and return
    if (!enable) {
        [self setRunning:enable];
        return YES;
    }

    // Enable path: initialize rings and chip
    result = [self _initRxRing];
    if (!result) {
        return NO;
    }

    result = [self _initTxRing];
    if (!result) {
        return NO;
    }

    result = [self _initChip];
    if (!result) {
        [self setRunning:NO];
        return NO;
    }

    // Enable interrupts
    [self enableAllInterrupts];
    [self _enableAdapterInterrupts];

    // Start the chip
    [self _startChip];

    // Set timeout for 300ms
    [self setRelativeTimeout:300];

    // Mark driver as ready
    ready = YES;

    // Send dummy packet to prime the hardware
    [self _sendDummyPacket];

    // Set running state
    [self setRunning:enable];

    return YES;
}

//
// Timeout occurred
//
- (void)timeoutOccurred
{
    unsigned int regValue;
    int watchdogCount;

    // Only process timeout if driver is running
    if (![self isRunning]) {
        return;
    }

    // Lock debugger access
    [self reserveDebuggerLock];

    // Monitor link status changes
    [self _monitorLinkStatus];

    // Read RX status register and check if bit 1 is clear
    regValue = _ReadGNicRegister((int)memBase, 0x20026);
    if ((regValue & 1) == 0) {
        // RX appears stuck, log and try to recover
        IOLog("Ethernet(GNic): Checking for timeout - RxHead = %d RxTail = %d\n\r",
              rxHead, rxTail);
        [self _receiveInterruptOccurred];
    }

    // Check if TX ring is empty or if we've had TX activity
    if ((txHead == txTail) || (pad_5c0 != 0)) {
        // TX ring empty or activity detected - clear watchdog counters
        pad_5c0 = 0;
        pad_5c4 = 0;
    } else {
        // TX ring not empty and no activity - increment watchdog
        watchdogCount = pad_5c4;
        pad_5c4 = watchdogCount + 1;

        if (watchdogCount != 0) {
            // Watchdog expired - try to recover
            [self _transmitInterruptOccurred];
            [self _restartTransmitter];
        }
    }

    // Set next timeout for 300ms
    [self setRelativeTimeout:300];

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Interrupt occurred
//
- (void)interruptOccurred
{
    unsigned int intStatus;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Process all pending interrupts
    do {
        // Read interrupt status register
        intStatus = _ReadGNicRegister((int)memBase, 0x40084);

        // Check for transmit completion (bits 0x700)
        if ((intStatus & 0x700) != 0) {
            // Increment TX interrupt counter
            pad_5c0++;

            // Process transmit completions
            [self _transmitInterruptOccurred];

            // Service any pending transmits
            [self serviceTransmitQueue];
        }

        // Check for receive completion (bits 0x7)
        if ((intStatus & 7) != 0) {
            // Process received packets
            [self _receiveInterruptOccurred];
        }

        // Loop while any interrupt bits are set
    } while (intStatus != 0);

    // Re-enable interrupts
    [self enableAllInterrupts];

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Get power management state
//
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
    // Power management not supported
    return 0xfffffd39;  // IO_R_UNSUPPORTED
}

//
// Set power management state
//
- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    // Power management not supported
    return 0xfffffd39;  // IO_R_UNSUPPORTED
}

//
// Get power state
//
- (IOReturn)getPowerState:(PMPowerState *)state
{
    // Power state not supported
    return 0xfffffd39;  // IO_R_UNSUPPORTED
}

//
// Set power state
//
- (IOReturn)setPowerState:(PMPowerState)state
{
    // Check if entering sleep state (state 3)
    if (state == 3) {
        // Mark driver as not ready
        ready = NO;

        // Reset the chip
        [self _resetChip];

        return IO_R_SUCCESS;
    }

    // Other power states not supported
    return 0xfffffd39;  // IO_R_UNSUPPORTED
}

//
// Add multicast address
//
- (void)addMulticastAddress:(enet_addr_t *)address
{
    // Lock debugger access
    [self reserveDebuggerLock];

    // Add address to hardware multicast table
    [self _addMulticastAddress:address];

    // Enable multicast mode
    [self enableMulticastMode];

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Remove multicast address
//
- (void)removeMulticastAddress:(enet_addr_t *)address
{
    // Lock debugger access
    [self reserveDebuggerLock];

    // Remove address from hardware multicast table
    [self _removeMulticastAddress:address];

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Enable promiscuous mode
//
- (BOOL)enablePromiscuousMode
{
    unsigned short regValue;

    // Set promiscuous mode flag
    promiscuousMode = YES;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Read current control register value
    regValue = _ReadGNicRegister((int)memBase, 0x200d0);

    // Set bits 0x24 to enable promiscuous mode
    _WriteGNicRegister((int)memBase, 0x200d0, regValue | 0x24);

    // Unlock debugger access
    [self releaseDebuggerLock];

    return YES;
}

//
// Disable promiscuous mode
//
- (void)disablePromiscuousMode
{
    unsigned int regValue;

    // Clear promiscuous mode flag
    promiscuousMode = NO;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Read current control register value
    regValue = _ReadGNicRegister((int)memBase, 0x200d0);

    // Clear bits 0x24 to disable promiscuous mode (AND with 0xffdb)
    _WriteGNicRegister((int)memBase, 0x200d0, regValue & 0xffdb);

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Enable multicast mode
//
- (BOOL)enableMulticastMode
{
    unsigned short regValue;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Set multicast enabled flag
    multicastEnabled = YES;

    // Read current control register value
    regValue = _ReadGNicRegister((int)memBase, 0x200d0);

    // Set bit 2 to enable multicast mode
    _WriteGNicRegister((int)memBase, 0x200d0, regValue | 2);

    // Unlock debugger access
    [self releaseDebuggerLock];

    return YES;
}

//
// Disable multicast mode
//
- (void)disableMulticastMode
{
    unsigned int regValue;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Clear multicast enabled flag
    multicastEnabled = NO;

    // Read current control register value
    regValue = _ReadGNicRegister((int)memBase, 0x200d0);

    // Clear bit 2 to disable multicast mode (AND with 0xfffd)
    _WriteGNicRegister((int)memBase, 0x200d0, regValue & 0xfffd);

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Transmit packet
//
- (void)transmit:(netbuf_t)pkt
{
    unsigned int queueCount;
    unsigned int maxCount;
    unsigned int nextTail;

    // Lock debugger access
    [self reserveDebuggerLock];

    // Check for NULL packet
    if (pkt == NULL) {
        IOLog("EtherNet(GNic): transmit received NULL netbuf\n");
        [self releaseDebuggerLock];
        return;
    }

    // Check if driver is running
    if (![self isRunning]) {
        // Not running - just free the packet
        nb_free(pkt);
        [self releaseDebuggerLock];
        return;
    }

    // Service any pending packets in queue
    [self serviceTransmitQueue];

    // Check transmit queue status
    queueCount = [transmitQueue count];

    if (queueCount == 0) {
        // Queue is empty - try direct transmit if ring has space
        nextTail = txTail + 1;
        if (nextTail >= rxDMACommandsSize) {
            nextTail = 0;
        }

        // If ring not full, transmit directly
        if (nextTail != txHead) {
            [self _transmitPacket:pkt];
            [self releaseDebuggerLock];
            return;
        }
    } else {
        // Queue has packets - check if at max capacity
        maxCount = [transmitQueue maxCount];
        if (maxCount <= queueCount) {
            IOLog("Ethernet(GNic): Transmit queue overflow\n");
        }
    }

    // Enqueue packet (either queue not empty or ring full)
    [transmitQueue enqueue:pkt];

    // Unlock debugger access
    [self releaseDebuggerLock];
}

//
// Send packet
//
- (void)sendPacket:(void *)pkt length:(unsigned int)len
{
    // Delegate to private implementation
    [self _sendPacket:pkt length:len];
}

//
// Receive packet
//
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout
{
    // Delegate to private implementation
    [self _receivePacket:pkt length:len timeout:timeout];
}

//
// Service transmit queue
//
- (void)serviceTransmitQueue
{
    int queueCount;
    unsigned int nextTail;
    netbuf_t packet;

    // Loop while there are packets in the transmit queue
    while (YES) {
        // Check if queue has any packets
        queueCount = [transmitQueue count];
        if (queueCount == 0) {
            return;
        }

        // Calculate next tail position
        nextTail = txTail + 1;
        if (nextTail >= rxDMACommandsSize) {
            nextTail = 0;
        }

        // Check if ring is full (nextTail == txHead)
        if (nextTail == txHead) {
            // Ring is full, can't transmit more
            return;
        }

        // Dequeue packet from transmit queue
        packet = [transmitQueue dequeue];

        // Transmit the packet
        [self _transmitPacket:packet];
    }
}

//
// Get transmit queue count
//
- (unsigned int)transmitQueueCount
{
    // Return number of packets in transmit queue
    return [transmitQueue count];
}

//
// Get transmit queue size
//
- (unsigned int)transmitQueueSize
{
    // Return maximum size of transmit queue (256 entries)
    return 0x100;
}

@end
