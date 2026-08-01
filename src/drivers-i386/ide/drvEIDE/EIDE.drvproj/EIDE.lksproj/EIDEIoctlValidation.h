#ifndef _EIDE_IOCTL_VALIDATION_H_
#define _EIDE_IOCTL_VALIDATION_H_

#define EIDE_IOCTL_CMD_RESTORE          0x10
#define EIDE_IOCTL_CMD_READ             0x20
#define EIDE_IOCTL_CMD_WRITE            0x30
#define EIDE_IOCTL_CMD_READ_VERIFY      0x40
#define EIDE_IOCTL_CMD_SEEK             0x70
#define EIDE_IOCTL_CMD_DIAGNOSE         0x90
#define EIDE_IOCTL_CMD_SET_PARAMS       0x91
#define EIDE_IOCTL_CMD_READ_MULTIPLE    0xc4
#define EIDE_IOCTL_CMD_WRITE_MULTIPLE   0xc5
#define EIDE_IOCTL_CMD_SET_MULTIPLE     0xc6
#define EIDE_IOCTL_CMD_READ_DMA         0xc8
#define EIDE_IOCTL_CMD_WRITE_DMA        0xca
#define EIDE_IOCTL_CMD_IDENTIFY         0xec

#define EIDE_IOCTL_MAX_BLOCKS           256U
#define EIDE_IOCTL_IDENTIFY_BYTES       512U

int EIDEIoctlPrepareTransfer(unsigned int command, unsigned int block,
                             unsigned int blockCount,
                             unsigned int blockSize,
                             unsigned int diskSize,
                             unsigned int *byteCount);
int EIDEIoctlValidateCompletion(unsigned int command,
                                unsigned int requestedBlocks,
                                unsigned int transferredBlocks,
                                unsigned int blockSize,
                                unsigned int *byteCount);

#endif
