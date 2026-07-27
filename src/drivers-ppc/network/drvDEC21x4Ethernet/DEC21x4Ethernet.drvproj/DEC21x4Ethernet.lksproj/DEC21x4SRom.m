/*
 * DEC21x4SRom.m - STUB, no in-tree source.
 *
 * This file was scaffolded, not copied: no source for the DEC21x4Ethernet
 * bundle exists anywhere in this tree. Every selector below was extracted
 * from the shipped DEC21x4Ethernet.config binary's Objective-C metadata
 * (DEC21x4Ethernet_reloc, read with binrecon.macho.read_macho), which
 * named this category DEC21x4SRom. Every method body here is empty: it
 * returns a zero value of its declared return type and does nothing
 * else. Nothing in this file implements Ethernet driver behaviour -- see
 * DEC21x4.h for the superclass determination.
 */

#import "DEC21x4.h"

@implementation DEC21x4(DEC21x4SRom)

- (void)_getStationAddress:(unsigned char *)addr
{
}

- (void)dumpSROM:(unsigned char *)sromData size:(unsigned int)size
{
}

- (BOOL)matchSROM:(unsigned char *)sromData forMarkers:(void *)markers
{
	return NO;
}

- (BOOL)parseSROM:(unsigned char *)sromData
{
	return NO;
}

- (void)patchSROM:(unsigned char *)sromData withSize:(unsigned int)size offset:(unsigned int)offset verbose:(BOOL)verbose
{
}

@end
