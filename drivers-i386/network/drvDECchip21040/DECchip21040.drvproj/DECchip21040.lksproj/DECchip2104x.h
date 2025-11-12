/*
 * DECchip2104x.h
 * Base class for DEC 21040/21041 Ethernet Controllers
 */

#import <driverkit/IOEthernet.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import "DECchip2104xRegisters.h"
#import "DECchip2104xShared.h"

@interface DECchip2104x : IOEthernet
{
@private
    IOPCIDeviceDescription *_deviceDescription;
    IORange *_ioRange;
    volatile void *_ioBase;
    void *_csrBase;

    /* Descriptor rings */
    DECchipDescriptor *_txRing;
    DECchipDescriptor *_rxRing;
    vm_offset_t _txRingPhys;
    vm_offset_t _rxRingPhys;

    unsigned int _txHead;
    unsigned int _txTail;
    unsigned int _rxHead;

    /* Network buffers */
    netbuf_t *_txNetBufs;
    netbuf_t *_rxNetBufs;

    /* Statistics */
    unsigned int _txInterrupts;
    unsigned int _rxInterrupts;
    unsigned int _errorInterrupts;

    /* State */
    BOOL _isRunning;
    BOOL _isFullDuplex;
}

/* Initialization */
+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;

/* Hardware control */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)interruptOccurred;

/* Network device methods */
- (int)transmit:(netbuf_t)pkt;
- (void)receivePackets;

/* Configuration */
- (void)getEthernetAddress:(enet_addr_t *)addr;
- (BOOL)setFullDuplex:(BOOL)fullDuplex;

@end
