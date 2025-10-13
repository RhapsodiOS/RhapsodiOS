/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * BusLogic FlashPoint SCSI Driver
 */

#import <driverkit/IODirectDevice.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@interface BusLogicFPSCSI : IOSCSIController
{
    IOPCIDevice *_pciDevice;
    unsigned int _baseAddress;
    unsigned int _irq;
    unsigned char _busNumber;
    unsigned char _deviceNumber;
    unsigned char _functionNumber;

    void *_cardHandle;
    void *_sccbMgrInfo;

    BOOL _initialized;
    unsigned char _scsiId;
    unsigned char _maxTargets;
    unsigned char _maxLun;

    IOEISADeviceDescription *_deviceDescription;

    /* Threading support */
    port_t _interruptPort;
    port_t _commandPort;
    id _controllerThread;
    BOOL _threadRunning;

    /* Command queue */
    queue_head_t _pendingQueue;
    simple_lock_data_t _queueLock;
}

+ (BOOL)probe:(IOPCIDevice *)deviceDescription;
- initFromDeviceDescription:(IOPCIDevice *)deviceDescription;

/* IODevice methods */
- (BOOL)reset;
- (void)free;

/* IOSCSIController methods */
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiRequest
                       buffer:(void *)buffer
                       client:(vm_task_t)client;

/* Hardware interface */
- (BOOL)resetHardware;
- (BOOL)initializeHardware;
- (void)interruptOccurred;
- (void)timeoutOccurred;

/* FlashPoint specific */
- (BOOL)resetSCSIBus;
- (void)createSCCB:(void *)sccb
        forRequest:(IOSCSIRequest *)request
            buffer:(void *)buffer
            client:(vm_task_t)client;

/* Additional exported methods from binary */
- (void)scsiComplete:(void *)sccb;
- (void)scsiCallback:(void *)sccb;
- threadComplete:(void *)sccb reason:(int)reason;
- cmdComplete:(void *)sccb;
- delete;
- cmdCancel:(void *)sccb;
- createSCCBs;
- resetHardware_xxx_8_xxx_11_xxx_14_xxx_8_xxx_11_xxx_14_first_time_2;

/* Threading methods */
- (void)controllerThread:(void *)arg;
- (BOOL)startControllerThread;
- (void)stopControllerThread;
- (void)queueCommand:(void *)sccb;
- (void *)dequeueCommand;

@end

/* FlashPoint SCCB Manager interface */
extern void *FlashPoint_ProbeHostAdapter(void *pCurrCard);
extern unsigned long FlashPoint_HardwareResetHostAdapter(void *pCurrCard);
extern void FlashPoint_StartCCB(void *pCurrCard, void *p_Sccb);
extern int FlashPoint_AbortCCB(void *pCurrCard, void *p_Sccb);
extern unsigned char FlashPoint_InterruptPending(void *pCurrCard);
extern int FlashPoint_HandleInterrupt(void *pCurrCard);
extern void FlashPoint_ReleaseHostAdapter(void *pCurrCard);
