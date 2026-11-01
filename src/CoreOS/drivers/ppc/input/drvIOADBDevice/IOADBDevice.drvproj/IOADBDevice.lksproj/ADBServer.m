/*
 * ADBServer.m - reconstructed from the shipped IOADBDevice.config binary.
 *
 * There is no in-tree source for this driver.  Every body below was
 * transcribed instruction by instruction from IOADBDevice_reloc's __text.
 * Each bl was resolved through the Mach-O relocation table rather than by
 * its branch target -- they are jump islands, and the two that matter most
 * here, _objc_msgSend and _objc_msgSendSuper, have different islands and
 * different meanings.  Every selector comes from __OBJC,__message_refs and
 * every class reference from __OBJC,__cls_refs.  Signatures come from
 * __OBJC,__meth_var_types, never from instructions.  The methods appear in
 * __text order, which is Apple's source order.
 *
 * NOT COMPILED.  There is no PowerPC toolchain in this tree.
 *
 * ADBServer is the pseudo device that fronts the ADB bus for user space:
 * +serverMajor: installs a character-device switch entry, +probe: sizes
 * the session map from the config table, and -getIntValues: publishes the
 * session count.  The character-device layer itself -- adbServeropen,
 * adbServerclose, adbServerioctlDispatch and the two ioctl handlers it
 * calls -- is five C functions, and they follow this file's @end in the
 * order __text carries them.  Being C they have no type encodings, so
 * their signatures are derived rather than read; each derivation is stated
 * above the function it belongs to.
 *
 * Recovered from the binary: every selector and signature; the file-scope
 * names gADBServerMajor, gADBServerLoaded, gADBDriver, gMapLock,
 * gNumSessions and gADBDeviceIdMap, and the function names adbServeropen,
 * adbServerclose, adbServerioctlDispatch, adbServerIoctl and
 * ioadbDeviceIoctl (all from the symbol table); the string constants; and
 * the config-table key "Maximum Sessions".
 *
 * Invented: the type names ADBDeviceIdMapEntry, ioadb_device_request_t and
 * ioadb_table_request_t and all of their field names, and every argument
 * and local name.
 *
 * gADBDeviceIdMap's layout is derived: +probe: bzeroes 0x800 bytes of it,
 * every index expression in this binary is i*8, the minor number that
 * indexes it is masked with 0xff, and the two words of an entry are used
 * as an object pointer (offset 0) and an in-use flag (offset 4).  256
 * entries of eight bytes is 2048, which is the whole reservation.  No
 * named constant with the value 256 was found in this tree, so it is a
 * literal and recorded here as unnamed.
 */

#import "ADBServer.h"
#import "IOADBDevice.h"

#import <driverkit/devsw.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <machkit/NXLock.h>
#import <bsd/dev/ppc/IOADBBus.h>
#import <bsd/sys/types.h>
#import <bsd/sys/errno.h>

extern void kprintf(const char *, ...);
extern int sprintf(char *, const char *, ...);
extern long strtol(const char *, char **, int);
extern int strcmp(const char *, const char *);
extern int strlen(const char *);
extern void bzero(void *, int);

/*
 * The read, write, stop, reset, select, mmap, getc and putc entry points
 * +serverMajor: registers are all this one, an external in the binary.
 */
extern int enodev();

/*
 * The five C functions of this module, all `local' symbols in the binary
 * and so static here.  They are declared up here because +serverMajor:
 * installs the first three and adbServerioctlDispatch calls the last two,
 * and all five are defined after this file's @end -- which is where __text
 * puts them, at 0xd84 onwards, after every ADBServer method.
 *
 * These are C: there are no type encodings, so every parameter list below
 * is DERIVED from the disassembly and from call sites, not read from
 * metadata.  What each derivation rests on is recorded above the function
 * itself.  In particular none of the three cdevsw entry points reads the
 * flag, devtype or proc arguments the kernel passes them, so their trailing
 * parameters are not recoverable and are not invented; +serverMajor: casts
 * all three to IOSwitchFunc, which devsw.h declares as `int (*)()', so the
 * casts remain correct either way.
 */
static int adbServeropen(dev_t dev);
static int adbServerclose(dev_t dev);
static int adbServerioctlDispatch(dev_t dev, int cmd, void *data);
static int adbServerIoctl(int cmd, void *data);
static int ioadbDeviceIoctl(int unit, void *data);

/* Invented type and field names; layout derived above. */
typedef struct {
    id		device;			/* +0x00, the IOADBDevice for the unit */
    int		inUse;			/* +0x04, nonzero once allocated */
} ADBDeviceIdMapEntry;

/*
 * The two ioctl payloads, DERIVED entirely from offsets.  Nothing in the
 * binary names any of these types or fields; every name below is invented.
 * What is not invented is the layout, and each one is confirmed twice over
 * by the ioctl command words themselves, which encode sizeof(payload):
 *
 *   ioadb_device_request_t   32 bytes  == 0x020, the length in 0xC0206102
 *   ioadb_table_request_t   396 bytes  == 0x18C, the length in 0xC18C6103
 *
 * ioadb_device_request_t's offsets come from ioadbDeviceIoctl's eight
 * switch arms: +0x00 is the command it switches on, +0x04 takes every
 * IOReturn it stores, +0x08 is the value word (the long uniqueID for
 * command 2, the register number for 5 and 6, the state for 7 to 9) and is
 * also the base of the IOADBDeviceInfo command 3 fills, +0x0c is the
 * register buffer and the mask, and +0x14 is the register length.  An
 * IOADBDeviceInfo at +0x08 is 24 bytes, which makes the struct exactly 32.
 *
 * ioadb_table_request_t's come from adbServerIoctl's GetTable arm: the same
 * command and result words, a table at +0x08 and its length at +0x188.
 * 0x188 - 0x08 = 384 = IO_ADB_MAX_DEVICE * sizeof(IOADBDeviceInfo), which
 * is also what IOADBBus.h's comment on GetTable:length: demands ("an array
 * that is IO_ADB_MAX_DEVICE long"), and 0x188 + 4 = 396.
 *
 * The register buffer's eight bytes are IO_ADB_MAX_PACKET, named in
 * IOADBBus.h.  It is `char' rather than `unsigned char' because the method
 * it is passed to encodes its buffer as `*', and because the dump loops
 * read it with lbz -- plain char is unsigned on this ABI either way.
 */
typedef struct {
    int			command;	/* +0x000 */
    IOReturn		result;		/* +0x004 */
    union {
	long		uniqueID;			/* command 2 */
	IOADBDeviceInfo	deviceInfo;			/* command 3 */
	struct {
	    int		whichRegister;			/* +0x008 */
	    char	buffer[IO_ADB_MAX_PACKET];	/* +0x00c */
	    int		length;				/* +0x014 */
	} reg;						/* commands 5, 6 */
	struct {
	    unsigned int state;				/* +0x008 */
	    unsigned int mask;				/* +0x00c */
	} st;						/* commands 7, 8, 9 */
    } u;				/* +0x008, 24 bytes */
} ioadb_device_request_t;		/* 32 bytes = 0x020 */

typedef struct {
    int			command;			/* +0x000 */
    IOReturn		result;				/* +0x004 */
    IOADBDeviceInfo	table[IO_ADB_MAX_DEVICE];	/* +0x008, 384 B */
    int			length;				/* +0x188 */
} ioadb_table_request_t;		/* 396 bytes = 0x18C */

/*
 * The three ioctl command words, written as the literals the binary
 * compares against.
 *
 * NO NAME FOR ANY OF THEM EXISTS IN THIS TREE.  adb.h, adb_io.h,
 * IOADBBus.h, IOADBBusProt.h and the sys/ioctl.h family were all checked;
 * the only 'a'-group ioctl in the tree is netiso's SIOCGSTYPE.  Rather than
 * invent names, the literals stand and their decomposition under
 * <bsd/sys/ioccom.h> is recorded here, each verified arithmetically:
 *
 *   0x40546101 = _IOR ('a', 1, char[84])                 84 == 0x054
 *   0xC0206102 = _IOWR('a', 2, ioadb_device_request_t)   32 == 0x020
 *   0xC18C6103 = _IOWR('a', 3, ioadb_table_request_t)   396 == 0x18C
 *
 * The first one is the only one Apple's own name for which survives: the
 * kprintf at 0x10d0 in adbServerIoctl prints "... IOADB_KERN_GETDEVICE\n"
 * on entry to its arm.  That is a string, not a definition, so it is
 * recorded here and NOT written as a macro -- the header that defined it
 * is not in this tree, and a macro here would be an invention wearing a
 * recovered name.  Its 84-byte payload is used only as the destination of
 * one sprintf, so nothing beyond "it starts with a string" is derivable
 * about its layout, and no type is declared for it.
 *
 * Both comparisons against these words are cmpw, the signed compare, so
 * the command is an int and 0xc18c6103 -- which does not fit in one -- is
 * matched by bit pattern.  That is what the binary does and it is written
 * as the binary does it, wart included.
 */

/*
 * gADBDriver is the IOADBBus this bundle talks to.  See IOADBDevice.m for
 * why it is a plain global here and not the static the shipped binary's
 * local symbol implies: the binary's __OBJC,__module_info names two
 * modules and both reference it, which standard C cannot express.  Its
 * storage sits in this module's __DATA,__data block, so it is defined
 * here.
 */
id gADBDriver;

/* All local symbols in the binary and referenced only from this module. */
static int			gADBServerMajor;
static char			gADBServerLoaded;
static id			gMapLock;
static int			gNumSessions;
static ADBDeviceIdMapEntry	gADBDeviceIdMap[256];	/* 2048 bytes */

@implementation ADBServer

/*
 * +serverMajor: (0x07d0, 292 bytes with its jump islands)
 *
 * 0x7d0-0x7e4   prologue: save lr and r29-r31, push a 112-byte frame.  The
 *               frame is larger than the other methods' because this call
 *               spills six arguments to the stack.
 * 0x7e8-0x7ec   self -> r30, deviceDescription -> r29.
 * 0x7f0-0x7fc   load gADBServerMajor into r3 and branch to the epilogue if
 *               it is nonzero.  The load serves both the test and the
 *               early return, which is why the return value needs no
 *               reload on that path.
 * 0x800-0x80c   [self class].
 * 0x810-0x834   the addToCdevsw... message_ref, and _enodev's address
 *               stored six times to sp+0x38 through sp+0x4c.  Those six
 *               words are arguments nine through fourteen -- stop, reset,
 *               select, mmap, getc and putc.
 * 0x838-0x854   r5 = deviceDescription, r6 = adbServeropen,
 *               r7 = adbServerclose, r8 = enodev (read), r9 = enodev
 *               already (write), r10 = adbServerioctlDispatch (ioctl).
 *               0x84c's mr r8, r9 is what fills read; write reuses the r9
 *               that 0x818 loaded.
 * 0x858         bl objc_msgSend.  The BOOL it returns is discarded.
 * 0x85c-0x870   [self class] again -- the `class' message_ref address is
 *               still in r31 from 0x800 -- then `characterMajor'.
 * 0x874-0x87c   store the result into gADBServerMajor.
 * 0x880-0x888   reload it and compare against -1.
 * 0x88c-0x898   equal: the "can't find space" kprintf, then join at 0x8b0.
 * 0x89c-0x8ac   otherwise: the "major number %d" kprintf, argument reloaded
 *               from gADBServerMajor.
 * 0x8b0-0x8b4   reload gADBServerMajor for the return.
 * 0x8b8-0x8d0   epilogue.
 */
+ (int)serverMajor:(id)deviceDescription
{
    if (gADBServerMajor == 0) {
	[[self class] addToCdevswFromDescription:deviceDescription
					    open:(IOSwitchFunc)adbServeropen
					   close:(IOSwitchFunc)adbServerclose
					    read:(IOSwitchFunc)enodev
					   write:(IOSwitchFunc)enodev
					   ioctl:(IOSwitchFunc)adbServerioctlDispatch
					    stop:(IOSwitchFunc)enodev
					   reset:(IOSwitchFunc)enodev
					  select:(IOSwitchFunc)enodev
					    mmap:(IOSwitchFunc)enodev
					    getc:(IOSwitchFunc)enodev
					    putc:(IOSwitchFunc)enodev];

	gADBServerMajor = [[self class] characterMajor];

	if (gADBServerMajor == -1)
	    kprintf("ADB Server: Can't find space in devsw\n");
	else
	    kprintf("ADB Server: major number %d\n", gADBServerMajor);
    }

    return gADBServerMajor;
}

/*
 * +deviceStyle (0x08f4, 16 bytes)
 *
 * 0x8f4  push a 32-byte frame.
 * 0x8f8  r3 = 1.
 * 0x8fc  pop the frame.
 * 0x900  blr.
 *
 * driverTypes.h's IODeviceStyle is { IO_DirectDevice, IO_IndirectDevice,
 * IO_PseudoDevice }, so 1 is IO_IndirectDevice.  That is what the binary
 * returns even though the device it registers is named ADBPseudo, and the
 * name is written from the constant, not the other way round.
 */
+ (IODeviceStyle)deviceStyle
{
    return IO_IndirectDevice;
}

/*
 * +requiredProtocols (0x0904, 20 bytes)
 *
 * 0x904        push a 32-byte frame.
 * 0x908-0x90c  materialise the address of _protocols.30 in __DATA,__data.
 * 0x910-0x914  epilogue.
 *
 * _protocols.30 is eight bytes at __DATA,__data+0x10.  Its first word
 * carries a vanilla-32-absolute relocation to __OBJC,__protocol+0, whose
 * five-word Protocol structure names ADBprotocol and points its instance
 * method list at __OBJC,__cat_inst_meth; the second word is zero.  So the
 * list is { @protocol(ADBprotocol), nil } and nothing here is guessed.
 *
 * gcc's `.30' suffix marks a function-scope static -- file-scope statics
 * in this binary keep their bare names, gADBDriver among them -- so the
 * array is declared inside the method.
 *
 * The protocol's six method descriptions read out of __OBJC,__cat_inst_meth
 * are adb_register_handler::, writeADBDeviceRegister::::,
 * readADBDeviceRegister::::, flushADBDevice:, getADBInfo:: and GetTable::.
 * That is exactly IOADBBus.h's ADBprotocol, selector for selector, and not
 * IOADBBusProt.h's, whose buffer:/length: keywords would give different
 * selectors.  IOADBBus.h is therefore the header imported here.
 */
+ (Protocol **)requiredProtocols
{
    static Protocol *protocols[] = { @protocol(ADBprotocol), nil };

    return protocols;
}

/*
 * +probe: (0x0918, 552 bytes with its jump islands)
 *
 * 0x918-0x930   prologue: save lr and r28-r31, push an 80-byte frame.
 * 0x934-0x938   self -> r31, deviceDescription -> r28.
 * 0x93c-0x944   the "ADB Server: probe" kprintf.
 * 0x948-0x960   [self serverMajor:deviceDescription], compared against -1;
 *               equal branches to 0x9c0, the shared `return NO'.
 * 0x964-0x96c   the "serverMajor success" kprintf.
 * 0x970-0x988   [deviceDescription directDevice] into gADBDriver.
 * 0x98c-0x9a0   [deviceDescription configTable]; mr. sets the condition
 *               and bne skips the failure block.
 * 0x9a4-0x9bc   nil: the "Invalid Config Table" kprintf, gNumSessions = -1,
 *               fall into 0x9c0.
 * 0x9c0-0x9c4   r3 = 0 and branch to the epilogue: the shared `return NO'
 *               that four separate branches reach.
 * 0x9c8-0x9dc   [configTable valueForStringKey:"Maximum Sessions"], kept
 *               in r31 -- self is dead from here on, which is why the
 *               register is reused.
 * 0x9e4-0x9f0   strtol(value, NULL, 0) into r30.
 * 0x9f4-0x9fc   [configTable freeString:value].
 * 0xa08-0xa10   clamp: > 255 becomes 256.  The test is against 0xff and
 *               the assignment is 0x100, so this is not a mask.
 * 0xa14-0xa28   raise gNumSessions to it if it is larger; the store is
 *               skipped otherwise.
 * 0xa2c-0xa3c   the "gNumSessions = %d" kprintf, argument reloaded from
 *               memory rather than from r30.
 * 0xa40-0xa4c   if gMapLock is already non-nil, branch back to 0x9c0 and
 *               return NO.  This is the second-probe guard.
 * 0xa50-0xa5c   bzero(gADBDeviceIdMap, 0x800).
 * 0xa60-0xa68   gADBDeviceIdMap[0].inUse = 1, reserving minor 0.
 * 0xa6c-0xa94   [[NXLock alloc] init] into gMapLock.  NXLock comes from
 *               __OBJC,__cls_refs, and `alloc' keeps its message_ref
 *               address in r31 because it is sent twice.
 * 0xa98-0xab4   [[ADBServer alloc] initFromDeviceDescription:
 *               deviceDescription].  The receiver is the ADBServer entry
 *               in __OBJC,__cls_refs, a literal class name, not [self ...].
 * 0xab8-0xacc   nil: the "= NO" kprintf, then back to 0x9c0.
 * 0xad0-0xadc   otherwise the "= YES" kprintf and r3 = 1.
 * 0xae0-0xafc   epilogue.
 */
+ (BOOL)probe:(id)deviceDescription
{
    const char	*value;
    id		configTable;
    int		maxSessions;

    kprintf("ADB Server: probe\n");

    if ([self serverMajor:deviceDescription] == -1)
	return NO;

    kprintf("ADB Server: serverMajor success\n");

    gADBDriver = [deviceDescription directDevice];

    configTable = [deviceDescription configTable];
    if (configTable == nil) {
	kprintf("ADBServer +probe: Invalid Config Table\n");
	gNumSessions = -1;
	return NO;
    }

    value = [configTable valueForStringKey:"Maximum Sessions"];
    maxSessions = strtol(value, NULL, 0);
    [configTable freeString:value];

    if (maxSessions > 255)
	maxSessions = 256;

    if (maxSessions > gNumSessions)
	gNumSessions = maxSessions;

    kprintf("ADBServer +probe gNumSessions = %d\n", gNumSessions);

    if (gMapLock != nil)
	return NO;

    bzero(gADBDeviceIdMap, sizeof(gADBDeviceIdMap));
    gADBDeviceIdMap[0].inUse = 1;

    gMapLock = [[NXLock alloc] init];

    if ([[ADBServer alloc] initFromDeviceDescription:deviceDescription] == nil) {
	kprintf("[ADBServer +probe] = NO\n");
	return NO;
    }

    kprintf("[ADBServer +probe] = YES\n");
    return YES;
}

/*
 * -initFromDeviceDescription: (0x0b40, 300 bytes with its jump islands)
 *
 * 0xb40-0xb50   prologue: save lr and r30-r31, push an 80-byte frame.
 * 0xb54-0xb58   self -> r31, deviceDescription -> r30.
 * 0xb5c-0xb6c   lbz gADBServerLoaded -- a byte, so a char -- and branch to
 *               0xc08 if it is already set.
 * 0xb70-0xb7c   set it to 1.
 * 0xb80-0xb94   [self setDeviceKind:"ADB Server"].
 * 0xb98-0xba8   [self setUnit:0].
 * 0xbac-0xbc0   [self setName:"ADBPseudo"].
 * 0xbc4-0xbd0   build the objc_super pair {self, ADBServer's super_class}
 *               at sp+0x38.  The class word is __OBJC,__class+0x2c, which
 *               is ADBServer's struct at +0x28 plus its super_class field
 *               at +4, and the island resolves to _objc_msgSendSuper.
 * 0xbd4-0xbe4   [super initFromDeviceDescription:deviceDescription].
 * 0xbe8-0xbec   mr./beq: nil falls through to the shared free at 0xc14.
 * 0xbf0-0xbfc   [self registerDevice], result discarded.
 * 0xc00-0xc04   return the super result.
 * 0xc08-0xc10   the already-loaded branch: the "called twice!" kprintf --
 *               note it carries no trailing newline, unlike every other
 *               string in this binary -- then falls into 0xc14.
 * 0xc14-0xc20   the shared tail: [self free], objc_msgSend.  Both the
 *               already-loaded path and the failed-super path reach it,
 *               and its result is the return value.
 * 0xc24-0xc38   epilogue.
 */
- initFromDeviceDescription:deviceDescription
{
    id result;

    if (gADBServerLoaded == 0) {
	gADBServerLoaded = 1;

	[self setDeviceKind:"ADB Server"];
	[self setUnit:0];
	[self setName:"ADBPseudo"];

	result = [super initFromDeviceDescription:deviceDescription];
	if (result != nil) {
	    [self registerDevice];
	    return result;
	}
    } else {
	kprintf("ADBServer initFromDeviceDescription called twice!");
    }

    return [self free];
}

/*
 * -getIntValues:forParameter:count: (0x0c6c, 280 bytes with its islands)
 *
 * 0xc6c-0xc84   prologue: save lr and r28-r31, push an 80-byte frame.
 * 0xc88-0xc94   self -> r28, parameterArray -> r29, parameterName -> r31,
 *               count -> r30.
 * 0xc98-0xca8   the entry kprintf; %s takes parameterName and %d takes
 *               *count, loaded at 0xca4.
 * 0xcac-0xcc0   strcmp(parameterName, "Maximum Sessions"); zero branches
 *               to 0xd0c.
 * 0xcc4-0xcd0   nonzero: build the objc_super pair {self, ADBServer's
 *               super_class} at sp+0x38 -- the same __OBJC,__class+0x2c
 *               word -initFromDeviceDescription: uses.
 * 0xcd4-0xcec   [super getIntValues:forParameter:count:] with all three
 *               arguments passed straight through.
 * 0xcf0-0xd00   keep the result in r31 and trace it.
 * 0xd04-0xd08   return it.
 * 0xd0c-0xd14   the match: parameterArray[0] = gNumSessions.
 * 0xd18-0xd1c   *count = 1.
 * 0xd20-0xd2c   the OK trace.  Its argument is reloaded from
 *               parameterArray[0] at 0xd28, not taken from the
 *               gNumSessions already in a register.
 * 0xd30         r3 = 0, IO_R_SUCCESS.
 * 0xd34-0xd50   epilogue.
 */
- (IOReturn)getIntValues:(unsigned int *)parameterArray
	    forParameter:(IOParameterName)parameterName
		   count:(unsigned int *)count
{
    IOReturn rtn;

    kprintf("[getIntValues: %s count:%d\n", parameterName, *count);

    if (strcmp(parameterName, "Maximum Sessions") != 0) {
	rtn = [super getIntValues:parameterArray
		     forParameter:parameterName
			    count:count];
	kprintf("... getIntValues:super] = %d;\n", rtn);
	return rtn;
    }

    parameterArray[0] = gNumSessions;
    *count = 1;
    kprintf("... getIntValues: NSES = %d] OK;\n", parameterArray[0]);

    return IO_R_SUCCESS;
}

@end

/*
 * adbServeropen (0x0d84, 272 bytes with its jump islands)
 *
 * Signature derived.  Only r3 is read: 0x0d9c copies it to r29 and 0x0da4
 * masks it with 0xff.  r4, r5 and r6 -- the flag, devtype and proc a
 * cdevsw d_open is called with -- are never touched, so they are not
 * recoverable and are not invented.  The return is r31, an int, and it is
 * both handed to IOSetUNIXError and returned, so it is a UNIX errno.  The
 * 0xff mask is minor()'s, defined in <bsd/sys/types.h> as ((x) & 0xff),
 * which is why the argument is written dev_t.
 *
 * 0x0d84-0x0d98  prologue: save lr and r29-r31, push an 80-byte frame.
 * 0x0d9c         dev -> r29.
 * 0x0da0         rtn = 0.  Placed before the test, so it is an initialiser
 *                rather than an assignment on the unit == 0 path.
 * 0x0da4-0x0da8  andi. r30, r29, 0xff -- unit = minor(dev) -- and a beq
 *                straight to the trailing trace at 0x0e28.  Minor 0 is the
 *                server's own node, reserved by +probe:, and opening it
 *                does nothing and succeeds.
 * 0x0dac-0x0db8  the "open unit" trace.
 * 0x0dbc-0x0dd4  gADBDeviceIdMap[unit].inUse: the i*8 index expression,
 *                the flag at +4, and zero means no such session.
 * 0x0dd8-0x0ddc  rtn = 0x13 = 19 = ENODEV, then to 0x0e28.
 * 0x0de0-0x0df4  .device at +0 non-nil means the unit is already open.
 * 0x0df8-0x0dfc  rtn = 0xd = 13 = EACCES, then to 0x0e28.
 * 0x0e00-0x0e20  [IOADBDevice alloc] -- the receiver is the IOADBDevice
 *                entry in __OBJC,__cls_refs, a literal class name -- stored
 *                into .device.  The object is only allocated here; it is
 *                initialised later, by ioadbDeviceIoctl's command 2.
 * 0x0e24         rtn = 0 again.  Redundant against 0x0da0, and emitted, so
 *                the source assigns it on this path too.
 * 0x0e28-0x0e38  the shared exit trace; %x takes dev, not unit.
 * 0x0e3c-0x0e40  IOSetUNIXError(rtn), called unconditionally, including
 *                with rtn == 0.
 * 0x0e44-0x0e60  epilogue returning rtn.
 */
static int
adbServeropen(dev_t dev)
{
    int	unit = minor(dev);
    int	rtn = 0;

    if (unit != 0) {
	kprintf("open unit:(%d)\n", unit);

	if (gADBDeviceIdMap[unit].inUse == 0) {
	    rtn = ENODEV;
	} else if (gADBDeviceIdMap[unit].device != nil) {
	    rtn = EACCES;
	} else {
	    gADBDeviceIdMap[unit].device = [IOADBDevice alloc];
	    rtn = 0;
	}
    }

    kprintf("adbServeropen(%x) = %d\n", dev, rtn);
    IOSetUNIXError(rtn);

    return rtn;
}

/*
 * adbServerclose (0x0e94, 268 bytes with its jump islands)
 *
 * Signature derived the same way: r3 alone is read and masked with 0xff at
 * 0x0ebc; r4 onwards are untouched.
 *
 * 0x0e94-0x0eb0  prologue: save lr and r27-r31, push an 80-byte frame.  Two
 *                more callee-saved registers than open, because the entry
 *                address is held live across three calls.
 * 0x0eb4         dev -> r31.
 * 0x0eb8         rtn = 0 in r27, and NOTHING EVER WRITES r27 AGAIN.  This
 *                function cannot fail: every path returns 0, and the three
 *                things that could have been errors are traces instead.
 * 0x0ebc-0x0ec0  unit = minor(dev); zero goes straight to 0x0f2c.
 * 0x0ec4-0x0ed0  unit*8, &gADBDeviceIdMap, and the entry address kept in
 *                r28 -- unlike open, which recomputes it three times.
 * 0x0ed4-0x0edc  .inUse zero -> 0x0f1c, the "already closed" trace.
 * 0x0ee0-0x0ee8  .device nil -> 0x0f00, the "adbDevice is nil" trace.
 * 0x0eec-0x0ef8  [device free], and the nil it returns stored back into
 *                .device.  objc_msgSend, not objc_msgSendSuper.
 * 0x0efc         join at 0x0f10.
 * 0x0f00-0x0f0c  the nil trace; falls into 0x0f10.
 * 0x0f10-0x0f18  .inUse = 0.  Both the freed and the nil path reach it, so
 *                the session is released either way.
 * 0x0f1c-0x0f28  the "already closed" trace; falls into 0x0f2c.
 * 0x0f2c-0x0f3c  the shared exit trace, %x on dev again.
 * 0x0f40-0x0f44  IOSetUNIXError(0).
 * 0x0f48-0x0f6c  epilogue returning 0.
 */
static int
adbServerclose(dev_t dev)
{
    int	unit = minor(dev);
    int	rtn = 0;

    if (unit != 0) {
	if (gADBDeviceIdMap[unit].inUse != 0) {
	    if (gADBDeviceIdMap[unit].device != nil)
		gADBDeviceIdMap[unit].device =
		    [gADBDeviceIdMap[unit].device free];
	    else
		kprintf("adbServerclose(%x), adbDevice is nil\n", dev);

	    gADBDeviceIdMap[unit].inUse = 0;
	} else {
	    kprintf("adbServerclose(%x), is already closed\n", dev);
	}
    }

    kprintf("adbServerclose(%x) = %d\n", dev, rtn);
    IOSetUNIXError(rtn);

    return rtn;
}

/*
 * adbServerioctlDispatch (0x0fa0, 236 bytes with its jump islands)
 *
 * Signature derived, and it is this function that settles the other two
 * ioctl signatures.  r3, r4 and r5 are read and nothing beyond; r5 is moved
 * into r4 at 0x0fc0 and never touched again, so it is passed straight
 * through to both callees as their second argument.  The two calls are
 *
 *   0x0fd0  r3 = r30 (cmd),           r4 = data  -> adbServerIoctl
 *   0x0ffc  r3 = r29 & 0xff (minor),  r4 = data  -> ioadbDeviceIoctl
 *
 * both resolved through the relocation table, which names __TEXT,__text
 * +0x108c and +0x1278 -- the branch targets alone are jump islands.  So
 * adbServerIoctl takes (cmd, data) and ioadbDeviceIoctl takes (unit, data),
 * and neither receives dev.  data's declared type is not recoverable: it is
 * only ever a pointer that is passed on, so void * is written and the two
 * handlers cast it to the payload their command implies.
 *
 * 0x0fa0-0x0fbc  prologue; dev -> r29, cmd -> r30, data r5 -> r4.
 * 0x0fc4-0x0fc8  andi. r3, r29, 0xff sets the condition AND leaves minor()
 *                in r3 for the second call; nonzero branches to 0x0fdc.
 * 0x0fcc-0x0fd8  minor 0: adbServerIoctl(cmd, data).  This is the server's
 *                own node, so the session-management ioctls land here.
 * 0x0fdc-0x0fe8  cmd == 0xc0206102 -> 0x0ffc.
 * 0x0fec-0x0ff8  cmd == 0xc18c6103 -> 0x0ffc, anything else -> 0x1008.
 * 0x0ffc-0x1004  ioadbDeviceIoctl(minor(dev), data), r3 still holding the
 *                masked value from 0x0fc4.
 * 0x1008         rtn = 0x16 = 22 = EINVAL for every other command.
 * 0x100c-0x1020  the shared trace.
 * 0x1024-0x1028  IOSetUNIXError(rtn), again unconditional.
 * 0x102c-0x1048  epilogue returning rtn.
 *
 * Note what is NOT here: no fifth cdevsw argument, and no check that data
 * is non-NULL.  Note also that both device commands reach the same handler
 * -- the dispatcher filters on the command word and lets ioadbDeviceIoctl
 * decide what the payload means.
 */
static int
adbServerioctlDispatch(dev_t dev, int cmd, void *data)
{
    int	rtn;

    if (minor(dev) == 0)
	rtn = adbServerIoctl(cmd, data);
    else if (cmd == 0xC0206102 || cmd == 0xC18C6103)	/* both unnamed */
	rtn = ioadbDeviceIoctl(minor(dev), data);
    else
	rtn = EINVAL;

    kprintf("adbServerioctlDispatch(%x, 0x%x) = %d\n", dev, cmd, rtn);
    IOSetUNIXError(rtn);

    return rtn;
}

/*
 * adbServerIoctl (0x108c, 492 bytes with its jump islands)
 *
 * Signature derived from the one call site above: (int cmd, void *data).
 *
 * 0x108c-0x10a0  prologue: save lr and r29-r31, push an 80-byte frame.
 * 0x10a4         data -> r31.
 * 0x10a8         rtn = 0 in r30.
 * 0x10ac         a second copy of data into r29.  r31 is about to be reused
 *                as the loop counter, so this copy is real, not codegen
 *                noise -- it is the only surviving reference to the payload
 *                after 0x1108.
 * 0x10b0-0x10bc  cmd == 0xc18c6103 -> 0x11d0.
 * 0x10c0-0x10cc  cmd != 0x40546101 -> 0x1214, the shared ENXIO.
 *
 * The compare order is the evidence for a switch rather than an if chain:
 * gcc orders switch compares by value and lays the arms out in source
 * order.  As signed ints 0xc18c6103 is negative and sorts first, which is
 * the order tested; but its body is second in __text, at 0x11d0, behind the
 * 0x40546101 body at 0x10d0.  An if/else-if would have put the first-tested
 * body first.
 *
 * The 0x40546101 arm, 0x10d0-0x11cc:
 * 0x10d0-0x10e4  two traces.  The first is the only place Apple's own name
 *                for a command in this driver survives anywhere.
 * 0x10e8-0x1104  [gMapLock lock] and the trace after it.
 * 0x1108-0x1148  the free-unit search.  0x1108 sets unit = 0 in r31; 0x110c
 *                to 0x1118 is the hoisted entry test, 0x111c to 0x1128 the
 *                hoisted base and bound, and 0x112c to 0x1148 the rotated
 *                body: the i*8 index, .inUse at +4, beq to break, then the
 *                back edge testing against the gNumSessions cached in r11.
 *                0x1148 is ble-, and the entry test at 0x1118 is bgt, so
 *                the condition is unit <= gNumSessions -- one past the last
 *                session, and written as the binary has it.
 * 0x114c-0x1160  the "found unit" trace, gNumSessions reloaded from memory.
 * 0x1164-0x1170  the bound re-read a third time for the post-loop test.
 * 0x1174-0x1178  no free unit: rtn = 6 = ENXIO, straight to the unlock.
 * 0x117c-0x1190  claim it: .inUse = 1.
 * 0x1194-0x11a4  sprintf(data, "/dev/radbki%02d", unit) into the caller's
 *                84-byte buffer.  This is the whole point of the command:
 *                it hands back the path of a free minor.
 * 0x11a8-0x11b4  the trace of what was written.
 * 0x11b8-0x11cc  [gMapLock unlock] -- reached from both the ENXIO path and
 *                the success path -- then to the exit trace.
 *
 * The 0xc18c6103 arm, 0x11d0-0x1210:
 * 0x11d0-0x11d8  the payload's command word must be 1; anything else joins
 *                the ENXIO at 0x1214.  1 is the GetTable command and has no
 *                name in this tree, exactly as commands 2-9 do not.
 * 0x11dc-0x11f4  [IOADBDevice GetTable:&req->table length:&req->length].
 *                The receiver is the class, from __OBJC,__cls_refs, which
 *                is consistent with GetTable:length: being a class method.
 *                Its implementation address is 0 because it is the first
 *                function in __text, not because it has no body.
 * 0x11f8-0x11fc  req->result = the IOReturn.
 * 0x1200-0x1210  the trace; %d takes the result still live in r4 and the
 *                second takes req->length reloaded from +0x188.
 *
 * 0x1214         the shared rtn = ENXIO.
 * 0x1218-0x1224  the exit trace.
 * 0x1228-0x1244  epilogue returning rtn.  Note there is no IOSetUNIXError
 *                here: the dispatcher above makes that call once, for both
 *                handlers.
 */
static int
adbServerIoctl(int cmd, void *data)
{
    ioadb_table_request_t	*req = data;
    int				rtn = 0;
    int				unit;

    switch (cmd) {
    case 0x40546101:				/* unnamed; see above */
	kprintf("... IOADB_KERN_GETDEVICE\n");
	kprintf("... test!\n");

	[gMapLock lock];
	kprintf("..... got lock\n");

	for (unit = 0; unit <= gNumSessions; unit++)
	    if (gADBDeviceIdMap[unit].inUse == 0)
		break;

	kprintf("..... found unit: %d of %d\n", unit, gNumSessions);

	if (unit > gNumSessions) {
	    rtn = ENXIO;
	} else {
	    gADBDeviceIdMap[unit].inUse = 1;
	    sprintf(data, "/dev/radbki%02d", unit);
	    kprintf("... adbDevice = %s\n", data);
	}

	[gMapLock unlock];
	break;

    case 0xC18C6103:				/* unnamed; see above */
	if (req->command != 1) {		/* 1: unnamed */
	    rtn = ENXIO;
	    break;
	}

	req->result = [IOADBDevice GetTable:req->table
				     length:&req->length];
	kprintf("[GetTable] = %d (length = %d)\n", req->result, req->length);
	break;

    default:
	rtn = ENXIO;
	break;
    }

    kprintf("adbServerIoctl error = %d\n", rtn);

    return rtn;
}

/*
 * ioadbDeviceIoctl (0x1278, 760 bytes with its jump islands) -- the largest
 * function in this binary.
 *
 * Signature derived from adbServerioctlDispatch's call at 0x0ffc:
 * (int unit, void *data).  r3 is used only to index gADBDeviceIdMap, r4
 * only as the payload pointer.  The dispatcher has already masked r3 with
 * 0xff, so no masking happens here.
 *
 * This is a jump table, not a chain.  Every command's work is one message
 * to the IOADBDevice the unit owns, its IOReturn stored into the payload,
 * and a trace.  All eight arms and the default are covered below.
 *
 * 0x1278-0x1294  prologue: save lr and r27-r31, push a 336-byte frame.  The
 *                frame is by far the largest here because of two 128-byte
 *                character buffers; see the register arms.
 * 0x1298-0x12a4  unit -> r28, data -> r31, a copy of data into r29, and
 *                rtn = 0 in r27.  The r29 copy is used only by command 2;
 *                every other arm addresses through r31.  Both are the same
 *                pointer and the duplication is codegen, not a second
 *                variable -- unlike adbServerIoctl's, where r31 is reused.
 * 0x12a8-0x12bc  adbDevice = gADBDeviceIdMap[unit].device, i*8 again.
 * 0x12c0-0x12d0  nil: trace, then r3 = 0x16 = EINVAL loaded directly and a
 *                branch to 0x150c, past the 0x1508 that moves rtn into r3.
 *                That is an early return, not a fall-through.
 * 0x12d4-0x1304  the switch.  req->command - 2 compared unsigned against 7,
 *                so the arms are 2 through 9 with no gaps; bgt takes
 *                anything else to the default at 0x14f4.  The table is
 *                eight signed offsets at __TEXT,__const+0 (0x1a78), each
 *                relative to the table's own address, and they resolve in
 *                order to 0x1308, 0x134c, 0x1378, 0x13a0, 0x1420, 0x14a8,
 *                0x14bc and 0x14d4 -- source order, one arm per method.
 *                Command 1 is GetTable and is handled by adbServerIoctl
 *                instead; command 0 exists in neither.  None of the nine
 *                values has a name in this tree.
 *
 * 0x1308-0x1348  command 2: [adbDevice initForDevice:req->u.uniqueID
 *                result:&req->result], and the id it returns replaces the
 *                map entry -- so a failed init stores nil and the unit
 *                becomes un-ioctl-able until it is closed.  The trace's
 *                %08x is the OLD pointer, still in r30, because r30 is not
 *                reloaded; %ld and %d are reloaded from the payload.
 * 0x134c-0x1374  command 3: getADBInfo: into &req->u.deviceInfo at +0x08.
 *                0x1360's mr r4, r3 puts the IOReturn where the trace wants
 *                it before 0x1364 stores it, which is why the trace needs
 *                no reload.
 * 0x1378-0x139c  command 4: flushADBDevice, same shape.
 * 0x13a0-0x141c  command 5: readADBDeviceRegister:buffer:length: with
 *                req->u.reg.whichRegister by value, &req->u.reg.buffer and
 *                &req->u.reg.length.  Then the hex dump: 0x13c4 writes one
 *                zero byte to the buffer at sp+0x38, and 0x13d8-0x1408 is
 *                the loop, reloading the length every iteration because
 *                sprintf may alias it, and re-running strlen every
 *                iteration to find the end.  The byte is read with lbz --
 *                zero-extended, which is what a plain char is on this ABI.
 *                0x141c branches into the write arm's trailing kprintf.
 * 0x1420-0x1498  command 6: the same, with the length passed by value and a
 *                second 128-byte buffer at sp+0xb8.  Two distinct frame
 *                slots for the two dumps is the evidence that these are two
 *                block-scoped locals and not one shared buffer.  Each is
 *                128 bytes: sp+0x38 to sp+0xb7 and sp+0xb8 to sp+0x137,
 *                which together with the 0x38-byte linkage area and the
 *                five saved registers at sp+0x13c account for the whole
 *                336-byte frame exactly.  128 has no name in this tree.
 * 0x149c-0x14a4  the trace tail the two register arms share.  gcc merged
 *                the two calls' last argument, req->result; the two format
 *                strings differ, so the source has two kprintf statements.
 * 0x14a8-0x14b8  command 7: setState:mask:, state from +0x08, then into the
 *                shared tail at 0x14e4.
 * 0x14bc-0x14d0  command 8: getState.  Its result is stored at +0x08, the
 *                value word, NOT at +0x04 -- this is the one arm that does
 *                not record an IOReturn, because getState's return type is
 *                the state itself.
 * 0x14d4-0x14f0  command 9: watchState:mask:, passing &req->u.st.state.
 *                0x14e4-0x14f0 is the tail command 7 also uses: the mask
 *                from +0x0c, the send, and req->result = the IOReturn.
 * 0x14f4-0x1504  default: trace the bad command and rtn = EINVAL.
 * 0x1508         the shared r3 = rtn for all nine arms.
 * 0x150c-0x152c  epilogue.
 *
 * Nothing here validates unit against gNumSessions, and nothing checks that
 * req->u.reg.length is within IO_ADB_MAX_PACKET before the dump loop reads
 * it.  Both are absent from the binary and neither is added.
 *
 * One thing the frame does not settle: the dump index.  Both loops use r30,
 * which command 5 clobbers over adbDevice once it no longer needs it, so a
 * single function-scope counter and two block-scoped ones are
 * indistinguishable.  Function scope is written and the ambiguity recorded.
 */
static int
ioadbDeviceIoctl(int unit, void *data)
{
    ioadb_device_request_t	*req = data;
    id				adbDevice = gADBDeviceIdMap[unit].device;
    int				rtn = 0;
    int				i;

    if (adbDevice == nil) {
	kprintf("ioadbDeviceIoctl adbDevice = NULL\n");
	return EINVAL;
    }

    switch (req->command) {			/* 2-9: all unnamed */
    case 2:
	gADBDeviceIdMap[unit].device =
	    [adbDevice initForDevice:req->u.uniqueID result:&req->result];
	kprintf("[0x%08x initForDevice: %ld] = %d\n",
		adbDevice, req->u.uniqueID, req->result);
	break;

    case 3:
	req->result = [adbDevice getADBInfo:&req->u.deviceInfo];
	kprintf("[getADBInfo] = %d\n", req->result);
	break;

    case 4:
	req->result = [adbDevice flushADBDevice];
	kprintf("[flushADBDevice] = %d\n", req->result);
	break;

    case 5:
	{
	    char buf[128];			/* 128: unnamed */

	    req->result =
		[adbDevice readADBDeviceRegister:req->u.reg.whichRegister
					  buffer:req->u.reg.buffer
					  length:&req->u.reg.length];

	    buf[0] = '\0';
	    for (i = 0; i < req->u.reg.length; i++)
		sprintf(buf + strlen(buf), "%02x ", req->u.reg.buffer[i]);

	    kprintf("[readADBDeviceRegister: %d, %s] = %d\n",
		    req->u.reg.whichRegister, buf, req->result);
	}
	break;

    case 6:
	{
	    char buf[128];			/* 128: unnamed */

	    req->result =
		[adbDevice writeADBDeviceRegister:req->u.reg.whichRegister
					   buffer:req->u.reg.buffer
					   length:req->u.reg.length];

	    buf[0] = '\0';
	    for (i = 0; i < req->u.reg.length; i++)
		sprintf(buf + strlen(buf), "%02x ", req->u.reg.buffer[i]);

	    kprintf("[writeADBDeviceRegister: %d, %s] = %d\n",
		    req->u.reg.whichRegister, buf, req->result);
	}
	break;

    case 7:
	req->result = [adbDevice setState:req->u.st.state
				     mask:req->u.st.mask];
	break;

    case 8:
	req->u.st.state = [adbDevice getState];
	break;

    case 9:
	req->result = [adbDevice watchState:&req->u.st.state
				       mask:req->u.st.mask];
	break;

    default:
	kprintf("ioadbDeviceIoctl invalid command = %d\n", req->command);
	rtn = EINVAL;
	break;
    }

    return rtn;
}
