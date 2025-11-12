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

- (BOOL)allocateMemory;
- (BOOL)initChip;
- (void)initRegisters;
- (BOOL)initRxRing;
- (BOOL)initTxRing;
- (void)loadSetupFilter:(BOOL)perfect;
- (void)receiveInterruptOccurred;
- (void)resetChip;
- (void)setAddressFiltering:(BOOL)enable;
- (void)startReceive;
- (void)startTransmit;
- (void)transmitInterruptOccurred;
- (BOOL)transmitPacket:(netbuf_t)pkt;
- (BOOL)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;
- (BOOL)sendPacket:(void *)data length:(unsigned int)length;

@end

#endif /* _DECCHIP2104XPRIVATE_H */
