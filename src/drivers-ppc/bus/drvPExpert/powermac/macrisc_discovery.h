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

#endif /* _PEXPERT_MACRISC_DISCOVERY_H_ */
