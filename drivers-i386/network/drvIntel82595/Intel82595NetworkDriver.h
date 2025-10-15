/*
 * Intel82595NetworkDriver.h
 * Intel 82595 PCMCIA Ethernet Adapter Driver (Cogent EM595)
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/IODirectDevice.h>

@interface Intel82595NetworkDriver : IOEthernetDriver
{
    IODeviceDescription *_deviceDescription;
    unsigned char _romAddress[6];
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
    unsigned int _memoryRegion;
    unsigned int _bankSelect;
    BOOL _promiscuousMode;
    BOOL _multicastMode;
    unsigned int _rxBufferStart;
    unsigned int _rxBufferEnd;
    unsigned int _txBufferStart;
    unsigned int _txBufferEnd;
    unsigned int _rxStopPtr;
    unsigned int _rxReadPtr;
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
- (unsigned int)receiveQueueCount;

/* Interrupt handling */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)receiveInterruptOccurred;
- (void)transmitInterruptOccurred;

/* Configuration methods */
- (BOOL)getHardwareAddress:(enet_addr_t *)addr;

/* Power management */
- (IOReturn)getPowerState;
- (IOReturn)setPowerState:(unsigned int)state;

/* Diagnostics and statistics */
- (void)resetStats;
- (void)updateStats;
- (void)getStatistics;

/* Internal utility methods */
- (BOOL)allocateBuffers;
- (void)freeBuffers;
- (BOOL)initChip;
- (void)resetChip;
- (void)coldInit;

/* Register bank selection */
- (void)selectBank:(unsigned int)bank;

/* Memory management */
- (void)allocateMemoryAvailable;
- (void)scheduleReset;
- (void)stoppingDesc;

/* Multicast and promiscuous support */
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticast;

/* Transmit operations */
- (void)transmitInterruptOccurred2;
- (void)sendPacket:(void *)pkt length:(unsigned int)len;
- (void)resetEnable;

/* Buffer management */
- (void)initTxRd;
- (void)onboardMemoryPresent;

/* EEPROM operations */
- (unsigned short)eepromIOSleep;
- (void)eepromIODezero;
- (unsigned short)eepromIOAlloc;

/* Description and identification */
- (void)description;
- (void)resetChip2;

/* IntelEEPro10Plus specific methods */
- (void)intelEEPro10Plus_probe;
- (void)intelEEPro10Plus_busConfig;
- (void)intelEEPro10Plus_coldInit;
- (void)intelEEPro10Plus_resetChip;
- (void)intelEEPro10Plus_io_address_enable_str;
- (void)intelEEPro10Plus_allocateMemoryAvailable;

/* CogentEM595 specific methods */
- (void)cogentEM595_probe;
- (void)cogentEM595_coldInit;
- (void)cogentEM595_description;
- (void)cogentEM595_allocateMemoryAvailable;
- (void)cogentEM595_stoppingDesc;

@end
