#include "AHCIState.h"

int AHCIPIValid(unsigned int cap, unsigned int pi)
{
    unsigned int highestPort;
    unsigned int validMask;

    if (pi == 0)
        return 0;
    highestPort = cap & 0x1fU;
    if (highestPort == 31U)
        return 1;
    validMask = (1U << (highestPort + 1U)) - 1U;
    return (pi & ~validMask) == 0;
}

int AHCINextPort(unsigned int pi, int previous)
{
    int port;

    if (previous >= 31)
        return -1;
    if (previous < -1)
        previous = -1;
    for (port = previous + 1; port < 32; ++port) {
        if ((pi & (1U << (unsigned int)port)) != 0)
            return port;
    }
    return -1;
}

AHCIDeviceKind AHCIClassifyPort(unsigned int ssts, unsigned int sig)
{
    if ((ssts & 0x0000000fU) != 3U ||
        ((ssts >> 8) & 0x0000000fU) != 1U)
        return AHCI_DEVICE_NONE;
    if (sig == 0x00000101U)
        return AHCI_DEVICE_SATA;
    if (sig == 0xeb140101U)
        return AHCI_DEVICE_ATAPI;
    return AHCI_DEVICE_UNSUPPORTED;
}

int AHCICommandCompleted(unsigned int ci, unsigned int portIS)
{
    /* Completion follows CI; portIS is classified separately for recovery. */
    (void)portIS;
    return (ci & 0x00000001U) == 0;
}

AHCIRecovery AHCIRecoveryFor(unsigned int portIS, unsigned int serr,
                             unsigned char engineStopped,
                             unsigned char hbaResetAlreadyTried)
{
    unsigned int localError;

    localError = (portIS & AHCI_PXIS_RECOVERABLE_MASK) |
                 (serr & AHCI_PXSERR_ERROR_MASK);
    if (engineStopped == 0 || (portIS & AHCI_PXIS_FATAL_MASK) != 0)
        return hbaResetAlreadyTried ? AHCI_RECOVERY_OFFLINE :
                                      AHCI_RECOVERY_HBA;
    if (localError != 0)
        return AHCI_RECOVERY_PORT;
    return AHCI_RECOVERY_NONE;
}

void AHCICommandArbiterInit(AHCICommandArbiter *arbiter)
{
    if (arbiter == 0)
        return;
    arbiter->state = AHCI_COMMAND_IDLE;
    arbiter->generation = 0;
    arbiter->completions = 0;
}

unsigned int AHCICommandBegin(AHCICommandArbiter *arbiter)
{
    if (arbiter == 0 || arbiter->state == AHCI_COMMAND_PENDING)
        return 0;
    ++arbiter->generation;
    if (arbiter->generation == 0)
        ++arbiter->generation;
    arbiter->state = AHCI_COMMAND_PENDING;
    return arbiter->generation;
}

static int ahci_command_finish(AHCICommandArbiter *arbiter,
                               unsigned int generation,
                               AHCICommandState state)
{
    if (arbiter == 0 || arbiter->state != AHCI_COMMAND_PENDING ||
        generation == 0 || generation != arbiter->generation)
        return 0;
    arbiter->state = state;
    ++arbiter->completions;
    return 1;
}

int AHCICommandFinishIRQ(AHCICommandArbiter *arbiter,
                         unsigned int generation)
{
    return ahci_command_finish(arbiter, generation, AHCI_COMMAND_COMPLETE);
}

int AHCICommandFinishTimeout(AHCICommandArbiter *arbiter,
                             unsigned int generation)
{
    return ahci_command_finish(arbiter, generation,
                               AHCI_COMMAND_TIMED_OUT);
}

int AHCICommandAbort(AHCICommandArbiter *arbiter)
{
    if (arbiter == 0)
        return 0;
    return ahci_command_finish(arbiter, arbiter->generation,
                               AHCI_COMMAND_TIMED_OUT);
}

AHCICompletionResult AHCIClassifyCompletion(AHCICompletionSnapshot *snapshot,
                                             unsigned int requested)
{
    if (snapshot == 0)
        return AHCI_COMPLETION_ERROR;
    if (snapshot->transferred > requested)
        snapshot->transferred = requested;
    if ((snapshot->portIS & (AHCI_PXIS_RECOVERABLE_MASK |
                             AHCI_PXIS_FATAL_MASK)) != 0 ||
        (snapshot->serr & AHCI_PXSERR_ERROR_MASK) != 0 ||
        (snapshot->taskFile & 1U) != 0)
        return AHCI_COMPLETION_ERROR;
    if ((snapshot->commandIssue & 1U) != 0)
        return AHCI_COMPLETION_PENDING;
    return AHCI_COMPLETION_OK;
}

int AHCICommandTimeoutDue(const AHCICommandArbiter *arbiter,
                          unsigned long deadline, unsigned long now)
{
    if (arbiter == 0 || deadline == 0)
        return 0;
    return arbiter->state == AHCI_COMMAND_PENDING && now >= deadline;
}

AHCITimeoutAction AHCICommandTimeoutAction(
    const AHCICommandArbiter *arbiter, unsigned int armedGeneration,
    unsigned long deadline, unsigned long now)
{
    if (arbiter == 0 || arbiter->state != AHCI_COMMAND_PENDING)
        return AHCI_TIMEOUT_WAIT;
    if (armedGeneration != arbiter->generation)
        return AHCI_TIMEOUT_REARM;
    return AHCICommandTimeoutDue(arbiter, deadline, now) ?
           AHCI_TIMEOUT_EXPIRE : AHCI_TIMEOUT_WAIT;
}

int AHCIRecoveredKindValid(AHCIDeviceKind before, AHCIDeviceKind after)
{
    return before == after &&
           (after == AHCI_DEVICE_SATA || after == AHCI_DEVICE_ATAPI);
}

int AHCILocalRecoveryAllowed(int destroying, int controllerResetting)
{
    return !destroying && !controllerResetting;
}

void AHCIRecoveryGateInit(AHCIRecoveryGate *gate)
{
    if (gate == 0)
        return;
    gate->setupCount = 0;
    gate->resetAttempts = 0;
    gate->recovering = 0;
    gate->offline = 0;
}

int AHCIRecoveryGateBeginSubmission(AHCIRecoveryGate *gate)
{
    if (gate == 0 || gate->recovering || gate->offline)
        return 0;
    ++gate->setupCount;
    return 1;
}

void AHCIRecoveryGateEndSubmission(AHCIRecoveryGate *gate)
{
    if (gate != 0 && gate->setupCount != 0)
        --gate->setupCount;
}

int AHCIRecoveryGateCommitSubmission(AHCIRecoveryGate *gate)
{
    if (gate == 0 || gate->setupCount == 0)
        return 0;
    --gate->setupCount;
    return !gate->recovering && !gate->offline;
}

int AHCIRecoveryGateStart(AHCIRecoveryGate *gate)
{
    if (gate == 0 || gate->recovering || gate->offline)
        return 0;
    gate->recovering = 1;
    ++gate->resetAttempts;
    return 1;
}

int AHCIRecoveryGateDrained(const AHCIRecoveryGate *gate)
{
    return gate != 0 && gate->setupCount == 0;
}

void AHCIRecoveryGateComplete(AHCIRecoveryGate *gate, int success)
{
    if (gate == 0)
        return;
    gate->recovering = 0;
    if (!success)
        gate->offline = 1;
}

void AHCITimeoutChainInit(AHCITimeoutChain *chain)
{
    if (chain == 0)
        return;
    chain->armedGeneration = 0;
    chain->pendingGeneration = 0;
    chain->handoffPending = 0;
}

int AHCITimeoutChainArm(AHCITimeoutChain *chain, unsigned int generation)
{
    if (chain == 0 || generation == 0)
        return 0;
    if (chain->armedGeneration == 0) {
        chain->armedGeneration = generation;
        return 1;
    }
    chain->pendingGeneration = generation;
    chain->handoffPending = 1;
    return 0;
}

int AHCITimeoutChainCallbackMayEvaluate(AHCITimeoutChain *chain)
{
    if (chain == 0 || chain->armedGeneration == 0)
        return 0;
    if (chain->handoffPending) {
        chain->armedGeneration = chain->pendingGeneration;
        chain->pendingGeneration = 0;
        chain->handoffPending = 0;
        return 0;
    }
    return 1;
}

AHCIAsyncAction AHCIAsyncInterruptAction(unsigned int portIS,
                                         unsigned int serr,
                                         unsigned int ssts)
{
    (void)serr;
    if ((portIS & AHCI_PXIS_FATAL_MASK) != 0)
        return AHCI_ASYNC_HBA_RECOVERY;
    if ((portIS & (AHCI_PXIS_PCS | AHCI_PXIS_PRCS)) != 0 &&
        ((ssts & 0x0000000fU) != 3U ||
         ((ssts >> 8) & 0x0000000fU) != 1U))
        return AHCI_ASYNC_PORT_OFFLINE;
    return AHCI_ASYNC_NONE;
}
