/*
 * IOADBDevice.m - STUB, no in-tree source.
 *
 * This file was scaffolded, not copied: no source for the IOADBDevice
 * bundle exists anywhere in this tree. Every selector below was extracted
 * from the shipped IOADBDevice.config binary's Objective-C metadata
 * (IOADBDevice_reloc, read with binrecon.macho.read_macho). Every method
 * body here is empty: it returns a zero value of its declared return type
 * and does nothing else. Nothing in this file implements ADB device
 * behaviour -- see IOADBDevice.h for the superclass determination.
 */

#import "IOADBDevice.h"

@implementation IOADBDevice

+ (IOReturn)GetTable:(void *)table length:(int *)length
{
	return 0;
}

- (IOReturn)flushADBDevice
{
	return 0;
}

- (id)free
{
	return nil;
}

- (IOReturn)getADBInfo:(int)whichDevice
{
	return 0;
}

- (unsigned long)getState
{
	return 0;
}

- (id)initForDevice:(id)device result:(IOReturn *)result
{
	return nil;
}

- (IOReturn)readADBDeviceRegister:(int)whichRegister buffer:(unsigned char *)buffer length:(int *)length
{
	return 0;
}

- (IOReturn)setState:(unsigned long)state mask:(unsigned long)mask
{
	return 0;
}

- (IOReturn)watchState:(unsigned long *)state mask:(unsigned long)mask
{
	return 0;
}

- (IOReturn)writeADBDeviceRegister:(int)whichRegister buffer:(unsigned char *)buffer length:(int)length
{
	return 0;
}

@end
