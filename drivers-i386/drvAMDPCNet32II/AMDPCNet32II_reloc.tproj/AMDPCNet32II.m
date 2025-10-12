/*
 * AMDPCNet32II -- driver for AMD PCNet32 II PCI Ethernet controller
 * Created by Austin Wells 01/11/2021
 *
 * Special thanks to Gabor Sebestyen for his NE2K drivers
 * which I used as a reference for this driver
 */

#import <driverkit/IONetbufQueue.h>
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
#import <bsd/net/etherdefs.h>

#import "AMDPCNet32II.h"
#import "PCNetIO.h"

#define DESCRIPTOR_SIZE 16
#define BUFFER_SIZE 1520

#define RX_BUFFER_COUNT 32
#define TX_BUFFER_COUNT 128

BOOL driverOwns(char *des, int idx) {
  // Check if the ownership bit is clear
  if ((des[DESCRIPTOR_SIZE * idx + 7] & 0x80) == 0)
    return YES;
  return NO;
}

void initDE(char *des, int idx, unsigned int buf, int is_tx) {

  unsigned short bcnt;

  bzero(&(des[idx * DESCRIPTOR_SIZE]), DESCRIPTOR_SIZE);

  *(long *)&(des[idx * DESCRIPTOR_SIZE]) = buf + idx * BUFFER_SIZE;

  bcnt = (unsigned char)(-BUFFER_SIZE);
  bcnt &= 0x0FFF;
  bcnt |= 0xF000;
  *(unsigned short *)&(des[idx * DESCRIPTOR_SIZE + 4]) = bcnt;

  if (!is_tx) {
    des[idx * DESCRIPTOR_SIZE + 7] = 0x80;
  } else {
    des[idx * DESCRIPTOR_SIZE + 7] = 0x00;
  }
}

@implementation AMDPCNet32II

+ (BOOL)probe:deviceDescription {
  AMDPCNet32II *driver = [self alloc];

  IOLog("AMDPCNet32II: Driver: %p\n", driver);
  IOLog("By Austin Wells\n");

  if ([driver initFromDeviceDescription:deviceDescription] != nil) {
    return YES;
  } else {
    IOLog("AMDPCNet32II: Failed to initialize driver\n");
    // do we need to free?
    [driver free];
    return NO;
  }
}

- (void)writeRAP16:(int)val {
  outw(ioBase + RAP16, val);
  inw(ioBase + RAP16);
}

- (void)writeRAP32:(long)val {
  outl(ioBase + RAP32, val);
  inl(ioBase + RAP32);
}

- (int)readRAP16:(int)csr_no {
  [self writeRAP16:csr_no];
  return inw(ioBase + RDP16);
}

- (long)readRAP32:(long)csr_no {
  [self writeRAP32:csr_no];
  return inl(ioBase + RDP32);
}

- (void)writeCSR16:(int)csr_no:(int)val {
  [self writeRAP16:csr_no];
  outw(ioBase + RDP16, val);
}

- (void)writeCSR32:(long)csr_no:(long)val {
  [self writeRAP32:csr_no];
  outl(ioBase + RDP32, val);
}

- (int)readCSR16:(int)csr_no {
  [self writeRAP16:csr_no];
  return inw(ioBase + RDP16);
}

- (long)readCSR32:(long)csr_no {
  [self writeRAP32:csr_no];
  return inl(ioBase + RDP32);
}

- (void)writeBCR16:(int)bcr_no:(int)val {
  [self writeRAP16:bcr_no];
  outw(ioBase + BDP16, val);
}

- (void)writeBCR32:(long)bcr_no:(long)val {
  [self writeRAP32:bcr_no];
  outl(ioBase + BDP32, val);
}

- (int)readBCR16:(int)bcr_no {
  [self writeRAP16:bcr_no];
  return inw(ioBase + BDP16);
}

- (long)readBCR32:(long)bcr_no {
  [self writeRAP32:bcr_no];
  return inl(ioBase + BDP32);
}

- (void)resetCard {
  ns_time_t start, end;
  IOLog("AMDPCNet32II: Resetting Card\n");
  inl(ioBase + 0x18);
  inw(ioBase + 0x14);
  outl(ioBase + 0x10, 0);

  IOLog("AMDPCNet32II: starting card");
  IOGetTimestamp(&start);
  while (1) {
    IOGetTimestamp(&end);
    IOLog(".");
    if ((end - start) > 10000)
      break;
  }
  IOLog("\n");
  IOLog("AMDPCNet32II: Card Reset\n");

  rx_buffer_ptr = 0;
  tx_buffer_ptr = 0;
}

- (void)configureCard {

  long bcr2;
  long csr58;

  /* SWSTYLE = 2 (32-bit mode) */
  csr58 = [self readCSR32:LANCE_CSR58];
  csr58 &= 0xFF00;
  csr58 |= 0x02;
  [self writeCSR32:LANCE_CSR58:csr58];

  /* enable ASEL mode */
  bcr2 = [self readBCR32:LANCE_BCR2];
  bcr2 |= 0x2;
  [self writeBCR32:LANCE_BCR2:bcr2];
}

- (void)initRingBuffers {

  int i;

  rx_buffer_ptr = 0;
  tx_buffer_ptr = 0;

  rdes = IOMalloc(RX_BUFFER_COUNT * DESCRIPTOR_SIZE);
  tdes = IOMalloc(TX_BUFFER_COUNT * DESCRIPTOR_SIZE);

  if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rdes,
                            &rdes_physical) != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get physical address of rdes\n");
  }

  if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)tdes,
                            &tdes_physical) != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get physical address of tdes\n");
  }

  rx_buffers = IOMalloc(RX_BUFFER_COUNT * BUFFER_SIZE);
  tx_buffers = IOMalloc(TX_BUFFER_COUNT * BUFFER_SIZE);

  if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rx_buffers,
                            &rx_buffers_physical) != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get physical address of rx buffers\n");
  }

  if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)tx_buffers,
                            &tx_buffers_physical) != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get physical address of tx buffers\n");
  }

  for (i = 0; i < RX_BUFFER_COUNT; i++) {
    initDE(rdes, i, rx_buffers_physical, 0);
  }

  for (i = 0; i < TX_BUFFER_COUNT; i++) {
    initDE(tdes, i, tx_buffers_physical, 1);
  }
}

- (void)setupInitBlock {

  unsigned int alignedAddress;
  int i = 0;

  initBlock = IOMalloc(34);

  // align to the next 4-byte boundary
  alignedAddress = ((unsigned int)initBlock + 3) & ~0x3;
  initBlock = (void *)alignedAddress;

  if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)initBlock,
                            &initBlockPhysical)) {
    IOLog("AMDPCNet32II: Failed to get physical address of initBlock\n");
  }

  initBlock[0] = 0x00;
  initBlock[1] = 0x00;

  initBlock[2] = 0x50; // RLEN = 32
  initBlock[3] = 0x70; // TLEN = 128

  for (i = 0; i < 6; i++) {
    initBlock[4 + i] = ((char *)&myAddress)[i];
  }

  bzero(&(initBlock[12]), 8);

  *(unsigned long *)(&(initBlock[20])) = rdes_physical;
  *(unsigned long *)(&(initBlock[24])) = tdes_physical;

  [self writeCSR32:LANCE_CSR1:initBlockPhysical & 0xFFFF];
  [self writeCSR32:LANCE_CSR2:(initBlockPhysical >> 16) & 0xFFFF];
}

- (void)configureInterrupts {

  unsigned long csr3;

  csr3 = [self readCSR32:LANCE_CSR3];

  [self writeCSR32:LANCE_CSR3:csr3];

  [self writeCSR32:LANCE_CSR3:0x5F50];
  csr3 = [self readCSR32:LANCE_CSR3];

  csr3 &= ~(LANCE_CSR3_RINTM); // enable receive interrupt
  csr3 &= ~(LANCE_CSR3_TINTM); // enable transmit interrupt

  [self writeCSR32:LANCE_CSR3:csr3];
  csr3 = [self readCSR32:LANCE_CSR3];

}

- (void)startCard {

  long csr0;
  [self writeCSR32:LANCE_CSR0:(LANCE_CSR0_INIT | LANCE_CSR0_STRT | LANCE_CSR0_STRT | LANCE_CSR0_RXON | LANCE_CSR0_TXON |
                 LANCE_CSR0_IENA | LANCE_CSR0_TDMD)];

  IOLog("AMDPCNet32II: waiting for card");
  while (!([self readCSR32:LANCE_CSR0] & LANCE_CSR0_IDON)) {
    IOLog(".");
    IOSleep(100);
  }
  IOLog("\nAMDPCNet32II: we're so back!\n");

  csr0 = [self readCSR32:LANCE_CSR0];
  csr0 = csr0 & ~(LANCE_CSR0_INIT | LANCE_CSR0_STOP);
  csr0 = csr0 | (LANCE_CSR0_STRT | LANCE_CSR0_RXON | LANCE_CSR0_TXON |
                 LANCE_CSR0_IENA | LANCE_CSR0_TDMD);
  [self writeCSR32:LANCE_CSR0:csr0];
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription {

  int i;
  unsigned char *mac_addr;
  IOPCIDeviceDescription *pciDeviceDescription =
      (IOPCIDeviceDescription *)deviceDescription;
  IOPCIConfigSpace config;
  unsigned long pciConfig;

  IOLog("AMDPCNet32II: Initializing driver\n");

  if ([IODirectDevice getPCIConfigSpace:&config
                  withDeviceDescription:pciDeviceDescription] != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get PCI config space\n");
    [self free];
    return nil;
  }

  IOLog("AMDPCNet32II: Vendor ID: %x\n", config.VendorID);
  IOLog("AMDPCNet32II: Device ID: %x\n", config.DeviceID);

  irq = (int)config.InterruptLine;
  base = (config.BaseAddress[0]) & 0xffffe;

  port.start = base;
  port.size = 0x20; /* TODO: figure this out */

  IOLog("AMDPCNet32II: IRQ: %d\n", irq);
  IOLog("AMDPCNet32II: Base: %x\n", base);

  if ([IODirectDevice getPCIConfigData:&pciConfig
                            atRegister:0x04
                 withDeviceDescription:pciDeviceDescription] != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Failed to get PCI config data\n");
    [self free];
    return nil;
  }

  pciConfig &= 0xFFFF0000; // clear config bits
  pciConfig |= 0x5;        // set bus mastering

  if ([IODirectDevice setPCIConfigData:pciConfig
                            atRegister:0x4
                 withDeviceDescription:pciDeviceDescription] != IO_R_SUCCESS) {
    IOLog("AMDPCNet32II: Can't set config space, exiting\n");
    [self free];
    return nil;
  }

  /* TODO: update this */
  ioBase = base;

  [deviceDescription setInterruptList:&irq num:1];

  if ([super initFromDeviceDescription:pciDeviceDescription] == nil) {
    IOLog("AMDPCNet32II: Failed to initialize super\n");
    [super free];
    return nil;
  }

  [self resetCard];
  mac_addr = (unsigned char *)&myAddress;
  for (i = 0; i < 6; i++) {
    mac_addr[i] = inb(ioBase + i);
  }

  IOLog("AMDPCNet32II: MAC Adress: %02x:%02x:%02x:%02x:%02x:%02x\n",
        mac_addr[0], mac_addr[1], mac_addr[2], mac_addr[3], mac_addr[4],
        mac_addr[5]);

  [self configureCard];
  [self initRingBuffers];
  [self setupInitBlock];
  [self configureInterrupts];

  [self startCard];

  /* Perform warm-start driver initialization. */
  [self resetAndEnable:NO];

  transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32];

  /* Inform my superclass of my address and cache the id of the
   * IONetwork object it creates for me. myAddress must be set
   * to the hardware address before this call is made. */
  network = [super attachToNetworkWithAddress:myAddress];

  receiveInterruptCount = 0;
  transmitInterruptCount = 0;
  bothInterruptCount = 0;

  isMulticastMode = NO;

  return self;
}

- (BOOL)resetAndEnable:(BOOL)enable {
  [self disableAllInterrupts];

  /* Disable interrupts
   * Clear pending timeouts
   * Initialize hardware settings and software data structures
   * Cache physical addresses
   * Enable running by invoking setRunning:
   * Reenable interrupts if the enable parameter is YES
   */
  if (enable) {
    [self writeCSR32:LANCE_CSR0:(LANCE_CSR0_IENA | LANCE_CSR0_TDMD)];
    [self enableAllInterrupts];
  }

  [self setRunning:enable];
  return YES;
}

- (void)transmit:(netbuf_t)pkt {

  unsigned int len;
  unsigned short bcnt;

  // IOLog("AMDPCNet32II: Transmitting packet (tdes = %d)\n", tx_buffer_ptr);
  /* 1. Queue the frame if it can't be processed immediately.
     2. Perform a software loopback if necessary using performLoopback:.
     3. Transfer the frame to the hardware.
     4. Free the frame's network buffer; you may need to do this in an interrupt
     handler.
     5. Set a timeout.
     6. Handle the transmit interrupt or timeout.
     7. Increment statistics such as number of frames sent, number of timeouts,
     and so on by invoking methods such as incrementOutputPackets in IONetwork.
  */
  if (!driverOwns(tdes, tx_buffer_ptr)) {
    // Queue packet
    [transmitQueue enqueue:pkt];
    return;
  }

  len = nb_size(pkt);
  IOCopyMemory(nb_map(pkt), tx_buffers + tx_buffer_ptr * BUFFER_SIZE, len, 1);

  tdes[tx_buffer_ptr * DESCRIPTOR_SIZE + 7] |= 0x2;
  tdes[tx_buffer_ptr * DESCRIPTOR_SIZE + 7] |= 0x1;

  bcnt = (unsigned short)(-len);
  bcnt &= 0x0FFF;
  bcnt |= 0xF000;

  *(unsigned short *)&(tdes[tx_buffer_ptr * DESCRIPTOR_SIZE + 4]) = bcnt;

  tdes[tx_buffer_ptr * DESCRIPTOR_SIZE + 7] |= 0x80;
  tx_buffer_ptr = (tx_buffer_ptr + 1) % TX_BUFFER_COUNT;

  // this is apparently absolutely neccessary for tramission
  // probably a bug? something must be unsetting this.
  [self writeCSR32:LANCE_CSR0:LANCE_CSR0_TDMD | LANCE_CSR0_IENA];

  // free the packet
  nb_free(pkt);

  [network incrementOutputPackets];
}

- (void)interruptOccurred {
  int i;
  unsigned long status;
  unsigned long writeBack;
  unsigned short status_flags;
  unsigned short mcnt;
  unsigned long startPkt;
  BOOL received;
  BOOL transmitted;

  netbuf_t pkt;

  status = [self readCSR32:LANCE_CSR0];

  received = (status & LANCE_CSR0_RINT) != 0;
  transmitted = (status & LANCE_CSR0_TINT) != 0;

  if (received && transmitted) {
    bothInterruptCount++;
  } else if (received) {
    receiveInterruptCount++;
  } else if (transmitted) {
    transmitInterruptCount++;
  }


  writeBack = 0;
  startPkt = 0;

  if (status & LANCE_CSR0_RINT) {

    i = 0;
    // scan for next availible rdes (maybe this will solve the "lag"?)
    while (!driverOwns(rdes, rx_buffer_ptr)) {
      rx_buffer_ptr = (rx_buffer_ptr + 1) % RX_BUFFER_COUNT;
      if (i == RX_BUFFER_COUNT) {
        break;
      }
      i++;
    }

    while (driverOwns(rdes, rx_buffer_ptr)) {
      status_flags =
          *(unsigned short *)(&(rdes[rx_buffer_ptr * DESCRIPTOR_SIZE + 6]));
      if (status_flags & (1 << 14)) {
        // IOLog("AMDPCNet32II: Error in received packet: %x\n", status_flags);
      }
      if (!(status_flags & (1 << 8)) || !(status_flags & (1 << 9))) {
        // IOLog("AMDPCNet32II: Incomplete Packet %x\n", status_flags);
      }

      mcnt = *(unsigned short *)(&(rdes[rx_buffer_ptr * DESCRIPTOR_SIZE + 8]));
      mcnt &= 0x0FFF;

      if (mcnt > BUFFER_SIZE) {
        // IOLog("AMDPCNet32II: Invalid message byte count %u\n", rx_buffer_ptr);
      }

      pkt = nb_alloc(mcnt);

      if (pkt == NULL) {
        // IOLog("AMDPCNet32II: Could not allocate new packet of size %u\n", mcnt);
      } else {
        nb_write(pkt, 0, mcnt, rx_buffers + rx_buffer_ptr * BUFFER_SIZE);
      }

      // This should handle receiving multicast packets 
      if (isMulticastMode && ([super isUnwantedMulticastPacket:(ether_header_t *)nb_map(pkt)])) {
        IOLog("AMDPCNet32II: Unwanted Multicast Packet\n");  
        nb_free(pkt);
      }
      else {
        [network handleInputPacket:pkt extra:0];
      }

      *(unsigned short *)(&(rdes[rx_buffer_ptr * DESCRIPTOR_SIZE + 6])) = 0;
      *(unsigned short *)(&(rdes[rx_buffer_ptr * DESCRIPTOR_SIZE + 6])) |=
          (1 << 15);

      rx_buffer_ptr = (rx_buffer_ptr + 1) % RX_BUFFER_COUNT;
      startPkt++;
      [network incrementInputPackets];
    }
    writeBack |= LANCE_CSR0_RINT;
  }

  if (status & LANCE_CSR0_IDON) {
    writeBack |= LANCE_CSR0_IDON; 
  }
  if (status & LANCE_CSR0_TINT) {
    while(driverOwns(tdes, tx_buffer_ptr) && ((pkt = [transmitQueue dequeue]) != NULL)) {
        [self transmit:pkt];
    } 
    writeBack |= LANCE_CSR0_TINT;
  }

  // other interrupt flags we don't care about for now
  [self writeCSR32:LANCE_CSR0:0xf800 | writeBack | LANCE_CSR0_TDMD | LANCE_CSR0_IENA];

  [self enableAllInterrupts];
}

- (IOReturn)enableAllInterrupts {
  long csr3 = [self readCSR32:LANCE_CSR3];
  csr3 &= ~(LANCE_CSR3_RINTM);
  csr3 &= ~(LANCE_CSR3_TINTM);
  [self writeCSR32:LANCE_CSR3:csr3];

  // Why does this not work?
  // long csr0 = [self readCSR32:LANCE_CSR0];
  // csr0 |= LANCE_CSR0_IENA;
  // [self writeCSR32:LANCE_CSR0:csr0];

  return [super enableAllInterrupts];
}

- (void)disableAllInterrupts {
  long csr3 = [self readCSR32:LANCE_CSR3];
  csr3 |= (LANCE_CSR3_RINTM);
  csr3 |= (LANCE_CSR3_TINTM);
  [self writeCSR32:LANCE_CSR3:csr3];

  // Why does this not work?
  // long csr0 = [self readCSR32:LANCE_CSR0];
  // csr0 &= ~(LANCE_CSR0_IENA);
  // [self writeCSR32:LANCE_CSR0:csr0];

  [super disableAllInterrupts];
}


- (BOOL)enablePromiscuousMode {

  IOLog("AMDPCNet32II: Suspending Card\n");
  // set SPND Bit
  [self writeCSR32: LANCE_CSR5: [self readCSR32: LANCE_CSR5] |  LANCE_CSR5_SPND];
  // poll until the card is indeed in suspend mode
  while(([self readCSR32: LANCE_CSR5] & LANCE_CSR5_SPND) == 0) {
    IOLog(".");
  }
  IOLog("\nAMDPCNet32II: Card Suspended\n");

  // Enable Promiscuous mode
  [self writeCSR32: LANCE_CSR15_PROM: [self readCSR32: LANCE_CSR15] | LANCE_CSR15_PROM];

  IOLog("AMDPCNet32II: Resuming Card\n");
  // set SPND Bit
  [self writeCSR32: LANCE_CSR5: [self readCSR32: LANCE_CSR5] & ~(LANCE_CSR5_SPND)];
  // poll until the card is indeed in suspend mode
  while(([self readCSR32: LANCE_CSR5] & LANCE_CSR5_SPND) == 1) {
    IOLog(".");
  }

  IOLog("\nAMDPCNet32II: Card Resumed\n");
  
  // I don't know how to tell if this failed?
  return YES;

}
- (void)disablePromiscuousMode {

  IOLog("AMDPCNet32II: Suspending Card\n");
  // set SPND Bit
  [self writeCSR32: LANCE_CSR5: [self readCSR32: LANCE_CSR5] |  LANCE_CSR5_SPND];
  // poll until the card is indeed in suspend mode
  while(([self readCSR32: LANCE_CSR5] & LANCE_CSR5_SPND) == 0) {
    IOLog(".");
  }
  IOLog("\nAMDPCNet32II: Card Suspended\n");

  // Enable Promiscuous mode
  [self writeCSR32: LANCE_CSR15_PROM: [self readCSR32: LANCE_CSR15] & ~(LANCE_CSR15_PROM)];

  IOLog("AMDPCNet32II: Resuming Card\n");
  // set SPND Bit
  [self writeCSR32: LANCE_CSR5: [self readCSR32: LANCE_CSR5] & ~(LANCE_CSR5_SPND)];
  // poll until the card is indeed in suspend mode
  while(([self readCSR32: LANCE_CSR5] & LANCE_CSR5_SPND) == 1) {
    IOLog(".");
  }
  
  IOLog("\nAMDPCNet32II: Card Resumed\n");

}


// The AMD PCNet32 II has hardware support for multicast
// but just leave that out for now
- (BOOL)enableMulticastMode {
  IOLog("AMDPCNet32II: Enabling Multicast Mode\n");
  isMulticastMode = YES;
  return YES;
}
- (void)disableMulticastMode {
  IOLog("AMDPCNet32II: Disabling Multicast Mode\n");
  isMulticastMode = NO;
}

- (void)timeoutOccurred {
  IOLog("AMDPCNet32II: Timeout occurred\n");
}

- free {
  return [super free];
}

@end
