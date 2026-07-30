#import <sys/types.h>
#import <sys/buf.h>
#import <sys/errno.h>
#import <sys/proc.h>
#import <sys/systm.h>
#import <sys/uio.h>
#import <bsd/dev/ldd.h>
#import <bsd/libkern/libkern.h>
#import <driverkit/devsw.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IODiskPartition.h>
#import <driverkit/kernelDiskMethods.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>

#import "ata_hd_registry.h"
#import "ata_hd_registry_core.h"

#define ATA_HD_BLOCK_MAJOR 3
#define ATA_HD_RAW_MAJOR 15
#define ATA_HD_LIVE_PART (ATA_HD_PARTITIONS - 1)
#define ATA_HD_MAX_PHYS_IO (256 * 512)

typedef struct ATAHDUnitState {
    struct buf *physbuf;
    ata_hd_ioctl_fn transportIoctl;
    ata_hd_flush_fn transportFlush;
    unsigned int ioCount;
    unsigned char blockOpen[ATA_HD_PARTITIONS];
    unsigned char rawOpen[ATA_HD_PARTITIONS];
} ATAHDUnitState;

typedef enum ATAHDDevswState {
    ATA_HD_DEVSW_NONE,
    ATA_HD_DEVSW_INITIALIZING,
    ATA_HD_DEVSW_READY
} ATAHDDevswState;

static ATAHDRegistryCore ata_hd_core;
static IODevAndIdInfo ata_hd_maps[ATA_HD_UNITS];
static ATAHDUnitState ata_hd_units[ATA_HD_UNITS];
static ATAHDAsyncTokenCore ata_hd_async_tokens;

/*
 * Initialized before i386 DriverKit probing starts. The registry lock protects
 * only the core, map contents, vnode-presence state, callback pointers, and
 * devsw publication state. It must not be held while calling an IODisk object.
 * IODisk map writers take this lock through the ata_hd_map_* entry points.
 */
static NXLock *ata_hd_lock = nil;
static BOOL ata_hd_registry_ready = NO;
static ATAHDDevswState ata_hd_devsw_state = ATA_HD_DEVSW_NONE;
static int ata_hd_block_major = -1;
static int ata_hd_raw_major = -1;

static int ata_hd_open(dev_t dev, int flag, int devtype, struct proc *proc);
static int ata_hd_close(dev_t dev, int flag, int devtype, struct proc *proc);
static int ata_hd_read(dev_t dev, struct uio *uiop, int ioflag);
static int ata_hd_write(dev_t dev, struct uio *uiop, int ioflag);
static void ata_hd_strategy(struct buf *bp);
static int ata_hd_ioctl(dev_t dev, u_long cmd, caddr_t data, int flag,
                        struct proc *proc);
static int ata_hd_size(dev_t dev);
static unsigned ata_hd_minphys(struct buf *bp);

static BOOL ata_hd_requested_majors(Class diskClass,
                                    IODeviceDescription *deviceDescription,
                                    int *blockMajor, int *rawMajor);
static BOOL ata_hd_parse_major(const char *string, int *majorOut);
static BOOL ata_hd_valid_dev_locked(dev_t dev);
static id ata_hd_disk_for_dev_locked(dev_t dev);
static unsigned char *ata_hd_presence_for_dev_locked(dev_t dev);
static int ata_hd_map_unit_locked(IODevAndIdInfo *map);
static int ata_hd_core_error_to_errno(int error);
static void ata_hd_free_physbufs(struct buf **physbufs,
                                 unsigned int count);
static int ata_hd_pin_io_locked(void *pending, unsigned int unit,
                                unsigned int partition,
                                ATAHDAsyncToken *tokenOut);

BOOL
ata_hd_registry_init(void)
{
    NXLock *registryLock;

    if (ata_hd_registry_ready)
        return YES;

    registryLock = [NXLock new];
    if (registryLock == nil)
        return NO;

    ATAHDRegistryCoreInit(&ata_hd_core);
    bzero((char *)ata_hd_maps, sizeof(ata_hd_maps));
    bzero((char *)ata_hd_units, sizeof(ata_hd_units));
    ATAHDAsyncTokenCoreInit(&ata_hd_async_tokens);
    ata_hd_devsw_state = ATA_HD_DEVSW_NONE;
    ata_hd_block_major = -1;
    ata_hd_raw_major = -1;
    ata_hd_lock = registryLock;
    ata_hd_registry_ready = YES;
    return YES;
}

static BOOL
ata_hd_parse_major(const char *string, int *majorOut)
{
    char *end;
    long value;

    if (string == NULL || majorOut == NULL)
        return NO;

    value = strtol(string, &end, 10);
    if (end == string || *end != '\0' || value < 0 || value > 255)
        return NO;

    *majorOut = (int)value;
    return YES;
}

static BOOL
ata_hd_requested_majors(Class diskClass,
                        IODeviceDescription *deviceDescription,
                        int *blockMajor, int *rawMajor)
{
    const char *majorString;

    if (diskClass == Nil || deviceDescription == nil ||
        blockMajor == NULL || rawMajor == NULL)
        return NO;

    majorString = [[deviceDescription configTable]
                    valueForStringKey:"Block Major"];
    if (majorString != NULL) {
        if (!ata_hd_parse_major(majorString, blockMajor))
            return NO;
    } else {
        *blockMajor = [diskClass blockMajor];
    }

    majorString = [[deviceDescription configTable]
                    valueForStringKey:"Character Major"];
    if (majorString != NULL) {
        if (!ata_hd_parse_major(majorString, rawMajor))
            return NO;
    } else {
        *rawMajor = [diskClass characterMajor];
    }

    return (*blockMajor >= 0 && *rawMajor >= 0);
}

BOOL
ata_hd_devsw_init(Class diskClass,
                  IODeviceDescription *deviceDescription)
{
    extern int seltrue();
    struct buf *physbufs[ATA_HD_UNITS];
    unsigned int unit;
    unsigned int allocated;
    int requestedBlockMajor;
    int requestedRawMajor;
    int blockMajor;
    int rawMajor;
    BOOL cdevAdded;
    BOOL bdevAdded;

    if (!ata_hd_requested_majors(diskClass, deviceDescription,
                                 &requestedBlockMajor,
                                 &requestedRawMajor))
        return NO;
    if (requestedBlockMajor != ATA_HD_BLOCK_MAJOR ||
        requestedRawMajor != ATA_HD_RAW_MAJOR)
        return NO;
    if (!ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;

    for (;;) {
        [ata_hd_lock lock];
        if (ata_hd_devsw_state != ATA_HD_DEVSW_INITIALIZING)
            break;
        [ata_hd_lock unlock];
        IOSleep(1);
    }

    if (ata_hd_devsw_state == ATA_HD_DEVSW_READY) {
        blockMajor = ata_hd_block_major;
        rawMajor = ata_hd_raw_major;
        [ata_hd_lock unlock];
        if (requestedBlockMajor != blockMajor ||
            requestedRawMajor != rawMajor)
            return NO;
        [diskClass setBlockMajor:blockMajor];
        [diskClass setCharacterMajor:rawMajor];
        return YES;
    }

    ata_hd_devsw_state = ATA_HD_DEVSW_INITIALIZING;
    [ata_hd_lock unlock];

    allocated = 0;
    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        physbufs[unit] = (struct buf *)IOMalloc(sizeof(struct buf));
        if (physbufs[unit] == NULL)
            break;
        bzero((char *)physbufs[unit], sizeof(struct buf));
        ++allocated;
    }
    if (allocated != ATA_HD_UNITS) {
        [ata_hd_lock lock];
        ata_hd_devsw_state = ATA_HD_DEVSW_NONE;
        [ata_hd_lock unlock];
        ata_hd_free_physbufs(physbufs, allocated);
        return NO;
    }

    cdevAdded = [diskClass addToCdevswFromDescription:deviceDescription
                                      open:(IOSwitchFunc)ata_hd_open
                                     close:(IOSwitchFunc)ata_hd_close
                                      read:(IOSwitchFunc)ata_hd_read
                                     write:(IOSwitchFunc)ata_hd_write
                                     ioctl:(IOSwitchFunc)ata_hd_ioctl
                                      stop:(IOSwitchFunc)eno_stop
                                     reset:(IOSwitchFunc)nulldev
                                    select:(IOSwitchFunc)seltrue
                                      mmap:(IOSwitchFunc)eno_mmap
                                      getc:(IOSwitchFunc)eno_getc
                                      putc:(IOSwitchFunc)eno_putc];
    bdevAdded = NO;
    if (cdevAdded == YES) {
        bdevAdded = [diskClass
                    addToBdevswFromDescription:deviceDescription
                                      open:(IOSwitchFunc)ata_hd_open
                                     close:(IOSwitchFunc)ata_hd_close
                                  strategy:(IOSwitchFunc)ata_hd_strategy
                                     ioctl:(IOSwitchFunc)ata_hd_ioctl
                                      dump:(IOSwitchFunc)eno_dump
                                     psize:(IOSwitchFunc)ata_hd_size
                                    isTape:FALSE];
    }

    blockMajor = [diskClass blockMajor];
    rawMajor = [diskClass characterMajor];
    if (cdevAdded != YES || bdevAdded != YES ||
        blockMajor != requestedBlockMajor || rawMajor != requestedRawMajor) {
        if (bdevAdded == YES)
            [diskClass removeFromBdevsw];
        if (cdevAdded == YES)
            [diskClass removeFromCdevsw];
        [ata_hd_lock lock];
        ata_hd_devsw_state = ATA_HD_DEVSW_NONE;
        [ata_hd_lock unlock];
        ata_hd_free_physbufs(physbufs, ATA_HD_UNITS);
        return NO;
    }

    [ata_hd_lock lock];
    for (unit = 0; unit < ATA_HD_UNITS; ++unit)
        ata_hd_units[unit].physbuf = physbufs[unit];
    ata_hd_block_major = blockMajor;
    ata_hd_raw_major = rawMajor;
    ata_hd_devsw_state = ATA_HD_DEVSW_READY;
    [ata_hd_lock unlock];
    return YES;
}

static void
ata_hd_free_physbufs(struct buf **physbufs, unsigned int count)
{
    unsigned int unit;

    for (unit = 0; unit < count; ++unit)
        IOFree(physbufs[unit], sizeof(struct buf));
}

int
ata_hd_register(id disk, ata_hd_ioctl_fn transportIoctl,
                IODevAndIdInfo **mapOut)
{
    IODevAndIdInfo *map;
    int unit;

    if (mapOut == NULL)
        return ATA_HD_REGISTRY_INVALID;
    *mapOut = NULL;
    if (disk == nil || !ata_hd_registry_ready || ata_hd_lock == nil)
        return ATA_HD_REGISTRY_INVALID;

    [ata_hd_lock lock];
    if (ata_hd_devsw_state != ATA_HD_DEVSW_READY) {
        [ata_hd_lock unlock];
        return ATA_HD_REGISTRY_INVALID;
    }

    unit = ATAHDRegistryAllocate(&ata_hd_core, disk);
    if (unit < 0) {
        [ata_hd_lock unlock];
        return unit;
    }

    map = &ata_hd_maps[unit];
    bzero((char *)map, sizeof(*map));
    map->rawDev = makedev(ata_hd_raw_major, (unit << 3));
    map->blockDev = makedev(ata_hd_block_major, (unit << 3));
    ata_hd_units[unit].transportIoctl = transportIoctl;
    ata_hd_units[unit].transportFlush = NULL;
    ata_hd_units[unit].ioCount = 0;
    bzero((char *)ata_hd_units[unit].blockOpen,
          sizeof(ata_hd_units[unit].blockOpen));
    bzero((char *)ata_hd_units[unit].rawOpen,
          sizeof(ata_hd_units[unit].rawOpen));
    *mapOut = map;

    [ata_hd_lock unlock];
    return unit;
}

BOOL
ata_hd_set_flush(unsigned int unit, id disk,
                 ata_hd_flush_fn transportFlush)
{
    BOOL set;

    if (unit >= ATA_HD_UNITS || disk == nil || transportFlush == NULL ||
        !ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    set = ATAHDRegistryOwner(&ata_hd_core, unit) == disk ? YES : NO;
    if (set)
        ata_hd_units[unit].transportFlush = transportFlush;
    [ata_hd_lock unlock];
    return set;
}

BOOL
ata_hd_activate_units(const unsigned int *units, id *disks,
                      unsigned int count)
{
    void *owners[ATA_HD_UNITS];
    unsigned int index;
    unsigned int unit;
    int result;

    if (!ata_hd_registry_ready || ata_hd_lock == nil ||
        count > ATA_HD_UNITS)
        return NO;
    if (count == 0)
        return YES;
    if (units == NULL || disks == NULL)
        return NO;

    [ata_hd_lock lock];
    if (ata_hd_devsw_state != ATA_HD_DEVSW_READY) {
        [ata_hd_lock unlock];
        return NO;
    }
    for (index = 0; index < count; ++index) {
        unit = units[index];
        if (unit >= ATA_HD_UNITS || disks[index] == nil ||
            ATAHDRegistryOwner(&ata_hd_core, unit) != disks[index] ||
            ata_hd_maps[unit].liveId != disks[index]) {
            [ata_hd_lock unlock];
            return NO;
        }
        owners[index] = disks[index];
    }
    result = ATAHDRegistryActivateBatch(&ata_hd_core, units, owners, count);
    [ata_hd_lock unlock];
    return (result == ATA_HD_REGISTRY_SUCCESS) ? YES : NO;
}

IOReturn
ata_hd_unregister(unsigned int unit)
{
    int result;

    if (unit >= ATA_HD_UNITS || !ata_hd_registry_ready ||
        ata_hd_lock == nil)
        return IO_R_INVALID_ARG;

    [ata_hd_lock lock];
    if (ata_hd_devsw_state != ATA_HD_DEVSW_READY) {
        [ata_hd_lock unlock];
        return IO_R_NO_DEVICE;
    }

    result = ATAHDRegistryRemove(&ata_hd_core, unit);
    if (result == ATA_HD_BUSY) {
        [ata_hd_lock unlock];
        return IO_R_BUSY;
    }
    if (result == ATA_HD_REGISTRY_NOT_FOUND) {
        [ata_hd_lock unlock];
        return IO_R_NO_DEVICE;
    }
    if (result != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        return IO_R_INVALID_ARG;
    }

    bzero((char *)&ata_hd_maps[unit], sizeof(ata_hd_maps[unit]));
    ata_hd_units[unit].transportIoctl = NULL;
    ata_hd_units[unit].transportFlush = NULL;
    ata_hd_units[unit].ioCount = 0;
    bzero((char *)ata_hd_units[unit].blockOpen,
          sizeof(ata_hd_units[unit].blockOpen));
    bzero((char *)ata_hd_units[unit].rawOpen,
          sizeof(ata_hd_units[unit].rawOpen));
    [ata_hd_lock unlock];
    return IO_R_SUCCESS;
}

IODevAndIdInfo *
ata_hd_lookup(dev_t dev)
{
    IODevAndIdInfo *map;

    if (!ata_hd_registry_ready || ata_hd_lock == nil)
        return NULL;

    [ata_hd_lock lock];
    if (!ata_hd_valid_dev_locked(dev)) {
        [ata_hd_lock unlock];
        return NULL;
    }
    map = &ata_hd_maps[IO_DISK_UNIT(dev)];
    [ata_hd_lock unlock];
    return map;
}

static int
ata_hd_map_unit_locked(IODevAndIdInfo *map)
{
    unsigned int unit;

    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        if (map == &ata_hd_maps[unit])
            return (int)unit;
    }
    return -1;
}

BOOL
ata_hd_map_is_owned(IODevAndIdInfo *map)
{
    BOOL owned;

    if (map == NULL || !ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    owned = (ata_hd_map_unit_locked(map) >= 0) ? YES : NO;
    [ata_hd_lock unlock];
    return owned;
}

BOOL
ata_hd_map_set_live(IODevAndIdInfo *map, id disk)
{
    int unit;

    if (map == NULL || disk == nil || !ata_hd_registry_ready ||
        ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    unit = ata_hd_map_unit_locked(map);
    if (unit >= 0 && ATAHDRegistryOwner(&ata_hd_core, unit) == disk)
        map->liveId = disk;
    [ata_hd_lock unlock];
    return (unit >= 0) ? YES : NO;
}

BOOL
ata_hd_map_clear_live(IODevAndIdInfo *map, id disk)
{
    int unit;
    unsigned int partition;
    BOOL busy;

    if (map == NULL || disk == nil || !ata_hd_registry_ready ||
        ata_hd_lock == nil)
        return NO;
    for (;;) {
        [ata_hd_lock lock];
        unit = ata_hd_map_unit_locked(map);
        if (unit < 0 || map->liveId != disk) {
            [ata_hd_lock unlock];
            return (unit >= 0) ? YES : NO;
        }
        busy = NO;
        for (partition = 0; partition < ATA_HD_PARTITIONS; ++partition) {
            if (ata_hd_core.openCounts[unit][partition] != 0) {
                busy = YES;
                break;
            }
        }
        if (!busy) {
            map->liveId = nil;
            [ata_hd_lock unlock];
            return YES;
        }
        [ata_hd_lock unlock];
        IOSleep(1);
    }
}

BOOL
ata_hd_map_set_partition(IODevAndIdInfo *map, id disk,
                         unsigned int partition)
{
    int unit;

    if (map == NULL || disk == nil || partition >= ATA_HD_LIVE_PART ||
        !ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    unit = ata_hd_map_unit_locked(map);
    if (unit >= 0 && ATAHDRegistryOwner(&ata_hd_core, unit) != NULL)
        map->partitionId[partition] = disk;
    [ata_hd_lock unlock];
    return (unit >= 0) ? YES : NO;
}

BOOL
ata_hd_map_clear_partition(IODevAndIdInfo *map, id disk,
                           unsigned int partition)
{
    int unit;

    if (map == NULL || disk == nil || partition >= ATA_HD_LIVE_PART ||
        !ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;
    for (;;) {
        [ata_hd_lock lock];
        unit = ata_hd_map_unit_locked(map);
        if (unit < 0 || map->partitionId[partition] != disk) {
            [ata_hd_lock unlock];
            return (unit >= 0) ? YES : NO;
        }
        if (ata_hd_core.openCounts[unit][partition] == 0) {
            map->partitionId[partition] = nil;
            [ata_hd_lock unlock];
            return YES;
        }
        [ata_hd_lock unlock];
        IOSleep(1);
    }
}

static BOOL
ata_hd_valid_dev_locked(dev_t dev)
{
    unsigned int unit;
    unsigned int partition;
    int deviceMajor;

    if (ata_hd_devsw_state != ATA_HD_DEVSW_READY)
        return NO;

    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    deviceMajor = major(dev);
    if (unit >= ATA_HD_UNITS || partition >= ATA_HD_PARTITIONS)
        return NO;
    if (deviceMajor != ata_hd_block_major &&
        deviceMajor != ata_hd_raw_major)
        return NO;
    return ATAHDRegistryIsActive(&ata_hd_core, unit);
}

static id
ata_hd_disk_for_dev_locked(dev_t dev)
{
    unsigned int unit;
    unsigned int partition;
    IODevAndIdInfo *map;

    if (!ata_hd_valid_dev_locked(dev))
        return nil;

    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    map = &ata_hd_maps[unit];
    if (partition == ATA_HD_LIVE_PART) {
        if (major(dev) == ata_hd_block_major)
            return nil;
        return map->liveId;
    }
    return map->partitionId[partition];
}

static unsigned char *
ata_hd_presence_for_dev_locked(dev_t dev)
{
    unsigned int unit;
    unsigned int partition;

    if (!ata_hd_valid_dev_locked(dev))
        return NULL;
    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    if (major(dev) == ata_hd_block_major)
        return &ata_hd_units[unit].blockOpen[partition];
    return &ata_hd_units[unit].rawOpen[partition];
}

static int
ata_hd_core_error_to_errno(int error)
{
    if (error == ATA_HD_BUSY || error == ATA_HD_REGISTRY_OVERFLOW)
        return EBUSY;
    if (error == ATA_HD_REGISTRY_NOT_FOUND ||
        error == ATA_HD_REGISTRY_INACTIVE ||
        error == ATA_HD_REGISTRY_INVALID)
        return ENXIO;
    return EINVAL;
}

static int
ata_hd_open(dev_t dev, int flag, int devtype, struct proc *proc)
{
    id disk;
    unsigned char *openState;
    BOOL becamePresent;
    unsigned int partition;
    unsigned int unit;
    int result;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    openState = ata_hd_presence_for_dev_locked(dev);
    if (disk == nil || openState == NULL) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    result = ATAHDRegistryOpen(&ata_hd_core, unit, partition);
    [ata_hd_lock unlock];
    if (result != ATA_HD_REGISTRY_SUCCESS)
        return ata_hd_core_error_to_errno(result);

    if ([disk isDiskReady:NO]) {
        [ata_hd_lock lock];
        (void)ATAHDRegistryClose(&ata_hd_core, unit, partition);
        [ata_hd_lock unlock];
        return ENXIO;
    }

    [ata_hd_lock lock];
    becamePresent = (*openState == 0) ? YES : NO;
    result = ATAHDRegistryPublishPinnedOpen(&ata_hd_core, unit, partition,
                                            openState);
    [ata_hd_lock unlock];
    if (result != ATA_HD_REGISTRY_SUCCESS) {
        return ata_hd_core_error_to_errno(result);
    }

    if (becamePresent && partition != ATA_HD_LIVE_PART) {
        if (major(dev) == ata_hd_block_major)
            [disk setBlockDeviceOpen:YES];
        else
            [disk setRawDeviceOpen:YES];
    }
    return 0;
}

static int
ata_hd_close(dev_t dev, int flag, int devtype, struct proc *proc)
{
    id disk;
    ata_hd_flush_fn flush;
    unsigned char *openState;
    unsigned int partition;
    unsigned int unit;
    int result;
    int flushError;
    IOReturn flushResult;

    flushError = 0;
    flushResult = IO_R_SUCCESS;
    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    openState = ata_hd_presence_for_dev_locked(dev);
    if (disk == nil || openState == NULL || *openState == 0) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    flush = ata_hd_units[unit].transportFlush;
    result = ATAHDRegistryOpen(&ata_hd_core, unit, partition);
    if (result == ATA_HD_REGISTRY_SUCCESS) {
        result = ATAHDRegistryCloseIfPresent(&ata_hd_core, unit, partition,
                                             openState);
        if (result != ATA_HD_REGISTRY_SUCCESS)
            (void)ATAHDRegistryClose(&ata_hd_core, unit, partition);
    }
    [ata_hd_lock unlock];
    if (result != ATA_HD_REGISTRY_SUCCESS)
        return ata_hd_core_error_to_errno(result);
    [ata_hd_lock lock];
    while (ata_hd_units[unit].ioCount != 0) {
        [ata_hd_lock unlock];
        IOSleep(1);
        [ata_hd_lock lock];
    }
    [ata_hd_lock unlock];
    if (flush != NULL) {
        if (result == ATA_HD_REGISTRY_SUCCESS)
            flushResult = flush(disk);
    }
    if (flushResult != IO_R_SUCCESS)
        flushError = [disk errnoFromReturn:flushResult];

    if (partition != ATA_HD_LIVE_PART) {
        if (major(dev) == ata_hd_block_major)
            [disk setBlockDeviceOpen:NO];
        else
            [disk setRawDeviceOpen:NO];
    }

    [ata_hd_lock lock];
    result = ATAHDRegistryClose(&ata_hd_core, unit, partition);
    [ata_hd_lock unlock];
    if (result != ATA_HD_REGISTRY_SUCCESS)
        return ata_hd_core_error_to_errno(result);
    return flushError;
}

static int
ata_hd_read(dev_t dev, struct uio *uiop, int ioflag)
{
    id disk;
    struct buf *physbuf;
    unsigned int blockSize;
    unsigned int unit;
    unsigned int partition;
    int pinResult;
    int result;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil || ata_hd_presence_for_dev_locked(dev) == NULL ||
        *ata_hd_presence_for_dev_locked(dev) == 0) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    pinResult = ATAHDRegistryOpen(&ata_hd_core, unit, partition);
    if (pinResult != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        return ata_hd_core_error_to_errno(pinResult);
    }
    physbuf = ata_hd_units[unit].physbuf;
    [ata_hd_lock unlock];
    blockSize = [disk blockSize];

    result = physio((int (*)())ata_hd_strategy, physbuf, dev, B_READ,
                    ata_hd_minphys, uiop, blockSize);
    [ata_hd_lock lock];
    pinResult = ATAHDRegistryClose(&ata_hd_core, unit, partition);
    [ata_hd_lock unlock];
    return result != 0 ? result :
           (pinResult == ATA_HD_REGISTRY_SUCCESS ? 0 :
            ata_hd_core_error_to_errno(pinResult));
}

static int
ata_hd_write(dev_t dev, struct uio *uiop, int ioflag)
{
    id disk;
    struct buf *physbuf;
    unsigned int blockSize;
    unsigned int unit;
    unsigned int partition;
    int pinResult;
    int result;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil || ata_hd_presence_for_dev_locked(dev) == NULL ||
        *ata_hd_presence_for_dev_locked(dev) == 0) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    pinResult = ATAHDRegistryOpen(&ata_hd_core, unit, partition);
    if (pinResult != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        return ata_hd_core_error_to_errno(pinResult);
    }
    physbuf = ata_hd_units[unit].physbuf;
    [ata_hd_lock unlock];
    blockSize = [disk blockSize];

    result = physio((int (*)())ata_hd_strategy, physbuf, dev, B_WRITE,
                    ata_hd_minphys, uiop, blockSize);
    [ata_hd_lock lock];
    pinResult = ATAHDRegistryClose(&ata_hd_core, unit, partition);
    [ata_hd_lock unlock];
    return result != 0 ? result :
           (pinResult == ATA_HD_REGISTRY_SUCCESS ? 0 :
            ata_hd_core_error_to_errno(pinResult));
}

static void
ata_hd_strategy(struct buf *bp)
{
    id disk;
    IOReturn result;
    vm_task_t client;
    unsigned int unit;
    unsigned int partition;
    ATAHDAsyncToken token;
    int pinResult;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(bp->b_dev);
    if (disk == nil || ata_hd_presence_for_dev_locked(bp->b_dev) == NULL ||
        *ata_hd_presence_for_dev_locked(bp->b_dev) == 0) {
        [ata_hd_lock unlock];
        bp->b_error = ENXIO;
        goto bad;
    }
    unit = IO_DISK_UNIT(bp->b_dev);
    partition = IO_DISK_PART(bp->b_dev);
    pinResult = ata_hd_pin_io_locked(bp, unit, partition, &token);
    if (pinResult != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        bp->b_error = ata_hd_core_error_to_errno(pinResult);
        goto bad;
    }
    [ata_hd_lock unlock];

    if ((bp->b_flags & (B_PHYS | B_KERNSPACE)) == B_PHYS)
        client = IOVmTaskForBuf(bp);
    else
        client = IOVmTaskSelf();

    if ([disk blockSize] == 0) {
        bp->b_error = ENXIO;
        ata_hd_async_complete(token);
        goto bad;
    }

    if (bp->b_flags & B_READ) {
        result = [disk readAsyncAt:bp->b_blkno
                            length:bp->b_bcount
                            buffer:bp->b_un.b_addr
                           pending:bp
                            client:client];
    } else {
        result = [disk writeAsyncAt:bp->b_blkno
                             length:bp->b_bcount
                             buffer:bp->b_un.b_addr
                            pending:bp
                             client:client];
    }

    if (result != IO_R_SUCCESS) {
        bp->b_error = [disk errnoFromReturn:result];
        ata_hd_async_complete(token);
        goto bad;
    }

    return;

bad:
    bp->b_flags |= B_ERROR;
    biodone(bp);
}

static int
ata_hd_pin_io_locked(void *pending, unsigned int unit,
                     unsigned int partition, ATAHDAsyncToken *tokenOut)
{
    int result;

    if (pending == NULL || tokenOut == NULL || unit >= ATA_HD_UNITS ||
        partition >= ATA_HD_PARTITIONS ||
        ata_hd_units[unit].ioCount == ~0U)
        return ATA_HD_REGISTRY_INVALID;
    result = ATAHDRegistryOpen(&ata_hd_core, unit, partition);
    if (result != ATA_HD_REGISTRY_SUCCESS)
        return result;
    result = ATAHDAsyncTokenReserve(&ata_hd_async_tokens, pending, unit,
                                    partition, tokenOut);
    if (result != ATA_HD_REGISTRY_SUCCESS) {
        (void)ATAHDRegistryClose(&ata_hd_core, unit, partition);
        return result;
    }
    ++ata_hd_units[unit].ioCount;
    return ATA_HD_REGISTRY_SUCCESS;
}

BOOL
ata_hd_async_token(void *pending, ATAHDAsyncToken *tokenOut)
{
    int result;

    if (pending == NULL || tokenOut == NULL || !ata_hd_registry_ready ||
        ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    result = ATAHDAsyncTokenForPending(&ata_hd_async_tokens, pending,
                                       tokenOut);
    [ata_hd_lock unlock];
    return result == ATA_HD_REGISTRY_SUCCESS ? YES : NO;
}

BOOL
ata_hd_async_claim(ATAHDAsyncToken token)
{
    int result;

    if (!ata_hd_registry_ready || ata_hd_lock == nil)
        return NO;
    [ata_hd_lock lock];
    result = ATAHDAsyncTokenClaim(&ata_hd_async_tokens, token);
    [ata_hd_lock unlock];
    return result == ATA_HD_REGISTRY_SUCCESS ? YES : NO;
}

void
ata_hd_async_complete(ATAHDAsyncToken token)
{
    unsigned int unit;
    unsigned int partition;
    int result;

    if (!ata_hd_registry_ready || ata_hd_lock == nil)
        return;
    [ata_hd_lock lock];
    result = ATAHDAsyncTokenRelease(&ata_hd_async_tokens, token, &unit,
                                    &partition);
    if (result == ATA_HD_REGISTRY_SUCCESS) {
        if (ata_hd_units[unit].ioCount != 0)
            --ata_hd_units[unit].ioCount;
        (void)ATAHDRegistryClose(&ata_hd_core, unit, partition);
    }
    [ata_hd_lock unlock];
}

static int
ata_hd_ioctl(dev_t dev, u_long cmd, caddr_t data, int flag,
             struct proc *proc)
{
    unsigned int unit;
    IODevAndIdInfo *map;
    ata_hd_ioctl_fn transportIoctl;
    id disk;
    IOReturn ioResult;
    int blockCount;
    int index;
    int result;

    [ata_hd_lock lock];
    if (!ata_hd_valid_dev_locked(dev) ||
        ata_hd_presence_for_dev_locked(dev) == NULL ||
        *ata_hd_presence_for_dev_locked(dev) == 0) {
        [ata_hd_lock unlock];
        return ENXIO;
    }

    unit = IO_DISK_UNIT(dev);
    map = &ata_hd_maps[unit];
    switch (cmd) {
    case DKIOCSFORMAT:
    case DKIOCGFORMAT:
    case DKIOCGLABEL:
    case DKIOCSLABEL:
        disk = map->partitionId[0];
        break;

    case DKIOCINFO:
    case DKIOCBLKSIZE:
    case DKIOCNUMBLKS:
        disk = (id)ATAHDRegistryOwner(&ata_hd_core, unit);
        break;

    default:
        disk = (id)ATAHDRegistryOwner(&ata_hd_core, unit);
        transportIoctl = ata_hd_units[unit].transportIoctl;
        [ata_hd_lock unlock];
        if (disk == nil) {
            return ENXIO;
        }
        if (transportIoctl == NULL) {
            return EINVAL;
        }
        return transportIoctl(disk, dev, (unsigned int)cmd,
                              data, flag, proc);
    }

    [ata_hd_lock unlock];
    if (disk == nil) {
        return ENXIO;
    }

    ioResult = IO_R_SUCCESS;
    switch (cmd) {
    case DKIOCSFORMAT:
        ioResult = [disk setFormatted:*(u_int *)data];
        break;

    case DKIOCGFORMAT:
        *(int *)data = [disk isFormatted];
        break;

    case DKIOCGLABEL:
    {
        struct disk_label *label;

        label = (struct disk_label *)IOMalloc(sizeof(*label));
        if (label == NULL)
            return ENOMEM;
        ioResult = [disk readLabel:label];
        if (ioResult == IO_R_SUCCESS)
            *(struct disk_label *)data = *label;
        IOFree(label, sizeof(*label));
        break;
    }

    case DKIOCSLABEL:
    {
        struct disk_label *label;

        label = (struct disk_label *)IOMalloc(sizeof(*label));
        if (label == NULL)
            return ENOMEM;
        *label = *(struct disk_label *)data;
        ioResult = [disk writeLabel:label];
        IOFree(label, sizeof(*label));
        break;
    }

    case DKIOCINFO:
    {
        struct drive_info info;

        bzero((char *)&info, sizeof(info));
        strcpy(info.di_name, [disk driveName]);
        info.di_devblklen = [disk blockSize];
        info.di_maxbcount = ATA_HD_MAX_PHYS_IO;
        if (info.di_devblklen != 0) {
            blockCount = howmany(sizeof(struct disk_label),
                                 info.di_devblklen);
        } else {
            blockCount = 0;
        }
        for (index = 0; index < NLABELS; ++index)
            info.di_label_blkno[index] = blockCount * index;
        *(struct drive_info *)data = info;
        break;
    }

    case DKIOCBLKSIZE:
        *(int *)data = [disk blockSize];
        break;

    case DKIOCNUMBLKS:
        *(int *)data = [disk diskSize];
        break;
    }

    result = 0;
    if (ioResult != IO_R_SUCCESS)
        result = [disk errnoFromReturn:ioResult];
    return result;
}

static int
ata_hd_size(dev_t dev)
{
    id disk;
    int blockSize;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil || ata_hd_presence_for_dev_locked(dev) == NULL ||
        *ata_hd_presence_for_dev_locked(dev) == 0) {
        [ata_hd_lock unlock];
        return -1;
    }
    [ata_hd_lock unlock];
    blockSize = [disk blockSize];
    return blockSize;
}

static unsigned
ata_hd_minphys(struct buf *bp)
{
    if (bp->b_bcount > ATA_HD_MAX_PHYS_IO)
        bp->b_bcount = ATA_HD_MAX_PHYS_IO;
    return bp->b_bcount;
}
