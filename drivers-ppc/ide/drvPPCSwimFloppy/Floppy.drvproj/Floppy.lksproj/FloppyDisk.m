/*
 * FloppyDisk.m - PPC SWIM Floppy disk device class implementation
 *
 * Main class for SWIM floppy disk devices
 */

#import "FloppyDisk.h"
#import <driverkit/return.h>
#import <driverkit/debugging.h>
#import <driverkit/IODirectDevice.h>
#import <objc/objc-runtime.h>
#import <string.h>
#import <stdio.h>

// Forward declaration
@class FloppyController;

/*****************************************************************************
 * Constants and Configuration Values
 *****************************************************************************/

// I/O retry configuration
#define MAX_RETRY_COUNT         3       // Maximum number of retries for I/O operations

// Error codes (IOKit error values as unsigned int)
#define IO_ERROR_TIMEOUT        0xfffffd31  // -719: Timeout error
#define IO_ERROR_DEVICE_ERROR   0xfffffd36  // -714: General device error
#define IO_ERROR_MEDIA          0xfffffd2c  // -724: Media error
#define IO_ERROR_WRITE_PROTECT  0xfffffd30  // -720: Write protected
#define IO_ERROR_NOT_READY      0xfffffbb2  // -1102: Device not ready
#define IO_ERROR_CRC            0xfffffd38  // -712: CRC error
#define IO_ERROR_UNDERRUN       0xfffffd39  // -711: Data underrun
#define IO_ERROR_SEEK           0xfffffd40  // -704: Seek error
#define IO_ERROR_DATA           0xfffffd43  // -701: Data error
#define IO_ERROR_UNKNOWN        0xfffffd37  // -713: Unknown error

// SWIM III controller timing constants
#define SWIM3_TIMEOUT_TICKS     1000000 // Controller timeout in microseconds
#define SWIM3_SETTLE_TIME       15000   // Head settle time in microseconds
#define SWIM3_MOTOR_SPINUP      500000  // Motor spin-up time in microseconds

// Track cache configuration
#define TRACK_CACHE_SIZE        (20 * 1024)  // 20KB track cache
#define MAX_SECTORS_PER_TRACK   12           // Maximum sectors per track (GCR format)
#define SECTOR_DIRTY_BYTES      2            // Bytes needed for sector dirty bits

// DMA configuration
#define DBDMA_ALIGN_MASK        0x7FFF       // DBDMA must not cross 32KB boundaries
#define DBDMA_MAX_TRANSFER      0x10000      // Maximum DMA transfer size (64KB)

// Drive power management
#define POWER_DOWN_DELAY        5000         // Delay before drive power down (ms)

// GCR encoding parameters
#define GCR_GROUP_SIZE          3            // 3 bytes encoded to 4 bytes
#define GCR_ENCODED_SIZE        4
#define GCR_CHECKSUM_SEED       0            // Initial checksum value

// FdBuffer structure (from FloppyDiskInt.m)
typedef struct _FdBuffer {
    void *reserved1;           // offset 0x00: command code
    void *reserved2;           // offset 0x04: I/O request pointer
    unsigned int actualLength; // offset 0x08: actual bytes transferred
    void *reserved4;           // offset 0x0c
    void *reserved5;           // offset 0x10: parameter pointer
    void *reserved6;           // offset 0x14
    id conditionLock;          // offset 0x18: NXConditionLock
    void *callback;            // offset 0x1c: callback parameter
    int flags;                 // offset 0x20: operation flags
    void *reserved7;           // offset 0x24
    int status;                // offset 0x28: I/O completion status
    struct _FdBuffer *prev;    // offset 0x2c: previous buffer
    struct _FdBuffer *next;    // offset 0x30: next buffer
} FdBuffer;

// Command names for logging (shared with FloppyDiskThread.m)
const char *_fdCommandValues[] = {
    "RECALIBRATE", "SEEK", "READ", "WRITE", "READ_ID",
    "WRITE_DELETED", "READ_TRACK", "FORMAT", "SENSE_INT",
    "SPECIFY", "SENSE_DRIVE", "UNKNOWN_B", "UNKNOWN_C",
    "CONFIGURE", "UNKNOWN_E", "UNKNOWN_F"
};

// Density value table structure
typedef struct {
    unsigned int reserved;
    const char *name;
    unsigned int value;
} DensityEntry;

// Density names and values table (shared with FloppyDiskThread.m)
DensityEntry _densityValues[] = {
    {0, "Auto", 0},
    {0, "500kbps", 1},
    {0, "300kbps", 2},
    {0, "1Mbps", 3},
    {0, NULL, 0}  // End marker
};

// MID (Media ID) value table
DensityEntry _midValues[] = {
    {0, "Unknown", 0},
    {0, "MFM_1Mbps", 1},
    {0, "MFM_500kbps", 2},
    {0, "GCR_Var", 3},
    {0, NULL, 0}  // End marker
};

// Ioctl command table structure
typedef struct {
    unsigned int cmd;
    const char *name;
} IoctlEntry;

// Floppy disk ioctl commands
IoctlEntry _fdIoctlValues[] = {
    {0x80046417, "DKIOCGLABEL"},      // Get disk label
    {0x40046417, "DKIOCSLABEL"},      // Set disk label
    {0x5c5c6400, "DKIOCGFORMAT"},     // Get format info
    {0x9c5c6401, "DKIOCSFORMAT"},     // Set format info
    {0x20006415, "DKIOCEJECT"},       // Eject disk
    {0xc0606600, "DKIOCGGEOM"},       // Get geometry
    {0x40346601, "DKIOCSGEOM"},       // Set geometry
    {0x80046602, "DKIOCGPART"},       // Get partition
    {0x80046603, "DKIOCSPART"},       // Set partition
    {0x80046604, "DKIOCGVOLNAME"},    // Get volume name
    {0x80046606, "DKIOCGFREEVOLS"},   // Get free volumes
    {0x40046607, "DKIOCRENAME"},      // Rename volume
    {0x80046608, "DKIOCGMAXPART"},    // Get max partitions
    {0x40046609, "DKIOCWLABEL"},      // Write label
    {0x40306405, "DKIOCFORMAT"},      // Format disk
    {0, NULL}                          // End marker
};

// Helper function to get status name from string array
const char *_getStatusName(unsigned int statusCode, const char **values)
{
    // Assume reasonable bounds for command arrays
    if (statusCode < 16) {
        return values[statusCode];
    }
    return "Unknown";
}

// Helper function to get density name from density table
const char *_getDensityName(unsigned int densityCode, DensityEntry *table)
{
    while (table->name != NULL) {
        if (table->value == densityCode) {
            return table->name;
        }
        table++;
    }
    return "Unknown";
}

// Helper function to get ioctl name
const char *_getIoctlName(unsigned int ioctlCmd)
{
    IoctlEntry *entry = _fdIoctlValues;
    while (entry->name != NULL) {
        if (entry->cmd == ioctlCmd) {
            return entry->name;
        }
        entry++;
    }
    return "Unknown";
}

// Global variables
void *_DataSource = (void *)0x00000001;          // Data source tracker
unsigned int _busyflag = 0;                      // Controller busy flag
unsigned int _ccCommandsLogicalAddr = 0;         // Command buffer logical address
unsigned int _ccCommandsPhysicalAddr = 0;        // Command buffer physical address

/*
 * FloppyController class
 * Controller class for SWIM floppy hardware
 */
@interface FloppyController : IODirectDevice
@end

@implementation FloppyController

/*
 * Class method: Probe for floppy controller
 * Forwards probe request to FloppyDisk class
 */
+ (BOOL)probe:(id)deviceDescription
{
    IOLog("Probe in Floppycontroller. calling FloppyDisk probe\n");

    // Forward probe to FloppyDisk class
    return [FloppyDisk probe:deviceDescription];
}

@end


@implementation FloppyDisk

/*
 * Class method: Return device style
 */
+ (int)deviceStyle
{
    return 1;  // Direct device style
}

/*
 * Class method: Return required protocols
 */
+ (Protocol **)requiredProtocols
{
    extern Protocol *_protocols[];
    return _protocols;
}

/*
 * Class method: Probe for floppy devices
 */
+ (BOOL)probe:(id)deviceDescription
{
    int idMap;
    id directDevice;
    int driveIndex;
    BOOL addedCdev, addedBdev;
    id diskInstance = nil;
    id firstDisk = nil;
    int registeredCount = 0;
    int initResult;
    void *lockPtr;
    int pluginResult;

    // External function declarations
    extern int _floppy_idmap(void);
    extern int _drive_present(void);
    extern void _fd_init_idmap(id classObj);
    extern void *(*_entry)(int, int, void *, int);
    extern void _HALISRHandler(void);
    extern int _FloppyPluginInit(int);
    extern void *_slock;

    // Character device operations
    extern int _Fdopen(void);
    extern int _Fdclose(void);
    extern int _fdread(void);
    extern int _fdwrite(void);
    extern int _fdioctl(void);

    // Block device operations
    extern int _fdstrategy(void);
    extern int _fdsize(void);

    IOLog("Floppy Probed \n");
    IOLog("FloppyDisk probe\n");

    // Get ID map
    idMap = _floppy_idmap();

    // Get direct device from device description
    directDevice = [deviceDescription directDevice];

    // Check if floppy drive is present
    if (_drive_present() == 0) {
        return NO;
    }

    IOLog("Calling addCdev\n");

    // Add character device to cdevsw table
    addedCdev = [self addToCdevswFromDescription:deviceDescription
                                            open:(void *)_Fdopen
                                           close:(void *)_Fdclose
                                            read:(void *)_fdread
                                           write:(void *)_fdwrite
                                           ioctl:(void *)_fdioctl
                                            stop:NULL
                                           reset:NULL
                                          select:NULL
                                            mmap:NULL
                                        getc:NULL
                                        putc:NULL];

    if (!addedCdev) {
        IOLog("FloppyDisk: could not add to cdevsw table\n");
        return NO;
    }

    IOLog("Calling addBdev\n");

    // Add block device to bdevsw table
    addedBdev = [self addToBdevswFromDescription:deviceDescription
                                            open:(void *)_Fdopen
                                           close:(void *)_Fdclose
                                        strategy:(void *)_fdstrategy
                                           ioctl:(void *)_fdioctl
                                            dump:NULL
                                          psize:(void *)_fdsize
                                           flags:0];

    if (!addedBdev) {
        IOLog("FloppyDisk: could not add to bdevsw table\n");
        return NO;
    }

    IOLog("calling fd_init_idmap\n");
    _fd_init_idmap(self);

    // Allocate and initialize lock structure
    lockPtr = IOMalloc(16);  // 4 ints = 16 bytes
    bzero(lockPtr, 16);
    _slock = lockPtr;

    IOLog("calling FloppyPluginInit\n");

    // Initialize interrupt handler
    (*_entry)(0x88, 0x18, (void *)_HALISRHandler, 0);

    // Initialize floppy plugin
    pluginResult = _FloppyPluginInit(0);
    if (pluginResult != 0) {
        return NO;
    }

    IOLog("calling pmac_register_int\n");

    // Probe for floppy drives (up to 1 drive)
    for (driveIndex = 0; driveIndex < 1; driveIndex++) {
        // Allocate FloppyDisk instance if needed
        if (diskInstance == nil) {
            IOLog("allocating FloppyDisk\n");
            diskInstance = [FloppyDisk new];

            IOLog("calling initResources\n");
            [diskInstance _initResources:directDevice];

            IOLog("calling setDevAndIdInfo\n");
            [diskInstance setDevAndIdInfo:(void *)(idMap + driveIndex * 0x4c)];
        }

        IOLog("calling floppyInit\n");
        initResult = [diskInstance _floppyInit:driveIndex];
        IOLog("FloppyDisk.m: floppyInit rtn=%d\n", initResult);

        if (initResult == 0) {
            // Successfully initialized drive
            IOLog("fd probe: registering drive %d\n", driveIndex);

            [diskInstance setDeviceDescription:deviceDescription];

            IOLog("calling setdeviceKind\n");
            [diskInstance setDeviceKind:"FloppyDisk"];

            IOLog("calling setIsPhysical\n");
            [diskInstance setIsPhysical:YES];

            IOLog("calling registerDevice\n");
            [diskInstance registerDevice];
            IOLog("registerDevice returned\n");

            // Save first registered disk
            if (firstDisk == nil) {
                firstDisk = diskInstance;
            }

            // Clear instance for next drive
            diskInstance = nil;
            registeredCount++;
        }
    }

    // Free any unused disk instance
    if (diskInstance != nil) {
        [diskInstance free];
    }

    // If no drives were registered, remove from device tables
    if (registeredCount == 0) {
        [self removeFromCdevsw];
        [self removeFromBdevsw];
    }

    IOLog("FloppyDisk:probe returns\n");
    return YES;
}

/*
 * Abort current request
 */
- (IOReturn)_abortRequest
{
    IOLog("fd abortRequest\n");

    // Send abort command (5) with no buffer, disk not required
    return [self _fdSimpleCommand:5 buffer:NULL needsDisk:NO];
}

/*
 * Close device
 */
- (IOReturn)_deviceClose
{
    // Nothing to do on close
    return IO_R_SUCCESS;
}

/*
 * Open device
 */
- (IOReturn)_deviceOpen:(BOOL)exclusive
{
    // Always succeeds
    return IO_R_SUCCESS;
}

/*
 * Disk became ready notification
 */
- (void)_diskBecameReady
{
    IOLog(" fd diskBecameReady\n");

    // Lock the queue
    [_queueLock lock];

    // Unlock with value 1 to wake up I/O thread
    [_queueLock unlockWith:1];
}

/*
 * Eject physical disk
 */
- (IOReturn)_ejectPhysical
{
    IOReturn result;

    IOLog("fd ejectPhysical\n");

    // Send eject command (4) with no buffer, disk required
    result = [self _fdSimpleCommand:4 buffer:NULL needsDisk:YES];

    IOLog("ejectPhysical: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Inner retry
 */
- (IOReturn)_innerRetry
{
    int retryCount[3];
    IOReturn result;

    IOLog("innerRetry\n");

    // Get inner retry count using command 0xc (12), disk not required
    result = [self _fdSimpleCommand:0xc buffer:retryCount needsDisk:NO];

    if (result != IO_R_SUCCESS) {
        IOLog("%s: FDC_GET_INNER_RETRY returned %s\n",
              [self name], [self stringFromReturn:result]);
    }

    IOLog("innerRetry: returning %d\n", retryCount[0]);

    return retryCount[0];
}

/*
 * Check if disk is ready
 */
- (BOOL)_isDiskReady:(id)controller
{
    int readyState;
    IOReturn result;

    IOLog("fd diskBecameReady\n");

    // Get last ready state
    readyState = objc_msgSend(self, sel_getUid("lastReadyState"));

    if (readyState == 0) {
        // Ready state is 0 - disk is ready
        return IO_R_SUCCESS;
    } else if (controller == nil) {
        // No controller provided - return IO_R_NO_DISK (0xfffffbb2 = -1102)
        return (IOReturn)0xfffffbb2;
    } else {
        // Check disk status with command 6, disk required
        result = [self _fdSimpleCommand:6 buffer:NULL needsDisk:YES];
        IOLog("fd isDiskReady: returning %s\n", [self stringFromReturn:result]);
        return result;
    }
}

/*
 * Check if needs manual polling
 */
- (BOOL)_needsManualPolling
{
    return NO;
}

/*
 * Outer retry
 */
- (IOReturn)_outerRetry
{
    int retryCount[3];
    IOReturn result;

    IOLog("outerRetry\n");

    // Get outer retry count using command 0xd (13), disk not required
    result = [self _fdSimpleCommand:0xd buffer:retryCount needsDisk:NO];

    if (result != IO_R_SUCCESS) {
        IOLog("%s: FDC_GET_INNER_RETRY returned %s\n",
              [self name], [self stringFromReturn:result]);
    }

    IOLog("outerRetry: returning %d\n", retryCount[0]);

    return retryCount[0];
}

/*
 * Get IODeviceType property
 */
- (IOReturn)_property_IODeviceType:(char *)types
                            length:(unsigned int *)maxLen
{
    // Call superclass implementation first
    [super _property_IODeviceType:types length:maxLen];

    // Append " IOFloppy" to the type string
    strcat(types, " IOFloppy");

    return IO_R_SUCCESS;
}

/*
 * Get IOUnit property
 */
- (IOReturn)_property_IOUnit:(unsigned int *)unit
                      length:(unsigned int *)length
{
    unsigned int unitNum;

    // Get unit number
    unitNum = [self unit];

    // Format as string into unit buffer
    sprintf((char *)unit, "%d", unitNum);

    return IO_R_SUCCESS;
}

/*
 * Asynchronous read operation
 */
- (IOReturn)readAsyncAt:(unsigned)offset
                 length:(unsigned)length
                 buffer:(void *)buffer
                pending:(void *)pending
                 client:(vm_task_t)client
{
    IOReturn result;

    IOLog("readAsyncAt\n");
    IOLog("fd readAsync: offset 0x%x length 0x%x\n", offset, length);

    // Call common read/write handler
    // Parameters: isRead=1, block=offset, length, buffer, client, pending, actualLength=NULL
    result = [self _deviceRwCommon:YES
                             block:offset
                            length:length
                            buffer:buffer
                            client:client
                           pending:pending
                      actualLength:NULL];

    IOLog("fd readAsync: RETURNING %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Synchronous read operation
 */
- (IOReturn)readAt:(unsigned)offset
            length:(unsigned)length
            buffer:(void *)buffer
      actualLength:(unsigned *)actualLength
            client:(vm_task_t)client
{
    IOReturn result;
    extern void *_DataSource;

    IOLog("fd read: offset 0x%x length 0x%x\n", offset, length);

    // Call common read/write handler
    // Parameters: isRead=1, block=offset, length, buffer, client, pending=NULL, actualLength
    result = [self _deviceRwCommon:YES
                             block:offset
                            length:length
                            buffer:buffer
                            client:client
                           pending:NULL
                      actualLength:actualLength];

    IOLog("FloppyDisk.m:ReadAt:offset=%d,len=%d,datasource=0x%x\n",
          offset, length, (unsigned int)_DataSource);

    IOLog("fd read: RETURNING %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Update physical parameters
 */
- (IOReturn)_updatePhysicalParameters
{
    IOReturn result;

    IOLog("fd updatePhysicalParameters\n");

    // Send update parameters command (0xf = 15), no buffer, disk not required
    result = [self _fdSimpleCommand:0xf buffer:NULL needsDisk:NO];

    IOLog("updatePhysicalParameters: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Update ready state
 */
- (void)_updateReadyState
{
    int state;

    // External functions for diskette state management
    extern void _GetBusyFlag(void);
    extern void _ScanForDisketteChange(void);
    extern int _GetCurrentState(void);
    extern void _ResetBusyFlag(void);

    // Lock controller
    _GetBusyFlag();

    // Scan for disk insertion/removal
    _ScanForDisketteChange();

    // Get current disk state
    state = _GetCurrentState();

    // Unlock controller
    _ResetBusyFlag();
}

/*
 * Asynchronous write operation
 */
- (IOReturn)writeAsyncAt:(unsigned)offset
                  length:(unsigned)length
                  buffer:(void *)buffer
                 pending:(void *)pending
                  client:(vm_task_t)client
{
    IOReturn result;

    IOLog("writeAsyncAt:\n");
    IOLog("fd writeAsync: offset 0x%x length 0x%x\n", offset, length);

    // Call common read/write handler
    // Parameters: isRead=NO (2), block=offset, length, buffer, client, pending, actualLength=NULL
    result = [self _deviceRwCommon:NO
                             block:offset
                            length:length
                            buffer:buffer
                            client:client
                           pending:pending
                      actualLength:NULL];

    IOLog("fd writeAsync: RETURNING %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Synchronous write operation
 */
- (IOReturn)writeAt:(unsigned)offset
             length:(unsigned)length
             buffer:(void *)buffer
       actualLength:(unsigned *)actualLength
             client:(vm_task_t)client
{
    IOReturn result;
    extern void *_DataSource;

    IOLog("fd write: offset 0x%x length 0x%x\n", offset, length);
    IOLog("FloppyDisk.m:WriteAt:offset=%d,len=%d,datasource=0x%x\n",
          offset, length, (unsigned int)_DataSource);

    // Call common read/write handler
    // Parameters: isRead=NO (2), block=offset, length, buffer, client, pending=NULL, actualLength
    result = [self _deviceRwCommon:NO
                             block:offset
                            length:length
                            buffer:buffer
                            client:client
                           pending:NULL
                      actualLength:actualLength];

    IOLog("fd write: RETURNING %s\n", [self stringFromReturn:result]);

    return result;
}


/*
 * Floppy command transfer
 */
- (IOReturn)_fdCmdXfr:(void *)command
{
    typedef struct {
        unsigned int field0;
        unsigned int field1;
        unsigned int field2;  // Command code at offset 0x8
        void *parameters;     // Parameters at offset 0xc
    } FdCommand;

    FdCommand *cmd = (FdCommand *)command;
    FdBuffer *fdBuf;
    IOReturn result;
    const char *cmdName;

    // Command value names for logging
    extern const char *_fdCommandValues[];
    extern const char *_getStatusName(unsigned int code, const char **values);

    cmdName = _getStatusName(cmd->field2, _fdCommandValues);
    IOLog("fdCmdXfr: command %s\n", cmdName);

    // Allocate FdBuffer with size 0 (synchronous operation)
    fdBuf = (FdBuffer *)[self _allocFdBuf:0];

    // Set up buffer fields
    fdBuf->reserved1 = 0;                    // Command code 0 (FD_SEND_CMD)
    fdBuf->reserved2 = command;              // Command pointer
    fdBuf->reserved5 = cmd->parameters;      // Parameters pointer

    // Set flags: clear bit 29, set bits 30 and 31
    // Bit 30 (0x40000000) = async flag (cleared for sync)
    // Bit 31 (0x80000000) = priority flag
    fdBuf->flags = (fdBuf->flags & 0xdfffffff) | 0xc0000000;

    // Enqueue and wait for completion
    [self _enqueueFdBuf:(id)fdBuf];

    // Get result from buffer status
    result = fdBuf->status;

    IOLog("fdCmdXfr: returning %s\n", [self stringFromReturn:result]);

    // Free buffer
    [self _freeFdBuf:(id)fdBuf];

    return result;
}

/*
 * Get format information
 */
- (IOReturn)_fdGetFormatInfo:(void *)formatInfo
{
    IOReturn result;

    IOLog("fdGetFormatInfo\n");

    // Send get format info command (0xe = 14), disk not required
    result = [self _fdSimpleCommand:0xe buffer:formatInfo needsDisk:NO];

    IOLog("fdGetFormatInfo: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Turn motor off
 */
- (IOReturn)_fdMotorOff
{
    unsigned char cmdBuf[96];

    IOLog("fdMotorOff\n");

    // Initialize command buffer
    bzero(cmdBuf, 96);

    // Set motor off command code (4) at offset 0x38
    *(unsigned int *)(cmdBuf + 0x38) = 4;

    // Send command, disk not required
    [self _fdSimpleIoReq:cmdBuf needsDisk:NO];

    IOLog("fd fdMotorOff: done\n");

    return IO_R_SUCCESS;
}

/*
 * Set density
 */
- (IOReturn)_fdSetDensity:(unsigned)density
{
    IOReturn result;
    const char *densityName;

    // Get density name from table
    extern const char *_getDensityName(unsigned int code, DensityEntry *table);

    densityName = _getDensityName(density, _densityValues);
    IOLog("fdSetDensity: density = %s\n", densityName);

    // Send set density command (7) with density value, disk required
    result = [self _fdSimpleCommand:7 buffer:&density needsDisk:YES];

    IOLog("fdSetDensity: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Set gap length
 */
- (IOReturn)_fdSetGapLength:(unsigned)gap
{
    IOReturn result;

    IOLog("fdSetGapLength: sectSize = %d\n", gap);

    // Send set gap command (9) with gap value, disk required
    result = [self _fdSimpleCommand:9 buffer:&gap needsDisk:YES];

    IOLog("fdSetGapLength: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Set inner retry count
 */
- (IOReturn)_fdSetInnerRetry:(unsigned)retry
{
    IOReturn result;

    IOLog("fdSetInnerRetry: innerRetry = %d\n", retry);

    // Send set inner retry command (10) with retry value, disk not required
    result = [self _fdSimpleCommand:10 buffer:&retry needsDisk:NO];

    IOLog("fdSetInnerRetry: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Set outer retry count
 */
- (IOReturn)_fdSetOuterRetry:(unsigned)retry
{
    IOReturn result;

    IOLog("fdSetOuterRetry: outerRetry = %d\n", retry);

    // Send set outer retry command (0xb = 11) with retry value, disk not required
    result = [self _fdSimpleCommand:0xb buffer:&retry needsDisk:NO];

    IOLog("fdSetOuterRetry: returning %s\n", [self stringFromReturn:result]);

    return result;
}

/*
 * Set sector size
 */
- (IOReturn)_fdSetSectSize:(unsigned)sectSize
{
    IOReturn result;

    IOLog("fdSetSectSize: sectSize = %d\n", sectSize);

    // Send set sector size command (8) with size value, disk required
    result = [self _fdSimpleCommand:8 buffer:&sectSize needsDisk:YES];

    IOLog("fdSetSectSize: returning %s\n", [self stringFromReturn:result]);

    return result;
}

@end

/*
 * C Utility Functions
 */

// Global variables for cache and state
unsigned short DAT_0000fb88 = 0;  // Track cache variable
unsigned int _FloppyState = 0;     // Floppy state variable
char DAT_0000f25e = 0;             // Drive index storage

/*
 * Assign track to cache
 */
void _AssignTrackInCache(int param_1)
{
    unsigned char trackNum;
    unsigned char cacheIndex;

    // Get track number from offset 0x46
    trackNum = *(unsigned char *)(param_1 + 0x46);
    DAT_0000fb88 = (unsigned short)trackNum;

    // Get cache index from offset 0x21
    cacheIndex = *(unsigned char *)(param_1 + 0x21);

    // Store track number at computed offset (0xb4 + cacheIndex)
    *(unsigned char *)(param_1 + cacheIndex + 0xb4) = *(unsigned char *)(param_1 + 0x20);
}

/*
 * Determine available formats for diskette
 */
void _AvailableFormats(int param_1, unsigned short *minFormat, unsigned short *maxFormat,
                       short *formatType)
{
    short diskFormatType;
    unsigned short format;

    // Initialize outputs
    *minFormat = 0;
    *formatType = 0;
    *maxFormat = 1;

    // Check field at offset 0x40
    if (*(int *)(param_1 + 0x40) == 1) {
        *formatType = 1;
    }

    // Check field at offset 0x47
    if (*(char *)(param_1 + 0x47) == -1) {
        *maxFormat = 2;

        // Check field at offset 0x48
        if (*(char *)(param_1 + 0x48) != -1) {
            return;
        }

        // Get diskette format type from hardware
        extern short _GetDisketteFormatType(void);
        diskFormatType = _GetDisketteFormatType();
        *formatType = diskFormatType;

        if (diskFormatType == 3) {
            // Format type 3
            *minFormat = 3;
            format = 4;
        } else if (diskFormatType < 4) {
            if (diskFormatType != 2) {
                return;
            }
            // Format type 2
            format = 2;
        } else {
            if (diskFormatType != 5) {
                return;
            }
            // Format type 5
            format = 5;
        }

        *minFormat = format;
        *maxFormat = format;
    }
}

/*
 * Get block list descriptor extent
 */
unsigned int _BSBlockListDescriptorGetExtent(unsigned int param_1, unsigned int param_2,
                                              unsigned int *startBlock, unsigned int *blockCount)
{
    // Set default extent: start at 0, count 0x5000 blocks
    *startBlock = 0;
    *blockCount = 0x5000;
    return 0;
}

/*
 * Notify family store changed state
 */
unsigned int _BSMPINotifyFamilyStoreChangedState(unsigned int param_1, unsigned int newState)
{
    // Update global floppy state
    _FloppyState = newState;
    return 0;
}

/*
 * Build track interleave table
 * Creates sector interleave pattern for optimal disk access
 */
void _BuildTrackInterleaveTable(int param_1, unsigned int sectorCount)
{
    unsigned char firstSector;
    unsigned int interleave;
    unsigned int increment;
    unsigned int currentSector;
    unsigned int nextSector;
    unsigned int index;
    unsigned int limit;
    unsigned int sectorsPerCylinder;

    sectorCount = sectorCount & 0xff;

    // Determine interleave increment
    if (*(unsigned char *)(param_1 + 0x59) < 2) {
        // No interleave or single interleave
        increment = 1;
        interleave = 2;
    } else {
        // Calculate interleave based on value at offset 0x59
        increment = (sectorCount / *(unsigned char *)(param_1 + 0x59) + (sectorCount & 1)) & 0xff;
        interleave = increment;
    }

    // Get first sector number (offset 0x58)
    firstSector = *(unsigned char *)(param_1 + 0x58);
    currentSector = (unsigned int)firstSector;
    sectorsPerCylinder = sectorCount;

    // Build interleave table
    limit = (sectorCount - 2) & 0xff;
    if (limit != 0xff) {
        index = currentSector;

        do {
            currentSector = interleave;

            // Store sector number in interleave table at offset 0x60
            *(char *)(param_1 + index + 0x60) = (char)currentSector;

            // Calculate next sector with interleave
            interleave = (currentSector + increment) & 0xff;

            // Wrap around if necessary
            if ((sectorCount + firstSector & 0xff) <= interleave) {
                interleave = (interleave - (sectorCount - ((sectorCount & 1) ^ 1))) & 0xff;
            }

            limit = (limit - 1) & 0xff;
            index = currentSector;
        } while (limit != 0xff);
    }

    // Store first sector at end of table
    *(unsigned char *)(param_1 + currentSector + 0x60) = *(unsigned char *)(param_1 + 0x58);
}

/*
 * Copy bytes from source to destination
 * Simple byte-by-byte memory copy
 */
void _ByteMove(unsigned char *source, unsigned char *dest, int count)
{
    if (count > 0) {
        do {
            *dest = *source;
            dest++;
            source++;
            count--;
        } while (count > 0);
    }
}

/*
 * Cancel OS event flags
 * Clears specified event bits
 */
unsigned int _CancelOSEvent(unsigned int *eventFlags, unsigned int eventMask)
{
    // Clear event bits by ANDing with complement of mask
    *eventFlags = *eventFlags & ~eventMask;
    return 0;
}

/*
 * Check drive number validity
 * Validates drive number and initializes drive structure
 */
unsigned int _CheckDriveNumber(short driveNum, unsigned int **drivePtr)
{
    extern void *_slock;
    extern char _fdOpValues[];
    extern char DAT_0000f25e;
    extern int _OSSpinLockTry(int, void *);
    extern void sync(int);

    unsigned int *lockPtr;
    int lockResult;
    int driveOffset;

    lockPtr = (unsigned int *)_slock;

    // Validate drive number (1 or 2)
    if ((unsigned int)(driveNum - 1) < 2) {
        // Acquire spin lock
        do {
            lockResult = _OSSpinLockTry(0, lockPtr);
        } while (lockResult != 0);

        // Calculate drive structure offset (0x324 = 804 bytes per drive)
        driveOffset = driveNum * 0x324;

        // Set drive pointer to base of drive structure array
        *drivePtr = (unsigned int *)((char *)_fdOpValues + driveOffset);

        // Set drive index (0 or 1)
        *((char *)&DAT_0000f25e + driveOffset) = (char)driveNum - 1;

        // Memory synchronization barrier
        sync(0);

        // Release spin lock
        *lockPtr = 0;

        return 0;  // Success
    } else {
        return 0xffffffc8;  // -56: Invalid drive number
    }
}

/*
 * Check if drive is online
 * Verifies drive presence and media
 */
unsigned int _CheckDriveOnLine(int driveStructure)
{
    extern int _HALDiskettePresence(int);
    extern void _HALGetMediaType(int);

    int isPresent;
    unsigned int result = 0;

    // Check if drive is enabled (offset 0x3d)
    if (*(char *)(driveStructure + 0x3d) == 0x01) {
        // Check if already marked online (offset 0x3c)
        if (*(char *)(driveStructure + 0x3c) == 0x00) {
            // Check physical disk presence
            isPresent = _HALDiskettePresence(driveStructure);

            if (isPresent == 1) {
                // Mark drive as online
                *(unsigned char *)(driveStructure + 0x3c) = 1;

                // Get media type from hardware
                _HALGetMediaType(driveStructure);
            } else {
                result = 0xffffffbf;  // -65: No disk present
            }
        }
    } else {
        result = 0xffffffc0;  // -64: Drive not enabled
    }

    return result;
}

/*
 * Close DBDMA channel
 * Cleanup descriptor-based DMA channel
 */
void _CloseDBDMAChannel(void)
{
    // No operation - DBDMA cleanup handled elsewhere
    return;
}

/*
 * Create OS event resources
 * Initialize event handling resources
 */
unsigned int _CreateOSEventResources(void)
{
    // Resources created statically
    return 0;
}

/*
 * Create OS hardware lock resources
 * Initialize hardware locking resources
 */
unsigned int _CreateOSHardwareLockResources(void)
{
    // Resources created statically
    return 0;
}

/*
 * Get current address space ID
 * Returns address space identifier
 */
unsigned int _CurrentAddressSpaceID(void)
{
    // Single address space
    return 0;
}

/*
 * Denibblize GCR checksum
 * Converts nibblized GCR checksum to binary
 */
void _DenibblizeGCRChecksum(unsigned char *nibbles, unsigned int *checksum)
{
    unsigned int packed;

    // Pack nibbles into 32-bit value
    packed = (unsigned int)nibbles[0] << 2;

    *checksum = ((unsigned int)nibbles[1] | (packed & 0xc0)) << 0x10 |
                ((unsigned int)nibbles[2] | ((packed & 0x30) << 2)) << 8 |
                (unsigned int)nibbles[3] | ((packed & 0xc) << 4);
}

/*
 * Denibblize GCR data
 * Converts nibblized GCR data to binary with checksum
 */
void _DenibblizeGCRData(unsigned char *nibbles, unsigned char *output,
                        short byteCount, unsigned int *checksum)
{
    unsigned int byte0, byte1, byte2;
    unsigned char *nibPtr;
    unsigned int carry;
    unsigned int temp1, temp2;
    unsigned int packed;

    // Extract checksum bytes
    byte0 = *checksum >> 0x10 & 0xff;
    byte1 = *checksum >> 8 & 0xff;
    byte2 = *((unsigned char *)checksum + 3);

    // Process data in groups of 3 bytes
    if (byteCount > 0) {
        do {
            // Rotate byte2
            carry = byte2 >> 7;
            byte2 = (byte2 << 1) | carry;

            // Decode first byte
            packed = ((unsigned int)nibbles[0] << 2 & 0xfc) << 2;
            temp1 = ((unsigned int)nibbles[0] << 2 & 0xc0 | (unsigned int)nibbles[1]) ^ byte2;
            *output = (char)temp1;

            // Update checksum byte0
            carry = carry + byte0 + (temp1 & 0xff);
            byte0 = carry & 0xff;

            nibPtr = nibbles + 3;

            // Decode second byte
            temp1 = (packed & 0xc0 | (unsigned int)nibbles[2]) ^ byte0;
            output[1] = (char)temp1;

            // Update checksum byte1
            carry = (carry >> 8) + byte1 + temp1;
            byte1 = carry & 0xff;

            // Check if we need to process third byte
            if ((short)(byteCount - 2) < 1) break;

            nibbles = nibbles + 4;

            // Decode third byte
            packed = ((packed & 0x30) << 2 | (unsigned int)*nibPtr) ^ byte1;
            output[2] = (char)packed;

            // Update checksum byte2
            byte2 = ((carry >> 8) + byte2 + packed) & 0xff;

            output = output + 3;
            byteCount = byteCount - 3;
        } while (byteCount > 0);
    }

    // Pack checksum back
    *checksum = ((byte0 << 8 | byte1) << 8) | (byte2 & 0xff);
}

/*
 * Do nothing function
 * Placeholder for logging/debugging that's been compiled out
 */
void _donone(void)
{
    // No operation
    return;
}

/*
 * Check if drive hardware is present
 * Reads hardware register to detect floppy controller
 */
BOOL _drive_present(void)
{
    extern volatile unsigned char DAT_418500ad;  // Hardware register at 0x418500ad

    // Check hardware presence register
    return (DAT_418500ad == '\0');
}

/*
 * Dump track cache
 * Clears all cached track data
 */
void _DumpTrackCache(int driveStructure)
{
    extern unsigned short DAT_0000fb88;
    extern unsigned char _ReadDataPresent;
    extern unsigned char DAT_0000f459;
    extern void _ResetBitArray(int, int);

    // Invalidate cached track
    DAT_0000fb88 = 0xffff;

    // Clear cache entries
    *(unsigned char *)(driveStructure + 0xb4) = 0xff;
    *(unsigned char *)(driveStructure + 0xb5) = 0xff;

    // Reset bit arrays (16 bytes each)
    _ResetBitArray(driveStructure + 0xa4, 0x10);
    _ResetBitArray(driveStructure + 0x94, 0x10);

    // Clear read data flags
    _ReadDataPresent = 0;
    DAT_0000f459 = 0;
}

//==============================================================================
// Disk Ejection and Hardware Locking Functions
//==============================================================================

/*
 * _EjectDisk - Eject disk from drive
 *
 * Powers up drive, flushes and dumps track cache, seeks to track 40,
 * and performs hardware eject operation.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _EjectDisk(int param_1)
{
    short sVar1;
    int iVar2;

    iVar2 = 0;

    // Check if disk is present (offset 0x3c)
    if (*(char *)(param_1 + 0x3c) != '\0') {
        // Power up the drive
        sVar1 = _PowerDriveUp();
        iVar2 = (int)sVar1;

        if (iVar2 == 0) {
            // Flush any pending writes and dump cache
            _FlushTrackCache(param_1);
            _DumpTrackCache(param_1);

            // Seek to track 40 (0x28)
            *(unsigned char *)(param_1 + 0x20) = 0x28;
            iVar2 = _SeekDrive(param_1);

            // Retry seek if it failed
            if (iVar2 != 0) {
                *(unsigned char *)(param_1 + 0x20) = 0x28;
                _SeekDrive(param_1);
            }

            // Mark disk as ejected (0xff = not present)
            *(unsigned char *)(param_1 + 0x3c) = 0xff;

            // Perform hardware eject
            sVar1 = _HALEjectDiskette(param_1);
            iVar2 = (int)sVar1;
        }

        // Power down drive
        _PowerDriveDown(param_1, 0);
    }

    return iVar2;
}

/*
 * _EnterHardwareLockSection - Enter hardware lock critical section
 *
 * Acquires spin lock for hardware access synchronization.
 */
void _EnterHardwareLockSection(void)
{
    // TODO: FUN_00006d00 is likely a spin lock acquire function
    extern void FUN_00006d00(void);
    FUN_00006d00();
}

/*
 * _ExitHardwareLockSection - Exit hardware lock critical section
 *
 * Releases spin lock for hardware access synchronization.
 */
void _ExitHardwareLockSection(void)
{
    // TODO: FUN_00006cd0 is likely a spin lock release function
    extern void FUN_00006cd0(void);
    FUN_00006cd0();
}

//==============================================================================
// Device ID Map and File Operations
//==============================================================================

/*
 * _fd_init_idmap - Initialize floppy device ID map
 *
 * Sets up the device ID mapping structure for block and character devices.
 * Allocates device structures for up to 2 floppy drives.
 *
 * Parameters:
 *   param_1 - Configuration or device description
 */
void _fd_init_idmap(unsigned int param_1)
{
    int iVar1;
    int *piVar2;
    unsigned char *puVar3;
    int iVar4;

    extern unsigned char _FloppyIdMap;
    extern int _Floppy_dev[2];
    extern int _fd_block_major;
    extern int _fd_raw_major;

    // Function prototypes (decompiler placeholders - need real implementations)
    extern int FUN_000046ac(unsigned int, const char *);
    extern void FUN_0000469c(void *, int);
    extern int FUN_0000468c(int);

    puVar3 = &_FloppyIdMap;
    piVar2 = &_Floppy_dev[0];

    // Get major device numbers from configuration
    _fd_block_major = FUN_000046ac(param_1, "blockMajor");
    _fd_raw_major = FUN_000046ac(param_1, "characterMajor");

    // Clear ID map structure (0x98 bytes)
    FUN_0000469c(&_FloppyIdMap, 0x98);

    iVar4 = 0;
    do {
        // Set up device numbers:
        // Raw device: (major << 8) | (drive << 3)
        // Block device: (major << 8) | (drive << 3)
        *(int *)(puVar3 + 0x44) = _fd_raw_major << 8 | iVar4 << 3;
        *(int *)(puVar3 + 0x48) = _fd_block_major << 8 | iVar4 << 3;
        puVar3 = puVar3 + 0x4c;

        // Allocate device structure (0x80 bytes)
        iVar1 = FUN_0000468c(0x80);
        *piVar2 = iVar1;

        // Initialize device structure
        *(unsigned int *)(iVar1 + 0x24) = 0;

        piVar2 = piVar2 + 1;
        iVar4 = iVar4 + 1;
    } while (iVar4 < 2);
}

/*
 * _Fdclose - Close floppy device
 *
 * Handles closing of block or character floppy device.
 *
 * Parameters:
 *   param_1 - Device number (major/minor encoded)
 *
 * Returns:
 *   0 on success, error code (6) on failure
 */
unsigned int _Fdclose(unsigned int param_1)
{
    int iVar1;
    unsigned int uVar2;
    char cVar3;
    char *pcVar4;
    unsigned int uVar5;

    extern int _fd_block_major;
    extern int _fd_dev_to_id(void);
    extern unsigned int FUN_00004940(int, const char *, ...);

    // Get device ID from device number
    iVar1 = _fd_dev_to_id();

    // Extract minor device (bits 0-2)
    uVar5 = param_1 & 7;

    // If bits 3-7 indicate high partition (> 15), add 8 to minor
    if (0xf < (param_1 >> 3 & 0x1f)) {
        uVar5 = uVar5 + 8;
    }

    _donone("floppy close ,dev=%d\n", param_1);

    if (iVar1 == 0) {
LAB_000048e0:
        uVar2 = 6;  // Error: no such device
    }
    else {
        // Get device name
        uVar2 = FUN_00004940(iVar1, "name");
        _donone("%s:fd_close\n", uVar2, 2, 3, 4, 5);

        // Don't close if minor device is 1
        if (uVar5 != 1) {
            // Check if instance is open
            cVar3 = FUN_00004940(iVar1, "isInstanceOpen");
            if (cVar3 == '\0') goto LAB_000048e0;

            // Determine if this is block or character device
            if ((param_1 >> 8 & 0xff) == _fd_block_major) {
                pcVar4 = "setBlockDeviceOpen:";
            }
            else {
                pcVar4 = "setRawDeviceOpen:";
            }

            // Mark device as closed
            FUN_00004940(iVar1, pcVar4, 0);
        }
        uVar2 = 0;
    }

    return uVar2;
}

/*
 * _fdioctl - Handle floppy disk ioctl commands
 *
 * Main ioctl dispatcher for floppy disk operations. Handles a wide variety
 * of commands including density control, format operations, disk labels,
 * device info queries, and direct command execution.
 *
 * Parameters:
 *   param_1 - Device number (major/minor encoded)
 *   param_2 - Ioctl command code
 *   param_3 - Pointer to ioctl data buffer
 *
 * Returns:
 *   0 on success, error code on failure (6=no device, 0x16=bad command)
 */
unsigned int _fdioctl(unsigned int param_1, int param_2, unsigned int *param_3)
{
    int iVar1;
    unsigned int uVar2;
    char cVar5;
    int iVar3;
    unsigned int uVar4;
    char *pcVar6;
    unsigned int uVar7;
    unsigned int uVar8;
    int iVar9;
    unsigned int uVar10;
    unsigned char *puVar11;
    unsigned char auStack_a8[76];
    unsigned char auStack_5c[24];
    int local_44[4];
    unsigned int local_34;
    unsigned int local_30;
    unsigned char auStack_2c[4];
    unsigned int local_28;
    unsigned int local_24;

    extern unsigned char _FloppyIdMap;
    extern unsigned char DAT_0000f464;
    extern unsigned int _entry;
    extern int _fd_block_major;
    extern const char *_getIoctlName(unsigned int ioctlCmd);
    extern void _GetBusyFlag(void);
    extern void _ResetBusyFlag(void);
    extern int _FloppyPluginGotoState(int, int);
    extern int _FloppyFormatDisk(unsigned char head, unsigned char track);
    extern void _FloppyFormatInfo(unsigned int *param);
    extern unsigned int _floppyMalloc(unsigned int size, unsigned int *param2, unsigned int *param3);

    extern unsigned int FUN_00005ae8(int cmd, void *table);
    extern int FUN_00005ab8(int obj, const char *selector, ...);
    extern unsigned int FUN_00005aa8(int size);
    extern void FUN_00005a98(void *dest, void *src, int size);
    extern void FUN_00005a88(unsigned int param1, unsigned int param2);
    extern int FUN_00005a48(void *param1, void *param2);
    extern void FUN_00005a78(void *buffer, int size);
    extern void FUN_00005a68(void *dest, unsigned int src);
    extern int FUN_00005a18(unsigned int src, unsigned int dest, unsigned int size);
    extern void FUN_000059f8(unsigned int param1, unsigned int param2);

    // Extract drive number from device number
    uVar10 = param_1 >> 3 & 0x1f;
    uVar8 = 0;
    uVar7 = 0;

    // Get ioctl command name for logging
    uVar2 = FUN_00005ae8(param_2, &_fdIoctlValues);
    _donone("fd_ioctl: cmd = %s\n", uVar2, 2, 3, 4, 5);

    // Adjust drive number if needed
    if (0xf < uVar10) {
        uVar10 = uVar10 - 0x10;
    }

    // Only support drives 0 and 1
    if (1 < (int)uVar10) {
        return 6;
    }

    iVar1 = uVar10 * 0x4c;

    // Main ioctl command dispatcher
    if (param_2 == 0x20006415) goto LAB_00005168;
    if (param_2 < 0x20006416) {
        if (param_2 == -0x7ffb99fa) goto LAB_00005170;
        if (param_2 < -0x7ffb99f9) {
            if (param_2 != -0x7ffb9be9) {
                if (((param_2 < -0x7ffb9be9) || (-0x7ffb99fc < param_2)) || (param_2 < -0x7ffb99fe))
                    goto LAB_00005178;
                goto LAB_00005170;
            }
        }
        else if (param_2 != -0x63a39bff) {
            if (param_2 < -0x63a39bfe) {
                iVar9 = -0x7ffb99f8;
            }
            else {
                if (param_2 == -0x3fe799fb) goto LAB_00005170;
                iVar9 = -0x3f9f9a00;
            }
            goto LAB_0000513c;
        }
LAB_00005168:
        iVar9 = *(int *)(&DAT_0000f464 + iVar1);
    }
    else {
        if (param_2 != 0x40046609) {
            if (param_2 < 0x4004660a) {
                if (param_2 < 0x4004641a) {
                    if (param_2 < 0x40046418) {
                        if (param_2 != 0x40046417) goto LAB_00005178;
                        goto LAB_00005168;
                    }
                }
                else {
                    iVar9 = 0x40046607;
LAB_0000513c:
                    if (param_2 != iVar9) {
LAB_00005178:
                        _donone("fd_ioctl: BAD cmd (0x%x)\n", param_2, 2, 3, 4, 5);
                        return 0x16;
                    }
                }
            }
            else if (param_2 != 0x40306405) {
                if (param_2 < 0x40306406) {
                    iVar9 = 0x4020660a;
                    goto LAB_0000513c;
                }
                if (param_2 != 0x40346601) {
                    if (param_2 != 0x5c5c6400) goto LAB_00005178;
                    goto LAB_00005168;
                }
            }
        }
LAB_00005170:
        iVar9 = *(int *)(&_FloppyIdMap + iVar1);
    }

    // Check if device exists
    if (iVar9 == 0) {
        _donone("nodev case\n");
        _donone("fd_ioctl: no such device (dev = 0x%x)\n", param_1, 2, 3, 4, 5);
        return 6;
    }

    // Get busy flag for most commands (except format info and label ops)
    if ((param_2 != 0x5c5c6400) && (param_2 != -0x63a39bff)) {
        _GetBusyFlag();
    }

    // DKIOCEJECT - Eject disk
    if (param_2 == 0x20006415) {
        iVar1 = FUN_00005ab8(iVar9, "eject");
        if (iVar1 == 0) {
            _FloppyPluginGotoState(0, 1);
        }
        uVar2 = FUN_00005ab8(iVar9, "errnoFromReturn:", iVar1);
        goto LAB_0000597c;
    }

    if (param_2 < 0x20006416) {
        // FDIOCSECTSIZE - Set sector size
        if (param_2 == -0x7ffb99fc) {
            pcVar6 = "fdSetGapLength:";
            goto LAB_0000586c;
        }

        if (param_2 < -0x7ffb99fb) {
            // FDIOCSDENS - Set density
            if (param_2 == -0x7ffb99fe) {
                uVar8 = *param_3;
                _donone("   set density = %d\n", uVar8, 2, 3, 4, 5);
                if (3 < uVar8) goto LAB_00005908;

                FUN_00005ab8(iVar9, "fdSetDensity:", uVar8);

                // If auto density, mark as unformatted
                if (uVar8 == 0) {
                    FUN_00005ab8(*(unsigned int *)(&DAT_0000f464 + iVar1), "setFormattedInternal:", 0);
                    uVar2 = FUN_00005ab8(*(unsigned int *)(&DAT_0000f464 + iVar1), "physicalDisk");
                    FUN_00005ab8(uVar2, "setFormattedInternal:", 0);
                }
                _donone("fdioctl:IOCSDENS returns\n");
            }
            // FDIOCSFORM - Set formatted flag
            else if (param_2 < -0x7ffb99fd) {
                if (param_2 != -0x7ffb9be9) goto LAB_000058e8;
                FUN_00005ab8(iVar9, "setFormatted:", *(unsigned char *)((int)param_3 + 3));
            }
            // FDIOCSSECTSIZE - Set sector size
            else {
                FUN_00005ab8(iVar9, "fdSetSectSize:", *param_3);
                FUN_00005ab8(*(unsigned int *)(&DAT_0000f464 + iVar1), "setFormattedInternal:", 1);
                uVar2 = FUN_00005ab8(*(unsigned int *)(&DAT_0000f464 + iVar1), "physicalDisk");
                FUN_00005ab8(uVar2, "setFormattedInternal:", 1);
            }
            goto LAB_00005914;
        }

        // FDIOCSRETRY - Set outer retry
        if (param_2 == -0x7ffb99f8) {
            pcVar6 = "fdSetOuterRetry:";
        }
        else {
            if (-0x7ffb99f8 < param_2) {
                // DKIOCSLABEL - Set disk label
                if (param_2 == -0x63a39bff) {
                    _donone("IOCSLABEL case\n");
                    uVar2 = FUN_00005aa8(0x1c5c);
                    FUN_00005a98(uVar2, param_3, 0x1c5c);
                    FUN_00005ab8(iVar9, "writeLabel:", uVar2);
LAB_000053f4:
                    FUN_00005a88(uVar2, 0x1c5c);
                    goto LAB_00005914;
                }

                // FDIOCREQ - Direct floppy command request
                if (param_2 != -0x3f9f9a00) goto LAB_000058e8;

                iVar1 = FUN_00005a48(auStack_a8, auStack_2c);
                if (iVar1 != 0) {
                    _donone("FDIOCREQ:suser:error,ret=0 anyway\n");
                }

                _donone("cmdbytes=%d,statbytes=%d,bytecount=%d\n", param_3[7], param_3[0xe], param_3[9]);

                if (param_3[9] == 0) {
LAB_00005628:
                    uVar10 = param_3[8];
                    param_3[8] = uVar8;
                    param_3[0x16] = _entry;
                    iVar1 = 0;

                    _donone("after cmdbytes=%d,statbytes=%d,bytecount=%d\n", param_3[7], param_3[0xe], param_3[9]);

                    // Check if format command (0x0d)
                    if ((*(unsigned char *)(param_3 + 3) & 0x3f) == 0xd) {
                        puVar11 = (unsigned char *)param_3[8];
                        _donone("head=%d,track=%d\n", puVar11[1], *puVar11);
                        iVar1 = _FloppyFormatDisk(puVar11[1], *puVar11);
                    }

                    param_3[8] = uVar10;
                    param_3[0x11] = param_3[7];
                    param_3[0x13] = param_3[0xe];
                    param_3[0x12] = param_3[9];

                    _donone("after output cmdbytes=%d,statbytes=%d,bytecount=%d\n", param_3[0x11], param_3[0x13]);

                    if (iVar1 == 0) {
                        param_3[0x10] = 0;
                    }
                    else {
                        param_3[0x10] = 8;
                    }

                    param_3[8] = uVar10;

                    if ((uVar7 != 0) && (param_3[0x12] != 0)) {
                        FUN_000059f8(uVar8, uVar10);
                    }
                }
                else {
                    // Allocate buffer for data transfer
                    uVar7 = param_3[0xf] >> 1 & 1;
                    uVar8 = _floppyMalloc(param_3[9], &local_28, &local_24);

                    if (uVar8 == 0) {
                        _donone(" ...floppyMalloc() failed\n", 1, 2, 3, 4, 5);
                        param_3[0x10] = 2;
                        _donone("ioctl:FDIOCREQ:malloc err,returning 0 anyway\n");
                        _ResetBusyFlag();
                        return 0;
                    }

                    if ((uVar7 != 0) || (iVar1 = FUN_00005a18(param_3[8], uVar8, param_3[9]), iVar1 == 0))
                        goto LAB_00005628;

                    _donone("   ...copyin() returned %d\n", iVar1, 2, 3, 4, 5);
                    param_3[0x10] = 3;
                }

                if (param_3[9] != 0) {
                    FUN_00005a88(local_28, local_24);
                }

                _donone("at the end cmdbytes=%d,statbytes=%d,bytecount=%d\n", param_3[0x11], param_3[0x13],
                        param_3[0x12]);
                goto LAB_00005914;
            }

            // FDIOCSIRETRY - Set inner retry
            if (param_2 != -0x7ffb99fa) goto LAB_000058e8;
            pcVar6 = "fdSetInnerRetry:";
        }
LAB_0000586c:
        FUN_00005ab8(iVar9, pcVar6, *param_3);
    }
    else {
        // FDIOCGRETRY - Get outer retry count
        if (param_2 == 0x40046609) {
            pcVar6 = "outerRetry";
        }
        else {
            if (0x40046609 < param_2) {
                // DKIOCINFO - Get disk info
                if (param_2 == 0x40306405) {
                    _donone("IOCINFO case\n");
                    FUN_00005a78(auStack_5c, 0x30);
                    uVar2 = FUN_00005ab8(iVar9, "driveName");
                    FUN_00005a68(auStack_5c, uVar2);
                    local_34 = FUN_00005ab8(iVar9, "blockSize");
                    local_30 = 0x10000;

                    if (local_34 != 0) {
                        uVar8 = (local_34 + 0x1c5b) / local_34;
                        iVar1 = 0;
                        do {
                            local_44[iVar1] = uVar8 * iVar1;
                            iVar1 = iVar1 + 1;
                        } while (iVar1 < 4);
                    }

                    _donone("DKIOCINFO:blksize=%d,name=%s,labelblks=%d,%d,%d,%d\n", local_34, auStack_5c,
                            local_44[0], local_44[1], local_44[2], local_44[3]);
                    FUN_00005a98(param_3, auStack_5c, 0x30);
                }
                else if (param_2 < 0x40306406) {
                    // DIOCGMEDIASIZE - Get media size in KB
                    if (param_2 != 0x4020660a) {
LAB_000058e8:
                        _donone("fd_ioctl: BAD cmd (0x%x)\n", param_2, 2, 3, 4, 5);
LAB_00005908:
                        _ResetBusyFlag();
                        return 0x16;
                    }
                    iVar1 = FUN_00005ab8(iVar9, "diskSize");
                    iVar3 = FUN_00005ab8(iVar9, "blockSize");
                    *param_3 = (unsigned int)(iVar1 * iVar3) >> 10;
                    param_3[1] = 0;
                }
                else {
                    // DKIOCGFORMAT - Get format info
                    if (param_2 != 0x40346601) {
                        // DKIOCGLABEL - Get disk label
                        if (param_2 == 0x5c5c6400) {
                            uVar2 = FUN_00005aa8(0x1c5c);
                            iVar1 = FUN_00005ab8(iVar9, "readLabel:", uVar2);
                            _donone("read disk labelret=%d\n", iVar1);

                            if (iVar1 != 0) {
                                _donone("read label failed,copying label anyway,irtn=%d\n", iVar1);
                            }

                            FUN_00005a98(param_3, uVar2, 0x1c5c);
                            goto LAB_000053f4;
                        }
                        goto LAB_000058e8;
                    }

                    _donone("ioctl:calling fdGetFormatInfo\n");
                    FUN_00005ab8(iVar9, "fdGetFormatInfo:", param_3);
                    _FloppyFormatInfo(param_3);
                    param_3[4] = param_3[4] | 1;
                    param_3[8] = 0x200;
                }
                goto LAB_00005914;
            }

            // DKIOCGBLKSIZE - Get block size
            if (param_2 == 0x40046418) {
                pcVar6 = "blockSize";
            }
            else {
                if (param_2 < 0x40046419) {
                    // DKIOCISGFORMAT - Check if formatted
                    if (param_2 == 0x40046417) {
                        _donone("IOCGFORMAT\n");
                        cVar5 = FUN_00005ab8(iVar9, "isFormatted");
                        *param_3 = (int)cVar5;
                        goto LAB_00005914;
                    }
                    goto LAB_000058e8;
                }

                // DKIOCGNUMBLKS - Get number of blocks
                if (param_2 == 0x40046419) {
                    pcVar6 = "diskSize";
                }
                else {
                    // FDIOCGIRETRY - Get inner retry count
                    if (param_2 != 0x40046607) goto LAB_000058e8;
                    pcVar6 = "innerRetry";
                }
            }
        }
        uVar8 = FUN_00005ab8(iVar9, pcVar6);
        *param_3 = uVar8;
    }

LAB_00005914:
    uVar2 = 0;
    uVar4 = FUN_00005ab8(iVar9, "stringFromReturn:", 0);
    _donone("fd_ioctl: returning %s (errno %d)\n", uVar4, 0, 3, 4, 5);
    _donone("fdioctl:returning %d\n", 0);

    // Don't reset busy flag for label operations
    if (param_2 == 0x5c5c6400) {
        return 0;
    }
    if (param_2 == -0x63a39bff) {
        return 0;
    }

LAB_0000597c:
    _ResetBusyFlag();
    return uVar2;
}

/*
 * _Fdopen - Open floppy device
 *
 * Opens a floppy disk device, checks if disk is ready, and marks
 * the device as open (block or character).
 *
 * Parameters:
 *   param_1 - Device number (major/minor encoded)
 *   param_2 - Open flags
 *
 * Returns:
 *   0 on success, error code on failure (6=no device/not ready)
 */
unsigned int _Fdopen(unsigned int param_1, unsigned int param_2)
{
    int iVar1;
    unsigned int uVar2;
    int iVar3;
    char *pcVar4;
    unsigned int uVar5;

    extern int _fd_block_major;
    extern int _fd_dev_to_id(void);
    extern unsigned int FUN_0000480c(int obj, const char *selector, ...);

    // Get device object ID
    iVar1 = _fd_dev_to_id();

    // Extract minor device number
    uVar5 = param_1 & 7;

    _donone("floppy open ,dev=%d,flag=%d,diskobj=%d\n", param_1, param_2, iVar1);

    // Adjust drive number if needed
    if (0xf < (param_1 >> 3 & 0x1f)) {
        uVar5 = uVar5 + 8;
    }

    if (iVar1 == 0) {
        uVar2 = 6;  // No such device
    }
    else {
        // Get device name
        uVar2 = FUN_0000480c(iVar1, "name");
        _donone("%s: Fdopen\n", uVar2, 2, 3, 4, 5);

        // Check if disk is ready
        // Convert flag bit 2 (0x4) to parameter:
        //   if (param_2 & 4) == 0: pass 1 (non-blocking check)
        //   else: pass 0 (blocking check)
        iVar3 = FUN_0000480c(iVar1, "isDiskReady:",
                            ((unsigned int)(unsigned char)(((param_2 & 4) == 0) << 1) << 0x1c) >> 0x1d);

        if (iVar3 == 0) {
            // Disk is ready - mark device as open (except for minor device 1)
            if (uVar5 != 1) {
                // Determine if this is block or character device
                if ((param_1 >> 8 & 0xff) == _fd_block_major) {
                    pcVar4 = "setBlockDeviceOpen:";
                }
                else {
                    pcVar4 = "setRawDeviceOpen:";
                }
                FUN_0000480c(iVar1, pcVar4, 1);
            }
            uVar2 = 0;
        }
        else {
            // Disk not ready
            _donone("fdopen:returning ENXIO\n");
            uVar2 = 6;  // No such device or address
        }
    }

    return uVar2;
}

/*
 * _fdread - Read from floppy device
 *
 * Handles read operations from floppy disk through the strategy routine.
 * Checks if disk is formatted before allowing reads.
 *
 * Parameters:
 *   param_1 - Device number (major/minor encoded)
 *   param_2 - Pointer to uio structure
 *
 * Returns:
 *   0 on success, error code on failure (6=no device, 0x16=not formatted)
 */
unsigned int _fdread(unsigned int param_1, int *param_2)
{
    int iVar1;
    unsigned int uVar2;
    char cVar3;
    unsigned int uVar4;

    extern int _Floppy_dev[2];
    extern int _fd_dev_to_id(void);
    extern unsigned int _fdstrategy;
    extern unsigned int _fdminphys;
    extern unsigned int FUN_00004ac8(int obj, const char *selector, ...);
    extern unsigned int FUN_00004aa8(unsigned int strategy, int dev, unsigned int devnum,
                                     unsigned int flags, unsigned int minphys,
                                     int *uio, unsigned int blocksize);

    // Get device object ID
    iVar1 = _fd_dev_to_id();

    // Extract drive number
    uVar4 = param_1 >> 3 & 0x1f;
    if (0xf < uVar4) {
        uVar4 = uVar4 - 0x10;
    }

    if (iVar1 == 0) {
        uVar2 = 6;  // No such device
    }
    else {
        // Get device name
        uVar2 = FUN_00004ac8(iVar1, "name");
        _donone("fdread %s\n", uVar2, 2, 3, 4, 5);

        // Check if disk is formatted
        cVar3 = FUN_00004ac8(iVar1, "isFormatted");
        if (cVar3 == '\0') {
            uVar2 = 0x16;  // Invalid argument - disk not formatted
        }
        else {
            // Get block size for logging
            uVar2 = FUN_00004ac8(iVar1, "blockSize");
            _donone("fdread:offset=%ld,len=%d,veclen=%d,blksize=%d\n", param_2[3],
                   *(unsigned int *)(*param_2 + 4), param_2[1], uVar2);

            // Get block size and perform read via strategy routine
            uVar2 = FUN_00004ac8(iVar1, "blockSize");
            uVar2 = FUN_00004aa8(_fdstrategy, _Floppy_dev[uVar4], param_1, 0x100000,
                                _fdminphys, param_2, uVar2);
        }
    }

    return uVar2;
}

/*
 * _fdsize - Get floppy disk block size
 *
 * Returns the block size of the floppy device.
 *
 * Returns:
 *   Block size on success, -1 (0xffffffff) if no device
 */
unsigned int _fdsize(void)
{
    int iVar1;
    unsigned int uVar2;

    extern int _fd_dev_to_id(void);
    extern unsigned int FUN_00005b64(int obj, const char *selector);

    // Get device object ID
    iVar1 = _fd_dev_to_id();

    if (iVar1 == 0) {
        _donone("fdsize: bad unit\n", 1, 2, 3, 4, 5);
        uVar2 = 0xffffffff;
    }
    else {
        uVar2 = FUN_00005b64(iVar1, "blockSize");
    }

    return uVar2;
}

/*
 * _fdstrategy - Block device strategy routine
 *
 * Main I/O dispatcher for floppy disk operations. Handles both read
 * and write requests through the buffer structure.
 *
 * Parameters:
 *   param_1 - Pointer to buf structure
 *
 * Returns:
 *   0 on success, -1 (0xffffffff) on error
 */
unsigned int _fdstrategy(int param_1)
{
    int iVar1;
    unsigned int uVar2;
    char *pcVar3;
    int iVar4;
    unsigned int uVar5;
    unsigned int uVar6;
    int local_28[4];

    extern unsigned int _entry;
    extern int _fd_dev_to_id(unsigned int device);
    extern unsigned int FUN_00004f6c(int obj, const char *selector, ...);
    extern unsigned int FUN_00004f4c(int buf);
    extern void FUN_00004f3c(int buf);

    // Get device object from buf->b_dev (offset 0x38)
    iVar1 = _fd_dev_to_id(*(unsigned int *)(param_1 + 0x38));

    local_28[0] = 0;
    *(unsigned int *)(param_1 + 0x28) = 0;  // Clear b_error
    *(unsigned int *)(param_1 + 0x34) = *(unsigned int *)(param_1 + 0x30);  // b_resid = b_bcount

    uVar2 = FUN_00004f6c(iVar1, "name");
    _donone("%s: fdstrategy\n", uVar2, 2, 3, 4, 5);

    if (iVar1 == 0) {
        pcVar3 = "fdstrategy: bad unit\n";
        uVar2 = 1;
    }
    else {
        uVar2 = _entry;

        // Check if this is a format operation (flags 0x4040000)
        if ((*(unsigned int *)(param_1 + 0x24) & 0x4040000) == 0x40000) {
            uVar2 = FUN_00004f4c(param_1);
        }

        // Get block size
        iVar4 = FUN_00004f6c(iVar1, "blockSize");

        if (iVar4 != 0) {
            uVar6 = *(unsigned int *)(param_1 + 0x48);  // b_blkno - block number
            iVar4 = *(int *)(param_1 + 0x30);           // b_bcount - byte count
            uVar5 = *(unsigned int *)(param_1 + 0x3c);  // b_un.b_addr - buffer address

            // Check if read or write (B_READ flag 0x100000)
            if ((*(unsigned int *)(param_1 + 0x24) & 0x100000) == 0) {
                // Write operation
                _donone("calling writeAt offset(b_blkno)=%d,len=%d\n", uVar6, iVar4);
                pcVar3 = "writeAt:length:buffer:actualLength:client:";
            }
            else {
                // Read operation
                _donone("calling readAt offset(b_blkno)=%d,len=%d\n", uVar6, iVar4);
                pcVar3 = "readAt:length:buffer:actualLength:client:";
            }

            // Perform the I/O operation
            iVar1 = FUN_00004f6c(iVar1, pcVar3, uVar6, iVar4, uVar5, local_28, uVar2);

            // Calculate residual count (requested - actual)
            *(int *)(param_1 + 0x34) = iVar4 - local_28[0];

            if (iVar4 - local_28[0] < 0) {
                *(unsigned int *)(param_1 + 0x34) = 0;
            }

            // Check for success (no error and no residual)
            if ((iVar1 == 0) && (*(int *)(param_1 + 0x34) < 1)) {
                uVar2 = 0;
            }
            else {
                // Partial I/O or error
                _donone("Floppy:partial IO rtn=%d,result=%d,req=%d,offset=%d\n", iVar1, local_28[0], iVar4,
                       uVar6);
                *(int *)(param_1 + 0x34) = *(int *)(param_1 + 0x30) - local_28[0];
                *(unsigned int *)(param_1 + 0x24) = *(unsigned int *)(param_1 + 0x24) | 0x800;  // Set B_ERROR
                uVar2 = 0xffffffff;
            }

            // Call biodone to complete I/O
            FUN_00004f3c(param_1);
            return uVar2;
        }

        // Block size is zero - error
        uVar2 = FUN_00004f6c(iVar1, "name");
        pcVar3 = "fdstrategy %s: zero block_size\n";
    }

    // Error path
    _donone(pcVar3, uVar2, 2, 3, 4, 5);
    *(unsigned int *)(param_1 + 0x28) = 6;  // Set b_error = ENXIO
    *(unsigned int *)(param_1 + 0x24) = *(unsigned int *)(param_1 + 0x24) | 0x800;  // Set B_ERROR flag
    FUN_00004f3c(param_1);
    _donone("fdstrategy: COMMAND REJECT\n", 1, 2, 3, 4, 5);
    return 0xffffffff;
}

/*
 * _fdTimer - Floppy timer callback
 *
 * Timer callback function that checks if timer event processing is needed.
 * Called periodically to handle delayed operations.
 *
 * Parameters:
 *   param_1 - Pointer to FloppyDisk object
 */
void _fdTimer(int param_1)
{
    extern void FUN_000031ac(int obj, const char *selector);

    // Check if timer flag is set (bit 31 at offset 0x1ac)
    if (*(int *)(param_1 + 0x1ac) < 0) {
        FUN_000031ac(param_1, "timerEvent");
    }
}

/*
 * _fdwrite - Write to floppy device
 *
 * Handles write operations to floppy disk through the strategy routine.
 * Checks if disk is formatted before allowing writes.
 *
 * Parameters:
 *   param_1 - Device number (major/minor encoded)
 *   param_2 - Pointer to uio structure
 *
 * Returns:
 *   0 on success, error code on failure (6=no device, 0x16=not formatted)
 */
unsigned int _fdwrite(unsigned int param_1, unsigned int param_2)
{
    int iVar1;
    unsigned int uVar2;
    char cVar3;
    unsigned int uVar4;

    extern int _Floppy_dev[2];
    extern int _fd_dev_to_id(void);
    extern unsigned int _fdstrategy;
    extern unsigned int _fdminphys;
    extern unsigned int FUN_00004c0c(int obj, const char *selector, ...);
    extern unsigned int FUN_00004bec(unsigned int strategy, int dev, unsigned int devnum,
                                     unsigned int flags, unsigned int minphys,
                                     unsigned int uio, unsigned int blocksize);

    // Get device object ID
    iVar1 = _fd_dev_to_id();

    // Extract drive number
    uVar4 = param_1 >> 3 & 0x1f;
    if (0xf < uVar4) {
        uVar4 = uVar4 - 0x10;
    }

    if (iVar1 == 0) {
        uVar2 = 6;  // No such device
    }
    else {
        // Get device name
        uVar2 = FUN_00004c0c(iVar1, "name");
        _donone("fd_write %s\n", uVar2, 2, 3, 4, 5);

        // Check if disk is formatted
        cVar3 = FUN_00004c0c(iVar1, "isFormatted");
        if (cVar3 == '\0') {
            uVar2 = 0x16;  // Invalid argument - disk not formatted
        }
        else {
            // Get block size and perform write via strategy routine
            uVar2 = FUN_00004c0c(iVar1, "blockSize");
            uVar2 = FUN_00004bec(_fdstrategy, _Floppy_dev[uVar4], param_1, 0,
                                _fdminphys, param_2, uVar2);
        }
    }

    return uVar2;
}

/*
 * _floppy_idmap - Get pointer to floppy ID map
 *
 * Returns pointer to the global floppy device ID map structure.
 *
 * Returns:
 *   Pointer to _FloppyIdMap
 */
unsigned char *_floppy_idmap(void)
{
    extern unsigned char _FloppyIdMap;
    return &_FloppyIdMap;
}

/*
 * _FloppyFormatDisk - Format a floppy disk
 *
 * Formats a specific track/head on the floppy disk. Acquires hardware
 * lock before formatting.
 *
 * Parameters:
 *   param_1 - Head number
 *   param_2 - Track/cylinder number
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FloppyFormatDisk(unsigned int param_1, unsigned int param_2)
{
    int iVar1;
    unsigned int uVar2;
    unsigned int *local_18[3];

    extern int _FormatDisk(unsigned int head, unsigned int track, unsigned int *drivePtr, int param4);
    extern short _GetDisketteFormatType(unsigned int *drivePtr);

    // Check if drive 1 is valid
    iVar1 = _CheckDriveNumber(1, local_18);

    if (iVar1 == 0) {
        // Enter hardware lock section
        uVar2 = (unsigned int)_EnterHardwareLockSection();
        *local_18[0] = uVar2;

        // Format the disk
        iVar1 = _FormatDisk(param_1, param_2, local_18[0], 0);

        // Exit hardware lock section
        _ExitHardwareLockSection(*local_18[0]);
    }

    return iVar1;
}

/*
 * _FloppyFormatInfo - Get floppy format information
 *
 * Retrieves format information for the current disk format type and
 * populates a format info structure.
 *
 * Parameters:
 *   param_1 - Pointer to format info structure to populate
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FloppyFormatInfo(int param_1)
{
    int iVar1;
    unsigned int uVar2;
    short sVar4;
    int iVar3;
    unsigned int *local_18[4];

    extern unsigned int DAT_0000fb90;  // Format info table - capacity
    extern unsigned char DAT_0000fb94;  // Format info table - sectors per track (low nibble)
    extern unsigned char DAT_0000fb95;  // Format info table - tracks per disk
    extern short DAT_0000fb96;          // Format info table - sectors per track (full)
    extern unsigned char DAT_0000fba1;  // Format info table - additional flags
    extern short _GetDisketteFormatType(unsigned int *drivePtr);

    // Check if drive 1 is valid
    iVar1 = _CheckDriveNumber(1, local_18);

    if (iVar1 == 0) {
        // Enter hardware lock section
        uVar2 = (unsigned int)_EnterHardwareLockSection();
        *local_18[0] = uVar2;

        // Get diskette format type
        sVar4 = _GetDisketteFormatType(local_18[0]);
        iVar3 = (int)sVar4;

        // Populate format info structure from tables
        // offset 0x30: capacity
        *(unsigned int *)(param_1 + 0x30) = (&DAT_0000fb90)[iVar3 * 5];

        // offset 0x4: sectors per track (low nibble)
        *(unsigned char *)(param_1 + 4) = (&DAT_0000fb94)[iVar3 * 0x14] & 0xf;

        // offset 0xc: density code
        switch(iVar3) {
        case 0:
        case 1:
        case 2:
            uVar2 = 1;  // 500kbps
            break;
        case 3:
        case 4:
            uVar2 = 2;  // 300kbps
            break;
        case 5:
            uVar2 = 3;  // 1Mbps
            break;
        default:
            uVar2 = 0;  // Auto
        }
        *(unsigned int *)(param_1 + 0xc) = uVar2;

        // offset 0x8: sectors per track (full value)
        *(int *)(param_1 + 8) = (int)(short)(&DAT_0000fb96)[iVar3 * 10];

        // offset 0x28: tracks per disk
        *(unsigned int *)(param_1 + 0x28) = (unsigned int)(unsigned char)(&DAT_0000fb95)[iVar3 * 0x14];

        // offset 0x2d: additional flags
        *(unsigned char *)(param_1 + 0x2d) = (&DAT_0000fba1)[iVar3 * 0x14];

        // Exit hardware lock section
        _ExitHardwareLockSection(*local_18[0]);
    }

    return iVar1;
}

/*
 * _floppyMalloc - Allocate memory for floppy operations
 *
 * Allocates memory buffer with size checking. Doubles the requested size
 * and validates against _entry limit.
 *
 * Parameters:
 *   param_1 - Requested size in bytes
 *   param_2 - Pointer to receive allocated buffer address
 *   param_3 - Pointer to receive actual allocated size
 *
 * Returns:
 *   Buffer address on success, 0 on failure
 */
unsigned int _floppyMalloc(unsigned int param_1, unsigned int *param_2, int *param_3)
{
    unsigned int uVar1;

    extern unsigned int _entry;
    extern unsigned int FUN_00005cec(unsigned int size);

    // Check if requested size exceeds limit
    if (_entry < param_1) {
        uVar1 = 0;
    }
    else {
        // Allocate double the requested size
        uVar1 = FUN_00005cec(param_1 << 1);
        *param_2 = uVar1;
        *param_3 = param_1 << 1;
    }

    return uVar1;
}

/*
 * _FloppyPluginFlush - Flush floppy track cache
 *
 * Flushes pending writes from the track cache to disk. Acquires
 * hardware lock during the operation.
 *
 * Returns:
 *   1 on success (or error)
 */
int _FloppyPluginFlush(void)
{
    unsigned int *puVar1;
    unsigned int uVar2;
    int iVar3;

    extern unsigned int *_myDriveStatus;
    extern int _FlushTrackCache(unsigned int *drivePtr);

    // Enter hardware lock section
    uVar2 = (unsigned int)_EnterHardwareLockSection();
    puVar1 = _myDriveStatus;
    *_myDriveStatus = uVar2;

    // Flush the track cache
    iVar3 = _FlushTrackCache(puVar1);

    // Exit hardware lock section
    _ExitHardwareLockSection(*_myDriveStatus);

    // Return 1 regardless of result (non-zero return = success)
    if (iVar3 == 0) {
        iVar3 = 1;
    }

    return iVar3;
}

/*
 * _FloppyPluginGotoState - Change floppy plugin state
 *
 * Changes the plugin state. When state is 0 or 1, ejects the disk.
 *
 * Parameters:
 *   param_1 - Unused state parameter
 *   param_2 - State code (< 2 triggers eject)
 *
 * Returns:
 *   Result of eject operation, or 0 if no action taken
 */
unsigned int _FloppyPluginGotoState(unsigned int param_1, unsigned int param_2)
{
    unsigned int *puVar1;
    unsigned int uVar2;

    extern unsigned int *_myDriveStatus;

    uVar2 = 0;

    // Only eject if state < 2
    if (param_2 < 2) {
        // Enter hardware lock section
        uVar2 = (unsigned int)_EnterHardwareLockSection();
        puVar1 = _myDriveStatus;
        *_myDriveStatus = uVar2;

        // Eject the disk
        uVar2 = _EjectDisk((int)puVar1);

        // Exit hardware lock section
        _ExitHardwareLockSection(*_myDriveStatus);
    }

    return uVar2;
}

/*
 * _FloppyPluginInit - Initialize floppy plugin
 *
 * Initializes the floppy plugin system including track buffer allocation,
 * format table initialization, and drive initialization.
 *
 * Parameters:
 *   param_1 - Plugin context or initialization parameter
 */
void _FloppyPluginInit(unsigned int param_1)
{
    unsigned int uVar1;
    int iVar2;

    extern int iRam9421ffe8;
    extern unsigned int _trackBuffer;
    extern unsigned int *_myDriveStatus;
    extern void FUN_00005f78(unsigned int, unsigned int *, unsigned int);
    extern void FUN_00005f68(const char *);
    extern unsigned int FUN_00005f58(int);
    extern void _InitFormatTable(void);
    extern int _InitializeDrive(int drive, unsigned int param2, int param3, int param4,
                                int param5, unsigned int param6, unsigned int param7,
                                unsigned int **statusPtr);

    // Calculate initialization parameter
    iVar2 = iRam9421ffe8 * 0x100 + -0x6af4ff71;

    // Allocate/setup track buffer (0xb000 bytes = 44KB)
    FUN_00005f78(0x9421ffe0, &_trackBuffer, 0xb000);
    FUN_00005f68("bsfloppy.c:Unable to create track cache memory ");

    // Get physical address
    uVar1 = FUN_00005f58(0);
    _donone("trackbuflogic=0x%x,phys=0x%x ", 0, uVar1);

    // Initialize format table
    _InitFormatTable();

    // Initialize drive 1
    iVar2 = _InitializeDrive(1, 0x5162fda4, iVar2, iVar2, 0, uVar1, 0xb000, &_myDriveStatus);

    // Store plugin context in drive status if initialization succeeded
    if (iVar2 == 0) {
        *(_myDriveStatus + 4) = param_1;
    }
}

/*
 * _FloppyPluginIO - Perform floppy I/O operation
 *
 * Main I/O handler for floppy plugin. Handles read and write operations
 * at the block level.
 *
 * Parameters:
 *   param_1 - Pointer to receive actual transfer count
 *   param_2 - Transfer length in bytes
 *   param_3 - Buffer address
 *   param_4 - Starting byte offset
 *   param_5 - Operation type (0=read, 1=write)
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FloppyPluginIO(unsigned int *param_1, int param_2, unsigned int param_3,
                    unsigned int param_4, int param_5)
{
    int iVar1;
    unsigned int uVar2;
    unsigned int *local_28;
    unsigned int local_24[2];

    extern int _ReadBlocks(unsigned int *ioReq, unsigned int *result);
    extern int _WriteBlocks(unsigned int *ioReq, unsigned int *result);
    extern int _RecordError(int errorCode);

    local_24[0] = 0;

    // Check if drive 1 is valid
    iVar1 = _CheckDriveNumber(1, &local_28);

    if (iVar1 == 0) {
        // Enter hardware lock section
        uVar2 = (unsigned int)_EnterHardwareLockSection();
        *local_28 = uVar2;

        // Setup I/O request structure
        *(unsigned short *)(local_28 + 3) = 1;  // offset 0xc: request flags

        // Set operation type
        if (param_5 == 0) {
            *(unsigned short *)((int)local_28 + 0xe) = 2;  // Read operation
        }
        if (param_5 == 1) {
            *(unsigned short *)((int)local_28 + 0xe) = 3;  // Write operation
        }

        *(unsigned short *)(local_28 + 4) = 0;              // offset 0x10: clear flags
        local_28[5] = param_4 >> 9;                         // offset 0x14: start block (byte offset / 512)
        local_28[6] = (param_2 + 0x1ff) >> 9;              // offset 0x18: block count (round up)
        local_28[9] = param_3;                              // offset 0x24: buffer address

        // Perform the operation
        if (*(short *)((int)local_28 + 0xe) == 2) {
            // Read operation
            _donone("read blk=%d,count=%d\n", local_28[5], local_28[6]);
            iVar1 = _ReadBlocks(local_28, local_24);
        }
        else if (*(short *)((int)local_28 + 0xe) == 3) {
            // Write operation
            if (local_28[0xe] == 0) {
                iVar1 = _WriteBlocks(local_28, local_24);
            }
            else {
                _donone("wrt:call record err ");
                iVar1 = _RecordError(0xffffffd4);  // -44 error code
            }
        }

        // Exit hardware lock section
        _ExitHardwareLockSection(*local_28);
    }

    // Return actual transfer count
    *param_1 = local_24[0];

    return iVar1;
}

/*
 * _FloppyRecalibrate - Recalibrate floppy drive
 *
 * Performs a recalibration operation on the floppy drive, seeking
 * to track 0 to establish a known position.
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FloppyRecalibrate(void)
{
    int iVar1;
    unsigned int uVar2;
    unsigned int *local_18[5];

    extern void _RecalDrive(unsigned int *drivePtr);

    // Check if drive 1 is valid
    iVar1 = _CheckDriveNumber(1, local_18);

    if (iVar1 == 0) {
        // Enter hardware lock section
        uVar2 = (unsigned int)_EnterHardwareLockSection();
        *local_18[0] = uVar2;

        // Recalibrate the drive
        _RecalDrive(local_18[0]);

        // Exit hardware lock section
        _ExitHardwareLockSection(*local_18[0]);
    }

    return iVar1;
}

/*
 * _FloppyTimedSleep - Sleep for specified milliseconds
 *
 * Provides a timed delay. For delays < 10ms, uses busy wait.
 * For longer delays, uses system sleep function.
 *
 * Parameters:
 *   param_1 - Delay time in milliseconds
 *
 * Returns:
 *   0 (always)
 */
unsigned int _FloppyTimedSleep(int param_1)
{
    unsigned char auStack_8[8];

    extern void FUN_00006ca0(int microseconds);
    extern void FUN_00006c90(int, unsigned char *, int);
    extern void FUN_00006c80(unsigned char *, int);

    if (param_1 < 10) {
        // Short delay - busy wait in microseconds
        FUN_00006ca0(param_1 * 1000);
    }
    else {
        // Longer delay - use system sleep
        // Convert milliseconds to 100ms units (param_1 + 9) / 10
        FUN_00006c90(0, auStack_8, (param_1 + 9) / 10);
        FUN_00006c80(auStack_8, 0x16);
    }

    return 0;
}

/*
 * _FloppyWriteProtected - Check if floppy is write protected
 *
 * Returns the write protection status of the floppy disk.
 *
 * Returns:
 *   Write protection flag from drive structure (offset 0x38)
 */
unsigned int _FloppyWriteProtected(void)
{
    int local_8[2];

    // Check drive 1 and get drive structure
    _CheckDriveNumber(1, local_8);

    // Return write protect flag at offset 0x38
    return *(unsigned int *)(local_8[0] + 0x38);
}

/*
 * _FlushCacheAndSeek - Flush cache and seek if track changed
 *
 * Checks if the current track differs from the target track. If so,
 * flushes any dirty cache data, dumps the cache, and seeks to the new track.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *
 * Returns:
 *   0 if no seek needed or seek succeeded, error code on failure
 */
int _FlushCacheAndSeek(int param_1)
{
    int iVar1;
    short sVar2;

    extern int _TestCacheDirtyState(int driveStructure);
    extern short _SeekDrive(int driveStructure);

    iVar1 = 0;

    // Check if current track (offset 0x1c) differs from target track (offset 0x20)
    if (*(char *)(param_1 + 0x1c) != *(char *)(param_1 + 0x20)) {
        // Check if cache has dirty data
        iVar1 = _TestCacheDirtyState(param_1);
        if (iVar1 != 0) {
            _FlushTrackCache(param_1);
        }

        // Dump (invalidate) the cache
        _DumpTrackCache(param_1);

        // Seek to the new track
        sVar2 = _SeekDrive(param_1);
        iVar1 = (int)sVar2;
    }

    return iVar1;
}

/*
 * _FlushDMAedDataFromCPUCache - Flush DMA data from CPU cache
 *
 * Placeholder function for flushing DMA'd data from CPU cache.
 * Currently a no-op.
 *
 * Returns:
 *   0 (always)
 */
unsigned int _FlushDMAedDataFromCPUCache(void)
{
    return 0;
}

/*
 * _FlushProcessorCache - Flush processor cache range
 *
 * Flushes a range of addresses from the processor cache.
 *
 * Parameters:
 *   param_1 - Unused
 *   param_2 - Start address
 *   param_3 - Length
 */
void _FlushProcessorCache(unsigned int param_1, unsigned int param_2, unsigned int param_3)
{
    extern void FUN_00006d38(unsigned int addr, unsigned int length);

    FUN_00006d38(param_2, param_3);
}

/*
 * _FlushTrackCache - Flush track cache to disk
 *
 * Writes dirty cache data for the current track to the physical disk.
 * Writes both head 0 and head 1 data if present.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FlushTrackCache(int param_1)
{
    int iVar1;
    short sVar2;
    unsigned int uVar3;
    int iVar4;

    extern int FUN_00009434(int param);
    extern short _WriteCacheToDiskTrack(int driveStructure);

    iVar4 = 0;

    // Check if there's data to flush
    iVar1 = FUN_00009434();
    if (iVar1 != 0) {
        // Save current target track
        uVar3 = *(unsigned int *)(param_1 + 0x20);

        // Set target track to cached track (offset 0x1c)
        *(unsigned char *)(param_1 + 0x20) = *(unsigned char *)(param_1 + 0x1c);

        // Set head to 0
        *(unsigned char *)(param_1 + 0x21) = 0;

        // Check if head 0 needs flushing
        iVar1 = FUN_00009434(param_1);
        if (iVar1 != 0) {
            sVar2 = _WriteCacheToDiskTrack(param_1);
            iVar4 = (int)sVar2;
        }

        // Set head to 1
        *(unsigned char *)(param_1 + 0x21) = 1;

        // If head 0 succeeded, try head 1
        if (iVar4 == 0) {
            iVar1 = FUN_00009434(param_1);
            if (iVar1 != 0) {
                sVar2 = _WriteCacheToDiskTrack(param_1);
                iVar4 = (int)sVar2;
            }
        }

        // Restore original target track
        *(unsigned int *)(param_1 + 0x20) = uVar3;
    }

    return iVar4;
}

/*
 * _FormatDisk - Format a floppy disk track
 *
 * Formats a specific track/head on the floppy disk. Handles write protection,
 * power management, format selection, recalibration, seeking, and track formatting.
 *
 * Parameters:
 *   param_1 - Head number
 *   param_2 - Track/cylinder number
 *   param_3 - Drive structure pointer
 *   param_4 - Format type (0=use default, >0=specific format)
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _FormatDisk(unsigned char param_1, unsigned char param_2, int param_3, short param_4)
{
    short sVar1;
    int iVar2;
    unsigned short local_28;
    unsigned char auStack_26[2];
    unsigned short local_24[8];

    extern short _PowerDriveUp(int driveStructure);
    extern void _PowerDriveDown(int driveStructure, int delay);
    extern void _SetDisketteFormat(int driveStructure, int format);
    extern void _RecalDrive(int driveStructure);
    extern void _GetSectorAddress(int driveStructure, int sector);
    extern void _SetSectorsPerTrack(int driveStructure);
    extern short _HALFormatTrack(int driveStructure);

    // Check if disk is write protected (offset 0x38)
    if (*(int *)(param_3 + 0x38) == 0) {
        // Power up the drive
        sVar1 = _PowerDriveUp(param_3);
        iVar2 = (int)sVar1;

        if (iVar2 == 0) {
            // Dump track cache
            _DumpTrackCache(param_3);

            // Get available formats
            _AvailableFormats(param_3, &local_28, auStack_26, local_24);

            // Set diskette format to default (first available format)
            _SetDisketteFormat(param_3, local_24[0]);

            // If specific format requested, use it
            if (param_4 != 0) {
                _SetDisketteFormat(param_3, (int)param_4 + (unsigned int)local_28 + -1);
            }

            // Set format fill byte (offset 0x34) to 0xf6
            *(unsigned char *)(param_3 + 0x34) = 0xf6;

            // Recalibrate drive
            _RecalDrive(param_3);

            // Get sector address for sector 0
            _GetSectorAddress(param_3, 0);

            // Set target track and head
            *(unsigned char *)(param_3 + 0x20) = param_2;  // Track
            *(unsigned char *)(param_3 + 0x21) = param_1;  // Head

            // Seek to the track
            sVar1 = _SeekDrive(param_3);
            iVar2 = (int)sVar1;

            if (iVar2 == 0) {
                // Set sectors per track if needed (offset 0x5a check)
                if (*(char *)(param_3 + 0x5a) != '\0') {
                    _SetSectorsPerTrack(param_3);
                }

                // Perform hardware format operation
                sVar1 = _HALFormatTrack(param_3);
                iVar2 = (int)sVar1;
            }

            // Power down drive (6 second delay)
            _PowerDriveDown(param_3, 6);
        }
    }
    else {
        // Disk is write protected - return error
        sVar1 = _RecordError(0xffffffd4);  // -44 error code
        iVar2 = (int)sVar1;
    }

    return iVar2;
}

/*
 * _FormatGCRCacheSWIMIIIData - Format GCR cache data for SWIM III
 *
 * Initializes the track cache with properly formatted GCR data for SWIM III
 * controller. Handles sector address marks, gap bytes, and data fields.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 */
void _FormatGCRCacheSWIMIIIData(int param_1)
{
    unsigned char bVar1;
    unsigned char bVar2;
    unsigned char bVar3;
    char *pcVar4;
    int iVar5;
    unsigned int uVar6;
    int iVar7;
    unsigned int uVar8;
    unsigned char bVar9;
    unsigned char *puVar10;
    unsigned char *puVar11;

    extern char _lastSectorsPerTrack;
    extern int _track_offset;
    extern unsigned char s_gap_0000e6e4[];      // Gap bytes pattern
    extern unsigned char DAT_0000c16c[];        // Address mark prefix
    extern unsigned char s_mark_0000e720[];     // Sector mark
    extern unsigned char s_data_0000e724[];     // Data mark
    extern unsigned char s_tail_0000e728[];     // Track tail

    // Get track buffer pointer (offset 0xb8)
    puVar10 = *(unsigned char **)(param_1 + 0xb8);
    uVar6 = 0;

    do {
        // Check if this is a subsequent format (same sector count as last time)
        if (_lastSectorsPerTrack == *(char *)(param_1 + 0x51)) {
            // Quick format - just update sector headers
            _lastSectorsPerTrack = *(char *)(param_1 + 0x51);
            _donone("Initializing %d sectors subsequent time\n", *(unsigned char *)(param_1 + 0x51));

            uVar8 = 0;
            if (*(char *)(param_1 + 0x51) != '\0') {
                do {
                    // Build sector address mark
                    bVar2 = *(unsigned char *)(param_1 + 0x20) & 0x3f;  // Track number
                    puVar10[0x33] = bVar2;
                    puVar10[0x34] = (unsigned char)uVar8;                // Sector number
                    bVar3 = (unsigned char)(uVar6 << 5) | *(unsigned char *)(param_1 + 0x20) & 0xc0;  // Side info
                    puVar10[0x35] = bVar3;
                    bVar1 = *(unsigned char *)(param_1 + 0x23);         // Format byte
                    puVar10[0x36] = bVar1;
                    puVar10[0x37] = bVar1 ^ bVar2 ^ (unsigned char)uVar8 ^ bVar3;  // Checksum

                    puVar10 = puVar10 + 0x30c;  // Move to next sector (780 bytes)
                    uVar8 = uVar8 + 1;
                } while (uVar8 < *(unsigned char *)(param_1 + 0x51));
            }

            puVar10 = puVar10 + 0x4b6;  // Skip to end
            iVar5 = *(int *)(param_1 + 0xb8);
            pcVar4 = "second pass track length =%d for side=%d\n";
        }
        else {
            // Full format - initialize entire track structure
            // Fill initial gap with pattern
            iVar5 = 0;
            do {
                _ByteMove(s_gap_0000e6e4, puVar10, 0x30);  // 48 byte gap pattern
                puVar10 = puVar10 + 6;
                iVar5 = iVar5 + 1;
            } while (iVar5 < 200);

            _donone("Initializing %d sectors first time;setting to 12\n", *(unsigned char *)(param_1 + 0x51));
            *(unsigned char *)(param_1 + 0x51) = 0xc;  // Set to 12 sectors

            uVar8 = 0;
            do {
                // Calculate alignment padding
                iVar7 = 0;
                iVar5 = (int)*(short *)(param_1 + 800);
                if (1 < iVar5) {
                    iVar7 = (((unsigned int)(puVar10 + 0x49) & -iVar5) + iVar5 + -0x49) - (int)puVar10;
                }

                // Fill initial sector gap
                iVar5 = 0;
                do {
                    _ByteMove(s_gap_0000e6e4, puVar10 + iVar5 * 6, 6);
                    iVar5 = iVar5 + 1;
                } while (iVar5 < 8);

                // Address mark prefix
                _ByteMove(&DAT_0000c16c, puVar10 + 0x30, 3);

                // Build sector address mark
                bVar2 = *(unsigned char *)(param_1 + 0x20) & 0x3f;
                puVar10[0x33] = bVar2;
                bVar9 = (unsigned char)uVar8;
                puVar10[0x34] = bVar9;
                bVar3 = (unsigned char)(uVar6 << 5) | *(unsigned char *)(param_1 + 0x20) & 0xc0;
                puVar10[0x35] = bVar3;
                bVar1 = *(unsigned char *)(param_1 + 0x23);
                puVar10[0x36] = bVar1;
                puVar10[0x37] = bVar1 ^ bVar2 ^ bVar9 ^ bVar3;

                // Sector mark
                _ByteMove(s_mark_0000e720, puVar10 + 0x38, 2);

                // Gap before data
                _ByteMove(s_gap_0000e6e4, puVar10 + 0x3a, 6);

                // Copy gap with alignment padding
                _ByteMove(puVar10 + 0x3a, puVar10 + 0x40, iVar7);

                // Gap after alignment
                _ByteMove(s_gap_0000e6e4, puVar10 + iVar7 + 0x40, 6);

                // Data mark
                _ByteMove(s_data_0000e724, puVar10 + iVar7 + 0x46, 3);

                // Sector number in data field
                puVar10[iVar7 + 0x49] = bVar9;
                puVar10[iVar7 + 0x4a] = 0;

                // Fill data field header
                _ByteMove(puVar10 + iVar7 + 0x4a, puVar10 + iVar7 + 0x4b, 0xf);

                // Format fill byte (offset 0x34)
                puVar10[iVar7 + 0x5a] = *(unsigned char *)(param_1 + 0x34);

                // Fill sector data (682 bytes = 0x2aa)
                _ByteMove(puVar10 + iVar7 + 0x5a, puVar10 + iVar7 + 0x5b, 0x2aa);

                // Data field trailer
                _ByteMove(s_mark_0000e720, puVar10 + iVar7 + 0x309, 2);
                _ByteMove(s_gap_0000e6e4, puVar10 + iVar7 + 0x30b, 1);

                puVar10 = puVar10 + 0x30c;  // Move to next sector
                uVar8 = uVar8 + 1;
            } while (uVar8 < *(unsigned char *)(param_1 + 0x51));

            // Fill track tail
            iVar5 = 0;
            do {
                puVar11 = puVar10;
                *puVar11 = 0x3f;
                iVar5 = iVar5 + 1;
                puVar10 = puVar11 + 1;
            } while (iVar5 < 4);

            _ByteMove(s_tail_0000e728, puVar11 + 1, 2);
            puVar10 = puVar11 + 3;

            iVar5 = *(int *)(param_1 + 0xb8);
            pcVar4 = "first pass track length =%d for side=%d\n";
        }

        _donone(pcVar4, (int)puVar10 - iVar5, uVar6);

        // Save track offset for side 0
        if (uVar6 == 0) {
            _track_offset = (int)puVar10 - *(int *)(param_1 + 0xb8);
        }

        // Check if single-sided or continue to side 1
        if (*(int *)(param_1 + 0x40) == 0) {
            uVar6 = 3;  // Exit loop
        }
        else {
            uVar6 = uVar6 + 1;
        }
    } while (uVar6 < 2);
}

/*
 * _FormatMFMCacheSWIMIIIData - Format MFM cache data for SWIM III
 *
 * Initializes the track cache with properly formatted MFM (Modified Frequency
 * Modulation) data for SWIM III controller. Similar to GCR version but uses
 * MFM encoding patterns.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 */
void _FormatMFMCacheSWIMIIIData(int param_1)
{
    char cVar1;
    unsigned char bVar2;
    int iVar3;
    unsigned int uVar4;
    int iVar5;
    unsigned int uVar6;
    unsigned char *puVar7;
    unsigned char *puVar8;
    unsigned char *puVar9;

    extern char _lastSectorsPerTrack;
    extern int _track_offset;
    extern unsigned char s__0000e758[];  // MFM gap/sync pattern 1
    extern unsigned char s__0000e764[];  // MFM address mark pattern
    extern unsigned char s__0000e770[];  // MFM CRC pattern
    extern unsigned char s__0000e774[];  // MFM data mark pattern
    extern unsigned char s__0000e780[];  // MFM data sync pattern
    extern unsigned char s__0000e728[];  // Track tail (shared with GCR)

    // Get track buffer pointer (offset 0xb8)
    puVar7 = *(unsigned char **)(param_1 + 0xb8);
    uVar4 = 0;

    do {
        cVar1 = *(char *)(param_1 + 0x51);  // Sectors per track

        // Check if this is a subsequent format (same sector count)
        if (_lastSectorsPerTrack == cVar1) {
            // Quick format - skip to first sector and update headers only
            puVar7 = puVar7 + (unsigned int)*(unsigned char *)(param_1 + 0x5e) +
                             *(unsigned char *)(param_1 + 0x5b) + 0x14;
            uVar6 = 1;
            _lastSectorsPerTrack = cVar1;

            if (*(char *)(param_1 + 0x51) != '\0') {
                do {
                    // Update sector header
                    puVar7[0x14] = *(unsigned char *)(param_1 + 0x20);  // Track
                    puVar7[0x15] = (char)uVar4;                         // Side
                    puVar7[0x16] = (char)uVar6;                         // Sector
                    puVar7[0x17] = *(unsigned char *)(param_1 + 0x23);  // Size code

                    // Move to next sector
                    puVar7 = puVar7 + 0x17 +
                            (unsigned int)*(unsigned char *)(param_1 + 0x5c) +
                            (int)*(short *)(param_1 + 0x54) +
                            *(unsigned char *)(param_1 + 0x5d) + 0x1b;
                    uVar6 = uVar6 + 1;
                } while (uVar6 <= *(unsigned char *)(param_1 + 0x51));
            }

            puVar7 = puVar7 + *(unsigned char *)(param_1 + 0x5f) + 2;
        }
        else {
            // Full format - initialize entire track
            // Gap 4a (pre-index gap)
            *puVar7 = 0x4e;
            _ByteMove(puVar7, puVar7 + 1, *(unsigned char *)(param_1 + 0x5e) - 1);
            puVar7 = puVar7 + *(unsigned char *)(param_1 + 0x5e);

            // Sync bytes (12 x 0x00)
            *puVar7 = 0;
            _ByteMove(puVar7, puVar7 + 1, 0xb);

            // Index address mark
            _ByteMove(s__0000e758, puVar7 + 0xc, 8);

            // Gap 1 (post-index gap)
            puVar8 = puVar7 + 0x14;
            *puVar8 = 0x4e;
            _ByteMove(puVar8, puVar7 + 0x15, *(unsigned char *)(param_1 + 0x5b) - 1);
            puVar8 = puVar8 + *(unsigned char *)(param_1 + 0x5b);

            // Format each sector
            for (uVar6 = 1; uVar6 <= *(unsigned char *)(param_1 + 0x51); uVar6 = uVar6 + 1) {
                // Calculate DMA alignment padding
                iVar5 = 0;
                iVar3 = (int)*(short *)(param_1 + 800);
                if (1 < iVar3) {
                    iVar5 = (((unsigned int)(puVar8 + *(short *)(param_1 + 0x31a)) & -iVar3) + iVar3) -
                           (int)(puVar8 + *(short *)(param_1 + 0x31a));
                }

                // Sync bytes (12 x 0x00)
                *puVar8 = 0;
                _ByteMove(puVar8, puVar8 + 1, 0xb);

                // ID address mark
                _ByteMove(s__0000e764, puVar8 + 0xc, 8);

                // ID field (C/H/S/N)
                puVar8[0x14] = *(unsigned char *)(param_1 + 0x20);  // Cylinder
                puVar8[0x15] = (char)uVar4;                         // Head
                puVar8[0x16] = (char)uVar6;                         // Sector
                puVar8[0x17] = *(unsigned char *)(param_1 + 0x23);  // Size

                // ID CRC
                _ByteMove(s__0000e770, puVar8 + 0x18, 2);

                // Gap 2 (ID to data gap)
                puVar7 = puVar8 + 0x1a;
                *puVar7 = 0x4e;
                _ByteMove(puVar7, puVar8 + 0x1b,
                         (unsigned int)*(unsigned char *)(param_1 + 0x5c) + iVar5 + -1);
                puVar7 = puVar7 + (unsigned int)*(unsigned char *)(param_1 + 0x5c) + iVar5;

                // Data sync bytes (12 x 0x00)
                *puVar7 = 0;
                _ByteMove(puVar7, puVar7 + 1, 0xb);

                // Data address mark
                _ByteMove(s__0000e774, puVar7 + 0xc, 8);

                // Data sync for DMA
                _ByteMove(s__0000e780, puVar7 + 0x14, 2);

                // Data field
                puVar9 = puVar7 + 0x16;
                *puVar9 = *(unsigned char *)(param_1 + 0x34);  // Fill byte
                _ByteMove(puVar9, puVar7 + 0x17, *(short *)(param_1 + 0x54) + -1);
                puVar9 = puVar9 + *(short *)(param_1 + 0x54);

                // Data CRC
                _ByteMove(s__0000e770, puVar9, 2);

                // Gap 3 (inter-sector gap)
                puVar8 = puVar9 + 2;
                *puVar8 = 0x4e;
                _ByteMove(puVar8, puVar9 + 3,
                         (unsigned int)*(unsigned char *)(param_1 + 0x5d) - (iVar5 + 1));
                puVar8 = puVar8 + ((unsigned int)*(unsigned char *)(param_1 + 0x5d) - iVar5);
            }

            // Gap 4b (post-data gap)
            *puVar8 = 0x4e;
            _ByteMove(puVar8, puVar8 + 1, *(unsigned char *)(param_1 + 0x5f) - 1);
            bVar2 = *(unsigned char *)(param_1 + 0x5f);

            // Track tail
            _ByteMove(s__0000e728, puVar8 + bVar2, 2);
            puVar7 = puVar8 + bVar2 + 2;

            // Save track offset for side 0
            if (uVar4 == 0) {
                _track_offset = (int)puVar7 - *(int *)(param_1 + 0xb8);
            }
        }

        // Check if single-sided or continue to side 1
        if (*(int *)(param_1 + 0x40) == 0) {
            uVar4 = 3;  // Exit loop
        }
        else {
            uVar4 = uVar4 + 1;
        }
    } while (uVar4 < 2);
}

/*
 * _FPYComputeCacheDMAAddress - Compute cache DMA addresses
 *
 * Calculates logical and physical DMA addresses for cache operations,
 * taking into account track layout, sector positioning, and DMA alignment.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *   param_2 - Head/side number (0 or 1)
 *   param_3 - Sector number
 *   param_4 - Additional offset
 *   param_5 - Pointer to array to receive [logical address, physical address]
 */
void _FPYComputeCacheDMAAddress(int param_1, char param_2, unsigned int param_3,
                                int param_4, int *param_5)
{
    int iVar1;
    unsigned int uVar2;
    int iVar3;

    // Calculate sector size (header + data + gaps)
    uVar2 = ((unsigned int)*(unsigned short *)(param_1 + 0x31a) +  // ID field size
             (unsigned int)*(unsigned short *)(param_1 + 0x54) +    // Data field size
             (unsigned int)*(unsigned short *)(param_1 + 0x31c)) & 0xffff;  // Gap size

    // Calculate base offset for sector
    // = track header + (sector_index * sector_size) + ID field offset
    iVar1 = (int)*(short *)(param_1 + 0x318) +                               // Track header size
            ((param_3 & 0xff) - (unsigned int)*(unsigned char *)(param_1 + 0x58)) * uVar2 +  // Sector offset
            (int)(short)*(unsigned short *)(param_1 + 0x31a);                // ID field size

    // If head 1, add offset for second side
    if (param_2 != '\0') {
        iVar1 = iVar1 +
                *(short *)(param_1 + 0x318) +                              // Track header
                uVar2 * *(unsigned char *)(param_1 + 0x51) +              // All sectors size
                (int)*(short *)(param_1 + 0x31e);                          // Side offset
    }

    // Calculate logical address (offset 0xb8)
    *param_5 = iVar1 + *(int *)(param_1 + 0xb8);

    // Calculate physical address (offset 0xbc)
    uVar2 = iVar1 + *(int *)(param_1 + 0xbc);
    param_5[1] = uVar2;

    // Calculate DMA alignment padding
    iVar1 = 0;
    iVar3 = (int)*(short *)(param_1 + 800);
    if (1 < iVar3) {
        iVar1 = ((-iVar3 & uVar2) + iVar3) - uVar2;
    }

    // Add alignment and additional offset to both addresses
    *param_5 = iVar1 + param_4 + *param_5;
    param_5[1] = iVar1 + param_4 + param_5[1];
}

/*
 * _FPYDenibblizeGCRSector - Denibblize GCR sector data
 *
 * Converts nibblized GCR sector data back to binary format. Checks if sector
 * is already denibblized using cache bit array, performs denibblization with
 * checksum validation, and optionally stores sector header information.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *   param_2 - Pointer to raw GCR sector data
 *   param_3 - Destination buffer for denibblized data
 *
 * Returns:
 *   0 on success, error code on checksum failure
 */
int _FPYDenibblizeGCRSector(int param_1, unsigned char *param_2, unsigned int param_3)
{
    unsigned char bVar1;
    unsigned int uVar2;
    short sVar3;
    unsigned short *puVar4;
    int iVar5;
    int iVar6;
    unsigned int *puVar7;
    int local_28;
    int local_24[4];

    extern unsigned int _DenibblizeGCRData(unsigned int *nibbles, unsigned char *output,
                                           short byteCount, int *checksum);
    extern void _DenibblizeGCRChecksum(unsigned int *nibbles, int *checksum);

    iVar6 = 0;

    // Check if sector is already denibblized using bit array
    // Offset 0x94: bit array for head 0, 0xa4: bit array for head 1
    // Each sector has 1 bit: bit set = already denibblized
    if (((unsigned int)*(unsigned char *)((unsigned int)*(unsigned char *)(param_1 + 0x21) * 8 +
                                          param_1 + (unsigned int)(*(unsigned char *)(param_1 + 0x22) >> 3) + 0x94) &
         1 << (*(unsigned char *)(param_1 + 0x22) & 7)) == 0) {

        // Get sector number from first byte
        bVar1 = *param_2;
        puVar7 = (unsigned int *)(param_2 + 1);
        local_28 = 0;

        // Denibblize sector header (12 bytes)
        uVar2 = _DenibblizeGCRData(puVar7, puVar7, 0xc, &local_28);

        // Denibblize sector data
        uVar2 = _DenibblizeGCRData(uVar2, param_3, *(unsigned short *)(param_1 + 0x54), &local_28);

        // Get and verify checksum
        _DenibblizeGCRChecksum(uVar2, local_24);
        if (local_24[0] != local_28) {
            sVar3 = _RecordError(0xffffffb8);  // -72 checksum error
            iVar6 = (int)sVar3;
        }

        // If sector header buffer provided (offset 0x30), store header info
        puVar4 = *(unsigned short **)(param_1 + 0x30);
        if (puVar4 != (unsigned short *)0x0) {
            *puVar4 = (unsigned short)bVar1;               // Sector number
            *(unsigned int *)(puVar4 + 2) = *puVar7;       // Header word 1
            puVar4[4] = *(unsigned short *)(param_2 + 5);  // Header word 2
            puVar4[5] = *(unsigned short *)(param_2 + 7);  // Header word 3
            *(unsigned int *)(puVar4 + 6) = *(unsigned int *)(param_2 + 9);  // Header word 4
        }

        // Mark sector as denibblized in bit array
        iVar5 = (unsigned int)*(unsigned char *)(param_1 + 0x21) * 8 + param_1 +
                (unsigned int)(*(unsigned char *)(param_1 + 0x22) >> 3);
        *(unsigned char *)(iVar5 + 0x94) = *(unsigned char *)(iVar5 + 0x94) |
                                           (unsigned char)(1 << (*(unsigned char *)(param_1 + 0x22) & 7));
    }

    return iVar6;
}

/*
 * _FPYNibblizeGCRSector - Nibblize sector data to GCR format
 *
 * Converts binary sector data to nibblized GCR format for writing to disk.
 * Only nibblizes if sector is marked as dirty (denibblized) in cache bit array.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *   param_2 - Destination buffer for nibblized GCR data
 *   param_3 - Source buffer with binary sector data
 *
 * Returns:
 *   0 (always)
 */
unsigned int _FPYNibblizeGCRSector(int param_1, unsigned char *param_2, int param_3)
{
    unsigned char bVar1;
    short sVar3;
    unsigned int uVar2;
    unsigned int uVar4;
    unsigned char *pbVar5;
    int iVar6;
    unsigned char *pbVar7;
    unsigned int local_18[4];

    extern unsigned int _NibblizeGCRData(unsigned char *input, unsigned char *output,
                                         short byteCount, unsigned int *checksum);
    extern void _NibblizeGCRChecksum(unsigned int output, unsigned int checksum);

    bVar1 = *(unsigned char *)(param_1 + 0x22);  // Sector number

    // Check if sector is denibblized (dirty) using bit array
    if (((unsigned int)*(unsigned char *)((unsigned int)*(unsigned char *)(param_1 + 0x21) * 8 +
                                          param_1 + (unsigned int)(bVar1 >> 3) + 0x94) &
         1 << (bVar1 & 7)) != 0) {

        // Store sector number in first byte
        *param_2 = bVar1;

        // Copy data backwards into buffer (699 bytes before nibblization buffer)
        pbVar5 = (unsigned char *)(param_3 + *(short *)(param_1 + 0x54));
        pbVar7 = param_2 + 699;
        for (sVar3 = *(short *)(param_1 + 0x54) + 0xc; 0 < sVar3; sVar3 = sVar3 + -1) {
            pbVar5 = pbVar5 + -1;
            *pbVar7 = *pbVar5;
            pbVar7 = pbVar7 + -1;
        }

        // Use sector header if available (offset 0x30)
        pbVar5 = pbVar7 + 1;
        if (*(unsigned char **)(param_1 + 0x30) != (unsigned char *)0x0) {
            pbVar5 = *(unsigned char **)(param_1 + 0x30);
        }

        local_18[0] = 0;

        // Nibblize sector header (12 bytes)
        uVar4 = _NibblizeGCRData(pbVar5, param_2 + 1, 0xc, local_18);

        // Nibblize sector data
        uVar4 = _NibblizeGCRData(pbVar7 + 0xd, uVar4, *(unsigned short *)(param_1 + 0x54), local_18);

        // Nibblize checksum
        _NibblizeGCRChecksum(uVar4, local_18[0]);

        // Clear dirty bit in cache bit array
        iVar6 = (unsigned int)*(unsigned char *)(param_1 + 0x21) * 8 + param_1 +
                (unsigned int)(*(unsigned char *)(param_1 + 0x22) >> 3);
        uVar2 = *(unsigned char *)(param_1 + 0x22) & 7;
        *(unsigned char *)(iVar6 + 0x94) =
            *(unsigned char *)(iVar6 + 0x94) &
            ((unsigned char)(-2 << uVar2) | (unsigned char)(0xfffffffe >> (0x20 - uVar2)));
    }

    return 0;
}

/*
 * _GetBusyFlag - Acquire busy flag with waiting
 *
 * Waits until busy flag becomes available, then atomically sets it.
 * Uses spin-wait loop with sleep to avoid busy waiting.
 */
void _GetBusyFlag(void)
{
    int iVar1;

    extern unsigned int _busyflag;
    extern int _SetBusyFlag(void);
    extern void FUN_00004cc4(int, unsigned int *, int);
    extern void FUN_00004cb4(unsigned int *, int);

    do {
        // Wait while busy flag is set
        while (_busyflag == 1) {
            FUN_00004cc4(0, &_busyflag, 1);
            FUN_00004cb4(&_busyflag, 0x16);
        }

        // Try to atomically set busy flag
        iVar1 = _SetBusyFlag();
    } while (iVar1 == 0);  // Retry if set failed (race condition)
}

/*
 * _GetCurrentState - Get current floppy state
 *
 * Returns the current state of the floppy subsystem.
 *
 * Returns:
 *   0 - State 1 (ready/mounted)
 *   1 - Other states
 *   2 - State 0 (uninitialized)
 *   3 - State 0xFF (error/unmounted)
 */
unsigned int _GetCurrentState(void)
{
    unsigned int uVar1;

    extern unsigned int _FloppyState;

    if (_FloppyState == 1) {
        uVar1 = 0;
    }
    else {
        if (_FloppyState < 2) {
            if (_FloppyState == 0) {
                return 2;
            }
        }
        else if (_FloppyState == 0xff) {
            return 3;
        }
        uVar1 = 1;
    }

    return uVar1;
}

/*
 * _GetDisketteFormat - Detect and set diskette format
 *
 * Attempts to detect the diskette format by trying different configurations.
 * First tries double-sided format, then falls back to single-sided if needed.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *
 * Returns:
 *   0 on success, error code on failure
 */
int _GetDisketteFormat(int param_1)
{
    unsigned int uVar1;
    short sVar2;
    int iVar3;

    extern unsigned int _GetDisketteFormatType(int driveStructure);
    extern short _HALGetNextAddressID(int driveStructure);

    // Check if disk is present (offset 0x47)
    if (*(char *)(param_1 + 0x47) != '\0') {
        // Try double-sided format first
        *(unsigned char *)(param_1 + 0x48) = 0xff;  // Set format type marker
        *(unsigned int *)(param_1 + 0x40) = 1;       // Set double-sided flag

        uVar1 = _GetDisketteFormatType();
        sVar2 = _SetDisketteFormat(param_1, uVar1);
        iVar3 = (int)sVar2;

        if (iVar3 == 0) {
            _donone("core:GetDisketteFormat:calling RecalDrive ");
            sVar2 = _RecalDrive(param_1);
            iVar3 = (int)sVar2;

            if (iVar3 == 0) {
                *(unsigned char *)(param_1 + 0x21) = 0;  // Head 0
                _donone("core:GetDisketteFormat:calling HALGetNextAddressID ");
                sVar2 = _HALGetNextAddressID(param_1);
                iVar3 = (int)sVar2;

                // If failed but format marker is set, treat as success
                if ((iVar3 != 0) && (*(char *)(param_1 + 0x49) != '\0')) {
                    iVar3 = 0;
                }
            }
        }

        // If successful with double-sided or specific format marker, return
        if (*(char *)(param_1 + 0x47) != '\0') {
            if (*(char *)(param_1 + 0x49) != '\0') {
                return iVar3;
            }
            if (iVar3 == 0) {
                return 0;
            }
        }
    }

    // Try single-sided format
    *(unsigned char *)(param_1 + 0x48) = 0;      // Clear format type marker
    *(unsigned int *)(param_1 + 0x40) = 0;       // Clear double-sided flag

    _donone("core:GetDisketteFormat:calling SetDisketteFormat ");
    uVar1 = _GetDisketteFormatType(param_1);
    sVar2 = _SetDisketteFormat(param_1, uVar1);
    iVar3 = (int)sVar2;

    if (iVar3 == 0) {
        _donone("core:GetDisketteFormat:calling RecalDrive again ");
        sVar2 = _RecalDrive(param_1);
        iVar3 = (int)sVar2;

        if (iVar3 == 0) {
            // Try head 0
            *(unsigned char *)(param_1 + 0x21) = 0;
            _donone("core:GetDisketteFormat:calling HALGetNextAddressID again ");
            sVar2 = _HALGetNextAddressID(param_1);
            iVar3 = (int)sVar2;

            if (iVar3 == 0) {
                // Try head 1
                *(unsigned char *)(param_1 + 0x21) = 1;
                _donone("core:GetDisketteFormat:calling HALGetNextAddressID 3rd again ");
                sVar2 = _HALGetNextAddressID(param_1);
                iVar3 = (int)sVar2;

                if (iVar3 == 0) {
                    // Successfully detected both heads - set double-sided
                    *(unsigned int *)(param_1 + 0x40) = 1;
                    _donone("core:calling SetDisketteFormat ");
                    uVar1 = _GetDisketteFormatType(param_1);
                    _SetDisketteFormat(param_1, uVar1);
                }
            }
        }
    }

    return iVar3;
}

/*
 * _GetDisketteFormatType - Get diskette format type code
 *
 * Returns the format type code based on drive structure parameters.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *
 * Returns:
 *   Format type code (0-5):
 *     0 - 400K/800K single-sided
 *     1 - 400K/800K double-sided
 *     2 - 720K MFM
 *     3 - 1.44MB MFM
 *     5 - 1.2MB MFM (5.25")
 */
unsigned char _GetDisketteFormatType(int param_1)
{
    unsigned char bVar1;
    unsigned char bVar2;

    _donone("core.c:GetDisketteFormatType: ");

    // Check for high-density formats (offset 0x48 = -1)
    if (*(char *)(param_1 + 0x48) == -1) {
        bVar1 = *(unsigned char *)(param_1 + 0x49);

        if (bVar1 == 0xfe) {
            return 5;  // 1.2MB 5.25" format
        }
        if (bVar1 < 0xff) {
            if (bVar1 == 0) {
                return 2;  // 720K format
            }
        }
        else if (bVar1 == 0xff) {
            return 3;  // 1.44MB format
        }
    }

    // Check for standard Mac GCR format
    if ((*(char *)(param_1 + 0x48) == '\0') && (*(char *)(param_1 + 0x49) == '\0')) {
        // Return 1 if double-sided (offset 0x40), 0 if single-sided
        bVar2 = *(int *)(param_1 + 0x40) != 0;
    }
    else {
        bVar2 = 0;
    }

    return bVar2;
}

/*
 * _GetSectorAddress - Convert logical block to physical address
 *
 * Converts a logical block number to physical track/head/sector address.
 * Handles both standard formats and variable sectors per track (GCR).
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *   param_2 - Logical block number
 */
void _GetSectorAddress(int param_1, short param_2)
{
    unsigned char bVar1;
    unsigned char bVar2;
    char cVar3;
    int iVar4;
    unsigned int uVar5;
    int iVar6;
    int iVar7;
    int iVar8;
    int iVar9;
    int iVar10;

    iVar10 = (int)param_2;
    uVar5 = *(unsigned char *)(param_1 + 0x50) & 0xf;  // Heads per cylinder

    // Check for standard format (offset 0x5a = 0)
    if (*(char *)(param_1 + 0x5a) == '\0') {
        // Standard format: fixed sectors per track
        bVar1 = *(unsigned char *)(param_1 + 0x51);  // Sectors per track

        // Calculate cylinder (track)
        *(char *)(param_1 + 0x20) = (char)(iVar10 / (int)(bVar1 * uVar5));

        // Calculate which head and sector
        bVar2 = (unsigned char)(iVar10 / (int)(unsigned int)bVar1);
        *(unsigned char *)(param_1 + 0x22) = ((char)param_2 - bVar2 * bVar1) + '\x01';  // Sector (1-based)
        *(unsigned char *)(param_1 + 0x21) = bVar2 & 1;  // Head (0 or 1)
    }
    else {
        // GCR format with variable sectors per track
        // Different zones have different sector counts

        // Determine zone boundaries based on head count
        if ((*(unsigned char *)(param_1 + 0x50) & 0xf) == 0) {
            // Single-sided
            iVar8 = 0xc0;   // 192 blocks (16 tracks * 12 sectors)
            iVar7 = 0x170;  // 368 blocks
            iVar6 = 0x210;  // 528 blocks
            iVar9 = 0x2a0;  // 672 blocks
        }
        else {
            // Double-sided
            iVar8 = 0x180;  // 384 blocks
            iVar7 = 0x2e0;  // 736 blocks
            iVar6 = 0x420;  // 1056 blocks
            iVar9 = 0x540;  // 1344 blocks
        }

        _donone("GetSectoraddress:blk=%d ", iVar10);

        // Determine which zone and adjust parameters
        if (iVar10 < iVar8) {
            // Zone 0: 12 sectors per track
            iVar4 = 0xc;
            cVar3 = '\0';
        }
        else {
            if (iVar10 < iVar7) {
                // Zone 1: 11 sectors per track (tracks 16-31)
                iVar4 = 0xb;
                cVar3 = '\x10';  // Track offset 16
                param_2 = param_2 - (short)iVar8;
            }
            else if (iVar10 < iVar6) {
                // Zone 2: 10 sectors per track (tracks 32-47)
                iVar4 = 10;
                cVar3 = ' ';     // Track offset 32
                param_2 = param_2 - (short)iVar7;
            }
            else if (iVar10 < iVar9) {
                // Zone 3: 9 sectors per track (tracks 48-63)
                iVar4 = 9;
                cVar3 = '0';     // Track offset 48
                param_2 = param_2 - (short)iVar6;
            }
            else {
                // Zone 4: 8 sectors per track (tracks 64-79)
                iVar4 = 8;
                cVar3 = '@';     // Track offset 64
                param_2 = param_2 - (short)iVar9;
            }
            iVar10 = (int)param_2;
        }

        // Calculate cylinder, head, and sector within zone
        *(char *)(param_1 + 0x20) = (char)(iVar10 / (int)(iVar4 * uVar5)) + cVar3;
        *(char *)(param_1 + 0x22) = (char)iVar10 - (char)(iVar10 / iVar4) * (char)iVar4;
        uVar5 = iVar10 / iVar4 & 1;
        *(char *)(param_1 + 0x21) = (char)uVar5;

        _donone("GCRRead %d:%d:%d\n", uVar5, (int)*(char *)(param_1 + 0x20),
               *(unsigned char *)(param_1 + 0x22));
    }
}


/*
 * _HALDiskettePresence - Check if diskette is present in drive
 *
 * This function checks for diskette presence by sensing SWIM III signals.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x38: Presence flag (set to 1 if diskette present)
 *
 * Returns:
 *   bool - true if diskette is present, false otherwise
 *
 * Signal meanings:
 *   0xf9 - Diskette presence sense (0 = present)
 *   0xf8 - Final presence confirmation (0 = present)
 */
bool _HALDiskettePresence(int param_1)
{
    int iVar1;

    // Select the disk drive
    _SwimIIIDiskSelect();

    // Initialize presence flag to 0 (not present)
    *(unsigned int *)(param_1 + 0x38) = 0;

    // Check first presence signal (0xf9)
    iVar1 = _SwimIIISenseSignal(0xf9);
    if (iVar1 == 0) {
        // Signal low means diskette is present
        *(unsigned int *)(param_1 + 0x38) = 1;
    }

    // Check second presence signal (0xf8) for final confirmation
    iVar1 = _SwimIIISenseSignal(0xf8);

    // Return true if signal is 0 (diskette present)
    return iVar1 == 0;
}


/*
 * _HALEjectDiskette - Eject diskette from drive
 *
 * This function triggers the diskette eject mechanism and waits for
 * the eject operation to complete (or timeout after ~3 seconds).
 *
 * Returns:
 *   unsigned int - 0 on success
 *
 * Signal meanings:
 *   0xf7 - Eject motor control (set to start eject)
 *   0xf8 - Eject complete sense (non-zero when complete)
 *
 * Timing:
 *   - Maximum wait time: 30 iterations * 100ms = 3 seconds
 *   - Final settling delay: 1ms
 */
unsigned int _HALEjectDiskette(void)
{
    short sVar1;
    int iVar2;

    // Start the eject mechanism by setting signal 0xf7
    _SwimIIISetSignal(0xf7);

    // Wait for eject to complete, with timeout
    sVar1 = 0x1d;  // 29 iterations (30 total with do-while)
    do {
        // Wait 100 milliseconds
        _FloppyTimedSleep(100);

        // Check if eject is complete (signal 0xf8 goes high)
        iVar2 = _SwimIIISenseSignal(0xf8);
        if (iVar2 != 0) {
            // Eject complete
            break;
        }

        // Decrement counter and continue waiting
        sVar1 = sVar1 - 1;
    } while (sVar1 != -1);

    // Allow time for mechanical settling
    _FloppyTimedSleep(1);

    return 0;
}


/*
 * _HALFormatTrack - Format a single track on diskette
 *
 * This function formats a track by preparing the track data in cache,
 * then using DMA to write the formatted track to the diskette via the
 * SWIM III controller.
 *
 * Parameters:
 *   param_1 - Drive/format structure pointer
 *             offset 0x20: Track number
 *             offset 0x21: Head number (0 or 1)
 *             offset 0x22: Sector number (set to 1)
 *             offset 0x51: Sectors per track
 *             offset 0x5a: Format type (0=MFM, non-zero=GCR)
 *             offset 0xb8: DMA buffer base address
 *
 * Returns:
 *   int - DMA operation result (0 on success, error code on failure)
 *
 * Process:
 *   1. Save/restore sectors per track count
 *   2. Format track data in cache (MFM or GCR)
 *   3. Wait for index hole (start of track)
 *   4. Select head and calculate DMA address
 *   5. Start DMA write to SWIM III controller
 *   6. Trigger format operation via control registers
 *
 * DMA buffer layout:
 *   - Track size: 0x8000 bytes (32KB)
 *   - Head 0: base address
 *   - Head 1: base address + _track_offset
 */
int _HALFormatTrack(int param_1)
{
    unsigned char uVar1;
    int iVar2;
    short sVar3;

    // Set sector number to 1 for format operation
    *(unsigned char *)(param_1 + 0x22) = 1;

    // Save current sectors per track count
    uVar1 = _lastSectorsPerTrack;
    _lastSectorsPerTrack = *(unsigned char *)(param_1 + 0x51);

    // Format track data based on format type
    if (*(char *)(param_1 + 0x5a) == '\0') {
        // MFM format (PC-style: 720K, 1.44MB, 1.2MB)
        _FormatMFMCacheSWIMIIIData(param_1);
        _lastSectorsPerTrack = uVar1;
    }
    else {
        // GCR format (Mac-style: 400K, 800K)
        _FormatGCRCacheSWIMIIIData();
        _lastSectorsPerTrack = uVar1;
    }

    // Wait for index hole (start of track marker)
    // First wait until index signal goes low
    do {
        iVar2 = _SwimIIISenseSignal(0xfb);
    } while (iVar2 != 0);

    // Then wait until it goes high (start of track)
    do {
        iVar2 = _SwimIIISenseSignal(0xfb);
    } while (iVar2 == 0);

    // Select the head (side 0 or 1)
    _SwimIIIHeadSelect(*(unsigned char *)(param_1 + 0x21));

    // Calculate DMA address based on head number
    if (*(char *)(param_1 + 0x21) == '\0') {
        // Head 0: use base address
        iVar2 = *(int *)(param_1 + 0xb8);
    }
    else {
        // Head 1: use base address + track offset
        iVar2 = *(int *)(param_1 + 0xb8) + _track_offset;
    }

    // Prepare CPU cache for DMA write operation
    _PrepareCPUCacheForDMAWrite();

    // Start DMA channel to write track data (32KB)
    sVar3 = _StartDMAChannel(iVar2, 0x8000, 0);

    // Write to SWIM III control register to start format
    *DAT_0000fc34 = 8;
    _SynchronizeIO();

    // Trigger the actual format operation
    *DAT_0000fc34 = 0x40;
    _SynchronizeIO();

    // Debug output
    _donone("gcr=%d hd=%d,track=%d,trksize=%d,err=%d\n",
           *(unsigned char *)(param_1 + 0x5a),
           *(unsigned char *)(param_1 + 0x21),
           (int)*(char *)(param_1 + 0x20),
           _track_offset,
           (int)sVar3);

    return (int)sVar3;
}


/*
 * _HALGetDriveType - Detect drive type and capabilities
 *
 * This function determines the type of floppy drive by sensing various
 * SWIM III signals to identify drive capabilities.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x47: Drive type code
 *                         0x00 = basic drive
 *                         0xfe = enhanced drive (supports 1.44MB)
 *                         0xff = high-density drive (supports 1.2MB/1.44MB)
 *
 * Returns:
 *   bool - true if drive is present, false otherwise
 *
 * Signal meanings:
 *   0xf7 - Drive presence/type sense
 *   0xf5 - Drive capability sense 1
 *   0xf6 - Drive capability sense 2 (set and read)
 *
 * Drive type detection:
 *   - Signal 0xf7 = 0: drive present
 *   - Signal 0xf5 != 0: enhanced drive
 *   - Signal 0xf6 after set:
 *     - 0 = 1.44MB capable (0xfe)
 *     - 1 = 1.2MB/1.44MB capable (0xff)
 */
bool _HALGetDriveType(int param_1)
{
    unsigned char uVar1;
    int iVar2;
    int iVar3;

    // Select the disk drive
    _SwimIIIDiskSelect();

    // Check if drive is present (signal 0xf7)
    iVar2 = _SwimIIISenseSignal(0xf7);

    if (iVar2 == 0) {
        // Drive is present - initialize drive type to basic (0)
        *(unsigned char *)(param_1 + 0x47) = 0;

        // Check drive capabilities (signal 0xf5)
        iVar3 = _SwimIIISenseSignal(0xf5);

        if (iVar3 != 0) {
            // Enhanced drive - perform further detection

            // Set signal 0xf6 to test drive response
            _SwimIIISetSignal(0xf6);

            // Read back signal 0xf6
            iVar3 = _SwimIIISenseSignal(0xf6);

            if (iVar3 == 0) {
                // Signal low = 1.44MB capable drive
                uVar1 = 0xfe;
            }
            else {
                // Signal high = 1.2MB/1.44MB capable drive
                uVar1 = 0xff;
            }

            *(unsigned char *)(param_1 + 0x47) = uVar1;
        }
    }

    // Return true if drive is present (iVar2 == 0)
    return iVar2 == 0;
}


/*
 * _HALGetMediaType - Detect media type and density
 *
 * This function determines the type and density of the media (diskette)
 * inserted in the drive by sensing SWIM III signals.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x48: Media presence flag (0xff = media present)
 *             offset 0x49: Media density type
 *                         0x00 = double-density (720K/800K)
 *                         0xfe = high-density 1.44MB
 *                         0xff = high-density 1.2MB
 *
 * Signal meanings:
 *   0xf5 - Media type detection enable
 *   0xff - Media presence sense
 *   0xf6 - Density detection (set and read)
 *
 * Media detection logic:
 *   - Signal 0xf5 = 0: No media detection available
 *   - Signal 0xff = 0: Media present (0x48 = 0xff)
 *     - Signal 0xf6 after set:
 *       - 0 = 1.44MB (0x49 = 0xfe)
 *       - 1 = 1.2MB (0x49 = 0xff)
 *   - Signal 0xff != 0: Double-density media (0x49 = 0)
 */
void _HALGetMediaType(int param_1)
{
    int iVar1;

    // Initialize media type fields to 0 (no media/unknown)
    *(unsigned char *)(param_1 + 0x48) = 0;
    *(unsigned char *)(param_1 + 0x49) = 0;

    // Check if media type detection is available (signal 0xf5)
    iVar1 = _SwimIIISenseSignal(0xf5);

    if (iVar1 != 0) {
        // Media detection available - check for media presence (signal 0xff)
        iVar1 = _SwimIIISenseSignal(0xff);

        if (iVar1 == 0) {
            // Media is present
            *(unsigned char *)(param_1 + 0x48) = 0xff;

            // Detect density by setting and reading signal 0xf6
            _SwimIIISetSignal(0xf6);
            iVar1 = _SwimIIISenseSignal(0xf6);

            if (iVar1 == 0) {
                // Signal low = 1.44MB high-density media
                *(unsigned char *)(param_1 + 0x49) = 0xfe;
            }
            else {
                // Signal high = 1.2MB high-density media
                *(unsigned char *)(param_1 + 0x49) = 0xff;
            }
        }
        else {
            // No media present or double-density media
            *(unsigned char *)(param_1 + 0x48) = 0xff;
            *(unsigned char *)(param_1 + 0x49) = 0;
        }
    }

    return;
}


/*
 * _HALGetNextAddressID - Read next address mark from diskette
 *
 * This function reads the next sector address mark (ID field) from the
 * diskette. It waits for the SWIM III controller to detect an address
 * mark and then reads the track, head, sector, and format information.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x1c: Track number (from address mark)
 *             offset 0x1d: Head number (from address mark bit 7)
 *             offset 0x1e: Sector number (from address mark)
 *             offset 0x1f: Format byte (sector size code)
 *             offset 0x21: Head select (input)
 *
 * Process:
 *   1. Reset DMA channel
 *   2. Cancel any pending OS events
 *   3. Select head and enter read mode
 *   4. Wait for address mark (event bit 2, timeout 400ms)
 *   5. Read address mark fields from SWIM III registers
 *   6. Disable read mode and record any errors
 *
 * SWIM III address mark registers:
 *   0xfc44 - Track number (bits 0-6) and head (bit 7)
 *   0xfc48 - Sector number (bits 0-6)
 *   0xfc4c - Format byte (sector size code)
 */
void _HALGetNextAddressID(int param_1)
{
    short sVar1;

    // Reset DMA channel to prepare for read operation
    _ResetDMAChannel();

    // Cancel any pending address mark events (event bit 2)
    _CancelOSEvent(_driveOSEventIDptr, 4);

    // Select the head (side) to read from
    _SwimIIIHeadSelect(*(unsigned char *)(param_1 + 0x21));

    // Enable SWIM III read mode to detect address marks
    _SwimIIISetReadMode();

    // Wait for address mark event (timeout 400ms, event mask 8, event bit 2)
    sVar1 = _WaitForEvent(400, 8, 4);

    if (sVar1 == 0) {
        // Address mark detected successfully - read fields from SWIM III registers

        // Disable read mode before reading registers
        _SwimIIIDisableRWMode();

        // Read track number from register 0xfc44 (bits 0-6)
        *(unsigned char *)(param_1 + 0x1c) = *DAT_0000fc44 & 0x7f;
        _SynchronizeIO();

        // Read head number from register 0xfc44 (bit 7)
        *(unsigned char *)(param_1 + 0x1d) = *DAT_0000fc44 >> 7;
        _SynchronizeIO();

        // Read sector number from register 0xfc48 (bits 0-6)
        *(unsigned char *)(param_1 + 0x1e) = *DAT_0000fc48 & 0x7f;
        _SynchronizeIO();

        // Read format byte from register 0xfc4c (sector size code)
        *(unsigned char *)(param_1 + 0x1f) = *DAT_0000fc4c;
        _SynchronizeIO();
    }

    // Ensure read mode is disabled
    _SwimIIIDisableRWMode();

    // Record any error that occurred during the operation
    _RecordError((int)sVar1);

    return;
}


/*
 * _HALISR_DMA - DMA interrupt service routine
 *
 * This is the interrupt service routine (ISR) for DMA operations.
 * Currently empty as DMA interrupts may be handled elsewhere or
 * not used in this driver implementation.
 */
void _HALISR_DMA(void)
{
    return;
}


/*
 * _HALISRHandler - Main SWIM III interrupt service routine
 *
 * This is the main interrupt service routine (ISR) for the SWIM III
 * floppy controller. It reads the interrupt status, clears the interrupt,
 * and signals the appropriate OS event to wake up waiting threads.
 *
 * Interrupt status bits:
 *   bit 0 (0x01) - Index hole detected
 *   bit 1 (0x02) - Address mark detected
 *   bit 2 (0x04) - Data available
 *   bit 3 (0x08) - Track boundary
 *   bit 4 (0x10) - Write protect error
 *   bit 5 (0x20) - Error occurred
 *   bit 6 (0x40) - Ready state change
 *   bit 7 (0x80) - Reserved
 *
 * SWIM III registers:
 *   0xfc3c - Interrupt status register (read pending interrupts)
 *   0xfc58 - Interrupt acknowledge register (write to clear)
 *   0xfc34 - Control register (write 1 to reset)
 *   0xfc24 - Error status register (read when bit 5 is set)
 */
void _HALISRHandler(void)
{
    unsigned char bVar1;

    // Read interrupt status register
    bVar1 = *DAT_0000fc3c;
    _SynchronizeIO();

    if (bVar1 == 0) {
        // No interrupts pending - this should not happen
        _donone("HALISR: Pending interrupt is ZERO ");
    }
    else {
        // Clear interrupt by writing to acknowledge register
        *DAT_0000fc58 = 0;
        _SynchronizeIO();

        // Reset controller state
        *DAT_0000fc34 = 1;
        _SynchronizeIO();

        // Signal OS event with interrupt status bits
        _SetOSEvent(_driveOSEventIDptr, bVar1);

        // If error bit is set (bit 5), read error status register
        if ((bVar1 & 0x20) != 0) {
            _lastErrorsPending = *DAT_0000fc24;
            _SynchronizeIO();
        }
    }

    return;
}


/*
 * _HALPowerDownDrive - Power down the floppy drive
 *
 * This function powers down the floppy drive by selecting it and
 * setting the power-down signal.
 *
 * Signal meanings:
 *   0xf6 - Power control signal (set to power down)
 *
 * This is typically called when:
 *   - Drive is idle for extended period
 *   - System is entering low-power mode
 *   - Driver is being unloaded
 */
void _HALPowerDownDrive(void)
{
    // Select the disk drive
    _SwimIIIDiskSelect();

    // Set power-down signal
    _SwimIIISetSignal(0xf6);

    return;
}


/*
 * _HALPowerUpDrive - Power up the floppy drive
 *
 * This function powers up the floppy drive and waits for it to become ready.
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Signal meanings:
 *   0xfd - Power control signal (set to power up)
 *   0xf2 - Motor enable signal (set to start motor)
 *
 * Process:
 *   1. Set power-up signal (0xfd)
 *   2. Enable drive motor (0xf2)
 *   3. Wait for drive to become ready (1ms timeout)
 */
int _HALPowerUpDrive(void)
{
    short sVar1;

    // Set power-up signal
    _SwimIIISetSignal(0xfd);

    // Enable drive motor
    _SwimIIISetSignal(0xf2);

    // Wait for drive to become ready (1ms delay)
    sVar1 = _SleepUntilReady(1);

    return (int)sVar1;
}


/*
 * _HALReadSector - Read a sector from diskette
 *
 * This function reads a single sector from the diskette using DMA.
 * It sets up the SWIM III controller registers and initiates a DMA
 * transfer to read the sector data.
 *
 * Parameters:
 *   param_1 - Drive/sector structure pointer
 *             offset 0x20: Track number
 *             offset 0x21: Head number (0 or 1)
 *             offset 0x22: Sector number
 *             offset 0x28: DMA buffer address
 *             offset 0x56: Sector size in bytes
 *
 * Returns:
 *   int - 0 on success, DMA error code on failure
 *
 * SWIM III registers:
 *   0xfc54 - Read enable register (set to 1)
 *   0xfc4c - Format control register (set to 0)
 *   0xfc50 - Sector number register (set to target sector, then 0xff)
 *
 * Process:
 *   1. Enable read mode (0xfc54 = 1)
 *   2. Set format control (0xfc4c = 0)
 *   3. Set target sector number
 *   4. Select head
 *   5. Start DMA channel to read sector data
 *   6. Disable read/write mode
 *   7. Reset sector number register (0xff)
 */
int _HALReadSector(int param_1)
{
    short sVar1;

    // Enable read mode
    *DAT_0000fc54 = 1;
    _SynchronizeIO();

    // Set format control register to 0
    *DAT_0000fc4c = 0;
    _SynchronizeIO();

    // Set target sector number
    *DAT_0000fc50 = *(unsigned char *)(param_1 + 0x22);
    _SynchronizeIO();

    // Select the head (side)
    _SwimIIIHeadSelect(*(unsigned char *)(param_1 + 0x21));

    // Start DMA channel to read sector (flag=1 for read)
    sVar1 = _StartDMAChannel(*(unsigned int *)(param_1 + 0x28),
                             (int)*(short *)(param_1 + 0x56),
                             1);

    if (sVar1 != 0) {
        // DMA failed - log error
        _donone("HALRead failed for %d:%d:%d ",
               *(unsigned char *)(param_1 + 0x21),
               (int)*(char *)(param_1 + 0x20),
               *(unsigned char *)(param_1 + 0x22));
    }

    // Disable read/write mode
    _SwimIIIDisableRWMode();

    // Reset sector number register
    *DAT_0000fc50 = 0xff;
    _SynchronizeIO();

    return (int)sVar1;
}


/*
 * _HALRecalDrive - Recalibrate drive to track 0
 *
 * This function recalibrates the floppy drive by stepping backwards
 * until track 0 is detected, then formats the track cache.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x52: Maximum step count
 *             offset 0x5a: Format type (0=MFM, non-zero=GCR)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Signal meanings:
 *   0xfa - Track 0 sensor (0 = at track 0)
 *
 * Process:
 *   1. Step backwards until track 0 detected or max steps reached
 *   2. Sleep 30ms to allow mechanical settling
 *   3. Verify track 0 was reached, record error if not
 *   4. Format track cache based on format type (GCR or MFM)
 *
 * Error codes:
 *   0xffffffb4 (-76) - Failed to reach track 0
 */
int _HALRecalDrive(int param_1)
{
    short sVar1;
    short sVar3;
    int iVar2;
    int iVar4;

    iVar4 = 0;
    sVar1 = *(short *)(param_1 + 0x52);

    // Step backwards until track 0 detected or max steps reached
    while ((sVar1 = sVar1 - 1, sVar1 != -1 &&
           (iVar2 = _SwimIIISenseSignal(0xfa), iVar2 != 0))) {
        // Step one track inward (direction 0xffffffff = backwards)
        sVar3 = _SwimIIIStepDrive(0xffffffff);
        iVar4 = (int)sVar3;

        if (iVar4 != 0) {
            // Step failed
            return iVar4;
        }
    }

    if (iVar4 != 0) {
        return iVar4;
    }

    // Allow mechanical settling (30ms)
    sVar3 = _SleepUntilReady(0x1e);
    if (sVar3 != 0) {
        return (int)sVar3;
    }

    iVar4 = 0;

    // Verify track 0 was reached
    if ((sVar1 == 0) && (iVar2 = _SwimIIISenseSignal(0xfa), iVar2 != 0)) {
        // Track 0 not reached after maximum steps
        sVar1 = _RecordError(0xffffffb4);
        iVar4 = (int)sVar1;
    }

    if (iVar4 != 0) {
        return iVar4;
    }

    // Format track cache based on format type
    if (*(char *)(param_1 + 0x5a) != '\0') {
        // GCR format (Mac-style: 400K, 800K)
        _FormatGCRCacheSWIMIIIData(param_1);
        return 0;
    }

    // MFM format (PC-style: 720K, 1.44MB, 1.2MB)
    _FormatMFMCacheSWIMIIIData(param_1);
    return 0;
}


/*
 * _HALReset - Reset and initialize SWIM III controller
 *
 * This function performs a complete reset and initialization of the
 * SWIM III floppy controller. It sets up all hardware register pointers,
 * initializes the DMA channel, and resets the controller to a known state.
 *
 * Parameters:
 *   param_1 - Drive structure base address
 *             offset 0x08: OS event ID (set as _driveOSEventIDptr)
 *             offset 0xb8-0xc4: Buffer pointers (initialized to 0 if NULL)
 *             offset 0x320: Drive ready flag (set to 1)
 *   param_2 - SWIM III register base address
 *             Registers mapped at offsets: +0x10, +0x20, +0x30, etc.
 *   param_3 - DMA register base address
 *
 * Returns:
 *   unsigned int - 0 on success
 *
 * SWIM III register mapping (from param_2):
 *   +0x10 (0xfc20) - Command register
 *   +0x20 (0xfc24) - Error status register
 *   +0x30 (0xfc28) - Status register 1
 *   +0x40 (0xfc2c) - Status register 2
 *   +0x50 (0xfc30) - Mode register
 *   +0x60 (0xfc34) - Control register
 *   +0x70 (0xfc38) - Timer register
 *   +0x80 (0xfc3c) - Interrupt status register
 *   +0x90 (0xfc40) - Interrupt enable register
 *   +0xa0 (0xfc44) - Track/head register
 *   +0xb0 (0xfc48) - Sector number register
 *   +0xc0 (0xfc4c) - Format byte register
 *   +0xd0 (0xfc50) - Target sector register
 *   +0xe0 (0xfc54) - Read enable register
 *   +0xf0 (0xfc58) - Interrupt acknowledge register
 *
 * Process:
 *   1. Initialize error status to 0
 *   2. Set up OS event pointer
 *   3. Map all SWIM III hardware registers
 *   4. Set drive ready flag
 *   5. Initialize DMA channel and allocate command buffers
 *   6. Initialize buffer pointers if NULL
 *   7. Reset SWIM III controller
 *   8. Set mode register to 0x20
 */
unsigned int _HALReset(int param_1, int param_2, unsigned int param_3)
{
    // Initialize error status
    _lastErrorsPending = 0;

    // Set OS event pointer (param_1 + 8)
    _driveOSEventIDptr = (unsigned int *)(param_1 + 8);

    // Map SWIM III hardware registers from base address (param_2)
    DAT_0000fc20 = (unsigned char *)(param_2 + 0x10);  // Command register
    DAT_0000fc24 = (unsigned char *)(param_2 + 0x20);  // Error status register
    DAT_0000fc28 = (unsigned char *)(param_2 + 0x30);  // Status register 1
    DAT_0000fc2c = (unsigned char *)(param_2 + 0x40);  // Status register 2
    DAT_0000fc30 = (unsigned char *)(param_2 + 0x50);  // Mode register
    DAT_0000fc34 = (unsigned char *)(param_2 + 0x60);  // Control register
    DAT_0000fc38 = (unsigned char *)(param_2 + 0x70);  // Timer register
    DAT_0000fc3c = (unsigned char *)(param_2 + 0x80);  // Interrupt status register
    DAT_0000fc40 = (unsigned char *)(param_2 + 0x90);  // Interrupt enable register
    DAT_0000fc44 = (unsigned char *)(param_2 + 0xa0);  // Track/head register
    DAT_0000fc48 = (unsigned char *)(param_2 + 0xb0);  // Sector number register
    DAT_0000fc4c = (unsigned char *)(param_2 + 0xc0);  // Format byte register
    DAT_0000fc50 = (unsigned char *)(param_2 + 0xd0);  // Target sector register
    DAT_0000fc54 = (unsigned char *)(param_2 + 0xe0);  // Read enable register
    DAT_0000fc58 = (unsigned char *)(param_2 + 0xf0);  // Interrupt acknowledge register

    // Store SWIM III register base address
    _FloppySWIMIIIRegs = param_2;

    // Set drive ready flag
    *(unsigned short *)(param_1 + 800) = 1;

    // Store DMA register base address
    _GRCFloppyDMARegs = param_3;

    // Initialize DMA channel and allocate command buffers
    _OpenDBDMAChannel(param_3, &_GRCFloppyDMAChannel, 1,
                     &_ccCommandsLogicalAddr, &_ccCommandsPhysicalAddr);

    // Initialize buffer pointers if NULL
    if (*(int *)(param_1 + 0xb8) == 0) {
        *(unsigned int *)(param_1 + 0xbc) = 0;
        *(unsigned int *)(param_1 + 0xb8) = 0;
        *(unsigned int *)(param_1 + 0xc0) = 0;
    }

    *(unsigned int *)(param_1 + 0xc4) = 0;

    // Reset SWIM III controller by toggling control register
    *DAT_0000fc34 = ~*DAT_0000fc34;
    _SynchronizeIO();

    // Set mode register to 0x20
    *DAT_0000fc30 = 0x20;
    _SynchronizeIO();

    return 0;
}


/*
 * _HALSeekDrive - Seek drive to target track
 *
 * This function seeks the drive head to a target track and formats
 * the track cache for the new position.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x1c: Current track position
 *             offset 0x20: Target track position
 *             offset 0x5a: Format type (0=MFM, non-zero=GCR)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Process:
 *   1. Calculate step distance (target - current)
 *   2. Step drive to target track
 *   3. Wait 30ms for mechanical settling
 *   4. Format track cache based on format type
 */
int _HALSeekDrive(int param_1)
{
    short sVar1;
    int iVar2;

    // Calculate and execute step (target track - current track)
    sVar1 = _SwimIIIStepDrive((int)*(char *)(param_1 + 0x20) -
                              (int)*(char *)(param_1 + 0x1c));
    iVar2 = (int)sVar1;

    if (iVar2 == 0) {
        // Step successful - wait for mechanical settling (30ms)
        sVar1 = _SleepUntilReady(0x1e);
        iVar2 = (int)sVar1;

        if (iVar2 == 0) {
            // Format track cache based on format type
            if (*(char *)(param_1 + 0x5a) == '\0') {
                // MFM format (PC-style: 720K, 1.44MB, 1.2MB)
                _FormatMFMCacheSWIMIIIData(param_1);
            }
            else {
                // GCR format (Mac-style: 400K, 800K)
                _FormatGCRCacheSWIMIIIData(param_1);
            }
        }
    }

    return iVar2;
}


/*
 * _HALSetFormatMode - Set SWIM III to format mode
 *
 * This function configures the SWIM III controller for formatting
 * diskettes. It sets up timing parameters and mode registers based
 * on whether the diskette is GCR or MFM format.
 *
 * Parameters:
 *   param_1 - Drive/format structure pointer
 *             offset 0x45: Signal mode (set to 0xfd)
 *             offset 0x48: Media type (0=GCR, non-zero=MFM)
 *             offset 0x49: Media density (0xfe=1.44MB, else 1.2MB/720K)
 *             offset 0x54-0x5f: Format parameters
 *             offset 0x318-0x31e: Timing parameters (6 shorts)
 *             offset 0x320: Drive ready flag
 *
 * GCR format setup:
 *   - Timing: 0, 0x1f, calculated, 2
 *   - Mode register: 0x4c
 *   - Status register: 0x88
 *   - Signal: 0xfd
 *
 * MFM format setup:
 *   - Timing: calculated from format parameters
 *   - Mode register: 0x20 (1.44MB) or 0x28 (1.2MB/720K)
 *   - Status register: 0x95
 *   - Signal: 0xf9
 *
 * Process:
 *   1. Set signal mode to 0xfd
 *   2. Calculate timing parameters based on format type
 *   3. Format track cache
 *   4. Set SWIM III mode and status registers
 *   5. Set appropriate signal and wait 30ms
 */
void _HALSetFormatMode(int param_1)
{
    unsigned char uVar1;
    unsigned int uVar2;

    // Set signal mode
    *(unsigned char *)(param_1 + 0x45) = 0xfd;

    if (*(char *)(param_1 + 0x48) == '\0') {
        // GCR format (Mac-style: 400K, 800K)

        // Set timing parameters
        *(unsigned short *)(param_1 + 0x318) = 0;        // Pre-gap
        *(unsigned short *)(param_1 + 0x31a) = 0x1f;     // Sync length
        // Calculate data length
        *(short *)(param_1 + 0x31c) =
            (*(short *)(param_1 + 0x56) - *(short *)(param_1 + 0x54)) + 0x1f;
        *(unsigned short *)(param_1 + 0x31e) = 2;        // Post-gap

        // Format track cache
        _lastSectorsPerTrack = 0xff;
        _FormatGCRCacheSWIMIIIData();

        // Set SWIM III mode register for GCR format
        *DAT_0000fc30 = 0x4c;
        _SynchronizeIO();

        // Toggle control register
        *DAT_0000fc34 = ~*DAT_0000fc34;
        _SynchronizeIO();

        // Set status register
        *DAT_0000fc28 = 0x88;
        _SynchronizeIO();

        // Set GCR signal
        uVar2 = 0xfd;
    }
    else {
        // MFM format (PC-style: 720K, 1.44MB, 1.2MB)

        // Calculate timing parameters from format parameters
        *(unsigned short *)(param_1 + 0x318) =
            (unsigned short)*(unsigned char *)(param_1 + 0x5b) +
            *(unsigned char *)(param_1 + 0x5e) + 0x14;  // Pre-gap
        *(unsigned short *)(param_1 + 0x31a) =
            *(unsigned char *)(param_1 + 0x5c) + 0x30;   // Sync length
        *(unsigned short *)(param_1 + 0x31c) =
            *(unsigned char *)(param_1 + 0x5d) + 2;      // Data length
        *(unsigned short *)(param_1 + 0x31e) =
            *(unsigned char *)(param_1 + 0x5f) + 2;      // Post-gap

        // Format track cache
        _lastSectorsPerTrack = 0xff;
        _FormatMFMCacheSWIMIIIData(param_1);

        // Set mode register based on media density
        if (*(char *)(param_1 + 0x49) == -2) {
            // 1.44MB high-density
            uVar1 = 0x20;
        }
        else {
            // 1.2MB or 720K
            uVar1 = 0x28;
        }
        *DAT_0000fc30 = uVar1;
        _SynchronizeIO();

        // Toggle control register
        *DAT_0000fc34 = ~*DAT_0000fc34;
        _SynchronizeIO();

        // Set status register
        *DAT_0000fc28 = 0x95;
        _SynchronizeIO();

        // Set MFM signal
        uVar2 = 0xf9;
    }

    // Set the signal and wait for settling
    _SwimIIISetSignal(uVar2);
    _SleepUntilReady(0x1e);

    return;
}


/*
 * _HALWriteSector - Write a sector to diskette
 *
 * This function writes a single sector to the diskette using DMA.
 * It sets up the SWIM III controller registers, prepares the write
 * buffer with proper alignment and padding, and initiates a DMA
 * transfer to write the sector data.
 *
 * Parameters:
 *   param_1 - Drive/sector structure pointer
 *             offset 0x20: Track number
 *             offset 0x21: Head number (0 or 1)
 *             offset 0x22: Sector number
 *             offset 0x28: DMA buffer address
 *             offset 0x48: Media type (0=GCR, non-zero=MFM)
 *             offset 0x56: Sector size in bytes
 *             offset 0x5c: MFM sync length
 *             offset 0x320: DMA alignment requirement
 *
 * Returns:
 *   int - 0 on success, DMA error code on failure
 *
 * SWIM III registers:
 *   0xfc54 - Write enable register (set to 1)
 *   0xfc4c - Format control register (set to 0)
 *   0xfc50 - Sector number register (set to target sector, then 0xff)
 *
 * Process:
 *   1. Enable write mode (0xfc54 = 1)
 *   2. Set format control (0xfc4c = 0)
 *   3. Set target sector number
 *   4. Copy tail bytes after sector data
 *   5. Calculate write offset with alignment padding
 *   6. Select head
 *   7. Start DMA channel to write sector data
 *   8. Disable read/write mode
 *   9. Reset sector number register (0xff)
 */
int _HALWriteSector(int param_1)
{
    int iVar1;
    short sVar2;
    int iVar3;
    unsigned int uVar4;
    int iVar5;

    // Enable write mode
    *DAT_0000fc54 = 1;
    _SynchronizeIO();

    // Set format control register to 0
    *DAT_0000fc4c = 0;
    _SynchronizeIO();

    // Set target sector number
    *DAT_0000fc50 = *(unsigned char *)(param_1 + 0x22);
    _SynchronizeIO();

    // Copy tail bytes after sector data (2 bytes from tail pattern)
    _ByteMove((unsigned char *)s__0000e728,
             (int)*(short *)(param_1 + 0x56) + *(int *)(param_1 + 0x28) + 6,
             2);

    // Calculate write offset based on media type
    if (*(char *)(param_1 + 0x48) == '\0') {
        // GCR format - 15 bytes before data
        iVar5 = 0xf;
    }
    else {
        // MFM format - sync length + 22 bytes
        iVar5 = *(unsigned char *)(param_1 + 0x5c) + 0x16;
    }

    // Calculate base write address (buffer address - offset)
    uVar4 = *(int *)(param_1 + 0x28) - iVar5;

    // Calculate alignment padding
    iVar1 = 0;
    iVar3 = (int)*(short *)(param_1 + 800);  // DMA alignment requirement
    if (1 < iVar3) {
        // Calculate padding needed to align buffer
        iVar1 = ((uVar4 & -iVar3) + iVar3) - uVar4;
    }

    sVar2 = *(short *)(param_1 + 0x56);  // Sector size

    // Select the head (side)
    _SwimIIIHeadSelect(*(unsigned char *)(param_1 + 0x21));

    // Start DMA channel to write sector (flag=0 for write)
    // Total length: offset - padding + 8 + sector size
    sVar2 = _StartDMAChannel(uVar4 + iVar1,
                            (iVar5 - iVar1) + 8 + (int)sVar2,
                            0);

    if (sVar2 != 0) {
        // DMA failed - log error
        _donone("HALWrite failed for %d:%d:%d ",
               *(unsigned char *)(param_1 + 0x21),
               (int)*(char *)(param_1 + 0x20),
               *(unsigned char *)(param_1 + 0x22));
    }

    // Disable read/write mode
    _SwimIIIDisableRWMode();

    // Reset sector number register
    *DAT_0000fc50 = 0xff;
    _SynchronizeIO();

    return (int)sVar2;
}


/*
 * _InitializeDrive - Initialize drive structure and hardware
 *
 * This function performs complete initialization of the floppy drive,
 * including resource allocation, hardware setup, and drive detection.
 *
 * Parameters:
 *   param_1 - Drive number (short)
 *   param_2 - SWIM III register base address
 *   param_3 - DMA register base address
 *   param_4 - Additional parameter (passed to _HALReset)
 *   param_5 - Value stored at offset 0xb8
 *   param_6 - Value stored at offset 0xbc
 *   param_7 - Value stored at offset 0xc0
 *   param_8 - Pointer to drive structure pointer (output)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Process:
 *   1. Validate and lookup drive number
 *   2. Create hardware lock resources
 *   3. Create OS event resources
 *   4. Enter hardware lock section
 *   5. Store parameters in drive structure
 *   6. Reset and initialize SWIM III controller
 *   7. Detect drive type
 *   8. If drive detected, set up initial state
 *   9. Exit hardware lock section
 *
 * Drive structure initialization:
 *   offset 0x00: Hardware lock ID
 *   offset 0x0c: Clear ready counter
 *   offset 0x1c: Set to 0 (current track)
 *   offset 0x28: Clear last error
 *   offset 0x3d: Set to 2 (detecting), then 1 (idle) if drive found
 *   offset 0xb8-0xc0: Store buffer parameters
 */
int _InitializeDrive(unsigned int param_1, unsigned int param_2, unsigned int param_3,
                    unsigned int param_4, unsigned int param_5, unsigned int param_6,
                    unsigned int param_7, unsigned int **param_8)
{
    short sVar3;
    unsigned int uVar1;
    int iVar2;
    int iVar4;

    // Validate drive number and get drive structure pointer
    sVar3 = _CheckDriveNumber(param_1, param_8);
    iVar4 = (int)sVar3;

    if (iVar4 == 0) {
        // Get drive structure from pointer
        param_8 = (unsigned int **)*param_8;

        // Create hardware lock resources for mutual exclusion
        sVar3 = _CreateOSHardwareLockResources((unsigned int *)param_8);
        iVar4 = (int)sVar3;

        if (iVar4 == 0) {
            // Create OS event resources for interrupt handling
            sVar3 = _CreateOSEventResources((unsigned int *)param_8 + 2);
            iVar4 = (int)sVar3;

            if (iVar4 == 0) {
                // Enter hardware lock section
                uVar1 = _EnterHardwareLockSection();
                *param_8 = (unsigned int *)uVar1;

                // Store buffer parameters in drive structure
                param_8[0x2e] = (unsigned int *)param_5;  // offset 0xb8
                param_8[0x2f] = (unsigned int *)param_6;  // offset 0xbc
                param_8[0x30] = (unsigned int *)param_7;  // offset 0xc0

                // Reset and initialize SWIM III controller
                sVar3 = _HALReset((int)param_8, param_2, param_3, param_4);
                iVar4 = (int)sVar3;

                if (iVar4 == 0) {
                    // Initialize ready counter to 0
                    *(unsigned short *)(param_8 + 3) = 0;

                    // Set state to "detecting" (2)
                    *(unsigned char *)((int)param_8 + 0x3d) = 2;

                    // Detect drive type
                    iVar2 = _HALGetDriveType((int)param_8);

                    if (iVar2 != 0) {
                        // Drive detected - initialize state
                        _DumpTrackCache((int)param_8);

                        // Set state to "idle" (1)
                        *(unsigned char *)((int)param_8 + 0x3d) = 1;

                        // Clear current track
                        *(unsigned char *)(param_8 + 0xf) = 0;

                        // Set last error to 0xff (no error)
                        *(unsigned char *)(param_8 + 7) = 0xff;

                        // Clear ready counter
                        param_8[0xc] = 0;

                        // Power down drive (idle state)
                        _PowerDriveDown((int)param_8, 0);
                    }
                }

                // Exit hardware lock section
                _ExitHardwareLockSection((unsigned int)*param_8);
            }
        }
    }

    return iVar4;
}


/*
 * _InitFormatTable - Initialize diskette format table
 *
 * This function initializes a global table containing format descriptors
 * for all supported floppy disk formats. Each entry contains parameters
 * like capacity, sectors per track, track count, sector size, etc.
 *
 * Format table entries (20 bytes each, starting at DAT_0000fb90):
 *   Entry 0: 400K Mac GCR (single-sided)
 *   Entry 1: 800K Mac GCR (double-sided)
 *   Entry 2: 720K PC MFM
 *   Entry 3: 1.44MB PC MFM (high-density)
 *   Entry 4: 1.2MB PC MFM (5.25" high-density)
 *
 * Each entry structure:
 *   +0x00 (4 bytes): Capacity in KB
 *   +0x04 (1 byte):  Format flags (bits 0-6: sectors, bit 7: density)
 *   +0x05 (1 byte):  Tracks per disk
 *   +0x06 (2 bytes): Total sectors
 *   +0x08 (2 bytes): Sector size in bytes
 *   +0x0a (2 bytes): Track size in bytes
 *   +0x0c (1 byte):  Format type (0=GCR, 1=MFM)
 *   +0x0d (1 byte):  Heads (1=single, 2=double)
 *   +0x0e (1 byte):  Reserved/flags
 *   +0x0f-0x13:      MFM-specific parameters
 */
void _InitFormatTable(void)
{
    // Entry 0: 400K Mac GCR (single-sided, 80 tracks, 9-12 sectors/track)
    DAT_0000fb90 = 800;        // Capacity: 800 blocks (400K)
    DAT_0000fb94 = 0x81;       // Format flags
    DAT_0000fb95 = 10;         // Tracks per disk (outer zone)
    DAT_0000fb96 = 0x50;       // Total sectors
    DAT_0000fb98 = 0x200;      // Sector size: 512 bytes
    DAT_0000fb9a = 0x2c0;      // Track size: 704 bytes
    DAT_0000fb9c = 0;          // Format type: GCR
    DAT_0000fb9d = 2;          // Heads: double-sided (actual use may vary)
    DAT_0000fb9e = 1;          // Reserved/flags

    // Entry 1: 800K Mac GCR (double-sided, 80 tracks, 9-12 sectors/track)
    DAT_0000fba4 = 0x640;      // Capacity: 1600 blocks (800K)
    DAT_0000fba8 = 0x82;       // Format flags
    DAT_0000fba9 = 10;         // Tracks per disk (outer zone)
    DAT_0000fbaa = 0x50;       // Total sectors
    DAT_0000fbac = 0x200;      // Sector size: 512 bytes
    DAT_0000fbae = 0x2c0;      // Track size: 704 bytes
    DAT_0000fbb0 = 0;          // Format type: GCR
    DAT_0000fbb1 = 2;          // Heads: double-sided
    DAT_0000fbb2 = 1;          // Reserved/flags

    // Entry 2: 720K PC MFM (double-sided, 80 tracks, 9 sectors/track)
    DAT_0000fbb8 = 0x5a0;      // Capacity: 1440 blocks (720K)
    DAT_0000fbbc = 0x82;       // Format flags
    DAT_0000fbbd = 9;          // Sectors per track: 9
    DAT_0000fbbe = 0x50;       // Total tracks: 80
    DAT_0000fbc0 = 0x200;      // Sector size: 512 bytes
    DAT_0000fbc2 = 0x200;      // Track size: 512 bytes
    DAT_0000fbc4 = 1;          // Format type: MFM
    DAT_0000fbc5 = 1;          // Heads: single (or interleave)
    DAT_0000fbc6 = 0;          // Reserved
    DAT_0000fbc7 = 0x32;       // MFM parameter: gap 1 (50 bytes)
    DAT_0000fbc8 = 0x16;       // MFM parameter: sync length (22 bytes)
    DAT_0000fbc9 = 0x54;       // MFM parameter: gap 2 (84 bytes)
    DAT_0000fbca = 0x50;       // MFM parameter: gap 3 (80 bytes)
    DAT_0000fbcb = 0xb6;       // MFM parameter: gap 4 (182 bytes)

    // Entry 3: 1.44MB PC MFM (double-sided, 80 tracks, 18 sectors/track)
    DAT_0000fbcc = 0xb40;      // Capacity: 2880 blocks (1.44MB)
    DAT_0000fbd0 = 0x92;       // Format flags
    DAT_0000fbd1 = 0x12;       // Sectors per track: 18
    DAT_0000fbd2 = 0x50;       // Total tracks: 80
    DAT_0000fbd4 = 0x200;      // Sector size: 512 bytes
    DAT_0000fbd6 = 0x200;      // Track size: 512 bytes
    DAT_0000fbd8 = 1;          // Format type: MFM
    DAT_0000fbd9 = 1;          // Heads: single (or interleave)
    DAT_0000fbda = 0;          // Reserved
    DAT_0000fbdb = 0x32;       // MFM parameter: gap 1 (50 bytes)
    DAT_0000fbdc = 0x16;       // MFM parameter: sync length (22 bytes)
    DAT_0000fbdd = 0x65;       // MFM parameter: gap 2 (101 bytes)
    DAT_0000fbde = 0x50;       // MFM parameter: gap 3 (80 bytes)
    DAT_0000fbdf = 0xcc;       // MFM parameter: gap 4 (204 bytes)

    // Entry 4: 1.2MB PC MFM (double-sided, 80 tracks, 15 sectors/track)
    DAT_0000fbe0 = 0xd20;      // Capacity: 3360 blocks (1.68MB actual, 1.2MB formatted)
    DAT_0000fbe4 = 0x92;       // Format flags
    DAT_0000fbe5 = 0x15;       // Sectors per track: 21
    DAT_0000fbe6 = 0x50;       // Total tracks: 80
    DAT_0000fbe8 = 0x200;      // Sector size: 512 bytes
    DAT_0000fbea = 0x200;      // Track size: 512 bytes
    DAT_0000fbec = 1;          // Format type: MFM
    DAT_0000fbed = 2;          // Heads: double-sided
    DAT_0000fbee = 0;          // Reserved
    DAT_0000fbef = 0x32;       // MFM parameter: gap 1 (50 bytes)
    DAT_0000fbf0 = 0x16;       // MFM parameter: sync length (22 bytes)
    DAT_0000fbf1 = 8;          // MFM parameter: gap 2 (8 bytes)
    DAT_0000fbf2 = 0x50;       // MFM parameter: gap 3 (80 bytes)
    DAT_0000fbf3 = 0x84;       // MFM parameter: gap 4 (132 bytes)

    // Entry 5: 5.76MB PC MFM (extended capacity, not commonly used)
    DAT_0000fbf4 = 0x1680;     // Capacity: 5760 blocks (2.88MB)
    DAT_0000fbf8 = 0x92;       // Format flags
    DAT_0000fbf9 = 0x24;       // Sectors per track: 36
    DAT_0000fbfa = 0x50;       // Total tracks: 80
    DAT_0000fbfc = 0x200;      // Sector size: 512 bytes
    DAT_0000fbfe = 0x200;      // Track size: 512 bytes
    DAT_0000fc00 = 1;          // Format type: MFM
    DAT_0000fc01 = 1;          // Heads: single (or interleave)
    DAT_0000fc02 = 0;          // Reserved
    DAT_0000fc03 = 0x32;       // MFM parameter: gap 1 (50 bytes)
    DAT_0000fc04 = 0x29;       // MFM parameter: sync length (41 bytes)
    DAT_0000fc05 = 0x53;       // MFM parameter: gap 2 (83 bytes)
    DAT_0000fc06 = 0x50;       // MFM parameter: gap 3 (80 bytes)

    return;
}


/*
 * _KillMediaScanTask - Terminate media scan task
 *
 * This function terminates the background media scan task that
 * monitors for diskette insertion/removal.
 *
 * Returns:
 *   unsigned int - 0 on success
 */
unsigned int _KillMediaScanTask(void)
{
    return 0;
}


/*
 * _LaunchMediaScanTask - Launch media scan background task
 *
 * This function launches a background task that periodically scans
 * for media insertion and removal events.
 *
 * Returns:
 *   unsigned int - 0 on success
 *
 * The task ID is stored in the global variable _MediaScanTaskID.
 */
unsigned int _LaunchMediaScanTask(void)
{
    // Launch media scan task with entry point and task structure
    _MediaScanTaskID = FUN_0000a300(_entry, &_MediaScanTask);

    return 0;
}


/*
 * _LookupFormatTable - Lookup disk format information
 *
 * This function looks up disk format information from the global format
 * table initialized by _InitFormatTable(). It returns format descriptors
 * for the available formats based on the drive capabilities.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x3c: Drive capability flags
 *   param_2 - Pointer to requested format count (input/output)
 *   param_3 - Pointer to minimum format index (output)
 *   param_4 - Pointer to maximum format index (output)
 *   param_5 - Pointer to default format index (output)
 *   param_6 - Pointer to format descriptor buffer (output array)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Error codes:
 *   0xffffffbf (-65) - Drive not detected or invalid
 *   0xffffffce (-50) - Invalid format count (<=0)
 *
 * Format descriptor structure (8 bytes each):
 *   +0x00 (4 bytes): Capacity in blocks
 *   +0x04 (1 byte):  Format flags (bit 6=default)
 *   +0x05 (1 byte):  Tracks per disk
 *   +0x06 (2 bytes): Total sectors
 *
 * Process:
 *   1. Check drive capability (must be >= 2)
 *   2. Validate format count (must be > 0)
 *   3. Call _AvailableFormats to determine format range
 *   4. Adjust count if necessary
 *   5. Copy format descriptors from global table
 *   6. Mark default format with bit 6 set
 */
int _LookupFormatTable(int param_1, short *param_2, short *param_3, short *param_4,
                      short *param_5, unsigned int *param_6)
{
    unsigned char bVar1;
    unsigned int uVar2;
    short sVar3;
    int iVar4;

    // Check drive capability flags
    if (*(unsigned char *)(param_1 + 0x3c) < 2) {
        // Drive not detected or invalid
        uVar2 = 0xffffffbf;
    }
    else {
        // Validate requested format count
        if (0 < *param_2) {
            // Determine available format range for this drive
            _AvailableFormats(param_1, param_3, param_4, param_5);

            // Calculate actual number of formats available
            sVar3 = (*param_4 - *param_3) + 1;

            // Adjust count if more formats requested than available
            if (sVar3 <= *param_2) {
                *param_2 = sVar3;
            }

            // Get starting format index
            iVar4 = (int)*param_3;

            // Check if range is valid
            if (*param_4 < iVar4) {
                return 0;
            }

            // Copy format descriptors from global table
            do {
                // Copy capacity (4 bytes)
                *param_6 = (&DAT_0000fb90)[iVar4 * 5];

                // Copy tracks per disk (1 byte at offset +5)
                *(unsigned char *)((int)param_6 + 5) = (&DAT_0000fb95)[iVar4 * 0x14];

                // Copy total sectors (2 bytes at offset +6)
                *(unsigned short *)((int)param_6 + 6) = (&DAT_0000fb96)[iVar4 * 10];

                // Copy format flags and mark default format
                if (iVar4 == *param_5) {
                    // Set bit 6 to mark this as the default format
                    bVar1 = (&DAT_0000fb94)[iVar4 * 0x14] | 0x40;
                }
                else {
                    // Copy flags without modification
                    bVar1 = (&DAT_0000fb94)[iVar4 * 0x14];
                }
                *(unsigned char *)(param_6 + 1) = bVar1;

                // Advance to next descriptor (8 bytes = 2 ints)
                param_6 = param_6 + 2;

                // Move to next format index
                iVar4 = (int)(short)((short)iVar4 + 1);
            } while (iVar4 <= *param_4);

            return 0;
        }

        // Invalid format count (<=0)
        uVar2 = 0xffffffce;
    }

    // Record error and return
    sVar3 = _RecordError(uVar2);
    return (int)sVar3;
}


/*
 * _MemListDescriptorDataCompare - Compare memory list descriptor data
 *
 * This function compares data in memory list descriptors.
 * Currently implemented as a stub.
 *
 * Returns:
 *   unsigned int - 0 (always)
 */
unsigned int _MemListDescriptorDataCompare(void)
{
    return 0;
}


/*
 * _MemListDescriptorDataCompareWithMemory - Compare descriptor with memory
 *
 * This function compares memory list descriptor data with memory contents.
 * Currently implemented as a stub.
 *
 * Returns:
 *   unsigned int - 0 (always)
 */
unsigned int _MemListDescriptorDataCompareWithMemory(void)
{
    return 0;
}


/*
 * _MemListDescriptorDataCopyFromMemory - Copy descriptor data from memory
 *
 * This function copies data from memory into a memory list descriptor.
 * The operation depends on the data source type.
 *
 * Returns:
 *   unsigned int - Result code from copy operation
 *
 * Data sources:
 *   2 - Special source requiring FUN_00006ba8
 *   Other - Standard source using FUN_00006bb8
 */
unsigned int _MemListDescriptorDataCopyFromMemory(void)
{
    unsigned int uVar1;

    if (_DataSource == 2) {
        // Special data source - call alternate copy function
        uVar1 = FUN_00006ba8();
    }
    else {
        // Standard data source - call standard copy function
        FUN_00006bb8();
        uVar1 = 0;
    }

    return uVar1;
}


/*
 * _MemListDescriptorDataCopyToMemory - Copy descriptor data to memory
 *
 * This function copies data from a memory list descriptor to memory.
 * The operation depends on the data source type.
 *
 * Returns:
 *   unsigned int - Result code from copy operation
 *
 * Data sources:
 *   2 - Special source requiring FUN_00006b4c
 *   Other - Standard source using FUN_00006b5c
 */
unsigned int _MemListDescriptorDataCopyToMemory(void)
{
    unsigned int uVar1;

    if (_DataSource == 2) {
        // Special data source - call alternate copy function
        uVar1 = FUN_00006b4c();
    }
    else {
        // Standard data source - call standard copy function
        FUN_00006b5c();
        uVar1 = 0;
    }

    return uVar1;
}


/*
 * _NibblizeGCRChecksum - Nibblize GCR checksum
 *
 * This function converts a 24-bit checksum value into GCR 6-and-2 encoded
 * format. Each 8-bit byte is split into 6 data bits and 2 overflow bits.
 *
 * Parameters:
 *   param_1 - Output buffer (4 bytes minimum)
 *   param_2 - 24-bit checksum value
 *
 * Returns:
 *   unsigned char * - Pointer after written bytes (param_1 + 4)
 *
 * GCR 6-and-2 encoding:
 *   Byte 0: Overflow bits from all three bytes
 *           bits 0-1: from byte 2 (bits 6-7)
 *           bits 2-3: from byte 1 (bits 6-7)
 *           bits 4-5: from byte 0 (bits 6-7)
 *   Byte 1: Data bits 0-5 from checksum byte 0 (bits 16-23)
 *   Byte 2: Data bits 0-5 from checksum byte 1 (bits 8-15)
 *   Byte 3: Data bits 0-5 from checksum byte 2 (bits 0-7)
 *
 * Each nibblized byte has only 6 bits set (0x00-0x3f range).
 */
unsigned char *_NibblizeGCRChecksum(unsigned char *param_1, unsigned int param_2)
{
    // Extract data bits (0-5) from each checksum byte
    param_1[1] = (unsigned char)(param_2 >> 0x10) & 0x3f;  // Byte 0 data bits
    param_1[2] = (unsigned char)(param_2 >> 8) & 0x3f;     // Byte 1 data bits
    param_1[3] = (unsigned char)param_2 & 0x3f;            // Byte 2 data bits

    // Combine overflow bits (6-7) from all three bytes into byte 0
    *param_1 = (unsigned char)((param_2 >> 0x10 & 0xff) >> 2) & 0x30 |  // Bits 6-7 from byte 0
               (unsigned char)((param_2 >> 8 & 0xff) >> 4) & 0xc |      // Bits 6-7 from byte 1
               (unsigned char)((param_2 & 0xff) >> 6);                  // Bits 6-7 from byte 2

    return param_1 + 4;
}


/*
 * _NibblizeGCRData - Nibblize data into GCR format
 *
 * This function converts raw data bytes into GCR 6-and-2 encoded format
 * with checksum calculation. Each group of 3 input bytes produces 4 output
 * bytes (with overflow bits packed into the first byte).
 *
 * Parameters:
 *   param_1 - Input data buffer
 *   param_2 - Output nibblized buffer
 *   param_3 - Number of bytes to encode
 *   param_4 - Pointer to 24-bit checksum (updated)
 *
 * GCR 6-and-2 encoding:
 *   - Input bytes are XORed with running checksum
 *   - Checksum is updated with each byte
 *   - Output: 4 bytes per 3 input bytes
 *     - Byte 0: Overflow bits (bits 6-7) from up to 3 bytes
 *     - Bytes 1-3: Data bits (0-5) from each input byte
 *
 * Checksum calculation:
 *   - 24-bit value stored as (high byte << 16) | (mid byte << 8) | low byte
 *   - Each input byte added to appropriate checksum byte with carry
 *   - Checksum bytes XORed with data before encoding
 */
void _NibblizeGCRData(unsigned char *param_1, unsigned char *param_2, short param_3,
                      unsigned int *param_4)
{
    unsigned char bVar1;
    short sVar2;
    unsigned char *pbVar3;
    unsigned char bVar4;
    unsigned int uVar5;
    unsigned char *pbVar6;
    unsigned int uVar7;
    unsigned int uVar8;
    unsigned int uVar9;
    unsigned int uVar10;
    unsigned int uVar11;

    // Extract checksum bytes
    uVar11 = *param_4 >> 0x10 & 0xff;  // High byte
    uVar5 = *param_4 >> 8 & 0xff;       // Mid byte
    uVar7 = (unsigned int)*(unsigned char *)((int)param_4 + 3);  // Low byte

    uVar10 = 0;

    // Process input bytes in groups
    if (param_3 != 0) {
        do {
            // Process first byte
            uVar10 = uVar10 + uVar11 + *param_1;
            uVar8 = *param_1 ^ uVar7;
            uVar11 = uVar10 & 0xff;
            param_2[1] = (unsigned char)uVar8 & 0x3f;  // Data bits 0-5

            // Process second byte
            uVar5 = (uVar10 >> 8) + uVar5 + param_1[1];
            uVar9 = param_1[1] ^ uVar11;
            pbVar6 = param_1 + 2;
            uVar10 = uVar5 >> 8;
            uVar5 = uVar5 & 0xff;

            // Pack overflow bits from first two bytes
            bVar4 = (unsigned char)((uVar8 & 0xc0) >> 2) | (unsigned char)((uVar9 & 0xc0) >> 4);
            param_2[2] = (unsigned char)uVar9 & 0x3f;  // Data bits 0-5
            pbVar3 = param_2 + 3;
            sVar2 = param_3 - 2;

            // Process optional third byte (if available)
            if ((short)(param_3 - 2) != 0) {
                bVar1 = *pbVar6;
                uVar8 = bVar1 ^ uVar5;
                pbVar6 = param_1 + 3;
                uVar7 = uVar10 + uVar7 + bVar1 & 0xff;

                // Add third byte's overflow bits
                bVar4 = bVar4 | (unsigned char)(uVar8 >> 6);
                *pbVar3 = (unsigned char)uVar8 & 0x3f;  // Data bits 0-5
                pbVar3 = param_2 + 4;

                // Update low checksum byte with rotation
                uVar10 = uVar7 >> 7;
                uVar7 = uVar10 | uVar7 << 1;
                sVar2 = param_3 - 3;
            }

            param_3 = sVar2;

            // Write overflow bits byte
            *param_2 = bVar4;

            // Advance pointers
            param_2 = pbVar3;
            param_1 = pbVar6;
        } while (param_3 != 0);
    }

    // Update checksum
    *param_4 = (uVar11 << 8 | uVar5) << 8 | uVar7 & 0xff;

    return;
}


/*
 * _PostDisketteEvent - Post diskette state change event
 *
 * This function notifies the system of a diskette state change (insertion,
 * removal, or other media events) using the BSM (Block Storage Manager)
 * notification system.
 *
 * Parameters:
 *   param_1 - Event type/state code
 *   param_2 - Drive number (1-based)
 *
 * The function looks up the drive structure from a global table at
 * 0x0000f540 and calls BSMPINotifyFamilyStoreChangedState to notify
 * the system of the state change.
 *
 * Drive structure table:
 *   Base: DAT_0000f540 (0x0000f540)
 *   Entry size: 0x324 bytes
 *   Index: (drive_number - 1)
 */
void _PostDisketteEvent(unsigned char param_1, short param_2)
{
    // Calculate drive structure offset: (drive_number - 1) * 0x324
    // Call BSM notification with drive's family store ID and new state
    _BSMPINotifyFamilyStoreChangedState(
        *(unsigned int *)(&DAT_0000f540 + (param_2 - 1) * 0x324),
        param_1);

    return;
}


/*
 * _PowerDriveDown - Power down floppy drive
 *
 * This function powers down the floppy drive, either immediately or
 * deferred (queued for later execution).
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x44: Power state (set to 0 when powered down)
 *   param_2 - Power down mode
 *             0 = Immediate power down
 *             Other = Deferred power down (store for later)
 *
 * Immediate mode (param_2 == 0):
 *   1. Flush track cache to disk
 *   2. Dump (clear) track cache
 *   3. Call HAL to power down drive hardware
 *   4. Clear power state flag
 *   5. Clear global power state
 *
 * Deferred mode (param_2 != 0):
 *   1. Store mode in global DAT_0000fb8a
 *   2. Store drive structure in global DAT_0000fb8c
 *   3. Actual power down occurs later
 */
void _PowerDriveDown(int param_1, int param_2)
{
    if (param_2 == 0) {
        // Immediate power down

        // Flush any dirty track cache data to disk
        _FlushTrackCache();

        // Dump (clear) the track cache
        _DumpTrackCache(param_1);

        // Power down the drive hardware
        _HALPowerDownDrive(param_1);

        // Clear power state flag in drive structure
        *(unsigned char *)(param_1 + 0x44) = 0;

        // Clear global power state
        DAT_0000fb8a = 0;
    }
    else {
        // Deferred power down - queue for later

        // Store power down mode
        DAT_0000fb8a = (unsigned short)param_2;

        // Store drive structure for deferred power down
        DAT_0000fb8c = param_1;
    }

    return;
}


/*
 * _PowerDriveUp - Power up floppy drive
 *
 * This function powers up the floppy drive and performs format detection
 * if necessary.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x0c: Ready state flags
 *             offset 0x3c: Format detection state (0/1/2)
 *             offset 0x44: Power state
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Format detection states (offset 0x3c):
 *   0 - No format detection needed
 *   1 - Need to detect format (_GetDisketteFormat)
 *   2 - Format detected, need to set it (_SetDisketteFormat)
 *
 * Process:
 *   1. Check for deferred power down of other drive
 *   2. Clear global power state
 *   3. If drive already powered up, return
 *   4. Call HAL to power up drive hardware
 *   5. Wait 600ms if not in special ready state (0x10002)
 *   6. Perform format detection based on state
 *   7. Update power state to 2 (powered up)
 */
int _PowerDriveUp(int param_1)
{
    short sVar2;
    unsigned int uVar1;
    unsigned char uVar3;
    int iVar4;

    iVar4 = 0;

    // Check if another drive has deferred power down
    if ((DAT_0000fb8a != 0) && (DAT_0000fb8c != param_1)) {
        // Power down the other drive immediately
        _PowerDriveDown(DAT_0000fb8c, 0);
    }

    // Clear global power state
    DAT_0000fb8a = 0;

    // Default power state: 1 (powered up, no format detection)
    uVar3 = 1;

    // Check if drive is currently powered down (0)
    if (*(char *)(param_1 + 0x44) == '\0') {
        _donone("core.c:PowerDriveUp:calling HALPowerUpDrive ");

        // Power up the drive hardware
        sVar2 = _HALPowerUpDrive(param_1);
        iVar4 = (int)sVar2;

        if (iVar4 == 0) {
            // Power up successful

            // Wait for drive to stabilize (600ms), unless in special ready state
            if (*(int *)(param_1 + 0xc) != 0x10002) {
                sVar2 = _FloppyTimedSleep(600);
                iVar4 = (int)sVar2;
            }

            // Power state will be 2 (powered up with format detection)
            uVar3 = 2;

            // Perform format detection based on state
            if (*(char *)(param_1 + 0x3c) != '\0') {
                if (*(char *)(param_1 + 0x3c) == '\x01') {
                    // State 1: Need to detect diskette format
                    _donone("core.c:PowerDriveUp:calling GetDisketteFormat ");

                    sVar2 = _GetDisketteFormat(param_1);
                    iVar4 = (int)sVar2;

                    if (iVar4 == 0) {
                        // Format detected successfully - advance to state 2
                        *(unsigned char *)(param_1 + 0x3c) = 2;
                    }

                    _donone("core.c:PowerDriveUp:return code from GetdisketteFormat=%d ",
                           iVar4);
                }
                else if (*(char *)(param_1 + 0x3c) == '\x02') {
                    // State 2: Format detected, now set it
                    uVar1 = _GetDisketteFormatType(param_1);
                    sVar2 = _SetDisketteFormat(param_1, uVar1);
                    iVar4 = (int)sVar2;
                }
            }
        }
    }

    // Update power state in drive structure
    *(unsigned char *)(param_1 + 0x44) = uVar3;

    _donone("core.c:PowerDriveUp:return=%d ", iVar4);

    return iVar4;
}


/*
 * _PrepareCPUCacheForDMARead - Prepare CPU cache for DMA read operation
 *
 * This function prepares the CPU data cache for a DMA read operation by
 * invalidating cache lines in the DMA buffer region. This ensures that
 * the CPU will read fresh data from memory after the DMA transfer completes,
 * rather than stale data from the cache.
 *
 * Returns:
 *   unsigned int - 0 on success
 *
 * Cache region:
 *   Base: 0 (offset from buffer base)
 *   Size: 0xb000 (45056 bytes, ~44KB)
 */
unsigned int _PrepareCPUCacheForDMARead(void)
{
    // Invalidate CPU cache lines for DMA buffer region
    FUN_00006b00(0, 0xb000);

    return 0;
}


/*
 * _PrepareCPUCacheForDMAWrite - Prepare CPU cache for DMA write operation
 *
 * This function prepares the CPU data cache for a DMA write operation by
 * flushing cache lines in the DMA buffer region. This ensures that any
 * dirty data in the cache is written to memory before the DMA controller
 * reads it.
 *
 * Returns:
 *   unsigned int - 0 on success
 *
 * Cache region:
 *   Base: 0 (offset from buffer base)
 *   Size: 0xb000 (45056 bytes, ~44KB)
 */
unsigned int _PrepareCPUCacheForDMAWrite(void)
{
    // Flush CPU cache lines for DMA buffer region
    FUN_00006abc(0, 0xb000);

    return 0;
}


/*
 * _PrepDBDMA - Prepare DBDMA channel descriptor
 *
 * This function prepares a DBDMA (Descriptor-Based DMA) channel descriptor
 * by byte-swapping the address field for big-endian PowerPC architecture.
 *
 * Parameters:
 *   param_1 - DBDMA descriptor structure pointer
 *             offset 0x04: DBDMA channel registers pointer
 *             offset 0x18: Physical address (to be byte-swapped)
 *
 * DBDMA descriptor:
 *   +0x04 - Pointer to DBDMA channel registers
 *   +0x18 - Physical address (32-bit, needs byte swap)
 *
 * The function performs a 32-bit endian swap on the physical address:
 *   Input:  0xAABBCCDD
 *   Output: 0xDDCCBBAA
 *
 * The swapped address is written to offset +0x0c of the channel registers.
 */
void _PrepDBDMA(int param_1)
{
    unsigned int uVar1;

    // Get physical address from descriptor
    uVar1 = *(unsigned int *)(param_1 + 0x18);

    // Byte-swap the 32-bit address (big-endian to little-endian or vice versa)
    // Shift operations:
    //   uVar1 >> 0x18          - Move byte 3 to byte 0
    //   uVar1 >> 8 & 0xff00    - Move byte 2 to byte 1
    //   (uVar1 & 0xff00) << 8  - Move byte 1 to byte 2
    //   uVar1 << 0x18          - Move byte 0 to byte 3
    *(unsigned int *)(*(int *)(param_1 + 4) + 0xc) =
        uVar1 >> 0x18 | uVar1 >> 8 & 0xff00 | (uVar1 & 0xff00) << 8 | uVar1 << 0x18;

    return;
}


/*
 * _PrintDMA - Print DMA debugging information
 *
 * This function is a placeholder for DMA debugging output.
 * Currently implemented as an empty stub.
 */
void _PrintDMA(void)
{
    return;
}


/*
 * _ReadBlocks - Read blocks from diskette
 *
 * This function reads one or more logical blocks from the diskette with
 * retry logic and error handling.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x14: First block number (updated during read)
 *             offset 0x16: Track number
 *             offset 0x18: Block count
 *             offset 0x4a: Error retry counter (incremented on error)
 *             offset 0x4c: Maximum block number (disk capacity)
 *   param_2 - Pointer to bytes read counter (output)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Process:
 *   1. Check if drive is online
 *   2. Power up drive
 *   3. Validate block range
 *   4. For each block:
 *      - Get sector address
 *      - Flush cache and seek if needed
 *      - Read sector from cache (with retry)
 *      - On error: recalibrate and retry (up to 2 times)
 *   5. Power down drive (deferred, mode 6)
 *
 * Error codes:
 *   0xffffffb0 (-80) - Block number out of range
 */
int _ReadBlocks(int param_1, int *param_2)
{
    short sVar1;
    short sVar2;
    int iVar3;
    int iVar4;

    _donone("floppycore.c:ReadBlock:calling CheckDriveOnLine ");

    // Check if drive is online
    sVar1 = _CheckDriveOnLine(param_1);
    iVar4 = (int)sVar1;

    if (iVar4 == 0) {
        _donone("floppycore.c:ReadBlock:calling powerdriveup ");

        // Power up the drive
        sVar1 = _PowerDriveUp(param_1);
        iVar4 = (int)sVar1;

        if (iVar4 == 0) {
            _donone("core.c:ReadBlock:PowerDriveUp returned SUCCESS ");

            // Calculate last block number
            iVar3 = *(int *)(param_1 + 0x14) + *(int *)(param_1 + 0x18) - 1;
            _donone("lastblk=%d,firstblk=%d,blkcount=%d\n", iVar3);

            // Validate block range
            if (iVar3 < *(int *)(param_1 + 0x4c)) {
                iVar4 = 0;
                *param_2 = 0;

                _donone("core.c:readblocks:firstblk=%d,lastblk=%d ",
                       *(unsigned int *)(param_1 + 0x14), iVar3);

                // Read each block
                do {
                    // Check if we've read all blocks
                    if (iVar3 < *(int *)(param_1 + 0x14)) {
                        break;
                    }

                    // Retry loop (up to 2 retries)
                    sVar1 = 2;
                    do {
                        _donone("floppycore.c:ReadBlock:calling Get Sectoraddr ");

                        // Convert block number to track/head/sector
                        _GetSectorAddress(param_1, *(unsigned short *)(param_1 + 0x16));

                        _donone("core.c:ReadBlocks:call FlushCacheAndSeek ");

                        // Seek to track if needed and flush cache
                        sVar2 = _FlushCacheAndSeek(param_1);
                        iVar4 = (int)sVar2;

                        if (iVar4 == 0) {
                            _donone("floppycore.c:ReadBlock:calling Readsector from cache ");

                            // Read sector from cache
                            sVar2 = _ReadSectorFromCacheMemory(param_1);
                            iVar4 = (int)sVar2;

                            if (iVar4 == 0) {
                                // Success - update bytes read and block number
                                *param_2 = (int)*(short *)(param_1 + 0x54) + *param_2;
                                *(int *)(param_1 + 0x14) = *(int *)(param_1 + 0x14) + 1;
                                break;
                            }
                        }

                        // Error occurred - recalibrate and retry
                        _donone("Found error,recalibrating ");
                        _RecalDrive(param_1);
                        *(short *)(param_1 + 0x4a) = *(short *)(param_1 + 0x4a) + 1;
                        sVar1 = sVar1 - 1;
                    } while (sVar1 != 0);

                } while (iVar4 == 0);
            }
            else {
                // Block number out of range
                _donone("last block number more than MAX ");
                sVar1 = _RecordError(0xffffffb0);
                iVar4 = (int)sVar1;
            }

            // Power down drive (deferred, mode 6)
            _donone("core.c:Powerdowning the drive ");
            _PowerDriveDown(param_1, 6);
        }
    }

    _donone("core.c:returning from ReadBlocks ");
    return iVar4;
}


/*
 * _ReadDiskTrackToCache - Read entire track from disk into cache
 *
 * This function reads all sectors of a track from the diskette into the
 * track cache using DMA. It skips sectors that are already in cache
 * (marked as dirty).
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x1c: Current track
 *             offset 0x20: Target track
 *             offset 0x21: Head number (0 or 1)
 *             offset 0x22: Sector number
 *             offset 0x28: DMA buffer address (for read)
 *             offset 0x51: Sectors per track
 *             offset 0x60: Sector interleave table
 *             offset 0xa4: Dirty bit array (head 0)
 *             offset 0xac: Dirty bit array (head 1)
 *             offset 0xc8: Sector address/buffer table (head 0)
 *             offset 0x1f0: Sector address/buffer table (head 1)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Process:
 *   1. Get next address ID to verify track
 *   2. Check if we're on the correct track
 *   3. Prepare CPU cache for DMA operations
 *   4. For each sector in track:
 *      - Use interleave table for ordering
 *      - Check dirty bit to skip already-cached sectors
 *      - Set up DMA buffer address
 *      - Read sector via HAL
 *      - Retry up to 3 times on error
 *   5. Flush DMA data from CPU cache
 *
 * Dirty bit array:
 *   - 1 bit per sector (8 sectors per byte)
 *   - Bit set = sector is dirty (in cache)
 *   - Bit clear = sector needs to be read
 */
int _ReadDiskTrackToCache(int param_1)
{
    unsigned char bVar1;
    unsigned short uVar2;
    short sVar3;
    short sVar4;
    unsigned int uVar5;
    unsigned int uVar6;
    int iVar7;

    // Save sectors per track count
    bVar1 = *(unsigned char *)(param_1 + 0x51);

    // Save original track number
    uVar6 = *(unsigned int *)(param_1 + 0x20);

    _donone("core.c:ReadDiskTrackToCache:calling HALGetNextAddressID ");

    // Get next address mark to verify track
    sVar3 = _HALGetNextAddressID(param_1);
    iVar7 = (int)sVar3;

    if (iVar7 == 0) {
        // Check if we're on the correct track
        if (*(char *)(param_1 + 0x20) == *(char *)(param_1 + 0x1c)) {
            _donone("core.c:ReadDiskTrackToCache:calling PrepareCPUCacheForDMARead ");

            // Prepare CPU cache for DMA operations
            _PrepareCPUCacheForDMAWrite();
            _PrepareCPUCacheForDMARead();

            // Set track number
            *(unsigned int *)(param_1 + 0x20) = *(unsigned int *)(param_1 + 0x1c);

            sVar3 = 0;
            uVar2 = (unsigned short)bVar1;

            // Loop through all sectors in track
            while ((uVar2 != 0 && (iVar7 == 0))) {
                // Get sector number from interleave table (first time through)
                if (sVar3 == 0) {
                    *(unsigned char *)(param_1 + 0x22) =
                        *(unsigned char *)(param_1 + (unsigned int)*(unsigned char *)(param_1 + 0x22) + 0x60);
                }

                bVar1 = *(unsigned char *)(param_1 + 0x22);

                // Check dirty bit array to see if sector is already cached
                // Calculate: dirty_array[head * 8 + (sector / 8)] & (1 << (sector & 7))
                if (((unsigned int)*(unsigned char *)((unsigned int)*(unsigned char *)(param_1 + 0x21) * 8 +
                                                      param_1 + (unsigned int)(bVar1 >> 3) + 0xa4) &
                     1 << (bVar1 & 7)) == 0) {
                    // Sector not in cache - need to read it

                    // Calculate sector table offset: head * 0x128 + sector * 8
                    iVar7 = (unsigned int)*(unsigned char *)(param_1 + 0x21) * 0x128 +
                           param_1 + (unsigned int)bVar1 * 8;

                    // Get DMA buffer addresses from sector table
                    uVar5 = *(unsigned int *)(iVar7 + 0xcc);
                    *(unsigned int *)(param_1 + 0x28) = *(unsigned int *)(iVar7 + 200);
                    *(unsigned int *)(param_1 + 0x2c) = uVar5;

                    _donone("core.c:ReadDiskTrackToCache:calling HALReadSector ");

                    // Read sector from disk
                    sVar4 = _HALReadSector(param_1);
                    iVar7 = (int)sVar4;

                    _donone("core.c:ReadDiskTrackToCache:HALReadSector returns ");
                }

                if (iVar7 == 0) {
                    // Success - move to next sector
                    sVar3 = 0;
                    uVar2 = uVar2 - 1;
                }
                else {
                    // Error - retry up to 3 times
                    if (2 < sVar3) {
                        break;
                    }
                    sVar3 = sVar3 + 1;
                    iVar7 = 0;
                }
            }

            // Flush DMA data from CPU cache
            _FlushDMAedDataFromCPUCache();
        }
        else {
            // Seek error - not on correct track
            _donone("ReadDiskTrackToCache:seek error--wanttrack=%d,actual=%d ");
            sVar3 = _RecordError(0xffffffb0);
            iVar7 = (int)sVar3;
        }
    }

    // Restore original track number
    *(unsigned int *)(param_1 + 0x20) = uVar6;

    return iVar7;
}


/*
 * _ReadSectorFromCacheMemory - Read sector from cache memory
 *
 * This function reads a sector from the track cache. If the track is not
 * in cache, it reads the entire track from disk first.
 *
 * Parameters:
 *   param_1 - Drive structure pointer
 *             offset 0x10: Flags (bit 6 = verify mode)
 *             offset 0x21: Head number (0 or 1)
 *             offset 0x22: Sector number
 *             offset 0x24: Target buffer pointer (updated)
 *             offset 0x54: Sector size
 *             offset 0x5a: Format type (0=MFM, non-zero=GCR)
 *
 * Returns:
 *   int - 0 on success, error code on failure
 *
 * Process:
 *   1. Test if track is in cache
 *   2. If not, read entire track to cache
 *   3. Mark read data present for this head
 *   4. For GCR format: denibblize sector data
 *   5. Copy data from cache to target buffer
 *      OR compare data if verify flag is set
 *
 * Verify mode (bit 6 of offset 0x10):
 *   - Instead of copying, compares cache with target
 *   - Returns error 0xffffffbc (-68) if mismatch
 *
 * Error codes:
 *   0xffffffbc (-68) - Verify failed (data mismatch)
 */
int _ReadSectorFromCacheMemory(int param_1)
{
    int iVar1;
    short sVar2;
    int iVar3;
    int iVar4;
    int local_18;
    unsigned char auStack_14[4];

    // Check if track is in cache
    iVar1 = _TestTrackInCache();

    if (iVar1 == 0) {
        // Track not in cache - read from disk
        _donone("floppycore.c:ReadSectorFromTheCache:calling ReadDiskTrackToCache ");

        sVar2 = _ReadDiskTrackToCache(param_1);
        if (sVar2 != 0) {
            return (int)sVar2;
        }

        // Mark track as cached
        _AssignTrackInCache(param_1);
        (&_ReadDataPresent)[*(unsigned char *)(param_1 + 0x21)] = 1;
    }
    else if ((&_ReadDataPresent)[*(unsigned char *)(param_1 + 0x21)] == '\0') {
        // Track in cache but data not marked present - re-read
        sVar2 = _ReadDiskTrackToCache(param_1);
        if (sVar2 != 0) {
            return (int)sVar2;
        }

        _AssignTrackInCache(param_1);
        (&_ReadDataPresent)[*(unsigned char *)(param_1 + 0x21)] = 1;
    }

    iVar3 = 0;

    // Get sector buffer address from cache table
    iVar4 = *(int *)((unsigned int)*(unsigned char *)(param_1 + 0x21) * 0x128 + param_1 +
                    (unsigned int)*(unsigned char *)(param_1 + 0x22) * 8 + 200);
    iVar1 = iVar4;

    // For GCR format, denibblize the sector data
    if (*(char *)(param_1 + 0x5a) != '\0') {
        iVar1 = iVar4 + 0xd;
        sVar2 = _FPYDenibblizeGCRSector(param_1, iVar4, iVar1);
        iVar3 = (int)sVar2;
    }

    if (iVar3 == 0) {
        // Check if verify mode (bit 6 of flags)
        if ((*(unsigned short *)(param_1 + 0x10) & 0x40) == 0) {
            // Normal read mode - copy data from cache to target buffer
            _donone("floppycore.c:ReadSectorFromTheCache:copying the data srx=0x%x,tgt=0x%x size=%d ",
                   iVar1, *(unsigned int *)(param_1 + 0x24), (int)*(short *)(param_1 + 0x54));

            sVar2 = _MemListDescriptorDataCopyFromMemory(
                iVar1,
                *(unsigned int *)(param_1 + 0x24),
                (int)*(short *)(param_1 + 0x54));
            iVar3 = (int)sVar2;

            // Advance target buffer pointer
            *(int *)(param_1 + 0x24) = (int)*(short *)(param_1 + 0x54) + *(int *)(param_1 + 0x24);
        }
        else {
            // Verify mode - compare cache data with target buffer
            sVar2 = _MemListDescriptorDataCompareWithMemory(
                *(unsigned int *)(param_1 + 0x24),
                iVar1,
                (int)*(short *)(param_1 + 0x54),
                &local_18,
                auStack_14);
            iVar3 = (int)sVar2;

            // If comparison failed and error count is non-zero, record error
            if ((iVar3 != 0) && (local_18 != 0)) {
                sVar2 = _RecordError(0xffffffbc);
                iVar3 = (int)sVar2;
            }
        }
    }

    return iVar3;
}


/**
 * _RecalDrive - Recalibrate drive to track 0
 *
 * This function recalibrates the floppy drive by moving the head to track 0.
 * It first dumps the track cache, then calls the HAL recalibrate function,
 * and updates the drive structure with the current track position.
 *
 * @param param_1: Drive structure pointer
 * @return: IOReturn status code (0 on success, error code on failure)
 */
short _RecalDrive(int param_1)
{
    short sVar1;
    unsigned int uVar2;

    // Dump the track cache to ensure no dirty data is lost
    _DumpTrackCache(param_1);

    // Get the current density setting from drive structure (offset 0x34)
    uVar2 = *(unsigned int *)(param_1 + 0x34);

    // Set the sectors per track in drive structure (offset 0x1a)
    // This is retrieved from the sector/track map for the current density
    *(unsigned short *)(param_1 + 0x1a) = *(unsigned short *)(_fpySectorPerTrackTbl + uVar2 * 4);

    // Call HAL function to physically recalibrate the drive
    sVar1 = _HALRecalDrive(param_1);

    // Update current track to 0 in drive structure (offset 0x10)
    *(unsigned short *)(param_1 + 0x10) = 0;

    return sVar1;
}


/**
 * _RecordError - Record and return error code
 *
 * This is a simple passthrough function that records an error code
 * and returns it unchanged. It may be used for error tracking or
 * debugging purposes.
 *
 * @param param_1: Error code to record
 * @return: The same error code that was passed in
 */
unsigned int _RecordError(unsigned int param_1)
{
    return param_1;
}


/**
 * _ResetBitArray - Clear a bit array to all zeros
 *
 * This function resets a bit array by writing zeros to it in 4-byte chunks.
 * The bit array is used to track sector states (cached, dirty, etc.).
 *
 * @param param_1: Pointer to the bit array to reset
 * @param param_2: Size of the bit array in bytes
 * @return: void
 */
void _ResetBitArray(int param_1, unsigned int param_2)
{
    unsigned int uVar1;
    unsigned int *puVar2;
    unsigned int uVar3;

    // Calculate number of 4-byte words to clear
    uVar3 = param_2 >> 2;

    if (uVar3 != 0) {
        // Get pointer to start of bit array
        puVar2 = (unsigned int *)param_1;

        // Loop counter
        uVar1 = uVar3;

        // Clear the array in 4-byte chunks
        do {
            *puVar2 = 0;
            uVar1 = uVar1 - 1;
            puVar2 = puVar2 + 1;
        } while (uVar1 != 0);
    }

    return;
}


/**
 * _ResetBusyFlag - Reset the global busy flag with proper synchronization
 *
 * This function safely resets the global busy flag by using a spin lock
 * to ensure thread-safe access. The busy flag is used to prevent concurrent
 * access to the floppy hardware.
 *
 * @return: void
 */
void _ResetBusyFlag(void)
{
    // Acquire the spin lock for synchronization
    _simple_lock(&_slock);

    // Reset the busy flag to 0
    _busyflag = 0;

    // Call unlock/signal function to wake any waiting threads
    FUN_00005df0();

    return;
}


/**
 * _ResetDBDMA - Reset a DBDMA channel descriptor
 *
 * This function resets a DBDMA (Descriptor-Based DMA) channel by
 * setting the control register and clearing various fields in the
 * descriptor structure.
 *
 * @param param_1: Pointer to DBDMA channel descriptor structure
 * @return: void
 */
void _ResetDBDMA(int param_1)
{
    // Set DBDMA control register to 0x200 (bit 9 set - likely RESET bit)
    // Offset 0x08 is the control/status register
    *(unsigned int *)(param_1 + 8) = 0x200;

    // Clear result field (offset 0x0c)
    *(unsigned int *)(param_1 + 0xc) = 0;

    // Clear command pointer high word (offset 0x04)
    *(unsigned int *)(param_1 + 4) = 0;

    // Clear command pointer low word (offset 0x00)
    *(unsigned int *)param_1 = 0;

    return;
}


/**
 * _ResetDMAChannel - Reset and prepare the global floppy DMA channel
 *
 * This function resets the global floppy DBDMA channel and then
 * prepares it for use by calling the prep function.
 *
 * @return: void
 */
void _ResetDMAChannel(void)
{
    // Reset the global floppy DMA channel descriptor
    _ResetDBDMA(_GRCFloppyDMAChannel);

    // Prepare the DMA channel for operation
    _PrepDBDMA(_GRCFloppyDMAChannel);

    return;
}


/**
 * _ScanForDisketteChange - Scan for diskette insertion/removal events
 *
 * This function is called periodically to check for diskette media changes.
 * It scans all configured drives and detects insertion or removal events,
 * posting appropriate notifications.
 *
 * @return: void
 */
void _ScanForDisketteChange(void)
{
    int iVar1;
    undefined4 uVar2;
    int iVar3;
    int local_28[5];

    // Loop through drive numbers (starting at 1)
    iVar3 = 1;
    do {
        // Check if this is a valid drive number and get drive structure
        iVar1 = _CheckDriveNumber(iVar3, local_28);

        // If valid drive and media scanning is enabled (offset 0x3d)
        if ((iVar1 == 0) && (*(char *)(local_28[0] + 0x3d) == '\x01')) {
            // Enter critical section for hardware access
            uVar2 = _EnterHardwareLockSection();

            // Check if deferred power down timer is active
            if (DAT_0000fb8a < 1) {
                // No deferred power down - check for media changes

                if (*(char *)(local_28[0] + 0x3c) == '\0') {
                    // No diskette was present - check if one was inserted
                    iVar1 = _HALDiskettePresence();

                    if (iVar1 == 1) {
                        // Diskette detected!
                        *(undefined *)(local_28[0] + 0x3c) = 1;

                        // Get media type (GCR/MFM, density, etc.)
                        _HALGetMediaType(local_28[0]);

                        // Power up the drive
                        _PowerDriveUp(local_28[0]);

                        // Post diskette insertion event (event type 1)
                        iVar1 = _PostDisketteEvent(1, iVar3);

                        // If event posting failed, mark as no diskette
                        if (iVar1 != 0) {
                            *(undefined *)(local_28[0] + 0x3c) = 0;
                        }
                    }
                }
                else {
                    // Diskette was present - check if it's still there
                    iVar1 = _HALDiskettePresence(local_28[0]);

                    if (iVar1 == 0) {
                        // Diskette was removed
                        _PostDisketteEvent(0, iVar3);

                        // Clear diskette present flag (offset 0x3c)
                        *(undefined *)(local_28[0] + 0x3c) = 0;

                        // Clear read data present flags (offsets 0x48, 0x49)
                        *(undefined *)(local_28[0] + 0x48) = 0;
                        *(undefined *)(local_28[0] + 0x49) = 0;

                        // Clear current format (offset 0x38)
                        *(undefined4 *)(local_28[0] + 0x38) = 0;
                    }
                    else if (*(char *)(local_28[0] + 0x3c) == -1) {
                        // Diskette marked as invalid - treat as ejected
                        *(undefined *)(local_28[0] + 0x3c) = 0;
                        _PostDisketteEvent(0, iVar3);
                    }
                }
            }
            else {
                // Deferred power down timer is active - decrement it
                DAT_0000fb8a = DAT_0000fb8a + -1;

                // If timer expired, power down the drive
                if (DAT_0000fb8a < 1) {
                    _PowerDriveDown(DAT_0000fb8c, 0);
                }
            }

            // Exit critical section
            _ExitHardwareLockSection(uVar2);
        }

        // Move to next drive
        iVar3 = (int)(short)((short)iVar3 + 1);
    } while (iVar3 < 2);

    return;
}


/**
 * _SeekDrive - Seek drive to target track
 *
 * This function seeks the floppy drive to a target track. If the current
 * track is unknown (-1), it first recalibrates the drive. After seeking,
 * it updates the cache addresses for the new track.
 *
 * @param param_1: Drive structure pointer
 * @return: IOReturn status code (0 on success, error code on failure)
 */
int _SeekDrive(int param_1)
{
    short sVar1;
    int iVar2;

    iVar2 = 0;

    // Debug output showing target track (offset 0x1c is current track)
    _donone("core.c:SeekDrive:track=%d ", (int)*(char *)(param_1 + 0x1c));

    // Check if current track is unknown (-1)
    if (*(char *)(param_1 + 0x1c) == -1) {
        // Recalibrate drive to establish known position
        sVar1 = _RecalDrive(param_1);
        iVar2 = (int)sVar1;
    }

    // If no error and current track != target track (offset 0x20)
    if ((iVar2 == 0) && (*(char *)(param_1 + 0x1c) != *(char *)(param_1 + 0x20))) {
        // Set sectors per track for the target track
        _SetSectorsPerTrack(param_1);

        _donone("SeekDrive:calling HALSeekDrive ");

        // Call HAL to physically seek to target track
        sVar1 = _HALSeekDrive(param_1);
        iVar2 = (int)sVar1;

        if (iVar2 == 0) {
            // Success - update current track to match target
            *(undefined *)(param_1 + 0x1c) = *(undefined *)(param_1 + 0x20);

            // Update cache addresses for new track
            _SetCacheAddresses(param_1);
        }
        else {
            // Seek failed - mark current track as unknown
            *(undefined *)(param_1 + 0x1c) = 0xff;
        }
    }

    return iVar2;
}


/**
 * _SetBusyFlag - Atomically set the busy flag
 *
 * This function attempts to atomically set the busy flag. It uses
 * load-link/store-conditional operations to ensure thread safety.
 * Returns true if the flag was successfully acquired (was 0), false
 * if it was already set.
 *
 * @return: true if busy flag was acquired, false if already busy
 */
bool _SetBusyFlag(void)
{
    bool bVar1;
    undefined4 *puVar2;
    int iVar3;

    puVar2 = _slock;

    // Loop using atomic operations until lock acquired
    do {
        // FUN_00005d80 is likely lwarx/stwcx (load-link/store-conditional)
        iVar3 = FUN_00005d80(0, puVar2);
    } while (iVar3 != 0);

    // Check if busy flag is clear
    bVar1 = _busyflag == 0;

    if (bVar1) {
        // Flag was clear - set it to mark as busy
        _busyflag = 1;
    }

    // Memory barrier to ensure ordering
    sync(0);

    // Release the spin lock
    *_slock = 0;

    return bVar1;
}


/**
 * _SetCacheAddresses - Set up DMA addresses for track cache
 *
 * This function computes and sets the DMA addresses for all sectors
 * in the track cache. It loops through both heads and all sectors,
 * calling the compute function for each sector.
 *
 * @param param_1: Drive structure pointer
 * @return: void
 */
void _SetCacheAddresses(int param_1)
{
    int iVar1;
    int iVar2;

    // Loop through both heads (0 and 1)
    iVar1 = 0;
    do {
        iVar2 = 0;

        // Check if there are sectors on this track (offset 0x51 = sectors per track)
        if (*(char *)(param_1 + 0x51) != '\0') {
            do {
                // Compute DMA address for this sector
                // Parameters:
                //   param_1: drive structure
                //   iVar1: head number (0 or 1)
                //   sector number: (offset 0x58 base sector) + iVar2
                //   0: flags
                //   address pointer: base + head offset + sector offset
                //     base: param_1 + 200
                //     head offset: iVar1 * 0x128 (296 bytes per head)
                //     sector offset: ((iVar2 + base_sector) * 8) bytes per sector
                _FPYComputeCacheDMAAddress
                          (param_1, iVar1, (uint)*(byte *)(param_1 + 0x58) + iVar2, 0,
                           param_1 + iVar1 * 0x128 + 200 +
                           (iVar2 + (uint)*(byte *)(param_1 + 0x58)) * 8);

                // Move to next sector
                iVar2 = (int)(short)((short)iVar2 + 1);
            } while (iVar2 < (int)(uint)*(byte *)(param_1 + 0x51));
        }

        // Move to next head
        iVar1 = (int)(short)((short)iVar1 + 1);
    } while (iVar1 < 2);

    return;
}


/**
 * _SetDBDMAPhysicalAddress - Set up DBDMA descriptor chain
 *
 * This function creates a DBDMA descriptor chain for a DMA transfer.
 * It handles page boundary crossing by splitting the transfer into
 * multiple descriptors as needed. Each descriptor is limited to not
 * cross a page boundary.
 *
 * @param param_1: DBDMA structure pointer
 * @param param_2: Direction flag (0=read from device, non-0=write to device)
 * @param param_3: Virtual buffer address
 * @param param_4: Transfer size in bytes
 * @return: void
 */
void _SetDBDMAPhysicalAddress(int param_1, uint param_2, uint param_3, uint param_4)
{
    undefined4 uVar1;
    uint uVar2;
    uint uVar3;
    uint uVar4;
    uint *puVar5;
    uint uVar6;

    // Get pointer to DBDMA descriptor list (offset 0x14)
    puVar5 = *(uint **)(param_1 + 0x14);

    // Clear DBDMA control/status register (offset 4) - set to 200
    **(undefined4 **)(param_1 + 4) = 200;

    // Compute command flags based on direction
    // This complex expression extracts bit patterns for DMA command
    uVar4 = ((int)param_2 >> 0x1f) - ((int)param_2 >> 0x1f ^ param_2) >> 2 & 0x20000000;
    uVar3 = 0x10000000;

    if (param_2 == 0) {
        // Read from device (INPUT_MORE)
        uVar1 = 8;
    }
    else {
        // Write to device (OUTPUT_MORE)
        uVar3 = 0x30000000;
        uVar1 = 4;
    }

    // Store command type (offset 8)
    *(undefined4 *)(param_1 + 8) = uVar1;

    _donone("request = %d dmacounts=", param_4);

    // Build descriptor chain, splitting at page boundaries
    if (param_4 != 0) {
        do {
            // Calculate bytes remaining to next page boundary
            // _entry is the page size
            uVar6 = _entry - (param_3 - (param_3 / _entry) * _entry);

            // Limit transfer size to page boundary or remaining bytes
            uVar2 = param_4;
            if (uVar6 < param_4) {
                uVar2 = uVar6;
            }

            // Update remaining byte count
            param_4 = param_4 - uVar2;

            // If this is the last descriptor, set interrupt and branch flags
            if (param_4 == 0) {
                uVar4 = uVar3 | 0x300000;  // Add INT and BR flags
            }

            // Convert virtual address to physical
            uVar1 = FUN_00006888(param_3);

            // Build descriptor word 0: command and count (byte-swapped)
            *puVar5 = (uVar4 | uVar2) >> 0x18 |
                      (uVar4 | uVar2) >> 8 & 0xff00 |
                      (uVar2 & 0xff00) << 8 |
                      uVar2 << 0x18;

            // Build descriptor word 1: physical address (byte-swapped)
            uVar6 = FUN_00006888(param_3);
            puVar5[1] = uVar6 >> 0x18 |
                        uVar6 >> 8 & 0xff00 |
                        (uVar6 & 0xff00) << 8 |
                        uVar6 << 0x18;

            // Clear descriptor words 2 and 3
            puVar5[3] = 0;
            puVar5[2] = 0;

            _donone("v=0x%x,p=0x%x:%d ", param_3, uVar1, uVar2);

            // Advance to next chunk
            param_3 = param_3 + uVar2;
            puVar5 = puVar5 + 4;  // Move to next descriptor (16 bytes)

        } while (param_4 != 0);
    }

    // Add STOP command at end of chain (0x70 = DBDMA_STOP)
    *puVar5 = 0x70;
    puVar5[1] = 0;
    puVar5[3] = 0;
    puVar5[2] = 0;

    // Get current address space ID
    uVar1 = _CurrentAddressSpaceID();

    // Flush processor cache for descriptor chain
    _FlushProcessorCache
              (uVar1, *(int *)(param_1 + 0x14),
               (int)puVar5 + (0x10 - *(int *)(param_1 + 0x14)));

    _donone("\n");

    return;
}


/**
 * _SetDisketteFormat - Set diskette format parameters
 *
 * This function sets the diskette format parameters in the drive structure
 * by copying values from the global format table. It then updates derived
 * parameters like sector address block size and sectors per track.
 *
 * @param param_1: Drive structure pointer
 * @param param_2: Format index (0-5) into format table
 * @return: void
 */
void _SetDisketteFormat(int param_1, short param_2)
{
    int iVar1;
    undefined4 uVar2;
    undefined4 uVar3;
    undefined4 uVar4;
    int iVar5;

    iVar5 = (int)param_2;

    _donone("core.c:SetDisketteFormat: ");

    // Calculate offset into format table (each entry is 0x14 = 20 bytes)
    iVar1 = iVar5 * 0x14;

    // Load format parameters from global table
    uVar3 = *(undefined4 *)(&DAT_0000fb94 + iVar1);
    uVar4 = *(undefined4 *)(&DAT_0000fb98 + iVar5 * 10);
    uVar2 = *(undefined4 *)(&DAT_0000fb9c + iVar1);

    // Copy format parameters to drive structure:
    // Offset 0x4c: First parameter (sectors/tracks/etc.)
    *(undefined4 *)(param_1 + 0x4c) = (&DAT_0000fb90)[iVar5 * 5];

    // Offset 0x50: Second parameter
    *(undefined4 *)(param_1 + 0x50) = uVar3;

    // Offset 0x54: Third parameter (sector size)
    *(undefined4 *)(param_1 + 0x54) = uVar4;

    // Offset 0x58: Fourth parameter (track size/base sector)
    *(undefined4 *)(param_1 + 0x58) = uVar2;

    // Offset 0x5c: Fifth parameter (type/heads/MFM parameters)
    *(undefined4 *)(param_1 + 0x5c) = *(undefined4 *)(&DAT_0000fba0 + iVar1);

    _donone("core.c:SetDisketteFormat:Calling SetSectorAddressBlocksize ");

    // Calculate and set sector address block size encoding
    _SetSectorAddressBlocksize(param_1);

    // Copy current track to target track (offset 0x20)
    *(undefined *)(param_1 + 0x20) = *(undefined *)(param_1 + 0x1c);

    _donone("Core.c:SetDisketteFormat:Calling SetSectorPerTrack ");

    // Set sectors per track based on format and current track
    _SetSectorsPerTrack(param_1);

    _donone("core.c:SetDisketteFormat:Calling HALSetFormatMode ");

    // Tell HAL to set the hardware format mode
    _HALSetFormatMode(param_1);

    return;
}


/**
 * _SetOSEvent - Set OS event flags and signal waiters
 *
 * This function sets event flags using a bitwise OR operation and
 * then signals any threads waiting on the event.
 *
 * @param param_1: Pointer to event flags word
 * @param param_2: Event flags to set (OR mask)
 * @return: Always returns 0
 */
undefined4 _SetOSEvent(uint *param_1, uint param_2)
{
    int iVar1;

    // Set the event flags using OR operation
    *param_1 = param_2 | *param_1;

    // Call wait/signal function (likely IOConditionLock or similar)
    // FUN_00006df0 is probably a timed wait function
    iVar1 = FUN_00006df0(0, param_1);

    if (iVar1 == 0) {
        // Timeout occurred
        _donone("TIMEOUT 0x%x ", param_2);
    }
    else {
        // Success - call unlock/signal function
        // FUN_00006de0 is probably an unlock/broadcast function
        FUN_00006de0(param_1);
    }

    return 0;
}


/**
 * _SetSectorAddressBlocksize - Calculate sector address block size
 *
 * This function calculates the block size encoding for sector addresses.
 * For MFM format, it computes log2 of the sector size. For GCR format,
 * it combines format-specific fields.
 *
 * @param param_1: Drive structure pointer
 * @return: void
 */
void _SetSectorAddressBlocksize(int param_1)
{
    uint uVar1;
    int iVar2;

    // Check format type (offset 0x5a: 0=MFM, non-zero=GCR)
    if (*(char *)(param_1 + 0x5a) == '\0') {
        // MFM format - calculate log2 of sector size
        uVar1 = (uint)*(short *)(param_1 + 0x54);

        // Initialize block size to 0
        *(undefined *)(param_1 + 0x23) = 0;

        // Calculate log2: divide by 256 and add 1 if there's a remainder
        for (iVar2 = ((int)uVar1 >> 8) + (uint)((int)uVar1 < 0 && (uVar1 & 0xff) != 0);
            iVar2 != 0;
            iVar2 = iVar2 >> 1) {
            // Increment for each bit shift (counting bits)
            *(char *)(param_1 + 0x23) = *(char *)(param_1 + 0x23) + '\x01';
        }
    }
    else {
        // GCR format - combine format fields
        // Offset 0x23: (bits 0-3 from 0x59) | (bits 4-7 from low nibble of 0x50)
        *(byte *)(param_1 + 0x23) =
             *(byte *)(param_1 + 0x59) | (byte)((*(byte *)(param_1 + 0x50) & 0xf) << 4);
    }

    return;
}


/**
 * _SetSectorsPerTrack - Set sectors per track for current position
 *
 * This function sets the number of sectors per track based on the
 * diskette format. For MFM, this is constant. For GCR, it varies
 * by zone (track range), with 5 zones having 12/11/10/9/8 sectors.
 *
 * @param param_1: Drive structure pointer
 * @return: void
 */
void _SetSectorsPerTrack(int param_1)
{
    char cVar1;

    // Check format type (offset 0x5a: 0=MFM, non-zero=GCR)
    if (*(char *)(param_1 + 0x5a) == '\0') {
        // MFM format - use fixed value from format parameters
        cVar1 = *(char *)(param_1 + 0x51);
    }
    else {
        // GCR format - calculate based on track number (zone-based)
        // Target track is at offset 0x20
        // Zones: 0-15=12, 16-31=11, 32-47=10, 48-63=9, 64-79=8 sectors
        // Formula: 12 - (track >> 4) = 12 - zone_number
        cVar1 = '\f' - (*(char *)(param_1 + 0x20) >> 4);
    }

    // Store sectors per track (offset 0x51)
    *(char *)(param_1 + 0x51) = cVar1;

    // Build the sector interleave table for this track
    _BuildTrackInterleaveTable(param_1, *(undefined *)(param_1 + 0x51));

    return;
}


/**
 * _SleepUntilReady - Wait for SWIM III controller to become ready
 *
 * This function polls the SWIM III controller status until it reports
 * ready, or times out after ~1000 attempts. It uses timed sleeps
 * between polls to avoid busy-waiting.
 *
 * @return: 0 on success, 0xffffffff on timeout
 */
undefined4 _SleepUntilReady(void)
{
    short sVar1;
    int iVar2;
    undefined4 uVar3;

    uVar3 = 0;

    // Initial sleep
    _FloppyTimedSleep();

    // Retry up to 1000 times
    sVar1 = 999;
    do {
        // Check SWIM III signal 0xfe (ready status)
        iVar2 = _SwimIIISenseSignal(0xfe);

        // If signal is 0, controller is ready
        if (iVar2 == 0) break;

        // Sleep for 1 tick before retry
        _FloppyTimedSleep(1);

        sVar1 = sVar1 + -1;
    } while (sVar1 != -1);

    // Check if we timed out
    if (sVar1 == 0) {
        // Timeout - record error
        uVar3 = _RecordError(0xffffffff);
    }

    return uVar3;
}


/**
 * _StartDBDMA - Start DBDMA channel operation
 *
 * This function starts a DBDMA channel by setting the RUN bit in the
 * control/status register. The bit position depends on whether the
 * channel is configured for input or output mode.
 *
 * @param param_1: DBDMA channel descriptor pointer
 * @return: void
 */
void _StartDBDMA(int param_1)
{
    uint uVar1;

    // Get current control/status register value (offset 8)
    uVar1 = *(uint *)(param_1 + 8);

    // Check bit 4 to determine mode (0=OUTPUT, 1=INPUT)
    if ((uVar1 & 4) == 0) {
        // OUTPUT mode - set bit 2 (RUN bit for output)
        uVar1 = uVar1 | 2;
    }
    else {
        // INPUT mode - set bit 1 (RUN bit for input)
        uVar1 = uVar1 | 1;
    }

    // Write modified control register back
    *(uint *)(param_1 + 8) = uVar1;

    // Write 0x800080 to register at offset 4
    // This likely sets channel active and priority bits
    **(undefined4 **)(param_1 + 4) = 0x800080;

    return;
}


/**
 * _StartDMAChannel - Start DMA transfer with full setup
 *
 * This is a high-level function that performs a complete DMA transfer.
 * It sets up the DBDMA descriptors, configures the SWIM III controller
 * for the appropriate mode, starts the transfer, waits for completion,
 * and cleans up.
 *
 * @param param_1: Buffer address for DMA transfer
 * @param param_2: Transfer size in bytes
 * @param param_3: Direction (1=read from device, 0=write to device)
 * @return: void
 */
void _StartDMAChannel(undefined4 param_1, int param_2, short param_3)
{
    undefined4 uVar1;

    // Reset and prepare the DMA channel
    _ResetDMAChannel();

    // Check transfer direction
    if (param_3 == 1) {
        // READ from device (device -> memory)
        // Set up DBDMA descriptors for input (direction=1)
        _SetDBDMAPhysicalAddress(_GRCFloppyDMAChannel, 1, param_1, param_2);

        // Configure SWIM III controller for read mode
        _SwimIIISetReadMode();
    }
    else {
        // WRITE to device (memory -> device)
        // Set up DBDMA descriptors for output (direction=0)
        _SetDBDMAPhysicalAddress(_GRCFloppyDMAChannel, 0, param_1, param_2);

        // If transfer size is 0x8000 (32KB), set format mode
        if (param_2 == 0x8000) {
            _SwimIIISetFormatMode();
        }

        // Configure SWIM III controller for write mode
        _SwimIIISetWriteMode();
    }

    // Clear any pending DMA complete events (event flag 8)
    _CancelOSEvent(_driveOSEventIDptr, 8);

    // Start the DBDMA channel
    _StartDBDMA(_GRCFloppyDMAChannel);

    // Wait for DMA completion event (timeout=1000ms, wait_mask=8, clear_mask=8)
    uVar1 = _WaitForEvent(1000, 8, 8);

    // Stop the DMA channel
    _StopDMAChannel();

    // Record the result (error code or success)
    _RecordError(uVar1);

    return;
}


/**
 * _StopDBDMA - Stop DBDMA channel operation
 *
 * This function stops a DBDMA channel by clearing the RUN bit in the
 * control/status register. The bit position depends on whether the
 * channel is configured for input or output mode.
 *
 * @param param_1: DBDMA channel descriptor pointer
 * @return: void
 */
void _StopDBDMA(int param_1)
{
    uint uVar1;

    // Get current control/status register value (offset 8)
    uVar1 = *(uint *)(param_1 + 8);

    // Check bit 4 to determine mode (0=OUTPUT, 1=INPUT)
    if ((uVar1 & 4) == 0) {
        // OUTPUT mode - clear bit 2 (RUN bit for output)
        uVar1 = uVar1 & 0xfffffffd;
    }
    else {
        // INPUT mode - clear bit 1 (RUN bit for input)
        uVar1 = uVar1 & 0xfffffffe;
    }

    // Write modified control register back
    *(uint *)(param_1 + 8) = uVar1;

    // Write 200 to register at offset 4 (reset/stop state)
    **(undefined4 **)(param_1 + 4) = 200;

    return;
}


/**
 * _StopDMAChannel - Stop the global floppy DMA channel
 *
 * This is a simple wrapper function that stops the global floppy
 * DBDMA channel.
 *
 * @return: Always returns 0
 */
undefined4 _StopDMAChannel(void)
{
    // Stop the global floppy DMA channel
    _StopDBDMA(_GRCFloppyDMAChannel);

    return 0;
}


/**
 * _SwimIIIAddrSignal - Send address signal to SWIM III controller
 *
 * This function sends an address/command signal to the SWIM III controller
 * by manipulating the hardware registers. It uses bit 3 of the parameter
 * to select between two different register addresses.
 *
 * @param param_1: Address/signal byte to send (bit 3 selects register)
 * @return: void
 */
void _SwimIIIAddrSignal(byte param_1)
{
    undefined *puVar1;

    // Write 0xf3 to SWIM III control register
    *DAT_0000fc2c = 0xf3;
    _SynchronizeIO();

    // Select register based on bit 3 of parameter
    puVar1 = DAT_0000fc34;
    if ((param_1 & 8) != 0) {
        // Bit 3 set - use alternate register
        puVar1 = DAT_0000fc38;
    }

    // Write 0x20 to selected register
    *puVar1 = 0x20;
    _SynchronizeIO();

    // Write address signal with bit 3 cleared
    *DAT_0000fc2c = param_1 & 0xf7;
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIIDisableRWMode - Disable SWIM III read/write mode
 *
 * This function disables the read/write mode in the SWIM III controller
 * by writing a command to the hardware register.
 *
 * @return: void
 */
void _SwimIIIDisableRWMode(void)
{
    // Write 0x18 to SWIM III register to disable RW mode
    *DAT_0000fc34 = 0x18;
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIIDiskSelect - Select disk drive
 *
 * This function selects which physical disk drive to use. The selection
 * is based on the drive select flag in the drive structure (offset 0x46).
 * It configures the SWIM III controller to route signals to the appropriate
 * drive.
 *
 * @param param_1: Drive structure pointer
 * @return: void
 */
void _SwimIIIDiskSelect(int param_1)
{
    undefined uVar1;

    // Check drive select flag at offset 0x46
    if (*(char *)(param_1 + 0x46) == '\0') {
        // Drive 0 selected
        *DAT_0000fc34 = 4;
        _SynchronizeIO();
        uVar1 = 2;
    }
    else {
        // Drive 1 selected
        *DAT_0000fc34 = 2;
        _SynchronizeIO();
        uVar1 = 4;
    }

    // Write complementary value to second register
    *DAT_0000fc38 = uVar1;
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIIHeadSelect - Select disk head (side)
 *
 * This function selects which head (side) of the diskette to use.
 * Side 0 is typically the top of the disk, side 1 is the bottom.
 * It delays briefly to allow head settling, then sends the appropriate
 * signal to the SWIM III controller.
 *
 * @param param_1: Head number (0 or 1)
 * @return: void
 */
void _SwimIIIHeadSelect(short param_1)
{
    undefined4 uVar1;

    // Delay 500 microseconds for head settling
    FUN_0000af58(500);

    // Select signal based on head number
    uVar1 = 0xfc;
    if (param_1 == 0) {
        // Head 0 (side 0)
        uVar1 = 0xf4;
    }

    // Send head select signal to SWIM III
    _SwimIIISenseSignal(uVar1);

    return;
}


/**
 * _SwimIIISenseSignal - Read signal status from SWIM III controller
 *
 * This function reads a status signal from the SWIM III controller.
 * It sends an address signal to select which status to read, then
 * reads and extracts bit 3 of the result.
 *
 * @param param_1: Signal address to read (e.g., 0xfe for ready status)
 * @return: Status bit value (0 or 1)
 */
byte _SwimIIISenseSignal(byte param_1)
{
    byte bVar1;

    // Send address signal to select status register
    _SwimIIIAddrSignal(param_1);

    // Read status from SWIM III data register 2
    bVar1 = *DAT_0000fc38;
    _SynchronizeIO();

    // Extract and return bit 3
    return bVar1 >> 3 & 1;
}


/**
 * _SwimIIISetFormatMode - Set SWIM III to format mode
 *
 * This function configures the SWIM III controller for disk formatting
 * operations. Format mode is used when writing track format data.
 *
 * @return: void
 */
void _SwimIIISetFormatMode(void)
{
    _SynchronizeIO();

    // Write 8 to data register 1 to set format mode
    *DAT_0000fc34 = 8;
    _SynchronizeIO();

    // Write 0x40 to data register 2
    *DAT_0000fc38 = 0x40;
    _SynchronizeIO();
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIISetReadMode - Set SWIM III to read mode
 *
 * This function configures the SWIM III controller for reading data
 * from the diskette. It first disables any previous mode, then sets
 * read mode.
 *
 * @return: void
 */
void _SwimIIISetReadMode(void)
{
    // Disable current read/write mode
    _SwimIIIDisableRWMode();
    _SynchronizeIO();

    // Disable again for safety
    _SwimIIIDisableRWMode();

    // Write 0x10 to data register 1 to enable read mode
    *DAT_0000fc34 = 0x10;
    _SynchronizeIO();
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIISetSignal - Set signal on SWIM III controller
 *
 * This function sets a signal on the SWIM III controller by sending
 * an address signal, setting bit 3, waiting briefly, then clearing bit 3.
 * This creates a pulse on the signal line.
 *
 * @param param_1: Signal address to pulse
 * @return: void
 */
void _SwimIIISetSignal(byte param_1)
{
    // Send address signal to select signal line
    _SwimIIIAddrSignal(param_1);

    // Set bit 3 in control register (pulse high)
    *DAT_0000fc2c = *DAT_0000fc2c | 8;
    _SynchronizeIO();

    // Brief delay (1 unit)
    _SwimIIISmallWait(1);

    // Clear bit 3 in control register (pulse low)
    *DAT_0000fc2c = *DAT_0000fc2c & 0xf7;
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIISetWriteMode - Set SWIM III to write mode
 *
 * This function configures the SWIM III controller for writing data
 * to the diskette. It first disables any previous mode, then sets
 * write mode.
 *
 * @return: void
 */
void _SwimIIISetWriteMode(void)
{
    // Disable current read/write mode
    _SwimIIIDisableRWMode();
    _SynchronizeIO();

    // Disable again for safety
    _SwimIIIDisableRWMode();

    // Write 0x10 to data register 2 to enable write mode
    *DAT_0000fc38 = 0x10;
    _SynchronizeIO();
    _SynchronizeIO();

    return;
}


/**
 * _SwimIIISmallWait - Small delay using SWIM III timer
 *
 * This function implements a small delay by programming the SWIM III
 * internal timer and polling until it expires. The delay is proportional
 * to the parameter value.
 *
 * @param param_1: Wait duration (timer count value)
 * @return: void
 */
void _SwimIIISmallWait(char param_1)
{
    char cVar1;

    // Write wait count + 1 to SWIM III timer register
    *DAT_0000fc20 = param_1 + '\x01';
    _SynchronizeIO();

    // Poll timer register until it counts down to 0
    cVar1 = *DAT_0000fc20;
    while (cVar1 != '\0') {
        _SynchronizeIO();
        cVar1 = *DAT_0000fc20;
    }

    return;
}


/**
 * _SwimIIIStepDrive - Step drive head in or out
 *
 * This function moves the drive head by the specified number of tracks.
 * Positive values step outward (toward higher track numbers), negative
 * values step inward (toward track 0). It uses the SWIM III step control
 * and waits for the step operation to complete.
 *
 * @param param_1: Number of tracks to step (negative = inward, positive = outward)
 * @return: 0 on success, -75 (0xffffffb5) on timeout
 */
int _SwimIIIStepDrive(short param_1)
{
    int iVar1;

    iVar1 = 0;

    // Check if there are any steps to perform
    if (param_1 != 0) {
        if (param_1 < 0) {
            // Step inward (toward track 0) - signal 0xf4
            _SwimIIISetSignal(0xf4);
            param_1 = -param_1;  // Make positive for step count
        }
        else {
            // Step outward (away from track 0) - signal 0xf0
            _SwimIIISetSignal(0xf0);
        }

        // Brief delay before starting step sequence
        _SwimIIISmallWait(1);

        // Clear any pending step complete events (event flag 2)
        _CancelOSEvent(_driveOSEventIDptr, 2);

        // Send step address signal
        _SwimIIIAddrSignal(0xf1);

        // Write step count to SWIM III step register
        *DAT_0000fc40 = (char)param_1;
        _SynchronizeIO();

        // Wait for step complete event (wait_mask=0x80, clear_mask=2)
        // FUN_00002710 is likely a timeout calculation function
        iVar1 = _WaitForEvent(FUN_00002710, 0x80, 2);

        if (iVar1 != 0) {
            // Timeout occurred - return error code -75
            iVar1 = -0x4b;
        }
    }

    return iVar1;
}


/**
 * _SwimIIITimeOut - Handle timeout with sleep
 *
 * This function manages a timeout counter. If the counter reaches zero,
 * it returns timeout status. Otherwise, it decrements the counter by 5
 * (or to zero if less than 5 remains) and sleeps for 5 milliseconds.
 *
 * @param param_1: Pointer to timeout counter (in milliseconds)
 * @return: 1 if timed out, 0 if still waiting
 */
undefined4 _SwimIIITimeOut(uint *param_1)
{
    uint uVar1;
    undefined4 uVar2;

    // Check if timeout counter has reached zero
    if (*param_1 == 0) {
        // Timeout occurred
        uVar2 = 1;
    }
    else {
        // Still time remaining
        if (*param_1 < 6) {
            // Less than 6ms remaining - sleep for remaining time
            _FloppyTimedSleep(5);
            uVar1 = 0;
        }
        else {
            // More than 5ms remaining - sleep for 5ms and decrement
            _FloppyTimedSleep(5);
            uVar1 = *param_1 - 5;
        }

        // Update timeout counter
        *param_1 = uVar1;

        // Not timed out yet
        uVar2 = 0;
    }

    return uVar2;
}


/**
 * _SynchronizeIO - Enforce I/O ordering
 *
 * This function ensures that all previous I/O operations complete before
 * any subsequent operations begin. On PowerPC, this is typically implemented
 * using the 'eieio' instruction (Enforce In-order Execution of I/O).
 *
 * @return: void
 */
void _SynchronizeIO(void)
{
    // Call platform-specific I/O ordering enforcement
    enforceInOrderExecutionIO();

    return;
}


/**
 * _TestBitArray - Test if any bits are set in array
 *
 * This function tests whether any bits are set in a bit array by
 * OR-ing together all words in the array. It returns true if any
 * bits are set, false if all bits are zero.
 *
 * @param param_1: Pointer to bit array
 * @param param_2: Size of bit array in bytes
 * @return: true if any bits are set, false if all zeros
 */
bool _TestBitArray(int param_1, uint param_2)
{
    uint uVar1;
    uint uVar2;

    // Accumulator for OR operation
    uVar2 = 0;

    // Byte offset into array
    uVar1 = 0;

    // Loop through array in 4-byte chunks
    if (param_2 != 0) {
        do {
            // OR this word into accumulator
            uVar2 = uVar2 | *(uint *)(param_1 + uVar1);

            // Move to next word
            uVar1 = (uint)(short)((short)uVar1 + 4);
        } while (uVar1 < param_2);
    }

    // Return true if any bits were set
    return uVar2 != 0;
}


/**
 * _TestTrackInCache - Test if a track is cached
 *
 * This function checks whether a specific track is currently cached
 * by comparing the cached drive and track information with the current
 * target.
 *
 * @param param_1: Drive structure pointer
 * @return: true if track is cached, false otherwise
 */
bool _TestTrackInCache(int param_1)
{
    bool bVar1;

    // Check if cached drive matches current drive
    // DAT_0000fb88 holds the cached drive number
    // Offset 0x46 is the current drive number
    if (DAT_0000fb88 == *(byte *)(param_1 + 0x46)) {
        // Drive matches - now check if track matches
        // Offset 0x21 is the head number
        // Offset 0xb4 is the base of cached track array (one byte per head)
        // Offset 0x20 is the target track number
        bVar1 = *(char *)(param_1 + (uint)*(byte *)(param_1 + 0x21) + 0xb4) ==
                *(char *)(param_1 + 0x20);
    }
    else {
        // Different drive - not cached
        bVar1 = false;
    }

    return bVar1;
}


/**
 * _WaitForEvent - Wait for hardware event with error handling
 *
 * This function waits for a hardware event from the SWIM III controller.
 * It configures the interrupt mask, waits for the event, and processes
 * any errors that occur. Various error codes are returned based on the
 * type of failure.
 *
 * @param param_1: Timeout value in milliseconds
 * @param param_2: Event mask (which events to enable)
 * @param param_3: Event wait mask (which events to wait for)
 * @return: 0 on success, error code on failure
 */
undefined4 _WaitForEvent(undefined4 param_1, byte param_2, byte param_3)
{
    int iVar1;
    undefined4 uVar2;
    uint local_28[5];

    // Default return value: -66 (0xffffffbe) = timeout/general error
    uVar2 = 0xffffffbe;

    // Clear any pending errors
    _lastErrorsPending = 0;

    // Read current SWIM III interrupt status register
    local_28[0] = (uint)*DAT_0000fc3c;
    _SynchronizeIO();

    // Write event mask to SWIM III interrupt enable register
    *DAT_0000fc58 = param_3;
    _SynchronizeIO();

    // Enable interrupts with event mask (set bit 0 to enable)
    *DAT_0000fc38 = param_2 | 1;
    _SynchronizeIO();

    // Wait for OS event with specified timeout
    iVar1 = _WaitForOSEvent(_driveOSEventIDptr, (uint)param_3, param_1, local_28);

    if (iVar1 == 0) {
        // Timeout occurred - disable interrupts
        *DAT_0000fc34 = param_2;
        _SynchronizeIO();
    }
    else if (local_28[0] != 0) {
        // Event or error occurred
        if (_lastErrorsPending == 0) {
            // No errors - check if desired event occurred
            if ((param_3 & local_28[0]) != 0) {
                // Desired event occurred - disable interrupts and return success
                *DAT_0000fc34 = param_2;
                _SynchronizeIO();
                uVar2 = 0;
            }
        }
        else {
            // Error occurred - disable interrupts
            *DAT_0000fc34 = param_2;
            _SynchronizeIO();

            // Decode error type
            if ((_lastErrorsPending & 0x40) == 0) {
                // Not a CRC error
                if ((_lastErrorsPending & 0x80) == 0) {
                    // Not an underrun error
                    // Check for other errors (bits 0 and 2)
                    uVar2 = 0xffffffbd;  // -67 = general error
                    if ((_lastErrorsPending & 5) != 0) {
                        uVar2 = 0xffffffb6;  // -74 = specific hardware error
                    }
                }
                else {
                    // Underrun error (bit 7 set)
                    uVar2 = 0xffffffb8;  // -72 = underrun
                }
            }
            else {
                // CRC error (bit 6 set)
                uVar2 = 0xffffffbb;  // -69 = CRC error
            }
        }
    }

    return uVar2;
}


/**
 * _WaitForOSEvent - Low-level OS event wait
 *
 * This function performs a low-level wait for OS events. If the desired
 * event flags are not already set, it waits with a timeout. It then
 * returns whether the event occurred.
 *
 * @param param_1: Pointer to event flags word
 * @param param_2: Event mask to wait for
 * @param param_3: Timeout in milliseconds (converted to units of 10ms)
 * @param param_4: Pointer to receive final event flags
 * @return: true if event occurred, false if timeout
 */
bool _WaitForOSEvent(uint *param_1, uint param_2, int param_3, uint *param_4)
{
    bool bVar1;

    // Check if desired event is already set
    if ((param_2 & *param_1) == 0) {
        // Event not yet set - need to wait

        // Call wait function with timeout converted to 10ms units
        // FUN_00006ee8 is likely IOLockLock or similar with timeout
        FUN_00006ee8(0, param_1, (param_3 + 9U) / 10);

        // Call function 0x16 on event (likely IOLockUnlock or status check)
        FUN_00006ed8(param_1, 0x16);

        // Return current event flags
        *param_4 = *param_1;

        // Check if desired event occurred during wait
        bVar1 = (param_2 & *param_1) != 0;
    }
    else {
        // Event already set - return immediately
        *param_4 = *param_1;
        bVar1 = true;
    }

    return bVar1;
}


/**
 * _WriteBlocks - Write blocks to diskette
 *
 * This is the main block write function. It validates the write request,
 * powers up the drive, and loops through each block writing them one at
 * a time with retry logic on errors.
 *
 * @param param_1: Drive structure pointer
 * @param param_2: Pointer to receive actual bytes written
 * @return: 0 on success, error code on failure
 */
int _WriteBlocks(int param_1, int *param_2)
{
    short sVar1;
    short sVar2;
    int iVar3;
    int iVar4;

    _donone("wrt:call checkdriveonline ");

    // Check if drive is online and has diskette
    sVar1 = _CheckDriveOnLine(param_1);
    iVar4 = (int)sVar1;

    if (iVar4 == 0) {
        _donone("wrt:call powerup drive ");

        // Power up the drive
        sVar1 = _PowerDriveUp(param_1);
        iVar4 = (int)sVar1;

        if (iVar4 == 0) {
            _donone("wrt:powerupdrive OK\n");

            // Calculate last block number to write
            // Offset 0x16: starting block number
            // Offset 0x1a: number of blocks
            iVar3 = (int)(short)(*(short *)(param_1 + 0x16) + *(short *)(param_1 + 0x1a) + -1);

            // Check if last block is within diskette capacity
            // Offset 0x4c: total blocks on diskette
            if (iVar3 < *(int *)(param_1 + 0x4c)) {
                // Valid block range
                iVar4 = 0;
                *param_2 = 0;

                // Loop through all blocks to write
                do {
                    // Check if we've gone beyond starting block
                    // Offset 0x14: current block number
                    if (iVar3 < *(int *)(param_1 + 0x14)) break;

                    // Retry up to 2 times on error
                    sVar1 = 2;
                    do {
                        _donone("wrtblks: call getsectoraddr ");

                        // Convert block number to track/head/sector
                        _GetSectorAddress(param_1, *(undefined2 *)(param_1 + 0x16));

                        _donone("core.c:write:calling FlushcacheAnd Seek\n");

                        // Flush cache if needed and seek to track
                        sVar2 = _FlushCacheAndSeek(param_1);
                        iVar4 = (int)sVar2;

                        if (iVar4 == 0) {
                            _donone("wrt:calling wrttocache ");

                            // Write sector to cache memory
                            sVar2 = _WriteSectorToCacheMemory(param_1);
                            iVar4 = (int)sVar2;

                            if (iVar4 == 0) {
                                // Success - update bytes written and advance block
                                *param_2 = (int)*(short *)(param_1 + 0x54) + *param_2;
                                *(int *)(param_1 + 0x14) = *(int *)(param_1 + 0x14) + 1;
                                break;
                            }
                        }

                        // Error occurred - recalibrate and retry
                        _donone("wrtblks:call RecalDrive ");
                        _RecalDrive(param_1);

                        // Increment error count (offset 0x4a)
                        *(short *)(param_1 + 0x4a) = *(short *)(param_1 + 0x4a) + 1;

                        sVar1 = sVar1 + -1;
                    } while (sVar1 != 0);

                    // Continue if no error
                } while (iVar4 == 0);
            }
            else {
                // Block range out of bounds
                _donone("core.c:Record error in write,firstblk=%d,lastblk=%d\n",
                        *(undefined4 *)(param_1 + 0x14), iVar3);
                sVar1 = _RecordError(0xffffffb0);  // Error -80
                iVar4 = (int)sVar1;
            }

            // Power down drive (deferred mode 6)
            _PowerDriveDown(param_1, 6);
        }
    }

    return iVar4;
}


/**
 * _WriteCacheToDiskTrack - Write cached track to disk
 *
 * This function writes all dirty sectors from the track cache to the
 * physical diskette. It checks which sectors are dirty and writes
 * only those, nibblizing GCR data if needed.
 *
 * @param param_1: Drive structure pointer
 * @return: 0 on success, error code on failure
 */
int _WriteCacheToDiskTrack(int param_1)
{
    byte bVar1;
    ushort uVar2;
    short sVar3;
    short sVar4;
    int iVar5;
    undefined4 uVar6;
    undefined4 uVar7;
    int iVar8;

    // Save sectors per track and target track
    bVar1 = *(byte *)(param_1 + 0x51);
    uVar7 = *(undefined4 *)(param_1 + 0x20);

    _donone("wrt:cachetodisktrack:call getaddr ");

    // Verify we're on the correct track
    sVar3 = _HALGetNextAddressID(param_1);
    iVar8 = (int)sVar3;

    if (iVar8 == 0) {
        // Check current track matches target track
        if (*(char *)(param_1 + 0x20) == *(char *)(param_1 + 0x1c)) {
            // Prepare CPU cache for DMA write operations
            _PrepareCPUCacheForDMAWrite();

            // Ensure target track matches current
            *(undefined4 *)(param_1 + 0x20) = *(undefined4 *)(param_1 + 0x1c);

            sVar3 = 0;
            uVar2 = (ushort)bVar1;

            if (uVar2 != 0) {
                do {
                    // On first sector, get sector from interleave table
                    if (sVar3 == 0) {
                        *(undefined *)(param_1 + 0x22) =
                             *(undefined *)(param_1 + (uint)*(byte *)(param_1 + 0x22) + 0x60);
                    }

                    bVar1 = *(byte *)(param_1 + 0x22);

                    // Check if sector is dirty (needs writing)
                    // Offset 0xa4: dirty bit array base
                    if (((uint)*(byte *)((uint)*(byte *)(param_1 + 0x21) * 8 + param_1 +
                                        (uint)(bVar1 >> 3) + 0xa4) & 1 << (bVar1 & 7)) == 0) {
LAB_00007eb8:
                        if (iVar8 != 0) goto LAB_00007efc;

                        // Clear dirty bit after successful write
                        iVar5 = (uint)*(byte *)(param_1 + 0x21) * 8 + param_1 +
                                (uint)(*(byte *)(param_1 + 0x22) >> 3);
                        *(byte *)(iVar5 + 0xa4) =
                             *(byte *)(iVar5 + 0xa4) & ~(byte)(1 << (*(byte *)(param_1 + 0x22) & 7));

                        sVar3 = 0;
                        uVar2 = uVar2 - 1;
                    }
                    else {
                        // Sector is dirty - need to write it
                        // Get cache addresses for this sector
                        iVar5 = (uint)*(byte *)(param_1 + 0x21) * 0x128 + param_1 + (uint)bVar1 * 8;
                        uVar6 = *(undefined4 *)(iVar5 + 0xcc);
                        *(undefined4 *)(param_1 + 0x28) = *(undefined4 *)(iVar5 + 200);
                        *(undefined4 *)(param_1 + 0x2c) = uVar6;

                        // If GCR format, nibblize sector data
                        if (*(char *)(param_1 + 0x5a) != '\0') {
                            _donone("GCR Read\n");
                            sVar4 = _FPYNibblizeGCRSector
                                          (param_1, *(int *)(param_1 + 0x28),
                                           *(int *)(param_1 + 0x28) + 0xd);
                            iVar8 = (int)sVar4;
                        }

                        if (iVar8 == 0) {
                            // Write sector via HAL with DMA
                            sVar4 = _HALWriteSector(param_1);
                            iVar8 = (int)sVar4;
                            goto LAB_00007eb8;
                        }

LAB_00007efc:
                        // Error occurred - retry up to 3 times
                        if (2 < sVar3) break;
                        sVar3 = sVar3 + 1;
                        iVar8 = 0;
                    }

                    if ((uVar2 == 0) || (iVar8 != 0)) break;
                } while (true);
            }

            // Flush DMA data from CPU cache
            _FlushDMAedDataFromCPUCache();
        }
        else {
            // Wrong track
            sVar3 = _RecordError(0xffffffb0);  // Error -80
            iVar8 = (int)sVar3;
        }
    }

    // Restore target track
    *(undefined4 *)(param_1 + 0x20) = uVar7;

    return iVar8;
}


/**
 * _WriteSectorToCacheMemory - Write sector to cache memory
 *
 * This function writes a sector from the I/O buffer into the track cache.
 * It marks the sector as dirty so it will be written to disk when the
 * cache is flushed.
 *
 * @param param_1: Drive structure pointer
 * @return: 0 on success, error code on failure
 */
int _WriteSectorToCacheMemory(int param_1)
{
    byte bVar1;
    int iVar2;
    short sVar3;
    int iVar4;

    // Test if this track is already cached
    iVar2 = _TestTrackInCache();

    if (iVar2 == 0) {
        // Track not cached - assign it to cache
        _AssignTrackInCache(param_1);

        // Clear read data present flag for this head
        // _ReadDataPresent is a 2-byte array (one per head)
        (&_ReadDataPresent)[*(byte *)(param_1 + 0x21)] = 0;
    }

    // Get sector number (offset 0x22)
    bVar1 = *(byte *)(param_1 + 0x22);

    // Get cache address for this sector
    // Base: param_1 + 200
    // Offset: head * 0x128 + sector * 8
    iVar2 = *(int *)((uint)*(byte *)(param_1 + 0x21) * 0x128 + param_1 + (uint)bVar1 * 8 + 200);

    // If GCR format, adjust pointer and set denibblize bit
    if (*(char *)(param_1 + 0x5a) != '\0') {
        // Skip 13-byte header in GCR data
        iVar2 = iVar2 + 0xd;

        // Set denibblize bit (offset 0x94) for this sector
        iVar4 = (uint)*(byte *)(param_1 + 0x21) * 8 + param_1 + (uint)(bVar1 >> 3);
        *(byte *)(iVar4 + 0x94) =
             *(byte *)(iVar4 + 0x94) | (byte)(1 << (bVar1 & 7));
    }

    // Copy data from buffer to cache memory
    // Offset 0x24: buffer pointer
    // Offset 0x54: sector size
    sVar3 = _MemListDescriptorDataCopyToMemory
                      (*(undefined4 *)(param_1 + 0x24), iVar2, (int)*(short *)(param_1 + 0x54));

    if (sVar3 == 0) {
        // Success - update buffer pointer
        *(int *)(param_1 + 0x24) = (int)*(short *)(param_1 + 0x54) + *(int *)(param_1 + 0x24);

        // Mark sector as dirty (offset 0xa4) so it will be written to disk
        iVar2 = (uint)*(byte *)(param_1 + 0x21) * 8 + param_1 +
                (uint)(*(byte *)(param_1 + 0x22) >> 3);
        *(byte *)(iVar2 + 0xa4) =
             *(byte *)(iVar2 + 0xa4) | (byte)(1 << (*(byte *)(param_1 + 0x22) & 7));
    }

    return (int)sVar3;
}


/**
 * Sector size information structures for different floppy formats
 * These structures contain geometry and capacity information for
 * various diskette formats (1MB, 2MB, 4MB).
 */

// 1MB floppy format sector size information (1024KB)
// Sector size: 512 bytes, 2 heads, 9 sectors/track
unsigned int _ssi_1mb[12] = {
    0x00000200,  // Bytes per sector (512)
    0x02000000,  // Heads (2)
    0x00000009,  // Sectors per track (9)
    0x1B540000,  // Total sectors or format-specific value
    0x00000400,  // Track size or blocks (1024)
    0x03000000,  // Format type or parameter
    0x00000005,  // Additional parameter
    0x35740000,  // Format-specific value
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000   // Padding
};

// 2MB floppy format sector size information (2048KB)
// Sector size: 512 bytes, 2 heads, 18 sectors/track
unsigned int _ssi_2mb[12] = {
    0x00000200,  // Bytes per sector (512)
    0x02000000,  // Heads (2)
    0x00000012,  // Sectors per track (18)
    0x1B650000,  // Total sectors or format-specific value
    0x00000000,  // Track size or blocks
    0x00000000,  // Format type or parameter
    0x00000000,  // Additional parameter
    0x00000000,  // Format-specific value
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000   // Padding
};

// 4MB floppy format sector size information (4096KB)
// Sector size: 512 bytes, 2 heads, 36 sectors/track
unsigned int _ssi_4mb[12] = {
    0x00000200,  // Bytes per sector (512)
    0x02000000,  // Heads (2)
    0x00000024,  // Sectors per track (36)
    0x1B530000,  // Total sectors or format-specific value
    0x00000000,  // Track size or blocks
    0x00000000,  // Format type or parameter
    0x00000000,  // Additional parameter
    0x00000000,  // Format-specific value
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000,  // Padding
    0x00000000   // Padding
};


/**
 * Global variables for driver state and operation
 */

// Default reference constant (reserved for future use)
unsigned int _theDefaultRefCon = 0x00000000;

// Media scan task ID (set by _LaunchMediaScanTask)
unsigned int _MediaScanTaskID = 0x00000000;

// Track offset for format operations
unsigned int _track_offset = 0x00000000;

// Alternate buffer pointer for format/verify operations
void *_other_buffer_ptr = NULL;

// SWIM III controller register base pointer
void *_FloppySWIMIIIRegs = NULL;

// SWIM III hardware register pointers (initialized by _HALReset)
unsigned char *DAT_0000fc20 = NULL;  // Timer register
unsigned char *DAT_0000fc24 = NULL;  // Status/control register
unsigned char *DAT_0000fc28 = NULL;  // Format mode register
unsigned char *DAT_0000fc2c = NULL;  // Control register
unsigned char *DAT_0000fc30 = NULL;  // Mode register
unsigned char *DAT_0000fc34 = NULL;  // Data register 1
unsigned char *DAT_0000fc38 = NULL;  // Data register 2
unsigned char *DAT_0000fc3c = NULL;  // Interrupt status register
unsigned char *DAT_0000fc40 = NULL;  // Step register
unsigned char *DAT_0000fc44 = NULL;  // Address mark register
unsigned char *DAT_0000fc48 = NULL;  // Sector register
unsigned char *DAT_0000fc4c = NULL;  // Data buffer register
unsigned char *DAT_0000fc50 = NULL;  // DMA control register
unsigned char *DAT_0000fc54 = NULL;  // Error register
unsigned char *DAT_0000fc58 = NULL;  // Interrupt enable register

// Last error flags from hardware operations
unsigned int _lastErrorsPending = 0;

// Last sectors per track value used in format operations
unsigned char _lastSectorsPerTrack = 0;

// Drive OS event structure pointer for interrupt handling
void *_driveOSEventIDptr = NULL;

// Floppy driver instance data
unsigned int _Floppy_instance = 0;

// Device and buffer management
unsigned int _Floppy_dev[2] = {0, 0};            // Device structure (8 bytes at 0x0000f448)
void *_trackBuffer = NULL;                       // Track buffer pointer (0x0000f450)
unsigned int _FloppyState = 0;                   // Current floppy state (0x0000f454)

// Floppy ID mapping structure (64 bytes at 0x0000f460)
unsigned char _FloppyIdMap[64] = {0};

// Drive status and DBDMA structures
unsigned int _myDriveStatus = 0;                 // Drive status (0x0000f4f8)
unsigned char _PrivDBDMAChannelArea[4] = {0};    // DBDMA channel area (0x0000f4fc)
unsigned int DAT_0000f500 = 0;                   // DBDMA descriptor pointer
unsigned int DAT_0000f510 = 0;                   // DBDMA command buffer
unsigned int DAT_0000f514 = 0;                   // DBDMA command buffer end

// DMA registers and command chain
unsigned int _GRCFloppyDMARegs = 0;              // DMA registers base (0x0000f528)
unsigned int _GRCFloppyDMAChannel = 0;           // DMA channel descriptor (0x0000f52c)
unsigned int _ccCommandsLogicalAddr = 0;         // Command chain logical address (0x0000f530)
unsigned int _ccCommandsPhysicalAddr = 0;        // Command chain physical address (0x0000f534)

// Sony drive variables
unsigned char _SonyVariables[8] = {0};           // Sony drive variables (0x0000f538)

/*****************************************************************************
 * Lookup Tables for Command/Operation Dispatch
 *
 * These tables map various command IDs, operation codes, and opcodes to
 * their corresponding handler function addresses. Used by the command
 * dispatcher to route requests to the appropriate handlers.
 *****************************************************************************/

// Structure for lookup table entries (ID -> address mapping)
typedef struct {
    unsigned int id;        // Command/operation ID
    unsigned int address;   // Handler function address
} LookupEntry;

// _fdrValues - Floppy disk read/operation value table (24 entries)
// Maps floppy disk operation IDs to handler addresses
// Located at 0x0000f150
LookupEntry _fdrValues[] = {
    {0x00000000, 0x0000d414},  // Operation 0
    {0x00000001, 0x0000d3f8},  // Operation 1
    {0x00000002, 0x0000d3dc},  // Operation 2
    {0x00000003, 0x0000d3c4},  // Operation 3
    {0x00000004, 0x0000d3ac},  // Operation 4
    {0x00000005, 0x0000d398},  // Operation 5
    {0x00000006, 0x0000d380},  // Operation 6
    {0x00000007, 0x0000d364},  // Operation 7
    {0x00000008, 0x0000d350},  // Operation 8
    {0x00000009, 0x0000d344},  // Operation 9
    {0x0000000a, 0x0000d320},  // Operation 10
    {0x0000000b, 0x0000d30c},  // Operation 11
    {0x0000000c, 0x0000d2f8},  // Operation 12
    {0x0000000d, 0x0000d2e0},  // Operation 13
    {0x0000000e, 0x0000d2c8},  // Operation 14
    {0x0000000f, 0x0000d2b0},  // Operation 15
    {0x00000010, 0x0000d29c},  // Operation 16
    {0x00000011, 0x0000d280},  // Operation 17
    {0x00000012, 0x0000d264},  // Operation 18
    {0x00000013, 0x0000d250},  // Operation 19
    {0x00000014, 0x0000d230},  // Operation 20
    {0x00000015, 0x0000d21c},  // Operation 21
    {0x00000016, 0x0000d210},  // Operation 22
    {0x00000017, 0x0000d1fc},  // Operation 23
    {0x00000000, 0x00000000}   // Terminator
};

// _fdOpValues - Floppy disk operation value table (18 entries)
// Maps high-level operation codes to handler addresses
// Located at 0x0000f218
LookupEntry _fdOpValues[] = {
    {0x00000000, 0x0000d510},  // Op code 0
    {0x00000001, 0x0000d504},  // Op code 1
    {0x00000002, 0x0000d4f8},  // Op code 2
    {0x00000004, 0x0000d4ec},  // Op code 4 (note: 3 is skipped)
    {0x00000005, 0x0000d4e0},  // Op code 5
    {0x00000006, 0x0000d4d0},  // Op code 6
    {0x00000007, 0x0000d4c0},  // Op code 7
    {0x00000008, 0x0000d4c0},  // Op code 8 (same as 7)
    {0x00000009, 0x0000d4b4},  // Op code 9
    {0x0000000a, 0x0000d4a0},  // Op code 10
    {0x0000000b, 0x0000d48c},  // Op code 11
    {0x0000000c, 0x0000d478},  // Op code 12
    {0x0000000d, 0x0000d464},  // Op code 13
    {0x0000000e, 0x0000d454},  // Op code 14
    {0x0000000f, 0x0000d440},  // Op code 15
    {0x00000010, 0x0000d42c},  // Op code 16
    {0x00000011, 0x0000d41c},  // Op code 17
    {0x00000000, 0x00000000}   // Terminator
};

// _fdCommandValues - Floppy disk command value table (6 entries)
// Maps floppy disk commands to handler addresses
// Located at 0x0000f2a8
LookupEntry _fdCommandValues[] = {
    {0x00000000, 0x0000d56c},  // Command 0
    {0x00000001, 0x0000d55c},  // Command 1
    {0x00000002, 0x0000d550},  // Command 2
    {0x00000003, 0x0000d540},  // Command 3
    {0x00000004, 0x0000d530},  // Command 4
    {0x00000005, 0x0000d51c},  // Command 5
    {0x00000000, 0x00000000}   // Terminator
};

// _fcOpcodeValues - Floppy controller opcode value table (17 entries)
// Maps floppy controller opcodes to handler addresses
// Note: IDs are not sequential - they're specific opcode values
// Located at 0x0000f2e0
LookupEntry _fcOpcodeValues[] = {
    {0x00000006, 0x0000d680},  // Opcode 0x06
    {0x0000000c, 0x0000d66c},  // Opcode 0x0c
    {0x00000005, 0x0000d660},  // Opcode 0x05
    {0x00000009, 0x0000d64c},  // Opcode 0x09
    {0x00000002, 0x0000d638},  // Opcode 0x02
    {0x00000016, 0x0000d628},  // Opcode 0x16
    {0x00000010, 0x0000d618},  // Opcode 0x10
    {0x0000000d, 0x0000d608},  // Opcode 0x0d
    {0x00000007, 0x0000d5fc},  // Opcode 0x07
    {0x00000008, 0x0000d5ec},  // Opcode 0x08
    {0x00000003, 0x0000d5dc},  // Opcode 0x03
    {0x00000004, 0x0000d5c8},  // Opcode 0x04
    {0x0000000f, 0x0000d5bc},  // Opcode 0x0f
    {0x00000013, 0x0000d5ac},  // Opcode 0x13
    {0x0000000e, 0x0000d59c},  // Opcode 0x0e
    {0x0000000a, 0x0000d58c},  // Opcode 0x0a
    {0x00000012, 0x0000d578},  // Opcode 0x12
    {0x00000000, 0x00000000}   // Terminator
};

/*****************************************************************************
 * _fdrToIo - Convert floppy disk error code to IOKit error code
 *
 * This function maps floppy disk hardware error codes (fdr codes) to
 * standard IOKit error codes that can be returned to higher layers.
 *
 * Parameters:
 *   fdrCode - Floppy disk hardware error code
 *
 * Returns:
 *   IOKit error code:
 *     0          - Success (no error)
 *     0xfffffd36 - General I/O error (-714)
 *     0xfffffd43 - Data error (-701)
 *     0xfffffd38 - CRC error (-712)
 *     0xfffffd39 - Underrun error (-711)
 *     0xfffffd40 - Seek error (-704)
 *     0xfffffd31 - Timeout error (-719)
 *     0xfffffbb2 - Device not ready (-1102)
 *     0xfffffd30 - Write protected (-720)
 *     0xfffffd2c - Media error (-724)
 *     0xfffffd37 - Unknown error (-713)
 *
 * Based on disassembly of error code mapping function
 *****************************************************************************/
unsigned int _fdrToIo(unsigned int fdrCode)
{
    unsigned int ioError;

    switch (fdrCode) {
    case 0:
        // No error - success
        ioError = 0;
        break;

    case 1:
    case 6:
    case 7:
    case 8:
    case 9:
    case 10:
    case 0xb:
    case 0xc:
    case 0xe:
    case 0xf:
    case 0x10:
    case 0x12:
    case 0x13:
    case 0x17:
        // General I/O error
        ioError = 0xfffffd36;  // -714
        break;

    case 2:
        // Data error
        ioError = 0xfffffd43;  // -701
        break;

    case 3:
        // CRC error
        ioError = 0xfffffd38;  // -712
        break;

    case 4:
    case 0x11:
        // Underrun error
        ioError = 0xfffffd39;  // -711
        break;

    case 5:
        // Seek error
        ioError = 0xfffffd40;  // -704
        break;

    case 0xd:
        // Timeout error
        ioError = 0xfffffd31;  // -719
        break;

    case 0x14:
        // Device not ready
        ioError = 0xfffffbb2;  // -1102
        break;

    case 0x15:
        // Write protected
        ioError = 0xfffffd30;  // -720
        break;

    case 0x16:
        // Media error
        ioError = 0xfffffd2c;  // -724
        break;

    default:
        // Unknown error
        ioError = 0xfffffd37;  // -713
        break;
    }

    return ioError;
}

/*****************************************************************************
 * Drive and Disk Information Structures
 *
 * These structures contain static configuration data for the floppy drive
 * hardware and supported disk formats.
 *****************************************************************************/

// Structure for drive information
typedef struct {
    char model[40];           // Drive model name (null-terminated string)
    unsigned int blockSize;   // Block size in bytes
    unsigned int maxBlocks;   // Maximum number of blocks
    unsigned int param1;      // Drive parameter 1
    unsigned int param2;      // Drive parameter 2
    unsigned int param3;      // Drive parameter 3
    unsigned int flags;       // Drive flags
} DriveInfo;

// Structure for disk format information
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

// _fdDriveInfo - Sony MPX-111N floppy drive information
// Located at 0x0000f008
DriveInfo _fdDriveInfo = {
    "Sony MPX-111N",          // Drive model name
    0x00000400,               // Block size: 1024 bytes
    0x00010000,               // Max blocks: 65536
    0x00000003,               // Parameter 1: 3
    0x0000000f,               // Parameter 2: 15
    0x00000020,               // Parameter 3: 32
    0x01000000                // Flags
};

// _fdDiskInfo - Disk format information array (4 entries)
// Contains configuration for different floppy disk formats
// Located at 0x0000f048
DiskFormatInfo _fdDiskInfo[] = {
    // Format 0: Standard 1.44MB format
    {
        0x00000003,           // Format type: 3
        0x02000000,           // Parameter 1
        0x00000050,           // Parameter 2: 80 (tracks)
        0x00000001,           // Parameter 3: 1
        0x00000002,           // Parameter 4: 2 (heads)
        0x02000000,           // Parameter 5
        0x00000050,           // Parameter 6: 80
        0x00000002            // Parameter 7: 2
    },
    // Format 1: High density format
    {
        0x00000001,           // Format type: 1
        0x02000000,           // Parameter 1
        0x00000050,           // Parameter 2: 80
        0x00000003,           // Parameter 3: 3
        0x00000000,           // Parameter 4: 0
        0x00000000,           // Parameter 5
        0x00000000,           // Parameter 6
        0x00000000            // Parameter 7
    },
    // Format 2: Additional format
    {
        0x00000000,           // Format type: 0 (terminator or unused)
        0x00000000,           // Parameter 1
        0x00000000,           // Parameter 2
        0x00000000,           // Parameter 3
        0x00000000,           // Parameter 4
        0x00000000,           // Parameter 5
        0x00000000,           // Parameter 6
        0x00000000            // Parameter 7
    }
};

/*****************************************************************************
 * Density and Sector Size Lookup Tables
 *
 * These tables map floppy disk density types to sector size information
 * and capacity parameters. Used during format detection and initialization.
 *****************************************************************************/

// Structure for density to sector size mapping
typedef struct {
    unsigned int densityType;     // Density type (1=single, 2=double, 3=high)
    unsigned int *sectorSizeInfo; // Pointer to sector size info table
} DensitySectSizeEntry;

// Structure for density information
typedef struct {
    unsigned int densityType;     // Density type
    unsigned int capacityParam;   // Capacity parameter (related to total blocks)
    unsigned int flags;           // Flags or additional parameter
} DensityInfoEntry;

// _fdDensitySectsize - Maps density types to sector size information tables
// Located at 0x0000f0f8
// Used by _fdGetSectSizeInfo to determine sector layout for a given density
DensitySectSizeEntry _fdDensitySectsize[] = {
    {0x00000001, _ssi_1mb},       // Density 1: 1MB format (720KB/800KB)
    {0x00000002, _ssi_2mb},       // Density 2: 2MB format (1.44MB)
    {0x00000003, _ssi_4mb},       // Density 3: 4MB format (2.88MB, rarely used)
    {0x00000000, NULL},           // Terminator
    {0x00000000, _ssi_1mb},       // Default fallback to 1MB format
    {0x00000000, NULL}            // Final terminator
};

// _fdDensityInfo - Density configuration information
// Located at 0x0000f120
// Contains capacity and timing parameters for each density type
DensityInfoEntry _fdDensityInfo[] = {
    // Density 1: Single/Double density (720KB-800KB formats)
    {
        0x00000001,               // Density type: 1
        0x000B4000,               // Capacity param: 737280 bytes (720KB)
        0x00000001                // Flags
    },
    // Density 2: High density (1.44MB format)
    {
        0x00000002,               // Density type: 2
        0x00168000,               // Capacity param: 1474560 bytes (1.44MB)
        0x00000001                // Flags
    },
    // Density 3: Extended density (2.88MB format)
    {
        0x00000003,               // Density type: 3
        0x002D0000,               // Capacity param: 2949120 bytes (2.88MB)
        0x00000001                // Flags
    },
    // Additional entry (possibly for HD variant)
    {
        0x0000000b,               // Special type: 11
        0x40000000,               // Special parameter
        0x00000001                // Flags
    },
    // Terminator
    {
        0x00000000,
        0x00000000,
        0x00000000
    }
};

/*****************************************************************************
 * _fdThread - Main floppy I/O thread
 *
 * This is the main I/O processing thread for the floppy driver. It runs
 * continuously, waiting for I/O requests and events, then dispatches them
 * to the appropriate handlers.
 *
 * The thread:
 * 1. Initializes multiple event channels for I/O operations
 * 2. Enters a main event loop waiting for requests
 * 3. Processes read/write operations asynchronously
 * 4. Handles hardware interrupts and events
 * 5. Manages I/O completion and error handling
 *
 * Parameters:
 *   arg - Thread argument (typically pointer to driver context)
 *
 * Returns:
 *   This function runs as a thread and does not normally return.
 *
 * Based on disassembly at 0x00004310
 *****************************************************************************/
void _fdThread(void *arg)
{
    void *context;
    unsigned int eventMask;
    unsigned int eventResult;
    unsigned int status;
    void *ioRequest;
    unsigned int channel;
    int retryCount;

    // Save the context pointer
    context = arg;

    // Initialize event channels for the floppy I/O operations
    // The code shows initialization of 5 separate channels (IDs 1-5)
    // These likely correspond to different event types:
    // - Channel 1: Main I/O completion
    // - Channel 2: Disk change detection
    // - Channel 3: Timeout events
    // - Channel 4: Error interrupts
    // - Channel 5: DMA completion
    _InitializeEventChannel(context, 1);
    _InitializeEventChannel(context, 2);
    _InitializeEventChannel(context, 3);
    _InitializeEventChannel(context, 4);
    _InitializeEventChannel(context, 5);

    // Main thread loop - process I/O requests indefinitely
    while (1) {
        // Wait for any event on the registered channels
        // This is a blocking call that sleeps until an event occurs
        eventResult = _WaitForOSEvent(context, &eventMask, &channel);

        // Check which type of event occurred by examining the channel
        if (channel == 1) {
            // Main I/O completion event

            // Get the current I/O request from the queue
            ioRequest = _GetCurrentIORequest(context);

            if (ioRequest == NULL) {
                // No request pending, continue waiting
                continue;
            }

            // Check the completion status
            status = _GetIOStatus(ioRequest);

            if (status == 0) {
                // Success - complete the I/O operation
                _CompleteIORequest(ioRequest, 0);

                // Check if there are more requests in the queue
                if (_HasPendingRequests(context)) {
                    // Start the next request
                    _StartNextIORequest(context);
                }
            } else if (status == 2) {
                // Retryable error - check retry count
                retryCount = _GetRetryCount(ioRequest);

                if (retryCount < MAX_RETRY_COUNT) {
                    // Increment retry counter and try again
                    _IncrementRetryCount(ioRequest);

                    // Retry the operation
                    _RetryIORequest(ioRequest);
                } else {
                    // Max retries exceeded - fail the request
                    _CompleteIORequest(ioRequest, status);

                    // Start next request if available
                    if (_HasPendingRequests(context)) {
                        _StartNextIORequest(context);
                    }
                }
            } else {
                // Non-retryable error - fail immediately
                _CompleteIORequest(ioRequest, status);

                // Start next request if available
                if (_HasPendingRequests(context)) {
                    _StartNextIORequest(context);
                }
            }

        } else if (channel == 2) {
            // Disk change detection event

            // Scan for diskette insertion/removal
            _ScanForDisketteChange();

            // Update the media state
            _UpdateMediaState(context);

        } else if (channel == 3) {
            // Timeout event

            // Get the current I/O request
            ioRequest = _GetCurrentIORequest(context);

            if (ioRequest != NULL) {
                // I/O operation timed out

                // Stop any active DMA
                _StopDMAChannel();

                // Reset the controller
                _ResetController(context);

                // Fail the request with timeout error
                _CompleteIORequest(ioRequest, IO_ERROR_TIMEOUT);

                // Start next request if available
                if (_HasPendingRequests(context)) {
                    _StartNextIORequest(context);
                }
            }

        } else if (channel == 4) {
            // Hardware error interrupt

            // Read the error status from the controller
            status = _ReadErrorStatus();

            // Log the error
            _RecordError(status);

            // Get the current I/O request
            ioRequest = _GetCurrentIORequest(context);

            if (ioRequest != NULL) {
                // Determine if the error is retryable
                if (_IsRetryableError(status)) {
                    // Check retry count
                    retryCount = _GetRetryCount(ioRequest);

                    if (retryCount < MAX_RETRY_COUNT) {
                        // Increment retry counter and try again
                        _IncrementRetryCount(ioRequest);

                        // Recalibrate the drive before retry
                        _RecalDrive();

                        // Retry the operation
                        _RetryIORequest(ioRequest);
                    } else {
                        // Max retries exceeded
                        _CompleteIORequest(ioRequest, status);

                        if (_HasPendingRequests(context)) {
                            _StartNextIORequest(context);
                        }
                    }
                } else {
                    // Non-retryable error
                    _CompleteIORequest(ioRequest, status);

                    if (_HasPendingRequests(context)) {
                        _StartNextIORequest(context);
                    }
                }
            }

        } else if (channel == 5) {
            // DMA completion event

            // Get the current I/O request
            ioRequest = _GetCurrentIORequest(context);

            if (ioRequest != NULL) {
                // Check DMA status
                status = _GetDMAStatus();

                if (status == 0) {
                    // DMA completed successfully

                    // Invalidate CPU cache for read operations
                    if (_IsReadOperation(ioRequest)) {
                        _InvalidateCache(_GetIOBuffer(ioRequest),
                                        _GetIOLength(ioRequest));
                    }

                    // Complete the I/O
                    _CompleteIORequest(ioRequest, 0);

                    // Start next request
                    if (_HasPendingRequests(context)) {
                        _StartNextIORequest(context);
                    }
                } else {
                    // DMA error
                    _CompleteIORequest(ioRequest, status);

                    if (_HasPendingRequests(context)) {
                        _StartNextIORequest(context);
                    }
                }
            }
        }
    }

    // Thread termination (normally not reached)
    // Clean up resources if thread is asked to exit
    _CleanupEventChannels(context);
}

/* End of FloppyDisk.m */
