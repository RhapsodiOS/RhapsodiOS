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
 * session count.  The character-device entry points it registers --
 * adbServeropen, adbServerclose and adbServerioctlDispatch -- are C
 * functions belonging to a later task and are only declared here.
 *
 * Recovered from the binary: every selector and signature; the file-scope
 * names gADBServerMajor, gADBServerLoaded, gADBDriver, gMapLock,
 * gNumSessions and gADBDeviceIdMap, and the entry-point names
 * adbServeropen, adbServerclose and adbServerioctlDispatch (all from the
 * symbol table); the string constants; and the config-table key
 * "Maximum Sessions".
 *
 * Invented: the type name ADBDeviceIdMapEntry and its two field names, and
 * every argument and local name.
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

#import <driverkit/devsw.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <machkit/NXLock.h>
#import <bsd/dev/ppc/IOADBBus.h>

extern void kprintf(const char *, ...);
extern long strtol(const char *, char **, int);
extern int strcmp(const char *, const char *);
extern void bzero(void *, int);

/*
 * The read, write, stop, reset, select, mmap, getc and putc entry points
 * +serverMajor: registers are all this one, an external in the binary.
 */
extern int enodev();

/*
 * The three real entry points.  They are local symbols in the binary, so
 * static here.  Their argument lists are not settled by this task -- every
 * use below casts them to IOSwitchFunc, which is itself unprototyped -- so
 * they are declared without prototypes rather than with invented ones.
 */
static int adbServeropen();
static int adbServerclose();
static int adbServerioctlDispatch();

/* Invented type and field names; layout derived above. */
typedef struct {
    id		device;			/* +0x00, the IOADBDevice for the unit */
    int		inUse;			/* +0x04, nonzero once allocated */
} ADBDeviceIdMapEntry;

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
