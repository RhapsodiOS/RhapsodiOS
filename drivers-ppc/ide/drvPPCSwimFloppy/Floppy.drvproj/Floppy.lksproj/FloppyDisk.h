/*
 * FloppyDisk.h - PPC SWIM Floppy disk device class
 *
 * Main class for SWIM floppy disk devices
 */

#import <driverkit/IODisk.h>
#import <driverkit/return.h>
#import <mach/vm_types.h>

// Forward declaration
typedef struct _FdBuffer FdBuffer;
typedef struct _QueueHead {
    FdBuffer *first;
    FdBuffer *last;
} QueueHead;

@interface FloppyDisk : IODisk
{
    // Queue management (offsets 0x184-0x194)
    QueueHead _priorityQueue;         // offset 0x184: High priority I/O queue
    QueueHead _normalQueue;           // offset 0x18c: Normal priority I/O queue
    id _queueLock;                    // offset 0x194: Lock for queue operations
    id _controller;                   // offset 0x198: Floppy controller reference
    unsigned int _innerRetry;         // offset 0x19c: Inner retry count
    unsigned int _outerRetry;         // offset 0x1a0: Outer retry count
    unsigned char _reserved1[8];      // offset 0x1a4-0x1ab: reserved
    unsigned int _timerFlags;         // offset 0x1ac: Timer flags (bit 31)
    unsigned char _reserved2[4];      // offset 0x1b0-0x1b3: reserved
    const char *_driveInfo;           // offset 0x1b4: Drive info string
    unsigned char _reserved3[8];      // offset 0x1b8-0x1bf: reserved

    // Drive state (offsets 0x1c8-0x1eb)
    unsigned int _field_0x1c8;        // offset 0x1c8: unknown
    unsigned int _density;            // offset 0x1cc: Media density (1=500kbps, 2=300kbps, 3=1Mbps)
    unsigned int _capacity;           // offset 0x1d0: Disk capacity
    unsigned int _isFormatted;        // offset 0x1d4: Formatted flag
    unsigned int _blockSize;          // offset 0x1d8: Block size in bytes
    unsigned int _gapLength;          // offset 0x1dc: Gap length
    unsigned int _sectorsPerTrack;    // offset 0x1e0: Sectors per track
    unsigned int _sectorSizeCode;     // offset 0x1e4: Sector size code
    unsigned int _field_0x1e8;        // offset 0x1e8: unknown
    void *_buffer;                    // offset 0x1ec: Buffer pointer

    // Additional fields from earlier offsets
    unsigned char _headsPerCylinder;  // offset 0x1bc: heads per cylinder
    unsigned char _field_0x1d7;       // offset 0x1d7: additional flag
}

// Public methods
- (IOReturn)_abortRequest;
- (IOReturn)_deviceClose;
- (IOReturn)_deviceOpen:(BOOL)exclusive;
- (void)_diskBecameReady;
- (IOReturn)_ejectPhysical;
- (IOReturn)_innerRetry;
- (BOOL)_isDiskReady:(id)controller;
- (BOOL)_needsManualPolling;
- (IOReturn)_outerRetry;
- (IOReturn)_property_IODeviceType:(char *)types length:(unsigned int *)maxLen;
- (IOReturn)_property_IOUnit:(unsigned int *)unit length:(unsigned int *)length;
- (IOReturn)readAsyncAt:(unsigned)offset length:(unsigned)length buffer:(void *)buffer pending:(void *)pending client:(vm_task_t)client;
- (IOReturn)readAt:(unsigned)offset length:(unsigned)length buffer:(void *)buffer actualLength:(unsigned *)actualLength client:(vm_task_t)client;
- (IOReturn)_updatePhysicalParameters;
- (void)_updateReadyState;
- (IOReturn)writeAsyncAt:(unsigned)offset length:(unsigned)length buffer:(void *)buffer pending:(void *)pending client:(vm_task_t)client;
- (IOReturn)writeAt:(unsigned)offset length:(unsigned)length buffer:(void *)buffer actualLength:(unsigned *)actualLength client:(vm_task_t)client;

// Helper methods
- (void)setDriveName:(const char *)name;
- (void)setLastReadyState:(BOOL)ready;
- (unsigned int)unit;
- (const char *)name;
- (const char *)stringFromReturn:(IOReturn)rtn;
- (BOOL)isFormatted;
- (unsigned int)blockSize;
- (unsigned int)diskSize;

- (IOReturn)_fdCmdXfr:(void *)command;
- (IOReturn)_fdGetFormatInfo:(void *)formatInfo;
- (IOReturn)_fdMotorOff;
- (IOReturn)_fdSetDensity:(unsigned)density;
- (IOReturn)_fdSetGapLength:(unsigned)gap;
- (IOReturn)_fdSetInnerRetry:(unsigned)retry;
- (IOReturn)_fdSetOuterRetry:(unsigned)retry;
- (IOReturn)_fdSetSectSize:(unsigned)sectSize;
@end

// Category headers
#import "FloppyDiskInt.h"
#import "FloppyDiskThread.h"
#import "FloppyDiskKern.h"

// Global variables
extern void *_DataSource;                    // Data source tracker
extern unsigned int _busyflag;               // Controller busy flag
extern unsigned int _ccCommandsLogicalAddr;  // Command buffer logical address
extern unsigned int _ccCommandsPhysicalAddr; // Command buffer physical address

// Table structures
typedef struct {
    unsigned int reserved;
    const char *name;
    unsigned int value;
} DensityEntry;

typedef struct {
    unsigned int cmd;
    const char *name;
} IoctlEntry;

// Global tables
extern DensityEntry _densityValues[];        // Density values table
extern DensityEntry _midValues[];            // Media ID values table
extern IoctlEntry _fdIoctlValues[];          // Ioctl commands table

// Helper functions
extern const char *_getStatusName(unsigned int statusCode, const char **values);
extern const char *_getDensityName(unsigned int densityCode, DensityEntry *table);
extern const char *_getIoctlName(unsigned int ioctlCmd);

// Additional global variables
extern unsigned short DAT_0000fb88;          // Track cache variable
extern unsigned int _FloppyState;            // Floppy state variable
extern char DAT_0000f25e;                    // Drive index storage
extern volatile unsigned char DAT_418500ad;  // Hardware presence register
extern unsigned char _ReadDataPresent;       // Read data present flag
extern unsigned char DAT_0000f459;           // Additional cache flag

// Format info tables
extern unsigned int DAT_0000fb90;            // Format info table - capacity
extern unsigned char DAT_0000fb94;           // Format info table - sectors per track (low nibble)
extern unsigned char DAT_0000fb95;           // Format info table - tracks per disk
extern short DAT_0000fb96;                   // Format info table - sectors per track (full)
extern unsigned char DAT_0000fba1;           // Format info table - additional flags

// Plugin globals
extern unsigned int *_myDriveStatus;         // Current drive status pointer
extern unsigned int _trackBuffer;            // Track cache buffer
extern int iRam9421ffe8;                     // RAM initialization value
extern char _lastSectorsPerTrack;            // Last formatted sectors per track count
extern int _track_offset;                    // Track offset in cache

// GCR format data patterns
extern unsigned char s_gap_0000e6e4[];       // Gap bytes pattern
extern unsigned char DAT_0000c16c[];         // Address mark prefix
extern unsigned char s_mark_0000e720[];      // Sector mark
extern unsigned char s_data_0000e724[];      // Data mark
extern unsigned char s_tail_0000e728[];      // Track tail

// MFM format data patterns
extern unsigned char s__0000e758[];          // MFM gap/sync pattern 1
extern unsigned char s__0000e764[];          // MFM address mark pattern
extern unsigned char s__0000e770[];          // MFM CRC pattern
extern unsigned char s__0000e774[];          // MFM data mark pattern
extern unsigned char s__0000e780[];          // MFM data sync pattern

// C Utility functions
extern void _AssignTrackInCache(int param_1);
extern void _AvailableFormats(int param_1, unsigned short *minFormat,
                               unsigned short *maxFormat, short *formatType);
extern unsigned int _BSBlockListDescriptorGetExtent(unsigned int param_1, unsigned int param_2,
                                                     unsigned int *startBlock,
                                                     unsigned int *blockCount);
extern unsigned int _BSMPINotifyFamilyStoreChangedState(unsigned int param_1,
                                                         unsigned int newState);
extern void _BuildTrackInterleaveTable(int param_1, unsigned int sectorCount);
extern void _ByteMove(unsigned char *source, unsigned char *dest, int count);
extern unsigned int _CancelOSEvent(unsigned int *eventFlags, unsigned int eventMask);
extern unsigned int _CheckDriveNumber(short driveNum, unsigned int **drivePtr);
extern unsigned int _CheckDriveOnLine(int driveStructure);
extern void _CloseDBDMAChannel(void);
extern unsigned int _CreateOSEventResources(void);
extern unsigned int _CreateOSHardwareLockResources(void);
extern unsigned int _CurrentAddressSpaceID(void);
extern void _DenibblizeGCRChecksum(unsigned char *nibbles, unsigned int *checksum);
extern void _DenibblizeGCRData(unsigned char *nibbles, unsigned char *output,
                               short byteCount, unsigned int *checksum);
extern void _donone(void);
extern BOOL _drive_present(void);
extern void _DumpTrackCache(int driveStructure);
extern int _EjectDisk(int param_1);
extern void _EnterHardwareLockSection(void);
extern void _ExitHardwareLockSection(void);
extern void _fd_init_idmap(unsigned int param_1);
extern unsigned int _Fdclose(unsigned int param_1);
extern unsigned int _fdioctl(unsigned int param_1, int param_2, unsigned int *param_3);
extern unsigned int _Fdopen(unsigned int param_1, unsigned int param_2);
extern unsigned int _fdread(unsigned int param_1, int *param_2);
extern unsigned int _fdsize(void);
extern unsigned int _fdstrategy(int param_1);
extern void _fdTimer(int param_1);
extern unsigned int _fdwrite(unsigned int param_1, unsigned int param_2);
extern unsigned char *_floppy_idmap(void);
extern int _FloppyFormatDisk(unsigned int param_1, unsigned int param_2);
extern int _FloppyFormatInfo(int param_1);
extern unsigned int _floppyMalloc(unsigned int param_1, unsigned int *param_2, int *param_3);
extern int _FloppyPluginFlush(void);
extern unsigned int _FloppyPluginGotoState(unsigned int param_1, unsigned int param_2);
extern void _FloppyPluginInit(unsigned int param_1);
extern int _FloppyPluginIO(unsigned int *param_1, int param_2, unsigned int param_3,
                           unsigned int param_4, int param_5);
extern int _FloppyRecalibrate(void);
extern unsigned int _FloppyTimedSleep(int param_1);
extern unsigned int _FloppyWriteProtected(void);
extern int _FlushCacheAndSeek(int param_1);
extern unsigned int _FlushDMAedDataFromCPUCache(void);
extern void _FlushProcessorCache(unsigned int param_1, unsigned int param_2, unsigned int param_3);
extern int _FlushTrackCache(int param_1);
extern int _FormatDisk(unsigned char param_1, unsigned char param_2, int param_3, short param_4);
extern void _FormatGCRCacheSWIMIIIData(int param_1);
extern void _FormatMFMCacheSWIMIIIData(int param_1);
extern void _FPYComputeCacheDMAAddress(int param_1, char param_2, unsigned int param_3,
                                       int param_4, int *param_5);
extern int _FPYDenibblizeGCRSector(int param_1, unsigned char *param_2, unsigned int param_3);
extern unsigned int _FPYNibblizeGCRSector(int param_1, unsigned char *param_2, int param_3);
extern void _GetBusyFlag(void);
extern unsigned int _GetCurrentState(void);
extern int _GetDisketteFormat(int param_1);
extern unsigned char _GetDisketteFormatType(int param_1);
extern void _GetSectorAddress(int param_1, short param_2);
extern bool _HALDiskettePresence(int param_1);
extern unsigned int _HALEjectDiskette(void);
extern int _HALFormatTrack(int param_1);
extern bool _HALGetDriveType(int param_1);
extern void _HALGetMediaType(int param_1);
extern void _HALGetNextAddressID(int param_1);
extern void _HALISR_DMA(void);
extern void _HALISRHandler(void);
extern void _HALPowerDownDrive(void);
extern int _HALPowerUpDrive(void);
extern int _HALReadSector(int param_1);
extern int _HALRecalDrive(int param_1);
extern unsigned int _HALReset(int param_1, int param_2, unsigned int param_3);
extern int _HALSeekDrive(int param_1);
extern void _HALSetFormatMode(int param_1);
extern int _HALWriteSector(int param_1);
extern int _InitializeDrive(unsigned int param_1, unsigned int param_2, unsigned int param_3,
                            unsigned int param_4, unsigned int param_5, unsigned int param_6,
                            unsigned int param_7, unsigned int **param_8);
extern void _InitFormatTable(void);
extern unsigned int _KillMediaScanTask(void);
extern unsigned int _LaunchMediaScanTask(void);
extern int _LookupFormatTable(int param_1, short *param_2, short *param_3, short *param_4,
                              short *param_5, unsigned int *param_6);
extern unsigned int _MemListDescriptorDataCompare(void);
extern unsigned int _MemListDescriptorDataCompareWithMemory(void);
extern unsigned int _MemListDescriptorDataCopyFromMemory(void);
extern unsigned int _MemListDescriptorDataCopyToMemory(void);
extern unsigned char *_NibblizeGCRChecksum(unsigned char *param_1, unsigned int param_2);
extern void _NibblizeGCRData(unsigned char *param_1, unsigned char *param_2, short param_3,
                             unsigned int *param_4);
extern void _PostDisketteEvent(unsigned char param_1, short param_2);
extern void _PowerDriveDown(int param_1, int param_2);
extern int _PowerDriveUp(int param_1);
extern unsigned int _PrepareCPUCacheForDMARead(void);
extern unsigned int _PrepareCPUCacheForDMAWrite(void);
extern void _PrepDBDMA(int param_1);
extern void _PrintDMA(void);
extern int _ReadBlocks(int param_1, int *param_2);
extern int _ReadDiskTrackToCache(int param_1);
extern int _ReadSectorFromCacheMemory(int param_1);

// Block and track cache helper functions
extern short _CheckDriveOnLine(int driveStructure);
extern short _RecalDrive(int driveStructure);
extern int _TestTrackInCache(void);
extern void _AssignTrackInCache(int driveStructure);

// Memory descriptor helper functions
extern unsigned int FUN_00006b4c(void);
extern void FUN_00006b5c(void);
extern unsigned int FUN_00006ba8(void);
extern void FUN_00006bb8(void);

// Cache management helper functions
extern void FUN_00006abc(int offset, int size);  // Flush cache
extern void FUN_00006b00(int offset, int size);  // Invalidate cache

// Format detection functions
extern short _SetDisketteFormat(int driveStructure, unsigned int formatType);

// SWIM III controller functions
extern void _SwimIIIDiskSelect(void);
extern int _SwimIIISenseSignal(unsigned int signal);
extern void _SwimIIISetSignal(unsigned int signal);
extern void _SwimIIIHeadSelect(unsigned char head);
extern void _SwimIIISetReadMode(void);
extern void _SwimIIIDisableRWMode(void);
extern short _SwimIIIStepDrive(unsigned int direction);

// DMA and cache management functions
extern void _PrepareCPUCacheForDMAWrite(void);
extern short _StartDMAChannel(int address, unsigned int length, int flags);
extern void _SynchronizeIO(void);
extern void _ResetDMAChannel(void);
extern void _OpenDBDMAChannel(unsigned int dmaBase, void *channelPtr, int param3,
                              unsigned int *logicalAddr, unsigned int *physicalAddr);

// OS event management functions
extern short _WaitForEvent(int timeout, int mask, int eventBit);
extern void _SetOSEvent(unsigned int *eventPtr, unsigned char eventBits);
extern unsigned int *_driveOSEventIDptr;     // Drive OS event ID pointer

// Sleep/timing functions
extern short _SleepUntilReady(int milliseconds);

// Error handling functions
extern void _RecordError(int errorCode);
extern unsigned char _lastErrorsPending;     // Last error status from SWIM III

// Drive power management
extern void _PowerDriveDown(int driveStructure, int param_2);

// SWIM III hardware registers
extern unsigned char *DAT_0000fc20;          // Command register
extern unsigned char *DAT_0000fc24;          // Error status register
extern unsigned char *DAT_0000fc28;          // Status register 1
extern unsigned char *DAT_0000fc2c;          // Status register 2
extern unsigned char *DAT_0000fc30;          // Mode register
extern unsigned char *DAT_0000fc34;          // Control register
extern unsigned char *DAT_0000fc38;          // Timer register
extern unsigned char *DAT_0000fc3c;          // Interrupt status register
extern unsigned char *DAT_0000fc40;          // Interrupt enable register
extern unsigned char *DAT_0000fc44;          // Track/head register
extern unsigned char *DAT_0000fc48;          // Sector number register
extern unsigned char *DAT_0000fc4c;          // Format byte register
extern unsigned char *DAT_0000fc50;          // Target sector register
extern unsigned char *DAT_0000fc54;          // Read enable register
extern unsigned char *DAT_0000fc58;          // Interrupt acknowledge register

// SWIM III and DMA register bases
extern int _FloppySWIMIIIRegs;               // SWIM III register base address
extern unsigned int _GRCFloppyDMARegs;       // DMA register base address
extern void *_GRCFloppyDMAChannel;           // DMA channel structure

// Format table globals (20-byte entries starting at 0xfb90)
extern unsigned int DAT_0000fb90;            // Format 0: Capacity
extern unsigned char DAT_0000fb94;           // Format 0: Flags
extern unsigned char DAT_0000fb95;           // Format 0: Tracks
extern unsigned short DAT_0000fb96;          // Format 0: Total sectors
extern unsigned short DAT_0000fb98;          // Format 0: Sector size
extern unsigned short DAT_0000fb9a;          // Format 0: Track size
extern unsigned char DAT_0000fb9c;           // Format 0: Type
extern unsigned char DAT_0000fb9d;           // Format 0: Heads
extern unsigned char DAT_0000fb9e;           // Format 0: Reserved
extern unsigned int DAT_0000fba4;            // Format 1: Capacity
extern unsigned char DAT_0000fba8;           // Format 1: Flags
extern unsigned char DAT_0000fba9;           // Format 1: Tracks
extern unsigned short DAT_0000fbaa;          // Format 1: Total sectors
extern unsigned short DAT_0000fbac;          // Format 1: Sector size
extern unsigned short DAT_0000fbae;          // Format 1: Track size
extern unsigned short DAT_0000fbb0;          // Format 1: Type/Heads
extern unsigned char DAT_0000fbb1;           // Format 1: Heads
extern unsigned char DAT_0000fbb2;           // Format 1: Reserved
extern unsigned int DAT_0000fbb8;            // Format 2: Capacity
extern unsigned char DAT_0000fbbc;           // Format 2: Flags
extern unsigned char DAT_0000fbbd;           // Format 2: Sectors/track
extern unsigned char DAT_0000fbbe;           // Format 2: Tracks
extern unsigned short DAT_0000fbc0;          // Format 2: Sector size
extern unsigned short DAT_0000fbc2;          // Format 2: Track size
extern unsigned char DAT_0000fbc4;           // Format 2: Type
extern unsigned char DAT_0000fbc5;          // Format 2: Heads
extern unsigned char DAT_0000fbc6;           // Format 2: Reserved
extern unsigned char DAT_0000fbc7;           // Format 2: MFM gap 1
extern unsigned char DAT_0000fbc8;           // Format 2: MFM sync
extern unsigned char DAT_0000fbc9;           // Format 2: MFM gap 2
extern unsigned char DAT_0000fbca;           // Format 2: MFM gap 3
extern unsigned char DAT_0000fbcb;           // Format 2: MFM gap 4
extern unsigned int DAT_0000fbcc;            // Format 3: Capacity
extern unsigned char DAT_0000fbd0;           // Format 3: Flags
extern unsigned char DAT_0000fbd1;           // Format 3: Sectors/track
extern unsigned char DAT_0000fbd2;           // Format 3: Tracks
extern unsigned short DAT_0000fbd4;          // Format 3: Sector size
extern unsigned short DAT_0000fbd6;          // Format 3: Track size
extern unsigned char DAT_0000fbd8;           // Format 3: Type
extern unsigned char DAT_0000fbd9;           // Format 3: Heads
extern unsigned char DAT_0000fbda;           // Format 3: Reserved
extern unsigned char DAT_0000fbdb;           // Format 3: MFM gap 1
extern unsigned char DAT_0000fbdc;           // Format 3: MFM sync
extern unsigned char DAT_0000fbdd;           // Format 3: MFM gap 2
extern unsigned char DAT_0000fbde;           // Format 3: MFM gap 3
extern unsigned char DAT_0000fbdf;           // Format 3: MFM gap 4
extern unsigned int DAT_0000fbe0;            // Format 4: Capacity
extern unsigned char DAT_0000fbe4;           // Format 4: Flags
extern unsigned char DAT_0000fbe5;           // Format 4: Sectors/track
extern unsigned char DAT_0000fbe6;           // Format 4: Tracks
extern unsigned short DAT_0000fbe8;          // Format 4: Sector size
extern unsigned short DAT_0000fbea;          // Format 4: Track size
extern unsigned char DAT_0000fbec;           // Format 4: Type
extern unsigned char DAT_0000fbed;           // Format 4: Heads
extern unsigned char DAT_0000fbee;           // Format 4: Reserved
extern unsigned char DAT_0000fbef;           // Format 4: MFM gap 1
extern unsigned char DAT_0000fbf0;           // Format 4: MFM sync
extern unsigned char DAT_0000fbf1;           // Format 4: MFM gap 2
extern unsigned char DAT_0000fbf2;           // Format 4: MFM gap 3
extern unsigned char DAT_0000fbf3;           // Format 4: MFM gap 4
extern unsigned int DAT_0000fbf4;            // Format 5: Capacity
extern unsigned char DAT_0000fbf8;           // Format 5: Flags
extern unsigned char DAT_0000fbf9;           // Format 5: Sectors/track
extern unsigned char DAT_0000fbfa;           // Format 5: Tracks
extern unsigned short DAT_0000fbfc;          // Format 5: Sector size
extern unsigned short DAT_0000fbfe;          // Format 5: Track size
extern unsigned char DAT_0000fc00;           // Format 5: Type
extern unsigned char DAT_0000fc01;           // Format 5: Heads
extern unsigned char DAT_0000fc02;           // Format 5: Reserved
extern unsigned char DAT_0000fc03;           // Format 5: MFM gap 1
extern unsigned char DAT_0000fc04;           // Format 5: MFM sync
extern unsigned char DAT_0000fc05;           // Format 5: MFM gap 2
extern unsigned char DAT_0000fc06;           // Format 5: MFM gap 3

// Media scan task globals
extern unsigned int _MediaScanTaskID;        // Media scan task ID
extern void *_MediaScanTask;                 // Media scan task structure
extern void *_entry;                         // Task entry point
extern unsigned int FUN_0000a300(void *entry, void *task);  // Task launch function

// Drive structure table and power state globals
extern unsigned int DAT_0000f540;            // Drive structure table base
extern unsigned short DAT_0000fb8a;          // Power state/deferred power down mode
extern int DAT_0000fb8c;                     // Deferred power down drive structure

// Block read and cache management functions
extern short _RecalDrive(int driveStructure);
extern unsigned int _RecordError(unsigned int errorCode);
extern void _ResetBitArray(int bitArrayPtr, unsigned int arraySize);
extern void _ResetBusyFlag(void);
extern void _ResetDBDMA(int dbdmaDescriptor);
extern void _ResetDMAChannel(void);

// Media scan and drive control functions
extern void _ScanForDisketteChange(void);
extern int _SeekDrive(int driveStructure);
extern bool _SetBusyFlag(void);
extern void _SetCacheAddresses(int driveStructure);
extern void _SetDBDMAPhysicalAddress(int dbdmaStructure, uint direction, uint bufferAddress, uint transferSize);

// Helper functions referenced by the above
extern int _CheckDriveNumber(int driveNumber, int *driveStructureOut);
extern void _SetSectorsPerTrack(int driveStructure);

// Format and configuration functions
extern void _SetDisketteFormat(int driveStructure, short formatIndex);
extern undefined4 _SetOSEvent(uint *eventFlags, uint eventMask);
extern void _SetSectorAddressBlocksize(int driveStructure);
extern undefined4 _SleepUntilReady(void);

// Additional helper functions
extern void _BuildTrackInterleaveTable(int driveStructure, unsigned char sectorsPerTrack);
extern int FUN_00006df0(int param_1, void *param_2);  // Event wait function
extern void FUN_00006de0(void *param_1);               // Event signal function

// DBDMA control functions
extern void _StartDBDMA(int dbdmaDescriptor);
extern void _StartDMAChannel(undefined4 bufferAddress, int transferSize, short direction);
extern void _StopDBDMA(int dbdmaDescriptor);
extern undefined4 _StopDMAChannel(void);

// SWIM III mode control functions
extern void _SwimIIISetReadMode(void);
extern void _SwimIIISetFormatMode(void);
extern void _SwimIIISetWriteMode(void);

// SWIM III controller hardware functions
extern void _SwimIIIAddrSignal(byte addressSignal);
extern void _SwimIIIDisableRWMode(void);
extern void _SwimIIIDiskSelect(int driveStructure);
extern void _SwimIIIHeadSelect(short headNumber);
extern byte _SwimIIISenseSignal(byte signalAddress);
extern void _SwimIIISetSignal(byte signalAddress);

// SWIM III timing and control functions
extern void _SwimIIISmallWait(char waitDuration);
extern int _SwimIIIStepDrive(short stepCount);
extern undefined4 _SwimIIITimeOut(uint *timeoutCounter);

// I/O synchronization
extern void _SynchronizeIO(void);
extern void enforceInOrderExecutionIO(void);

// Bit array operations
extern bool _TestBitArray(int bitArrayPtr, uint arraySize);

// Event management functions
extern void _CancelOSEvent(void *eventPtr, unsigned int eventMask);
extern undefined4 _WaitForEvent(undefined4 timeoutMs, byte eventMask, byte waitMask);
extern bool _WaitForOSEvent(uint *eventFlags, uint eventMask, int timeout, uint *resultFlags);

// Cache test functions
extern bool _TestTrackInCache(int driveStructure);

// Write operations
extern int _WriteBlocks(int driveStructure, int *actualBytes);
extern int _WriteCacheToDiskTrack(int driveStructure);
extern int _WriteSectorToCacheMemory(int driveStructure);

// Low-level OS event functions
extern void FUN_00006ee8(int param_1, void *param_2, unsigned int param_3);  // Event lock/wait
extern void FUN_00006ed8(void *param_1, unsigned int param_2);                // Event unlock

// Global variables for DMA and events
extern void *_driveOSEventIDptr;                 // Drive OS event structure pointer
extern unsigned int _lastErrorsPending;          // Last error flags from hardware

// Cache tracking globals
extern unsigned char DAT_0000fb88;               // Cached drive number
extern unsigned char _ReadDataPresent;           // Read data present flags (2-byte array, indexed by head)

// Driver global state variables
extern unsigned int _theDefaultRefCon;           // Default reference constant
extern unsigned int _track_offset;               // Track offset for format operations
extern void *_other_buffer_ptr;                  // Alternate buffer pointer
extern void *_FloppySWIMIIIRegs;                 // SWIM III controller register base
extern unsigned char _lastSectorsPerTrack;       // Last sectors per track for format
extern unsigned int _Floppy_instance;            // Floppy driver instance data

// SWIM III hardware register pointers (initialized by HALReset)
extern unsigned char *DAT_0000fc20;              // SWIM III timer register
extern unsigned char *DAT_0000fc24;              // SWIM III status/control register
extern unsigned char *DAT_0000fc28;              // SWIM III format mode register
extern unsigned char *DAT_0000fc2c;              // SWIM III control register
extern unsigned char *DAT_0000fc30;              // SWIM III mode register
extern unsigned char *DAT_0000fc34;              // SWIM III data register 1
extern unsigned char *DAT_0000fc38;              // SWIM III data register 2
extern unsigned char *DAT_0000fc3c;              // SWIM III interrupt status register
extern unsigned char *DAT_0000fc40;              // SWIM III step register
extern unsigned char *DAT_0000fc44;              // SWIM III address mark register
extern unsigned char *DAT_0000fc48;              // SWIM III sector register
extern unsigned char *DAT_0000fc4c;              // SWIM III data buffer register
extern unsigned char *DAT_0000fc50;              // SWIM III DMA control register
extern unsigned char *DAT_0000fc54;              // SWIM III error register
extern unsigned char *DAT_0000fc58;              // SWIM III interrupt enable register

// Delay/timing functions
extern void FUN_0000af58(unsigned int microseconds);  // Microsecond delay function
extern unsigned int FUN_00002710;                     // Timeout calculation value

// Sector size information tables for different floppy formats
extern unsigned int _ssi_1mb[12];                    // 1MB (1024KB) floppy format info
extern unsigned int _ssi_2mb[12];                    // 2MB (2048KB) floppy format info
extern unsigned int _ssi_4mb[12];                    // 4MB (4096KB) floppy format info

// Device and buffer management
extern unsigned int _Floppy_dev[2];                  // Device structure (8 bytes)
extern void *_trackBuffer;                           // Track buffer pointer
extern unsigned int _FloppyState;                    // Current floppy state

// Floppy ID mapping structure (64 bytes)
extern unsigned char _FloppyIdMap[64];

// Drive status and DBDMA structures
extern unsigned int _myDriveStatus;                  // Drive status
extern unsigned char _PrivDBDMAChannelArea[4];       // DBDMA channel area
extern unsigned int DAT_0000f500;                    // DBDMA descriptor pointer
extern unsigned int DAT_0000f510;                    // DBDMA command buffer
extern unsigned int DAT_0000f514;                    // DBDMA command buffer end

// DMA registers and command chain
extern unsigned int _GRCFloppyDMARegs;               // DMA registers base
extern unsigned int _GRCFloppyDMAChannel;            // DMA channel descriptor
extern unsigned int _ccCommandsLogicalAddr;          // Command chain logical address
extern unsigned int _ccCommandsPhysicalAddr;         // Command chain physical address

// Sony drive variables
extern unsigned char _SonyVariables[8];              // Sony drive variables

// Lookup table type definition
typedef struct {
    unsigned int id;        // Command/operation ID
    unsigned int address;   // Handler function address
} LookupEntry;

// Lookup tables for command dispatch
extern LookupEntry _fdrValues[];                     // Floppy disk read/operation value table (24 entries)
extern LookupEntry _fdOpValues[];                    // Floppy disk operation value table (18 entries)
extern LookupEntry _fdCommandValues[];               // Floppy disk command value table (6 entries)
extern LookupEntry _fcOpcodeValues[];                // Floppy controller opcode value table (17 entries)

// Error code mapping functions
extern unsigned int _fdrToIo(unsigned int fdrCode); // Convert floppy error code to IOKit error code

// Drive information structures
typedef struct {
    char model[40];           // Drive model name (null-terminated string)
    unsigned int blockSize;   // Block size in bytes
    unsigned int maxBlocks;   // Maximum number of blocks
    unsigned int param1;      // Drive parameter 1
    unsigned int param2;      // Drive parameter 2
    unsigned int param3;      // Drive parameter 3
    unsigned int flags;       // Drive flags
} DriveInfo;

typedef struct {
    unsigned int formatType;  // Format type identifier
    unsigned int param1;      // Format parameter 1
    unsigned int param2;      // Format parameter 2
    unsigned int param3;      // Format parameter 3
    unsigned int param4;      // Format parameter 4
    unsigned int param5;      // Format parameter 5
    unsigned int param6;      // Format parameter 6
    unsigned int param7;      // Format parameter 7
} DiskFormatInfo;

// Drive and disk configuration data
extern DriveInfo _fdDriveInfo;        // Sony MPX-111N drive information
extern DiskFormatInfo _fdDiskInfo[];  // Disk format information array

// Density and sector size mapping structures
typedef struct {
    unsigned int densityType;     // Density type (1=single, 2=double, 3=high)
    unsigned int *sectorSizeInfo; // Pointer to sector size info table
} DensitySectSizeEntry;

typedef struct {
    unsigned int densityType;     // Density type
    unsigned int capacityParam;   // Capacity parameter (related to total blocks)
    unsigned int flags;           // Flags or additional parameter
} DensityInfoEntry;

// Density lookup tables
extern DensitySectSizeEntry _fdDensitySectsize[];  // Maps density to sector size info
extern DensityInfoEntry _fdDensityInfo[];          // Density configuration parameters

// Thread functions
extern void _fdThread(void *arg);                    // Main floppy I/O thread

// Thread helper functions (called by _fdThread)
extern void _InitializeEventChannel(void *context, unsigned int channelID);
extern unsigned int _WaitForOSEvent(void *context, unsigned int *eventMask, unsigned int *channel);
extern void *_GetCurrentIORequest(void *context);
extern unsigned int _GetIOStatus(void *ioRequest);
extern void _CompleteIORequest(void *ioRequest, unsigned int status);
extern int _HasPendingRequests(void *context);
extern void _StartNextIORequest(void *context);
extern int _GetRetryCount(void *ioRequest);
extern void _IncrementRetryCount(void *ioRequest);
extern void _RetryIORequest(void *ioRequest);
extern void _UpdateMediaState(void *context);
extern void _ResetController(void *context);
extern unsigned int _ReadErrorStatus(void);
extern int _IsRetryableError(unsigned int status);
extern unsigned int _GetDMAStatus(void);
extern int _IsReadOperation(void *ioRequest);
extern void *_GetIOBuffer(void *ioRequest);
extern unsigned int _GetIOLength(void *ioRequest);
extern void _CleanupEventChannels(void *context);

/* End of FloppyDisk.h */
