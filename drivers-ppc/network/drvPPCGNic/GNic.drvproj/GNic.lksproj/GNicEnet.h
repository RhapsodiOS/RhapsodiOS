/* GNicEnet.h - PowerPC GNic Ethernet Driver */

#import <driverkit/IOEthernet.h>
#import <driverkit/ppc/directDevice.h>

/* multicast entry */
#define	MAR_MAX	32

struct mar_entry {
    BOOL	valid;
    enet_addr_t	addr;
};

@interface GNicEnet : IOEthernet
{
    IOPCIMemoryAddress	memBase;	/* memory base address */
    IORange		memRange;	/* memory base and extent */
    int			irq;		/* interrupt */
    enet_addr_t		myAddress;	/* local copy of ethernet address */
    IONetwork		*network;	/* handle to kernel network object */
    id			transmitQueue;	/* transmit queue */
    BOOL		promiscuousMode;/* Promiscuous mode flag */
    BOOL		multicastEnabled;/* Multicast enabled flag */
    BOOL		ready;		/* Ready flag */
    unsigned char	pad_18b;	/* Padding */
    unsigned int	initValue1;	/* Init value */
    unsigned char	initValue2;	/* Init value */
    unsigned char	initValue3;	/* Init value */
    unsigned short	linkStatus;	/* Link status */

    /* Multicast support */
    struct mar_entry	mar_list[MAR_MAX];	/* multicast address list */
    int			mar_cnt;		/* multicast address list count */
    unsigned char	mcfilter[8];		/* multicast filter */

    /* Transmit/Receive ring buffers */
    void		*txRing;		/* transmit ring buffer */
    void		*rxRing;		/* receive ring buffer */

    /* DMA memory management */
    unsigned int	txHead;			/* TX ring head */
    unsigned int	txTail;			/* TX ring tail */
    unsigned int	rxDMACommandsSize;	/* RX DMA size */
    unsigned int	rxHead;			/* RX ring head */
    unsigned int	rxTail;			/* RX ring tail */
    unsigned int	txDMACommandsSize;	/* TX DMA size */
    void		*dmaCommands;		/* DMA command memory */
    void		*rxDMACommands;		/* RX DMA commands virtual */
    unsigned int	txDMACommandsPhys;	/* TX DMA commands physical */
    void		*txDMACommands;		/* TX DMA commands virtual */
    unsigned int	rxDMACommandsPhys;	/* RX DMA commands physical */
    unsigned int	pad_5c0;		/* Padding */
    unsigned int	pad_5c4;		/* Padding */
    void		*debuggerPktBuffer;	/* Debugger packet buffer */
    unsigned int	debuggerPktLength;	/* Debugger packet length */

    /* Multicast hash table */
    unsigned short	hashTableUseCount[256];	/* Hash usage counter */
    unsigned short	hashTableMask[32];	/* Hash filter mask */

    /* TX netbuf array */
    netbuf_t		txNetbufs[128];		/* TX netbuf array */

    /* RX netbuf array */
    netbuf_t		rxNetbufs[128];		/* RX netbuf array */

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
@interface GNicEnet(Private)

/* Hardware initialization */
- (BOOL)_initChip;
- (void)_resetChip;
- (void)_startChip;
- (BOOL)_allocateMemory;

/* Ring buffer management */
- (BOOL)_initTxRing;
- (BOOL)_initRxRing;

/* Interrupt handling */
- (void)_enableAdapterInterrupts;
- (void)_disableAdapterInterrupts;
- (void)_transmitInterruptOccurred;
- (BOOL)_receiveInterruptOccurred;

/* Transmit operations */
- (void)_transmitPacket:(netbuf_t)packet;
- (void)_sendPacket:(void *)pkt length:(unsigned int)len;
- (void)_sendDummyPacket;
- (void)_stopTransmitDMA;
- (void)_restartTransmitter;

/* Receive operations */
- (void)_receivePacket:(void *)pkt length:(unsigned int *)len timeout:(unsigned int)timeout;
- (BOOL)_receivePackets:(BOOL)freeRun;
- (void)_stopReceiveDMA;
- (void)_restartReceiver;

/* Multicast operations */
- (void)_addMulticastAddress:(enet_addr_t *)address;
- (void)_removeMulticastAddress:(enet_addr_t *)address;
- (BOOL)_findMulticastAddress:(enet_addr_t *)address Index:(unsigned int *)index;

/* Utilities */
- (void)_getStationAddress:(enet_addr_t *)addr;
- (BOOL)_updateDescriptorFromNetBuf:(netbuf_t)nb Desc:(void *)desc ReceiveFlag:(BOOL)isReceive;
- (void)_monitorLinkStatus;
- (void)_packetToDebugger:(netbuf_t)pkt;

@end
