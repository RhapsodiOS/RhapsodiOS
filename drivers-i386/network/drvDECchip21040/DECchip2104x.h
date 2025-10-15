/*
 * DECchip2104x.h
 * Base class for DECchip 21040/21041 Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@class DECchip2104xKernelServerInstance;

/* Chip types */
typedef enum {
    CHIP_TYPE_21040 = 0,
    CHIP_TYPE_21041,
    CHIP_TYPE_UNKNOWN
} DECchip2104xType;

@interface DECchip2104x : IOEthernetDriver
{
    @public
    IOPCIDeviceDescription *_deviceDescription;
    DECchip2104xKernelServerInstance *_kernelServerInstance;

    /* Hardware state */
    unsigned char _stationAddress[6];
    void *_memBase;
    unsigned int _ioBase;
    unsigned int _irqLevel;
    BOOL _isInitialized;
    BOOL _isEnabled;

    /* Chip identification */
    DECchip2104xType _chipType;
    unsigned int _pciDevice;
    unsigned int _pciVendor;
    unsigned int _pciRevision;

    /* Buffers and descriptors */
    void *_receiveBuffers;
    void *_transmitBuffers;
    void *_setupFrame;
    void *_rxDescriptors;
    void *_txDescriptors;
    unsigned int _rxHead;
    unsigned int _rxTail;
    unsigned int _txHead;
    unsigned int _txTail;
    unsigned int _rxRingSize;
    unsigned int _txRingSize;

    /* Network state */
    BOOL _linkUp;
    BOOL _fullDuplex;
    unsigned int _mediaType;

    /* Filtering */
    unsigned int _multicastCount;
    BOOL _promiscuousMode;

    /* Statistics */
    unsigned int _txPackets;
    unsigned int _rxPackets;
    unsigned int _txErrors;
    unsigned int _rxErrors;
    unsigned int _collisions;
    unsigned int _missedFrames;

    /* Private implementation */
    void *_private;
}

/* Initialization and probe */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* Hardware control */
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)enableAllInterrupts;
- (BOOL)disableAllInterrupts;

/* Network interface */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket;
- (unsigned int)transmitQueueSize;
- (unsigned int)receiveQueueSize;

/* Interrupt handling */
- (void)interruptOccurred;
- (void)timeoutOccurred;

/* Configuration */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr;
- (void)setStationAddress:(enet_addr_t *)addr;

/* Power management */
- (IOReturn)getPowerState;
- (IOReturn)setPowerState:(unsigned int)state;

/* Statistics */
- (void)resetStats;
- (void)updateStats;
- (void)getStatistics;

/* Internal methods */
- (BOOL)allocateMemory;
- (void)freeMemory;
- (BOOL)initChip;
- (void)resetChip;

/* Descriptor management */
- (BOOL)initDescriptors;
- (void)freeDescriptors;
- (void)setupRxDescriptor:(int)index;
- (void)setupTxDescriptor:(int)index;

/* DMA operations */
- (void)startTransmit;
- (void)stopTransmit;
- (void)startReceive;
- (void)stopReceive;

/* Setup frame */
- (void)loadSetupFilter;
- (void)sendSetupFrame;

/* Multicast */
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

/* Promiscuous mode */
- (void)setPromiscuousMode:(BOOL)enable;

/* CSR access */
- (unsigned int)readCSR:(int)csr;
- (void)writeCSR:(int)csr value:(unsigned int)value;

/* Chip identification */
- (DECchip2104xType)identifyChip;
- (const char *)chipName;

/* Server instance */
- (DECchip2104xKernelServerInstance *)kernelServerInstance;

@end

/* Private category - internal implementation */
@interface DECchip2104x(Private)

/* Private initialization */
- (BOOL)_allocMemory;
- (void)_freeMemory;
- (BOOL)_initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Private chip operations */
- (void)_resetChip;
- (BOOL)_initChip;
- (void)_selectInterface:(int)interface;
- (void)_setInterface;

/* Private transmit/receive */
- (void)_startTransmit;
- (void)_startReceive;
- (void)_transmitInterruptOccurred;
- (void)_receiveInterruptOccurred;
- (void)_sendPacket_length:(void *)packet length:(unsigned int)len;
- (void)_receivePacket_length:(void *)packet;

/* Private descriptor operations */
- (BOOL)_initDescriptors;
- (void)_setupRxDescriptor:(int)index;
- (void)_setupTxDescriptor:(int)index;

/* Private setup frame */
- (void)_loadSetupFilter;
- (void)_updateDescriptorFromNetbuf:(void *)descriptor;
- (void)_allocateNetbuf;

/* Private statistics */
- (void)_getStatistics;
- (void)_resetStats;

/* Private power management */
- (IOReturn)_getPowerState;
- (IOReturn)_setPowerState:(unsigned int)state;
- (void)_setPowerManagement;

@end
