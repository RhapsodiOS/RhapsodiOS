#ifndef RHAPSODIOS_AHCI_STATE_H
#define RHAPSODIOS_AHCI_STATE_H

typedef enum {
    AHCI_DEVICE_NONE,
    AHCI_DEVICE_SATA,
    AHCI_DEVICE_ATAPI,
    AHCI_DEVICE_UNSUPPORTED
} AHCIDeviceKind;

typedef enum {
    AHCI_RECOVERY_NONE,
    AHCI_RECOVERY_PORT,
    AHCI_RECOVERY_HBA,
    AHCI_RECOVERY_OFFLINE
} AHCIRecovery;

/* AHCI 1.3.1 PxIS bits used by the recovery decision. */
#define AHCI_PXIS_UFS             0x00000010U
#define AHCI_PXIS_PCS             0x00000040U
#define AHCI_PXIS_PRCS            0x00400000U
#define AHCI_PXIS_IPMS            0x00800000U
#define AHCI_PXIS_OFS             0x01000000U
#define AHCI_PXIS_INFS            0x04000000U
#define AHCI_PXIS_IFS             0x08000000U
#define AHCI_PXIS_HBDS            0x10000000U
#define AHCI_PXIS_HBFS            0x20000000U
#define AHCI_PXIS_TFES            0x40000000U

#define AHCI_PXIS_FATAL_MASK      (AHCI_PXIS_HBDS | AHCI_PXIS_HBFS)
#define AHCI_PXIS_RECOVERABLE_MASK \
    (AHCI_PXIS_UFS | AHCI_PXIS_PCS | AHCI_PXIS_PRCS | AHCI_PXIS_IPMS | \
     AHCI_PXIS_OFS | AHCI_PXIS_INFS | AHCI_PXIS_IFS | AHCI_PXIS_TFES)

/* AHCI 1.3.1 PxSERR Error and Diagnostics fields. */
#define AHCI_PXSERR_ERR_MASK      0x0000ffffU
#define AHCI_PXSERR_DIAG_N        0x00010000U
#define AHCI_PXSERR_DIAG_I        0x00020000U
#define AHCI_PXSERR_DIAG_MASK     0x07ff0000U
#define AHCI_PXSERR_ERROR_MASK    \
    (AHCI_PXSERR_ERR_MASK | AHCI_PXSERR_DIAG_MASK)

int AHCIPIValid(unsigned int cap, unsigned int pi);
int AHCINextPort(unsigned int pi, int previous);
AHCIDeviceKind AHCIClassifyPort(unsigned int ssts, unsigned int sig);
int AHCICommandCompleted(unsigned int ci, unsigned int portIS);
AHCIRecovery AHCIRecoveryFor(unsigned int portIS, unsigned int serr,
                             unsigned char engineStopped,
                             unsigned char hbaResetAlreadyTried);

#endif
