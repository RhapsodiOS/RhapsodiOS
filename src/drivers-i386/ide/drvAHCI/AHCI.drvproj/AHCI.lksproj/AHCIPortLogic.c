#include <limits.h>
#include <string.h>
#include "AHCIPortLogic.h"

static int ahci_power_of_two(unsigned int value)
{
    return value != 0 && (value & (value - 1U)) == 0;
}

static int ahci_translate_expected(AHCIPortTranslate translate,
                                   void *context,
                                   unsigned long virtualAddress,
                                   AHCIU32 expected)
{
    AHCIU32 physical;

    return translate(context, virtualAddress, &physical) &&
           physical == expected;
}

AHCIPortResult AHCIPortPrepareArena(unsigned long rawVirtual,
                                    unsigned int rawBytes,
                                    unsigned int pageBytes,
                                    AHCIPortTranslate translate,
                                    void *translateContext,
                                    AHCIPortArena *arena)
{
    AHCIU32 rawPhysical;
    AHCIU32 physicalBase;
    unsigned int adjustment;
    unsigned long virtualBase;
    unsigned int offsets[6];
    unsigned int i;

    if (rawVirtual == 0 || translate == 0 || arena == 0 ||
        pageBytes < 1024U || !ahci_power_of_two(pageBytes) ||
        rawBytes < AHCI_PORT_ARENA_USABLE_BYTES + pageBytes - 1U)
        return AHCI_PORT_BAD_ARGUMENT;
    if (!translate(translateContext, rawVirtual, &rawPhysical))
        return AHCI_PORT_ADDRESS_ERROR;
    adjustment = (pageBytes - (rawPhysical & (pageBytes - 1U))) &
                 (pageBytes - 1U);
    if (rawPhysical > UINT_MAX - adjustment ||
        rawVirtual > ULONG_MAX - adjustment)
        return AHCI_PORT_ADDRESS_ERROR;
    physicalBase = rawPhysical + adjustment;
    virtualBase = rawVirtual + adjustment;
    if ((physicalBase & (pageBytes - 1U)) != 0 ||
        (virtualBase & (pageBytes - 1U)) != 0 ||
        adjustment > rawBytes ||
        rawBytes - adjustment < AHCI_PORT_ARENA_USABLE_BYTES ||
        physicalBase > UINT_MAX - (AHCI_PORT_ARENA_USABLE_BYTES - 1U) ||
        virtualBase > ULONG_MAX - (AHCI_PORT_ARENA_USABLE_BYTES - 1U))
        return AHCI_PORT_ADDRESS_ERROR;

    offsets[0] = AHCI_PORT_COMMAND_LIST_OFFSET;
    offsets[1] = AHCI_PORT_COMMAND_LIST_OFFSET +
                 AHCI_PORT_COMMAND_LIST_BYTES - 1U;
    offsets[2] = AHCI_PORT_RECEIVED_FIS_OFFSET;
    offsets[3] = AHCI_PORT_RECEIVED_FIS_OFFSET +
                 AHCI_PORT_RECEIVED_FIS_BYTES - 1U;
    offsets[4] = AHCI_PORT_COMMAND_TABLE_OFFSET;
    offsets[5] = AHCI_PORT_COMMAND_TABLE_OFFSET +
                 AHCI_PORT_COMMAND_TABLE_BYTES - 1U;
    for (i = 0; i < 6U; ++i) {
        if (!ahci_translate_expected(translate, translateContext,
                                     virtualBase + offsets[i],
                                     physicalBase + offsets[i]))
            return AHCI_PORT_ADDRESS_ERROR;
    }
    if ((physicalBase & 1023U) != 0 ||
        ((physicalBase + AHCI_PORT_RECEIVED_FIS_OFFSET) & 255U) != 0 ||
        ((physicalBase + AHCI_PORT_COMMAND_TABLE_OFFSET) & 127U) != 0)
        return AHCI_PORT_ADDRESS_ERROR;

    arena->virtualBase = virtualBase;
    arena->physicalBase = physicalBase;
    arena->commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena->commandListBytes = AHCI_PORT_COMMAND_LIST_BYTES;
    arena->receivedFISOffset = AHCI_PORT_RECEIVED_FIS_OFFSET;
    arena->receivedFISBytes = AHCI_PORT_RECEIVED_FIS_BYTES;
    arena->commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    arena->commandTableBytes = AHCI_PORT_COMMAND_TABLE_BYTES;
    arena->usableBytes = AHCI_PORT_ARENA_USABLE_BYTES;
    return AHCI_PORT_SUCCESS;
}

static AHCIU32 ahci_port_read(const AHCIPortOps *ops, unsigned int port,
                              AHCIU32 reg)
{
    return ops->read(ops->context, AHCI_PORT_BASE(port) + reg);
}

static void ahci_port_write(const AHCIPortOps *ops, unsigned int port,
                            AHCIU32 reg, AHCIU32 value)
{
    ops->write(ops->context, AHCI_PORT_BASE(port) + reg, value);
    ops->barrier(ops->context);
}

static int ahci_wait(const AHCIPortOps *ops, unsigned int port,
                     AHCIU32 mask, int set, unsigned int timeout)
{
    AHCIU32 value;
    unsigned int waited;

    waited = 0;
    value = ahci_port_read(ops, port, AHCI_PX_CMD);
    while ((((value & mask) != 0) ? 1 : 0) != set && waited < timeout) {
        ops->delay(ops->context, AHCI_POLL_INTERVAL_MS);
        waited += AHCI_POLL_INTERVAL_MS;
        value = ahci_port_read(ops, port, AHCI_PX_CMD);
    }
    return (((value & mask) != 0) ? 1 : 0) == set;
}

static AHCIPortResult ahci_stop_fis(const AHCIPortOps *ops,
                                    unsigned int port)
{
    AHCIU32 command;

    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD, command & ~AHCI_PXCMD_FRE);
    return ahci_wait(ops, port, AHCI_PXCMD_FR, 0,
                     AHCI_ENGINE_TIMEOUT_MS) ?
        AHCI_PORT_SUCCESS : AHCI_PORT_ENGINE_TIMEOUT;
}

static void ahci_clear_port_errors(const AHCIPortOps *ops,
                                   unsigned int port)
{
    ahci_port_write(ops, port, AHCI_PX_IS, 0xffffffffU);
    ahci_port_write(ops, port, AHCI_PX_SERR, 0xffffffffU);
}

static int ahci_link_active(AHCIU32 ssts)
{
    return (ssts & AHCI_SSTS_DET_MASK) == AHCI_SSTS_DET_PRESENT &&
           (ssts & AHCI_SSTS_IPM_MASK) == AHCI_SSTS_IPM_ACTIVE;
}

static int ahci_wait_link(const AHCIPortOps *ops, unsigned int port)
{
    unsigned int waited;

    waited = 0;
    while (!ahci_link_active(ahci_port_read(ops, port, AHCI_PX_SSTS)) &&
           waited < AHCI_LINK_TIMEOUT_MS) {
        ops->delay(ops->context, AHCI_POLL_INTERVAL_MS);
        waited += AHCI_POLL_INTERVAL_MS;
    }
    return ahci_link_active(ahci_port_read(ops, port, AHCI_PX_SSTS));
}

AHCIPortResult AHCIPortInitializeHardware(const AHCIPortOps *ops,
                                          unsigned int port,
                                          AHCIU32 capabilities,
                                          const AHCIPortArena *arena,
                                          AHCIDeviceKind *kind)
{
    AHCIU32 command;
    AHCIU32 ssts;
    AHCIU32 sctl;

    if (ops == 0 || ops->read == 0 || ops->write == 0 || ops->delay == 0 ||
        ops->barrier == 0 || arena == 0 || kind == 0 || port >= 32U)
        return AHCI_PORT_BAD_ARGUMENT;
    *kind = AHCI_DEVICE_NONE;

    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD, command & ~AHCI_PXCMD_ST);
    if (!ahci_wait(ops, port, AHCI_PXCMD_CR, 0,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;
    if (ahci_stop_fis(ops, port) != AHCI_PORT_SUCCESS)
        return AHCI_PORT_ENGINE_TIMEOUT;

    ahci_port_write(ops, port, AHCI_PX_CLB,
                    arena->physicalBase + arena->commandListOffset);
    ahci_port_write(ops, port, AHCI_PX_CLBU, 0);
    ahci_port_write(ops, port, AHCI_PX_FB,
                    arena->physicalBase + arena->receivedFISOffset);
    ahci_port_write(ops, port, AHCI_PX_FBU, 0);
    ahci_clear_port_errors(ops, port);

    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    if ((command & AHCI_PXCMD_CPD) != 0)
        command |= AHCI_PXCMD_POD;
    if ((capabilities & AHCI_CAP_SSS) != 0)
        command |= AHCI_PXCMD_SUD;
    ahci_port_write(ops, port, AHCI_PX_CMD, command | AHCI_PXCMD_FRE);
    if (!ahci_wait(ops, port, AHCI_PXCMD_FR, 1,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;

    ssts = ahci_port_read(ops, port, AHCI_PX_SSTS);
    if (!ahci_link_active(ssts) && (ssts & AHCI_SSTS_DET_MASK) != 0) {
        sctl = ahci_port_read(ops, port, AHCI_PX_SCTL);
        ahci_port_write(ops, port, AHCI_PX_SCTL,
                        (sctl & ~AHCI_SCTL_DET_MASK) |
                        AHCI_SCTL_DET_COMRESET);
        ops->delay(ops->context, AHCI_COMRESET_ASSERT_MS);
        ahci_port_write(ops, port, AHCI_PX_SCTL,
                        sctl & ~AHCI_SCTL_DET_MASK);
        if (!ahci_wait_link(ops, port)) {
            if (ahci_stop_fis(ops, port) != AHCI_PORT_SUCCESS)
                return AHCI_PORT_ENGINE_TIMEOUT;
            ahci_clear_port_errors(ops, port);
            ahci_port_write(ops, port, AHCI_PX_IE,
                            AHCI_PORT_INITIAL_IE_MASK);
            return AHCI_PORT_SUCCESS;
        }
        ahci_clear_port_errors(ops, port);
        ssts = ahci_port_read(ops, port, AHCI_PX_SSTS);
    }
    if (!ahci_link_active(ssts)) {
        if (ahci_stop_fis(ops, port) != AHCI_PORT_SUCCESS)
            return AHCI_PORT_ENGINE_TIMEOUT;
        ahci_port_write(ops, port, AHCI_PX_IE, AHCI_PORT_INITIAL_IE_MASK);
        return AHCI_PORT_SUCCESS;
    }

    *kind = AHCIClassifyPort(ssts,
                             ahci_port_read(ops, port, AHCI_PX_SIG));
    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD, command | AHCI_PXCMD_ST);
    if (!ahci_wait(ops, port, AHCI_PXCMD_CR, 1,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;
    ahci_port_write(ops, port, AHCI_PX_IE, AHCI_PORT_INITIAL_IE_MASK);
    return AHCI_PORT_SUCCESS;
}

AHCIPortResult AHCIPortStopHardware(const AHCIPortOps *ops,
                                    unsigned int port)
{
    AHCIU32 command;

    if (ops == 0 || ops->read == 0 || ops->write == 0 || ops->delay == 0 ||
        ops->barrier == 0 || port >= 32U)
        return AHCI_PORT_BAD_ARGUMENT;
    ahci_port_write(ops, port, AHCI_PX_IE, 0);
    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD, command & ~AHCI_PXCMD_ST);
    if (!ahci_wait(ops, port, AHCI_PXCMD_CR, 0,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;
    if (ahci_stop_fis(ops, port) != AHCI_PORT_SUCCESS)
        return AHCI_PORT_ENGINE_TIMEOUT;
    ahci_clear_port_errors(ops, port);
    return AHCI_PORT_SUCCESS;
}

AHCIPortResult AHCIPortRecoverHardware(const AHCIPortOps *ops,
                                       unsigned int port,
                                       const AHCIPortArena *arena)
{
    AHCIPortResult result;
    AHCIU32 sctl;
    AHCIU32 command;

    if (arena == 0)
        return AHCI_PORT_BAD_ARGUMENT;
    result = AHCIPortStopHardware(ops, port);
    if (result != AHCI_PORT_SUCCESS)
        return result;
    sctl = ahci_port_read(ops, port, AHCI_PX_SCTL);
    ahci_port_write(ops, port, AHCI_PX_SCTL,
                    (sctl & ~AHCI_SCTL_DET_MASK) |
                    AHCI_SCTL_DET_COMRESET);
    ops->delay(ops->context, AHCI_COMRESET_ASSERT_MS);
    ahci_port_write(ops, port, AHCI_PX_SCTL,
                    sctl & ~AHCI_SCTL_DET_MASK);
    if (!ahci_wait_link(ops, port))
        return AHCI_PORT_LINK_TIMEOUT;
    ahci_port_write(ops, port, AHCI_PX_CLB,
                    arena->physicalBase + arena->commandListOffset);
    ahci_port_write(ops, port, AHCI_PX_CLBU, 0);
    ahci_port_write(ops, port, AHCI_PX_FB,
                    arena->physicalBase + arena->receivedFISOffset);
    ahci_port_write(ops, port, AHCI_PX_FBU, 0);
    ahci_clear_port_errors(ops, port);
    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD,
                    command | AHCI_PXCMD_FRE);
    if (!ahci_wait(ops, port, AHCI_PXCMD_FR, 1,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;
    command = ahci_port_read(ops, port, AHCI_PX_CMD);
    ahci_port_write(ops, port, AHCI_PX_CMD,
                    command | AHCI_PXCMD_ST);
    if (!ahci_wait(ops, port, AHCI_PXCMD_CR, 1,
                   AHCI_ENGINE_TIMEOUT_MS))
        return AHCI_PORT_ENGINE_TIMEOUT;
    ahci_port_write(ops, port, AHCI_PX_IE, AHCI_PORT_INITIAL_IE_MASK);
    return AHCI_PORT_SUCCESS;
}

unsigned int AHCIPortCountImplemented(AHCIU32 pi)
{
    return AHCIPortCollectImplemented(pi, 0, 0);
}

int AHCIPortImplemented(AHCIU32 pi, unsigned int port)
{
    return port < 32U && (pi & (1U << port)) != 0;
}

unsigned int AHCIPortCollectImplemented(AHCIU32 pi, unsigned char *ports,
                                        unsigned int capacity)
{
    unsigned int count;
    unsigned int port;

    count = 0;
    for (port = 0; port < 32U; ++port) {
        if ((pi & (1U << port)) != 0) {
            if (ports != 0 && count < capacity)
                ports[count] = (unsigned char)port;
            ++count;
        }
    }
    return count;
}

int AHCIPortArenaMayRelease(AHCIPortResult stopResult)
{
    return stopResult == AHCI_PORT_SUCCESS;
}

AHCIPortResult AHCIPortBuildSegments(unsigned long virtualAddress,
                                     unsigned int length,
                                     unsigned int pageBytes,
                                     AHCIPortTranslate translate,
                                     void *translateContext,
                                     AHCISegment *segments,
                                     unsigned int capacity,
                                     unsigned int *segmentCount)
{
    unsigned int remaining;
    unsigned int count;
    unsigned int pageOffset;
    unsigned int chunk;
    AHCIU32 physical;

    if (virtualAddress == 0 || length == 0 ||
        length > AHCI_MAX_TRANSFER_BYTES ||
        !ahci_power_of_two(pageBytes) || translate == 0 || segments == 0 ||
        capacity == 0 || segmentCount == 0 ||
        virtualAddress > ULONG_MAX - (length - 1U))
        return AHCI_PORT_BAD_ARGUMENT;
    remaining = length;
    count = 0;
    while (remaining != 0) {
        pageOffset = (unsigned int)(virtualAddress & (pageBytes - 1U));
        chunk = pageBytes - pageOffset;
        if (chunk > remaining)
            chunk = remaining;
        if (!translate(translateContext, virtualAddress, &physical) ||
            physical > UINT_MAX - (chunk - 1U))
            return AHCI_PORT_ADDRESS_ERROR;
        if (count != 0 &&
            segments[count - 1U].address <=
                UINT_MAX - segments[count - 1U].length &&
            segments[count - 1U].address + segments[count - 1U].length ==
                physical) {
            if (segments[count - 1U].length > UINT_MAX - chunk)
                return AHCI_PORT_ADDRESS_ERROR;
            segments[count - 1U].length += chunk;
        } else {
            if (count == capacity)
                return AHCI_PORT_ADDRESS_ERROR;
            segments[count].address = physical;
            segments[count].length = chunk;
            ++count;
        }
        virtualAddress += chunk;
        remaining -= chunk;
    }
    *segmentCount = count;
    return AHCI_PORT_SUCCESS;
}

int AHCIPortBuildSlot(AHCICommandHeader *header, unsigned char *table,
                      AHCIU32 tablePhysical, const unsigned char fis[20],
                      const unsigned char *packet,
                      unsigned int packetLength,
                      const AHCISegment *segments,
                      unsigned int segmentCount,
                      unsigned int transferBytes,
                      unsigned char write, unsigned char atapi)
{
    AHCIPRDTEntry *prd;
    int prdtCount;

    if (header == 0 || table == 0 || fis == 0 ||
        (packetLength != 0 && packet == 0) || packetLength > 16U ||
        (atapi && packetLength == 0) || (!atapi && packetLength != 0) ||
        transferBytes > AHCI_MAX_TRANSFER_BYTES ||
        (transferBytes != 0 && (segments == 0 || segmentCount == 0)))
        return 0;
    memset(table, 0, AHCI_PORT_COMMAND_TABLE_BYTES);
    memcpy(table, fis, 20U);
    if (packetLength != 0)
        memcpy(table + 64U, packet, packetLength);
    prdtCount = 0;
    if (transferBytes != 0) {
        prd = (AHCIPRDTEntry *)(table +
                               AHCI_PORT_COMMAND_TABLE_HEADER_BYTES);
        prdtCount = AHCIBuildPRDT(prd, 32U, segments, segmentCount,
                                  transferBytes);
        if (prdtCount <= 0)
            return 0;
    }
    AHCIInitCommandHeader(header, tablePhysical,
                          (unsigned int)prdtCount, write, atapi);
    return header->ctba == tablePhysical && header->ctbau == 0;
}
