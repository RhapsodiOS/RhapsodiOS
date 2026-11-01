#include <errno.h>
#include <limits.h>

#include "EIDEIoctlValidation.h"

static int EIDEIoctlIsBuffered(unsigned int command)
{
    return command == EIDE_IOCTL_CMD_READ ||
           command == EIDE_IOCTL_CMD_WRITE ||
           command == EIDE_IOCTL_CMD_READ_MULTIPLE ||
           command == EIDE_IOCTL_CMD_WRITE_MULTIPLE ||
           command == EIDE_IOCTL_CMD_READ_DMA ||
           command == EIDE_IOCTL_CMD_WRITE_DMA;
}

static int EIDEIoctlRangeIsValid(unsigned int block,
                                 unsigned int blockCount,
                                 unsigned int diskSize)
{
    return block < diskSize && blockCount <= diskSize - block;
}

static int EIDEIoctlByteCount(unsigned int blockCount,
                              unsigned int blockSize,
                              unsigned int *byteCount)
{
    if (blockSize == 0 || blockCount > (unsigned int)INT_MAX / blockSize)
        return EINVAL;
    *byteCount = blockCount * blockSize;
    return 0;
}

int EIDEIoctlPrepareTransfer(unsigned int command, unsigned int block,
                             unsigned int blockCount,
                             unsigned int blockSize,
                             unsigned int diskSize,
                             unsigned int *byteCount)
{
    if (byteCount == 0)
        return EINVAL;
    *byteCount = 0;

    if (command == EIDE_IOCTL_CMD_IDENTIFY) {
        *byteCount = EIDE_IOCTL_IDENTIFY_BYTES;
        return 0;
    }
    if (EIDEIoctlIsBuffered(command)) {
        if (blockCount == 0 || blockCount > EIDE_IOCTL_MAX_BLOCKS ||
            !EIDEIoctlRangeIsValid(block, blockCount, diskSize))
            return EINVAL;
        return EIDEIoctlByteCount(blockCount, blockSize, byteCount);
    }
    if (command == EIDE_IOCTL_CMD_READ_VERIFY) {
        if (blockCount == 0 || blockCount > EIDE_IOCTL_MAX_BLOCKS ||
            !EIDEIoctlRangeIsValid(block, blockCount, diskSize))
            return EINVAL;
        return 0;
    }
    if (command == EIDE_IOCTL_CMD_SEEK)
        return EIDEIoctlRangeIsValid(block, 1, diskSize) ? 0 : EINVAL;
    if (command == EIDE_IOCTL_CMD_RESTORE ||
        command == EIDE_IOCTL_CMD_DIAGNOSE ||
        command == EIDE_IOCTL_CMD_SET_PARAMS ||
        command == EIDE_IOCTL_CMD_SET_MULTIPLE)
        return 0;
    return EINVAL;
}

int EIDEIoctlValidateCompletion(unsigned int command,
                                unsigned int requestedBlocks,
                                unsigned int transferredBlocks,
                                unsigned int blockSize,
                                unsigned int *byteCount)
{
    if (byteCount == 0)
        return EINVAL;
    *byteCount = 0;
    if (command == EIDE_IOCTL_CMD_IDENTIFY) {
        if (transferredBlocks > 1)
            return EINVAL;
        *byteCount = transferredBlocks * EIDE_IOCTL_IDENTIFY_BYTES;
        return 0;
    }
    if (!EIDEIoctlIsBuffered(command))
        return transferredBlocks <= requestedBlocks ? 0 : EINVAL;
    if (transferredBlocks > requestedBlocks)
        return EINVAL;
    return EIDEIoctlByteCount(transferredBlocks, blockSize, byteCount);
}
