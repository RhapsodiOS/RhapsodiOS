/*
 * ADBServer.m - STUB, no in-tree source.
 *
 * This file was scaffolded, not copied: no source for the IOADBDevice
 * bundle exists anywhere in this tree. Every selector below was extracted
 * from the shipped IOADBDevice.config binary's Objective-C metadata
 * (IOADBDevice_reloc, read with binrecon.macho.read_macho). Every method
 * body here is empty: it returns a zero value of its declared return type
 * and does nothing else. Nothing in this file implements ADB server
 * behaviour -- see ADBServer.h for the superclass determination.
 */

#import "ADBServer.h"

@implementation ADBServer

+ (IODeviceStyle)deviceStyle
{
	return (IODeviceStyle)0;
}

+ (BOOL)probe:(id)deviceDescription
{
	return NO;
}

+ (Protocol **)requiredProtocols
{
	return (Protocol **)0;
}

+ (int)serverMajor:(id)deviceDescription
{
	return 0;
}

- (IOReturn)getIntValues:(unsigned int *)parameterArray forParameter:(IOParameterName)parameterName count:(unsigned int *)count
{
	return 0;
}

- (id)initFromDeviceDescription:(id)deviceDescription
{
	return nil;
}

@end
