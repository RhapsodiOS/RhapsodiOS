/*
 * ADBServer.h - reconstructed from the shipped IOADBDevice.config binary.
 *
 * No in-tree source exists.  The class, its superclass and its one ivar
 * come from __OBJC,__class and __OBJC,__instance_vars; every signature
 * below comes from __OBJC,__meth_var_types.  Nothing here is inferred from
 * instructions and nothing has been compiled.
 *
 *     class ADBServer : IODevice   instance_size = 268 (0x10c)
 *         +0x0108  {ioadb_state="ioadb"@}   state
 *
 * The ivar's encoding gives the struct tag `ioadb_state' and one field
 * named `ioadb' of type @ (an object).  Four bytes of ivar storage at
 * +0x108 on top of IODevice's 0x108 accounts for the whole struct, so the
 * one encoded field is the whole struct: no further fields are added, and
 * none would be justified -- none of the six methods touches +0x108 at
 * all.  The struct is declared, unused, exactly as the binary carries it.
 *
 * Argument names are invented.  This is a pseudo device: -probe: registers
 * a character-device major and -initFromDeviceDescription: names the unit
 * "ADBPseudo", so the shape follows the same pattern as the in-tree
 * PortServer pseudo device.
 */

#import <driverkit/IODevice.h>
#import <driverkit/driverTypes.h>
#import <driverkit/return.h>

/*
 * Derived: the tag and the single field name are from the ivar encoding;
 * the type of `ioadb' is @, written id here.
 */
typedef struct ioadb_state {
    id	ioadb;
} ioadb_state;

@interface ADBServer : IODevice
{
    ioadb_state state;			/* {ioadb_state="ioadb"@} at +0x0108 */
}

/* i8@4:8@12 */
+ (int)serverMajor:(id)deviceDescription;

/* i4@4:8 -- IODeviceStyle is an enum and encodes i */
+ (IODeviceStyle)deviceStyle;

/*
 * ^@4@4:8.  Protocol ** and id * are indistinguishable in the encoding;
 * IODevice.h declares this method Protocol **, so that spelling is used.
 */
+ (Protocol **)requiredProtocols;

/* c8@4:8@12 */
+ (BOOL)probe:(id)deviceDescription;

/* @8@4:8@12 -- untyped argument, matching IODevice's own declaration */
- initFromDeviceDescription:deviceDescription;

/* i16@4:8^I12*16^I20 */
- (IOReturn)getIntValues:(unsigned int *)parameterArray
	    forParameter:(IOParameterName)parameterName
		   count:(unsigned int *)count;

@end
