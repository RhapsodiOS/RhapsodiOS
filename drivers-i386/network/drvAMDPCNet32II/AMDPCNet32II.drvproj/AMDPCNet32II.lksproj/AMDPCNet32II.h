#import <bsd/net/etherdefs.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetwork.h>
#import <driverkit/align.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

#define NETWORK_TIMEOUT 3000

@interface AMDPCNet32II : IOEthernet {

  /* Mac address */
  enet_addr_t myAddress;
  IONetwork *network;
  id transmitQueue;

  IOEISAPortAddress base;
  IORange port;
  int irq;
  int ioBase;

  int rx_buffer_ptr;
  int tx_buffer_ptr;

  char *rdes;
  char *tdes;

  unsigned int rdes_physical;
  unsigned int tdes_physical;

  char *rx_buffers;
  char *tx_buffers;

  unsigned int rx_buffers_physical;
  unsigned int tx_buffers_physical;

  char *initBlock;
  unsigned int initBlockPhysical;

  int receiveInterruptCount;
  int transmitInterruptCount;
  int bothInterruptCount;

  BOOL isMulticastMode;

}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

- (void)transmit:(netbuf_t)pkt;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;
- (void)interruptOccurred;
- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;

- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;

/* TODO Features */
/*
- (void)addMulticastAddress:(enet_addr_t *) address;
- (void)removeMulticastAddress:(enet_addr_t *) address;
*/

- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;

- (void)resetCard;
- (void)configureCard;
- (void)initRingBuffers;
- (void)setupInitBlock;
- (void)configureInterrupts;
- (void)writeRAP32:(long)val;
- (void)writeCSR32:(long)csr_no:(long)val;
- (long)readCSR32:(long)csr_no;
- (void)writeBCR32:(long)bcr_no:(long)val;
- (long)readBCR32:(long)bcr_no;

@end