/* GemEnet.h - PowerPC Gem Ethernet Driver */

#import <driverkit/IOEthernet.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/ppc/directDevice.h>

@interface GemEnet : IOEthernet
{
    /* Layout and names from the stock drvPPCGem_reloc ivar list */
    void		*ioBaseEnet;		/* 0x174 */
    enet_addr_t		myAddress;		/* 0x178 */
    IONetwork		*networkInterface;	/* 0x180 */
    IONetbufQueue	*transmitQueue;		/* 0x184 */
    BOOL		isPromiscuous;		/* 0x188 */
    BOOL		multicastEnabled;	/* 0x189 */
    BOOL		resetAndEnabled;	/* 0x18a */
    unsigned int	enetAddressOffset;	/* 0x18c */
    unsigned char	phyId;			/* 0x190 */
    unsigned char	sromAddressBits;	/* 0x191 */
    unsigned short	phyStatusPrev;		/* 0x192 */
    netbuf_t		txNetbuf[128];		/* 0x194 */
    netbuf_t		rxNetbuf[128];		/* 0x394 */
    unsigned int	txCommandHead;		/* 0x594 */
    unsigned int	txCommandTail;		/* 0x598 */
    unsigned int	txMaxCommand;		/* 0x59c */
    unsigned int	rxCommandHead;		/* 0x5a0 */
    unsigned int	rxCommandTail;		/* 0x5a4 */
    unsigned int	rxMaxCommand;		/* 0x5a8 */
    void		*dmaCommands;		/* 0x5ac */
    void		*txDMACommands;		/* 0x5b0 */
    unsigned int	txDMACommandsPhys;	/* 0x5b4 */
    void		*rxDMACommands;		/* 0x5b8 */
    unsigned int	rxDMACommandsPhys;	/* 0x5bc */
    unsigned int	txWDInterrupts;		/* 0x5c0 */
    unsigned int	txWDCount;		/* 0x5c4 */
    void		*debuggerPkt;		/* 0x5c8 */
    unsigned int	debuggerPktSize;	/* 0x5cc */
    unsigned short	hashTableUseCount[256];	/* 0x5d0 */
    unsigned short	hashTableMask[16];	/* 0x7d0 */
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
- (BOOL)_transmitInterruptOccurred;
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
