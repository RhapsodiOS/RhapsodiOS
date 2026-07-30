#ifndef RHAPSODIOS_AHCI_REGS_H
#define RHAPSODIOS_AHCI_REGS_H

typedef struct {
    unsigned short flags;
    unsigned short prdtl;
    unsigned int prdbc;
    unsigned int ctba;
    unsigned int ctbau;
    unsigned int reserved[4];
} AHCICommandHeader;

typedef struct {
    unsigned int dba;
    unsigned int dbau;
    unsigned int reserved;
    unsigned int dbc_ioc;
} AHCIPRDTEntry;

typedef char AHCICommandHeaderMustBe32Bytes[
    (sizeof(AHCICommandHeader) == 32) ? 1 : -1];
typedef char AHCIPRDTEntryMustBe16Bytes[
    (sizeof(AHCIPRDTEntry) == 16) ? 1 : -1];

#endif
