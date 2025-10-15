/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * EtherExpress16.h - Intel EtherExpress 16 Ethernet Driver
 */

#import <driverkit/IOEthernet.h>
#import <driverkit/i386/IOPCIDevice.h>

@interface EtherExpress16 : IOEthernet
{
    unsigned short ioBase;
    unsigned int   irq;
    unsigned char  myAddress[6];
    void          *kernelServerInstance;
}

+ (BOOL)probe:(IOPCIDevice *)devDesc;
- initFromDeviceDescription:(IOPCIDevice *)devDesc;
- free;

- (BOOL)resetChip;
- (BOOL)initChip;
- (void)resetEtherChip:(id)arg_88_xxx_93_xxx_96_xxx_99;

- (int)getIntValues:(unsigned int **)paramPtr count:(unsigned int *)count
           forParameter:(IOParameterName)parameterName;

- (IOReturn)getHandler:(IOEthernetHandler *)handler
                 level:(unsigned int *)level
              argument:(void **)arg
           forInterrupt:(unsigned int)irqNum;

- (void)interruptOccurred;
- (void)timeoutOccurred;

- (BOOL)enableAllInterrupts;
- (BOOL)disableAllInterrupts;
- (void)sendPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket;

- (IOReturn)getEtherAddress:(enet_addr_t *)ea;
- (void)setRunningState:(BOOL)state;
- (BOOL)isRunning;

@end
