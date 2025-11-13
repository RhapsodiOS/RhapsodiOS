/*
 * DECchip2104xPrivate.h
 * Private helper functions for DEC 21040/21041 driver
 */

#ifndef _DECCHIP2104XPRIVATE_H
#define _DECCHIP2104XPRIVATE_H

#include <driverkit/IONetworkDeviceDescription.h>
#include "DECchip2104xShared.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Update a DMA descriptor from a network buffer.
 * Returns: 1 on success, 0 on failure
 */
BOOL IOUpdateDescriptorFromNetBuf(netbuf_t netBuf,
                                   DECchipDescriptor *descriptor,
                                   BOOL isSetupFrame);

#ifdef __cplusplus
}
#endif

/* Import for category */
#import "DECchip2104x.h"

/* Private category methods */
@interface DECchip2104x(Private)

/* PCI Configuration */
+ (IOReturn)getPCIConfigSpace:(void *)configSpace withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc;
+ (IOReturn)getPCIConfigData:(unsigned int *)data atRegister:(unsigned int)reg withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc;
+ (IOReturn)setPCIConfigData:(unsigned int)data atRegister:(unsigned int)reg withDeviceDescription:(IOPCIDeviceDescription *)deviceDesc;

/* Memory management */
- (BOOL)allocateMemory;

/* Chip initialization */
- (BOOL)initChip;
- (void)initRegisters;
- (BOOL)initRxRing;
- (BOOL)initTxRing;

/* Filtering */
- (void)loadSetupFilter:(BOOL)perfect;
- (BOOL)setAddressFiltering:(BOOL)enable;

/* Interrupt handlers */
- (void)receiveInterruptOccurred;
- (void)transmitInterruptOccurred;

/* Chip control */
- (void)resetChip;
- (void)startReceive;
- (void)startTransmit;

/* Packet I/O */
- (BOOL)transmitPacket:(netbuf_t)pkt;
- (BOOL)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
- (BOOL)sendPacket:(void *)data length:(unsigned int)length;

@end

#endif /* _DECCHIP2104XPRIVATE_H */
