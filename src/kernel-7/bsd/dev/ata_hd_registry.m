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
} ATAHDUnitState;

static ATAHDRegistryCore ata_hd_core;
static IODevAndIdInfo ata_hd_maps[ATA_HD_UNITS];
static ATAHDUnitState ata_hd_units[ATA_HD_UNITS];

/*
 * DriverKit configuration is serialized while the first disk class probes.
 * NXLock is a sleep lock and may cover IODisk calls which allocate or wait.
 */
static NXLock *ata_hd_lock = nil;
static BOOL ata_hd_initialized = NO;
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
static int ata_hd_core_error_to_errno(int error);

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
    unsigned int unit;
    unsigned int allocated;
    int requestedBlockMajor;
    int requestedRawMajor;

    if (!ata_hd_requested_majors(diskClass, deviceDescription,
                                 &requestedBlockMajor,
                                 &requestedRawMajor))
        return NO;
    if (requestedBlockMajor != ATA_HD_BLOCK_MAJOR ||
        requestedRawMajor != ATA_HD_RAW_MAJOR)
        return NO;

    if (ata_hd_lock == nil) {
        ata_hd_lock = [NXLock new];
        if (ata_hd_lock == nil)
            return NO;
    }

    [ata_hd_lock lock];

    if (ata_hd_initialized) {
        if (requestedBlockMajor == ata_hd_block_major &&
            requestedRawMajor == ata_hd_raw_major) {
            [diskClass setBlockMajor:ata_hd_block_major];
            [diskClass setCharacterMajor:ata_hd_raw_major];
            [ata_hd_lock unlock];
            return YES;
        }
        [ata_hd_lock unlock];
        return NO;
    }

    if ([diskClass addToCdevswFromDescription:deviceDescription
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
                                      putc:(IOSwitchFunc)eno_putc] != YES) {
        [ata_hd_lock unlock];
        return NO;
    }

    if ([diskClass addToBdevswFromDescription:deviceDescription
                                      open:(IOSwitchFunc)ata_hd_open
                                     close:(IOSwitchFunc)ata_hd_close
                                  strategy:(IOSwitchFunc)ata_hd_strategy
                                     ioctl:(IOSwitchFunc)ata_hd_ioctl
                                      dump:(IOSwitchFunc)eno_dump
                                     psize:(IOSwitchFunc)ata_hd_size
                                    isTape:FALSE] != YES) {
        [diskClass removeFromCdevsw];
        [ata_hd_lock unlock];
        return NO;
    }

    ata_hd_block_major = [diskClass blockMajor];
    ata_hd_raw_major = [diskClass characterMajor];
    if (ata_hd_block_major != requestedBlockMajor ||
        ata_hd_raw_major != requestedRawMajor) {
        [diskClass removeFromBdevsw];
        [diskClass removeFromCdevsw];
        ata_hd_block_major = -1;
        ata_hd_raw_major = -1;
        [ata_hd_lock unlock];
        return NO;
    }

    ATAHDRegistryCoreInit(&ata_hd_core);
    bzero((char *)ata_hd_maps, sizeof(ata_hd_maps));
    bzero((char *)ata_hd_units, sizeof(ata_hd_units));

    allocated = 0;
    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        ata_hd_units[unit].physbuf =
            (struct buf *)IOMalloc(sizeof(struct buf));
        if (ata_hd_units[unit].physbuf == NULL)
            break;
        bzero((char *)ata_hd_units[unit].physbuf, sizeof(struct buf));
        ++allocated;
    }

    if (allocated != ATA_HD_UNITS) {
        for (unit = 0; unit < allocated; ++unit) {
            IOFree(ata_hd_units[unit].physbuf, sizeof(struct buf));
            ata_hd_units[unit].physbuf = NULL;
        }
        [diskClass removeFromBdevsw];
        [diskClass removeFromCdevsw];
        ata_hd_block_major = -1;
        ata_hd_raw_major = -1;
        [ata_hd_lock unlock];
        return NO;
    }

    ata_hd_initialized = YES;
    [ata_hd_lock unlock];
    return YES;
}

int
ata_hd_register(id disk, ata_hd_ioctl_fn transportIoctl,
                IODevAndIdInfo **mapOut)
{
    IODevAndIdInfo *map;
    int unit;

    if (disk == nil || mapOut == NULL || ata_hd_lock == nil)
        return ATA_HD_REGISTRY_INVALID;

    [ata_hd_lock lock];
    if (!ata_hd_initialized) {
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
    *mapOut = map;

    [ata_hd_lock unlock];
    return unit;
}

IOReturn
ata_hd_unregister(unsigned int unit)
{
    int result;

    if (unit >= ATA_HD_UNITS || ata_hd_lock == nil)
        return IO_R_INVALID_ARG;

    [ata_hd_lock lock];
    if (!ata_hd_initialized) {
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
    [ata_hd_lock unlock];
    return IO_R_SUCCESS;
}

IODevAndIdInfo *
ata_hd_lookup(dev_t dev)
{
    IODevAndIdInfo *map;

    if (ata_hd_lock == nil)
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

static BOOL
ata_hd_valid_dev_locked(dev_t dev)
{
    unsigned int unit;
    unsigned int partition;
    int deviceMajor;

    if (!ata_hd_initialized)
        return NO;

    unit = IO_DISK_UNIT(dev);
    partition = IO_DISK_PART(dev);
    deviceMajor = major(dev);
    if (unit >= ATA_HD_UNITS || partition >= ATA_HD_PARTITIONS)
        return NO;
    if (deviceMajor != ata_hd_block_major &&
        deviceMajor != ata_hd_raw_major)
        return NO;
    return (ATAHDRegistryOwner(&ata_hd_core, unit) != NULL);
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
        return (id)ATAHDRegistryOwner(&ata_hd_core, unit);
    }
    return map->partitionId[partition];
}

static int
ata_hd_core_error_to_errno(int error)
{
    if (error == ATA_HD_BUSY || error == ATA_HD_REGISTRY_OVERFLOW)
        return EBUSY;
    if (error == ATA_HD_REGISTRY_NOT_FOUND ||
        error == ATA_HD_REGISTRY_INVALID)
        return ENXIO;
    return EINVAL;
}

static int
ata_hd_open(dev_t dev, int flag, int devtype, struct proc *proc)
{
    id disk;
    int result;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    if ([disk isDiskReady:NO]) {
        [ata_hd_lock unlock];
        return ENXIO;
    }

    result = ATAHDRegistryOpen(&ata_hd_core, IO_DISK_UNIT(dev),
                               IO_DISK_PART(dev));
    if (result != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        return ata_hd_core_error_to_errno(result);
    }

    if (IO_DISK_PART(dev) != ATA_HD_LIVE_PART) {
        if (major(dev) == ata_hd_block_major)
            [disk setBlockDeviceOpen:YES];
        else
            [disk setRawDeviceOpen:YES];
    }

    [ata_hd_lock unlock];
    return 0;
}

static int
ata_hd_close(dev_t dev, int flag, int devtype, struct proc *proc)
{
    id disk;
    int result;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    if (IO_DISK_PART(dev) != ATA_HD_LIVE_PART &&
        ![disk isInstanceOpen]) {
        [ata_hd_lock unlock];
        return ENXIO;
    }

    result = ATAHDRegistryClose(&ata_hd_core, IO_DISK_UNIT(dev),
                                IO_DISK_PART(dev));
    if (result != ATA_HD_REGISTRY_SUCCESS) {
        [ata_hd_lock unlock];
        return ata_hd_core_error_to_errno(result);
    }

    if (IO_DISK_PART(dev) != ATA_HD_LIVE_PART) {
        if (major(dev) == ata_hd_block_major)
            [disk setBlockDeviceOpen:NO];
        else
            [disk setRawDeviceOpen:NO];
    }

    [ata_hd_lock unlock];
    return 0;
}

static int
ata_hd_read(dev_t dev, struct uio *uiop, int ioflag)
{
    id disk;
    struct buf *physbuf;
    unsigned int blockSize;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    physbuf = ata_hd_units[IO_DISK_UNIT(dev)].physbuf;
    blockSize = [disk blockSize];
    [ata_hd_lock unlock];

    return physio((int (*)())ata_hd_strategy, physbuf, dev, B_READ,
                  ata_hd_minphys, uiop, blockSize);
}

static int
ata_hd_write(dev_t dev, struct uio *uiop, int ioflag)
{
    id disk;
    struct buf *physbuf;
    unsigned int blockSize;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil) {
        [ata_hd_lock unlock];
        return ENXIO;
    }
    physbuf = ata_hd_units[IO_DISK_UNIT(dev)].physbuf;
    blockSize = [disk blockSize];
    [ata_hd_lock unlock];

    return physio((int (*)())ata_hd_strategy, physbuf, dev, B_WRITE,
                  ata_hd_minphys, uiop, blockSize);
}

static void
ata_hd_strategy(struct buf *bp)
{
    id disk;
    IOReturn result;
    vm_task_t client;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(bp->b_dev);
    if (disk == nil) {
        bp->b_error = ENXIO;
        goto bad_locked;
    }

    if ((bp->b_flags & (B_PHYS | B_KERNSPACE)) == B_PHYS)
        client = IOVmTaskForBuf(bp);
    else
        client = IOVmTaskSelf();

    if ([disk blockSize] == 0) {
        bp->b_error = ENXIO;
        goto bad_locked;
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
        goto bad_locked;
    }

    [ata_hd_lock unlock];
    return;

bad_locked:
    bp->b_flags |= B_ERROR;
    [ata_hd_lock unlock];
    biodone(bp);
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
    if (!ata_hd_valid_dev_locked(dev)) {
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
        if (disk == nil) {
            [ata_hd_lock unlock];
            return ENXIO;
        }
        transportIoctl = ata_hd_units[unit].transportIoctl;
        if (transportIoctl == NULL) {
            [ata_hd_lock unlock];
            return EINVAL;
        }
        result = transportIoctl(disk, dev, (unsigned int)cmd,
                                data, flag, proc);
        [ata_hd_lock unlock];
        return result;
    }

    if (disk == nil) {
        [ata_hd_lock unlock];
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
        if (label == NULL) {
            [ata_hd_lock unlock];
            return ENOMEM;
        }
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
        if (label == NULL) {
            [ata_hd_lock unlock];
            return ENOMEM;
        }
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
    [ata_hd_lock unlock];
    return result;
}

static int
ata_hd_size(dev_t dev)
{
    id disk;
    int blockSize;

    [ata_hd_lock lock];
    disk = ata_hd_disk_for_dev_locked(dev);
    if (disk == nil) {
        [ata_hd_lock unlock];
        return -1;
    }
    blockSize = [disk blockSize];
    [ata_hd_lock unlock];
    return blockSize;
}

static unsigned
ata_hd_minphys(struct buf *bp)
{
    if (bp->b_bcount > ATA_HD_MAX_PHYS_IO)
        bp->b_bcount = ATA_HD_MAX_PHYS_IO;
    return bp->b_bcount;
}
