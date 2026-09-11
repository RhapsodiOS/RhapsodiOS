/*
 * DEC21x4.m - STUB, no in-tree source.
 *
 * This file was scaffolded, not copied: no source for the DEC21x4Ethernet
 * bundle exists anywhere in this tree. Every selector below was extracted
 * from the shipped DEC21x4Ethernet.config binary's Objective-C metadata
 * (DEC21x4Ethernet_reloc, read with binrecon.macho.read_macho). Every
 * method body here is empty: it returns a zero value of its declared
 * return type and does nothing else. Nothing in this file implements
 * Ethernet driver behaviour -- see DEC21x4.h for the superclass
 * determination.
 */

#import "DEC21x4.h"

@implementation DEC21x4

+ (BOOL)probe:(IOPCIDevice *)deviceDescription
{
	return NO;
}

- (void)addMulticastAddress:(enet_addr_t *)addr
{
}

- (void)disableMulticastMode
{
}

- (void)disablePromiscuousMode
{
}

- (void)enableMulticastMode
{
}

- (BOOL)enablePromiscuousMode
{
	return NO;
}

- (id)free
{
	return nil;
}

- (IOReturn)getCharValues:(unsigned char *)parameterArray forParameter:(IOParameterName)parameterName count:(unsigned int *)count
{
	return 0;
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
	return 0;
}

- (IOReturn)getPowerState:(PMPowerState *)state
{
	return 0;
}

- (id)initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
	return nil;
}

- (void)mbufsPlease
{
}

- (void)removeMulticastAddress:(enet_addr_t *)addr
{
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
	return 0;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
	return 0;
}

@end
