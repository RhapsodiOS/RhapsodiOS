/*
 * Copyright (c) 1999-2000 Apple Computer, Inc.
 *
 * Hardware definitions for PacketEngines Gigabit Ethernet adapters
 * (Yellowfin and Hamachi chipsets).
 *
 * Based on Linux drivers by Donald Becker and others.
 *
 * HISTORY
 *
 * 7 Oct 2025
 *	Created for RhapsodiOS Project.
 */

#ifndef _PPCGNICHDW_H
#define _PPCGNICHDW_H

/* PCI Vendor/Device IDs */
#define PCI_VENDOR_SYMBIOS		0x1000
#define PCI_VENDOR_PACKET_ENGINES	0x1318

#define PCI_DEVICE_YELLOWFIN		0x0702
#define PCI_DEVICE_HAMACHI		0x0911

/* Default ring sizes */
#define RX_RING_SIZE			64
#define TX_RING_SIZE			64

/* Buffer sizes */
#define PKT_BUF_SZ			1536
#define MAX_FRAME_SIZE			1518

/* Yellowfin Register Offsets */
#define YF_ChipConfig			0x00
#define YF_ChipRev			0x04
#define YF_TxConfig			0x0C
#define YF_RxConfig			0x10
#define YF_IntrStatus			0x14
#define YF_IntrEnb			0x18
#define YF_IntrClear			0x1C
#define YF_RxStatus			0x20
#define YF_TxStatus			0x24
#define YF_HashTbl0			0x30
#define YF_HashTbl1			0x34
#define YF_RxPtr			0x38
#define YF_TxPtr			0x3C
#define YF_TxThreshold			0x40
#define YF_TxPktLen			0x48
#define YF_PauseTmr			0x4C
#define YF_RxDescQIdx			0x50
#define YF_RxDescQPtr			0x54
#define YF_RxDescQLen			0x58
#define YF_TxDescQIdx			0x5C
#define YF_TxDescQPtr			0x60
#define YF_TxDescQLen			0x64
#define YF_RxComplQIdx			0x68
#define YF_RxComplQPtr			0x6C
#define YF_RxComplQLen			0x70
#define YF_TxComplQIdx			0x74
#define YF_TxComplQPtr			0x78
#define YF_TxComplQLen			0x7C
#define YF_MIICmd			0x80
#define YF_MIIData			0x84
#define YF_MIIStatus			0x88

/* Hamachi Register Offsets */
#define HAM_PCIDeviceConfig		0x00
#define HAM_TxCmd			0x80
#define HAM_TxStatus			0x84
#define HAM_TxPtr			0x88
#define HAM_TxThreshold			0x8C
#define HAM_RxCmd			0xC0
#define HAM_RxStatus			0xC4
#define HAM_RxPtr			0xC8
#define HAM_IntrStatus			0x100
#define HAM_IntrEnb			0x104
#define HAM_RxData			0x108
#define HAM_MACConfig1			0x200
#define HAM_MACConfig2			0x204
#define HAM_StationAddr0		0x210
#define HAM_StationAddr1		0x214
#define HAM_ANControl			0x220
#define HAM_ANStatus			0x224

/* Common interrupt bits */
#define INTR_RX_DONE			0x00000001
#define INTR_RX_EARLY			0x00000002
#define INTR_RX_NO_BUF			0x00000004
#define INTR_TX_DONE			0x00000010
#define INTR_TX_IDLE			0x00000020
#define INTR_TX_ABORT			0x00000040
#define INTR_LINK_CHANGE		0x00000100
#define INTR_ABNORMAL_SUMMARY		0x00008000
#define INTR_NORMAL_SUMMARY		0x00010000

/* ChipConfig bits (Yellowfin) */
#define CFG_RESET			0x80000000
#define CFG_MII_ENABLE			0x00000001
#define CFG_FULL_DUPLEX			0x00000002

/* TxConfig bits */
#define TX_ENABLE			0x00000001
#define TX_AUTO_PAD			0x00000010
#define TX_ADD_CRC			0x00000020

/* RxConfig bits */
#define RX_ENABLE			0x00000001
#define RX_ACCEPT_BROADCAST		0x00000010
#define RX_ACCEPT_MULTICAST		0x00000020
#define RX_ACCEPT_ALL_PHYS		0x00000040
#define RX_STRIP_CRC			0x00000080

/* MII/PHY definitions */
#define MII_BMCR			0x00	/* Basic mode control register */
#define MII_BMSR			0x01	/* Basic mode status register */
#define MII_PHYSID1			0x02	/* PHY ID 1 */
#define MII_PHYSID2			0x03	/* PHY ID 2 */
#define MII_ADVERTISE			0x04	/* Advertisement control reg */
#define MII_LPA				0x05	/* Link partner ability reg */

/* MII BMCR bits */
#define BMCR_RESET			0x8000	/* Reset */
#define BMCR_LOOPBACK			0x4000	/* Loopback */
#define BMCR_SPEED100			0x2000	/* Select 100Mbps */
#define BMCR_ANENABLE			0x1000	/* Enable auto negotiation */
#define BMCR_PDOWN			0x0800	/* Power down */
#define BMCR_ISOLATE			0x0400	/* Isolate */
#define BMCR_ANRESTART			0x0200	/* Restart auto negotiation */
#define BMCR_FULLDPLX			0x0100	/* Full duplex */
#define BMCR_SPEED1000			0x0040	/* Select 1000Mbps */

/* MII BMSR bits */
#define BMSR_100FULL			0x4000	/* Can do 100BASE-TX full duplex */
#define BMSR_100HALF			0x2000	/* Can do 100BASE-TX half duplex */
#define BMSR_10FULL			0x1000	/* Can do 10BASE-T full duplex */
#define BMSR_10HALF			0x0800	/* Can do 10BASE-T half duplex */
#define BMSR_ANEGCOMPLETE		0x0020	/* Auto-negotiation complete */
#define BMSR_LSTATUS			0x0004	/* Link status */

/* MII Command bits for Yellowfin */
#define MII_READ_CMD			0x00000000
#define MII_WRITE_CMD			0x00000001
#define MII_START			0x00000002
#define MII_BUSY			0x80000000

/* Descriptor structures */

/* Yellowfin descriptor format */
typedef struct {
    volatile unsigned int	request_cnt;	/* Length and control bits */
    volatile unsigned int	addr;		/* Buffer physical address */
    volatile unsigned int	branch_addr;	/* Next descriptor address */
    volatile unsigned int	result_status;	/* Status after completion */
} yellowfin_desc_t;

/* Hamachi descriptor format */
typedef struct {
    volatile unsigned int	status_n_length;
    volatile unsigned int	addr;
    volatile unsigned int	reserved1;
    volatile unsigned int	reserved2;
} hamachi_desc_t;

/* Descriptor status bits */
#define DESC_OWN			0x80000000	/* Owned by NIC */
#define DESC_END_PACKET			0x40000000	/* End of packet */
#define DESC_INTR			0x20000000	/* Generate interrupt */

/* Status bits */
#define RX_STATUS_OK			0x00000001
#define RX_STATUS_CRC_ERROR		0x00000002
#define RX_STATUS_LONG_ERROR		0x00000004
#define RX_STATUS_RUNT_ERROR		0x00000008

#define TX_STATUS_OK			0x00000001
#define TX_STATUS_UNDERFLOW		0x00000002
#define TX_STATUS_LATE_COLL		0x00000004
#define TX_STATUS_ABORT			0x00000008

#endif /* _PPCGNICHDW_H */
