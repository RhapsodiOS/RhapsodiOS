/*
 * EtherLink3.h
 * 3Com EtherLink III Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>

typedef struct {
    netbuf_t head;
    netbuf_t tail;
    unsigned int count;
    unsigned int max;
} EtherLink3Queue;

@interface EtherLink3 : IOEthernetDriver
{
    /* Offsets are relative to the start of the Objective-C instance. */
    unsigned short ioBase;              /* 0x174 */
    unsigned int reported_irq;          /* 0x178 */
    unsigned int real_irq;              /* 0x17c */
    enet_addr_t myAddress;              /* 0x180 */
    int myConnector;                    /* 0x188 */
    unsigned char autoConnector;        /* 0x18c */
    unsigned short myType;              /* 0x18e */
    unsigned char isISA;                /* 0x190 */
    id networkInterface;                /* 0x194 */
    unsigned char resetInProgress;       /* 0x198 */
    unsigned short rxEarlyThreshold;     /* 0x19a */
    unsigned char rxModes;               /* 0x19c */
    unsigned char currentWindow;         /* 0x19d */
    EtherLink3Queue txQ;                 /* 0x1a0 */
    EtherLink3Queue txFreeQ;             /* 0x1b0 */
    EtherLink3Queue rxQ;                 /* 0x1c0 */
    EtherLink3Queue rxPoolQ;             /* 0x1d0 */
    unsigned char interruptHappened;      /* 0x1e0 */
    unsigned int outputErrors;           /* 0x1e4 */
    unsigned int collisions;             /* 0x1e8 */
    unsigned int outputPackets;          /* 0x1ec */
    unsigned int inputErrors;            /* 0x1f0 */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;
- (BOOL)resetAndEnable:(BOOL)enable;

- (void)setISA:(BOOL)flag;
- (void)setIOBase:(unsigned short)base;
- (void)setIRQ:(unsigned int)interrupt;
- (void)setDoAuto:(BOOL)flag;

- (void)_doAutoConnectorDetect;
- (BOOL)_hwInit;
- (void)_scheduleReset;

- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt;
- (void)transmit:(netbuf_t)packet;
- (unsigned int)transmitQueueSize;
- (unsigned int)transmitQueueCount;
- (netbuf_t)allocateNetbuf;
- (void)QFill:(EtherLink3Queue *)queue;
- (IOReturn)getPowerManagement:(void *)powerManagement;
- (IOReturn)setPowerManagement:(unsigned int)powerLevel;
- (IOReturn)getPowerState:(void *)powerState;
- (IOReturn)setPowerState:(unsigned int)powerState;
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;
@end

@interface EtherLink3EISA : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

@interface EtherLink3PCMCIA : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

@interface EtherLink3PnP : EtherLink3
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
@end

@interface EtherLink3KernelServerInstance : Object
+ (id)kernelServerInstance;
@end

@interface EtherLink3Version : Object
+ (const char *)driverKitVersionForEtherLink3;
@end
