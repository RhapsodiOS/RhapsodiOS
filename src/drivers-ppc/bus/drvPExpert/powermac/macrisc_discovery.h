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

#endif /* _PEXPERT_MACRISC_DISCOVERY_H_ */
