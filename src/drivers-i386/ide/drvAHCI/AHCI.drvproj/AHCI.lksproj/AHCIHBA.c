#include "AHCIHBA.h"

static int ahci_pi_valid(AHCIU32 cap, AHCIU32 pi)
{
    AHCIU32 highestPort;
    AHCIU32 validMask;

    if (pi == 0)
        return 0;
    highestPort = cap & AHCI_CAP_NP_MASK;
    if (highestPort == 31U)
        return 1;
    validMask = (1U << (highestPort + 1U)) - 1U;
    return (pi & ~validMask) == 0;
}

static void ahci_write(const AHCIHBAOps *ops, AHCIU32 offset,
                       AHCIU32 value)
{
    ops->write(ops->context, offset, value);
    ops->barrier(ops->context);
}

static AHCIHBAResult ahci_bios_handoff(const AHCIHBAOps *ops,
                                      AHCIU32 capabilities2)
{
    AHCIU32 bohc;
    unsigned int waited;

    if ((capabilities2 & AHCI_CAP2_BOH) == 0)
        return AHCI_HBA_SUCCESS;

    bohc = ops->read(ops->context, AHCI_REG_BOHC);
    ahci_write(ops, AHCI_REG_BOHC, bohc | AHCI_BOHC_OOS);
    ops->delay(ops->context, AHCI_BOHC_BB_OBSERVE_MS);
    bohc = ops->read(ops->context, AHCI_REG_BOHC);

    if ((bohc & AHCI_BOHC_BB) != 0) {
        waited = 0;
        while ((bohc & (AHCI_BOHC_BOS | AHCI_BOHC_BB)) != 0 &&
               waited < AHCI_BOHC_HANDOFF_TIMEOUT_MS) {
            ops->delay(ops->context, AHCI_POLL_INTERVAL_MS);
            waited += AHCI_POLL_INTERVAL_MS;
            bohc = ops->read(ops->context, AHCI_REG_BOHC);
        }
        if ((bohc & (AHCI_BOHC_BOS | AHCI_BOHC_BB)) != 0)
            return AHCI_HBA_BOHC_TIMEOUT;
    }
    return AHCI_HBA_SUCCESS;
}

static void ahci_disable_interrupts(const AHCIHBAOps *ops)
{
    AHCIU32 ghc;

    ghc = ops->read(ops->context, AHCI_REG_GHC);
    ahci_write(ops, AHCI_REG_GHC, (ghc | AHCI_GHC_AE) & ~AHCI_GHC_IE);
    ahci_write(ops, AHCI_REG_IS, 0xffffffffU);
}

AHCIHBAResult AHCIHBAInitialize(const AHCIHBAOps *ops, AHCIHBAInfo *info)
{
    AHCIHBAResult result;
    AHCIU32 ghc;
    unsigned int waited;

    if (ops == 0 || info == 0 || ops->read == 0 || ops->write == 0 ||
        ops->delay == 0 || ops->barrier == 0)
        return AHCI_HBA_BAD_ARGUMENT;

    info->capabilities = ops->read(ops->context, AHCI_REG_CAP);
    info->version = ops->read(ops->context, AHCI_REG_VS);
    info->capabilities2 = ops->read(ops->context, AHCI_REG_CAP2);
    info->portsImplemented = ops->read(ops->context, AHCI_REG_PI);
    if (info->version == 0 || info->version == 0xffffffffU ||
        info->capabilities == 0xffffffffU ||
        info->capabilities2 == 0xffffffffU)
        return AHCI_HBA_INVALID_REGISTERS;
    if (!ahci_pi_valid(info->capabilities, info->portsImplemented))
        return AHCI_HBA_INVALID_PI;

    result = ahci_bios_handoff(ops, info->capabilities2);
    if (result != AHCI_HBA_SUCCESS)
        return result;

    ghc = ops->read(ops->context, AHCI_REG_GHC);
    ahci_write(ops, AHCI_REG_GHC, ghc | AHCI_GHC_AE);
    ghc = ops->read(ops->context, AHCI_REG_GHC);
    ahci_write(ops, AHCI_REG_GHC, ghc | AHCI_GHC_AE | AHCI_GHC_HR);

    waited = 0;
    ghc = ops->read(ops->context, AHCI_REG_GHC);
    while ((ghc & AHCI_GHC_HR) != 0 &&
           waited < AHCI_HBA_RESET_TIMEOUT_MS) {
        ops->delay(ops->context, AHCI_POLL_INTERVAL_MS);
        waited += AHCI_POLL_INTERVAL_MS;
        ghc = ops->read(ops->context, AHCI_REG_GHC);
    }
    if ((ghc & AHCI_GHC_HR) != 0) {
        ahci_disable_interrupts(ops);
        return AHCI_HBA_RESET_TIMEOUT;
    }

    ahci_write(ops, AHCI_REG_GHC, ghc | AHCI_GHC_AE);
    ahci_disable_interrupts(ops);
    return AHCI_HBA_SUCCESS;
}
