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

int main(void)
{
    test_pi_validation();
    test_sparse_port_selection();
    test_port_classification();
    test_command_completion_requires_ci_clear();
    test_recovery_decisions();

    if (failures != 0) {
        fprintf(stderr, "ahci_state_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ahci_state_test: all tests passed\n");
    return EXIT_SUCCESS;
}
