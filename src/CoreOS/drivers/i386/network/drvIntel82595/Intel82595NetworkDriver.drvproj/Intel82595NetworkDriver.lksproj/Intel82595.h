#ifndef INTEL82595_H
#define INTEL82595_H
#import <sys/types.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IOEthernetPrivate.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <net/netbuf.h>

/* The shipped i386 class extends IOEthernet at 0x174, ends at 0x1a4.
 * All four adapter subclasses inherit these ivars; none adds storage. */
@interface Intel82595 : IOEthernet
{
    unsigned short ioBase;
    int irq;
    enet_addr_t myAddress;
    IONetwork *networkInterface;
    IONetbufQueue *transmitQueue;
    unsigned char myStepping;
    unsigned char currentBank;
    BOOL promiscuousEnabled;
    BOOL multicastEnabled;
    BOOL multicastConfigured;
    BOOL transmitActive;
    unsigned short memoryUsed;
    unsigned short transmitLower, transmitUpper;
    unsigned short receiveLower, receiveUpper, receiveNext;
    unsigned int myAttributeMemory;
}
+ (BOOL)probeIDRegisterAt:(unsigned short)address;
- initFromDeviceDescription:(IODeviceDescription *)description;
- free;
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)coldInit;
- (const char *)description;
- (BOOL)resetChip;
- (BOOL)initializeChip;
- (BOOL)busConfig;
- (BOOL)connectorConfig;
- (BOOL)rxInit;
- (BOOL)txInit;
- (unsigned int)onboardMemoryPresent;
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)transmit:(netbuf_t)packet;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;
- (void)receivePacket:(void *)packet length:(unsigned int *)length timeout:(unsigned int)timeout;
- (void)sendPacket:(void *)packet length:(unsigned int)length;
@end

@interface Intel82595 (Private)
- (unsigned int)_onboardMemoryAvailable;
- (unsigned short)_allocateOnboardMemory:(unsigned int)size;
- (BOOL)_mcSetup;
- (unsigned short)_memoryRegion:(unsigned int)size;
- (BOOL)_receiveInterruptOccurred;
- (BOOL)_transmitInterruptOccurred;
@end

@interface Intel82595ISA : Intel82595
- (BOOL)irqConfig;
@end
@interface CogentEM525 : Intel82595ISA
+ (BOOL)probe:(IODeviceDescription *)description;
@end
@interface CogentEM595 : Intel82595
+ (BOOL)probe:(IODeviceDescription *)description;
@end
@interface IntelEEPro10Plus : Intel82595ISA
+ (BOOL)probe:(IODeviceDescription *)description;
@end
@interface IntelEEPro10 : Intel82595ISA
+ (BOOL)probe:(IODeviceDescription *)description;
- (void)intelEEPro10PnPInit;
@end

@interface i82595eeprom : Object
{
    unsigned short eepromBase;
    int nbits;
    unsigned char contents[128];
}
- initWithBase:(unsigned short)base CurrentBank:(unsigned char *)bank;
- (unsigned short)readWord:(int)address;
- (unsigned char *)getContents;
@end
#endif
