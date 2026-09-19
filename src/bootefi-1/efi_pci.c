/* PCI discovery for the UEFI loader.
 *
 * Two separate things depend on this, and missing either one looks like a
 * driver bug rather than a loader gap:
 *
 *   - kernBootStruct.pciInfo tells the kernel's PCI bus driver which config
 *     mechanism exists.  drvPCIBus's PCIKernBus reads configMethod1 /
 *     configMethod2 from there and only falls back to probing itself when
 *     pciInfo.BIOSPresent is set.  There is no PCI BIOS under UEFI, so with
 *     pciInfo zeroed neither flag is set, the self-probe never runs,
 *     -isPCIPresent returns NO, and the bus driver frees itself in
 *     -initFromDeviceDescription:.  Every IOPCIDeviceDescription is then
 *     invalid and no PCI driver can read config space at all.
 *
 *   - PCISlotInfo is what set_dinfo() in boot-2's drivers.c walks to decide
 *     how many instances of a driver to configure.  It emits one config
 *     table per PCI device matching the driver's "Auto Detect IDs", each
 *     carrying that device's "Location".  With PCISlotInfo NULL it takes
 *     the !detected fallback instead: a single instance with no Location,
 *     which PCIKernBus -configAddress: then resolves by scanning for the
 *     first matching device.  On a board with two identical controllers
 *     that binds the driver to whichever comes first in bus order, even if
 *     the devices are on the other one.
 *
 * So the loader reports what a PCI BIOS would have: the access mechanism,
 * the bus count, and the slot inventory.  The probe and the scan mirror
 * testMethod1()/getMethod1()/scanBus() in src/boot-2/i386/libsaio/pci.c,
 * which cannot be linked here -- its <driverkit/KernDevice.h> chain wants a
 * machine/cpu_number.h this tree does not carry.
 */
#include "efi.h"

#include "kernBootStruct.h"
#include "io_inline.h"
#include "pci.h"

/* PCI 2.0 spec, sec 3.6.4.1.1.  Same ports boot-2's pci.c uses. */
#define PCI_CONFIG_ADDRESS  0x0cf8
#define PCI_CONFIG_DATA     0x0cfc

/* A read of a non-existent device floats the bus high. */
#define PCI_NO_DEVICE       0xffffffffUL

/* Configuration Mechanism 1 addresses 32 devices per bus. */
#define EFI_PCI_MAX_DEV     31

/* No BIOS to report a bus count and nothing cheap to ask instead, so walk
 * the whole space.  Absent buses read back all-ones and cost a port access
 * each. */
#define EFI_PCI_MAX_BUS     255

/* Slot inventory, sized for far more functions than a period board carries
 * so the loader needs no allocator.  One spare entry terminates the list,
 * which is how set_dinfo() knows where to stop. */
#define EFI_PCI_MAX_SLOTS   128

extern int printf(const char *, ...);

/* boot-2's pci.c owns this symbol in the BIOS build; here the definition
 * lives with the code that fills it. */
_pci_slot_info_t *PCISlotInfo;

static _pci_slot_info_t efi_pci_slots[EFI_PCI_MAX_SLOTS + 1];

/*
 * One configuration-space dword.  Mirrors getMethod1(): the address is
 * written to CF8 and read back, and a mismatch means the mechanism did not
 * take the write, so report the device as absent rather than trusting CFC.
 */
static unsigned long pci_config_read(unsigned int bus, unsigned int dev,
                                     unsigned int func, unsigned int offset)
{
    unsigned long address;
    unsigned long value;

    address = 0x80000000UL | ((unsigned long)bus << 16) |
              ((unsigned long)dev << 11) | ((unsigned long)func << 8) |
              ((unsigned long)offset & 0xffUL);

    value = PCI_NO_DEVICE;
    outl(PCI_CONFIG_ADDRESS, address);
    if (inl(PCI_CONFIG_ADDRESS) == address)
        value = inl(PCI_CONFIG_DATA);
    outl(PCI_CONFIG_ADDRESS, 0);
    return value;
}

/*
 * Configuration Mechanism 1 responds if CF8 latches an address we wrote
 * back verbatim and some device answers on CFC.  Mirrors testMethod1().
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
 * Fill efi_pci_slots with every responding function.  Mirrors scanBus(),
 * including its treatment of the multi-function bit: funcs 1..7 are skipped
 * only once func 0 has answered and cleared the bit, so a board that
 * populates a higher function without func 0 is still found.
 */
static int pci_scan_slots(unsigned int maxBusNum)
{
    unsigned int bus;
    unsigned int dev;
    unsigned int func;
    unsigned long pid;
    int count;

    count = 0;
    for (bus = 0; bus <= maxBusNum; bus++) {
        for (dev = 0; dev <= EFI_PCI_MAX_DEV; dev++) {
            for (func = 0; func < 8; func++) {
                pid = pci_config_read(bus, dev, func, 0x00);
                if ((pid & 0xffffUL) == 0xffffUL ||
                    (pid & 0xffffUL) == 0UL)
                    continue;

                if (count < EFI_PCI_MAX_SLOTS) {
                    efi_pci_slots[count].pid = pid;
                    efi_pci_slots[count].sid =
                        pci_config_read(bus, dev, func, 0x2c);
                    efi_pci_slots[count].dev = dev;
                    efi_pci_slots[count].func = func;
                    efi_pci_slots[count].bus = bus;
                }
                count++;

                /* Header type bit 23 marks a multi-function device. */
                pid = pci_config_read(bus, dev, func, 0x0c);
                if ((pid & 0x00800000UL) == 0UL)
                    break;
            }
        }
    }
    return count;
}

/*
 * Record the PCI access mechanism and slot inventory in the places the
 * kernel and boot-2's driver matcher expect them.  Returns the number of
 * devices found, zero if there is no usable config mechanism.
 */
int efi_pci_init(void)
{
    PCI_bus_info_t *info = &kernBootStruct->pciInfo;
    int count;

    if (!pci_mechanism_1_present()) {
        printf("pci: no config mechanism; PCI drivers will not bind\n");
        return 0;
    }

    /* BIOSPresent stays 0 -- there genuinely is no PCI BIOS here, and
     * nothing reads it except the self-probe branch we are replacing. */
    info->u_bus.s.configMethod1 = 1;
    info->maxBusNum = EFI_PCI_MAX_BUS;

    count = pci_scan_slots(EFI_PCI_MAX_BUS);
    if (count > EFI_PCI_MAX_SLOTS) {
        printf("pci: %d devices, only the first %d recorded\n",
               count, EFI_PCI_MAX_SLOTS);
        count = EFI_PCI_MAX_SLOTS;
    }

    /* set_dinfo() stops at the first zero pid. */
    efi_pci_slots[count].pid = 0;
    efi_pci_slots[count].sid = 0;
    PCISlotInfo = efi_pci_slots;
    return count;
}
