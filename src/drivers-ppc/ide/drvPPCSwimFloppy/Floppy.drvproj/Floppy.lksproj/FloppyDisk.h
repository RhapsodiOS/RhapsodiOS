/*
 * FloppyDisk.h - PPC SWIM Floppy disk device class
 *
 * Main class for SWIM floppy disk devices
 */

#import <driverkit/IODisk.h>
#import <driverkit/IODirectDevice.h>
#import <driverkit/kernelDiskMethods.h>
#import <driverkit/IODiskPartition.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <kernserv/queue.h>
#import <bsd/dev/disk.h>
#import <bsd/dev/fd_extern.h>
#import <sys/fcntl.h>
#import <string.h>

/*
 * Drive description; fdDriveInfo is the only instance. DKIOCINFO copies out
 * the leading struct drive_info.
 */
typedef struct {
	struct drive_info	gen_drive_info;
	int			seek_rate;
	int			head_settle_time;
	int			head_unload_time;
	char			is_perpendicular;
	char			rsvd;
} fd_drive_info_t;

/*
 * Request passed from the method layer to the I/O thread, 0x34 bytes.
 */
typedef enum {
	FDC_IOREQ = 0,
	FDC_READ,
	FDC_WRITE,
	FDC_EJECT = 4,
	FDC_ABORT,
	FDC_PROBEDISK,
	FDC_SET_DENSITY,
	FDC_SET_SECTSIZE,
	FDC_SET_GAP,
	FDC_SET_INNER_RETRY,
	FDC_SET_OUTER_RETRY,
	FDC_GET_INNER_RETRY,
	FDC_GET_OUTER_RETRY,
	FDC_GET_FORMAT,
	FDC_GET_PHYS_PARAMS,
	FDC_THREAD_ABORT,
	FDC_TIMER_EVENT
} fdCommand_t;

typedef struct {
	fdCommand_t	command;
	fd_ioreq_t	fdIoReq;	/* FDC_IOREQ */
	unsigned int	block;
	unsigned int	blockCount;
	void		*buf;		/* data, or a simple command's argument */
	vm_task_t	client;
	id		waitLock;	/* NXConditionLock, synchronous requests */
	void		*pending;	/* asynchronous requests */
	unsigned int	needsDisk:1,
			singleShot:1,	/* no retries, stop after one chunk */
			async:1,	/* freed by the I/O thread */
			rsvd:29;
	unsigned int	bytesXfr;
	IOReturn	status;
	queue_chain_t	link;
} fdBuf_t;

@protocol FloppyControllerPublic
- (fd_return_t)fcCmdXfr:(fd_ioreq_t)fdIoReq driveInfo:(fd_drive_info_t *)driveInfo;
@end

@interface FloppyController : IODirectDevice
{
	id		fcCmdLock;
	int		floppyInterruptPort;
	int		floppyDevicePort;
}
@end

@interface FloppyDisk : IODisk <IODiskReadingAndWriting, IOPhysicalDiskMethods>
{
	queue_head_t		ioQueueDisk;	/* requests that need a disk */
	queue_head_t		ioQueueNodisk;
	id			ioQLock;	/* NXConditionLock */
	id			cntrlr;
	int			innerRetryCount;
	int			outerRetryCount;
	ns_time_t		lastAccess;
	unsigned int		timerRunning:1;
	unsigned int		inProbe;
	fd_drive_info_t		*driveInfo;
	struct fd_format_info	formatInfo;
	char			*floppySectorBuffer;
}

+ (IODeviceStyle)deviceStyle;
+ (Protocol **)requiredProtocols;
+ (BOOL)probe:deviceDescription;

- (IOReturn)readAt:(unsigned)offset length:(unsigned)length buffer:(unsigned char *)buffer actualLength:(unsigned *)actualLength client:(vm_task_t)client;
- (IOReturn)readAsyncAt:(unsigned)offset length:(unsigned)length buffer:(unsigned char *)buffer pending:(void *)pending client:(vm_task_t)client;
- (IOReturn)writeAt:(unsigned)offset length:(unsigned)length buffer:(unsigned char *)buffer actualLength:(unsigned *)actualLength client:(vm_task_t)client;
- (IOReturn)writeAsyncAt:(unsigned)offset length:(unsigned)length buffer:(unsigned char *)buffer pending:(void *)pending client:(vm_task_t)client;
- (IOReturn)fdCmdXfr:(fd_ioreq_t)fdIoReq;
- (IOReturn)fdSetDensity:(int)density;
- (IOReturn)fdSetSectSize:(int)sectSize;
- (IOReturn)fdSetGapLength:(int)gapLength;
- (IOReturn)fdGetFormatInfo:(struct fd_format_info *)formatInfo;
- (IOReturn)fdSetInnerRetry:(int)count;
- (IOReturn)fdSetOuterRetry:(int)count;
- (int)innerRetry;
- (int)outerRetry;
- (IOReturn)fdMotorOff;
- (IOReturn)ejectPhysical;
- (IOReturn)updatePhysicalParameters;
- (BOOL)needsManualPolling;
- (IOReturn)deviceOpen:(unsigned)intentions;
- (void)deviceClose;
- (IODiskReadyState)updateReadyState;
- (void)abortRequest;
- (void)diskBecameReady;
- (IOReturn)isDiskReady:(BOOL)prompt;
- property_IODeviceType:(char *)types length:(unsigned *)maxLen;
- property_IOUnit:(char *)types length:(unsigned *)maxLen;
@end

#import "FloppyDiskInt.h"
#import "FloppyDiskThread.h"

/*
 * Sony driver format table entry, 0x14 bytes.
 */
typedef struct {
	unsigned int	blocks;
	unsigned char	flags;
	unsigned char	sectorsPerTrack;
	unsigned short	tracks;
	unsigned short	sectorSize;
	unsigned short	field_a;
	unsigned char	field_c;
	unsigned char	field_d;
	unsigned char	field_e;
	unsigned char	mfmGap[5];
} FormatTableEntry;

/*
 * Sony driver state, 0x6d4 bytes. Drive n (1 or 2) is drive[n - 1].
 */
#define SONY_DRIVE_SIZE	0x324

typedef struct {
	unsigned int		reserved0;
	unsigned char		drive[2][SONY_DRIVE_SIZE];
	unsigned int		reserved64c;
	short			cachedDrive;
	short			deferredPowerDown;
	int			deferredDrive;
	FormatTableEntry	formatTable[6];
	unsigned int		reserved6d0;
} SonyVariables_t;

/*
 * SWIM III register addresses, set up by HALReset. The names follow the
 * register layout at 0x10 spacing from the chip base.
 */
typedef struct {
	volatile unsigned char	*data;		/* chip base */
	volatile unsigned char	*timer;
	volatile unsigned char	*error;
	volatile unsigned char	*mode;
	volatile unsigned char	*select;
	volatile unsigned char	*setup;
	volatile unsigned char	*control;	/* writing bits clears them */
	volatile unsigned char	*status;	/* writing bits sets them in control */
	volatile unsigned char	*intr;
	volatile unsigned char	*nseek;
	volatile unsigned char	*ctrack;
	volatile unsigned char	*csect;
	volatile unsigned char	*gap3;
	volatile unsigned char	*sector;
	volatile unsigned char	*nsect;
	volatile unsigned char	*intrEnable;
} SWIMIIIRegs_t;

/*
 * Data, in the reference's __data / __common / __bss order.
 */
extern fd_drive_info_t		fdDriveInfo;
extern struct fd_disk_info	fdDiskInfo[];
extern struct fd_density_info	fdDensityInfo[];
typedef struct {
	int			density;
	struct fd_sectsize_info	*ssi;
} fdDensitySectsize_t;
extern fdDensitySectsize_t	fdDensitySectsize[];
extern IONamedValue		fdrValues[];
extern IONamedValue		fdOpValues[];
extern IONamedValue		fdCommandValues[];
extern IONamedValue		fcOpcodeValues[];
extern IONamedValue		densityValues[];
extern IONamedValue		midValues[];
extern IONamedValue		fdIoctlValues[];
extern int			DataSource;
extern int			busyflag;
extern void			*trackBuffer;
extern int			FloppyState;
extern unsigned char		ReadDataPresent[2];

extern int			*slock;
extern unsigned char		FloppyIdMap[2][0x4c];
extern int			myDriveStatus;
extern unsigned char		PrivDBDMAChannelArea[0x2c];
extern unsigned int		GRCFloppyDMARegs;
extern int			GRCFloppyDMAChannel;
extern unsigned int		ccCommandsLogicalAddr;
extern unsigned int		ccCommandsPhysicalAddr;
extern SonyVariables_t		SonyVariables;
extern unsigned int		theDefaultRefCon;
extern int			MediaScanTaskID;
extern int			track_offset;
extern void			*other_buffer_ptr;
extern SWIMIIIRegs_t		FloppySWIMIIIRegs;
extern unsigned char		lastErrorsPending;
extern unsigned char		lastSectorsPerTrack;
extern int			driveOSEventIDptr;

/*
 * Kernel interfaces the driver uses that the public headers do not declare.
 */
struct buf;
struct uio;
extern int	nulldev(void);
extern int	physio(int (*strategy)(), struct buf *bp, dev_t dev, int flags,
			unsigned (*minphys)(), struct uio *uio, int blocksize);
extern void	biodone(struct buf *bp);
extern int	copyin(const void *uaddr, void *kaddr, unsigned len);
extern int	copyout(const void *kaddr, void *uaddr, unsigned len);
extern int	printf(const char *fmt, ...);
extern int	sleep(void *chan, int pri);
extern void	wakeup(void *chan);
extern void	timeout(void (*fn)(void *), void *arg, int ticks);
extern int	untimeout(void (*fn)(void *), void *arg);
extern int	splbio(void);
extern void	splx(int s);
extern unsigned	kvtophys(unsigned vaddr);
extern void	flush_cache_v(unsigned vaddr, unsigned len);
extern void	invalidate_cache_v(unsigned vaddr, unsigned len);
extern int	kmem_alloc_wired(struct vm_map *map, void *addrp, unsigned size);
extern task_t	kernel_task;
extern struct vm_map	*kernel_map;
extern unsigned	page_size;
extern void	(*pmac_register_int)(int source, int level, void (*handler)(), void *arg);
extern unsigned	powermac_info[];
extern unsigned	powermac_io_info[];
extern unsigned	*powermac_dbdma_channels;
extern vm_task_t IOVmTaskForBuf(struct buf *bp);
extern int	volCheckRequest(id diskObj, int diskType);

/*
 * FloppyDisk.m, FloppyDiskInt.m, FloppyDiskThread.m
 */
extern IODiskReadyState	GetCurrentState(void);
extern void		fdTimer(void *disk);
extern void		fdThread(void *disk);

/*
 * BSD entry points and plugin glue
 */
extern IOReturn		fdrToIo(fd_return_t fdrCode);
extern void		fd_init_idmap(id diskClass);
extern unsigned char	*floppy_idmap(void);
extern int		Fdopen(dev_t dev, int flag);
extern int		Fdclose(dev_t dev);
extern int		fdread(dev_t dev, struct uio *uio);
extern int		fdwrite(dev_t dev, struct uio *uio);
extern void		GetBusyFlag(void);
extern int		fdstrategy(struct buf *bp);
extern int		fdioctl(dev_t dev, u_long cmd, caddr_t data);
extern int		fdsize(dev_t dev);
extern void		*floppyMalloc(unsigned size, void **bufp, unsigned *sizep);
extern int		SetBusyFlag(void);
extern void		ResetBusyFlag(void);
extern int		FloppyPluginInit(int refCon);
extern int		FloppyPluginIO(unsigned *actualLength, unsigned length, void *buffer,
				unsigned offset, int direction, int unused);
extern int		FloppyPluginFlush(void);
extern int		FloppyPluginGotoState(int unused, unsigned state);
extern int		FloppyRecalibrate(void);
extern int		FloppyFormatInfo(struct fd_format_info *formatInfo);
extern int		FloppyFormatDisk(int head, int cylinder);
extern int		FloppyWriteProtected(void);
extern BOOL		drive_present(void);

/*
 * DBDMA support
 */
extern void		StartDBDMA(int channel);
extern void		StopDBDMA(int channel);
extern void		PrepDBDMA(int channel);
extern void		ResetDBDMA(int channel);
extern void		SetDBDMAPhysicalAddress(int channel, unsigned direction,
				unsigned bufferAddress, unsigned transferSize);
extern int		OpenDBDMAChannel(unsigned dmaBase, int *channelp, int count,
				unsigned *logicalAddr, unsigned *physicalAddr);
extern void		CloseDBDMAChannel(int channel);
extern void		PrintDMA(int channel);

/*
 * OS services for the Sony driver
 */
extern int		CreateOSHardwareLockResources(void *lock);
extern int		CreateOSEventResources(void *event);
extern int		BSMPINotifyFamilyStoreChangedState(int drive, int newState);
extern int		FlushDMAedDataFromCPUCache(void);
extern int		PrepareCPUCacheForDMAWrite(void);
extern int		PrepareCPUCacheForDMARead(void);
extern int		MemListDescriptorDataCopyToMemory(void *src, void *dst, unsigned len);
extern int		MemListDescriptorDataCopyFromMemory(void *src, void *dst, unsigned len);
extern int		MemListDescriptorDataCompare(void);
extern int		MemListDescriptorDataCompareWithMemory(void *mem, void *data, int len,
				int *mismatch, int *offset);
extern void		SynchronizeIO(void);
extern short		FloppyTimedSleep(int msec);
extern void		ExitHardwareLockSection(int s);
extern int		EnterHardwareLockSection(void);
extern void		FlushProcessorCache(int space, unsigned vaddr, unsigned len);
extern int		CurrentAddressSpaceID(void);
extern int		SetOSEvent(unsigned *event, unsigned eventMask);
extern int		CancelOSEvent(unsigned *event, unsigned eventMask);
extern BOOL		WaitForOSEvent(unsigned *event, unsigned eventMask, unsigned msec, unsigned *eventsp);
extern int		BSBlockListDescriptorGetExtent(int list, int index,
				unsigned *startBlock, unsigned *blockCount);
extern void		donone(const char *format, ...);
extern void		ResetBitArray(unsigned char *bits, unsigned count);
extern BOOL		TestBitArray(unsigned char *bits, unsigned count);

/*
 * Sony driver core
 */
extern short		InitializeDrive(short driveNum, unsigned swimBase, unsigned dmaBase,
				unsigned dmaBase2, void *trackBuffer, unsigned trackBufferPhys,
				unsigned trackBufferSize, int *drivep);
extern void		ScanForDisketteChange(void);
extern short		FormatDisk(int head, int track, int drive, short formatIndex);
extern short		EjectDisk(int drive);
extern void		InitFormatTable(void);
extern void		AvailableFormats(int drive, short *minFormat, short *maxFormat, short *current);
extern short		LookupFormatTable(int drive, short *count, short *minFormat, short *maxFormat,
				short *current, void *list);
extern short		CheckDriveOnLine(int drive);
extern short		ReadDiskTrackToCache(int drive);
extern short		WriteCacheToDiskTrack(int drive);
extern short		ReadSectorFromCacheMemory(int drive);
extern short		WriteSectorToCacheMemory(int drive);

/*
 * Sony driver core, continued
 */
extern short		ReadBlocks(int drive, unsigned *actualCount);
extern short		WriteBlocks(int drive, unsigned *actualCount);
extern short		CheckDriveNumber(short driveNum, int *drivep);
extern short		PowerDriveUp(int drive);
extern void		PowerDriveDown(int drive, int deferred);
extern short		GetDisketteFormatType(int drive);
extern short		SetDisketteFormat(int drive, short formatIndex);
extern short		GetDisketteFormat(int drive);
extern void		BuildTrackInterleaveTable(int drive, unsigned char sectors);
extern void		SetCacheAddresses(int drive);
extern void		SetSectorsPerTrack(int drive);
extern void		SetSectorAddressBlocksize(int drive);
extern void		GetSectorAddress(int drive, short block);
extern void		DumpTrackCache(int drive);
extern short		FlushTrackCache(int drive);
extern BOOL		TestCacheDirtyState(int drive);
extern BOOL		TestTrackInCache(int drive);
extern void		AssignTrackInCache(int drive);
extern void		FPYComputeCacheDMAAddress(int drive, unsigned char head, unsigned char sector,
				int which, unsigned *addrp);
extern unsigned char	*DenibblizeGCRData(unsigned char *nibbles, unsigned char *output,
				short count, unsigned *checksum);
extern void		DenibblizeGCRChecksum(unsigned char *nibbles, unsigned *checksum);
extern short		FPYDenibblizeGCRSector(int drive, unsigned char *nibbles, unsigned char *output);
extern unsigned char	*NibblizeGCRData(unsigned char *input, unsigned char *nibbles,
				unsigned short count, unsigned *checksum);
extern unsigned char	*NibblizeGCRChecksum(unsigned char *nibbles, unsigned checksum);
extern short		FPYNibblizeGCRSector(int drive, unsigned char *nibbles, unsigned char *data);
extern short		RecalDrive(int drive);
extern short		SeekDrive(int drive);
extern short		FlushCacheAndSeek(int drive);
extern short		ResetDMAChannel(void);
extern short		StopDMAChannel(void);
extern short		StartDMAChannel(unsigned address, unsigned length, unsigned short direction);

/*
 * Sony driver core, continued
 */
extern short		HALReset(int drive, unsigned swimBase, unsigned dmaBase);
extern short		RecordError(short error);
extern int		PostDisketteEvent(unsigned char newState, short driveNum);
extern void		MediaScanTask(void);
extern short		LaunchMediaScanTask(void);
extern short		KillMediaScanTask(void);
extern short		SleepUntilReady(int msec);
extern short		WaitForEvent(int msec, unsigned char controlBits, unsigned char intrMask);
extern void		ByteMove(const void *src, void *dst, int count);

/*
 * SWIM III hardware layer
 */
extern void		FormatGCRCacheSWIMIIIData(int drive);
extern void		FormatMFMCacheSWIMIIIData(int drive);
extern void		SwimIIISmallWait(unsigned short ticks);
extern short		SwimIIITimeOut(unsigned *timeoutp);
extern void		SwimIIIAddrSignal(unsigned char signal);
extern BOOL		SwimIIISenseSignal(unsigned char signal);
extern void		SwimIIISetSignal(unsigned char signal);
extern void		SwimIIIHeadSelect(short head);
extern void		SwimIIIDiskSelect(int drive);
extern short		SwimIIIStepDrive(short steps);
extern void		SwimIIIDisableRWMode(void);
extern void		SwimIIISetReadMode(void);
extern void		SwimIIISetWriteMode(void);
extern void		SwimIIISetFormatMode(void);
extern void		HALISR_DMA(void);
extern void		HALISRHandler(void);
extern short		HALSetFormatMode(int drive);
extern BOOL		HALDiskettePresence(int drive);
extern void		HALGetMediaType(int drive);
extern BOOL		HALGetDriveType(int drive);
extern short		HALPowerUpDrive(int drive);
extern void		HALPowerDownDrive(int drive);
extern short		HALSeekDrive(int drive);
extern short		HALRecalDrive(int drive);
extern short		HALEjectDiskette(int drive);
extern short		HALGetNextAddressID(int drive);
extern short		HALReadSector(int drive);
extern short		HALWriteSector(int drive);
extern short		HALFormatTrack(int drive);


/* End of FloppyDisk.h */
