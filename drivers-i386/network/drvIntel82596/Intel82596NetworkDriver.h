/*
 * Intel82596NetworkDriver.h
 * Intel 82596 EISA Ethernet Adapter Driver (Cogent EM935)
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOEISADirectDevice.h>

@interface Intel82596NetworkDriver : IOEthernetDriver
{
    IOEISADeviceDescription *_deviceDescription;
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

    /* 82596 specific structures */
    void *_scbBase;              /* System Configuration Block */
    void *_iscp;                 /* Intermediate System Configuration Pointer */
    void *_scp;                  /* System Configuration Pointer */
    void *_cmdList;              /* Command list */
    void *_rfdList;              /* Receive Frame Descriptor list */
    void *_rbdList;              /* Receive Buffer Descriptor list */
    void *_tbd;                  /* Transmit Buffer Descriptor */

    unsigned int _cmdIndex;
    unsigned int _rfdIndex;
    BOOL _promiscuousMode;
    unsigned int _multicastCount;
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

/* Interrupt handling */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)serviceTransmitQueue;
- (void)acknowledgeInterrupts;

/* Configuration methods */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr;

/* Power management */
- (IOReturn)getPowerState;
- (IOReturn)setPowerState:(unsigned int)state;

/* Diagnostics and statistics */
- (void)resetStats;
- (void)updateStats;

/* Internal utility methods */
- (BOOL)allocateBuffers;
- (void)freeBuffers;
- (BOOL)initChip;
- (void)resetChip;
- (void)coldInit;

/* 82596 specific command operations */
- (int)polledCommand:(void *)cmd;
- (void)processRecInterrupt;
- (void)processCmdInterrupt;
- (void)startCommandUnit;
- (void)scheduleReset;

/* Buffer management */
- (void)initRxRd;
- (void)initTxRd;
- (void)serviceRxInt;
- (void)botRxReceiveInt;

/* Multicast support */
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)enableAllInterrupts2;
- (void)disableAllInterrupts2;

/* Transmit operations */
- (void)transmit;
- (void)timeoutOccurred2;
- (void)waitScb;

/* Memory and wrapper functions */
- (void)nb_alloc_wrapper;
- (void)nb_free;
- (void)nb_map;
- (void)nb_shrink_bot;
- (void)nb_size;
- (void)nb_timeout;
- (void)nb_msgSend;
- (void)msgSendSuper_page_mask_page_size;

/* CogentEMaster specific methods */
- (void)cogentEMaster_clearIrqLatch;
- (void)cogentEMaster_sendChannelAttention;

/* IntelEEFlash32 specific methods */
- (void)intelEEFlash32_probe;
- (void)intelEEFlash32_initFromDeviceDescription;
- (void)intelEEFlash32_clearIrqLatch;
- (void)intelEEFlash32_sendChannelAttention;
- (void)intelEEFlash32_interruptOccurred;

/* IntelPRO10PCI specific methods */
- (void)intelPRO10PCI_probe;
- (void)intelPRO10PCI_setConnectorType;
- (void)intelPRO10PCI_getConnectorType;
- (void)intelPRO10PCI_initFromDeviceDescription;
- (void)intelPRO10PCI_clearIrqLatch;
- (void)intelPRO10PCI_initChip;
- (void)intelPRO10PCI_resetChip;
- (void)intelPRO10PCI_enableAdapterInterrupts;
- (void)intelPRO10PCI_disableAdapterInterrupts;
- (void)intelPRO10PCI_resetEnable;

/* Description and identification */
- (void)description;

@end
