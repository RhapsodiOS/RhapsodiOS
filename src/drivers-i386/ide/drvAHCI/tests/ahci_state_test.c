#include <stdio.h>
#include <stdlib.h>

#include "AHCIState.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                      \
                    __FILE__, __LINE__, #expression);                        \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void test_pi_validation(void)
{
    CHECK(AHCIPIValid(0, 0x00000001U));
    CHECK(!AHCIPIValid(0, 0));
    CHECK(!AHCIPIValid(0, 0x00000002U));
    CHECK(AHCIPIValid(1, 0x00000003U));
    CHECK(!AHCIPIValid(1, 0x00000004U));
    CHECK(AHCIPIValid(31, 0x80000001U));
}

static void test_sparse_port_selection(void)
{
    CHECK(AHCINextPort(0x80000001U, -1) == 0);
    CHECK(AHCINextPort(0x80000001U, 0) == 31);
    CHECK(AHCINextPort(0x80000001U, 5) == 31);
    CHECK(AHCINextPort(0x80000001U, 31) == -1);
}

static void test_port_classification(void)
{
    unsigned int presentActive;

    presentActive = 0x00000103U;
    CHECK(AHCIClassifyPort(presentActive, 0x00000101U) == AHCI_DEVICE_SATA);
    CHECK(AHCIClassifyPort(presentActive, 0xeb140101U) == AHCI_DEVICE_ATAPI);
    CHECK(AHCIClassifyPort(presentActive, 0x96690101U) ==
          AHCI_DEVICE_UNSUPPORTED);
    CHECK(AHCIClassifyPort(0x00000101U, 0x00000101U) == AHCI_DEVICE_NONE);
    CHECK(AHCIClassifyPort(0x00000003U, 0x00000101U) == AHCI_DEVICE_NONE);
}

static void test_command_completion_requires_ci_clear(void)
{
    CHECK(!AHCICommandCompleted(0x00000001U, 0));
    CHECK(!AHCICommandCompleted(0x00000001U, AHCI_PXIS_TFES));
    CHECK(AHCICommandCompleted(0, 0));
    CHECK(AHCICommandCompleted(0, AHCI_PXIS_TFES));
}

static void test_recovery_decisions(void)
{
    CHECK(AHCIRecoveryFor(0, 0, 1, 0) == AHCI_RECOVERY_NONE);
    CHECK(AHCIRecoveryFor(0, 0, 0, 0) == AHCI_RECOVERY_HBA);
    CHECK(AHCIRecoveryFor(0, 0, 0, 1) == AHCI_RECOVERY_OFFLINE);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_PCS, 0, 1, 0) == AHCI_RECOVERY_PORT);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_TFES, 0, 1, 0) == AHCI_RECOVERY_PORT);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_IFS, 0, 1, 0) == AHCI_RECOVERY_PORT);
    CHECK(AHCIRecoveryFor(0, AHCI_PXSERR_DIAG_I, 1, 0) ==
          AHCI_RECOVERY_PORT);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_TFES, 0, 0, 0) == AHCI_RECOVERY_HBA);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_HBFS, 0, 1, 0) == AHCI_RECOVERY_HBA);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_HBFS, 0, 1, 1) ==
          AHCI_RECOVERY_OFFLINE);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_HBDS, 0, 1, 0) == AHCI_RECOVERY_HBA);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_HBDS, 0, 1, 1) ==
          AHCI_RECOVERY_OFFLINE);
    CHECK(AHCIRecoveryFor(AHCI_PXIS_TFES, 0, 0, 1) ==
          AHCI_RECOVERY_OFFLINE);
}

static void test_completion_races(void)
{
    AHCICommandArbiter arbiter;
    unsigned int generation;

    AHCICommandArbiterInit(&arbiter);
    generation = AHCICommandBegin(&arbiter);
    CHECK(generation != 0);
    CHECK(AHCICommandFinishIRQ(&arbiter, generation));
    CHECK(!AHCICommandFinishTimeout(&arbiter, generation));
    CHECK(arbiter.state == AHCI_COMMAND_COMPLETE);
    CHECK(arbiter.completions == 1U);

    generation = AHCICommandBegin(&arbiter);
    CHECK(AHCICommandFinishTimeout(&arbiter, generation));
    CHECK(!AHCICommandFinishIRQ(&arbiter, generation));
    CHECK(arbiter.state == AHCI_COMMAND_TIMED_OUT);
    CHECK(arbiter.completions == 2U);
}

static void test_stale_and_spurious_completion(void)
{
    AHCICommandArbiter arbiter;
    unsigned int oldGeneration;
    unsigned int generation;

    AHCICommandArbiterInit(&arbiter);
    CHECK(!AHCICommandFinishIRQ(&arbiter, 0));
    CHECK(arbiter.completions == 0U);
    oldGeneration = AHCICommandBegin(&arbiter);
    CHECK(AHCICommandFinishIRQ(&arbiter, oldGeneration));
    generation = AHCICommandBegin(&arbiter);
    CHECK(generation != oldGeneration);
    CHECK(!AHCICommandFinishTimeout(&arbiter, oldGeneration));
    CHECK(arbiter.state == AHCI_COMMAND_PENDING);
    CHECK(AHCICommandFinishIRQ(&arbiter, generation));
    CHECK(arbiter.completions == 2U);
}

static void test_completion_snapshot_classification(void)
{
    AHCICompletionSnapshot snapshot;

    snapshot.portIS = 0;
    snapshot.taskFile = 0;
    snapshot.serr = 0;
    snapshot.commandIssue = 0;
    snapshot.transferred = 8192U;
    CHECK(AHCIClassifyCompletion(&snapshot, 4096U) == AHCI_COMPLETION_OK);
    CHECK(snapshot.transferred == 4096U);
    snapshot.commandIssue = 1U;
    CHECK(AHCIClassifyCompletion(&snapshot, 4096U) ==
          AHCI_COMPLETION_PENDING);
    snapshot.portIS = AHCI_PXIS_TFES;
    CHECK(AHCIClassifyCompletion(&snapshot, 4096U) ==
          AHCI_COMPLETION_ERROR);
}

static void test_dequeued_timeout_cannot_expire_new_deadline(void)
{
    AHCICommandArbiter arbiter;
    unsigned int oldGeneration;
    unsigned int newGeneration;

    AHCICommandArbiterInit(&arbiter);
    oldGeneration = AHCICommandBegin(&arbiter);
    CHECK(AHCICommandFinishIRQ(&arbiter, oldGeneration));
    newGeneration = AHCICommandBegin(&arbiter);
    CHECK(!AHCICommandTimeoutDue(&arbiter, 200U, 100U));
    CHECK(!AHCICommandFinishTimeout(&arbiter, oldGeneration));
    CHECK(arbiter.state == AHCI_COMMAND_PENDING);
    CHECK(AHCICommandTimeoutDue(&arbiter, 200U, 200U));
    CHECK(AHCICommandFinishTimeout(&arbiter, newGeneration));
}

static void test_stale_timeout_after_new_deadline_only_rearms(void)
{
    AHCICommandArbiter arbiter;
    AHCITimeoutChain chain;
    unsigned int oldGeneration;
    unsigned int newGeneration;

    AHCICommandArbiterInit(&arbiter);
    AHCITimeoutChainInit(&chain);
    oldGeneration = AHCICommandBegin(&arbiter);
    CHECK(AHCITimeoutChainArm(&chain, oldGeneration));
    CHECK(AHCICommandFinishIRQ(&arbiter, oldGeneration));
    newGeneration = AHCICommandBegin(&arbiter);
    CHECK(!AHCITimeoutChainArm(&chain, newGeneration));
    CHECK(!AHCITimeoutChainCallbackMayEvaluate(&chain));
    CHECK(chain.armedGeneration == newGeneration);
    CHECK(arbiter.state == AHCI_COMMAND_PENDING);
    CHECK(AHCICommandTimeoutAction(&arbiter, oldGeneration, 200U, 250U) ==
          AHCI_TIMEOUT_REARM);
    CHECK(arbiter.state == AHCI_COMMAND_PENDING);
    CHECK(AHCITimeoutChainCallbackMayEvaluate(&chain));
    CHECK(AHCICommandTimeoutAction(&arbiter, newGeneration, 200U, 250U) ==
          AHCI_TIMEOUT_EXPIRE);
}

static void test_controller_recovery_gate(void)
{
    AHCIRecoveryGate gate;

    AHCIRecoveryGateInit(&gate);
    CHECK(AHCIRecoveryGateBeginSubmission(&gate));
    CHECK(gate.setupCount == 1U);
    CHECK(AHCIRecoveryGateStart(&gate));
    CHECK(!AHCIRecoveryGateStart(&gate));
    CHECK(!AHCIRecoveryGateBeginSubmission(&gate));
    CHECK(!AHCIRecoveryGateDrained(&gate));
    CHECK(!AHCIRecoveryGateCommitSubmission(&gate));
    CHECK(AHCIRecoveryGateDrained(&gate));
    AHCIRecoveryGateComplete(&gate, 1);
    CHECK(!gate.recovering && !gate.offline);
    CHECK(gate.resetAttempts == 1U);
    CHECK(AHCIRecoveryGateStart(&gate));
    AHCIRecoveryGateComplete(&gate, 0);
    CHECK(gate.offline && !gate.recovering);
    CHECK(!AHCIRecoveryGateBeginSubmission(&gate));
}

static void test_controller_reset_owns_recovery_after_flag_is_set(void)
{
    CHECK(AHCILocalRecoveryAllowed(0, 0));
    CHECK(!AHCILocalRecoveryAllowed(1, 0));
    CHECK(!AHCILocalRecoveryAllowed(0, 1));
    CHECK(!AHCILocalRecoveryAllowed(1, 1));
}

static void test_destroy_aborts_active_request_once(void)
{
    AHCICommandArbiter arbiter;
    unsigned int generation;

    AHCICommandArbiterInit(&arbiter);
    CHECK(!AHCICommandAbort(&arbiter));
    generation = AHCICommandBegin(&arbiter);
    CHECK(AHCICommandAbort(&arbiter));
    CHECK(arbiter.state == AHCI_COMMAND_TIMED_OUT);
    CHECK(!AHCICommandFinishIRQ(&arbiter, generation));
    CHECK(!AHCICommandAbort(&arbiter));
    CHECK(arbiter.completions == 1U);
}

static void test_recovery_requires_same_supported_kind(void)
{
    CHECK(AHCIRecoveredKindValid(AHCI_DEVICE_SATA, AHCI_DEVICE_SATA));
    CHECK(AHCIRecoveredKindValid(AHCI_DEVICE_ATAPI, AHCI_DEVICE_ATAPI));
    CHECK(!AHCIRecoveredKindValid(AHCI_DEVICE_SATA, AHCI_DEVICE_ATAPI));
    CHECK(!AHCIRecoveredKindValid(AHCI_DEVICE_ATAPI, AHCI_DEVICE_NONE));
    CHECK(!AHCIRecoveredKindValid(AHCI_DEVICE_UNSUPPORTED,
                                  AHCI_DEVICE_UNSUPPORTED));
}

static void test_async_interrupt_actions(void)
{
    CHECK(AHCIAsyncInterruptAction(0, 0, 0x00000103U) ==
          AHCI_ASYNC_NONE);
    CHECK(AHCIAsyncInterruptAction(AHCI_PXIS_HBFS, 0, 0x00000103U) ==
          AHCI_ASYNC_HBA_RECOVERY);
    CHECK(AHCIAsyncInterruptAction(AHCI_PXIS_PCS, 0, 0) ==
          AHCI_ASYNC_PORT_OFFLINE);
    CHECK(AHCIAsyncInterruptAction(AHCI_PXIS_PRCS, 0, 0x00000103U) ==
          AHCI_ASYNC_NONE);
}

static void test_async_hba_recovery_ownership(void)
{
    CHECK(AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_PENDING, 1, 0));
    CHECK(AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_COMPLETE, 1, 1));
    CHECK(AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_TIMED_OUT, 1, 1));
    CHECK(!AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_COMPLETE, 1, 0));
    CHECK(!AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_IDLE, 0, 0));
    CHECK(!AHCIAsyncHBARecoveryDeferred(AHCI_COMMAND_COMPLETE, 0, 1));
}

int main(void)
{
    test_pi_validation();
    test_sparse_port_selection();
    test_port_classification();
    test_command_completion_requires_ci_clear();
    test_recovery_decisions();
    test_completion_races();
    test_stale_and_spurious_completion();
    test_completion_snapshot_classification();
    test_dequeued_timeout_cannot_expire_new_deadline();
    test_stale_timeout_after_new_deadline_only_rearms();
    test_controller_recovery_gate();
    test_controller_reset_owns_recovery_after_flag_is_set();
    test_destroy_aborts_active_request_once();
    test_recovery_requires_same_supported_kind();
    test_async_interrupt_actions();
    test_async_hba_recovery_ownership();

    if (failures != 0) {
        fprintf(stderr, "ahci_state_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ahci_state_test: all tests passed\n");
    return EXIT_SUCCESS;
}
