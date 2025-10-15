/*
 * DECchip21140NetworkDriver.h
 * Main driver class for DECchip 21140 Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@class DECchip21140NetworkDriverKernelServerInstance;

/* Chip types */
typedef enum {
    CHIP_TYPE_21140 = 0,
    CHIP_TYPE_21142,
    CHIP_TYPE_21143,
    CHIP_TYPE_UNKNOWN
} DECchip21140Type;

@interface DECchip21140NetworkDriver : IOEthernetDriver
{
    @public
    IOPCIDeviceDescription *_deviceDescription;
    DECchip21140NetworkDriverKernelServerInstance *_kernelServerInstance;

    /* Hardware state */
    unsigned char _stationAddress[6];
    void *_memBase;
    unsigned int _ioBase;
    unsigned int _irqLevel;
    BOOL _isInitialized;
    BOOL _isEnabled;

    /* Chip identification */
    DECchip21140Type _chipType;
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
- (DECchip21140Type)identifyChip;
- (const char *)chipName;

/* Server instance */
- (DECchip21140NetworkDriverKernelServerInstance *)kernelServerInstance;

@end
