#include <stdio.h>
#include <stdlib.h>

#include "AHCIPCI.h"

static int failures;

static void fail(const char *test, const char *message)
{
    fprintf(stderr, "%s: %s\n", test, message);
    ++failures;
}

static void test_valid_bar5(void)
{
    static const char name[] = "valid BAR5";
    AHCIU32 base;

    base = 0;
    if (AHCIPCIValidateBAR5(0xfebf0000U, 0x1100U, &base) !=
        AHCI_PCI_SUCCESS)
        fail(name, "32-bit non-prefetchable BAR was rejected");
    if (base != 0xfebf0000U)
        fail(name, "memory flags were not masked from BAR5");
}

static void test_invalid_bar5_values(void)
{
    static const char name[] = "invalid BAR5";
    static const AHCIU32 invalid[] = {
        0x00000000U,
        0xffffffffU,
        0xfebf0001U,
        0xfebf0004U,
        0xfebf0008U,
        0xfffffff0U,
        0xfffff000U
    };
    AHCIU32 base;
    unsigned int index;

    for (index = 0; index < sizeof(invalid) / sizeof(invalid[0]); ++index) {
        base = 0x12345678U;
        if (AHCIPCIValidateBAR5(invalid[index], 0x1100U, &base) !=
            AHCI_PCI_INVALID_BAR)
            fail(name, "malformed BAR was accepted");
    }
    if (AHCIPCIValidateBAR5(0xfebf0000U, 0, &base) !=
        AHCI_PCI_BAD_ARGUMENT ||
        AHCIPCIValidateBAR5(0xfebf0000U, 0x1100U, 0) !=
        AHCI_PCI_BAD_ARGUMENT)
        fail(name, "bad output/span argument was accepted");
}

static void test_changed_command_plan(void)
{
    static const char name[] = "changed command plan";
    AHCIU32 enableWrite;
    AHCIU32 restoreWrite;
    unsigned char changed;

    if (AHCIPCIPlanCommand(0xabcd0001U, &enableWrite, &restoreWrite,
                           &changed) != AHCI_PCI_SUCCESS)
        fail(name, "plan failed");
    if (enableWrite != 0x00000007U || restoreWrite != 0x00000001U)
        fail(name, "command bits or restore value are wrong");
    if ((enableWrite & ~AHCI_PCI_COMMAND_MASK) != 0 ||
        (restoreWrite & ~AHCI_PCI_COMMAND_MASK) != 0)
        fail(name, "W1C PCI status bits were echoed into a write");
    if (changed != 1U)
        fail(name, "changed command was not marked changed");
}

static void test_already_enabled_command_plan(void)
{
    static const char name[] = "already-enabled command plan";
    AHCIU32 enableWrite;
    AHCIU32 restoreWrite;
    unsigned char changed;

    if (AHCIPCIPlanCommand(0xffff0047U, &enableWrite, &restoreWrite,
                           &changed) != AHCI_PCI_SUCCESS)
        fail(name, "plan failed");
    if (enableWrite != 0x00000047U || restoreWrite != 0x00000047U)
        fail(name, "unrelated command bits were not preserved");
    if (changed != 0)
        fail(name, "already-enabled command was marked changed");
}

static void test_command_readback(void)
{
    static const char name[] = "command readback";

    if (AHCIPCIValidateCommandReadback(0xffff0006U) != AHCI_PCI_SUCCESS)
        fail(name, "enabled lower command word was rejected");
    if (AHCIPCIValidateCommandReadback(0xffff0002U) !=
        AHCI_PCI_COMMAND_NOT_ENABLED ||
        AHCIPCIValidateCommandReadback(0xffff0004U) !=
        AHCI_PCI_COMMAND_NOT_ENABLED)
        fail(name, "missing command bit was accepted");
}

static void test_command_plan_arguments(void)
{
    static const char name[] = "command plan arguments";
    AHCIU32 value;
    unsigned char changed;

    if (AHCIPCIPlanCommand(0, 0, &value, &changed) !=
        AHCI_PCI_BAD_ARGUMENT ||
        AHCIPCIPlanCommand(0, &value, 0, &changed) !=
        AHCI_PCI_BAD_ARGUMENT ||
        AHCIPCIPlanCommand(0, &value, &value, 0) !=
        AHCI_PCI_BAD_ARGUMENT)
        fail(name, "missing output was accepted");
}

static void test_legacy_interrupt_line(void)
{
    static const char name[] = "legacy interrupt line";
    unsigned int line;

    if (AHCIPCIInterruptLine(0xabcd010bU, &line) != AHCI_PCI_SUCCESS ||
        line != 11U)
        fail(name, "valid interrupt line was not extracted");
    if (AHCIPCIInterruptLine(0x00000100U, &line) !=
            AHCI_PCI_INVALID_INTERRUPT ||
        AHCIPCIInterruptLine(0x00000101U, &line) !=
            AHCI_PCI_INVALID_INTERRUPT ||
        AHCIPCIInterruptLine(0x00000110U, &line) !=
            AHCI_PCI_INVALID_INTERRUPT ||
        AHCIPCIInterruptLine(0x000001ffU, &line) !=
            AHCI_PCI_INVALID_INTERRUPT ||
        AHCIPCIInterruptLine(0x0000010bU, 0) != AHCI_PCI_BAD_ARGUMENT)
        fail(name, "invalid interrupt line was accepted");
}

int main(void)
{
    test_valid_bar5();
    test_invalid_bar5_values();
    test_changed_command_plan();
    test_already_enabled_command_plan();
    test_command_readback();
    test_command_plan_arguments();
    test_legacy_interrupt_line();
    if (failures != 0) {
        fprintf(stderr, "ahci_pci_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    printf("ahci_pci_test: all tests passed\n");
    return EXIT_SUCCESS;
}
