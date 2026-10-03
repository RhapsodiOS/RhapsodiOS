/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * The PCI device owns the AIC host block and creates an SCSIBus controller.
 */

#ifndef _ADAPTEC2940_H
#define _ADAPTEC2940_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/return.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "Adaptec2940Types.h"

@interface Adaptec2940 : IODirectDevice
{
	/* Ivar offsets start at 296, after IODirectDevice's 296-byte prefix. */
	unsigned short ioBase;                 /* 296 */
	unsigned short _pad_ioBase;            /* 298 */
	Adaptec2940ChannelInfo channelInfo[1]; /* 300 */
	Adaptec2940HostInfo *hspStructSave;    /* 308 */
	unsigned int hspStructFreeSize;        /* 312 */
	int interruptPortKern;                 /* 316 */
	queue_head_t commandQ;                 /* 320 */
	id commandLock;                        /* 328 */
	queue_head_t activeQ;                  /* 332 */
	queue_head_t scbQ;                     /* 340 */
	unsigned int scbQLength;               /* 348 */
	queue_head_t scbBadQ;                  /* 352 */
	unsigned autoSenseEnable:1;            /* 360, bit 0 */
	unsigned cmdQueueEnable:1;              /* 360, bit 1 */
	unsigned syncModeEnable:1;              /* 360, bit 2 */
	unsigned ioThreadRunning:1;             /* 360, bit 3 */
	unsigned needReinit:1;                  /* 360, bit 4 */
	unsigned _pad_flags:27;                 /* 360, bits 5..31 */
	unsigned int reinitChannel;             /* 364 */
	int resetState;                         /* 368 */
	unsigned int maxQueueLen;               /* 372 */
	unsigned int queueLenTotal;             /* 376 */
	unsigned int totalCommands;             /* 380 */
	unsigned int outstandingCount;          /* 384 */
	int busType;                            /* 388 */
	char levelIRQ;                          /* 392 */
	unsigned char busNumber;                /* 393 */
	unsigned char deviceNumber;             /* 394 */
	unsigned char functionNumber;           /* 395 */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (id)free;
- (void)resetStats;
- (unsigned int)numQueueSamples;
- (unsigned int)sumQueueLengths;
- (unsigned int)maxQueueLength;
- (int)numberOfTargets:(int)channel;
- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)localNum;
- (void)otherOccurred:(int)event;
- (void)receiveMsg;
- (void)timeoutOccurred;
- (void)commandRequestOccurred;
- (IOReturn)setIntValues:(unsigned int *)parameters
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count;
- (IOReturn)getIntValues:(unsigned int *)parameters
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count;
- (char)acquireSCSIBus:(unsigned int)channel owner:(id)owner;
- (void)releaseSCSIBus:(unsigned int)channel owner:(id)owner;
- (unsigned int)maxTransfer;
- (int)scsiBusId:(unsigned int)channel;
- (int)executeCmdBuf:(Adaptec2940RequestMessage *)message;
- (char)checkScbAlign:(Adaptec2940SCB *)scb;
- (Adaptec2940SCB *)allocScb;
- (void)freeScb:(Adaptec2940SCB *)scb;
- (void)createScbs:(unsigned int)base size:(unsigned int)size;
- (void)threadExecuteRequest:(Adaptec2940RequestMessage *)message;
- (void)threadResetBus:(Adaptec2940RequestMessage *)message
              channel:(unsigned int)channel
               reason:(const char *)reason;
- (void)commandCompleted:(Adaptec2940SCB *)scb;
- (void)scbComplete:(Adaptec2940SCB *)scb;
- (unsigned int)initHostAdaptor;
- (void)startIOThread;
- (void)enableAllInterrupts;
- (id)deviceDescription;
- (port_t)interruptPort;
@end

#endif /* _ADAPTEC2940_H */
