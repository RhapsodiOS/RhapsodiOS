/*
 * IOADBDevice.h - STUB, no in-tree source.
 *
 * This header was scaffolded, not copied: no source for the IOADBDevice
 * bundle exists anywhere in this tree. The class name and every selector
 * below were extracted from the shipped IOADBDevice.config binary's
 * Objective-C metadata (IOADBDevice_reloc, read with
 * binrecon.macho.read_macho) -- they are not derived from disassembly or
 * any other source. Every method body in IOADBDevice.m is empty and
 * returns a zero value of its declared return type; nothing here
 * implements ADB device behaviour.
 *
 * Superclass: the linked class symbols in IOADBDevice_reloc name IODevice
 * and no other custom class between IOADBDevice and IODevice, so IODevice
 * is the direct superclass. This also matches
 * src/kernel-7/bsd/dev/ppc/IOADBBus.h ("@interface IOADBBus : IODevice
 * <ADBprotocol>"), whose own header comment records it was originally
 * named IOADBDevice.h/IOADBDevice.m, and whose ADBprotocol declares a
 * closely matching selector set (getADBInfo:, flushADBDevice,
 * readADBDeviceRegister:.., writeADBDeviceRegister:.., setState:..mask:,
 * watchState:..mask:) -- though the binary's selectors carry explicit
 * buffer:/length: keyword labels that IOADBBus's current ADBprotocol does
 * not, a measured spelling divergence this stub does not resolve.
 * GetTable:length: is extracted as a class method (+) here, unlike
 * IOADBBus's instance-method GetTable::.
 * Parameter types below are placeholders -- the binary's exported symbol
 * table carries selector names only, not argument types, and this stub
 * does not import kernel-7's private ADB type definitions.
 */

#import <driverkit/IODevice.h>

@interface IOADBDevice : IODevice

+ (IOReturn)GetTable:(void *)table length:(int *)length;

- (IOReturn)flushADBDevice;
- (id)free;
- (IOReturn)getADBInfo:(int)whichDevice;
- (unsigned long)getState;
- (id)initForDevice:(id)device result:(IOReturn *)result;
- (IOReturn)readADBDeviceRegister:(int)whichRegister buffer:(unsigned char *)buffer length:(int *)length;
- (IOReturn)setState:(unsigned long)state mask:(unsigned long)mask;
- (IOReturn)watchState:(unsigned long *)state mask:(unsigned long)mask;
- (IOReturn)writeADBDeviceRegister:(int)whichRegister buffer:(unsigned char *)buffer length:(int)length;

@end
