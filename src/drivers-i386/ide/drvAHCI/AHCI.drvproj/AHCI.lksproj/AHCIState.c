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
