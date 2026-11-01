/*
 * FloppyDisk.m - PPC SWIM Floppy disk device class implementation
 *
 * Main class for SWIM floppy disk devices
 */

#import "FloppyDisk.h"
#import <machkit/NXLock.h>
#import <string.h>
#import <stdio.h>

/*
 * Driver data, in the order the reference lays it out in __data and
 * __common. Values are the reference's initialisers.
 */

fd_drive_info_t fdDriveInfo = {
	{ "Sony MPX-111N", { 0, 0, 0, 0 }, 0x400, 0x10000 },
	3, 0xf, 0x20, 1
};

struct fd_disk_info fdDiskInfo[] = {
	{ FD_MID_1MB,  NUM_FD_HEADS, NUM_FD_CYL, FD_DENS_1 },
	{ FD_MID_2MB,  NUM_FD_HEADS, NUM_FD_CYL, FD_DENS_2 },
	{ FD_MID_4MB,  NUM_FD_HEADS, NUM_FD_CYL, FD_DENS_4 },
	{ FD_MID_NONE, 0,            0,          0         }
};

static struct fd_sectsize_info ssi_1mb[] = {
	{ 512,  2, 9,  0x1b, 0x54 },
	{ 1024, 3, 5,  0x35, 0x74 },
	{ 0,    0, 0,  0,    0    }
};

static struct fd_sectsize_info ssi_2mb[] = {
	{ 512,  2, 18, 0x1b, 0x65 },
	{ 0,    0, 0,  0,    0    }
};

static struct fd_sectsize_info ssi_4mb[] = {
	{ 512,  2, 36, 0x1b, 0x53 },
	{ 0,    0, 0,  0,    0    }
};

fdDensitySectsize_t fdDensitySectsize[] = {
	{ FD_DENS_1,    ssi_1mb },
	{ FD_DENS_2,    ssi_2mb },
	{ FD_DENS_4,    ssi_4mb },
	{ FD_DENS_NONE, ssi_1mb },
	{ 0,            NULL    }
};

struct fd_density_info fdDensityInfo[] = {
	{ FD_DENS_1,    0xb4000,  TRUE },
	{ FD_DENS_2,    0x168000, TRUE },
	{ FD_DENS_4,    0x2d0000, TRUE },
	{ FD_DENS_NONE, 0xb4000,  TRUE }
};

IONamedValue fdrValues[] = {
	{ FDR_SUCCESS,		"Success" },
	{ FDR_TIMEOUT,		"fd_ioreq.timeout exceeded" },
	{ FDR_MEMALLOC,		"Couldn't allocate memory" },
	{ FDR_MEMFAIL,		"Memory transfer error" },
	{ FDR_REJECT,		"Bad field in fd_ioreq" },
	{ FDR_BADDRV,		"Drive not present" },
	{ FDR_DATACRC,		"Media error - data CRC" },
	{ FDR_HDRCRC,		"Media error - header CRC" },
	{ FDR_MEDIA,		"Misc. media error" },
	{ FDR_SEEK,		"seek error" },
	{ FDR_BADPHASE,		"Unexpected controller phase change" },
	{ FDR_DRIVE_FAIL,	"Basic Drive Failure" },
	{ FDR_NOHDR,		"Header Not Found" },
	{ FDR_WRTPROT,		"Disk Write Protected" },
	{ FDR_NO_ADDRS_MK,	"Missing Address Mark" },
	{ FDR_CNTRL_MK,		"Missing Control Mark" },
	{ FDR_NO_DATA_MK,	"Missing Data Mark" },
	{ FDR_CNTRL_REJECT,	"Controller rejected command" },
	{ FDR_CNTRLR,		"Controller Handshake Error" },
	{ FDR_DMAOURUN,		"DMA Over/underrun" },
	{ FDR_VOLUNAVAIL,	"Requested Volume not available" },
	{ FDR_ALIGN,		"DMA Alignment Error" },
	{ FDR_DMA,		"DMA Error" },
	{ FDR_SPURIOUS,		"Spurious Interrupt" },
	{ 0,			NULL }
};

/* The reference names both 7 and 8 FDC_SET_DENSITY. */
IONamedValue fdOpValues[] = {
	{ FDC_IOREQ,		"FDC_IOREQ" },
	{ FDC_READ,		"FDC_READ" },
	{ FDC_WRITE,		"FDC_WRITE" },
	{ FDC_EJECT,		"FDC_EJECT" },
	{ FDC_ABORT,		"FDC_ABORT" },
	{ FDC_PROBEDISK,	"FDC_PROBEDISK" },
	{ FDC_SET_DENSITY,	"FDC_SET_DENSITY" },
	{ FDC_SET_SECTSIZE,	"FDC_SET_DENSITY" },
	{ FDC_SET_GAP,		"FDC_SET_GAP" },
	{ FDC_SET_INNER_RETRY,	"FDC_SET_INNER_RETRY" },
	{ FDC_SET_OUTER_RETRY,	"FDC_SET_OUTER_RETRY" },
	{ FDC_GET_INNER_RETRY,	"FDC_GET_INNER_RETRY" },
	{ FDC_GET_OUTER_RETRY,	"FDC_GET_OUTER_RETRY" },
	{ FDC_GET_FORMAT,	"FDC_GET_FORMAT" },
	{ FDC_GET_PHYS_PARAMS,	"FDC_GET_PHYS_PARAMS" },
	{ FDC_THREAD_ABORT,	"FDC_THREAD_ABORT" },
	{ FDC_TIMER_EVENT,	"FDC_TIMER_EVENT" },
	{ 0,			NULL }
};

IONamedValue fdCommandValues[] = {
	{ FDCMD_BAD,		"FDCMD_BAD" },
	{ FDCMD_CMD_XFR,	"FDCMD_CMD_XFR" },
	{ FDCMD_EJECT,		"FDCMD_EJECT" },
	{ FDCMD_MOTOR_ON,	"FDCMD_MOTOR_ON" },
	{ FDCMD_MOTOR_OFF,	"FDCMD_MOTOR_OFF" },
	{ FDCMD_GET_STATUS,	"FDCMD_GET_STATUS" },
	{ 0,			NULL }
};

/* The reference spells FCCMD_WRITE without its prefix. */
IONamedValue fcOpcodeValues[] = {
	{ FCCMD_READ,		"FCCMD_READ" },
	{ FCCMD_READ_DELETE,	"FCCMD_READ_DELETE" },
	{ FCCMD_WRITE,		"CMD_WRITE" },
	{ FCCMD_WRITE_DELETE,	"FCCMD_WRITE_DELETE" },
	{ FCCMD_READ_TRACK,	"FCCMD_READ_TRACK" },
	{ FCCMD_VERIFY,		"FCCMD_VERIFY" },
	{ FCCMD_VERSION,	"FCCMD_VERSION" },
	{ FCCMD_FORMAT,		"FCCMD_FORMAT" },
	{ FCCMD_RECAL,		"FCCMD_RECAL" },
	{ FCCMD_INTSTAT,	"FCCMD_INTSTAT" },
	{ FCCMD_SPECIFY,	"FCCMD_SPECIFY" },
	{ FCCMD_DRIVE_STATUS,	"FCCMD_DRIVE_STATUS" },
	{ FCCMD_SEEK,		"FCCMD_SEEK" },
	{ FCCMD_CONFIGURE,	"FCCMD_CONFIGURE" },
	{ FCCMD_DUMPREG,	"FCCMD_DUMPREG" },
	{ FCCMD_READID,		"FCCMD_READID" },
	{ FCCMD_PERPENDICULAR,	"FCCMD_PERPENDICULAR" },
	{ 0,			NULL }
};

IONamedValue densityValues[] = {
	{ FD_DENS_NONE,		"FD_DENS_NONE" },
	{ FD_DENS_1,		"FD_DENS_1" },
	{ FD_DENS_2,		"FD_DENS_2" },
	{ FD_DENS_4,		"FD_DENS_4" },
	{ 0,			NULL }
};

IONamedValue midValues[] = {
	{ FD_MID_NONE,		"FD_MID_NONE" },
	{ FD_MID_1MB,		"FD_MID_1MB" },
	{ FD_MID_2MB,		"FD_MID_2MB" },
	{ FD_MID_4MB,		"FD_MID_4MB" },
	{ 0,			NULL }
};

IONamedValue fdIoctlValues[] = {
	{ DKIOCSFORMAT,		"DKIOCSFORMAT" },
	{ DKIOCGFORMAT,		"DKIOCGFORMAT" },
	{ DKIOCGLABEL,		"DKIOCGLABEL" },
	{ DKIOCSLABEL,		"DKIOCSLABEL" },
	{ DKIOCEJECT,		"DKIOCEJECT" },
	{ FDIOCREQ,		"FDIOCREQ" },
	{ FDIOCGFORM,		"FDIOCGFORM" },
	{ FDIOCSDENS,		"FDIOCSDENS" },
	{ FDIOCSSIZE,		"FDIOCSSIZE" },
	{ FDIOCSGAPL,		"FDIOCSGAPL" },
	{ FDIOCSIRETRY,		"FDIOCSIRETRY" },
	{ FDIOCGIRETRY,		"FDIOCGIRETRY" },
	{ FDIOCSORETRY,		"FDIOCSORETRY" },
	{ FDIOCGORETRY,		"FDIOCGORETRY" },
	{ DKIOCINFO,		"DKIOCINFO" },
	{ 0,			NULL }
};

int DataSource = 1;
int busyflag = 0;
void *trackBuffer = NULL;
int FloppyState = 0;
unsigned char ReadDataPresent[2] = { 0, 0 };

int *slock;
unsigned char FloppyIdMap[2][0x4c];
int myDriveStatus;
unsigned char PrivDBDMAChannelArea[0x2c];
unsigned int GRCFloppyDMARegs;
int GRCFloppyDMAChannel;
unsigned int ccCommandsLogicalAddr;
unsigned int ccCommandsPhysicalAddr;
SonyVariables_t SonyVariables;
unsigned int theDefaultRefCon;
int MediaScanTaskID;
int track_offset;
void *other_buffer_ptr;
SWIMIIIRegs_t FloppySWIMIIIRegs;
unsigned char lastErrorsPending;
unsigned char lastSectorsPerTrack;
int driveOSEventIDptr;

/* IODevice implements these, but its header does not declare them. */
@interface IODevice(FloppyDeviceProperties)
- property_IODeviceType:(char *)types length:(unsigned *)maxLen;
@end

static Protocol *protocols[] = {
    @protocol(FloppyControllerPublic),
    nil
};

@implementation FloppyController

+ (BOOL)probe:deviceDescription
{
    donone("Probe in Floppycontroller. calling FloppyDisk probe\n");
    return [FloppyDisk probe:deviceDescription];
}

@end

@implementation FloppyDisk

+ (BOOL)probe:deviceDescription
{
    id disk = nil;
    id firstDisk = nil;
    IODevAndIdInfo *idMap;
    id controller;
    int unit;
    int drivesFound = 0;
    int rtn;

    idMap = (IODevAndIdInfo *)floppy_idmap();
    controller = [deviceDescription directDevice];
    donone("Floppy Probed \n");
    donone("FloppyDisk probe\n", 1, 2, 3, 4, 5);
    if (!drive_present())
        return NO;

    donone("Calling addCdev\n");
    if ([self addToCdevswFromDescription:deviceDescription
                                    open:(IOSwitchFunc)Fdopen
                                   close:(IOSwitchFunc)Fdclose
                                    read:(IOSwitchFunc)fdread
                                   write:(IOSwitchFunc)fdwrite
                                   ioctl:(IOSwitchFunc)fdioctl
                                    stop:(IOSwitchFunc)nulldev
                                   reset:(IOSwitchFunc)nulldev
                                  select:(IOSwitchFunc)nulldev
                                    mmap:(IOSwitchFunc)nulldev
                                    getc:(IOSwitchFunc)nulldev
                                    putc:(IOSwitchFunc)nulldev] != YES) {
        printf("FloppyDisk: could not add to cdevsw table\n");
        return NO;
    }
    donone("Calling addBdev\n");
    if ([self addToBdevswFromDescription:deviceDescription
                                    open:(IOSwitchFunc)Fdopen
                                   close:(IOSwitchFunc)Fdclose
                                strategy:(IOSwitchFunc)fdstrategy
                                   ioctl:(IOSwitchFunc)fdioctl
                                    dump:(IOSwitchFunc)nulldev
                                   psize:(IOSwitchFunc)fdsize
                                  isTape:NO] != YES) {
        printf("FloppyDisk: could not add to bdevsw table\n");
        return NO;
    }

    donone("calling fd_init_idmap\n");
    fd_init_idmap(self);
    slock = (int *)simple_lock_alloc();
    slock[0] = 0;
    slock[1] = 0;
    slock[2] = 0;
    slock[3] = 0;

    /* The reference registers the interrupt between these two messages. */
    donone("calling FloppyPluginInit\n");
    (*pmac_register_int)(0x88, 0x18, HALISRHandler, 0);
    if (FloppyPluginInit(0) != 0)
        return NO;
    donone("calling pmac_register_int\n");

    for (unit = 0; unit < 1; unit++) {
        if (disk == nil) {
            donone("allocating FloppyDisk\n");
            disk = [FloppyDisk new];
            donone("calling initResources\n");
            [disk initResources:controller];
            donone("calling setDevAndIdInfo\n");
            [disk setDevAndIdInfo:&idMap[unit]];
        }
        donone("calling floppyInit\n");
        rtn = [disk floppyInit:unit];
        donone("FloppyDisk.m: floppyInit rtn=%d\n", rtn);
        if (rtn != 0)
            continue;

        donone("fd probe: registering drive %d\n", unit, 2, 3, 4, 5);
        [disk setDeviceDescription:deviceDescription];
        donone("calling setdeviceKind\n");
        [disk setDeviceKind:"FloppyDisk"];
        donone("calling setIsPhysical\n");
        [disk setIsPhysical:YES];
        donone("calling registerDevice\n");
        [disk registerDevice];
        donone("registerDevice returned\n");
        if (firstDisk == nil)
            firstDisk = disk;
        disk = nil;
        drivesFound++;
    }
    if (disk != nil)
        [disk free];
    if (drivesFound == 0) {
        [self removeFromCdevsw];
        [self removeFromBdevsw];
    }
    donone("FloppyDisk:probe returns\n");
    return YES;
}

+ (Protocol **)requiredProtocols
{
    return protocols;
}

+ (IODeviceStyle)deviceStyle
{
    return IO_IndirectDevice;
}

- (BOOL)needsManualPolling
{
    return NO;
}

- (IOReturn)readAt:(unsigned)offset
            length:(unsigned)length
            buffer:(unsigned char *)buffer
      actualLength:(unsigned *)actualLength
            client:(vm_task_t)client
{
    IOReturn rtn;

    donone("fd read: offset 0x%x length 0x%x\n", offset, length, 3, 4, 5);
    rtn = [self deviceRwCommon:1
                         block:offset
                        length:length
                        buffer:buffer
                        client:client
                       pending:NULL
                  actualLength:actualLength];
    donone("FloppyDisk.m:ReadAt:offset=%d,len=%d,datasource=0x%x\n", offset, length, DataSource);
    donone("fd read: RETURNING %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)readAsyncAt:(unsigned)offset
                 length:(unsigned)length
                 buffer:(unsigned char *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client
{
    IOReturn rtn;

    donone("readAsyncAt\n");
    donone("fd readAsync: offset 0x%x length 0x%x\n", offset, length, 3, 4, 5);
    rtn = [self deviceRwCommon:1
                         block:offset
                        length:length
                        buffer:buffer
                        client:client
                       pending:pending
                  actualLength:NULL];
    donone("fd readAsync: RETURNING %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)writeAt:(unsigned)offset
             length:(unsigned)length
             buffer:(unsigned char *)buffer
       actualLength:(unsigned *)actualLength
             client:(vm_task_t)client
{
    IOReturn rtn;

    donone("fd write: offset 0x%x length 0x%x\n", offset, length, 3, 4, 5);
    donone("FloppyDisk.m:WriteAt:offset=%d,len=%d,datasource=0x%x\n", offset, length, DataSource);
    rtn = [self deviceRwCommon:2
                         block:offset
                        length:length
                        buffer:buffer
                        client:client
                       pending:NULL
                  actualLength:actualLength];
    donone("fd write: RETURNING %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)writeAsyncAt:(unsigned)offset
                  length:(unsigned)length
                  buffer:(unsigned char *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    IOReturn rtn;

    donone("writeAsyncAt:\n");
    donone("fd writeAsync: offset 0x%x length 0x%x\n", offset, length, 3, 4, 5);
    rtn = [self deviceRwCommon:2
                         block:offset
                        length:length
                        buffer:buffer
                        client:client
                       pending:pending
                  actualLength:NULL];
    donone("fd writeAsync: RETURNING %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdCmdXfr:(fd_ioreq_t)fdIoReq
{
    fdBuf_t *fdBuf;
    IOReturn rtn;

    donone("fdCmdXfr: command %s\n",
           IOFindNameForValue(fdIoReq->command, fdCommandValues), 2, 3, 4, 5);
    fdBuf = [self allocFdBuf:NULL];
    fdBuf->command = FDC_IOREQ;
    fdBuf->fdIoReq = fdIoReq;
    fdBuf->client = (vm_task_t)fdIoReq->map;
    fdBuf->needsDisk = 1;
    fdBuf->singleShot = 1;
    fdBuf->async = 0;
    rtn = [self enqueueFdBuf:fdBuf];
    donone("fdCmdXfr: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    [self freeFdBuf:fdBuf];
    return rtn;
}

- (IOReturn)fdSetDensity:(int)density
{
    IOReturn rtn;

    donone("fdSetDensity: density = %s\n",
           IOFindNameForValue(density, densityValues), 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_SET_DENSITY buffer:&density needsDisk:YES];
    donone("fdSetDensity: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdSetSectSize:(int)sectSize
{
    IOReturn rtn;

    donone("fdSetSectSize: sectSize = %d\n", sectSize, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_SET_SECTSIZE buffer:&sectSize needsDisk:YES];
    donone("fdSetSectSize: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdSetGapLength:(int)gapLength
{
    IOReturn rtn;

    donone("fdSetGapLength: sectSize = %d\n", gapLength, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_SET_GAP buffer:&gapLength needsDisk:YES];
    donone("fdSetGapLength: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdGetFormatInfo:(struct fd_format_info *)formatInfop
{
    IOReturn rtn;

    donone("fdGetFormatInfo\n", 1, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_GET_FORMAT buffer:formatInfop needsDisk:NO];
    donone("fdGetFormatInfo: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdSetInnerRetry:(int)count
{
    IOReturn rtn;

    donone("fdSetInnerRetry: innerRetry = %d\n", count, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_SET_INNER_RETRY buffer:&count needsDisk:NO];
    donone("fdSetInnerRetry: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdSetOuterRetry:(int)count
{
    IOReturn rtn;

    donone("fdSetOuterRetry: outerRetry = %d\n", count, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_SET_OUTER_RETRY buffer:&count needsDisk:NO];
    donone("fdSetOuterRetry: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (int)innerRetry
{
    int count;
    IOReturn rtn;

    donone("innerRetry\n", 1, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_GET_INNER_RETRY buffer:&count needsDisk:NO];
    if (rtn)
        donone("%s: FDC_GET_INNER_RETRY returned %s\n", [self name], [self stringFromReturn:rtn]);
    donone("innerRetry: returning %d\n", count, 2, 3, 4, 5);
    return count;
}

/* The reference's failure message names FDC_GET_INNER_RETRY here too. */
- (int)outerRetry
{
    int count;
    IOReturn rtn;

    donone("outerRetry\n", 1, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_GET_OUTER_RETRY buffer:&count needsDisk:NO];
    if (rtn)
        donone("%s: FDC_GET_INNER_RETRY returned %s\n", [self name], [self stringFromReturn:rtn]);
    donone("outerRetry: returning %d\n", count, 2, 3, 4, 5);
    return count;
}

- (IOReturn)fdMotorOff
{
    struct fd_ioreq ioReq;

    donone("fdMotorOff\n", 1, 2, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    ioReq.command = FDCMD_MOTOR_OFF;
    [self fdSimpleIoReq:&ioReq needsDisk:NO];
    donone("fd fdMotorOff: done\n", 1, 2, 3, 4, 5);
    return IO_R_SUCCESS;
}

- (IOReturn)ejectPhysical
{
    IOReturn rtn;

    donone("fd ejectPhysical\n", 1, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_EJECT buffer:NULL needsDisk:YES];
    donone("ejectPhysical: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)updatePhysicalParameters
{
    IOReturn rtn;

    donone("fd updatePhysicalParameters\n", 1, 2, 3, 4, 5);
    rtn = [self fdSimpleCommand:FDC_GET_PHYS_PARAMS buffer:NULL needsDisk:NO];
    donone("updatePhysicalParameters: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)deviceOpen:(unsigned)intentions
{
    return IO_R_SUCCESS;
}

- (void)deviceClose
{
}

- (IODiskReadyState)updateReadyState
{
    IODiskReadyState readyState;

    GetBusyFlag();
    ScanForDisketteChange();
    readyState = GetCurrentState();
    ResetBusyFlag();
    return readyState;
}

- (void)abortRequest
{
    donone("fd abortRequest\n", 1, 2, 3, 4, 5);
    [self fdSimpleCommand:FDC_ABORT buffer:NULL needsDisk:NO];
}

- (void)diskBecameReady
{
    donone(" fd diskBecameReady\n", 1, 2, 3, 4, 5);
    [ioQLock lock];
    [ioQLock unlockWith:1];
}

/* The reference's trace message here says diskBecameReady. */
- (IOReturn)isDiskReady:(BOOL)prompt
{
    IOReturn rtn;

    donone("fd diskBecameReady\n", 1, 2, 3, 4, 5);
    if ([self lastReadyState] == IO_Ready)
        return IO_R_SUCCESS;
    if (!prompt)
        return IO_R_NO_DISK;
    rtn = [self fdSimpleCommand:FDC_PROBEDISK buffer:NULL needsDisk:YES];
    donone("fd isDiskReady: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

IODiskReadyState GetCurrentState(void)
{
    switch (FloppyState) {
    case 1:
        return IO_Ready;
    case 0:
        return IO_NoDisk;
    case 0xff:
        return IO_Ejecting;
    default:
        return IO_NotReady;
    }
}

- property_IODeviceType:(char *)types length:(unsigned *)maxLen
{
    [super property_IODeviceType:types length:maxLen];
    strcat(types, " IOFloppy");
    return self;
}

- property_IOUnit:(char *)types length:(unsigned *)maxLen
{
    sprintf(types, "%d", [self unit]);
    return self;
}

@end

/*
 * BSD device entry points, the busy flag and the glue between the
 * FloppyDisk object and the Sony driver core.
 */

extern boolean_t test_and_set();

static struct buf *Floppy_dev[2] = { NULL, NULL };
static int fd_block_major;
static int fd_raw_major;

static unsigned fdminphys(struct buf *bp);
static id fd_dev_to_id(dev_t dev);

IOReturn fdrToIo(fd_return_t fdrCode)
{
    switch (fdrCode) {
        case FDR_SUCCESS:
            return IO_R_SUCCESS;
        case FDR_MEMALLOC:
            return IO_R_NO_MEMORY;
        case FDR_MEMFAIL:
            return IO_R_VM_FAILURE;
        case FDR_REJECT:
        case FDR_CNTRL_REJECT:
            return IO_R_UNSUPPORTED;
        case FDR_BADDRV:
            return IO_R_NO_DEVICE;
        case FDR_WRTPROT:
            return IO_R_NOT_WRITABLE;
        case FDR_VOLUNAVAIL:
            return IO_R_NO_DISK;
        case FDR_ALIGN:
            return IO_R_ALIGN;
        case FDR_DMA:
            return IO_R_DMA;
        case FDR_TIMEOUT:
        case FDR_DATACRC:
        case FDR_HDRCRC:
        case FDR_MEDIA:
        case FDR_SEEK:
        case FDR_BADPHASE:
        case FDR_DRIVE_FAIL:
        case FDR_NOHDR:
        case FDR_NO_ADDRS_MK:
        case FDR_CNTRL_MK:
        case FDR_NO_DATA_MK:
        case FDR_CNTRLR:
        case FDR_DMAOURUN:
        case FDR_SPURIOUS:
            return IO_R_IO;
        default:
            return IO_R_INTERNAL;
    }
}

/*
 * Each FloppyIdMap entry (0x4c bytes) holds the live disk object at +0,
 * per-partition objects from +4, the raw dev_t at +0x44 and the block
 * dev_t at +0x48.
 */
void fd_init_idmap(id diskClass)
{
    int i;

    fd_block_major = [diskClass blockMajor];
    fd_raw_major = [diskClass characterMajor];
    bzero(FloppyIdMap, sizeof(FloppyIdMap));
    for (i = 0; i <= 1; i++) {
        int *entry = (int *)FloppyIdMap[i];

        entry[0x44 / 4] = (fd_raw_major << 8) | (i << 3);
        entry[0x48 / 4] = (fd_block_major << 8) | (i << 3);
        Floppy_dev[i] = IOMalloc(0x80);
        Floppy_dev[i]->b_flags = 0;
    }
}

unsigned char *floppy_idmap(void)
{
    return (unsigned char *)FloppyIdMap;
}

int Fdopen(dev_t dev, int flag)
{
    id disk;
    int part;

    part = dev & 7;
    disk = fd_dev_to_id(dev);
    donone("floppy open ,dev=%d,flag=%d,diskobj=%d\n", dev, flag, disk);
    if ((minor(dev) >> 3) > 15)
        part += 8;
    if (disk == nil)
        return ENXIO;
    donone("%s: Fdopen\n", [disk name], 2, 3, 4, 5);
    if ([disk isDiskReady:((flag & FNONBLOCK) == 0)] != IO_R_SUCCESS) {
        donone("fdopen:returning ENXIO\n");
        return ENXIO;
    }
    if (part != 1) {
        if (major(dev) == fd_block_major)
            [disk setBlockDeviceOpen:YES];
        else
            [disk setRawDeviceOpen:YES];
    }
    return 0;
}

int Fdclose(dev_t dev)
{
    id disk;
    int part;

    disk = fd_dev_to_id(dev);
    part = dev & 7;
    if ((minor(dev) >> 3) > 15)
        part += 8;
    donone("floppy close ,dev=%d\n", dev);
    if (disk == nil)
        return ENXIO;
    donone("%s:fd_close\n", [disk name], 2, 3, 4, 5);
    if (part != 1) {
        if (![disk isInstanceOpen])
            return ENXIO;
        if (major(dev) == fd_block_major)
            [disk setBlockDeviceOpen:NO];
        else
            [disk setRawDeviceOpen:NO];
    }
    return 0;
}

int fdread(dev_t dev, struct uio *uio)
{
    id disk;
    int unit;

    disk = fd_dev_to_id(dev);
    unit = minor(dev) >> 3;
    if (unit > 15)
        unit -= 16;
    if (disk == nil)
        return ENXIO;
    donone("fdread %s\n", [disk name], 2, 3, 4, 5);
    if (![disk isFormatted])
        return EINVAL;
    donone("fdread:offset=%ld,len=%d,veclen=%d,blksize=%d\n",
        (long)uio->uio_offset, uio->uio_iov->iov_len, uio->uio_iovcnt,
        [disk blockSize]);
    return physio(fdstrategy, Floppy_dev[unit], dev, B_READ, fdminphys, uio,
        [disk blockSize]);
}

int fdwrite(dev_t dev, struct uio *uio)
{
    id disk;
    int unit;

    disk = fd_dev_to_id(dev);
    unit = minor(dev) >> 3;
    if (unit > 15)
        unit -= 16;
    if (disk == nil)
        return ENXIO;
    donone("fd_write %s\n", [disk name], 2, 3, 4, 5);
    if (![disk isFormatted])
        return EINVAL;
    return physio(fdstrategy, Floppy_dev[unit], dev, 0, fdminphys, uio,
        [disk blockSize]);
}

void GetBusyFlag(void)
{
    do {
        while (busyflag == 1) {
            timeout(wakeup, &busyflag, 1);
            sleep(&busyflag, PZERO);
        }
    } while (!SetBusyFlag());
}

int fdstrategy(struct buf *bp)
{
    id disk;
    vm_task_t client;
    unsigned actual;
    unsigned block, length;
    IOReturn rtn;
    int result;

    disk = fd_dev_to_id(bp->b_dev);
    actual = 0;
    bp->b_error = 0;
    bp->b_resid = bp->b_bcount;
    donone("%s: fdstrategy\n", [disk name], 2, 3, 4, 5);
    if (disk == nil) {
        donone("fdstrategy: bad unit\n", 1, 2, 3, 4, 5);
        bp->b_error = ENXIO;
        goto reject;
    }
    if ((bp->b_flags & (B_KERNSPACE | B_PHYS)) == B_PHYS)
        client = IOVmTaskForBuf(bp);
    else
        client = (vm_task_t)kernel_map;
    if ([disk blockSize] == 0) {
        donone("fdstrategy %s: zero block_size\n", [disk name], 2, 3, 4, 5);
        bp->b_error = ENXIO;
        goto reject;
    }

    block = bp->b_blkno;
    length = bp->b_bcount;
    if (bp->b_flags & B_READ) {
        donone("calling readAt offset(b_blkno)=%d,len=%d\n", block, length);
        rtn = [disk readAt:block length:length
            buffer:(unsigned char *)bp->b_un.b_addr actualLength:&actual
            client:client];
    } else {
        donone("calling writeAt offset(b_blkno)=%d,len=%d\n", block, length);
        rtn = [disk writeAt:block length:length
            buffer:(unsigned char *)bp->b_un.b_addr actualLength:&actual
            client:client];
    }
    bp->b_resid = length - actual;
    if (bp->b_resid < 0)
        bp->b_resid = 0;
    if (rtn != IO_R_SUCCESS || bp->b_resid > 0) {
        donone("Floppy:partial IO rtn=%d,result=%d,req=%d,offset=%d\n",
            rtn, actual, length, block);
        bp->b_resid = bp->b_bcount - actual;
        bp->b_flags |= B_ERROR;
        result = -1;
    } else
        result = 0;
    biodone(bp);
    return result;

reject:
    bp->b_flags |= B_ERROR;
    biodone(bp);
    donone("fdstrategy: COMMAND REJECT\n", 1, 2, 3, 4, 5);
    return -1;
}

int fdioctl(dev_t dev, u_long cmd, caddr_t data)
{
    int unit;
    id *map;
    id disk;
    int result;
    BOOL dmaRead = NO;
    void *dmaBuf = NULL;
    void *allocBuf;
    unsigned allocSize;
    struct ucred cred;
    u_short acflag;
    struct drive_info info;

    unit = minor(dev) >> 3;
    donone("fd_ioctl: cmd = %s\n", IOFindNameForValue(cmd, fdIoctlValues),
        2, 3, 4, 5);
    if (unit > 15)
        unit -= 16;
    if (unit > 1)
        return ENXIO;
    map = (id *)FloppyIdMap[unit];

    switch (cmd) {
        case DKIOCEJECT:
        case DKIOCSFORMAT:
        case DKIOCGFORMAT:
        case DKIOCGLABEL:
        case DKIOCSLABEL:
            disk = map[1];
            break;
        case FDIOCREQ:
        case FDIOCGFORM:
        case FDIOCSDENS:
        case FDIOCSSIZE:
        case FDIOCSGAPL:
        case FDIOCRRW:
        case FDIOCSIRETRY:
        case FDIOCGIRETRY:
        case FDIOCSORETRY:
        case FDIOCGORETRY:
        case FDIOCGCAPLIST:
        case DKIOCINFO:
        case DKIOCBLKSIZE:
        case DKIOCNUMBLKS:
            disk = map[0];
            break;
        default:
            donone("fd_ioctl: BAD cmd (0x%x)\n", cmd, 2, 3, 4, 5);
            return EINVAL;
    }
    if (disk == nil) {
        donone("nodev case\n");
        donone("fd_ioctl: no such device (dev = 0x%x)\n", dev, 2, 3, 4, 5);
        return ENXIO;
    }

    /* The label calls go through IODisk, which takes the busy flag itself. */
    if (cmd != DKIOCGLABEL && cmd != DKIOCSLABEL)
        GetBusyFlag();

    switch (cmd) {
        case DKIOCSFORMAT:
            [disk setFormatted:*(int *)data];
            break;

        case DKIOCGFORMAT:
            donone("IOCGFORMAT\n");
            *(int *)data = [disk isFormatted];
            break;

        case DKIOCGLABEL:
        {
            struct disk_label *label = IOMalloc(sizeof(struct disk_label));
            IOReturn rtn = [disk readLabel:label];

            donone("read disk labelret=%d\n", rtn);
            if (rtn != IO_R_SUCCESS)
                donone("read label failed,copying label anyway,irtn=%d\n", rtn);
            memcpy(data, label, sizeof(struct disk_label));
            IOFree(label, sizeof(struct disk_label));
            break;
        }

        case DKIOCSLABEL:
        {
            struct disk_label *label;

            donone("IOCSLABEL case\n");
            label = IOMalloc(sizeof(struct disk_label));
            memcpy(label, data, sizeof(struct disk_label));
            [disk writeLabel:label];
            IOFree(label, sizeof(struct disk_label));
            break;
        }

        case DKIOCINFO:
        {
            int i;

            donone("IOCINFO case\n");
            bzero(&info, sizeof(info));
            strcpy(info.di_name, [disk driveName]);
            info.di_devblklen = [disk blockSize];
            info.di_maxbcount = 0x10000;
            if (info.di_devblklen != 0) {
                unsigned labelBlocks = (sizeof(struct disk_label) +
                    info.di_devblklen - 1) / (unsigned)info.di_devblklen;

                for (i = 0; i <= 3; i++)
                    info.di_label_blkno[i] = labelBlocks * i;
            }
            donone("DKIOCINFO:blksize=%d,name=%s,labelblks=%d,%d,%d,%d\n",
                info.di_devblklen, info.di_name, info.di_label_blkno[0],
                info.di_label_blkno[1], info.di_label_blkno[2],
                info.di_label_blkno[3]);
            memcpy(data, &info, sizeof(info));
            break;
        }

        case DKIOCBLKSIZE:
            *(int *)data = [disk blockSize];
            break;

        case DKIOCNUMBLKS:
            *(int *)data = [disk diskSize];
            break;

        case DKIOCEJECT:
        {
            IOReturn rtn = [disk eject];

            if (rtn == IO_R_SUCCESS)
                FloppyPluginGotoState(0, 1);
            result = [disk errnoFromReturn:rtn];
            ResetBusyFlag();
            return result;
        }

        case FDIOCREQ:
        {
            fd_ioreq_t req = (fd_ioreq_t)data;
            caddr_t userAddrs;
            int err;

            /* Reference passes uninitialised credentials. */
            if (suser(&cred, &acflag))
                donone("FDIOCREQ:suser:error,ret=0 anyway\n");
            donone("cmdbytes=%d,statbytes=%d,bytecount=%d\n",
                req->num_cmd_bytes, req->num_stat_bytes, req->byte_count);
            if (req->byte_count != 0) {
                dmaRead = (req->flags & FD_IOF_DMA_RD) != 0;
                dmaBuf = floppyMalloc(req->byte_count, &allocBuf, &allocSize);
                if (dmaBuf == NULL) {
                    donone(" ...floppyMalloc() failed\n", 1, 2, 3, 4, 5);
                    req->status = FDR_MEMALLOC;
                    donone("ioctl:FDIOCREQ:malloc err,returning 0 anyway\n");
                    ResetBusyFlag();
                    return 0;
                }
                if (!dmaRead) {
                    int rtn = copyin(req->addrs, dmaBuf, req->byte_count);

                    if (rtn != 0) {
                        donone("   ...copyin() returned %d\n", rtn, 2, 3, 4, 5);
                        req->status = FDR_MEMFAIL;
                        goto reqDone;
                    }
                }
            }

            userAddrs = req->addrs;
            req->addrs = dmaBuf;
            req->map = kernel_map;
            err = 0;
            donone("after cmdbytes=%d,statbytes=%d,bytecount=%d\n",
                req->num_cmd_bytes, req->num_stat_bytes, req->byte_count);
            if ((req->cmd_blk[0] & 0x3f) == 0x0d) {
                struct format_data *fmt = (struct format_data *)req->addrs;

                donone("head=%d,track=%d\n", fmt->head, fmt->cylinder);
                err = FloppyFormatDisk(fmt->head, fmt->cylinder);
            }
            req->addrs = userAddrs;
            req->cmd_bytes_xfr = req->num_cmd_bytes;
            req->stat_bytes_xfr = req->num_stat_bytes;
            req->bytes_xfr = req->byte_count;
            donone("after output cmdbytes=%d,statbytes=%d,bytecount=%d\n",
                req->cmd_bytes_xfr, req->stat_bytes_xfr, req->bytes_xfr);
            if (err == 0)
                req->status = FDR_SUCCESS;
            else
                req->status = FDR_MEDIA;
            req->addrs = userAddrs;
            if (dmaRead && req->bytes_xfr != 0)
                copyout(dmaBuf, userAddrs, req->bytes_xfr);
reqDone:
            if (req->byte_count != 0)
                IOFree(allocBuf, allocSize);
            donone("at the end cmdbytes=%d,statbytes=%d,bytecount=%d\n",
                req->cmd_bytes_xfr, req->stat_bytes_xfr, req->bytes_xfr);
            break;
        }

        case FDIOCGFORM:
        {
            struct fd_format_info *formatInfo = (struct fd_format_info *)data;

            donone("ioctl:calling fdGetFormatInfo\n");
            [disk fdGetFormatInfo:formatInfo];
            FloppyFormatInfo(formatInfo);
            formatInfo->flags |= FFI_FORMATTED;
            formatInfo->sectsize_info.sect_size = 512;
            break;
        }

        case FDIOCSDENS:
        {
            unsigned density = *(unsigned *)data;

            donone("   set density = %d\n", density, 2, 3, 4, 5);
            if (density > FD_DENS_4)
                goto badArg;
            [disk fdSetDensity:density];
            if (density == FD_DENS_NONE) {
                [map[1] setFormattedInternal:NO];
                [[map[1] physicalDisk] setFormattedInternal:NO];
            }
            donone("fdioctl:IOCSDENS returns\n");
            break;
        }

        case FDIOCSSIZE:
            [disk fdSetSectSize:*(int *)data];
            [map[1] setFormattedInternal:YES];
            [[map[1] physicalDisk] setFormattedInternal:YES];
            break;

        case FDIOCSGAPL:
            [disk fdSetGapLength:*(int *)data];
            break;

        case FDIOCSIRETRY:
            [disk fdSetInnerRetry:*(int *)data];
            break;

        case FDIOCSORETRY:
            [disk fdSetOuterRetry:*(int *)data];
            break;

        case FDIOCGIRETRY:
            *(int *)data = [disk innerRetry];
            break;

        case FDIOCGORETRY:
            *(int *)data = [disk outerRetry];
            break;

        case FDIOCGCAPLIST:
        {
            unsigned size = [disk diskSize];

            ((int *)data)[0] = (size * [disk blockSize]) >> 10;
            ((int *)data)[1] = 0;
            break;
        }

        default:
            donone("fd_ioctl: BAD cmd (0x%x)\n", cmd, 2, 3, 4, 5);
badArg:
            ResetBusyFlag();
            return EINVAL;
    }

    result = 0;
    donone("fd_ioctl: returning %s (errno %d)\n",
        [disk stringFromReturn:IO_R_SUCCESS], result, 3, 4, 5);
    donone("fdioctl:returning %d\n", result);
    if (cmd != DKIOCGLABEL && cmd != DKIOCSLABEL)
        ResetBusyFlag();
    return result;
}

int fdsize(dev_t dev)
{
    id disk = fd_dev_to_id(dev);

    if (disk != nil)
        return [disk blockSize];
    donone("fdsize: bad unit\n", 1, 2, 3, 4, 5);
    return -1;
}

static unsigned fdminphys(struct buf *bp)
{
    if ((unsigned)bp->b_bcount > page_size)
        bp->b_bcount = page_size;
    return bp->b_bcount;
}

static id fd_dev_to_id(dev_t dev)
{
    int unit, part;
    id *map;

    unit = minor(dev) >> 3;
    part = dev & 7;
    if (unit > 15) {
        unit -= 16;
        part += 8;
    }
    if (unit > 1) {
        donone("fd_dev_to_id:ret nil\n");
        return nil;
    }
    map = (id *)FloppyIdMap[unit];
    if (part != 1)
        return map[part + 1];
    if (major(dev) == fd_block_major) {
        donone("fd_dev_to_id:fdblockmaj=%d\n", major(dev));
        return nil;
    }
    donone("fd_dev_to_id:retlive=0x%x\n", map[0]);
    return map[0];
}

/*
 * Allocates twice the requested size; returns NULL for more than a page.
 */
void *floppyMalloc(unsigned size, void **bufp, unsigned *sizep)
{
    unsigned allocSize = size * 2;
    void *buf;

    if (size > page_size)
        return NULL;
    buf = IOMalloc(allocSize);
    *bufp = buf;
    *sizep = allocSize;
    return buf;
}

int SetBusyFlag(void)
{
    int gotIt = 0;
    int *lock = slock;

    while (test_and_set(0, lock))
        ;
    if (busyflag == 0) {
        busyflag = 1;
        gotIt = 1;
    }
    __asm__ volatile("sync");
    *slock = 0;
    return gotIt;
}

void ResetBusyFlag(void)
{
    int *lock = slock;

    while (test_and_set(0, lock))
        ;
    busyflag = 0;
    __asm__ volatile("sync");
    *slock = 0;
}

int FloppyPluginInit(int refCon)
{
    unsigned swimBase, dmaBase;
    void *buffer;
    unsigned bufferPhys;
    int ret;

    swimBase = powermac_io_info[0x40 / 4] - powermac_io_info[1] +
        powermac_io_info[2];
    dmaBase = powermac_io_info[0x18 / 4] - powermac_io_info[1] +
        powermac_io_info[2] + (powermac_dbdma_channels[2] << 8);
    ret = kmem_alloc_wired(kernel_map, &trackBuffer, 0xb000);
    buffer = trackBuffer;
    if (ret != 0 || buffer == NULL)
        printf("bsfloppy.c:Unable to create track cache memory ");
    bufferPhys = kvtophys((unsigned)buffer);
    donone("trackbuflogic=0x%x,phys=0x%x ", buffer, bufferPhys);
    InitFormatTable();
    ret = InitializeDrive(1, swimBase, dmaBase, dmaBase, buffer, bufferPhys,
        0xb000, &myDriveStatus);
    if (ret == 0)
        *(int *)(myDriveStatus + 4) = refCon;
    return ret;
}

int FloppyPluginIO(unsigned *actualLength, unsigned length, void *buffer,
        unsigned offset, int direction, int unused)
{
    int drive;
    unsigned actual = 0;
    int err;

    err = CheckDriveNumber(1, &drive);
    if (err == 0) {
        *(int *)drive = EnterHardwareLockSection();
        *(short *)(drive + 0x0c) = 1;
        if (direction == 0)
            *(short *)(drive + 0x0e) = 2;
        if (direction == 1)
            *(short *)(drive + 0x0e) = 3;
        *(short *)(drive + 0x10) = 0;
        *(unsigned *)(drive + 0x14) = offset >> 9;
        *(unsigned *)(drive + 0x18) = (length + 511) >> 9;
        *(void **)(drive + 0x24) = buffer;
        if (*(short *)(drive + 0x0e) == 2) {
            donone("read blk=%d,count=%d\n", *(unsigned *)(drive + 0x14),
                *(unsigned *)(drive + 0x18));
            err = ReadBlocks(drive, &actual);
        } else if (*(short *)(drive + 0x0e) == 3) {
            if (*(int *)(drive + 0x38) != 0) {
                donone("wrt:call record err ");
                err = RecordError(-44);
            } else
                err = WriteBlocks(drive, &actual);
        }
        ExitHardwareLockSection(*(int *)drive);
    }
    *actualLength = actual;
    return err;
}

int FloppyPluginFlush(void)
{
    int err;

    *(int *)myDriveStatus = EnterHardwareLockSection();
    err = FlushTrackCache(myDriveStatus);
    ExitHardwareLockSection(*(int *)myDriveStatus);
    if (err == 0)
        err = 1;
    return err;
}

int FloppyPluginGotoState(int unused, unsigned state)
{
    int err = 0;

    if (state <= 1) {
        *(int *)myDriveStatus = EnterHardwareLockSection();
        err = EjectDisk(myDriveStatus);
        ExitHardwareLockSection(*(int *)myDriveStatus);
    }
    return err;
}

int FloppyRecalibrate(void)
{
    int drive;
    int err;

    err = CheckDriveNumber(1, &drive);
    if (err == 0) {
        *(int *)drive = EnterHardwareLockSection();
        RecalDrive(drive);
        ExitHardwareLockSection(*(int *)drive);
    }
    return err;
}

int FloppyFormatInfo(struct fd_format_info *formatInfo)
{
    int drive;
    int err;
    short type;
    FormatTableEntry *format;

    err = CheckDriveNumber(1, &drive);
    if (err == 0) {
        *(int *)drive = EnterHardwareLockSection();
        type = GetDisketteFormatType(drive);
        format = &SonyVariables.formatTable[type];
        formatInfo->total_sects = format->blocks;
        formatInfo->disk_info.tracks_per_cyl = format->flags & 0x0f;
        switch (type) {
            case 0:
            case 1:
            case 2:
                formatInfo->disk_info.max_density = FD_DENS_1;
                break;
            case 3:
            case 4:
                formatInfo->disk_info.max_density = FD_DENS_2;
                break;
            case 5:
                formatInfo->disk_info.max_density = FD_DENS_4;
                break;
            default:
                formatInfo->disk_info.max_density = FD_DENS_NONE;
                break;
        }
        formatInfo->disk_info.num_cylinders = (short)format->tracks;
        formatInfo->sectsize_info.sects_per_trk = format->sectorsPerTrack;
        formatInfo->sectsize_info.fmt_gap_length = format->mfmGap[2];
        ExitHardwareLockSection(*(int *)drive);
    }
    return err;
}

int FloppyFormatDisk(int head, int cylinder)
{
    int drive;
    int err;

    err = CheckDriveNumber(1, &drive);
    if (err == 0) {
        *(int *)drive = EnterHardwareLockSection();
        err = FormatDisk(head, cylinder, drive, 0);
        ExitHardwareLockSection(*(int *)drive);
    }
    return err;
}

int FloppyWriteProtected(void)
{
    int drive;

    CheckDriveNumber(1, &drive);
    return *(int *)(drive + 0x38);
}

BOOL drive_present(void)
{
    if (powermac_info[0x18 / 4] == 0)
        return YES;
    return *(unsigned char *)(powermac_io_info[2] + 0x35) == 0;
}

/*
 * DBDMA support, OS services, and the Sony driver core from
 * InitializeDrive through WriteSectorToCacheMemory.
 */

/* DBDMA command words and registers are little-endian. */
#define SWAP_LONG(x) \
    ((((unsigned)(x)) >> 24) | ((((unsigned)(x)) >> 8) & 0xff00) | \
     ((((unsigned)(x)) << 8) & 0xff0000) | (((unsigned)(x)) << 24))

/*
 * DBDMA channel area (PrivDBDMAChannelArea): +4 register base, +8 run
 * flags (4 = input), +0x14 / +0x18 command list logical / physical address.
 */

void StartDBDMA(int channel)
{
    volatile unsigned *regs = *(volatile unsigned **)(channel + 4);
    unsigned flags = *(unsigned *)(channel + 8);

    if (flags & 4)
        flags |= 1;
    else
        flags |= 2;
    *(unsigned *)(channel + 8) = flags;
    regs[0] = 0x800080;
}

void StopDBDMA(int channel)
{
    volatile unsigned *regs = *(volatile unsigned **)(channel + 4);
    unsigned flags = *(unsigned *)(channel + 8);

    if (flags & 4)
        flags &= ~1;
    else
        flags &= ~2;
    *(unsigned *)(channel + 8) = flags;
    regs[0] = 0xc8;
}

void PrepDBDMA(int channel)
{
    volatile unsigned *regs = *(volatile unsigned **)(channel + 4);

    regs[3] = SWAP_LONG(*(unsigned *)(channel + 0x18));
}

void ResetDBDMA(int channel)
{
    volatile unsigned *regs = *(volatile unsigned **)(channel + 4);

    regs[0] = 0xc8;
    *(unsigned *)(channel + 8) = 0;
    regs[3] = 0;
}

void SetDBDMAPhysicalAddress(int channel, unsigned direction,
    unsigned bufferAddress, unsigned transferSize)
{
    volatile unsigned *regs = *(volatile unsigned **)(channel + 4);
    unsigned *cmd = *(unsigned **)(channel + 0x14);
    unsigned command, lastCommand, chunk, phys;

    regs[0] = 0xc8;
    command = (direction != 0) ? 0x20000000 : 0;	/* INPUT_MORE : OUTPUT_MORE */
    lastCommand = (direction != 0) ? 0x30000000 : 0x10000000;
    *(unsigned *)(channel + 8) = (direction != 0) ? 4 : 8;
    donone("request = %d dmacounts=", transferSize);

    while (transferSize != 0) {
        chunk = page_size - bufferAddress % page_size;
        if (transferSize <= chunk)
            chunk = transferSize;
        transferSize -= chunk;
        if (transferSize == 0)
            command = lastCommand | 0x300000;
        phys = kvtophys(bufferAddress);
        cmd[0] = SWAP_LONG(command | chunk);
        cmd[1] = SWAP_LONG(kvtophys(bufferAddress));
        cmd[3] = 0;
        cmd[2] = 0;
        donone("v=0x%x,p=0x%x:%d ", bufferAddress, phys, chunk);
        bufferAddress += chunk;
        cmd += 4;
    }

    cmd[0] = 0x70;	/* STOP */
    cmd[1] = 0;
    cmd[3] = 0;
    cmd[2] = 0;
    cmd += 4;
    FlushProcessorCache(CurrentAddressSpaceID(), *(unsigned *)(channel + 0x14),
        (unsigned)cmd - *(unsigned *)(channel + 0x14));
    donone("\n");
}

/* The reference ignores logicalAddr and physicalAddr. */
int OpenDBDMAChannel(unsigned dmaBase, int *channelp, int count,
    unsigned *logicalAddr, unsigned *physicalAddr)
{
    int area = (int)PrivDBDMAChannelArea;
    int result = 0;
    unsigned *cmd;
    unsigned i;

    *channelp = area;
    if (count == 0)
        return -50;

    kmem_alloc_wired(kernel_map, (void *)(area + 0x14),
        (count * 16 - 1 + page_size) & -page_size);
    if (*(unsigned *)(area + 0x14) == 0) {
        donone("dbdmasupport.c:Unable to create DBDMA CCLs memory\n");
        result = 10;
    }
    *(unsigned *)(area + 0x18) = kvtophys(*(unsigned *)(area + 0x14));

    cmd = *(unsigned **)(area + 0x14);
    /* Reference fills the list even when the allocation failed; skip it then. */
    if (cmd != NULL) {
        for (i = 0; i < page_size >> 4; i++) {
            cmd[0] = 0x70;
            cmd[1] = 0;
            cmd[3] = 0;
            cmd[2] = 0;
            cmd += 4;
        }
    }

    if (result != 0) {
        CloseDBDMAChannel(*channelp);
    } else {
        *(unsigned *)(area + 4) = dmaBase;
        ResetDBDMA(*channelp);
    }
    return result;
}

void CloseDBDMAChannel(int channel)
{
}

void PrintDMA(int channel)
{
}

/*
 * OS services
 */

int CreateOSHardwareLockResources(void *lock)
{
    return 0;
}

int CreateOSEventResources(void *event)
{
    return 0;
}

int BSMPINotifyFamilyStoreChangedState(int drive, int newState)
{
    FloppyState = newState;
    return 0;
}

int FlushDMAedDataFromCPUCache(void)
{
    return 0;
}

int PrepareCPUCacheForDMAWrite(void)
{
    flush_cache_v((unsigned)trackBuffer, 0xb000);
    return 0;
}

int PrepareCPUCacheForDMARead(void)
{
    invalidate_cache_v((unsigned)trackBuffer, 0xb000);
    return 0;
}

int MemListDescriptorDataCopyToMemory(void *src, void *dst, unsigned len)
{
    if (DataSource == 2)
        return copyin(src, dst, len);
    bcopy(src, dst, len);
    return 0;
}

int MemListDescriptorDataCopyFromMemory(void *src, void *dst, unsigned len)
{
    if (DataSource == 2)
        return copyout(src, dst, len);
    bcopy(src, dst, len);
    return 0;
}

int MemListDescriptorDataCompare(void)
{
    return 0;
}

int MemListDescriptorDataCompareWithMemory(void *mem, void *data, int len,
    int *mismatch, int *offset)
{
    return 0;
}

void SynchronizeIO(void)
{
    __asm__ volatile("eieio");
}

short FloppyTimedSleep(int msec)
{
    int chan;

    if (msec <= 9) {
        delay(msec * 1000);
    } else {
        timeout(wakeup, &chan, (msec + 9) / 10);
        sleep(&chan, 0x16);
    }
    return 0;
}

void ExitHardwareLockSection(int s)
{
    splx(s);
}

int EnterHardwareLockSection(void)
{
    return splbio();
}

void FlushProcessorCache(int space, unsigned vaddr, unsigned len)
{
    flush_cache_v(vaddr, len);
}

int CurrentAddressSpaceID(void)
{
    return 0;
}

int SetOSEvent(unsigned *event, unsigned eventMask)
{
    *event |= eventMask;
    if (untimeout(wakeup, event))
        wakeup(event);
    else
        donone("TIMEOUT 0x%x ", eventMask);
    return 0;
}

int CancelOSEvent(unsigned *event, unsigned eventMask)
{
    *event &= ~eventMask;
    return 0;
}

BOOL WaitForOSEvent(unsigned *event, unsigned eventMask, unsigned msec, unsigned *eventsp)
{
    if (*event & eventMask) {
        *eventsp = *event;
        return YES;
    }
    timeout(wakeup, event, (msec + 9) / 10);
    sleep(event, 0x16);
    *eventsp = *event;
    return (eventMask & *event) != 0;
}

int BSBlockListDescriptorGetExtent(int list, int index,
    unsigned *startBlock, unsigned *blockCount)
{
    *startBlock = 0;
    *blockCount = 0x5000;
    return 0;
}

void donone(const char *format, ...)
{
}

void ResetBitArray(unsigned char *bits, unsigned count)
{
    short i;

    for (i = 0; (unsigned)i < count; i += 4)
        *(unsigned *)(bits + i) = 0;
}

BOOL TestBitArray(unsigned char *bits, unsigned count)
{
    unsigned any = 0;
    short i;

    for (i = 0; (unsigned)i < count; i += 4)
        any |= *(unsigned *)(bits + i);
    return any != 0;
}

/*
 * Sony driver core
 */

short InitializeDrive(short driveNum, unsigned swimBase, unsigned dmaBase,
    unsigned dmaBase2, void *trackBuffer, unsigned trackBufferPhys,
    unsigned trackBufferSize, int *drivep)
{
    int drive;
    short result;

    result = CheckDriveNumber(driveNum, drivep);
    if (result != 0)
        return result;
    drive = *drivep;
    result = CreateOSHardwareLockResources((void *)drive);
    if (result != 0)
        return result;
    result = CreateOSEventResources((void *)(drive + 8));
    if (result != 0)
        return result;

    *(int *)drive = EnterHardwareLockSection();
    *(void **)(drive + 0xb8) = trackBuffer;
    *(unsigned *)(drive + 0xbc) = trackBufferPhys;
    *(unsigned *)(drive + 0xc0) = trackBufferSize;
    /* The reference also passes dmaBase2, which HALReset does not use. */
    result = HALReset(drive, swimBase, dmaBase);
    if (result == 0) {
        *(short *)(drive + 0xc) = 0;
        *(unsigned char *)(drive + 0x3d) = 2;
        if (HALGetDriveType(drive)) {
            DumpTrackCache(drive);
            *(unsigned char *)(drive + 0x3d) = 1;
            *(unsigned char *)(drive + 0x3c) = 0;
            *(unsigned char *)(drive + 0x1c) = 0xff;
            *(int *)(drive + 0x30) = result;
            PowerDriveDown(drive, 0);
        }
    }
    ExitHardwareLockSection(*(int *)drive);
    return result;
}

void ScanForDisketteChange(void)
{
    short driveNum;
    int drive;
    int s;

    for (driveNum = 1; driveNum <= 1; driveNum++) {
        if (CheckDriveNumber(driveNum, &drive) != 0)
            continue;
        if (*(unsigned char *)(drive + 0x3d) != 1)
            continue;

        s = EnterHardwareLockSection();
        if (SonyVariables.deferredPowerDown > 0) {
            SonyVariables.deferredPowerDown--;
            if (SonyVariables.deferredPowerDown <= 0)
                PowerDriveDown(SonyVariables.deferredDrive, 0);
        } else if (*(unsigned char *)(drive + 0x3c) == 0) {
            if (HALDiskettePresence(drive) == 1) {
                *(unsigned char *)(drive + 0x3c) = 1;
                HALGetMediaType(drive);
                PowerDriveUp(drive);
                if (PostDisketteEvent(1, driveNum) != 0)
                    *(unsigned char *)(drive + 0x3c) = 0;
            }
        } else if (HALDiskettePresence(drive) == 0) {
            PostDisketteEvent(0, driveNum);
            *(unsigned char *)(drive + 0x3c) = 0;
            *(unsigned char *)(drive + 0x48) = 0;
            *(unsigned char *)(drive + 0x49) = 0;
            *(int *)(drive + 0x38) = 0;
        } else if (*(unsigned char *)(drive + 0x3c) == 0xff) {
            *(unsigned char *)(drive + 0x3c) = 0;
            PostDisketteEvent(0, driveNum);
        }
        ExitHardwareLockSection(s);
    }
}

short FormatDisk(int head, int track, int drive, short formatIndex)
{
    short minFormat, maxFormat, current;
    short result;

    if (*(int *)(drive + 0x38) != 0)
        return RecordError(-44);
    result = PowerDriveUp(drive);
    if (result != 0)
        return result;

    DumpTrackCache(drive);
    AvailableFormats(drive, &minFormat, &maxFormat, &current);
    SetDisketteFormat(drive, current);
    if (formatIndex != 0)
        SetDisketteFormat(drive, formatIndex + minFormat - 1);
    *(unsigned char *)(drive + 0x34) = 0xf6;
    RecalDrive(drive);
    GetSectorAddress(drive, 0);
    *(unsigned char *)(drive + 0x20) = track;
    *(unsigned char *)(drive + 0x21) = head;
    result = SeekDrive(drive);
    if (result == 0) {
        if (*(unsigned char *)(drive + 0x5a) != 0)
            SetSectorsPerTrack(drive);
        result = HALFormatTrack(drive);
    }
    PowerDriveDown(drive, 6);
    return result;
}

short EjectDisk(int drive)
{
    short result = 0;

    if (*(unsigned char *)(drive + 0x3c) != 0) {
        result = PowerDriveUp(drive);
        if (result == 0) {
            FlushTrackCache(drive);
            DumpTrackCache(drive);
            *(unsigned char *)(drive + 0x20) = 40;
            if (SeekDrive(drive) != 0) {
                *(unsigned char *)(drive + 0x20) = 40;
                SeekDrive(drive);
            }
            *(unsigned char *)(drive + 0x3c) = 0xff;
            result = HALEjectDiskette(drive);
        }
        PowerDriveDown(drive, 0);
    }
    return result;
}

void InitFormatTable(void)
{
    FormatTableEntry *f = SonyVariables.formatTable;

    /* GCR 400K */
    f[0].blocks = 0x320;
    f[0].flags = 0x81;
    f[0].sectorsPerTrack = 10;
    f[0].tracks = 0x50;
    f[0].sectorSize = 0x200;
    f[0].field_a = 0x2c0;
    f[0].field_c = 0;
    f[0].field_d = 2;
    f[0].field_e = 1;

    /* GCR 800K */
    f[1].blocks = 0x640;
    f[1].flags = 0x82;
    f[1].sectorsPerTrack = 10;
    f[1].tracks = 0x50;
    f[1].sectorSize = 0x200;
    f[1].field_a = 0x2c0;
    f[1].field_c = 0;
    f[1].field_d = 2;
    f[1].field_e = 1;

    /* MFM 720K */
    f[2].blocks = 0x5a0;
    f[2].flags = 0x82;
    f[2].sectorsPerTrack = 9;
    f[2].tracks = 0x50;
    f[2].sectorSize = 0x200;
    f[2].field_a = 0x200;
    f[2].field_c = 1;
    f[2].field_d = 1;
    f[2].field_e = 0;
    f[2].mfmGap[0] = 0x32;
    f[2].mfmGap[1] = 0x16;
    f[2].mfmGap[2] = 0x54;
    f[2].mfmGap[3] = 0x50;
    f[2].mfmGap[4] = 0xb6;

    /* MFM 1440K */
    f[3].blocks = 0xb40;
    f[3].flags = 0x92;
    f[3].sectorsPerTrack = 0x12;
    f[3].tracks = 0x50;
    f[3].sectorSize = 0x200;
    f[3].field_a = 0x200;
    f[3].field_c = 1;
    f[3].field_d = 1;
    f[3].field_e = 0;
    f[3].mfmGap[0] = 0x32;
    f[3].mfmGap[1] = 0x16;
    f[3].mfmGap[2] = 0x65;
    f[3].mfmGap[3] = 0x50;
    f[3].mfmGap[4] = 0xcc;

    /* MFM 1680K */
    f[4].blocks = 0xd20;
    f[4].flags = 0x92;
    f[4].sectorsPerTrack = 0x15;
    f[4].tracks = 0x50;
    f[4].sectorSize = 0x200;
    f[4].field_a = 0x200;
    f[4].field_c = 1;
    f[4].field_d = 2;
    f[4].field_e = 0;
    f[4].mfmGap[0] = 0x32;
    f[4].mfmGap[1] = 0x16;
    f[4].mfmGap[2] = 0x08;
    f[4].mfmGap[3] = 0x50;
    f[4].mfmGap[4] = 0x84;

    /* MFM 2880K; the reference leaves mfmGap[4] unset */
    f[5].blocks = 0x1680;
    f[5].flags = 0x92;
    f[5].sectorsPerTrack = 0x24;
    f[5].tracks = 0x50;
    f[5].sectorSize = 0x200;
    f[5].field_a = 0x200;
    f[5].field_c = 1;
    f[5].field_d = 1;
    f[5].field_e = 0;
    f[5].mfmGap[0] = 0x32;
    f[5].mfmGap[1] = 0x29;
    f[5].mfmGap[2] = 0x53;
    f[5].mfmGap[3] = 0x50;
}

void AvailableFormats(int drive, short *minFormat, short *maxFormat, short *current)
{
    short type;

    *minFormat = 0;
    *current = 0;
    *maxFormat = 1;
    if (*(int *)(drive + 0x40) == 1)
        *current = 1;
    if (*(unsigned char *)(drive + 0x47) != 0xff)
        return;
    *maxFormat = 2;
    if (*(unsigned char *)(drive + 0x48) != 0xff)
        return;

    type = GetDisketteFormatType(drive);
    *current = type;
    switch (type) {
    case 2:
        *minFormat = 2;
        *maxFormat = 2;
        break;
    case 3:
        *minFormat = 3;
        *maxFormat = 4;
        break;
    case 5:
        *minFormat = 5;
        *maxFormat = 5;
        break;
    }
}

/*
 * Each list entry is 8 bytes: +0 blocks, +4 flags (0x40 marks the current
 * format), +5 sectors per track, +6 tracks.
 */
short LookupFormatTable(int drive, short *count, short *minFormat, short *maxFormat,
    short *current, void *list)
{
    unsigned char *entry = list;
    FormatTableEntry *f;
    short available, i;

    if (*(unsigned char *)(drive + 0x3c) <= 1)
        return RecordError(-65);
    if (*count <= 0)
        return RecordError(-50);

    AvailableFormats(drive, minFormat, maxFormat, current);
    available = *maxFormat - *minFormat + 1;
    if (*count >= available)
        *count = available;

    for (i = *minFormat; i <= *maxFormat; i++) {
        f = &SonyVariables.formatTable[i];
        *(unsigned *)entry = f->blocks;
        entry[5] = f->sectorsPerTrack;
        *(unsigned short *)(entry + 6) = f->tracks;
        if (i == *current)
            entry[4] = f->flags | 0x40;
        else
            entry[4] = f->flags;
        entry += 8;
    }
    return 0;
}

short CheckDriveOnLine(int drive)
{
    if (*(unsigned char *)(drive + 0x3d) != 1)
        return -64;
    if (*(unsigned char *)(drive + 0x3c) == 0) {
        if (HALDiskettePresence(drive) != 1)
            return -65;
        *(unsigned char *)(drive + 0x3c) = 1;
        HALGetMediaType(drive);
    }
    return 0;
}

/*
 * Track cache: +0x60 holds the sector interleave chain, +0xa4 the per-head
 * dirty bitmap (8 bytes a head), +0xc8 the per-head (0x128 bytes) table of
 * 8-byte sector buffer address pairs that HALReadSector/HALWriteSector take
 * from +0x28/+0x2c.
 */
#define CACHE_BITS(drive, base, head, sector) \
    (*(unsigned char *)((drive) + (base) + (head) * 8 + ((sector) >> 3)))
#define SECTOR_SLOT(drive, head, sector) \
    ((drive) + (head) * 0x128 + (sector) * 8)

short ReadDiskTrackToCache(int drive)
{
    short count = *(unsigned char *)(drive + 0x51);
    int savedAddress = *(int *)(drive + 0x20);
    short retries;
    short result;
    unsigned char head, sector;

    donone("core.c:ReadDiskTrackToCache:calling HALGetNextAddressID ");
    result = HALGetNextAddressID(drive);
    if (result == 0) {
        if (*(signed char *)(drive + 0x20) != *(signed char *)(drive + 0x1c)) {
            donone("ReadDiskTrackToCache:seek error--wanttrack=%d,actual=%d ",
                *(signed char *)(drive + 0x20), *(signed char *)(drive + 0x1c));
            result = RecordError(-80);
        } else {
            donone("core.c:ReadDiskTrackToCache:calling PrepareCPUCacheForDMARead ");
            PrepareCPUCacheForDMAWrite();
            PrepareCPUCacheForDMARead();
            *(int *)(drive + 0x20) = *(int *)(drive + 0x1c);
            retries = 0;
            while (count != 0 && result == 0) {
                if (retries == 0)
                    *(unsigned char *)(drive + 0x22) =
                        *(unsigned char *)(drive + 0x60 + *(unsigned char *)(drive + 0x22));
                head = *(unsigned char *)(drive + 0x21);
                sector = *(unsigned char *)(drive + 0x22);
                if (!(CACHE_BITS(drive, 0xa4, head, sector) & (1 << (sector & 7)))) {
                    *(int *)(drive + 0x28) = *(int *)(SECTOR_SLOT(drive, head, sector) + 0xc8);
                    *(int *)(drive + 0x2c) = *(int *)(SECTOR_SLOT(drive, head, sector) + 0xcc);
                    donone("core.c:ReadDiskTrackToCache:calling HALReadSector ");
                    result = HALReadSector(drive);
                    donone("core.c:ReadDiskTrackToCache:HALReadSector returns ");
                }
                if (result == 0) {
                    retries = 0;
                    count--;
                } else {
                    if (retries > 2)
                        break;
                    retries++;
                    result = 0;
                }
            }
            FlushDMAedDataFromCPUCache();
        }
    }
    *(int *)(drive + 0x20) = savedAddress;
    return result;
}

short WriteCacheToDiskTrack(int drive)
{
    short count = *(unsigned char *)(drive + 0x51);
    int savedAddress = *(int *)(drive + 0x20);
    short retries;
    short result;
    unsigned char head, sector;
    unsigned char *data;

    donone("wrt:cachetodisktrack:call getaddr ");
    result = HALGetNextAddressID(drive);
    if (result == 0) {
        if (*(signed char *)(drive + 0x20) != *(signed char *)(drive + 0x1c)) {
            result = RecordError(-80);
        } else {
            PrepareCPUCacheForDMAWrite();
            *(int *)(drive + 0x20) = *(int *)(drive + 0x1c);
            retries = 0;
            while (count != 0 && result == 0) {
                if (retries == 0)
                    *(unsigned char *)(drive + 0x22) =
                        *(unsigned char *)(drive + 0x60 + *(unsigned char *)(drive + 0x22));
                head = *(unsigned char *)(drive + 0x21);
                sector = *(unsigned char *)(drive + 0x22);
                if (CACHE_BITS(drive, 0xa4, head, sector) & (1 << (sector & 7))) {
                    *(int *)(drive + 0x28) = *(int *)(SECTOR_SLOT(drive, head, sector) + 0xc8);
                    *(int *)(drive + 0x2c) = *(int *)(SECTOR_SLOT(drive, head, sector) + 0xcc);
                    if (*(unsigned char *)(drive + 0x5a) != 0) {
                        donone("GCR Read\n");
                        data = *(unsigned char **)(drive + 0x28);
                        result = FPYNibblizeGCRSector(drive, data, data + 0xd);
                    }
                    if (result == 0)
                        result = HALWriteSector(drive);
                }
                if (result == 0) {
                    head = *(unsigned char *)(drive + 0x21);
                    sector = *(unsigned char *)(drive + 0x22);
                    CACHE_BITS(drive, 0xa4, head, sector) &= ~(1 << (sector & 7));
                    retries = 0;
                    count--;
                } else {
                    if (retries > 2)
                        break;
                    retries++;
                    result = 0;
                }
            }
            FlushDMAedDataFromCPUCache();
        }
    }
    *(int *)(drive + 0x20) = savedAddress;
    return result;
}

short ReadSectorFromCacheMemory(int drive)
{
    unsigned char *data;
    int mismatch, offset;
    short result = 0;

    if (!TestTrackInCache(drive)) {
        donone("floppycore.c:ReadSectorFromTheCache:calling ReadDiskTrackToCache ");
        result = ReadDiskTrackToCache(drive);
        if (result != 0)
            return result;
        AssignTrackInCache(drive);
        ReadDataPresent[*(unsigned char *)(drive + 0x21)] = 1;
    } else if (ReadDataPresent[*(unsigned char *)(drive + 0x21)] == 0) {
        result = ReadDiskTrackToCache(drive);
        if (result != 0)
            return result;
        AssignTrackInCache(drive);
        ReadDataPresent[*(unsigned char *)(drive + 0x21)] = 1;
    }

    data = *(unsigned char **)(SECTOR_SLOT(drive, *(unsigned char *)(drive + 0x21),
        *(unsigned char *)(drive + 0x22)) + 0xc8);
    if (*(unsigned char *)(drive + 0x5a) != 0) {
        data += 0xd;
        result = FPYDenibblizeGCRSector(drive, data - 0xd, data);
        if (result != 0)
            return result;
    }

    if (*(unsigned short *)(drive + 0x10) & 0x40) {
        result = MemListDescriptorDataCompareWithMemory(*(void **)(drive + 0x24), data,
            *(short *)(drive + 0x54), &mismatch, &offset);
        if (result != 0 && mismatch != 0)
            result = RecordError(-68);
    } else {
        donone("floppycore.c:ReadSectorFromTheCache:copying the data srx=0x%x,tgt=0x%x size=%d ",
            data, *(int *)(drive + 0x24), *(short *)(drive + 0x54));
        result = MemListDescriptorDataCopyFromMemory(data, *(void **)(drive + 0x24),
            *(short *)(drive + 0x54));
        *(int *)(drive + 0x24) += *(short *)(drive + 0x54);
    }
    return result;
}

short WriteSectorToCacheMemory(int drive)
{
    unsigned char head, sector;
    unsigned char *data;
    short result;

    if (!TestTrackInCache(drive)) {
        AssignTrackInCache(drive);
        ReadDataPresent[*(unsigned char *)(drive + 0x21)] = 0;
    }

    head = *(unsigned char *)(drive + 0x21);
    sector = *(unsigned char *)(drive + 0x22);
    data = *(unsigned char **)(SECTOR_SLOT(drive, head, sector) + 0xc8);
    if (*(unsigned char *)(drive + 0x5a) != 0) {
        data += 0xd;
        CACHE_BITS(drive, 0x94, head, sector) |= 1 << (sector & 7);
    }

    result = MemListDescriptorDataCopyToMemory(*(void **)(drive + 0x24), data,
        *(short *)(drive + 0x54));
    if (result != 0)
        return result;
    *(int *)(drive + 0x24) += *(short *)(drive + 0x54);
    head = *(unsigned char *)(drive + 0x21);
    sector = *(unsigned char *)(drive + 0x22);
    CACHE_BITS(drive, 0xa4, head, sector) |= 1 << (sector & 7);
    return 0;
}

/*
 * Sony driver core: block I/O, drive power, formats, track cache,
 * GCR coding, seeks and the DMA channel.
 */

extern boolean_t test_and_set();

short ReadBlocks(int drive, unsigned *actualCount)
{
    short err;
    short retries;
    int lastBlock;

    donone("floppycore.c:ReadBlock:calling CheckDriveOnLine ");
    err = CheckDriveOnLine(drive);
    if (err != 0)
        goto done;
    donone("floppycore.c:ReadBlock:calling powerdriveup ");
    err = PowerDriveUp(drive);
    if (err != 0)
        goto done;
    donone("core.c:ReadBlock:PowerDriveUp returned SUCCESS ");

    lastBlock = *(int *)(drive + 0x14) + *(int *)(drive + 0x18) - 1;
    donone("lastblk=%d,firstblk=%d,blkcount=%d\n", lastBlock,
        *(int *)(drive + 0x14), *(int *)(drive + 0x18));
    if (lastBlock >= *(int *)(drive + 0x4c)) {
        donone("last block number more than MAX ");
        err = RecordError(-0x50);
    } else {
        err = 0;
        *actualCount = 0;
        donone("core.c:readblocks:firstblk=%d,lastblk=%d ", *(int *)(drive + 0x14), lastBlock);
        while (*(int *)(drive + 0x14) <= lastBlock) {
            retries = 2;
            do {
                donone("floppycore.c:ReadBlock:calling Get Sectoraddr ");
                GetSectorAddress(drive, *(unsigned short *)(drive + 0x16));
                donone("core.c:ReadBlocks:call FlushCacheAndSeek ");
                err = FlushCacheAndSeek(drive);
                if (err == 0) {
                    donone("floppycore.c:ReadBlock:calling Readsector from cache ");
                    err = ReadSectorFromCacheMemory(drive);
                    if (err == 0) {
                        *actualCount += *(short *)(drive + 0x54);
                        (*(int *)(drive + 0x14))++;
                        break;
                    }
                }
                donone("Found error,recalibrating ");
                RecalDrive(drive);
                (*(unsigned short *)(drive + 0x4a))++;
            } while (--retries != 0);
            if (err != 0)
                break;
        }
    }
    donone("core.c:Powerdowning the drive ");
    PowerDriveDown(drive, 6);
done:
    donone("core.c:returning from ReadBlocks ");
    return err;
}

short WriteBlocks(int drive, unsigned *actualCount)
{
    short err;
    short retries;
    short lastBlock;

    donone("wrt:call checkdriveonline ");
    err = CheckDriveOnLine(drive);
    if (err != 0)
        return err;
    donone("wrt:call powerup drive ");
    err = PowerDriveUp(drive);
    if (err != 0)
        return err;
    donone("wrt:powerupdrive OK\n");

    lastBlock = *(unsigned short *)(drive + 0x16) + *(unsigned short *)(drive + 0x1a) - 1;
    if (lastBlock >= *(int *)(drive + 0x4c)) {
        donone("core.c:Record error in write,firstblk=%d,lastblk=%d\n",
            *(int *)(drive + 0x14), lastBlock);
        err = RecordError(-0x50);
    } else {
        err = 0;
        *actualCount = 0;
        while (*(int *)(drive + 0x14) <= lastBlock) {
            retries = 2;
            do {
                donone("wrtblks: call getsectoraddr ");
                GetSectorAddress(drive, *(unsigned short *)(drive + 0x16));
                donone("core.c:write:calling FlushcacheAnd Seek\n");
                err = FlushCacheAndSeek(drive);
                if (err == 0) {
                    donone("wrt:calling wrttocache ");
                    err = WriteSectorToCacheMemory(drive);
                    if (err == 0) {
                        *actualCount += *(short *)(drive + 0x54);
                        (*(int *)(drive + 0x14))++;
                        break;
                    }
                }
                donone("wrtblks:call RecalDrive ");
                RecalDrive(drive);
                (*(unsigned short *)(drive + 0x4a))++;
            } while (--retries != 0);
            if (err != 0)
                break;
        }
    }
    PowerDriveDown(drive, 6);
    return err;
}

short CheckDriveNumber(short driveNum, int *drivep)
{
    int *lock;
    int drive;

    if ((unsigned)(driveNum - 1) > 1)
        return -0x38;

    lock = slock;
    while (test_and_set(0, lock) != 0)
        ;
    drive = (int)&SonyVariables.drive[driveNum - 1];
    *drivep = drive;
    *(unsigned char *)(drive + 0x46) = driveNum - 1;
    __asm__ volatile("sync");
    *slock = 0;
    return 0;
}

short PowerDriveUp(int drive)
{
    short err = 0;
    unsigned char powerState;
    unsigned char diskState;

    if (SonyVariables.deferredPowerDown != 0 && SonyVariables.deferredDrive != drive)
        PowerDriveDown(SonyVariables.deferredDrive, 0);
    SonyVariables.deferredPowerDown = 0;

    powerState = 1;
    if (*(unsigned char *)(drive + 0x44) == 0) {
        donone("core.c:PowerDriveUp:calling HALPowerUpDrive ");
        err = HALPowerUpDrive(drive);
        if (err == 0) {
            if (*(int *)(drive + 0xc) != 0x10002)
                err = FloppyTimedSleep(600);
            powerState = 2;
            diskState = *(unsigned char *)(drive + 0x3c);
            if (diskState != 0) {
                if (diskState == 1) {
                    donone("core.c:PowerDriveUp:calling GetDisketteFormat ");
                    err = GetDisketteFormat(drive);
                    if (err == 0)
                        *(unsigned char *)(drive + 0x3c) = 2;
                    donone("core.c:PowerDriveUp:return code from GetdisketteFormat=%d ", err);
                } else if (*(unsigned char *)(drive + 0x3c) == 2) {
                    err = SetDisketteFormat(drive, GetDisketteFormatType(drive));
                }
            }
        }
    }
    *(unsigned char *)(drive + 0x44) = powerState;
    donone("core.c:PowerDriveUp:return=%d ", err);
    return err;
}

void PowerDriveDown(int drive, int deferred)
{
    if (deferred == 0) {
        FlushTrackCache(drive);
        DumpTrackCache(drive);
        HALPowerDownDrive(drive);
        *(unsigned char *)(drive + 0x44) = 0;
        SonyVariables.deferredPowerDown = 0;
    } else {
        SonyVariables.deferredPowerDown = deferred;
        SonyVariables.deferredDrive = drive;
    }
}

short GetDisketteFormatType(int drive)
{
    donone("core.c:GetDisketteFormatType: ");
    if (*(unsigned char *)(drive + 0x48) == 0xff) {
        switch (*(unsigned char *)(drive + 0x49)) {
        case 0:
            return 2;
        case 0xff:
            return 3;
        case 0xfe:
            return 5;
        }
    }
    if (*(unsigned char *)(drive + 0x48) == 0 && *(unsigned char *)(drive + 0x49) == 0)
        return *(int *)(drive + 0x40) != 0;
    return 0;
}

short SetDisketteFormat(int drive, short formatIndex)
{
    donone("core.c:SetDisketteFormat: ");
    *(FormatTableEntry *)(drive + 0x4c) = SonyVariables.formatTable[formatIndex];
    donone("core.c:SetDisketteFormat:Calling SetSectorAddressBlocksize ");
    SetSectorAddressBlocksize(drive);
    *(unsigned char *)(drive + 0x20) = *(unsigned char *)(drive + 0x1c);
    donone("Core.c:SetDisketteFormat:Calling SetSectorPerTrack ");
    SetSectorsPerTrack(drive);
    donone("core.c:SetDisketteFormat:Calling HALSetFormatMode ");
    return HALSetFormatMode(drive);
}

short GetDisketteFormat(int drive)
{
    short err;

    if (*(unsigned char *)(drive + 0x47) != 0) {
        /* Try MFM first */
        *(unsigned char *)(drive + 0x48) = 0xff;
        *(int *)(drive + 0x40) = 1;
        err = SetDisketteFormat(drive, GetDisketteFormatType(drive));
        if (err == 0) {
            donone("core:GetDisketteFormat:calling RecalDrive ");
            err = RecalDrive(drive);
            if (err == 0) {
                *(unsigned char *)(drive + 0x21) = 0;
                donone("core:GetDisketteFormat:calling HALGetNextAddressID ");
                err = HALGetNextAddressID(drive);
                if (err != 0 && *(unsigned char *)(drive + 0x49) != 0)
                    err = 0;
            }
        }
        if (*(unsigned char *)(drive + 0x47) != 0
            && (*(unsigned char *)(drive + 0x49) != 0 || err == 0))
            return err;
    }

    /* GCR: single-sided, then double-sided if side 1 reads */
    *(unsigned char *)(drive + 0x48) = 0;
    *(int *)(drive + 0x40) = 0;
    donone("core:GetDisketteFormat:calling SetDisketteFormat ");
    err = SetDisketteFormat(drive, GetDisketteFormatType(drive));
    if (err != 0)
        return err;
    donone("core:GetDisketteFormat:calling RecalDrive again ");
    err = RecalDrive(drive);
    if (err != 0)
        return err;
    *(unsigned char *)(drive + 0x21) = 0;
    donone("core:GetDisketteFormat:calling HALGetNextAddressID again ");
    err = HALGetNextAddressID(drive);
    if (err != 0)
        return err;
    *(unsigned char *)(drive + 0x21) = 1;
    donone("core:GetDisketteFormat:calling HALGetNextAddressID 3rd again ");
    err = HALGetNextAddressID(drive);
    if (err != 0)
        return err;
    *(int *)(drive + 0x40) = 1;
    donone("core:calling SetDisketteFormat ");
    SetDisketteFormat(drive, GetDisketteFormatType(drive));
    return err;
}

/*
 * Link the sectors of a track in interleave order: table[sector] is the
 * sector that follows it.
 */
void BuildTrackInterleaveTable(int drive, unsigned char sectors)
{
    unsigned char *table = (unsigned char *)(drive + 0x60);
    unsigned char firstSector = *(unsigned char *)(drive + 0x58);
    unsigned char interleave = *(unsigned char *)(drive + 0x59);
    unsigned char step, next, prev, limit, count;
    unsigned wrap;

    if (interleave > 1) {
        step = (unsigned)sectors / interleave + (sectors & 1);
        next = step;
    } else {
        step = 1;
        next = 2;
    }
    limit = sectors + firstSector;
    prev = firstSector;
    wrap = sectors - ((sectors & 1) ^ 1);
    for (count = sectors - 2; count != 0xff; count--) {
        table[prev] = next;
        prev = next;
        next = prev + step;
        if (next >= limit)
            next -= wrap;
    }
    table[prev] = *(unsigned char *)(drive + 0x58);
}

void SetCacheAddresses(int drive)
{
    short head;
    short sector;
    unsigned firstSector;

    for (head = 0; head <= 1; head++) {
        for (sector = 0; sector < *(unsigned char *)(drive + 0x51); sector++) {
            firstSector = *(unsigned char *)(drive + 0x58);
            FPYComputeCacheDMAAddress(drive, head, firstSector + sector, 0,
                (unsigned *)(drive + head * 0x128 + 0xc8 + (sector + firstSector) * 8));
        }
    }
}

void SetSectorsPerTrack(int drive)
{
    unsigned char sectors;

    if (*(unsigned char *)(drive + 0x5a) != 0)
        sectors = 12 - (*(signed char *)(drive + 0x20) >> 4);
    else
        sectors = *(unsigned char *)(drive + 0x51);
    *(unsigned char *)(drive + 0x51) = sectors;
    BuildTrackInterleaveTable(drive, *(unsigned char *)(drive + 0x51));
}

void SetSectorAddressBlocksize(int drive)
{
    unsigned heads = *(unsigned char *)(drive + 0x50) & 0xf;
    int size;

    if (*(unsigned char *)(drive + 0x5a) != 0) {
        *(unsigned char *)(drive + 0x23) = (heads << 4) | *(unsigned char *)(drive + 0x59);
    } else {
        *(unsigned char *)(drive + 0x23) = 0;
        for (size = *(short *)(drive + 0x54) / 256; size != 0; size >>= 1)
            (*(unsigned char *)(drive + 0x23))++;
    }
}

void GetSectorAddress(int drive, short block)
{
    int heads = *(unsigned char *)(drive + 0x50) & 0xf;
    int zone1, zone2, zone3, zone4;
    int sectors, firstTrack, quotient;

    if (*(unsigned char *)(drive + 0x5a) != 0) {
        /* GCR: five speed zones of 16 tracks, 12 down to 8 sectors per track */
        if (heads == 0) {
            zone1 = 0xc0;
            zone2 = 0x170;
            zone3 = 0x210;
            zone4 = 0x2a0;
        } else {
            zone1 = 0x180;
            zone2 = 0x2e0;
            zone3 = 0x420;
            zone4 = 0x540;
        }
        donone("GetSectoraddress:blk=%d ", block);
        if (block < zone1) {
            sectors = 12;
            firstTrack = 0;
        } else {
            if (block < zone2) {
                sectors = 11;
                firstTrack = 0x10;
                block -= zone1;
            } else if (block < zone3) {
                sectors = 10;
                firstTrack = 0x20;
                block -= zone2;
            } else if (block < zone4) {
                sectors = 9;
                firstTrack = 0x30;
                block -= zone3;
            } else {
                sectors = 8;
                firstTrack = 0x40;
                block -= zone4;
            }
        }
        /* Reference divides by sectors * heads, which is 0 for a single-sided disk */
        *(unsigned char *)(drive + 0x20) = block / (sectors * heads) + firstTrack;
        quotient = block / sectors;
        *(unsigned char *)(drive + 0x22) = block - quotient * sectors;
        *(unsigned char *)(drive + 0x21) = quotient & 1;
        donone("GCRRead %d:%d:%d\n", (unsigned char)(quotient & 1),
            *(signed char *)(drive + 0x20), *(unsigned char *)(drive + 0x22));
    } else {
        sectors = *(unsigned char *)(drive + 0x51);
        *(unsigned char *)(drive + 0x20) = block / (sectors * heads);
        quotient = block / sectors;
        *(unsigned char *)(drive + 0x22) = block - quotient * sectors + 1;
        *(unsigned char *)(drive + 0x21) = quotient & 1;
    }
}

void DumpTrackCache(int drive)
{
    SonyVariables.cachedDrive = -1;
    *(unsigned char *)(drive + 0xb4) = 0xff;
    *(unsigned char *)(drive + 0xb5) = 0xff;
    ResetBitArray((unsigned char *)(drive + 0xa4), 0x10);
    ResetBitArray((unsigned char *)(drive + 0x94), 0x10);
    ReadDataPresent[0] = 0;
    ReadDataPresent[1] = 0;
}

short FlushTrackCache(int drive)
{
    short err = 0;
    int savedAddress;

    if (TestCacheDirtyState(drive)) {
        /* Write both sides of the cached track, then restore track/head/sector/size */
        savedAddress = *(int *)(drive + 0x20);
        *(unsigned char *)(drive + 0x20) = *(unsigned char *)(drive + 0x1c);
        *(unsigned char *)(drive + 0x21) = 0;
        if (TestCacheDirtyState(drive))
            err = WriteCacheToDiskTrack(drive);
        *(unsigned char *)(drive + 0x21) = 1;
        if (err == 0 && TestCacheDirtyState(drive))
            err = WriteCacheToDiskTrack(drive);
        *(int *)(drive + 0x20) = savedAddress;
    }
    return err;
}

BOOL TestCacheDirtyState(int drive)
{
    if (SonyVariables.cachedDrive != *(unsigned char *)(drive + 0x46))
        return NO;
    return TestBitArray((unsigned char *)(drive + 0xa4), 0x10);
}

BOOL TestTrackInCache(int drive)
{
    if (SonyVariables.cachedDrive != *(unsigned char *)(drive + 0x46))
        return NO;
    return *(signed char *)(drive + 0xb4 + *(unsigned char *)(drive + 0x21))
        == *(signed char *)(drive + 0x20);
}

void AssignTrackInCache(int drive)
{
    SonyVariables.cachedDrive = *(unsigned char *)(drive + 0x46);
    *(unsigned char *)(drive + 0xb4 + *(unsigned char *)(drive + 0x21)) =
        *(unsigned char *)(drive + 0x20);
}

/*
 * addrp[0] gets the sector's logical cache address, addrp[1] its physical
 * address, both advanced to the alignment at +0x320 and by `which'.
 */
void FPYComputeCacheDMAAddress(int drive, unsigned char head, unsigned char sector,
    int which, unsigned *addrp)
{
    unsigned short sectorSize;
    int offset;
    int align;
    unsigned pad;

    sectorSize = *(unsigned short *)(drive + 0x31a) + *(unsigned short *)(drive + 0x54)
        + *(unsigned short *)(drive + 0x31c);
    offset = *(short *)(drive + 0x318) + (sector - *(unsigned char *)(drive + 0x58)) * sectorSize
        + *(short *)(drive + 0x31a);
    if (head != 0)
        offset += *(short *)(drive + 0x318) + sectorSize * *(unsigned char *)(drive + 0x51)
            + *(short *)(drive + 0x31e);
    addrp[0] = offset + *(unsigned *)(drive + 0xb8);
    addrp[1] = offset + *(unsigned *)(drive + 0xbc);

    pad = 0;
    align = *(short *)(drive + 0x320);
    if (align > 1)
        pad = (addrp[1] & -align) + align - addrp[1];
    addrp[0] += pad + which;
    addrp[1] += pad + which;
}

/*
 * Decode GCR 6-and-2 groups (four nibbles to three bytes), updating the
 * three-byte running checksum. Returns the next nibble.
 */
unsigned char *DenibblizeGCRData(unsigned char *nibbles, unsigned char *output,
    short count, unsigned *checksum)
{
    unsigned sum0 = (*checksum >> 16) & 0xff;
    unsigned sum1 = (*checksum >> 8) & 0xff;
    unsigned sum2 = ((unsigned char *)checksum)[3];
    unsigned carry, high;
    unsigned char value;

    if (count > 0) {
        do {
            carry = sum2 >> 7;
            sum2 = (sum2 << 1) | carry;
            high = (*nibbles++ & 0x3f) << 2;

            value = ((high & 0xc0) | *nibbles++) ^ sum2;
            *output++ = value;
            carry += sum0 + value;
            sum0 = carry & 0xff;
            carry >>= 8;
            high = (high << 2) & 0xf0;

            value = ((high & 0xc0) | *nibbles++) ^ sum0;
            *output++ = value;
            carry += sum1 + value;
            sum1 = carry & 0xff;
            carry >>= 8;
            count -= 2;
            if (count <= 0)
                break;

            value = (((high << 2) & 0xc0) | *nibbles++) ^ sum1;
            *output++ = value;
            sum2 = (sum2 + carry + value) & 0xff;
        } while (--count > 0);
    }
    *checksum = (sum0 & 0xff) << 16 | (sum1 & 0xff) << 8 | (sum2 & 0xff);
    return nibbles;
}

void DenibblizeGCRChecksum(unsigned char *nibbles, unsigned *checksum)
{
    unsigned high = (nibbles[0] & 0x3f) << 2;
    unsigned sum;

    sum = (nibbles[1] | (high & 0xc0)) << 16;
    high = (high << 2) & 0xf0;
    sum |= (nibbles[2] | (high & 0xc0)) << 8;
    high = (high << 2) & 0xc0;
    sum |= nibbles[3] | high;
    *checksum = sum;
}

short FPYDenibblizeGCRSector(int drive, unsigned char *nibbles, unsigned char *output)
{
    short err = 0;
    unsigned char *bits;
    unsigned char sectorByte;
    unsigned char *tag;
    unsigned char *next;
    unsigned char *tagCopy;
    unsigned checksum, diskChecksum;

    bits = (unsigned char *)(drive + 0x94 + *(unsigned char *)(drive + 0x21) * 8
        + (*(unsigned char *)(drive + 0x22) >> 3));
    if (*bits & (1 << (*(unsigned char *)(drive + 0x22) & 7)))
        return 0;

    sectorByte = nibbles[0];
    tag = nibbles + 1;
    checksum = 0;
    next = DenibblizeGCRData(tag, tag, 12, &checksum);
    next = DenibblizeGCRData(next, output, *(unsigned short *)(drive + 0x54), &checksum);
    DenibblizeGCRChecksum(next, &diskChecksum);
    if (diskChecksum != checksum)
        err = RecordError(-0x48);

    tagCopy = *(unsigned char **)(drive + 0x30);
    if (tagCopy != 0) {
        *(unsigned short *)(tagCopy + 0) = sectorByte;
        *(unsigned *)(tagCopy + 4) = *(unsigned *)(tag + 0);
        *(unsigned short *)(tagCopy + 8) = *(unsigned short *)(tag + 4);
        *(unsigned short *)(tagCopy + 0xa) = *(unsigned short *)(tag + 6);
        *(unsigned *)(tagCopy + 0xc) = *(unsigned *)(tag + 8);
    }

    bits = (unsigned char *)(drive + 0x94 + *(unsigned char *)(drive + 0x21) * 8
        + (*(unsigned char *)(drive + 0x22) >> 3));
    *bits |= 1 << (*(unsigned char *)(drive + 0x22) & 7);
    return err;
}

/*
 * Encode bytes into GCR 6-and-2 groups (three bytes to four nibbles),
 * updating the running checksum. Returns the next nibble.
 */
unsigned char *NibblizeGCRData(unsigned char *input, unsigned char *nibbles,
    unsigned short count, unsigned *checksum)
{
    unsigned sum0 = (*checksum >> 16) & 0xff;
    unsigned sum1 = (*checksum >> 8) & 0xff;
    unsigned sum2 = ((unsigned char *)checksum)[3];
    unsigned carry;
    unsigned char value, high;
    unsigned char *highp;

    /*
     * Reference divergence: the reference rotates sum2 at the end of each
     * group and drops the carry when the call returns, so a sector with a
     * non-zero tag gets a checksum the decoder rejects. Rotate at the start
     * of each group, as DenibblizeGCRData does.
     */
    while (count != 0) {
        highp = nibbles++;

        carry = sum2 >> 7;
        sum2 = ((sum2 << 1) | carry) & 0xff;

        sum0 += *input + carry;
        value = *input++ ^ sum2;
        carry = sum0 >> 8;
        sum0 &= 0xff;
        high = (value & 0xc0) >> 2;
        *nibbles++ = value & 0x3f;

        sum1 += *input + carry;
        value = *input++ ^ sum0;
        carry = sum1 >> 8;
        sum1 &= 0xff;
        high |= (value & 0xc0) >> 4;
        *nibbles++ = value & 0x3f;

        count -= 2;
        if (count != 0) {
            sum2 = (sum2 + *input + carry) & 0xff;
            value = *input++ ^ sum1;
            high |= (value & 0xc0) >> 6;
            *nibbles++ = value & 0x3f;
            count--;
        }
        *highp = high;
    }
    *checksum = (sum0 & 0xff) << 16 | (sum1 & 0xff) << 8 | (sum2 & 0xff);
    return nibbles;
}

unsigned char *NibblizeGCRChecksum(unsigned char *nibbles, unsigned checksum)
{
    unsigned char sum0 = checksum >> 16;
    unsigned char sum1 = checksum >> 8;
    unsigned char sum2 = checksum;

    nibbles[1] = sum0 & 0x3f;
    nibbles[2] = sum1 & 0x3f;
    nibbles[3] = sum2 & 0x3f;
    nibbles[0] = ((sum0 & 0xc0) >> 2) | ((sum1 & 0xc0) >> 4) | (sum2 >> 6);
    return nibbles + 4;
}

/*
 * The sector's 12 tag bytes precede `data'. Both are first copied to the end
 * of the nibble buffer so the expanding encode can run in place.
 */
short FPYNibblizeGCRSector(int drive, unsigned char *nibbles, unsigned char *data)
{
    unsigned char *bits;
    unsigned short sectorSize;
    unsigned char *src, *dst;
    unsigned char *tag;
    unsigned char *next;
    short count;
    unsigned checksum;

    bits = (unsigned char *)(drive + 0x94 + *(unsigned char *)(drive + 0x21) * 8
        + (*(unsigned char *)(drive + 0x22) >> 3));
    if ((*bits & (1 << (*(unsigned char *)(drive + 0x22) & 7))) == 0)
        return 0;

    *nibbles++ = *(unsigned char *)(drive + 0x22);
    sectorSize = *(unsigned short *)(drive + 0x54);
    src = data + (short)sectorSize - 1;
    dst = nibbles + 0x2ba;
    for (count = sectorSize + 12; count > 0; count--)
        *dst-- = *src--;
    dst++;

    tag = *(unsigned char **)(drive + 0x30);
    if (tag == 0)
        tag = dst;
    checksum = 0;
    next = NibblizeGCRData(tag, nibbles, 12, &checksum);
    next = NibblizeGCRData(dst + 12, next, *(unsigned short *)(drive + 0x54), &checksum);
    NibblizeGCRChecksum(next, checksum);

    bits = (unsigned char *)(drive + 0x94 + *(unsigned char *)(drive + 0x21) * 8
        + (*(unsigned char *)(drive + 0x22) >> 3));
    *bits &= ~(1 << (*(unsigned char *)(drive + 0x22) & 7));
    return 0;
}

short RecalDrive(int drive)
{
    short err;

    DumpTrackCache(drive);
    *(unsigned char *)(drive + 0x20) = 0;
    donone("core.c:RecalDrive:calling SetSectorsPerTrack ");
    SetSectorsPerTrack(drive);
    donone("core.c:RecalDrive:calling HALRecalDrive ");
    err = HALRecalDrive(drive);
    if (err == 0) {
        *(unsigned char *)(drive + 0x1c) = *(unsigned char *)(drive + 0x20);
        SetCacheAddresses(drive);
    } else {
        *(unsigned char *)(drive + 0x1c) = 0xff;
    }
    donone("core.c:RecalDrive:ret=%d ", err);
    return err;
}

short SeekDrive(int drive)
{
    short err = 0;

    donone("core.c:SeekDrive:track=%d ", *(signed char *)(drive + 0x1c));
    if (*(signed char *)(drive + 0x1c) == -1)
        err = RecalDrive(drive);
    if (err == 0 && *(signed char *)(drive + 0x1c) != *(signed char *)(drive + 0x20)) {
        SetSectorsPerTrack(drive);
        donone("SeekDrive:calling HALSeekDrive ");
        err = HALSeekDrive(drive);
        if (err == 0) {
            *(unsigned char *)(drive + 0x1c) = *(unsigned char *)(drive + 0x20);
            SetCacheAddresses(drive);
        } else {
            *(unsigned char *)(drive + 0x1c) = 0xff;
        }
    }
    return err;
}

short FlushCacheAndSeek(int drive)
{
    if (*(signed char *)(drive + 0x1c) == *(signed char *)(drive + 0x20))
        return 0;
    if (TestCacheDirtyState(drive))
        FlushTrackCache(drive);
    DumpTrackCache(drive);
    return SeekDrive(drive);
}

short ResetDMAChannel(void)
{
    ResetDBDMA(GRCFloppyDMAChannel);
    PrepDBDMA(GRCFloppyDMAChannel);
    return 0;
}

short StopDMAChannel(void)
{
    StopDBDMA(GRCFloppyDMAChannel);
    return 0;
}

/*
 * direction 1 reads into `address'; anything else writes, and a 0x8000-byte
 * transfer is a track format.
 */
short StartDMAChannel(unsigned address, unsigned length, unsigned short direction)
{
    short err;

    ResetDMAChannel();
    if (direction == 1) {
        SetDBDMAPhysicalAddress(GRCFloppyDMAChannel, 1, address, length);
        SwimIIISetReadMode();
    } else {
        SetDBDMAPhysicalAddress(GRCFloppyDMAChannel, 0, address, length);
        if (length == 0x8000)
            SwimIIISetFormatMode();
        SwimIIISetWriteMode();
    }
    CancelOSEvent((unsigned *)driveOSEventIDptr, 8);
    StartDBDMA(GRCFloppyDMAChannel);
    err = WaitForEvent(1000, 8, 8);
    StopDMAChannel();
    return RecordError(err);
}

/*
 * Sony driver core, continued, and the SWIM III hardware layer.
 */

/*
 * Track format patterns. FormatGCRCacheSWIMIIIData's gap fill copies 48
 * bytes from the 6-byte self-sync pattern, so it also reads the cstring that
 * follows it in the reference; every byte past the first six is overwritten
 * by the next copy or by the first sector.
 */
static const unsigned char gcrSelfSync[48] = {
    0x3f, 0xbf, 0x1e, 0x34, 0x3c, 0x3f, 0x00, 0x00,
    'I', 'n', 'i', 't', 'i', 'a', 'l', 'i', 'z', 'i', 'n', 'g', ' ', '%',
    'd', ' ', 's', 'e', 'c', 't', 'o', 'r', 's', ' ', 'f', 'i', 'r', 's',
    't', ' ', 't', 'i', 'm', 'e', ';', 's', 'e', 't', 't', 'i'
};
static const unsigned char gcrAddressMark[3] = { 0xd5, 0xaa, 0x00 };
static const unsigned char gcrBitSlip[2] = { 0x27, 0xaa };
static const unsigned char gcrDataMark[3] = { 0xd5, 0xaa, 0x0b };
static const unsigned char trackEnd[2] = { 0x99, 0x08 };
static const unsigned char mfmIndexMark[8] = { 0x99, 0xc2, 0x99, 0xc2, 0x99, 0xc2, 0x99, 0xfc };
static const unsigned char mfmIDMark[8] = { 0x99, 0xa1, 0x99, 0xa1, 0x99, 0xa1, 0x99, 0xfe };
static const unsigned char mfmCRC[2] = { 0x99, 0x04 };
static const unsigned char mfmDataMark[8] = { 0x99, 0xa1, 0x99, 0xa1, 0x99, 0xa1, 0x99, 0xfb };
static const unsigned char mfmDataStart[2] = { 0x99, 0x0f };

short HALReset(int drive, unsigned swimBase, unsigned dmaBase)
{
    lastErrorsPending = 0;
    driveOSEventIDptr = drive + 8;

    FloppySWIMIIIRegs.data = (volatile unsigned char *)swimBase;
    FloppySWIMIIIRegs.timer = (volatile unsigned char *)(swimBase + 0x10);
    FloppySWIMIIIRegs.error = (volatile unsigned char *)(swimBase + 0x20);
    FloppySWIMIIIRegs.mode = (volatile unsigned char *)(swimBase + 0x30);
    FloppySWIMIIIRegs.select = (volatile unsigned char *)(swimBase + 0x40);
    FloppySWIMIIIRegs.setup = (volatile unsigned char *)(swimBase + 0x50);
    FloppySWIMIIIRegs.control = (volatile unsigned char *)(swimBase + 0x60);
    FloppySWIMIIIRegs.status = (volatile unsigned char *)(swimBase + 0x70);
    FloppySWIMIIIRegs.intr = (volatile unsigned char *)(swimBase + 0x80);
    FloppySWIMIIIRegs.nseek = (volatile unsigned char *)(swimBase + 0x90);
    FloppySWIMIIIRegs.ctrack = (volatile unsigned char *)(swimBase + 0xa0);
    FloppySWIMIIIRegs.csect = (volatile unsigned char *)(swimBase + 0xb0);
    FloppySWIMIIIRegs.gap3 = (volatile unsigned char *)(swimBase + 0xc0);
    FloppySWIMIIIRegs.sector = (volatile unsigned char *)(swimBase + 0xd0);
    FloppySWIMIIIRegs.nsect = (volatile unsigned char *)(swimBase + 0xe0);
    FloppySWIMIIIRegs.intrEnable = (volatile unsigned char *)(swimBase + 0xf0);

    *(short *)(drive + 0x320) = 1;
    GRCFloppyDMARegs = dmaBase;
    OpenDBDMAChannel(GRCFloppyDMARegs, &GRCFloppyDMAChannel, 1,
        &ccCommandsLogicalAddr, &ccCommandsPhysicalAddr);

    if (*(int *)(drive + 0xb8) == 0) {
        *(int *)(drive + 0xbc) = 0;
        *(int *)(drive + 0xb8) = 0;
        *(int *)(drive + 0xc0) = 0;
    }
    *(int *)(drive + 0xc4) = 0;

    *FloppySWIMIIIRegs.control = ~*FloppySWIMIIIRegs.control;
    SynchronizeIO();
    *FloppySWIMIIIRegs.setup = 0x20;
    SynchronizeIO();
    return 0;
}

short RecordError(short error)
{
    return error;
}

int PostDisketteEvent(unsigned char newState, short driveNum)
{
    return BSMPINotifyFamilyStoreChangedState(
        *(int *)((int)&SonyVariables.drive[driveNum - 1] + 4), newState);
}

void MediaScanTask(void)
{
    while (1) {
        ScanForDisketteChange();
        FloppyTimedSleep(500);
    }
}

short LaunchMediaScanTask(void)
{
    MediaScanTaskID = (int)kernel_thread(kernel_task, MediaScanTask);
    return 0;
}

short KillMediaScanTask(void)
{
    return 0;
}

short SleepUntilReady(int msec)
{
    short result = 0;
    short tries;

    FloppyTimedSleep(msec);
    for (tries = 999; tries != -1; tries--) {
        if (SwimIIISenseSignal(0xfe) == 0)
            break;
        FloppyTimedSleep(1);
    }
    /* Reference tests 0, so running out of tries (-1) is not reported. */
    if (tries == 0)
        result = RecordError(-1);
    return result;
}

short WaitForEvent(int msec, unsigned char controlBits, unsigned char intrMask)
{
    short result = -66;
    unsigned events;

    lastErrorsPending = 0;
    events = *FloppySWIMIIIRegs.intr;		/* clears pending interrupts */
    SynchronizeIO();
    *FloppySWIMIIIRegs.intrEnable = intrMask;
    SynchronizeIO();
    *FloppySWIMIIIRegs.status = controlBits | 1;
    SynchronizeIO();

    if (!WaitForOSEvent((unsigned *)driveOSEventIDptr, intrMask, msec, &events)) {
        *FloppySWIMIIIRegs.control = controlBits;
        SynchronizeIO();
    } else if (events != 0) {
        if (lastErrorsPending == 0) {
            if (intrMask & events) {
                *FloppySWIMIIIRegs.control = controlBits;
                SynchronizeIO();
                result = 0;
            }
        } else {
            *FloppySWIMIIIRegs.control = controlBits;
            SynchronizeIO();
            if (lastErrorsPending & 0x40)
                result = -69;
            else if (lastErrorsPending & 0x80)
                result = -72;
            else if (lastErrorsPending & 5)
                result = -74;
            else
                result = -67;
        }
    }
    return result;
}

void ByteMove(const void *src, void *dst, int count)
{
    const unsigned char *from = src;
    unsigned char *to = dst;

    for (; count > 0; count--)
        *to++ = *from++;
}

void FormatGCRCacheSWIMIIIData(int drive)
{
    unsigned char *p = *(unsigned char **)(drive + 0xb8);
    unsigned char *sect;
    unsigned side = 0;
    unsigned sector;
    unsigned char check, sideTrack;
    int i, pad, align;

    do {
        if (lastSectorsPerTrack == *(unsigned char *)(drive + 0x51)) {
            /* Layout already built: only the address fields change. */
            lastSectorsPerTrack = *(unsigned char *)(drive + 0x51);
            sect = p;
            donone("Initializing %d sectors subsequent time\n", *(unsigned char *)(drive + 0x51));
            for (sector = 0; sector < *(unsigned char *)(drive + 0x51); sector++) {
                sect[0x33] = *(unsigned char *)(drive + 0x20) & 0x3f;
                sect[0x34] = sector;
                check = sect[0x33] ^ sector;
                sideTrack = (side << 5) | (*(unsigned char *)(drive + 0x20) & 0xc0);
                sect[0x35] = sideTrack;
                check ^= sideTrack;
                sect[0x36] = *(unsigned char *)(drive + 0x23);
                sect[0x37] = sect[0x36] ^ check;
                sect += 0x30c;
            }
            p = sect + 0x4b6;
            donone("second pass track length =%d for side=%d\n",
                p - *(unsigned char **)(drive + 0xb8), side);
        } else {
            for (i = 0; i <= 199; i++) {
                ByteMove(gcrSelfSync, p, 48);
                p += 6;
            }
            donone("Initializing %d sectors first time;setting to 12\n", *(unsigned char *)(drive + 0x51));
            *(unsigned char *)(drive + 0x51) = 12;
            sect = p;
            sector = 0;
            do {
                pad = 0;
                align = *(short *)(drive + 0x320);
                if (align > 1)
                    pad = (((unsigned)(sect + 0x49) & -align) + align - 0x49) - (unsigned)sect;
                for (i = 0; i <= 7; i++)
                    ByteMove(gcrSelfSync, sect + i * 6, 6);
                ByteMove(gcrAddressMark, sect + 0x30, 3);
                sect[0x33] = *(unsigned char *)(drive + 0x20) & 0x3f;
                sect[0x34] = sector;
                check = sect[0x33] ^ sector;
                sideTrack = (side << 5) | (*(unsigned char *)(drive + 0x20) & 0xc0);
                sect[0x35] = sideTrack;
                check ^= sideTrack;
                sect[0x36] = *(unsigned char *)(drive + 0x23);
                sect[0x37] = sect[0x36] ^ check;
                ByteMove(gcrBitSlip, sect + 0x38, 2);
                ByteMove(gcrSelfSync, sect + 0x3a, 6);
                ByteMove(sect + 0x3a, sect + 0x40, pad);
                sect += pad;
                ByteMove(gcrSelfSync, sect + 0x40, 6);
                ByteMove(gcrDataMark, sect + 0x46, 3);
                sect[0x49] = sector;
                sect[0x4a] = 0;
                ByteMove(sect + 0x4a, sect + 0x4b, 15);
                sect[0x5a] = *(unsigned char *)(drive + 0x34);
                ByteMove(sect + 0x5a, sect + 0x5b, 0x2aa);
                ByteMove(gcrBitSlip, sect + 0x309, 2);
                ByteMove(gcrSelfSync, sect + 0x30b, 1);
                sect = sect + 0x30c - pad;
                sector++;
            } while (sector < *(unsigned char *)(drive + 0x51));
            p = sect;
            for (i = 0; i <= 3; i++)
                *p++ = 0x3f;
            ByteMove(trackEnd, p, 2);
            p += 2;
            donone("first pass track length =%d for side=%d\n",
                p - *(unsigned char **)(drive + 0xb8), side);
        }
        if (side == 0)
            track_offset = p - *(unsigned char **)(drive + 0xb8);
        if (*(int *)(drive + 0x40) == 0)
            side = 3;
        else
            side++;
    } while (side <= 1);
}

void FormatMFMCacheSWIMIIIData(int drive)
{
    unsigned char *p = *(unsigned char **)(drive + 0xb8);
    unsigned side = 0;
    unsigned sector;
    int pad, align;
    unsigned char *field;

    do {
        if (lastSectorsPerTrack == *(unsigned char *)(drive + 0x51)) {
            /* Layout already built: only the ID fields change. */
            lastSectorsPerTrack = *(unsigned char *)(drive + 0x51);
            p += *(unsigned char *)(drive + 0x5e) + *(unsigned char *)(drive + 0x5b) + 20;
            for (sector = 1; sector <= *(unsigned char *)(drive + 0x51); sector++) {
                p += 20;
                p[0] = *(unsigned char *)(drive + 0x20);
                p[1] = side;
                p[2] = sector;
                p[3] = *(unsigned char *)(drive + 0x23);
                p += 4;
                p += *(unsigned char *)(drive + 0x5c) + *(short *)(drive + 0x54) + 24
                    + *(unsigned char *)(drive + 0x5d) + 2;
            }
            p += *(unsigned char *)(drive + 0x5f) + 2;
        } else {
            *p = 0x4e;
            ByteMove(p, p + 1, *(unsigned char *)(drive + 0x5e) - 1);
            p += *(unsigned char *)(drive + 0x5e);
            *p = 0;
            ByteMove(p, p + 1, 11);
            p += 12;
            ByteMove(mfmIndexMark, p, 8);
            p += 8;
            *p = 0x4e;
            ByteMove(p, p + 1, *(unsigned char *)(drive + 0x5b) - 1);
            p += *(unsigned char *)(drive + 0x5b);

            for (sector = 1; sector <= *(unsigned char *)(drive + 0x51); sector++) {
                field = p + *(short *)(drive + 0x31a);
                pad = 0;
                align = *(short *)(drive + 0x320);
                if (align > 1)
                    pad = (((unsigned)field & -align) + align) - (unsigned)field;

                *p = 0;
                ByteMove(p, p + 1, 11);
                p += 12;
                ByteMove(mfmIDMark, p, 8);
                p += 8;
                p[0] = *(unsigned char *)(drive + 0x20);
                p[1] = side;
                p[2] = sector;
                p[3] = *(unsigned char *)(drive + 0x23);
                p += 4;
                ByteMove(mfmCRC, p, 2);
                p += 2;
                *p = 0x4e;
                ByteMove(p, p + 1, *(unsigned char *)(drive + 0x5c) + pad - 1);
                p += *(unsigned char *)(drive + 0x5c) + pad;

                *p = 0;
                ByteMove(p, p + 1, 11);
                p += 12;
                ByteMove(mfmDataMark, p, 8);
                p += 8;
                ByteMove(mfmDataStart, p, 2);
                p += 2;
                *p = *(unsigned char *)(drive + 0x34);
                ByteMove(p, p + 1, *(short *)(drive + 0x54) - 1);
                p += *(short *)(drive + 0x54);
                ByteMove(mfmCRC, p, 2);
                p += 2;
                *p = 0x4e;
                ByteMove(p, p + 1, *(unsigned char *)(drive + 0x5d) - (pad + 1));
                p += *(unsigned char *)(drive + 0x5d) - pad;
            }

            *p = 0x4e;
            ByteMove(p, p + 1, *(unsigned char *)(drive + 0x5f) - 1);
            p += *(unsigned char *)(drive + 0x5f);
            ByteMove(trackEnd, p, 2);
            p += 2;
            if (side == 0)
                track_offset = p - *(unsigned char **)(drive + 0xb8);
        }
        if (*(int *)(drive + 0x40) == 0)
            side = 3;
        else
            side++;
    } while (side <= 1);
}

void SwimIIISmallWait(unsigned short ticks)
{
    *FloppySWIMIIIRegs.timer = ticks + 1;
    SynchronizeIO();
    while (*FloppySWIMIIIRegs.timer != 0)
        SynchronizeIO();
}

short SwimIIITimeOut(unsigned *timeoutp)
{
    if (*timeoutp == 0)
        return 1;
    if (*timeoutp > 5) {
        FloppyTimedSleep(5);
        *timeoutp -= 5;
    } else {
        FloppyTimedSleep(5);
        *timeoutp = 0;
    }
    return 0;
}

void SwimIIIAddrSignal(unsigned char signal)
{
    *FloppySWIMIIIRegs.select = 0xf3;
    SynchronizeIO();
    if (signal & 8)
        *FloppySWIMIIIRegs.status = 0x20;
    else
        *FloppySWIMIIIRegs.control = 0x20;
    SynchronizeIO();
    *FloppySWIMIIIRegs.select = signal & 0xf7;
    SynchronizeIO();
}

BOOL SwimIIISenseSignal(unsigned char signal)
{
    BOOL sense;

    SwimIIIAddrSignal(signal);
    sense = (*FloppySWIMIIIRegs.status >> 3) & 1;
    SynchronizeIO();
    return sense;
}

void SwimIIISetSignal(unsigned char signal)
{
    SwimIIIAddrSignal(signal);
    *FloppySWIMIIIRegs.select |= 8;
    SynchronizeIO();
    SwimIIISmallWait(1);
    *FloppySWIMIIIRegs.select &= 0xf7;
    SynchronizeIO();
}

void SwimIIIHeadSelect(short head)
{
    delay(500);
    SwimIIISenseSignal(head != 0 ? 0xfc : 0xf4);
}

void SwimIIIDiskSelect(int drive)
{
    if (*(unsigned char *)(drive + 0x46) == 0) {
        *FloppySWIMIIIRegs.control = 4;
        SynchronizeIO();
        *FloppySWIMIIIRegs.status = 2;
    } else {
        *FloppySWIMIIIRegs.control = 2;
        SynchronizeIO();
        *FloppySWIMIIIRegs.status = 4;
    }
    SynchronizeIO();
}

short SwimIIIStepDrive(short steps)
{
    if (steps == 0)
        return 0;
    if (steps < 0) {
        SwimIIISetSignal(0xf4);
        steps = -steps;
    } else {
        SwimIIISetSignal(0xf0);
    }
    SwimIIISmallWait(1);
    CancelOSEvent((unsigned *)driveOSEventIDptr, 2);
    SwimIIIAddrSignal(0xf1);
    *FloppySWIMIIIRegs.nseek = steps;
    SynchronizeIO();
    if (WaitForEvent(10000, 0x80, 2) != 0)
        return -75;
    return 0;
}

void SwimIIIDisableRWMode(void)
{
    *FloppySWIMIIIRegs.control = 0x18;
    SynchronizeIO();
}

/* The error and intr reads below clear those registers. */
void SwimIIISetReadMode(void)
{
    SwimIIIDisableRWMode();
    (void)*FloppySWIMIIIRegs.error;
    SynchronizeIO();
    SwimIIIDisableRWMode();
    *FloppySWIMIIIRegs.control = 0x10;
    SynchronizeIO();
    (void)*FloppySWIMIIIRegs.intr;
    SynchronizeIO();
}

void SwimIIISetWriteMode(void)
{
    SwimIIIDisableRWMode();
    (void)*FloppySWIMIIIRegs.error;
    SynchronizeIO();
    SwimIIIDisableRWMode();
    *FloppySWIMIIIRegs.status = 0x10;
    SynchronizeIO();
    (void)*FloppySWIMIIIRegs.intr;
    SynchronizeIO();
}

void SwimIIISetFormatMode(void)
{
    (void)*FloppySWIMIIIRegs.error;
    SynchronizeIO();
    *FloppySWIMIIIRegs.control = 8;
    SynchronizeIO();
    *FloppySWIMIIIRegs.status = 0x40;
    SynchronizeIO();
    (void)*FloppySWIMIIIRegs.intr;
    SynchronizeIO();
}

void HALISR_DMA(void)
{
}

void HALISRHandler(void)
{
    unsigned char pending;

    pending = *FloppySWIMIIIRegs.intr;
    SynchronizeIO();
    if (pending == 0) {
        donone("HALISR: Pending interrupt is ZERO ");
        return;
    }
    *FloppySWIMIIIRegs.intrEnable = 0;
    SynchronizeIO();
    *FloppySWIMIIIRegs.control = 1;
    SynchronizeIO();
    SetOSEvent((unsigned *)driveOSEventIDptr, pending);
    if (pending & 0x20) {
        lastErrorsPending = *FloppySWIMIIIRegs.error;
        SynchronizeIO();
    }
}

short HALSetFormatMode(int drive)
{
    unsigned char signal;

    *(unsigned char *)(drive + 0x45) = 0xfd;
    if (*(unsigned char *)(drive + 0x48) == 0) {
        *(short *)(drive + 0x318) = 0;
        *(short *)(drive + 0x31a) = 31;
        *(short *)(drive + 0x31c) = *(unsigned short *)(drive + 0x56)
            - *(unsigned short *)(drive + 0x54) + 31;
        *(short *)(drive + 0x31e) = 2;
        lastSectorsPerTrack = 0xff;
        FormatGCRCacheSWIMIIIData(drive);
        *FloppySWIMIIIRegs.setup = 0x4c;
        SynchronizeIO();
        *FloppySWIMIIIRegs.control = ~*FloppySWIMIIIRegs.control;
        SynchronizeIO();
        *FloppySWIMIIIRegs.mode = 0x88;
        SynchronizeIO();
        signal = 0xfd;
    } else {
        *(short *)(drive + 0x318) = *(unsigned char *)(drive + 0x5b)
            + *(unsigned char *)(drive + 0x5e) + 20;
        *(short *)(drive + 0x31a) = *(unsigned char *)(drive + 0x5c) + 48;
        *(short *)(drive + 0x31c) = *(unsigned char *)(drive + 0x5d) + 2;
        *(short *)(drive + 0x31e) = *(unsigned char *)(drive + 0x5f) + 2;
        lastSectorsPerTrack = 0xff;
        FormatMFMCacheSWIMIIIData(drive);
        if (*(unsigned char *)(drive + 0x49) == 0xfe)
            *FloppySWIMIIIRegs.setup = 0x20;
        else
            *FloppySWIMIIIRegs.setup = 0x28;
        SynchronizeIO();
        *FloppySWIMIIIRegs.control = ~*FloppySWIMIIIRegs.control;
        SynchronizeIO();
        *FloppySWIMIIIRegs.mode = 0x95;
        SynchronizeIO();
        signal = 0xf9;
    }
    SwimIIISetSignal(signal);
    return SleepUntilReady(30);
}

BOOL HALDiskettePresence(int drive)
{
    SwimIIIDiskSelect(drive);
    *(int *)(drive + 0x38) = 0;
    if (SwimIIISenseSignal(0xf9) == 0)
        *(int *)(drive + 0x38) = 1;
    return SwimIIISenseSignal(0xf8) == 0;
}

void HALGetMediaType(int drive)
{
    *(unsigned char *)(drive + 0x48) = 0;
    *(unsigned char *)(drive + 0x49) = 0;
    if (SwimIIISenseSignal(0xf5) == 0)
        return;
    if (SwimIIISenseSignal(0xff) != 0) {
        *(unsigned char *)(drive + 0x48) = 0xff;
        *(unsigned char *)(drive + 0x49) = 0;
    } else {
        *(unsigned char *)(drive + 0x48) = 0xff;
        SwimIIISetSignal(0xf6);
        if (SwimIIISenseSignal(0xf6) != 0)
            *(unsigned char *)(drive + 0x49) = 0xff;
        else
            *(unsigned char *)(drive + 0x49) = 0xfe;
    }
}

BOOL HALGetDriveType(int drive)
{
    BOOL present;

    SwimIIIDiskSelect(drive);
    present = SwimIIISenseSignal(0xf7) == 0;
    if (present == 1) {
        *(unsigned char *)(drive + 0x47) = 0;
        if (SwimIIISenseSignal(0xf5) != 0) {
            SwimIIISetSignal(0xf6);
            if (SwimIIISenseSignal(0xf6) != 0)
                *(unsigned char *)(drive + 0x47) = 0xff;
            else
                *(unsigned char *)(drive + 0x47) = 0xfe;
        }
    }
    return present;
}

/* The reference ignores the drive argument. */
short HALPowerUpDrive(int drive)
{
    SwimIIISetSignal(0xfd);
    SwimIIISetSignal(0xf2);
    return SleepUntilReady(1);
}

void HALPowerDownDrive(int drive)
{
    SwimIIIDiskSelect(drive);
    SwimIIISetSignal(0xf6);
}

short HALSeekDrive(int drive)
{
    short result;

    result = SwimIIIStepDrive(*(signed char *)(drive + 0x20) - *(signed char *)(drive + 0x1c));
    if (result == 0) {
        result = SleepUntilReady(30);
        if (result == 0) {
            if (*(unsigned char *)(drive + 0x5a) != 0)
                FormatGCRCacheSWIMIIIData(drive);
            else
                FormatMFMCacheSWIMIIIData(drive);
        }
    }
    return result;
}

short HALRecalDrive(int drive)
{
    short result = 0;
    short steps = *(short *)(drive + 0x52);

    while (--steps != -1) {
        if (SwimIIISenseSignal(0xfa) == 0)
            break;
        result = SwimIIIStepDrive(-1);
        if (result != 0)
            return result;
    }
    if (result == 0) {
        result = SleepUntilReady(30);
        if (result == 0) {
            if (steps == 0 && SwimIIISenseSignal(0xfa) != 0)
                result = RecordError(-76);
            if (result == 0) {
                if (*(unsigned char *)(drive + 0x5a) != 0)
                    FormatGCRCacheSWIMIIIData(drive);
                else
                    FormatMFMCacheSWIMIIIData(drive);
            }
        }
    }
    return result;
}

/* The reference ignores the drive argument. */
short HALEjectDiskette(int drive)
{
    short tries = 29;

    SwimIIISetSignal(0xf7);
    do {
        FloppyTimedSleep(100);
        if (SwimIIISenseSignal(0xf8) != 0)
            break;
    } while (--tries != -1);
    FloppyTimedSleep(1);
    return 0;
}

short HALGetNextAddressID(int drive)
{
    short result;

    ResetDMAChannel();
    CancelOSEvent((unsigned *)driveOSEventIDptr, 4);
    SwimIIIHeadSelect(*(unsigned char *)(drive + 0x21));
    SwimIIISetReadMode();
    result = WaitForEvent(400, 8, 4);
    if (result == 0) {
        SwimIIIDisableRWMode();
        *(unsigned char *)(drive + 0x1c) = *FloppySWIMIIIRegs.ctrack & 0x7f;
        SynchronizeIO();
        *(unsigned char *)(drive + 0x1d) = *FloppySWIMIIIRegs.ctrack >> 7;
        SynchronizeIO();
        *(unsigned char *)(drive + 0x1e) = *FloppySWIMIIIRegs.csect & 0x7f;
        SynchronizeIO();
        *(unsigned char *)(drive + 0x1f) = *FloppySWIMIIIRegs.gap3;
        SynchronizeIO();
    }
    SwimIIIDisableRWMode();
    return RecordError(result);
}

short HALReadSector(int drive)
{
    short result;

    *FloppySWIMIIIRegs.nsect = 1;
    SynchronizeIO();
    *FloppySWIMIIIRegs.gap3 = 0;
    SynchronizeIO();
    *FloppySWIMIIIRegs.sector = *(unsigned char *)(drive + 0x22);
    SynchronizeIO();
    SwimIIIHeadSelect(*(unsigned char *)(drive + 0x21));
    result = StartDMAChannel(*(unsigned *)(drive + 0x28), *(short *)(drive + 0x56), 1);
    if (result != 0)
        donone("HALRead failed for %d:%d:%d ", *(unsigned char *)(drive + 0x21),
            *(signed char *)(drive + 0x20), *(unsigned char *)(drive + 0x22));
    SwimIIIDisableRWMode();
    *FloppySWIMIIIRegs.sector = 0xff;
    SynchronizeIO();
    return result;
}

short HALWriteSector(int drive)
{
    short result;
    int preamble, pad, align;
    unsigned address;

    *FloppySWIMIIIRegs.nsect = 1;
    SynchronizeIO();
    *FloppySWIMIIIRegs.gap3 = 0;
    SynchronizeIO();
    *FloppySWIMIIIRegs.sector = *(unsigned char *)(drive + 0x22);
    SynchronizeIO();
    ByteMove(trackEnd, (unsigned char *)(*(short *)(drive + 0x56) + *(int *)(drive + 0x28) + 6), 2);

    if (*(unsigned char *)(drive + 0x48) == 0)
        preamble = 15;
    else
        preamble = *(unsigned char *)(drive + 0x5c) + 22;
    address = *(unsigned *)(drive + 0x28) - preamble;
    pad = 0;
    align = *(short *)(drive + 0x320);
    if (align > 1)
        pad = ((address & -align) + align) - address;
    address += pad;

    SwimIIIHeadSelect(*(unsigned char *)(drive + 0x21));
    result = StartDMAChannel(address, preamble - pad + 8 + *(short *)(drive + 0x56), 0);
    if (result != 0)
        donone("HALWrite failed for %d:%d:%d ", *(unsigned char *)(drive + 0x21),
            *(signed char *)(drive + 0x20), *(unsigned char *)(drive + 0x22));
    SwimIIIDisableRWMode();
    *FloppySWIMIIIRegs.sector = 0xff;
    SynchronizeIO();
    return result;
}

short HALFormatTrack(int drive)
{
    unsigned char savedSectors;
    unsigned address;
    short result;

    *(unsigned char *)(drive + 0x22) = 1;
    savedSectors = lastSectorsPerTrack;
    lastSectorsPerTrack = *(unsigned char *)(drive + 0x51);
    if (*(unsigned char *)(drive + 0x5a) != 0)
        FormatGCRCacheSWIMIIIData(drive);
    else
        FormatMFMCacheSWIMIIIData(drive);
    lastSectorsPerTrack = savedSectors;

    while (SwimIIISenseSignal(0xfb) != 0)
        ;
    while (SwimIIISenseSignal(0xfb) == 0)
        ;
    SwimIIIHeadSelect(*(unsigned char *)(drive + 0x21));
    if (*(unsigned char *)(drive + 0x21) != 0)
        address = *(unsigned *)(drive + 0xb8) + track_offset;
    else
        address = *(unsigned *)(drive + 0xb8);
    PrepareCPUCacheForDMAWrite();
    result = StartDMAChannel(address, 0x8000, 0);
    *FloppySWIMIIIRegs.control = 8;
    SynchronizeIO();
    *FloppySWIMIIIRegs.control = 0x40;
    SynchronizeIO();
    donone("gcr=%d hd=%d,track=%d,trksize=%d,err=%d\n", *(unsigned char *)(drive + 0x5a),
        *(unsigned char *)(drive + 0x21), *(signed char *)(drive + 0x20), track_offset, result);
    return result;
}

/* End of FloppyDisk.m */
