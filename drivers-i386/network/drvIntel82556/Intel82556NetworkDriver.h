/*
 * Intel82556NetworkDriver.h
 * Intel EtherExpress PRO/100 EISA Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEISADeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOEISADirectDevice.h>

@interface Intel82556NetworkDriver : IOEthernetDriver
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

/* Internal utility methods */
- (BOOL)allocateBuffers;
- (void)freeBuffers;
- (BOOL)initChip;
- (void)resetChip;

/* MII/PHY management */
- (int)miiRead:(int)phyAddr reg:(int)regAddr;
- (void)miiWrite:(int)phyAddr reg:(int)regAddr value:(int)value;
- (BOOL)checkLink;

/* EEPROM access */
- (unsigned short)eepromRead:(int)location;
- (void)eepromWrite:(int)location value:(unsigned short)value;

/* DMA operations */
- (BOOL)setupDMA;
- (void)startTransmit;
- (void)stopTransmit;

@end
