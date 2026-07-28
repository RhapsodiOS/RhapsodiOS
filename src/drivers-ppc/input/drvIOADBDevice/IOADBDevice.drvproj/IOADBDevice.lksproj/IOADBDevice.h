/*
 * IOADBDevice.h - reconstructed from the shipped IOADBDevice.config binary.
 *
 * There is no in-tree source for this driver.  Everything declared below
 * was read out of IOADBDevice_reloc's Objective-C metadata: the class and
 * its superclass from __OBJC,__class, the ivar from __OBJC,__instance_vars,
 * and every method signature from __OBJC,__meth_var_types.  No signature
 * here was inferred from instructions.  Nothing in this project has been
 * compiled -- there is no PowerPC toolchain in this tree.
 *
 * Superclass.  The class table's super_class field names Object, not the
 * IODevice an earlier scaffold assumed.  The binary's linked-class list
 * carries both .objc_class_name_Object and .objc_class_name_IODevice, so
 * only the table settles it:
 *
 *     class IOADBDevice : Object   instance_size = 8 (0x8)
 *         +0x0004  ^v   _priv
 *
 * The eight-byte instance is isa at +0 and the single void * at +4.  What
 * _priv points at is not in the metadata; it is derived from the code and
 * described in IOADBDevice.m.
 *
 * IOADBDeviceInfo, IOADBDeviceState, kIOADBDeviceAvailable and
 * @protocol ADBprotocol already exist in <bsd/dev/ppc/IOADBBus.h>, whose
 * own history records that it began as this driver's header ("1997-12-19
 * Brent Schorsch (schorsch) created IOADBDevice.h").  They are imported
 * here, never redeclared.  Two spelling divergences between that header
 * and this binary's encodings are recorded below and in IOADBDevice.m.
 *
 * Argument names are invented.  The binary carries argument types and
 * nothing else; only the local `index' and the argument `uniqueID' of
 * -initForDevice:result: are recovered, and those come from an assertion
 * string rather than from the metadata.
 */

#import <objc/Object.h>
#import <driverkit/return.h>
#import <bsd/dev/ppc/IOADBBus.h>

@interface IOADBDevice : Object
{
    void *_priv;			/* ^v at +0x0004 */
}

/*
 * +GetTable:length: appears in __OBJC,__cls_meth with an implementation
 * address of 0 and no function entry, so there is no body to transcribe.
 * It is declared because callers exist -- adbServerIoctl sends it to the
 * IOADBDevice class -- but its code is absent from Apple's binary.  This
 * is the fourth occurrence of that pattern in this series.
 *
 * Encoding: i12@4:8^{?=iiiilL}12^i16
 */
+ (IOReturn)GetTable:(IOADBDeviceInfo *)table length:(int *)length;

/* @12@4:8l12^i16 */
- initForDevice:(long)uniqueID result:(IOReturn *)result;

/* @4@4:8 */
- free;

/* i8@4:8^{?=iiiilL}12 */
- (IOReturn)getADBInfo:(IOADBDeviceInfo *)deviceInfo;

/* i4@4:8 */
- (IOReturn)flushADBDevice;

/*
 * i16@4:8i12*16^i20 and i16@4:8i12*16i20.  The buffer encodes as `*',
 * which is char *; IOADBBus.h's ADBprotocol spells the same parameter
 * unsigned char *, which would encode ^C.  The encoding is followed here.
 */
- (IOReturn)readADBDeviceRegister:(int)whichRegister
			   buffer:(char *)buffer
			   length:(int *)length;

- (IOReturn)writeADBDeviceRegister:(int)whichRegister
			    buffer:(char *)buffer
			    length:(int)length;

/*
 * The three state methods encode their state words as I and ^I, that is
 * unsigned int, not the unsigned long of IOADBBus.h's IOADBDeviceState.
 * The same binary encodes IOADBDeviceInfo's long and unsigned long fields
 * as l and L, so this compiler does distinguish the two and I is decisive.
 */

/* i12@4:8I12I16 */
- (IOReturn)setState:(unsigned int)state mask:(unsigned int)mask;

/* I4@4:8 */
- (unsigned int)getState;

/* i12@4:8^I12I16 */
- (IOReturn)watchState:(unsigned int *)state mask:(unsigned int)mask;

@end
