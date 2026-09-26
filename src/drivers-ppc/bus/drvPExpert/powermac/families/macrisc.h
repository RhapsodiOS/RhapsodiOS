#ifndef _PEXPERT_FAMILIES_MACRISC_H_
#define _PEXPERT_FAMILIES_MACRISC_H_

#include <macrisc_discovery.h>

struct powermac_interrupt;
struct powermac_dbdma_channels;

/*
 * Runtime tables built from a validated descriptor.  They touch no
 * hardware, so the host tests build them too.  mapping holds two words per
 * source in INT_TBL form.
 */
int PEMacRISCBuildMPIC(const PEMacRISCPlatform *platform,
    struct powermac_interrupt *interrupts, unsigned long *mapping);
int PEMacRISCBuildDBDMA(const PEDBDMAChannels *source,
    struct powermac_dbdma_channels *destination);

#ifndef MACRISC_HOST_TEST

#include <powermac.h>

extern powermac_init_t macrisc_init;

extern int  rtc_init(void);
extern void configure_macrisc(void);
extern void macrisc_initialize_bats(boot_args *args);

#endif /* !MACRISC_HOST_TEST */

#endif /* _PEXPERT_FAMILIES_MACRISC_H_ */
