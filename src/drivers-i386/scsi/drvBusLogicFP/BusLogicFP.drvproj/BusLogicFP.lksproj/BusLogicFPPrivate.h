#ifndef _BUSLOGICFP_PRIVATE_H
#define _BUSLOGICFP_PRIVATE_H

#include "FlashPoint.h"

typedef unsigned long long blfp_u64;

/* 48-byte command record shared by executeCmdBuf: and the I/O thread. */
struct blfp_command_record {
    u32 command;                       /* 0 */
    void *request;                     /* 4 */
    void *dataBuffer;                  /* 8 */
    void *clientTask;                  /* 12 */
    int result;                        /* 16 */
    void *conditionLock;               /* 20 */
    struct sccb *sccb;                 /* 24 */
    u32 transferred;                   /* 28 */
    blfp_u64 timestamp;                /* 32 */
    struct sccb_queue_links queue;     /* 40 */
};

struct blfp_queue_head {
    struct sccb_queue_links links;
};

/* Compiler-independent mirror of BLFPController's runtime ivar tail. */
struct blfp_controller_abi {
    u8 inherited[0x244];
    u16 ioBase;
    u16 pad246;
    u32 irq;
    struct sccb_mgr_info *sccbMgr;
    void *sccbMgrRaw;
    struct sccb_card *cardHandle;
    struct blfp_queue_head sccbFreeList;
    struct blfp_queue_head commandQ;
    void *commandLock;
    struct blfp_queue_head outstandingQ;
    u32 outstandingCount;
    u32 maxQueueLen;
    u32 queueLenTotal;
    u32 totalCommands;
    u32 interruptPortKern;
    u8 ioThreadRunning;
    u8 pad289[3];
    u32 busType;
    u8 levelIRQ;
    u8 targetsPerBus;
    u8 tail[2];
};

#define BLFP_ABI_ASSERT(name, expr) typedef char blfp_abi_assert_##name[(expr) ? 1 : -1]
BLFP_ABI_ASSERT(command_size, sizeof(struct blfp_command_record) == 48);
BLFP_ABI_ASSERT(command_result, __builtin_offsetof(struct blfp_command_record, result) == 16);
BLFP_ABI_ASSERT(command_timestamp, __builtin_offsetof(struct blfp_command_record, timestamp) == 32);
BLFP_ABI_ASSERT(command_queue, __builtin_offsetof(struct blfp_command_record, queue) == 40);

#endif
