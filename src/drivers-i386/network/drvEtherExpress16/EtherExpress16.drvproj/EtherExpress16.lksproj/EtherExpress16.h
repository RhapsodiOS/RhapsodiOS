/*
 * EtherExpress16.h
 * Intel EtherExpress 16 Network Driver
 */

#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>

/* Connector types */
#define CONNECTOR_AUI          0         /* AUI (Attachment Unit Interface) */
#define CONNECTOR_BNC          1         /* BNC (10Base2 coaxial) */
#define CONNECTOR_RJ45         2         /* RJ-45 (10Base-T twisted pair) */

/* Magic values for descriptor validation */
#define RBD_MAGIC              0xBD42    /* Receive Buffer Descriptor magic */
#define RFD_MAGIC              0x0D02    /* Receive Frame Descriptor magic */

/* i82586 System Configuration Pointer address */
#define SCP_ADDRESS            0xFFF6    /* Fixed SCP location in adapter memory */

/* EtherExpress 16 ID value */
#define EE16_ID_VALUE          0xBABA    /* Adapter ID read from port+0x0F */

/* i82586 Command codes */
#define CMD_NOP                0x0000    /* No operation */
#define CMD_IA_SETUP           0x0001    /* Individual Address Setup */
#define CMD_CONFIGURE          0x0002    /* Configure */
#define CMD_MC_SETUP           0x0003    /* Multicast Setup */
#define CMD_TRANSMIT           0x0004    /* Transmit */
#define CMD_TDR                0x0005    /* Time Domain Reflectometry */
#define CMD_DUMP               0x0006    /* Dump */
#define CMD_DIAGNOSE           0x0007    /* Diagnose */

/* Memory region structure */
typedef struct {
    unsigned short start;
    unsigned short size;
} mem_region_t;

/* The 14-byte Ethernet header is read from the RFD data area. */
typedef struct {
    unsigned char bytes[16];
} recv_hdr_t;

@interface EtherExpress16 : IOEthernet
{
    unsigned short base;
    int irq;
    enet_addr_t myAddress;
    IONetwork *network;
    struct { int val[14]; } resetLabel;
    unsigned short boardID;
    int interfaceConnector;
    int boardType;
    id xmtQueue;
    char xmtActive;
    char promiscuousEnabled;
    char multicastEnabled;
    char multicastConfigured;
    unsigned short membase;
    unsigned int memused;
    unsigned short scb_off;
    unsigned short frf_off;
    unsigned short lrf_off;
    unsigned short frb_off;
    unsigned short lrb_off;
    unsigned short tcb_off;
    unsigned short tbd_off;
    unsigned short tbuf_off;
}

/* Class Methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance Methods - Initialization */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)free;

/* Configuration Methods */
- (BOOL)config;
- (BOOL)getIntValues:(unsigned int *)parameterArray
        forParameter:(IOParameterName)parameterName
               count:(unsigned int *)count;

/* Hardware Initialization */
- (void)hwInit:(BOOL)reset;
- (void)swInit;

/* Promiscuous and Multicast Mode Control */
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

/* Interrupt Management */
- (void)interruptOccurred;
- (void)timeoutOccurred;

/* Interrupt Control */
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;

/* Transmit Methods */
- (void)transmit:(netbuf_t)packet;
- (void)sendPacket:(void *)data length:(unsigned int)len;

/* Receive Methods */
- (void)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout;

/* Memory Management */
- (unsigned short)memAlloc:(unsigned int)size;
- (unsigned int)memAvail;
- (unsigned short)memRegion:(unsigned int)size;

/* Command Block List Operations */
- (void)performCBL:(unsigned short)addr;
- (void)abortCBL;

/* Receive Operations */
- (void)recvInit;
- (void)recvStart;
- (void)recvRestart;
- (void)recvFrame:(unsigned short)frameOffset hdr:(recv_hdr_t *)hdr ok:(BOOL)status;

/* Interrupt Handlers */
- (void)cxIntr;
- (void)frIntr;

@end

/* Private Category - Internal Implementation */
@interface EtherExpress16(EtherExpress16Private)
- (id)_configEE16:(BOOL)doConfig;
- (id)_resetEE16:(BOOL)enable;
- (void)_configureMulticastAddresses;
- (BOOL)ia_setup;
- (void)xmtInit;
@end

/* Kernel Server Instance */
@interface EtherExpress16KernelServerInstance : Object
+ (id)kernelServerInstance;
@end

/* Version Information */
@interface EtherExpress16Version : Object
+ (const char *)driverKitVersionForEtherExpress16;
@end
