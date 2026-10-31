/* i386 interface recovered from the BusLogicFPSCSI_reloc image. */
#ifndef _BUSLOGICFPSCSI_H
#define _BUSLOGICFPSCSI_H

#import <driverkit/IOSCSIController.h>
#import <mach/mach_types.h>
#import "FlashPoint.h"
#import "BusLogicFPPrivate.h"

@protocol BLFPConditionLockInterface
- (void)lock;
- (void)lockWhen:(int)value;
- (void)unlockWith:(int)value;
- (id)free;
@end

@protocol BLFPLockInterface
- (void)lock;
- (void)unlock;
@end

@interface NXConditionLock
+ (id)alloc;
- (id)initWith:(int)value;
- (id)free;
@end

@interface NXLock
+ (id)alloc;
- (id)init;
- (id)free;
- (void)lock;
- (void)unlock;
@end

@interface BLFPController : IOSCSIController
{
    unsigned short ioBase;                    /* 0x244 */
    unsigned int irq;                         /* 0x248 */
    struct sccb_mgr_info *sccbMgr;             /* 0x24c */
    void *sccbMgrRaw;                         /* 0x250 */
    struct sccb_card *cardHandle;              /* 0x254 */
    struct blfp_queue_head sccbFreeList;        /* 0x258 */
    struct blfp_queue_head commandQ;            /* 0x260 */
    id commandLock;                            /* 0x268 */
    struct blfp_queue_head outstandingQ;        /* 0x26c */
    unsigned int outstandingCount;              /* 0x274 */
    unsigned int maxQueueLen;                   /* 0x278 */
    unsigned int queueLenTotal;                 /* 0x27c */
    unsigned int totalCommands;                 /* 0x280 */
    port_t interruptPortKern;                   /* 0x284 */
    unsigned char ioThreadRunning;              /* 0x288 */
    int busType;                                /* 0x28c */
    unsigned char levelIRQ;                     /* 0x290 */
    unsigned char targetsPerBus;                /* 0x291 */
    unsigned int :0;                            /* round instance size to 0x294 */
}

+ (int)probe:(id)deviceDescription;
- (unsigned int)maxTransfer;
- (int)numberOfTargets;
- (id)free;
- (unsigned int)numQueueSamples;
- (unsigned int)sumQueueLengths;
- (unsigned int)maxQueueLength;
- (void)resetStats;
- (int)executeRequest:(id)request buffer:(void *)buffer client:(vm_task_t)client;
- (int)resetSCSIBus;
- (void)interruptOccurred;
- (void)interruptOccurredAt:(int)interrupt;
- (void)otherOccurred:(int)message;
- (void)receiveMsg;
- (int)resetHardware;
- (int)probeForBoard;

@end

@interface BLFPController (Initialization)
- (id)initFromDeviceDescription:(id)deviceDescription;
@end

@interface BLFPController (PrivateMethods)
- (int)executeCmdBuf:(struct blfp_command_record *)command;
- (void)enableAllInterrupts;
- (struct sccb *)allocSccb;
- (void)freeSccb:(struct sccb *)sccb;
- (void)createSCCBs;
- (void)cmdComplete:(struct blfp_command_record *)command;
- (void)sccbComplete:(struct sccb *)sccb reason:(int)reason;
- (void)commandRequestOccurred;
- (void)threadExecuteRequest:(struct blfp_command_record *)command;
- (void)threadResetBus:(struct blfp_command_record *)command;
- (int)sccbFromCmd:(struct blfp_command_record *)command;
@end

#endif
