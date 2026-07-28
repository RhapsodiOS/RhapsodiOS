/*
 * IOADBDevice.m - reconstructed from the shipped IOADBDevice.config binary.
 *
 * There is no in-tree source for this driver.  Every body below was
 * transcribed instruction by instruction from IOADBDevice_reloc's __text,
 * with each bl resolved through the Mach-O relocation table (they are jump
 * islands; the branch target alone names nothing) and every selector read
 * from __OBJC,__message_refs.  Method signatures come from
 * __OBJC,__meth_var_types, never from instructions.  The methods appear
 * here in the order they appear in __text, which is Apple's source order.
 *
 * NOT COMPILED.  There is no PowerPC toolchain in this tree; nothing here
 * has been built, linked, loaded or run, and no claim is made that it
 * behaves as Apple's does.
 *
 * What is recovered and what is invented
 * --------------------------------------
 * Recovered from the binary: every selector and signature; the file-scope
 * names gDeviceTable, gDeviceCount, gADBDriver and initalize (from the
 * symbol table -- note Apple's misspelling of `initialize', reproduced
 * deliberately); the field name `info' and the local `index' and argument
 * `uniqueID' of -initForDevice:result: (from the assertion string at
 * 0x15c0, "ASSERTION gDeviceTable[index].info.uniqueID == uniqueID failed
 * at line %d in %s\n"); and the string constants themselves.
 *
 * Invented: the type names IOADBDevicePriv and IOADBDeviceEntry, the field
 * names IOADBDevicePriv.info, IOADBDevicePriv.index and
 * IOADBDeviceEntry.device, and every argument name other than uniqueID.
 * The binary carries none of these.
 *
 * Derived layouts
 * ---------------
 * _priv points at 28 bytes: -initForDevice:result: allocates
 * NXZoneCalloc(zone, 1, 0x1C), copies six words from a gDeviceTable entry
 * into offsets 0..0x17, and stores the table index at 0x18.  0..0x17 is
 * exactly IOADBDeviceInfo (iiiilL), which -getADBInfo: copies straight
 * back out, and -flushADBDevice and the two register methods read offset 4
 * of -- IOADBDeviceInfo.address.
 *
 * gDeviceTable's element stride is 28: every index expression in the
 * binary is (i*8 - i)*4.  Offsets 0..0x17 are the IOADBDeviceInfo the
 * assertion string names `info'; offset 0x18 holds the id claiming the
 * slot, written with self in -initForDevice:result: and cleared in -free.
 * The table's storage is 1792 bytes (gDeviceTable at __DATA,__bss+0 and
 * gDeviceCount at __DATA,__bss+0x700), so it holds 64 entries.  No named
 * constant with the value 64 exists anywhere in this tree -- adb_io.h's
 * ADB_DEVICE_COUNT and IOADBBus.h's IO_ADB_MAX_DEVICE are both 16 -- so 64
 * is written as a literal and recorded here as unnamed.
 *
 * Divergences from <bsd/dev/ppc/IOADBBus.h>, which is imported rather than
 * copied
 * -----------------------------------------------------------------------
 * 1. The IOADBDeviceInfo in every encoding here is {?=iiiilL}: an untagged
 *    struct.  IOADBBus.h's is `struct _adbDeviceInfo', which would encode
 *    {_adbDeviceInfo=iiiilL}.  Field count, order and types agree exactly;
 *    only the tag differs, so Apple's IOADBDevice.m carried its own
 *    untagged copy of the typedef.  Importing IOADBBus.h's tagged one is
 *    the instruction this reconstruction was given, and the resulting
 *    encoding difference is recorded rather than papered over.
 * 2. The register buffers encode `*' (char *), where IOADBBus.h's
 *    ADBprotocol spells them unsigned char * (which would encode ^C).
 * 3. The state words encode I / ^I (unsigned int), where IOADBBus.h has
 *    IOADBDeviceState (unsigned long, which would encode L / ^L).
 */

#import "IOADBDevice.h"

#import <objc/zone.h>

extern void kprintf(const char *, ...);
extern void printf(const char *, ...);
extern void panic(const char *, ...);

/*
 * Reproduces the message the binary's only assertion emits.  printf, not
 * kprintf: the relocation at 0x24c names _printf.  The line number the
 * shipped binary passes is 115; ours will differ, and no rearrangement
 * here can recover Apple's line numbering.
 */
#define ASSERT(e)							\
    do {								\
	if (!(e)) {							\
	    printf("ASSERTION " #e " failed at line %d in %s\n",	\
		   __LINE__, __FILE__);					\
	    panic("assertion failed");					\
	}								\
    } while (0)

/* Invented type name; layout derived above. */
typedef struct {
    IOADBDeviceInfo	info;		/* +0x00, 24 bytes */
    int			index;		/* +0x18, index into gDeviceTable */
} IOADBDevicePriv;

/* Invented type name; `info' is recovered from the assertion string. */
typedef struct {
    IOADBDeviceInfo	info;		/* +0x00, 24 bytes */
    id			device;		/* +0x18, the IOADBDevice holding it */
} IOADBDeviceEntry;

/*
 * gDeviceTable and gDeviceCount are local symbols in the shipped binary
 * and are referenced only from this module, so they are static here.
 */
static IOADBDeviceEntry	gDeviceTable[64];	/* 1792 bytes of __bss */
static int		gDeviceCount;

/*
 * gADBDriver is the IOADBBus this driver talks to; +[ADBServer probe:]
 * sets it from the device description's directDevice.
 *
 * DIVERGENCE, recorded not resolved: the shipped binary's _gADBDriver is a
 * local (static) symbol, yet __OBJC,__module_info names two separate
 * modules -- IOADBDevice.m and ADBServer.m -- and both reference it.  A
 * file-scope static cannot be reached from another translation unit, so
 * Apple's arrangement is not reproducible in standard C.  Its storage sits
 * inside ADBServer.m's __DATA,__data block, so it is defined there and
 * declared extern here, at the cost of one symbol binding the original had
 * as local.  This is the same compromise the in-tree PortServer
 * reconstruction records for ttyiops_devsw.
 */
extern id gADBDriver;

/*
 * Builds gDeviceTable from adb_devices[].  Apple misspelled it; the symbol
 * table says _initalize and the spelling is the evidence.  Its body is one
 * of this driver's six C functions and is not part of this file set yet.
 */
static int initalize(void);

/*
 * Nine methods, not ten: +GetTable:length: is declared in the header
 * because callers send it, but __OBJC,__cls_meth gives its implementation
 * address as 0 with no function entry, so Apple's binary has no body for
 * it either.  There is nothing to transcribe.
 */
@implementation IOADBDevice

/*
 * -initForDevice:result: (0x00e4, 696 bytes with its jump islands)
 *
 * 0x0e4-0x0fc   prologue: save lr and r28-r31, push an 80-byte frame.
 * 0x100-0x108   self -> r30, uniqueID -> r28, result -> r29.
 * 0x10c-0x11c   kprintf of the entry trace.  %d takes the long uniqueID
 *               and %x the result pointer; the project Makefile passes
 *               -Wno-format, which is consistent with both.
 * 0x120-0x128   bl initalize (the relocation names __TEXT,__text+0x5fc,
 *               _initalize), then mr./beq on its result.
 * 0x12c-0x140   nonzero: *result = rtn, build the objc_super pair
 *               {self, IOADBDevice's super_class} at sp+0x38, branch into
 *               the shared [super free] at 0x19c.  The class field loaded
 *               is __OBJC,__class+4, the super_class slot, and the island
 *               resolves to _objc_msgSendSuper -- not _objc_msgSend.
 * 0x144-0x160   zero: build the same objc_super pair, keeping the
 *               superclass in r31 for reuse, and send `init'.  The result
 *               is discarded; nothing reads r3 afterwards.
 * 0x164-0x17c   [self zone], then NXZoneCalloc(zone, 1, 0x1C).
 * 0x180-0x188   store into self->_priv and test it.
 * 0x18c-0x1ac   NULL: *result = -0x2BD (IO_R_NO_MEMORY), rebuild the
 *               objc_super pair from r31, [super free], branch to the
 *               epilogue.  0x19c-0x1a8 are the shared tail the 0x140
 *               branch also enters.
 * 0x1b0-0x1f8   the search loop.  gcc hoisted the first bound test to
 *               0x1bc/0x1c0 and rotated the body, so the back edge at
 *               0x1f8 re-tests against the gDeviceCount cached in r11
 *               while the entry test at 0x1bc reads it fresh.  0x1d4-0x1e0
 *               is the (i*8-i)*4 = i*28 index expression; 0x1e4 loads
 *               .info.uniqueID at +0x10; 0x1ec breaks on a match.
 * 0x1fc-0x210   re-read gDeviceCount, and if index reached it set -0x2C0
 *               (IO_R_NO_DEVICE) and branch to the shared failure tail at
 *               0x2f8.
 * 0x214-0x258   the assertion: recompute &gDeviceTable[index], reload
 *               .info.uniqueID, and on mismatch printf line 0x73 = 115 of
 *               "IOADBDevice.m" and panic("assertion failed").
 * 0x25c-0x27c   .device at +0x18 nonzero -> failure tail at 0x2f4.
 * 0x280-0x2a0   .info.flags at +0x14 andi. 1 -- kIOADBDeviceAvailable --
 *               clear -> the same failure tail.
 * 0x2a4-0x2ac   priv->index = index, then gDeviceTable[index].device =
 *               self.
 * 0x2b0-0x2e0   reload _priv (the store through gDeviceTable may alias, so
 *               gcc could not keep it live) and copy the 24-byte info in
 *               six word pairs.
 * 0x2e4-0x2f0   *result = 0 (IO_R_SUCCESS), return self.
 * 0x2f4         the IO_R_PRIVILEGE failure sets -0x2C1.
 * 0x2f8-0x308   shared failure tail: *result = rtn, then [self free] --
 *               objc_msgSend here, not the objc_msgSendSuper of 0x1a8.
 * 0x30c-0x328   epilogue.
 */
- initForDevice:(long)uniqueID result:(IOReturn *)result
{
    int		index;
    IOReturn	rtn;

    kprintf("(driver) [initForDevice %d result:%x]\n", uniqueID, result);

    rtn = initalize();
    if (rtn != IO_R_SUCCESS) {
	*result = rtn;
	return [super free];
    }

    [super init];

    _priv = NXZoneCalloc([self zone], 1, sizeof(IOADBDevicePriv));
    if (_priv == NULL) {
	*result = IO_R_NO_MEMORY;
	return [super free];
    }

    for (index = 0; index < gDeviceCount; index++)
	if (gDeviceTable[index].info.uniqueID == uniqueID)
	    break;

    if (index >= gDeviceCount) {
	rtn = IO_R_NO_DEVICE;
	goto bad;
    }

    ASSERT(gDeviceTable[index].info.uniqueID == uniqueID);

    if (gDeviceTable[index].device != nil ||
	!(gDeviceTable[index].info.flags & kIOADBDeviceAvailable)) {
	rtn = IO_R_PRIVILEGE;
	goto bad;
    }

    ((IOADBDevicePriv *)_priv)->index = index;
    gDeviceTable[index].device = self;
    ((IOADBDevicePriv *)_priv)->info = gDeviceTable[index].info;

    *result = IO_R_SUCCESS;
    return self;

bad:
    *result = rtn;
    return [self free];
}

/*
 * -free (0x039c, 232 bytes with its jump islands)
 *
 * 0x39c-0x3b4   prologue: save lr and r28-r31, push an 80-byte frame.
 * 0x3b8-0x3c4   self -> r30, load _priv, branch past the body if NULL.
 * 0x3c8-0x3e8   &gDeviceTable in r11, priv->index at +0x18, the i*28 index
 *               expression, then store r28 = 0 into .device at +0x18.
 * 0x3ec-0x3f8   [self zone] -- r3 is still self, untouched since 0x3b8 --
 *               and the result kept in r29.  The `zone' message_ref
 *               address stays in r31 because it is sent twice.
 * 0x3fc-0x41c   [self zone] a second time, load offset 8 of the returned
 *               NXZone (its `free' function pointer, the third field after
 *               realloc and malloc), pass the first zone and _priv, and
 *               call through it.  Two identical messages and one pointer
 *               load is exactly what NXZoneFree's macro expansion,
 *               ((*(zonep)->free)(zonep, ptr)), does to an argument with a
 *               side effect: it evaluates it twice.
 * 0x420         _priv = NULL, reusing the zero in r28.
 * 0x424-0x440   build the objc_super pair {self, IOADBDevice's
 *               super_class} at sp+0x38 and send `free'.  Both the NULL
 *               and non-NULL paths reach this.
 * 0x444-0x460   epilogue; the msgSendSuper result is the return value.
 */
- free
{
    if (_priv != NULL) {
	gDeviceTable[((IOADBDevicePriv *)_priv)->index].device = nil;
	NXZoneFree([self zone], _priv);
	_priv = NULL;
    }

    return [super free];
}

/*
 * -getADBInfo: (0x0484, 68 bytes)
 *
 * 0x484         push a 32-byte frame; a leaf, so lr is not saved.
 * 0x488         _priv -> r9.
 * 0x48c-0x4b8   the 24-byte structure assignment, emitted as four loads,
 *               four stores, two loads, two stores.  Source is r9+0..0x17,
 *               destination is r5, the only argument -- deviceInfo.
 * 0x4bc         r3 = 0, IO_R_SUCCESS.
 * 0x4c0-0x4c4   epilogue.
 *
 * There is no NULL check on _priv; the binary has none.
 */
- (IOReturn)getADBInfo:(IOADBDeviceInfo *)deviceInfo
{
    *deviceInfo = ((IOADBDevicePriv *)_priv)->info;

    return IO_R_SUCCESS;
}

/*
 * -flushADBDevice (0x04c8, 76 bytes with its jump island)
 *
 * 0x4c8-0x4d0   prologue: save lr, push a 64-byte frame.
 * 0x4d4-0x4e8   gADBDriver as the receiver, the `flushADBDevice:'
 *               message_ref at __OBJC,__message_refs+0xc as the selector,
 *               and _priv->info.address (offset 4) as the only argument.
 *               Note the trailing colon: that is ADBprotocol's
 *               one-argument selector, a different selector from this
 *               method's own zero-argument one.
 * 0x4ec         bl objc_msgSend.
 * 0x4f0         r3 = 0.  The message's result is overwritten, so it is
 *               discarded -- unlike the two register methods below, which
 *               return theirs.
 * 0x4f4-0x500   epilogue.
 */
- (IOReturn)flushADBDevice
{
    [gADBDriver flushADBDevice:((IOADBDevicePriv *)_priv)->info.address];

    return IO_R_SUCCESS;
}

/*
 * -readADBDeviceRegister:buffer:length: (0x0514, 92 bytes with its island)
 *
 * 0x514-0x51c   prologue: save lr, push a 64-byte frame.
 * 0x520-0x528   whichRegister (r5) -> r0, buffer (r6) -> r10 and length
 *               (r7) -> r8.  The outgoing call needs r5-r8 for its four
 *               arguments, so the incoming three must move out of the way
 *               first; r8 is already in its final position and survives.
 * 0x52c-0x53c   receiver gADBDriver, selector `readADBDeviceRegister::::'
 *               at __OBJC,__message_refs+0x10 -- ADBprotocol's
 *               four-keyword form, whose first argument is the device.
 * 0x540         r5 = _priv->info.address.
 * 0x544-0x548   r6 = whichRegister, r7 = buffer; r8 = length from 0x528.
 * 0x54c         bl objc_msgSend.
 * 0x550-0x55c   epilogue with no li -- the message's result is returned.
 */
- (IOReturn)readADBDeviceRegister:(int)whichRegister
			   buffer:(char *)buffer
			   length:(int *)length
{
    return [gADBDriver
	     readADBDeviceRegister:((IOADBDevicePriv *)_priv)->info.address
				  :whichRegister
				  :buffer
				  :length];
}

/*
 * -writeADBDeviceRegister:buffer:length: (0x0570, 92 bytes with its island)
 *
 * Instruction for instruction the same shape as the read above:
 * 0x570-0x578 prologue, 0x57c-0x584 the same three-register shuffle,
 * 0x588-0x598 gADBDriver and the `writeADBDeviceRegister::::' message_ref
 * at __OBJC,__message_refs+0x14, 0x59c _priv->info.address into r5,
 * 0x5a0-0x5a4 whichRegister and buffer into r6 and r7, 0x5a8
 * bl objc_msgSend, 0x5ac-0x5b8 epilogue returning the message's result.
 * The only differences from the read are the selector and that length is
 * an int rather than an int *.
 */
- (IOReturn)writeADBDeviceRegister:(int)whichRegister
			    buffer:(char *)buffer
			    length:(int)length
{
    return [gADBDriver
	     writeADBDeviceRegister:((IOADBDevicePriv *)_priv)->info.address
				   :whichRegister
				   :buffer
				   :length];
}

/*
 * -setState:mask: (0x05cc, 16 bytes)
 *
 * 0x5cc  push a 32-byte frame.
 * 0x5d0  r3 = -0x2C7 = -711 = IO_R_UNSUPPORTED (driverkit/return.h).
 * 0x5d4  pop the frame.
 * 0x5d8  blr.
 *
 * Neither argument is read.  IOADBBus.h's comment on the corresponding
 * bus-level methods -- "The state functions below are not currently
 * implemented" -- says the same thing this code does.
 */
- (IOReturn)setState:(unsigned int)state mask:(unsigned int)mask
{
    return IO_R_UNSUPPORTED;
}

/*
 * -getState (0x05dc, 16 bytes)
 *
 * Byte for byte the same four instructions as -setState:mask:, at 0x5dc,
 * 0x5e0, 0x5e4 and 0x5e8.  The declared return type is unsigned int, so
 * IO_R_UNSUPPORTED reaches the caller as 0xfffffd39; the binary makes no
 * attempt to return a plausible state.
 */
- (unsigned int)getState
{
    return IO_R_UNSUPPORTED;
}

/*
 * -watchState:mask: (0x05ec, 16 bytes)
 *
 * The same four instructions again, at 0x5ec, 0x5f0, 0x5f4 and 0x5f8.  The
 * state pointer is never dereferenced.
 */
- (IOReturn)watchState:(unsigned int *)state mask:(unsigned int)mask
{
    return IO_R_UNSUPPORTED;
}

@end
