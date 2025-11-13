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

    /* Hardware configuration */
    unsigned short _portBase;          /* I/O port base address */
    unsigned short _irqNumber;         /* IRQ number */
    enet_addr_t _stationAddress;       /* MAC address (6 bytes) */

    /* Network interface */
    id _networkInterface;              /* Network interface object at 0x180 */

    /* Transmit queue */
    id _transmitQueue;                 /* IONetbufQueue for transmit */

    /* State flags at 0x188, 0x189, 0x18a, 0x18b */
    BOOL _isEnabled;
    BOOL _isAttached;
    BOOL _isRunning;
    BOOL _isPollingMode;               /* Polling/debug mode flag */

    /* Network buffers (arrays) */
    netbuf_t _txNetBufs[16];           /* TX netbuf array (16 entries) at 0x18c */
    netbuf_t _rxNetBufs[32];           /* RX netbuf array (32 entries) at 0x1cc */

    /* Descriptor rings */
    DECchipDescriptor *_rxRing;        /* RX ring pointer at 0x24c */
    DECchipDescriptor *_txRing;        /* TX ring pointer at 0x250 */

    unsigned int _txHead;              /* TX ring head pointer at 0x254 */
    unsigned int _txCompletionIndex;   /* TX completion pointer at 0x258 */
    unsigned int _txTail;              /* TX available count at 0x25c */
    unsigned int _txInterruptCounter;  /* TX interrupt counter at 0x260 */
    unsigned int _rxHead;              /* RX ring head pointer at 0x264 */
    netbuf_t _debugNetBuf;             /* Debug/blocking mode netbuf at 0x268 */

    /* Memory allocation */
    void *_descriptorMemory;              /* Base pointer for allocated memory */
    unsigned int _descriptorMemorySize;   /* Size of allocated memory */
    void *_setupFrame;                    /* Setup frame buffer */
    vm_offset_t _setupFramePhys;          /* Physical address of setup frame */

    /* Interface selection */
    unsigned int _interfaceType;          /* 0=AUTO, 1=BNC, 2=AUI, 3=TP at 0x27c */
    unsigned int _interruptMask;          /* Interrupt mask for CSR7 at 0x280 */
    unsigned int _cachedCSR6;             /* Saved CSR6 operational mode at 0x284 */
    unsigned int _linkStatus;             /* Link status flags at 0x288 */

    /* Statistics */
    unsigned int _txInterrupts;
    unsigned int _rxInterrupts;
    unsigned int _errorInterrupts;

    /* Duplex mode */
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
