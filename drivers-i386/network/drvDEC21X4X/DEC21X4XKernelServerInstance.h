/*
 * DEC21X4XKernelServerInstance.h
 * Kernel Server Instance for DEC21X4X Network Driver
 */

#import <objc/Object.h>
#import <driverkit/return.h>

@class DEC21X4X;

@interface DEC21X4XKernelServerInstance : Object
{
    DEC21X4X *_driver;
    void *_transmitQueues;
    void *_receiveQueues;
    unsigned int _queueCount;
    BOOL _isOpen;
    void *_reserved1;
    void *_reserved2;
}

/* Initialization */
- initWithDriver:(DEC21X4X *)driver;
- free;

/* Server instance methods from binary exports */
- (int)_init;
- (int)_initDeviceDescription;
- (int)_initSIARegisters;
- (int)_initAdapter;
- (int)_initInterrupts;
- (int)_initNetworking;
- (int)_initTransmitQueues;
- (int)_initReceiveQueues;

/* Channel control */
- (int)_openChannel;
- (int)_closeChannel;

/* Mode control */
- (int)_enableMulticastMode;
- (int)_disableMulticastMode;
- (int)_enablePromiscuousMode;
- (int)_disablePromiscuousMode;

/* Setup and filtering */
- (int)_getSetupFilter;
- (int)_setAddressFiltering;
- (int)_setMulticastAddr;
- (int)_setAddress:(void *)addr;
- (int)_getStationAddress:(void *)addr;
- (unsigned int)_getDriverName_forParameter_count_mediaSupport;

/* Interface control */
- (int)_selectInterface:(int)interface;
- (int)_setOwnerState;
- (int)_setNetworkState;
- (int)_getOwnerState;

/* Transmit operations */
- (int)_scanTransmitQueue;
- (int)_transmitInterruptOccurred;
- (int)_transmitQueueSize;
- (unsigned int)_transmitQueueCount;
- (int)_pendingTransmitCount;
- (int)_allocateNetbuf;
- (int)_enablePromiscuousMode;
- (int)_timeoutOccurred;
- (int)_startTransmit;
- (int)_resetTransmit;
- (int)_sendPacket_length:(void *)packet length:(unsigned int)len;

/* Receive operations */
- (int)_receiveInterruptOccurred;
- (int)_startReceive;
- (int)_resetReceive;
- (int)_receivePacket_length:(void *)packet;

/* Connection control methods from binary exports */
- (void)_checkConnectionSupport_ConnectionType;
- (void)_convertConnectionToControl;
- (void)_handleLinkChangeInterrupt;
- (void)_handleLinkFailInterrupt;
- (void)_handleLinkPassInterrupt;

/* Media control */
- (int)_selectMedia:(int)media;
- (int)_detectMedia;
- (void)_setAutoSenseTimer;
- (void)_startAutoSenseTimer;
- (void)_checkLink;

/* PHY control */
- (int)_setPhyConnection:(int)connectionType;
- (int)_getPhyControl;
- (void)_setPhyControl:(int)control;

/* Descriptor control */
- (int)_initDescriptors;
- (int)_setupRxDescriptors;
- (int)_setupTxDescriptors;

/* Statistics and status */
- (void)_getStatistics;
- (void)_updateStats;
- (void)_resetStats;
- (unsigned int)_getValues_count;

/* Network control */
- (void)_doAutoForSelect;
- (void)_writeGenRegister:(int)reg value:(unsigned int)value;
- (void)_verifyChecksum_writeHi_getDriverName;
- (void)_scheduleFunc_sendPacket_unscheduleFunc;

/* Management methods */
- (DEC21X4X *)driver;
- (void)setDriver:(DEC21X4X *)driver;
- (BOOL)isOpen;
- (void)setOpen:(BOOL)open;

@end
