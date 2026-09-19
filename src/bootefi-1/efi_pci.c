/* Tell the kernel that PCI config space exists.
 *
 * The kernel's PCI bus driver does not probe for a configuration mechanism
 * on its own unless a PCI BIOS is present: drvPCIBus's PCIKernBus reads
 * configMethod1/configMethod2 out of kernBootStruct.pciInfo and only falls
 * back to test_M1/test_M2 when pciInfo.BIOSPresent is set.  Under UEFI
 * there is no PCI BIOS, efi_memory.c leaves pciInfo zeroed, so neither
 * mechanism flag is set and the self-probe never runs.  -isPCIPresent then
 * returns NO and the bus driver frees itself in
 * -initFromDeviceDescription:, after which every IOPCIDeviceDescription is
 * invalid and no PCI driver can read config space at all.  That is what
 * stopped drvAHCI at its first getPCIConfigData:.
 *
 * So the loader reports what a PCI BIOS would have: which access mechanism
 * exists, and how many buses to scan.  The probe is boot-2's testMethod1()
 * (libsaio/pci.c), which works without a BIOS because it only touches
 * CF8/CFC -- ports UEFI does not trap on x86.
 *
 * Note this deliberately does NOT build PCISlotInfo, so drivers still get
 * no "Location" key.  They do not need one: PCIKernBus -configAddress:
 * falls back to scanning every bus/device/function for a driver's
 * "Auto Detect IDs" when Location is absent.
 */
#include "efi.h"

#include "kernBootStruct.h"
#include "io_inline.h"

/* PCI 2.0 spec, sec 3.6.4.1.1.  Same ports boot-2's pci.c uses. */
#define PCI_CONFIG_ADDRESS  0x0cf8
#define PCI_CONFIG_DATA     0x0cfc

/* A read of a non-existent device floats the bus high. */
#define PCI_NO_DEVICE       0xffffffffUL

/* No BIOS to report a bus count and nothing cheap to ask instead, so let
 * the kernel walk the whole space.  Absent buses read back all-ones and
 * cost only a port access each. */
#define EFI_PCI_MAX_BUS     255

extern int printf(const char *, ...);

/*
 * Configuration Mechanism 1 responds if CF8 latches an address we wrote
 * back verbatim and some device answers on CFC.  Mirrors testMethod1() in
 * src/boot-2/i386/libsaio/pci.c, which is static and cannot be called from
 * here; that file is not part of this build because its
 * <driverkit/KernDevice.h> chain wants a machine/cpu_number.h this tree
 * does not carry.
 */
static int pci_mechanism_1_present(void)
{
    unsigned long address;
    unsigned long data;

    for (address = 0x80000000UL; address < 0x80010000UL;
         address += 0x800UL) {
        outl(PCI_CONFIG_ADDRESS, address);
        if (inl(PCI_CONFIG_ADDRESS) != address) {
            outl(PCI_CONFIG_ADDRESS, 0);
            return 0;
        }
        data = inl(PCI_CONFIG_DATA);
        if (data != PCI_NO_DEVICE && data != 0UL) {
            outl(PCI_CONFIG_ADDRESS, 0);
            return 1;
        }
    }

    outl(PCI_CONFIG_ADDRESS, 0);
    return 0;
}

/*
 * Record the PCI access mechanism in kernBootStruct for the kernel's bus
 * driver.  Returns non-zero if PCI config space was found.
 */
int efi_pci_init(void)
{
    PCI_bus_info_t *info = &kernBootStruct->pciInfo;

    if (!pci_mechanism_1_present()) {
        printf("pci: no config mechanism; PCI drivers will not bind\n");
        return 0;
    }

    /* BIOSPresent stays 0 -- there genuinely is no PCI BIOS here, and
     * nothing reads it except the self-probe branch we are replacing. */
    info->u_bus.s.configMethod1 = 1;
    info->maxBusNum = EFI_PCI_MAX_BUS;
    return 1;
}
