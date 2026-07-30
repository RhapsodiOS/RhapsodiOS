#include "PPCDBDMAAudio.h"

#include <stddef.h>
#include <string.h>

#define PPC_DBDMA_MAX_DESCRIPTORS \
    (PPC_DBDMA_MAX_RING_BYTES / PPC_DBDMA_DESCRIPTOR_BYTES)
#define PPC_DBDMA_ALL_CONTROL \
    (kPPCDBDMARun | kPPCDBDMAPause | kPPCDBDMAFlushBit | \
     kPPCDBDMAWake | kPPCDBDMADead | kPPCDBDMAActive)

typedef char PPCDBDMAWordMustBe32Bits[(sizeof(unsigned int) == 4) ? 1 : -1];

typedef struct {
    unsigned long physical;
    unsigned long count;
    unsigned long interrupt;
} PPCDBDMAChunk;

static void store_be32(unsigned char *bytes, unsigned long value)
{
    bytes[0] = (unsigned char)(value >> 24);
    bytes[1] = (unsigned char)(value >> 16);
    bytes[2] = (unsigned char)(value >> 8);
    bytes[3] = (unsigned char)value;
}

static unsigned long load_be32(const unsigned char *bytes)
{
    return ((unsigned long)bytes[0] << 24) |
        ((unsigned long)bytes[1] << 16) |
        ((unsigned long)bytes[2] << 8) | (unsigned long)bytes[3];
}

static void store_descriptor(unsigned char *bytes, unsigned long operation,
    unsigned long address, unsigned long dependency, unsigned long result)
{
    store_be32(bytes, operation);
    store_be32(bytes + 4, address);
    store_be32(bytes + 8, dependency);
    store_be32(bytes + 12, result);
}

static int aligned_16(const void *pointer)
{
    return (((size_t)pointer & 15U) == 0U);
}

static PPCDBDMAStatus collect_chunks(PPCDBDMAChunk *chunks,
    unsigned long *chunkCount, PPCDBDMADirection direction,
    const unsigned char *buffer, unsigned long bufferBytes,
    unsigned long periodBytes, const PPCDBDMAOps *ops)
{
    unsigned long offset;
    unsigned long periodRemaining;
    unsigned long physical;
    unsigned long contiguous;
    unsigned long count;
    PPCDBDMAStatus status;
    (void)direction;
    offset = 0UL;
    *chunkCount = 0UL;
    while (offset < bufferBytes) {
        status = ops->translate(ops->context, buffer + offset, &physical,
            &contiguous);
        if (status != kPPCDBDMAOK || contiguous == 0UL)
            return status == kPPCDBDMAOK ? kPPCDBDMAUnmappable : status;
        count = bufferBytes - offset;
        if (count > contiguous)
            count = contiguous;
        if (count > PPC_DBDMA_MAX_TRANSFER)
            count = PPC_DBDMA_MAX_TRANSFER;
        periodRemaining = periodBytes - (offset % periodBytes);
        if (count > periodRemaining)
            count = periodRemaining;
        if (physical > 0xffffffffUL ||
            count - 1UL > 0xffffffffUL - physical)
            return kPPCDBDMAOverflow;
        if (*chunkCount >= PPC_DBDMA_MAX_DESCRIPTORS - 1UL)
            return kPPCDBDMAOversized;
        chunks[*chunkCount].physical = physical;
        chunks[*chunkCount].count = count;
        chunks[*chunkCount].interrupt =
            ((offset + count) % periodBytes == 0UL) ? 3UL : 0UL;
        ++*chunkCount;
        offset += count;
    }
    return kPPCDBDMAOK;
}

PPCDBDMAStatus PPCDBDMABuildRing(PPCDBDMARing *ring,
    const PPCDBDMAStorage *storage, PPCDBDMADirection direction,
    const void *buffer, unsigned long bufferBytes,
    unsigned long periodBytes, const PPCDBDMAOps *ops)
{
    PPCDBDMAChunk chunks[PPC_DBDMA_MAX_DESCRIPTORS - 1UL];
    PPCDBDMARing built;
    unsigned char encoded[PPC_DBDMA_MAX_RING_BYTES];
    unsigned long chunkCount;
    unsigned long index;
    unsigned long command;
    unsigned long operation;
    unsigned long needed;
    PPCDBDMAStatus status;
    if (ring == 0 || storage == 0 || buffer == 0 || ops == 0 ||
        ops->translate == 0 || bufferBytes == 0UL || periodBytes == 0UL ||
        periodBytes > bufferBytes || bufferBytes % periodBytes != 0UL ||
        (direction != kPPCDBDMAInput && direction != kPPCDBDMAOutput))
        return kPPCDBDMAInvalid;
    if (storage->logical == 0 || !aligned_16(storage->logical) ||
        (storage->physical & 15UL) != 0UL)
        return kPPCDBDMAMisaligned;
    if (storage->bytes > PPC_DBDMA_MAX_RING_BYTES)
        return kPPCDBDMAOversized;
    status = collect_chunks(chunks, &chunkCount, direction,
        (const unsigned char *)buffer, bufferBytes, periodBytes, ops);
    if (status != kPPCDBDMAOK)
        return status;
    needed = (chunkCount + 1UL) * PPC_DBDMA_DESCRIPTOR_BYTES;
    if (needed > storage->bytes)
        return kPPCDBDMAOversized;
    memset(encoded, 0, sizeof(encoded));
    command = direction == kPPCDBDMAInput ? 2UL : 0UL;
    for (index = 0UL; index < chunkCount; ++index) {
        operation = (command << 28) | (chunks[index].interrupt << 20) |
            chunks[index].count;
        store_descriptor(encoded + index * PPC_DBDMA_DESCRIPTOR_BYTES,
            operation, chunks[index].physical, 0UL, 0UL);
    }
    operation = (6UL << 28) | (3UL << 18);
    store_descriptor(encoded + chunkCount * PPC_DBDMA_DESCRIPTOR_BYTES,
        operation, 0UL, storage->physical, 0UL);
    memset(&built, 0, sizeof(built));
    built.descriptors = (unsigned char *)storage->logical;
    built.descriptorPhysical = storage->physical;
    built.storageBytes = storage->bytes;
    built.descriptorCount = chunkCount + 1UL;
    built.dataDescriptorCount = chunkCount;
    built.direction = direction;
    built.state = kPPCDBDMAReady;
    memcpy(storage->logical, encoded, (size_t)needed);
    *ring = built;
    return kPPCDBDMAOK;
}

PPCDBDMAStatus PPCDBDMALoadDescriptor(const PPCDBDMARing *ring,
    unsigned long index, PPCDBDMADescriptor *descriptor)
{
    const unsigned char *bytes;
    if (ring == 0 || descriptor == 0 || ring->descriptors == 0 ||
        index >= ring->descriptorCount)
        return kPPCDBDMAInvalid;
    bytes = ring->descriptors + index * PPC_DBDMA_DESCRIPTOR_BYTES;
    descriptor->operation = load_be32(bytes);
    descriptor->address = load_be32(bytes + 4);
    descriptor->dependency = load_be32(bytes + 8);
    descriptor->result = load_be32(bytes + 12);
    return kPPCDBDMAOK;
}

PPCDBDMAStatus PPCDBDMAServiceCompletions(PPCDBDMARing *ring,
    PPCDBDMACompletion *completion)
{
    PPCDBDMACompletion captured;
    PPCDBDMADescriptor descriptor;
    unsigned long status;
    unsigned long residual;
    unsigned long requested;
    unsigned char *result;
    if (ring == 0 || completion == 0 || ring->descriptors == 0 ||
        ring->dataDescriptorCount == 0UL)
        return kPPCDBDMAInvalid;
    memset(&captured, 0, sizeof(captured));
    while (captured.descriptors < ring->dataDescriptorCount) {
        if (PPCDBDMALoadDescriptor(ring, ring->consumer, &descriptor) !=
            kPPCDBDMAOK)
            return kPPCDBDMAInvalid;
        status = descriptor.result >> 16;
        residual = descriptor.result & 0xffffUL;
        if (status == 0UL)
            break;
        requested = descriptor.operation & 0xffffUL;
        captured.lastStatus = status;
        captured.lastResidual = residual;
        ++captured.descriptors;
        if (residual > requested || (status & kPPCDBDMADead) != 0UL) {
            captured.fault = 1;
            ring->faultStatus = status;
            ring->state = kPPCDBDMAFaulted;
        } else {
            captured.bytes += requested - residual;
        }
        result = ring->descriptors +
            ring->consumer * PPC_DBDMA_DESCRIPTOR_BYTES + 12;
        store_be32(result, 0UL);
        ++ring->consumer;
        if (ring->consumer == ring->dataDescriptorCount)
            ring->consumer = 0UL;
        if (captured.fault)
            break;
    }
    captured.spurious = captured.descriptors == 0UL;
    *completion = captured;
    return captured.fault ? kPPCDBDMAFault : kPPCDBDMAOK;
}

unsigned long PPCDBDMASetControl(unsigned long mask)
{
    return mask | (mask << 16);
}

unsigned long PPCDBDMAClearControl(unsigned long mask)
{
    return mask << 16;
}

static int valid_register_ops(const PPCDBDMAOps *ops)
{
    return ops != 0 && ops->readRegister != 0 &&
        ops->writeRegister != 0 && ops->now != 0;
}

static PPCDBDMATransition transition_result(PPCDBDMAStatus status,
    int sharedClockInvalidated)
{
    PPCDBDMATransition result;
    result.status = status;
    result.sharedClockInvalidated = sharedClockInvalidated;
    return result;
}

static PPCDBDMAStatus wait_clear(const PPCDBDMAOps *ops,
    unsigned long mask, unsigned long deadline)
{
    unsigned long status;
    for (;;) {
        if (ops->now(ops->registerContext) >= deadline)
            return kPPCDBDMATimeout;
        status = ops->readRegister(ops->registerContext,
            kPPCDBDMARegStatus);
        if ((status & mask) == 0UL)
            return kPPCDBDMAOK;
    }
}

PPCDBDMATransition PPCDBDMAStartRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || ring->state != kPPCDBDMAReady ||
        !valid_register_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(PPC_DBDMA_ALL_CONTROL));
    status = wait_clear(ops, kPPCDBDMAActive, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 1);
    }
    ops->writeRegister(ops->registerContext, kPPCDBDMARegCommandPtr,
        ring->descriptorPhysical);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMASetControl(kPPCDBDMARun | kPPCDBDMAWake));
    ring->state = kPPCDBDMARunning;
    return transition_result(kPPCDBDMAOK, 0);
}

PPCDBDMATransition PPCDBDMAStopRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || ring->state != kPPCDBDMARunning ||
        !valid_register_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(kPPCDBDMARun) |
        PPCDBDMASetControl(kPPCDBDMAFlushBit));
    status = wait_clear(ops, kPPCDBDMAActive | kPPCDBDMAFlushBit,
        deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 1);
    }
    ring->state = kPPCDBDMAReady;
    return transition_result(kPPCDBDMAOK, 0);
}

PPCDBDMATransition PPCDBDMAFlushRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || ring->state != kPPCDBDMARunning ||
        !valid_register_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMASetControl(kPPCDBDMAFlushBit));
    status = wait_clear(ops, kPPCDBDMAFlushBit, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 1);
    }
    return transition_result(kPPCDBDMAOK, 0);
}

PPCDBDMATransition PPCDBDMAResetRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || (ring->state != kPPCDBDMARunning &&
        ring->state != kPPCDBDMAFaulted) || !valid_register_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(PPC_DBDMA_ALL_CONTROL));
    status = wait_clear(ops, kPPCDBDMAActive, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 1);
    }
    ring->state = kPPCDBDMAReady;
    ring->faultStatus = 0UL;
    return transition_result(kPPCDBDMAOK, 0);
}
