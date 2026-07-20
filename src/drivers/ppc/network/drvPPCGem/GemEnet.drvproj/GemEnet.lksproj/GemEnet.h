/* GemEnet.h - PowerPC Gem Ethernet Driver */

#import <driverkit/IOEthernet.h>
#import <driverkit/ppc/directDevice.h>

/* multicast entry */
#define	MAR_MAX	32

struct mar_entry {
    BOOL	valid;
    enet_addr_t	addr;
};

@interface GemEnet : IOEthernet
{
    IOPCIMemoryAddress	memBase;	/* memory base address */
    IORange		memRange;	/* memory base and extent */
    int			irq;		/* interrupt */
    enet_addr_t		myAddress;	/* local copy of ethernet address */
    IONetwork		*network;	/* handle to kernel network object */
    id			transmitQueue;	/* transmit queue */
    BOOL		promiscuousMode;/* Promiscuous mode flag (offset 0x188) */
    BOOL		multicastEnabled;/* Multicast enabled flag (offset 0x189) */
    BOOL		ready;		/* Ready flag (offset 0x18a) */
    unsigned char	pad_18b;	/* Padding (offset 0x18b) */
    unsigned int	initValue1;	/* Init value (offset 0x18c) */
    unsigned char	initValue2;	/* Init value (offset 0x190) */
    unsigned char	initValue3;	/* Init value (offset 0x191) */
    unsigned short	linkStatus;	/* Link status (offset 0x192) */

    /* Multicast support */
    struct mar_entry	mar_list[MAR_MAX];	/* multicast address list */
    int			mar_cnt;		/* multicast address list count */
    unsigned char	mcfilter[8];		/* multicast filter */

    /* Transmit/Receive ring buffers */
    void		*txRing;		/* transmit ring buffer */
    void		*rxRing;		/* receive ring buffer */

    /* DMA memory management */
    unsigned int	txHead;			/* TX ring head (offset 0x594) */
    unsigned int	txTail;			/* TX ring tail (offset 0x598) */
    unsigned int	rxDMACommandsSize;	/* RX DMA size (offset 0x59c) */
    unsigned int	rxHead;			/* RX ring head (offset 0x5a0) */
    unsigned int	rxTail;			/* RX ring tail (offset 0x5a4) */
    unsigned int	txDMACommandsSize;	/* TX DMA size (offset 0x5a8) */
    void		*dmaCommands;		/* DMA command memory (offset 0x5ac) */
    void		*rxDMACommands;		/* RX DMA commands virtual (offset 0x5b0) */
    unsigned int	txDMACommandsPhys;	/* TX DMA commands physical (offset 0x5b4) */
    void		*txDMACommands;		/* TX DMA commands virtual (offset 0x5b8) */
    unsigned int	rxDMACommandsPhys;	/* RX DMA commands physical (offset 0x5bc) */
    unsigned int	pad_5c0;		/* Padding (offset 0x5c0) */
    unsigned int	pad_5c4;		/* Padding (offset 0x5c4) */
    void		*debuggerPktBuffer;	/* Debugger packet buffer (offset 0x5c8) */
    unsigned int	debuggerPktLength;	/* Debugger packet length (offset 0x5cc) */

    /* Multicast hash table */
    unsigned short	hashTableUseCount[256];	/* Hash usage counter (offset 0x5d0) */
    unsigned short	hashTableMask[32];	/* Hash filter mask (offset 2000/0x7d0) */

    /* Status flags */
    BOOL		transmitActive;		/* Transmit active */
    BOOL		promMode;		/* Promiscuous mode */
    BOOL		multiMode;		/* Multicast mode */

    /* Link status */
    unsigned short	linkStatus;		/* Link status (offset 0x192) */
    unsigned short	pad3;			/* Padding */

    /* TX netbuf array */
    netbuf_t		txNetbufs[128];		/* TX netbuf array (offset 0x194) */

    /* RX netbuf array */
    netbuf_t		rxNetbufs[128];		/* RX netbuf array (offset 0x394) */

    /* Hardware info */
    int			debug;			/* debug level flag; 0=off */
}

/* Class method */
+ (BOOL)probe:(IODeviceDescription *)devDesc;

/* Initialization and cleanup */
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- free;

/* Hardware control */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;
- (void)interruptOccurred;

/* Power management */
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerState:(PMPowerState)state;

/* Multicast support */
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;

/* Promiscuous mode */
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;

/* Multicast mode */
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;

/* Transmit/Receive */
- (void)transmit:(netbuf_t)pkt;
- (void)sendPacket:(void *)pkt length:(unsigned int)len;
- (void)receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout;
- (void)serviceTransmitQueue;
- (unsigned int)transmitQueueCount;
- (unsigned int)transmitQueueSize;

@end

/* Private methods category */
@interface GemEnet(Private)

/* Hardware initialization */
- (void)_initChip;
- (void)_resetChip;
- (void)_startChip;
- (void)_allocateMemory;

/* Ring buffer management */
- (void)_initTxRing;
- (void)_initRxRing;

/* Interrupt handling */
- (void)_enableAdapterInterrupts;
- (void)_disableAdapterInterrupts;
- (void)_transmitInterruptOccurred;
- (void)_receiveInterruptOccurred;

/* Transmit operations */
- (void)_transmitPacket:(netbuf_t)packet;
- (void)_sendPacket:(void *)pkt length:(unsigned int)len;
- (void)_sendDummyPacket;
- (void)_stopTransmitDMA;
- (void)_restartTransmitter;

/* Receive operations */
- (void)_receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout;
- (void)_receivePackets:(BOOL)freeRun;
- (void)_receiveInterruptOccurred;
- (void)_stopReceiveDMA;
- (void)_restartReceiver;

/* Multicast hash table */
- (void)_updateGemHashTableMask;
- (void)_addToHashTableMask:(enet_addr_t *)addr;
- (void)_removeFromHashTableMask:(enet_addr_t *)addr;

/* Utilities */
- (void)_getStationAddress:(enet_addr_t *)addr;
- (BOOL)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(void *)desc ReceiveFlag:(BOOL)isReceive;
- (void)_monitorLinkStatus;
- (void)_dumpRegisters;
- (void)_packetToDebugger:(void *)pkt;

@end
