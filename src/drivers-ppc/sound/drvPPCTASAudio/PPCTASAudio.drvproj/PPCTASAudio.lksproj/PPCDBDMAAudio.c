#include "PPCDBDMAAudio.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define PPC_DBDMA_MAX_DESCRIPTORS \
    (PPC_DBDMA_MAX_RING_BYTES / PPC_DBDMA_DESCRIPTOR_BYTES)
#define PPC_DBDMA_ALL_CONTROL \
    (kPPCDBDMARun | kPPCDBDMAPause | kPPCDBDMAFlushBit | \
     kPPCDBDMAWake | kPPCDBDMADead | kPPCDBDMAActive)

typedef char PPCDBDMAWordMustBe32Bits[(sizeof(unsigned int) == 4) ? 1 : -1];

static void store_le32(unsigned char *bytes, unsigned long value)
{
    bytes[0] = (unsigned char)value;
    bytes[1] = (unsigned char)(value >> 8);
    bytes[2] = (unsigned char)(value >> 16);
    bytes[3] = (unsigned char)(value >> 24);
}

static unsigned long load_le32(const unsigned char *bytes)
{
    return (unsigned long)bytes[0] |
        ((unsigned long)bytes[1] << 8) |
        ((unsigned long)bytes[2] << 16) |
        ((unsigned long)bytes[3] << 24);
}

static void store_descriptor(unsigned char *bytes, unsigned long operation,
    unsigned long address, unsigned long dependency, unsigned long result)
{
    store_le32(bytes, operation);
    store_le32(bytes + 4, address);
    store_le32(bytes + 8, dependency);
    store_le32(bytes + 12, result);
}

static int aligned_16(const void *pointer)
{
    return (((size_t)pointer & 15U) == 0U);
}

static int ranges_overlap(const void *first, unsigned long firstBytes,
    const void *second, unsigned long secondBytes)
{
    size_t a;
    size_t b;
    a = (size_t)first;
    b = (size_t)second;
    if (a <= b)
        return b - a < (size_t)firstBytes;
    return a - b < (size_t)secondBytes;
}

PPCDBDMAStatus PPCDBDMABuildRing(PPCDBDMARing *ring,
    const PPCDBDMAStorage *storage, PPCDBDMADirection direction,
    const void *buffer, unsigned long bufferBytes,
    unsigned long periodBytes, const PPCDBDMAOps *ops)
{
    PPCDBDMARing built;
    unsigned char *encoded;
    unsigned long chunkCount;
    unsigned long offset;
    unsigned long periodRemaining;
    unsigned long physical;
    unsigned long contiguous;
    unsigned long count;
    unsigned long command;
    unsigned long operation;
    unsigned long needed;
    PPCDBDMAStatus status;
    if (ring == 0 || storage == 0 || buffer == 0 || ops == 0 ||
        ops->translate == 0 || bufferBytes == 0UL || periodBytes == 0UL ||
        periodBytes > bufferBytes || bufferBytes % periodBytes != 0UL ||
        (direction != kPPCDBDMAInput && direction != kPPCDBDMAOutput))
        return kPPCDBDMAInvalid;
    if (storage->logical == 0 || storage->scratch == 0)
        return kPPCDBDMAInvalid;
    if (!aligned_16(storage->logical) || !aligned_16(storage->scratch) ||
        (storage->physical & 15UL) != 0UL)
        return kPPCDBDMAMisaligned;
    if (storage->bytes > PPC_DBDMA_MAX_RING_BYTES)
        return kPPCDBDMAOversized;
    if (ranges_overlap(storage->logical, storage->bytes, storage->scratch,
        storage->scratchBytes))
        return kPPCDBDMAInvalid;
    encoded = (unsigned char *)storage->scratch;
    chunkCount = 0UL;
    offset = 0UL;
    command = direction == kPPCDBDMAInput ? 2UL : 0UL;
    while (offset < bufferBytes) {
        status = ops->translate(ops->context,
            (const unsigned char *)buffer + offset, &physical, &contiguous);
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
        needed = (chunkCount + 2UL) * PPC_DBDMA_DESCRIPTOR_BYTES;
        if (needed > storage->bytes || needed > storage->scratchBytes ||
            chunkCount >= PPC_DBDMA_MAX_DESCRIPTORS - 1UL)
            return kPPCDBDMAOversized;
        operation = (command << 28) |
            ((((offset + count) % periodBytes == 0UL) ? 3UL : 0UL) << 20) |
            count;
        store_descriptor(encoded + chunkCount * PPC_DBDMA_DESCRIPTOR_BYTES,
            operation, physical, 0UL, 0UL);
        ++chunkCount;
        offset += count;
    }
    needed = (chunkCount + 1UL) * PPC_DBDMA_DESCRIPTOR_BYTES;
#if ULONG_MAX > 0xffffffffUL
    if (storage->physical > 0xffffffffUL)
        return kPPCDBDMAOverflow;
#endif
    if (needed - 1UL > 0xffffffffUL - storage->physical)
        return kPPCDBDMAOverflow;
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
    descriptor->operation = load_le32(bytes);
    descriptor->address = load_le32(bytes + 4);
    descriptor->dependency = load_le32(bytes + 8);
    descriptor->result = load_le32(bytes + 12);
    return kPPCDBDMAOK;
}

static int valid_coherency_ops(const PPCDBDMAOps *ops)
{
    return ops != 0 && ops->publish != 0 && ops->invalidate != 0 &&
        ops->barrier != 0;
}

PPCDBDMAStatus PPCDBDMAServiceCompletions(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, PPCDBDMACompletion *completion)
{
    PPCDBDMACompletion captured;
    PPCDBDMADescriptor descriptor;
    unsigned long status;
    unsigned long residual;
    unsigned long requested;
    unsigned char *result;
    unsigned long originalResult;
    PPCDBDMAStatus coherencyStatus;
    if (ring == 0 || completion == 0 || ring->descriptors == 0 ||
        ring->dataDescriptorCount == 0UL || !valid_coherency_ops(ops))
        return kPPCDBDMAInvalid;
    memset(&captured, 0, sizeof(captured));
    coherencyStatus = ops->invalidate(ops->coherencyContext,
        ring->descriptors,
        ring->descriptorCount * PPC_DBDMA_DESCRIPTOR_BYTES);
    if (coherencyStatus != kPPCDBDMAOK)
        return coherencyStatus;
    coherencyStatus = ops->barrier(ops->coherencyContext);
    if (coherencyStatus != kPPCDBDMAOK)
        return coherencyStatus;
    while (captured.descriptors < ring->dataDescriptorCount) {
        if (PPCDBDMALoadDescriptor(ring, ring->consumer, &descriptor) !=
            kPPCDBDMAOK)
            return kPPCDBDMAInvalid;
        status = descriptor.result >> 16;
        residual = descriptor.result & 0xffffUL;
        if ((status & kPPCDBDMADead) != 0UL) {
            captured.lastStatus = status;
            captured.lastResidual = residual;
            ++captured.descriptors;
            captured.fault = 1;
            ring->faultStatus = status;
            ring->state = kPPCDBDMAFaulted;
            break;
        }
        if ((status & kPPCDBDMAActive) == 0UL)
            break;
        requested = descriptor.operation & 0xffffUL;
        captured.lastStatus = status;
        captured.lastResidual = residual;
        ++captured.descriptors;
        if (residual > requested) {
            captured.fault = 1;
            ring->faultStatus = status;
            ring->state = kPPCDBDMAFaulted;
            break;
        }
        captured.bytes += requested - residual;
        result = ring->descriptors +
            ring->consumer * PPC_DBDMA_DESCRIPTOR_BYTES + 12;
        originalResult = descriptor.result;
        store_le32(result, 0UL);
        coherencyStatus = ops->publish(ops->coherencyContext, result, 4UL);
        if (coherencyStatus != kPPCDBDMAOK) {
            store_le32(result, originalResult);
            ring->state = kPPCDBDMAFaulted;
            ring->faultStatus = status;
            return coherencyStatus;
        }
        coherencyStatus = ops->barrier(ops->coherencyContext);
        if (coherencyStatus != kPPCDBDMAOK) {
            ring->state = kPPCDBDMAFaulted;
            ring->faultStatus = status;
            return coherencyStatus;
        }
        ++ring->consumer;
        if (ring->consumer == ring->dataDescriptorCount)
            ring->consumer = 0UL;
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

static int deadline_expired(const PPCDBDMAOps *ops, unsigned long deadline)
{
    return deadline == 0UL ||
        ops->now(ops->registerContext) >= deadline;
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
        if (deadline_expired(ops, deadline))
            return kPPCDBDMATimeout;
        status = ops->readRegister(ops->registerContext,
            kPPCDBDMARegStatus);
        if (deadline_expired(ops, deadline))
            return kPPCDBDMATimeout;
        if ((status & mask) == 0UL)
            return kPPCDBDMAOK;
    }
}

PPCDBDMATransition PPCDBDMAStartRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || ring->state != kPPCDBDMAReady ||
        !valid_register_ops(ops) || !valid_coherency_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    if (deadline_expired(ops, deadline))
        return transition_result(kPPCDBDMATimeout, 0);
    status = ops->publish(ops->coherencyContext, ring->descriptors,
        ring->descriptorCount * PPC_DBDMA_DESCRIPTOR_BYTES);
    if (status == kPPCDBDMAOK)
        status = ops->barrier(ops->coherencyContext);
    if (status != kPPCDBDMAOK)
        return transition_result(status, 0);
    if (deadline_expired(ops, deadline))
        return transition_result(kPPCDBDMATimeout, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(PPC_DBDMA_ALL_CONTROL));
    status = wait_clear(ops, kPPCDBDMAActive, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 0);
    }
    if (deadline_expired(ops, deadline)) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(kPPCDBDMATimeout, 0);
    }
    ops->writeRegister(ops->registerContext, kPPCDBDMARegCommandPtr,
        ring->descriptorPhysical);
    if (deadline_expired(ops, deadline)) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(kPPCDBDMATimeout, 0);
    }
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
    if (deadline_expired(ops, deadline))
        return transition_result(kPPCDBDMATimeout, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(kPPCDBDMARun) |
        PPCDBDMASetControl(kPPCDBDMAFlushBit));
    status = wait_clear(ops, kPPCDBDMAActive | kPPCDBDMAFlushBit,
        deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 0);
    }
    ring->state = kPPCDBDMAStopped;
    return transition_result(kPPCDBDMAOK, 0);
}

PPCDBDMATransition PPCDBDMAFlushRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    if (ring == 0 || ring->state != kPPCDBDMARunning ||
        !valid_register_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    if (deadline_expired(ops, deadline))
        return transition_result(kPPCDBDMATimeout, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMASetControl(kPPCDBDMAFlushBit));
    status = wait_clear(ops, kPPCDBDMAFlushBit, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 0);
    }
    return transition_result(kPPCDBDMAOK, 0);
}

PPCDBDMATransition PPCDBDMAResetRing(PPCDBDMARing *ring,
    const PPCDBDMAOps *ops, unsigned long deadline)
{
    PPCDBDMAStatus status;
    unsigned long index;
    if (ring == 0 || (ring->state != kPPCDBDMAStopped &&
        ring->state != kPPCDBDMAFaulted) || !valid_register_ops(ops) ||
        !valid_coherency_ops(ops))
        return transition_result(kPPCDBDMAInvalid, 0);
    if (deadline_expired(ops, deadline))
        return transition_result(kPPCDBDMATimeout, 0);
    ops->writeRegister(ops->registerContext, kPPCDBDMARegControl,
        PPCDBDMAClearControl(PPC_DBDMA_ALL_CONTROL));
    status = wait_clear(ops, kPPCDBDMAActive, deadline);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 0);
    }
    for (index = 0UL; index < ring->descriptorCount; ++index)
        store_le32(ring->descriptors +
            index * PPC_DBDMA_DESCRIPTOR_BYTES + 12UL, 0UL);
    status = ops->publish(ops->coherencyContext, ring->descriptors,
        ring->descriptorCount * PPC_DBDMA_DESCRIPTOR_BYTES);
    if (status == kPPCDBDMAOK)
        status = ops->barrier(ops->coherencyContext);
    if (status != kPPCDBDMAOK) {
        ring->state = kPPCDBDMAFaulted;
        return transition_result(status, 0);
    }
    ring->state = kPPCDBDMAReady;
    ring->faultStatus = 0UL;
    ring->consumer = 0UL;
    return transition_result(kPPCDBDMAOK, 0);
}
