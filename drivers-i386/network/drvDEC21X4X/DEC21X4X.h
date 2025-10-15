/*
 * DEC21X4X.h
 * DEC Generic 21X4X Network Driver
 * Supports DEC 21040, 21041, 21140, 21142, 21143 Ethernet Controllers
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@class DEC21X4XKernelServerInstance;

/* Chip types */
typedef enum {
    CHIP_21040 = 0,
    CHIP_21041,
    CHIP_21140,
    CHIP_21142,
    CHIP_21143,
    CHIP_UNKNOWN
} DEC21X4XChipType;

/* Media types */
typedef enum {
    MEDIA_10BASE_T = 0,
    MEDIA_10BASE_2,
    MEDIA_10BASE_5,
    MEDIA_100BASE_TX,
    MEDIA_100BASE_T4,
    MEDIA_100BASE_FX,
    MEDIA_AUTO
} DEC21X4XMediaType;

@interface DEC21X4X : IOEthernetDriver
{
    IOPCIDeviceDescription *_deviceDescription;
    DEC21X4XKernelServerInstance *_serverInstance;

    /* Hardware state */
    unsigned char _romAddress[6];
    void *_memBase;
    unsigned int _ioBase;
    unsigned int _irqLevel;
    BOOL _isInitialized;
    BOOL _isEnabled;
    BOOL _linkUp;

    /* Chip identification */
    DEC21X4XChipType _chipType;
    unsigned int _pciDevice;
    unsigned int _pciVendor;
    unsigned int _pciRevision;

    /* Buffers and descriptors */
    void *_receiveBuffer;
    void *_transmitBuffer;
    void *_setupFrame;
    void *_rxDescriptors;
    void *_txDescriptors;
    unsigned int _rxIndex;
    unsigned int _txIndex;
    unsigned int _rxRingSize;
    unsigned int _txRingSize;

    /* Media and connection */
    DEC21X4XMediaType _mediaType;
    BOOL _fullDuplex;
    BOOL _autoNegotiate;
    unsigned int _linkSpeed;

    /* Filtering */
    unsigned int _multicastCount;
    BOOL _promiscuousMode;
    void *_multicastList;

    /* Statistics and timing */
    unsigned int _transmitTimeout;
    unsigned int _txPackets;
    unsigned int _rxPackets;
    unsigned int _txErrors;
    unsigned int _rxErrors;
    unsigned int _missedFrames;

    /* CSR shadow registers */
    unsigned int _csrBusMode;
    unsigned int _csrOpMode;
    unsigned int _csrInterruptMask;

    /* SROM data */
    unsigned char *_sromData;
    unsigned int _sromSize;
    BOOL _sromValid;

    /* PHY management */
    int _phyAddress;
    unsigned int _phyID;

    /* Reserved for future use */
    void *_reserved1;
    void *_reserved2;
    void *_reserved3;
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
- (BOOL)phyInit;
- (void)phyReset;
- (BOOL)phyAutoSense;
- (void)setPhyConnection:(int)connectionType;
- (int)getPhyControl;
- (void)setPhyControl:(int)control;

/* SROM/EEPROM access */
- (unsigned short)sromRead:(int)location;
- (void)sromWrite:(int)location value:(unsigned short)value;
- (BOOL)parseSROM;
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
- (void)allocateNetbuf;
- (void)enablePromiscuousMode;
- (void)disableMulticastMode;
- (unsigned int)pendingTransmitCount;
- (unsigned int)timeoutOccurred_timeout;

/* Media control */
- (void)selectMedia:(DEC21X4XMediaType)media;
- (DEC21X4XMediaType)detectMedia;
- (void)setAutoSenseTimer;
- (void)startAutoSenseTimer;

/* Connection control */
- (void)checkConnectionSupport;
- (void)convertConnectionToControl;
- (void)handleLinkChangeInterrupt;
- (void)handleLinkFailInterrupt;
- (void)handleLinkPassInterrupt;

/* CSR access */
- (unsigned int)readCSR:(int)csr;
- (void)writeCSR:(int)csr value:(unsigned int)value;

/* Chip-specific methods */
- (DEC21X4XChipType)identifyChip;
- (const char *)chipName;
- (BOOL)isChipType:(DEC21X4XChipType)type;

/* Server instance management */
- (DEC21X4XKernelServerInstance *)serverInstance;
- (void)setServerInstance:(DEC21X4XKernelServerInstance *)instance;

/* Network control */
- (void)writeGenRegister:(int)reg value:(unsigned int)value;
- (unsigned int)getDriverName_mediaTypeOccurred;
- (void)scheduleFunc_sendPacket_unscheduleFunc;
- (void)verifyChecksum_writeHi_getDriverName;

/* Delay and timing */
- (void)IODelay_IOFree_IOLog_IOPanic_IOReturn;

@end

/* C helper functions */
#ifdef __cplusplus
extern "C" {
#endif

/* Utility functions from binary exports */
void dec21x4x_page_mask(void);
void dec21x4x_page_size(void);
void dec21x4x_nb_alloc_np_free(void);
void dec21x4x_nb_grow_bot(void);
void dec21x4x_nb_map(void);
void dec21x4x_nb_shrink_bot(void);
void dec21x4x_nb_shrink_top(void);
void dec21x4x_nb_size(void);
void dec21x4x_msgSuper_page_mask(void);

#ifdef __cplusplus
}
#endif
