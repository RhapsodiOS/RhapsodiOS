/*
 * PCI config typedefs.
 */
 
#define PCI_NUM_BASE_ADDRESS	6

/*
 * Status word as bitfields.
 */
typedef struct {
	unsigned short	rsvd1:6,
			fastBtb:1,		// fast back-to-back
			dataParity:1,
			devSelTiming:2,
			sigTargetAbort:1,
			rcvTargetAbort:1,
			rcvMasterAbort:1,
			sigSystemError:1,
			detParityError:1;
} pciStatusBits;

/*
 * For looking at status as either bitfields or a word. 
 */
typedef union {
	pciStatusBits 	bits;
	unsigned short	word;
} pciConfStatus;

/*
 * PCI configuration header struct, "software" view.
 */
typedef struct {
	unsigned short	deviceId;
	unsigned short	vendorId;
	pciConfStatus	status;		
	unsigned short	command;	
	unsigned	revId:8,
			classApi:8,
			subclass:8,
			classCode:8;
	unsigned char	bist;
	unsigned char	headerType;
	unsigned char 	latencyTimer;
	unsigned char	cacheLineSize;
	unsigned	baseAddress[PCI_NUM_BASE_ADDRESS];
	unsigned	baseAddressExp0;
	unsigned	baseAddressExp1;
	unsigned	expansionRomBase;
	unsigned	rsvd1;
	unsigned	rsvd2;
	unsigned char	maxLat;
	unsigned char	minGnt;
	unsigned char	intrPin;
	unsigned char	intrLine;
} pciConfHeader;

/*
 * Individual registers indices, the "hardware" view.
 */
#define PCI_DEV_AND_VENDOR_ID		0
#define PCI_DEV_ID(reg)			((reg & 0xffff0000) >> 16)
#define PCI_VENDOR_ID(reg)		 (reg &	0x0000ffff)

#define PCI_STATUS_AND_COMMAND		1
#define PCI_STATUS(reg)			((reg & 0xffff0000) >> 16)
#define PCI_COMMAND(reg)		 (reg &	0x0000ffff)

#define PCI_CLASS_AND_REV		2
#define PCI_CLASS_CODE(reg)		((reg & 0xff000000) >> 24)
#define PCI_SUBCLASS(reg)		((reg & 0x00ff0000) >> 16)
#define PCI_CLASS_API(reg)		((reg & 0x0000ff00) >> 8)
#define PCI_REV_ID(reg)			 (reg &	0x000000ff)

#define	PCI_BIST_HDR_LAT_LS		3
#define PCI_BIST(reg)			((reg & 0xff000000) >> 24)
#define PCI_HDR_TYPE(reg)		((reg & 0x00ff0000) >> 16)
#define PCI_LATENCY(reg)		((reg & 0x0000ff00) >> 8)
#define PCI_CACHE_LINE_SIZE(reg)	 (reg & 0x000000ff)

#define PCI_BASE_ADDRESS_0		4
#define PCI_BASE_ADDRESS_1		5
#define PCI_BASE_ADDRESS_2		6
#define PCI_BASE_ADDRESS_3		7
#define PCI_BASE_ADDRESS_4		8
#define PCI_BASE_ADDRESS_5		9
#define PCI_BASE_ADDRESS_EXP0		0xa
#define PCI_BASE_ADDRESS_EXP1		0xb
#define PCI_ROM_BASE_ADDRESS		0xc
#define PCI_RSVD1			0xd
#define PCI_RSVD2			0xe

#define PCI_BUS_AND_INTR		0xf
#define PCI_MAX_LAT(reg)		((reg & 0xff000000) >> 24)
#define PCI_MAX_GNT(reg)		((reg & 0x00ff0000) >> 16)
#define PCI_INTR_PIN(reg)		((reg & 0x0000ff00) >> 8)
#define PCI_INTR_LINE(reg)		 (reg & 0x000000ff)

#define PCI_BUS_AND_INTR_REG(lat, gnt, pin, line) 	\
	((lat << 24) | (gnt << 16) | (pin << 8) | line)

/*
 * Command register bits. 
 */
#define PCI_COMMAND_IO_ENABLE		0x0001
#define PCI_COMMAND_MEM_ENABLE		0x0002
#define PCI_COMMAND_MASTER_ENABLE	0x0004
#define PCI_COMMAND_SPECIAL		0x0008
#define PCI_COMMAND_MWI			0x0010
#define PCI_COMMAND_PALETTE_SNOOP	0x0020
#define PCI_COMMAND_PARITY_ERROR	0x0040
#define PCI_COMMAND_WAIT_ENABLE		0x0080
#define PCI_COMMAND_SYSTEM_ERR		0x0100
#define PCI_COMMAND_FAST_BTB		0x0200

/*
 * headerType bits.
 */
#define HEADER_TYPE_MULTI_FCN	0x80	/* 1 --> multifunction */

/*
 * bist (built in self test) bits.
 */
#define PCI_BIST_CAPABLE	0x80
#define PCI_BIST_START		0x40
#define PCI_BIST_CODE_MASK	0x0f
/*
 * Limits.
 */
/* #define PCI_NUM_BUSSES		256 */
#define PCI_NUM_BUSSES		1	/* for now... */
#define PCI_NUM_DEVICES_1	32	/* per bus, method 1 */
#define PCI_NUM_DEVICES_2	16	/* per bus, method 2 */
#define PCI_NUM_FUNCTIONS	8	/* per target */

/*
 * Vendor ID meaning "no device here".
 */
#define VENDOR_ID_NONE	0xffff

/*
 * Class codes.
 */
#define PCI_CLASS_OLD		0
#define PCI_CLASS_MASS_STORAGE	1
#define PCI_CLASS_NETWORK	2
#define PCI_CLASS_DISPLAY	3
#define PCI_CLASS_MULTIMEDIA	4
#define PCI_CLASS_MEMORY	5
#define PCI_CLASS_BRIDGE	6
#define PCI_CLASS_OTHER		0xff

/*
 * Subclass codes.
 */
 
#define PCI_SUBCLASS0_NON_VGA	0x00
#define PCI_SUBCLASS0_VGA	0x01

#define PCI_SUBCLASS1_SCSI	0x00
#define PCI_SUBCLASS1_IDE	0x01
#define PCI_SUBCLASS1_FLOPPY	0x02
#define PCI_SUBCLASS1_IPI	0x03
#define PCI_SUBCLASS1_OTHER	0x80

#define PCI_SUBCLASS2_ENET	0x00
#define PCI_SUBCLASS2_TR	0x01
#define PCI_SUBCLASS2_FDDI	0x02
#define PCI_SUBCLASS2_OTHER	0x80

#define PCI_SUBCLASS3_VGA	0x00
#define PCI_SUBCLASS3_XGA	0x01
#define PCI_SUBCLASS3_OTHER	0x80

#define PCI_SUBCLASS4_VIDEO	0x00
#define PCI_SUBCLASS4_AUDIO	0x01
#define PCI_SUBCLASS4_OTHER	0x02

#define PCI_SUBCLASS5_RAM	0x00
#define PCI_SUBCLASS5_FLASH	0x01
#define PCI_SUBCLASS5_OTHER	0x80

#define PCI_SUBCLASS6_HOST_PCI	0x00
#define PCI_SUBCLASS6_PCI_ISA	0x01
#define PCI_SUBCLASS6_PCI_EISA	0x02
#define PCI_SUBCLASS6_PCI_MICRO	0x03
#define PCI_SUBCLASS6_PCI_PCI	0x04
#define PCI_SUBCLASS6_PCI_MCIA	0x05
#define PCI_SUBCLASS6_OTHER	0x80

/* 
 * Constants for parsing base address registers.
 */
#define PCI_BASE_IO_BIT		0x01
#define PCI_BASE_PREFETCHABLE	0x08
#define PCI_BASE_MEM_TYPE	0x06
#define PCI_BASE_IO(value)	(value & 0xfffffffc)
#define PCI_BASE_MEMORY(value)	(value & 0xfffffff0)
#define PCI_MEM_TYPE_ANY_32	0x00
#define PCI_MEM_TYPE_LOW_1MEG	0x02
#define PCI_MEM_TYPE_ANY_64	0x04

/*
 * The actual ports we read and write to get all of the above using 
 * Configuration mechanism 1.
 */
#define PCI_CONF_ADDRS_PORT	0xcf8
#define PCI_CONF_DATA_PORT	0xcfc

/*
 * Ports and constants used for Configuration mechanism 2.
 *
 * FIXME - what is the width of PCI_FORWARD_PORT?
 */
#define PCI_CSE_PORT		0xcf8	/* Configuration Space Enable */
					/*    (8-bit) */
#define PCI_FORWARD_PORT	0xcfa	/* basically, the bus number */
#define PCI_CONFIG_BASE		0xc000	/* base of mapped device register */
					/*    space */

/*
 * Fields in PCI_CSE_PORT
 */
#define PCI_CSE_SPECIAL		0x01
#define PCI_CSE_KEY_MAP		0xf0
#define PCI_CSE_KEY_NORMAL	0x00

