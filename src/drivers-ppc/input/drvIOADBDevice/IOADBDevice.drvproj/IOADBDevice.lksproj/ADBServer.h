/*
 * ADBServer.h - STUB, no in-tree source.
 *
 * This header was scaffolded, not copied: no source for the IOADBDevice
 * bundle exists anywhere in this tree. The class name and every selector
 * below were extracted from the shipped IOADBDevice.config binary's
 * Objective-C metadata (IOADBDevice_reloc, read with
 * binrecon.macho.read_macho) -- they are not derived from disassembly or
 * any other source. Every method body in ADBServer.m is empty and returns
 * a zero value of its declared return type; nothing here implements ADB
 * server behaviour.
 *
 * Superclass: the linked class symbols in IOADBDevice_reloc name IODevice
 * and no other custom class between ADBServer and IODevice, so IODevice is
 * the direct superclass. ADBServer's class-method set (deviceStyle,
 * requiredProtocols, serverMajor:, getIntValues:forParameter:count:) also
 * matches the pattern of an existing in-tree IODevice pseudo-device class,
 * src/drvPortServer/PortServer.drvproj/PortServer.lksproj/PortServer.h.
 * Parameter types below are placeholders -- the binary's exported symbol
 * table carries selector names only, not argument types.
 */

#import <driverkit/IODevice.h>

@interface ADBServer : IODevice

+ (IODeviceStyle)deviceStyle;
+ (BOOL)probe:(id)deviceDescription;
+ (Protocol **)requiredProtocols;
+ (int)serverMajor:(id)deviceDescription;

- (IOReturn)getIntValues:(unsigned int *)parameterArray forParameter:(IOParameterName)parameterName count:(unsigned int *)count;
- (id)initFromDeviceDescription:(id)deviceDescription;

@end
