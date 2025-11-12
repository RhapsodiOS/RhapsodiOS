/*
 * DECchip2104x.m
 * Base class for DEC 21040/21041 Ethernet Controllers
 */

#import "DECchip2104x.h"
#import "DECchip2104xInline.h"
#import "DECchip2104xPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>

@implementation DECchip2104x

/*
 * Probe for supported devices
 */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned int vendorID, deviceID;

    if ([deviceDescription respondsToSelector:@selector(getPCIVendorID)] &&
        [deviceDescription respondsToSelector:@selector(getPCIDeviceID)]) {

        vendorID = [deviceDescription getPCIVendorID];
        deviceID = [deviceDescription getPCIDeviceID];

        /* DEC vendor ID is 0x1011 */
        if (vendorID == 0x1011) {
            /* Check for 21040 (0x0002) or 21041 (0x0014) */
            if (deviceID == 0x0002 || deviceID == 0x0014) {
                return YES;
            }
        }
    }

    return NO;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    [super initFromDeviceDescription:deviceDescription];

    _deviceDescription = deviceDescription;
    _isRunning = NO;
    _isFullDuplex = NO;

    /* Get I/O base address */
    if ([deviceDescription numMemoryRanges] > 0) {
        _ioRange = [deviceDescription memoryRangeList];
        _ioBase = (volatile void *)[_ioRange start];
    } else {
        IOLog("%s: No memory ranges available\n", [self name]);
        return nil;
    }

    return self;
}

/*
 * Free resources
 */
- free
{
    /* TODO: Free descriptor rings and buffers */
    return [super free];
}

/*
 * Reset and optionally enable the controller
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    unsigned int csr0;
    int timeout;

    /* Software reset */
    DECchip_WriteCSR(_ioBase, CSR0_BUS_MODE, CSR0_SWR);
    IODelay(100);

    /* Wait for reset to complete */
    timeout = 1000;
    while (timeout-- > 0) {
        csr0 = DECchip_ReadCSR(_ioBase, CSR0_BUS_MODE);
        if ((csr0 & CSR0_SWR) == 0) {
            break;
        }
        IODelay(10);
    }

    if (timeout <= 0) {
        IOLog("%s: Reset timeout\n", [self name]);
        return NO;
    }

    /* Configure bus mode */
    csr0 = (8 << 8);  /* PBL = 8 longwords */
    DECchip_WriteCSR(_ioBase, CSR0_BUS_MODE, csr0);

    if (enable) {
        /* TODO: Enable receive and transmit */
    }

    return YES;
}

/*
 * Interrupt handler
 */
- (void)interruptOccurred
{
    unsigned int status;

    /* Read and acknowledge interrupt status */
    status = DECchip_ReadCSR(_ioBase, CSR5_STATUS);
    DECchip_WriteCSR(_ioBase, CSR5_STATUS, status);

    /* Handle transmit completion */
    if (status & CSR5_TI) {
        _txInterrupts++;
        /* TODO: Process transmitted packets */
    }

    /* Handle receive completion */
    if (status & CSR5_RI) {
        _rxInterrupts++;
        [self receivePackets];
    }

    /* Handle errors */
    if (status & (CSR5_TPS | CSR5_TU | CSR5_UNF | CSR5_RPS | CSR5_RU | CSR5_FBE)) {
        _errorInterrupts++;
        /* TODO: Handle error conditions */
    }
}

/*
 * Transmit a packet
 */
- (int)transmit:(netbuf_t)pkt
{
    /* TODO: Implement packet transmission */
    return 0;
}

/*
 * Receive packets
 */
- (void)receivePackets
{
    /* TODO: Implement packet reception */
}

/*
 * Get Ethernet MAC address
 */
- (void)getEthernetAddress:(enet_addr_t *)addr
{
    /* TODO: Read MAC address from SROM */
    memset(addr, 0, sizeof(enet_addr_t));
}

/*
 * Set full duplex mode
 */
- (BOOL)setFullDuplex:(BOOL)fullDuplex
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);

    if (fullDuplex) {
        csr6 |= CSR6_FD;
    } else {
        csr6 &= ~CSR6_FD;
    }

    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
    _isFullDuplex = fullDuplex;

    return YES;
}

/*
 * Get station (MAC) address - base implementation
 */
- (void)getStationAddress:(enet_addr_t *)addr
{
    [self getEthernetAddress:addr];
}

/*
 * Select network interface
 */
- (IOReturn)selectInterface
{
    /* TODO: Implement interface selection */
    return IO_R_SUCCESS;
}

/*
 * Allocate a network buffer
 */
- (netbuf_t)allocateNetbuf
{
    /* TODO: Implement netbuf allocation */
    return NULL;
}

/*
 * Enable adapter interrupts
 */
- (void)enableAdapterInterrupts
{
    /* TODO: Enable interrupts in CSR7 */
}

/*
 * Disable adapter interrupts
 */
- (void)disableAdapterInterrupts
{
    /* TODO: Disable interrupts in CSR7 */
}

/*
 * Enable promiscuous mode
 */
- (void)enablePromiscuousMode
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 |= CSR6_PR;
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
}

/*
 * Disable promiscuous mode
 */
- (void)disablePromiscuousMode
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 &= ~CSR6_PR;
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
}

/*
 * Enable multicast mode
 */
- (void)enableMulticastMode
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 |= CSR6_PM;
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
}

/*
 * Disable multicast mode
 */
- (void)disableMulticastMode
{
    unsigned int csr6;

    csr6 = DECchip_ReadCSR(_ioBase, CSR6_COMMAND);
    csr6 &= ~CSR6_PM;
    DECchip_WriteCSR(_ioBase, CSR6_COMMAND, csr6);
}

/*
 * Add multicast address
 */
- (void)addMulticastAddress:(enet_addr_t *)addr
{
    /* TODO: Add address to multicast filter */
}

/*
 * Remove multicast address
 */
- (void)removeMulticastAddress:(enet_addr_t *)addr
{
    /* TODO: Remove address from multicast filter */
}

/*
 * Service transmit queue
 */
- (void)serviceTransmitQueue
{
    /* TODO: Process pending transmit packets */
}

/*
 * Get pending transmit count
 */
- (unsigned int)pendingTransmitCount
{
    /* TODO: Return number of pending transmit packets */
    return 0;
}

/*
 * Get transmit queue count
 */
- (unsigned int)transmitQueueCount
{
    /* TODO: Return current transmit queue depth */
    return 0;
}

/*
 * Get transmit queue size
 */
- (unsigned int)transmitQueueSize
{
    /* TODO: Return maximum transmit queue size */
    return 0;
}

/*
 * Timeout occurred
 */
- (void)timeoutOccurred
{
    /* TODO: Handle timeout condition */
}

/*
 * Get power management capabilities
 */
- (IOReturn)getPowerManagement:(IOPMPowerManagementState *)state
{
    /* TODO: Report power management capabilities */
    return IO_R_UNSUPPORTED;
}

/*
 * Set power management
 */
- (IOReturn)setPowerManagement:(IOPMPowerManagementState)state
{
    /* TODO: Set power management state */
    return IO_R_UNSUPPORTED;
}

/*
 * Get power state
 */
- (IOReturn)getPowerState:(IOPMPowerState *)state
{
    /* TODO: Return current power state */
    return IO_R_UNSUPPORTED;
}

/*
 * Set power state
 */
- (IOReturn)setPowerState:(IOPMPowerState)state
{
    /* TODO: Set power state */
    return IO_R_UNSUPPORTED;
}

@end
