/*
 * DEC21x4.h - STUB, no in-tree source.
 *
 * This header was scaffolded, not copied: no source for the
 * DEC21x4Ethernet bundle exists anywhere in this tree. The class name,
 * category names and every selector below were extracted from the shipped
 * DEC21x4Ethernet.config binary's Objective-C metadata
 * (DEC21x4Ethernet_reloc, read with binrecon.macho.read_macho, which
 * preserves category tags that IDA's export strips) -- they are not
 * derived from disassembly or any other source. Every method body across
 * DEC21x4.m, DEC21x4Init.m, DEC21x4KDB.m, DEC21x4SRom.m and
 * DEC21x4Private.m is empty and returns a zero value of its declared
 * return type; nothing here implements Ethernet driver behaviour.
 *
 * Superclass: the linked class symbols in DEC21x4Ethernet_reloc name
 * IOEthernet and no other custom class between DEC21x4 and IOEthernet, so
 * IOEthernet is the direct superclass. This matches every sibling PPC
 * Ethernet driver already in the tree (DECchip2104x, MaceEnet, BMacEnet,
 * GemEnet all declare ": IOEthernet <IOPower>" or ": IOEthernet"
 * directly), and the base category's selectors (enablePromiscuousMode,
 * addMulticastAddress:, resetAndEnable:, transmit:, ...) match
 * src/driverkit-3/driverkit/IOEthernet.h and its (DriverInterface)
 * category exactly. getPowerManagement:/setPowerManagement:/
 * getPowerState:/setPowerState: match src/driverkit-3/driverkit/IOPower.h
 * (<IOPower>, as the sibling drivers also declare). getCharValues:
 * forParameter:count: matches src/driverkit-3/driverkit/IODevice.h.
 * The four categories (DEC21x4Init, DEC21x4KDB, DEC21x4SRom, Private) and
 * several selectors (sendPacket:length:, _initTxRing, _initRxRing,
 * enableAdapterInterrupts, disableAdapterInterrupts, _allocateMemory) also
 * match the naming convention of the in-tree
 * src/drivers-ppc/network/drvPPCGem (GemEnet's (Private) category) and
 * src/drivers-i386/network/drvDEC21X4X (DEC21x4Init.m, DEC21x4SRom.m) --
 * a real Apple driver for the same DEC21x4x chip family on i386.
 * Parameter types for selectors with no known framework or in-tree
 * counterpart (the private hardware-setup helpers) are placeholders --
 * the binary's exported symbol table carries selector names only, not
 * argument types.
 */

#import <driverkit/IOEthernet.h>

@interface DEC21x4 : IOEthernet

+ (BOOL)probe:(IOPCIDevice *)deviceDescription;

- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)disableMulticastMode;
- (void)disablePromiscuousMode;
- (void)enableMulticastMode;
- (BOOL)enablePromiscuousMode;
- (id)free;
- (IOReturn)getCharValues:(unsigned char *)parameterArray forParameter:(IOParameterName)parameterName count:(unsigned int *)count;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (id)initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)mbufsPlease;
- (void)removeMulticastAddress:(enet_addr_t *)addr;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;
- (IOReturn)setPowerState:(PMPowerState)state;

@end

@interface DEC21x4(DEC21x4Init)

- (void)_initAdapter;
- (void)_initRegisters;
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)verifyMediaSupport:(int)mediumType;

@end

@interface DEC21x4(DEC21x4KDB)

- (void)sendPacket:(void *)pkt length:(unsigned int)pktLength;

@end

@interface DEC21x4(DEC21x4SRom)

- (void)_getStationAddress:(unsigned char *)addr;
- (void)dumpSROM:(unsigned char *)sromData size:(unsigned int)size;
- (BOOL)matchSROM:(unsigned char *)sromData forMarkers:(void *)markers;
- (BOOL)parseSROM:(unsigned char *)sromData;
- (void)patchSROM:(unsigned char *)sromData withSize:(unsigned int)size offset:(unsigned int)offset verbose:(BOOL)verbose;

@end

@interface DEC21x4(Private)

- (void)_allocateDescMemory:(unsigned int)ringSize size:(unsigned int)descSize;
- (void)_allocateMemory;
- (void)_freeDescMemory:(void *)mem;
- (void)_initRxRing;
- (void)_initTxRing;
- (void)_loadSetupFilter:(unsigned char *)filter;
- (void)_setAddressFiltering:(BOOL)enable;
- (void)_startReceive;
- (void)_startTransmit;
- (void)disableAdapterInterrupts;
- (void)enableAdapterInterrupts;
- (void)transmit:(netbuf_t)pkt;
- (void)transmitMbuf:(struct mbuf *)mbuf;

@end
