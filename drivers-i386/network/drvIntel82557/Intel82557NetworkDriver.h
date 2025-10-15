/*
 * Intel82557NetworkDriver.h
 * Intel EtherExpress PRO/100B PCI Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@interface Intel82557NetworkDriver : IOEthernetDriver
{
    IOPCIDeviceDescription *_deviceDescription;
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
    void *_commandBlock;
    void *_rxRingBase;
    void *_txRingBase;
    unsigned int _rxRingSize;
    unsigned int _txRingSize;
    unsigned int _multicastCount;
    BOOL _promiscuousMode;
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
- (void)sendChannelAttention;

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

/* EEPROM access */
- (unsigned short)eepromRead:(int)location;
- (void)eepromWrite:(int)location value:(unsigned short)value;

/* DMA operations */
- (BOOL)setupDMA;
- (void)startTransmit;
- (void)stopTransmit;

/* Command block operations */
- (int)polledCommand:(void *)cmd;
- (BOOL)waitForCommand;

/* Multicast support */
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;
- (void)setMulticastMode:(BOOL)enable;

/* Promiscuous mode */
- (void)setPromiscuousMode:(BOOL)enable;

/* PCI-specific methods */
- (BOOL)enableAdapterInterrupts;
- (BOOL)disableAdapterInterrupts;
- (void)acknowledgeInterrupts;

/* Queue management */
- (void)recycleNetbuf;
- (void)shrinkQueue;
- (void)transmitQueueSize:(unsigned int)size;
- (void)transmitQueueCount;

/* Model identification */
- (void)getModelId;
- (void)setModelId:(int)modelId;

/* Counters */
- (void)getContents;

@end
