#ifndef _DECCHIP21140_PRIVATE_H_
#define _DECCHIP21140_PRIVATE_H_

#import "DECchip21140.h"

@interface DECchip21140(Private)
- (BOOL)_allocateMemory;
- (BOOL)_initTxRing;
- (BOOL)_initRxRing;
- (BOOL)_initChip;
- (void)_resetChip;
- (void)_startTransmit;
- (void)_startReceive;
- (void)_initRegisters;
- (BOOL)_transmitPacket:(netbuf_t)packet;
- (void)_receiveInterruptOccurred;
- (void)_transmitInterruptOccurred;
- (void)_getStationAddress:(enet_addr_t *)address;
- (BOOL)_loadSetupFilter:(BOOL)wait;
- (BOOL)_setAddressFiltering:(BOOL)enable;
- (BOOL)_verifyCheckSum;
@end

@interface DECchip21140(VendorSpecific)
- (void)_initGPPortRegisterForCogent100Mb;
- (void)_initGPPortRegisterForCogent10Mb;
- (void)_initGPPortRegisterForDE500100Mb;
- (void)_initGPPortRegisterForCustom;
- (BOOL)getNextValue:(unsigned int *)value fromString:(char *)string;
@end

BOOL IOUpdateDescriptorFromNetBuf(netbuf_t netBuf,
                                  DECchipDescriptor *descriptor,
                                  BOOL isSetupFrame);

#endif
