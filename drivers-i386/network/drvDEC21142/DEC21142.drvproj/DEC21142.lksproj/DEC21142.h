/*
 * DEC21142.h
 * DEC Celebris On-Board 21142 LAN Network Driver
 */

#import <driverkit/IONetworkDeviceDescription.h>
#import <driverkit/IOPCIDeviceDescription.h>
#import <driverkit/IOEthernetDriver.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@class DEC21142KernelServerInstance;

/* CSR (Control/Status Register) Numbers */
#define CSR0_BUS_MODE           0
#define CSR1_TX_POLL_DEMAND     1
#define CSR2_RX_POLL_DEMAND     2
#define CSR3_RX_LIST_BASE       3
#define CSR4_TX_LIST_BASE       4
#define CSR5_STATUS             5
#define CSR6_OPERATION_MODE     6
#define CSR7_INTERRUPT_ENABLE   7
#define CSR8_MISSED_FRAMES      8
#define CSR9_BOOT_ROM_MII_MGMT  9
#define CSR11_TIMER             11
#define CSR12_GP_PORT           12
#define CSR13_SIA_STATUS        13
#define CSR14_SIA_CONNECTIVITY  14
#define CSR15_SIA_TX_RX         15

/* CSR0 - Bus Mode Register */
#define CSR0_SOFTWARE_RESET     0x00000001
#define CSR0_BUS_ARBITRATION    0x00000002
#define CSR0_CACHE_ALIGNMENT    0x0000FF00

/* CSR5 - Status Register */
#define CSR5_TX_INTERRUPT       0x00000001
#define CSR5_TX_STOPPED         0x00000002
#define CSR5_TX_BUFFER_UNAVAIL  0x00000004
#define CSR5_TX_JABBER_TIMEOUT  0x00000008
#define CSR5_LINK_PASS          0x00000010
#define CSR5_TX_UNDERFLOW       0x00000020
#define CSR5_RX_INTERRUPT       0x00000040
#define CSR5_RX_UNAVAIL         0x00000080
#define CSR5_RX_STOPPED         0x00000100
#define CSR5_RX_WATCHDOG        0x00000200
#define CSR5_EARLY_TX           0x00000400
#define CSR5_GP_TIMER_EXPIRED   0x00000800
#define CSR5_LINK_FAIL          0x00001000
#define CSR5_SYSTEM_ERROR       0x00002000
#define CSR5_ABNORMAL_INT       0x00008000
#define CSR5_NORMAL_INT         0x00010000
#define CSR5_RX_STATE           0x000E0000
#define CSR5_TX_STATE           0x00700000
#define CSR5_ERROR_BITS         0x03800000

/* CSR6 - Operation Mode Register */
#define CSR6_HP                 0x00000001
#define CSR6_START_RX           0x00000002
#define CSR6_HASH_ONLY_FILTER   0x00000004
#define CSR6_HASH_PERFECT_RX    0x00000080
#define CSR6_PROMISCUOUS        0x00000040
#define CSR6_PASS_ALL_MULTICAST 0x00000080
#define CSR6_INVERSE_FILTER     0x00000100
#define CSR6_FULL_DUPLEX        0x00000200
#define CSR6_OPERATING_MODE     0x00000C00
#define CSR6_FORCE_COLLISION    0x00001000
#define CSR6_START_TX           0x00002000
#define CSR6_THRESHOLD_CONTROL  0x0000C000
#define CSR6_CAPTURE_EFFECT     0x00020000
#define CSR6_PORT_SELECT        0x00040000
#define CSR6_HEARTBEAT_DISABLE  0x00080000
#define CSR6_STORE_AND_FORWARD  0x00200000
#define CSR6_TX_THRESHOLD_MODE  0x00400000
#define CSR6_PCS_FUNCTION       0x00800000
#define CSR6_SCRAMBLER_MODE     0x01000000
#define CSR6_MBO                0x02000000

/* CSR7 - Interrupt Enable Register */
#define CSR7_TX_INTERRUPT       0x00000001
#define CSR7_TX_STOPPED         0x00000002
#define CSR7_TX_BUFFER_UNAVAIL  0x00000004
#define CSR7_TX_JABBER_TIMEOUT  0x00000008
#define CSR7_LINK_PASS          0x00000010
#define CSR7_TX_UNDERFLOW       0x00000020
#define CSR7_RX_INTERRUPT       0x00000040
#define CSR7_RX_UNAVAIL         0x00000080
#define CSR7_RX_STOPPED         0x00000100
#define CSR7_RX_WATCHDOG        0x00000200
#define CSR7_EARLY_TX           0x00000400
#define CSR7_GP_TIMER_EXPIRED   0x00000800
#define CSR7_LINK_FAIL          0x00001000
#define CSR7_SYSTEM_ERROR       0x00002000
#define CSR7_ABNORMAL_INT       0x00008000
#define CSR7_NORMAL_INT         0x00010000

/* CSR9 - Serial ROM / MII Management Register */
#define CSR9_SROM_DATA_IN       0x00000001
#define CSR9_SROM_DATA_OUT      0x00000002
#define CSR9_SROM_CLOCK         0x00000004
#define CSR9_SROM_CHIP_SELECT   0x00000008
#define CSR9_MII_MANAGEMENT     0x00000010
#define CSR9_MII_DATA_OUT       0x00020000
#define CSR9_MII_DATA_IN        0x00080000

/* Descriptor Bits */
#define DESC_OWN                0x80000000  /* Ownership bit */
#define DESC_ES                 0x00008000  /* Error summary */

/* Receive Descriptor Bits (RDES0) */
#define RDES0_OWN               0x80000000
#define RDES0_FRAME_LENGTH      0x3FFF0000
#define RDES0_ERROR_SUMMARY     0x00008000
#define RDES0_DESCRIPTOR_ERROR  0x00004000
#define RDES0_LENGTH_ERROR      0x00001000
#define RDES0_OVERFLOW          0x00000800
#define RDES0_FIRST_DESCRIPTOR  0x00000200
#define RDES0_LAST_DESCRIPTOR   0x00000100
#define RDES0_MULTICAST_FRAME   0x00000080
#define RDES0_RUNT_FRAME        0x00000040
#define RDES0_FRAME_TOO_LONG    0x00000020
#define RDES0_COLLISION_SEEN    0x00000010
#define RDES0_FRAME_TYPE        0x00000008
#define RDES0_MII_ERROR         0x00000004
#define RDES0_DRIBBLING_BIT     0x00000002
#define RDES0_CRC_ERROR         0x00000001

/* Receive Descriptor Bits (RDES1) */
#define RDES1_END_OF_RING       0x02000000
#define RDES1_BUFFER_SIZE_MASK  0x000007FF

/* Transmit Descriptor Bits (TDES0) */
#define TDES0_OWN               0x80000000
#define TDES0_ERROR_SUMMARY     0x00008000
#define TDES0_UNDERFLOW_ERROR   0x00000002
#define TDES0_DEFERRED          0x00000001

/* Transmit Descriptor Bits (TDES1) */
#define TDES1_INTERRUPT_ON_COMPLETION   0x80000000
#define TDES1_LAST_SEGMENT              0x40000000
#define TDES1_FIRST_SEGMENT             0x20000000
#define TDES1_FILTERING_TYPE            0x10000000
#define TDES1_SETUP_PACKET              0x08000000
#define TDES1_ADD_CRC_DISABLE           0x04000000
#define TDES1_END_OF_RING               0x02000000
#define TDES1_BUFFER_SIZE_MASK          0x000007FF

/* Ring Sizes */
#define RX_RING_SIZE            64
#define TX_RING_SIZE            32

/* Transmit Queue Parameters */
#define TX_QUEUE_MAX_SIZE       128
#define TX_INTERRUPT_FREQUENCY  16  /* Generate interrupt every N packets */

/* SROM Parameters */
#define SROM_SIZE               128
#define SROM_ADDR_LENGTH        6
#define SROM_READ_CMD           0x06
#define SROM_DELAY_USEC         2

/* Media Types */
#define MEDIA_10BASET           0
#define MEDIA_AUI               1
#define MEDIA_BNC               2
#define MEDIA_MII               3

/* Setup Frame Parameters */
#define SETUP_FRAME_SIZE        192
#define SETUP_FRAME_PERFECT_ADDRS   16

@interface DEC21142 : IOEthernetDriver
{
    /* Descriptor rings */
    void *rxDescriptors;              /* RX descriptor ring base */
    void *txDescriptors;              /* TX descriptor ring base */
    void *setupFrame;                 /* Setup frame buffer */
    unsigned int rxIndex;             /* Current RX descriptor index */

    /* Instance state flags */
    BOOL isRunning;                   /* Adapter running state */
    BOOL isPromiscuous;               /* Promiscuous mode enabled */
    BOOL isMulticast;                 /* Multicast mode enabled */
    BOOL isDebugger;                  /* Debugger/polling mode active */

    /* Synchronization */
    void *lock;                       /* Transmit lock */

    /* Transmit management */
    netbuf_t txNetbufArray[TX_RING_SIZE];   /* TX netbuf pointers */
    unsigned int txHead;              /* TX ring head index */
    unsigned int txTail;              /* TX ring tail index */
    unsigned int txCount;             /* Available TX descriptors */
    unsigned int txInterruptCounter;  /* Packet counter for interrupt coalescing */
    void *txQueue;                    /* Transmit queue */
    netbuf_t txTempNetbuf;            /* Temporary netbuf for polling mode */

    /* Receive management */
    netbuf_t rxNetbufArray[RX_RING_SIZE];   /* RX netbuf pointers */

    /* Hardware state */
    unsigned int interruptMask;       /* CSR7 interrupt mask */
    unsigned int csr6Value;           /* Cached CSR6 value */
    unsigned int mediaSelection;      /* Selected media type */
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance Methods - Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;

/* Hardware Access Methods */
- (unsigned int)readCSR:(unsigned int)reg;
- (void)writeCSR:(unsigned int)reg value:(unsigned int)value;

/* Address Management */
- (BOOL)addMulticastAddress:(enet_addr_t *)address;
- (BOOL)removeMulticastAddress:(enet_addr_t *)address;

/* Promiscuous and Multicast Mode Control */
- (void)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (void)enableMulticastMode;
- (void)disableMulticastMode;

/* Interrupt Management */
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (unsigned int)transmitQueueSize;
- (unsigned int)transmitQueueCount;
- (void)serviceTransmitQueue;
- (unsigned int)pendingTransmitCount;

/* Receive Methods */
- (netbuf_t)allocateNetbuf;

/* Debugger Support (Polling Mode) */
- (void)sendPacket:(void *)data length:(unsigned int)length;
- (BOOL)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;

/* Port Selection Methods */
- (void)select10BaseT;
- (void)selectAUI;
- (void)selectBNC;
- (void)selectMII;
- (void)doAutoPortSelect;

/* MII Management */
- (BOOL)checkMII;

/* Power Management */
- (IOReturn)getPowerState;
- (IOReturn)getPowerManagement;
- (IOReturn)setPowerState:(unsigned int)powerState;
- (IOReturn)setPowerManagement:(unsigned int)powerLevel;

/* Private Methods - Internal Implementation */
- (BOOL)_init;
- (BOOL)_allocateMemory;
- (void)_getStationAddress:(unsigned char *)address;
- (void)_initRegisters;
- (void)_initRxRing;
- (void)_initTxRing;
- (void)_resetChip;
- (void)_loadSetupFilter;
- (void)_setAddressFiltering;
- (void)_startReceive;
- (void)_startTransmit;
- (void)_receiveInterruptOccurred;
- (void)_transmitInterruptOccurred;
- (BOOL)_transmitPacket:(netbuf_t)packet;
- (BOOL)_verifyCheckSum:(unsigned char *)data length:(unsigned int)length;

@end
