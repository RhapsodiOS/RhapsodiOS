#ifndef _PEXPERT_MACRISC_DISCOVERY_H_
#define _PEXPERT_MACRISC_DISCOVERY_H_

/*
 * Allocation-free helpers for later New World (MacRISC) platform discovery.
 * Nothing here touches hardware or kernel state, so the same source builds
 * into the platform expert and into the host tests.
 */

/*
 * A bounded view of one firmware property.  Cells are big-endian and the
 * bytes are never assumed to be aligned.  Keep this layout identical to
 * PEKeyLargoProperty in chips/keylargo_discovery.h.
 */
typedef struct {
    const unsigned char *bytes;
    unsigned int size;
} PEProperty;

int PEPropertyHasString(PEProperty property, const char *expected);
int PEReadCell32(PEProperty property, unsigned int index,
    unsigned int *value);
int PEReadAddress32(PEProperty property, unsigned int cells,
    unsigned int *value);

#define PE_MACRISC_MODEL_MAX 64
#define PE_MACRISC_MAX_CPUS 4
#define PE_MACRISC_MAX_SOURCES 64
#define PE_MACRISC_MAX_CASCADE 7

typedef enum {
    kPECPUUnknown, kPECPU750, kPECPU7400, kPECPU7410, kPECPU745x, kPECPU970
} PECPUFamily;

typedef enum {
    kPEMacIOUnknown, kPEMacIOKeyLargo, kPEMacIOPangea, kPEMacIOIntrepid,
    kPEMacIOK2
} PEMacIOFamily;

typedef enum {
    kPEMacRISCNotMatched, kPEMacRISCSupported, kPEMacRISCCompatibleUnlisted,
    kPEMacRISCMalformed, kPEMacRISCUnsupportedCPU, kPEMacRISCUnsupportedHost,
    kPEMacRISCUnsupportedMacIO
} PEMacRISCStatus;

/*
 * model is the root "compatible" list (its first member names the machine,
 * as get_machine_id() uses it); hostCompatible belongs to the PCI host
 * bridge that parents mac-io; macIODeviceID is mac-io's one-cell
 * "device-id".
 */
typedef struct {
    PEProperty model, rootCompatible, hostCompatible, macIOCompatible;
    PEProperty macIODeviceID;
    unsigned int pvr;
} PEMacRISCIdentityInput;

PEMacRISCStatus PEMacRISCClassify(const PEMacRISCIdentityInput *input,
    PECPUFamily *cpu, PEMacIOFamily *macIO,
    char model[PE_MACRISC_MODEL_MAX]);
int PEMacRISCHostSupported(PEProperty hostCompatible);

typedef enum {
    kPERouteLegacy, kPERouteSawtooth, kPERouteMacRISC, kPERouteUnsupported
} PEPlatformRoute;

/*
 * model is get_machine_id()'s identifier.  The existing Yosemite and
 * Sawtooth identifiers keep their routes whatever discovery says.
 */
PEPlatformRoute PEMacRISCSelectRoute(const char *model,
    PEMacRISCStatus status);

typedef struct {
    int present;
    unsigned int base, length;      /* absolute physical address */
} PEResource;

/* Same field order as powermac_dbdma_channels_t; -1 means absent. */
typedef struct {
    int curio, mesh, floppy, ethernetTx, ethernetRx;
    int sccATx, sccARx, sccBTx, sccBRx;
    int audioOut, audioIn, ata0, ata1;
} PEDBDMAChannels;

typedef enum {
    kPEPlatformValid, kPEPlatformMissingMacIO, kPEPlatformBadMacIORange,
    kPEPlatformMissingMPIC, kPEPlatformBadMPICRange, kPEPlatformBadMPICCount,
    kPEPlatformMissingCPU, kPEPlatformBadCPUCount, kPEPlatformBadClock,
    kPEPlatformBadCascade, kPEPlatformMissingVIA, kPEPlatformMissingSerial,
    kPEPlatformMissingNVRAM, kPEPlatformBadRange
} PEPlatformError;

/*
 * Everything early boot needs from firmware, copied out of the device tree
 * so that nothing points into unchecked property storage.  Mac-IO, MPIC,
 * VIA, SCC and NVRAM are required because existing code dereferences their
 * bases unconditionally; the other resources are optional.
 */
/* What a primary MPIC source is known to belong to. */
typedef enum {
    kPERoleNone, kPERoleVIA, kPERolePMU, kPERoleNMI,
    kPERoleSCCA, kPERoleSCCATx, kPERoleSCCARx,
    kPERoleSCCB, kPERoleSCCBTx, kPERoleSCCBRx,
    kPERoleMESH, kPERoleMESHDMA, kPERoleFloppy, kPERoleFloppyDMA,
    kPERoleATA0, kPERoleATA0DMA, kPERoleATA1, kPERoleATA1DMA,
    kPERoleAudio, kPERoleAudioOut, kPERoleAudioIn
} PEInterruptRole;

/* sourceSense holds the OpenPIC "interrupts" sense cell (0..3). */
#define PE_MACRISC_SENSE_UNKNOWN 0xff

typedef struct {
    char model[PE_MACRISC_MODEL_MAX];
    int listedModel;
    PECPUFamily cpuFamily;
    PEMacIOFamily macIOFamily;
    int hostSupported;
    unsigned int cpuCount, bootCPU, pvr;
    unsigned int cpuClockHz, busClockHz, timebaseHz;
    unsigned int dcacheSize, dcacheBlockSize, icacheSize, l2CacheSize;
    int cachesUnified;
    PEResource macIO, mpic, via, serial, mesh, floppy, audio, ethernet;
    PEResource nvram, ata0, ata1;
    PEDBDMAChannels dbdma;
    unsigned int mpicSources;
    int hasPMU, hasCUDA, hasCascade;
    unsigned int cascadeSource, cascadeWidth;
    int hasPMUInterrupt;
    unsigned int pmuInterruptSource;
    unsigned char sourceRole[PE_MACRISC_MAX_SOURCES];
    unsigned char sourceSense[PE_MACRISC_MAX_SOURCES];
} PEMacRISCPlatform;

/* Absolute physical bases for powermac_io_info; absent devices are 0. */
typedef struct {
    unsigned int ioBase, ioSize, interruptBase, dmaBase, viaBase;
    unsigned int serialBase, meshBase, floppyBase, audioBase, ethernetBase;
    unsigned int nvramAddress, nvramData, ata0Base, ata1Base;
} PEMacRISCPublishedIO;

int PEMacRISCPublish(const PEMacRISCPlatform *platform,
    PEMacRISCPublishedIO *published);

/*
 * The nanosecond pair keeps the legacy scale (4000 over the bus clock in
 * MHz); the 8.24 decrementer period comes from the firmware timebase.
 */
/*
 * The two interrupts both PMU drivers expect, as raw AAPL,interrupts cells
 * (DriverKit XORs each with 0x18): the VIA1 cascade child, which
 * identify_via_irq() also writes, and the PMU GPIO (extint-gpio1) source.
 * Returns 2, or 0 when the machine has no complete PMU topology.
 */
unsigned int PEMacRISCPMUInterruptList(const PEMacRISCPlatform *platform,
    unsigned int output[2]);

int PEMacRISCComputeClockConversion(const PEMacRISCPlatform *platform,
    unsigned int *numerator, unsigned int *denominator,
    unsigned int *period824);

/*
 * One bounded boot-log line naming the model, CPU and Mac-IO families and
 * the failing capability.  Returns the length written.
 */
unsigned int PEMacRISCFormatDiagnostic(char *buffer, unsigned int size,
    const PEMacRISCPlatform *platform, PEMacRISCStatus status,
    PEPlatformError error);

void PEMacRISCPlatformInit(PEMacRISCPlatform *platform);
PEPlatformError PEMacRISCValidate(const PEMacRISCPlatform *platform);
int PEMacRISCSetResource(PEResource *resource, unsigned int base,
    unsigned int length);
int PEMacRISCSetDBDMA(PEDBDMAChannels *channels, const char *role,
    unsigned int channel);

#endif /* _PEXPERT_MACRISC_DISCOVERY_H_ */
