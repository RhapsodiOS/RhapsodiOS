/*
 * pcicfg.h
 * PCI configuration space access: mechanism #1 and MCFG (ECAM).
 */

#ifndef _PEXPERT_CHIPS_PCICFG_H_
#define _PEXPERT_CHIPS_PCICFG_H_

/* Tell the accessors about the memory-mapped space, once it is mapped. */
void pcicfg_set_ecam(volatile unsigned char *base, int start_bus, int end_bus);

/* Whether mechanism #1 answers on this machine. */
int pcicfg_probe_mechanism1(void);

int pcicfg_read(int bus, int dev, int fn, int off, int size, unsigned int *val);
int pcicfg_write(int bus, int dev, int fn, int off, int size, unsigned int val);

#endif /* _PEXPERT_CHIPS_PCICFG_H_ */
