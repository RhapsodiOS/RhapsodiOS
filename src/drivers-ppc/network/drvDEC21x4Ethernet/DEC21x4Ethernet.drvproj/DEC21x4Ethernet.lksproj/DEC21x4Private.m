/*
 * DEC21x4Private.m - STUB, no in-tree source.
 *
 * This file was scaffolded, not copied: no source for the DEC21x4Ethernet
 * bundle exists anywhere in this tree. Every selector below was extracted
 * from the shipped DEC21x4Ethernet.config binary's Objective-C metadata
 * (DEC21x4Ethernet_reloc, read with binrecon.macho.read_macho), which
 * named this category Private. Every method body here is empty: it
 * returns a zero value of its declared return type and does nothing
 * else. Nothing in this file implements Ethernet driver behaviour -- see
 * DEC21x4.h for the superclass determination.
 */

#import "DEC21x4.h"

@implementation DEC21x4(Private)

- (void)_allocateDescMemory:(unsigned int)ringSize size:(unsigned int)descSize
{
}

- (void)_allocateMemory
{
}

- (void)_freeDescMemory:(void *)mem
{
}

- (void)_initRxRing
{
}

- (void)_initTxRing
{
}

- (void)_loadSetupFilter:(unsigned char *)filter
{
}

- (void)_setAddressFiltering:(BOOL)enable
{
}

- (void)_startReceive
{
}

- (void)_startTransmit
{
}

- (void)disableAdapterInterrupts
{
}

- (void)enableAdapterInterrupts
{
}

- (void)transmit:(netbuf_t)pkt
{
}

- (void)transmitMbuf:(struct mbuf *)mbuf
{
}

@end
