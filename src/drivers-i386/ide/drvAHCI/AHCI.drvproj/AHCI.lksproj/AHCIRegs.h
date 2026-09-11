#ifndef RHAPSODIOS_AHCI_REGS_H
#define RHAPSODIOS_AHCI_REGS_H

typedef unsigned int AHCIU32;

typedef char AHCIU32MustBe4Bytes[(sizeof(AHCIU32) == 4) ? 1 : -1];

/* HBA global registers from AHCI 1.3.1 section 3.1. */
#define AHCI_REG_CAP             0x00U
#define AHCI_REG_GHC             0x04U
#define AHCI_REG_IS              0x08U
#define AHCI_REG_PI              0x0cU
#define AHCI_REG_VS              0x10U
#define AHCI_REG_CCC_CTL         0x14U
#define AHCI_REG_CCC_PORTS       0x18U
#define AHCI_REG_EM_LOC          0x1cU
#define AHCI_REG_EM_CTL          0x20U
#define AHCI_REG_CAP2            0x24U
#define AHCI_REG_BOHC            0x28U

#define AHCI_GHC_HR              0x00000001U
#define AHCI_GHC_IE              0x00000002U
#define AHCI_GHC_AE              0x80000000U

#define AHCI_CAP_NP_MASK         0x0000001fU
#define AHCI_CAP_SSS             0x08000000U
#define AHCI_CAP2_BOH            0x00000001U

#define AHCI_BOHC_BOS            0x00000001U
#define AHCI_BOHC_OOS            0x00000002U
#define AHCI_BOHC_SOOE           0x00000004U
#define AHCI_BOHC_OOC            0x00000008U
#define AHCI_BOHC_BB             0x00000010U

#define AHCI_POLL_INTERVAL_MS        1U
#define AHCI_BOHC_BB_OBSERVE_MS     25U
#define AHCI_BOHC_HANDOFF_TIMEOUT_MS 2000U
#define AHCI_HBA_RESET_TIMEOUT_MS   1000U

/* Per-port registers from AHCI 1.3.1 section 3.3. */
#define AHCI_PORT_BASE(port)     (0x100U + ((AHCIU32)(port) * 0x80U))
#define AHCI_PX_CLB              0x00U
#define AHCI_PX_CLBU             0x04U
#define AHCI_PX_FB               0x08U
#define AHCI_PX_FBU              0x0cU
#define AHCI_PX_IS               0x10U
#define AHCI_PX_IE               0x14U
#define AHCI_PX_CMD              0x18U
#define AHCI_PX_TFD              0x20U
#define AHCI_PX_SIG              0x24U
#define AHCI_PX_SSTS             0x28U
#define AHCI_PX_SCTL             0x2cU
#define AHCI_PX_SERR             0x30U
#define AHCI_PX_CI               0x38U

#define AHCI_PXCMD_ST            0x00000001U
#define AHCI_PXCMD_SUD           0x00000002U
#define AHCI_PXCMD_POD           0x00000004U
#define AHCI_PXCMD_FRE           0x00000010U
#define AHCI_PXCMD_FR            0x00004000U
#define AHCI_PXCMD_CR            0x00008000U
#define AHCI_PXCMD_CPD           0x00100000U

#define AHCI_SSTS_DET_MASK       0x0000000fU
#define AHCI_SSTS_DET_PRESENT    0x00000003U
#define AHCI_SSTS_IPM_MASK       0x00000f00U
#define AHCI_SSTS_IPM_ACTIVE     0x00000100U
#define AHCI_SCTL_DET_MASK       0x0000000fU
#define AHCI_SCTL_DET_COMRESET   0x00000001U
#define AHCI_SCTL_SPD_MASK       0x000000f0U

#define AHCI_SIG_ATA             0x00000101U
#define AHCI_SIG_ATAPI           0xeb140101U

typedef struct {
    unsigned short flags;
    unsigned short prdtl;
    AHCIU32 prdbc;
    AHCIU32 ctba;
    AHCIU32 ctbau;
    AHCIU32 reserved[4];
} AHCICommandHeader;

typedef struct {
    AHCIU32 dba;
    AHCIU32 dbau;
    AHCIU32 reserved;
    AHCIU32 dbc_ioc;
} AHCIPRDTEntry;

typedef char AHCICommandHeaderMustBe32Bytes[
    (sizeof(AHCICommandHeader) == 32) ? 1 : -1];
typedef char AHCIPRDTEntryMustBe16Bytes[
    (sizeof(AHCIPRDTEntry) == 16) ? 1 : -1];

#endif
