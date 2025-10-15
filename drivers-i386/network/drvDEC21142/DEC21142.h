/*
 * DEC21142.h
 * DEC Celebris On-Board 21142 LAN Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@class DEC21142KernelServerInstance;

@interface DEC21142 : IOEthernetDriver
{
    IOPCIDeviceDescription *_deviceDescription;
    DEC21142KernelServerInstance *_serverInstance;
    unsigned char _romAddress[6];
    void *_memBase;
    unsigned int _ioBase;
    unsigned int _irqLevel;
    BOOL _isInitialized;
    BOOL _isEnabled;
    BOOL _linkUp;
    unsigned int _transmitTimeout;
    void *_receiveBuffer;
    void *_transmitBuffer;
    unsigned int _rxIndex;
    unsigned int _txIndex;
    unsigned int _pciDevice;
    unsigned int _pciVendor;
    void *_setupFrame;
    void *_rxDescriptors;
    void *_txDescriptors;
    unsigned int _rxRingSize;
    unsigned int _txRingSize;
    unsigned int _multicastCount;
    BOOL _promiscuousMode;
    unsigned int _csrBusMode;
    unsigned int _csrTransmitPoll;
    unsigned int _csrReceivePoll;
    unsigned int _csrRxListBase;
    unsigned int _csrTxListBase;
    unsigned int _csrStatus;
    unsigned int _csrNetworkAccess;
    unsigned int _csrInterruptMask;
}

/* Initialization and probe methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/* Hardware control methods */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)clearTimeout;
- (BOOL)enableAllInterrupts;
- (BOOL)disableAllInterrupts;

/* Network interface methods */
- (void)transmitPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket;
- (unsigned int)transmitQueueSize;
- (unsigned int)receiveQueueSize;

/* Interrupt handling */
- (void)interruptOccurred;
- (void)timeoutOccurred;

/* Configuration methods */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr;
- (int)performCommand:(unsigned int)cmd;
- (void)sendSetupFrame;

/* Power management */
- (IOReturn)getPowerState;
- (IOReturn)setPowerState:(unsigned int)state;

/* Diagnostics and statistics */
- (void)resetStats;
- (void)updateStats;
- (void)getStatistics;
- (void)setupPhy;
- (void)checkLink;

/* Internal utility methods */
- (BOOL)allocateBuffers;
- (void)freeBuffers;
- (BOOL)initChip;
- (void)resetChip;

/* MII/PHY management */
- (int)miiRead:(int)phyAddr reg:(int)regAddr;
- (void)miiWrite:(int)phyAddr reg:(int)regAddr value:(int)value;

/* SROM/EEPROM access */
- (unsigned short)sromRead:(int)location;
- (void)sromWrite:(int)location value:(unsigned short)value;
- (void)loadSetupBuffer:(void *)buffer;

/* DMA operations */
- (BOOL)setupDMA;
- (void)startTransmit;
- (void)stopTransmit;
- (void)startReceive;
- (void)stopReceive;

/* Descriptor operations */
- (BOOL)initDescriptors;
- (void)freeDescriptors;
- (void)setupRxDescriptor:(int)index;
- (void)setupTxDescriptor:(int)index;

/* Multicast support */
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;
- (void)setMulticastMode:(BOOL)enable;
- (void)updateMulticastList;

/* Promiscuous mode */
- (void)setPromiscuousMode:(BOOL)enable;

/* PCI-specific methods */
- (BOOL)enableAdapterInterrupts;
- (BOOL)disableAdapterInterrupts;
- (void)acknowledgeInterrupts;

/* Queue management */
- (void)recycleNetbuf;
- (void)shrinkQueue;
- (void)setTransmitQueueSize:(unsigned int)size;
- (unsigned int)getTransmitQueueCount;

/* Model identification */
- (void)getModelId;
- (void)setModelId:(int)modelId;

/* CSR access */
- (unsigned int)readCSR:(int)csr;
- (void)writeCSR:(int)csr value:(unsigned int)value;

/* Server instance management */
- (DEC21142KernelServerInstance *)serverInstance;
- (void)setServerInstance:(DEC21142KernelServerInstance *)instance;

@end
