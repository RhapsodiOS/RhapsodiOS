/*
 * pcicfg.c
 * PCI configuration space access.
 *
 * Mechanism #1 (PCI 2.0 sec 3.6.4.1.1) reaches the first 256 bytes of
 * every function through the 0xCF8/0xCFC port pair.  The memory-mapped
 * space that MCFG describes (PCI Express base spec sec 7.2.2) reaches all
 * 4096 bytes; it is used whenever it covers the bus and the offset asks
 * for it, so a machine without MCFG behaves exactly as before.
 */

#include "pcicfg.h"

#define PCI_CONFIG_ADDRESS	0x0CF8
#define PCI_CONFIG_DATA		0x0CFC

static volatile unsigned char	*ecam_base;
static int			ecam_start_bus, ecam_end_bus = -1;

/*
 * Own 32-bit port accessors: the installed io_inline.h has shipped with
 * inl()/outl() declared on unsigned short, which would truncate the
 * configuration address.
 */
static inline unsigned int
port_inl(unsigned short port)
{
    unsigned int	data;

    asm volatile("inl %1,%0" : "=a" (data) : "d" (port));
    return (data);
}

static inline void
port_outl(unsigned short port, unsigned int data)
{
    asm volatile("outl %0,%1" : : "a" (data), "d" (port));
}

void
pcicfg_set_ecam(volatile unsigned char *base, int start_bus, int end_bus)
{
    ecam_base = base;
    ecam_start_bus = start_bus;
    ecam_end_bus = end_bus;
}

int
pcicfg_probe_mechanism1(void)
{
    unsigned int	saved, probe;

    saved = port_inl(PCI_CONFIG_ADDRESS);
    port_outl(PCI_CONFIG_ADDRESS, 0x80000000);
    probe = port_inl(PCI_CONFIG_ADDRESS);
    port_outl(PCI_CONFIG_ADDRESS, saved);

    return (probe == 0x80000000);
}

static int
args_ok(int bus, int dev, int fn, int off, int size)
{
    if (bus < 0 || bus > 255 || dev < 0 || dev > 31 || fn < 0 || fn > 7)
	return (0);
    if (size != 1 && size != 2 && size != 4)
	return (0);
    if (off < 0 || off > 4095 || (off & (size - 1)) != 0)
	return (0);
    return (1);
}

static volatile unsigned char *
ecam_address(int bus, int dev, int fn, int off)
{
    if (ecam_base == 0 || bus < ecam_start_bus || bus > ecam_end_bus)
	return (0);
    return (ecam_base + (((bus - ecam_start_bus) << 20) | (dev << 15) |
			 (fn << 12) | off));
}

int
pcicfg_read(int bus, int dev, int fn, int off, int size, unsigned int *val)
{
    volatile unsigned char	*p;
    unsigned int		dword;

    if (!args_ok(bus, dev, fn, off, size))
	return (-1);

    if ((p = ecam_address(bus, dev, fn, off)) != 0) {
	switch (size) {
	case 1: *val = *p; break;
	case 2: *val = *(volatile unsigned short *)p; break;
	default: *val = *(volatile unsigned int *)p; break;
	}
	return (0);
    }

    if (off > 255)
	return (-1);

    port_outl(PCI_CONFIG_ADDRESS,
	      0x80000000 | (bus << 16) | (dev << 11) | (fn << 8) | (off & 0xFC));
    dword = port_inl(PCI_CONFIG_DATA);

    switch (size) {
    case 1: *val = (dword >> ((off & 3) * 8)) & 0xFF; break;
    case 2: *val = (dword >> ((off & 2) * 8)) & 0xFFFF; break;
    default: *val = dword; break;
    }
    return (0);
}

int
pcicfg_write(int bus, int dev, int fn, int off, int size, unsigned int val)
{
    volatile unsigned char	*p;
    unsigned int		dword, shift;

    if (!args_ok(bus, dev, fn, off, size))
	return (-1);

    if ((p = ecam_address(bus, dev, fn, off)) != 0) {
	switch (size) {
	case 1: *p = val; break;
	case 2: *(volatile unsigned short *)p = val; break;
	default: *(volatile unsigned int *)p = val; break;
	}
	return (0);
    }

    if (off > 255)
	return (-1);

    port_outl(PCI_CONFIG_ADDRESS,
	      0x80000000 | (bus << 16) | (dev << 11) | (fn << 8) | (off & 0xFC));

    if (size == 4) {
	port_outl(PCI_CONFIG_DATA, val);
	return (0);
    }

    /* Read-modify-write the dword for the narrower sizes. */
    dword = port_inl(PCI_CONFIG_DATA);
    shift = (off & 3) * 8;
    if (size == 1)
	dword = (dword & ~(0xFF << shift)) | ((val & 0xFF) << shift);
    else
	dword = (dword & ~(0xFFFF << shift)) | ((val & 0xFFFF) << shift);
    port_outl(PCI_CONFIG_ADDRESS,
	      0x80000000 | (bus << 16) | (dev << 11) | (fn << 8) | (off & 0xFC));
    port_outl(PCI_CONFIG_DATA, dword);
    return (0);
}
