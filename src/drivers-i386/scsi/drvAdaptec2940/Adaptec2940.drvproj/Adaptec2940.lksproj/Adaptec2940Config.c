/* PCI configuration-space access recovered from the IDA reference. */
#ifndef A2940_CONFIG_STANDALONE
#include "Adaptec2940HIM.h"
#else
int PH_GetNumOfBusesOSM(void);
int Ph_ReadConfig(int, unsigned char, unsigned char, unsigned char);
int Ph_WriteConfig(int, unsigned char, unsigned char, unsigned char, unsigned int);
unsigned char Ph_NoAssistTerm(int);
int Ph_ReadCableStatus(int);
int Ph_UpdateEeprom(unsigned short *, int, unsigned short);
char Ph_MemorySet(unsigned char *, char, int);
unsigned char Ph_Pause(int);
unsigned char Ph_WriteHcntrl(short, unsigned char, ...);
int Ph_GetDrvrConfig(int);
int Ph_ReadEeprom(unsigned short *, int);
int Ph_InitDrvrHA(int);
int Ph_LoadSequencer(void *);
unsigned char Ph_ResetSCSI(int);
char Ph_CheckSyncNego(int);
char Ph_ResetChannel(int);
#endif

#if defined(A2940_TEST) || defined(A2940_CONFIG_STANDALONE)
extern void a2940_test_outb(unsigned short port, unsigned char value);
extern unsigned char a2940_test_inb(unsigned short port);
extern void a2940_test_outl(unsigned short port, unsigned int value);
extern unsigned int a2940_test_inl(unsigned short port);
#define A2940_CONFIG_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#define A2940_CONFIG_INB(port) a2940_test_inb((unsigned short)(port))
#define A2940_CONFIG_OUTL(port, value) a2940_test_outl((unsigned short)(port), (unsigned int)(value))
#define A2940_CONFIG_INL(port) a2940_test_inl((unsigned short)(port))
#else
#include <driverkit/i386/ioPorts.h>
#define A2940_CONFIG_OUTB(port, value) outb((port), (value))
#define A2940_CONFIG_INB(port) inb((port))
#define A2940_CONFIG_OUTL(port, value) outl((port), (value))
#define A2940_CONFIG_INL(port) inl((port))
#endif

#if defined(A2940_TEST)
extern int a2940_test_config_osm_override;
extern int a2940_test_bus_count_override;
#endif

int PH_GetNumOfBusesOSM(void)
{
#if defined(A2940_TEST)
	if (a2940_test_bus_count_override >= 0)
		return a2940_test_bus_count_override;
#endif
	return 0x55555555;
}

int PH_ReadConfigOSM(int selector, unsigned char bus, unsigned char device,
		     unsigned char reg)
{
	(void)selector;
	(void)bus;
	(void)device;
	(void)reg;
#if defined(A2940_TEST)
	if (a2940_test_config_osm_override >= 0)
		return 0x55555500 | (a2940_test_config_osm_override & 0xff);
#endif
	return 0x55555555;
}

int PH_WriteConfigOSM(int selector, unsigned char bus, unsigned char device,
		      unsigned char reg, unsigned int value)
{
	(void)selector;
	(void)bus;
	(void)device;
	(void)reg;
	(void)value;
#if defined(A2940_TEST)
	if (a2940_test_config_osm_override >= 0)
		return 0x55555500 | (a2940_test_config_osm_override & 0xff);
#endif
	return 0x55555555;
}

/* Mechanism-1 presence probing is also the dispatch test for config I/O. */
int Ph_AccessConfig(unsigned char requested_bus)
{
	unsigned int bus = 0;
	unsigned int device;
	unsigned int value;

	for (;;) {
		for (device = 0; device <= 0x1f; ++device) {
			unsigned int address = 0x80000008U | (bus << 16) | (device << 11);
			A2940_CONFIG_OUTL(0xcf8, address);
			value = A2940_CONFIG_INL(0xcfc);
			A2940_CONFIG_OUTL(0xcf8, 0);
			if ((value & 0xff000000U) != 0xff000000U)
				return 1;
		}
		if (requested_bus == bus)
			return 2;
		bus = requested_bus;
	}
}

int PH_FindMechanism(void)
{
	unsigned int bus;

	for (bus = 0; bus <= 0xff; ++bus) {
		if ((unsigned char)Ph_AccessConfig((unsigned char)bus) == 1)
			return 1;
	}
	return 2;
}

int PH_FindHA(short bus_number, short device_number)
{
	unsigned char result = 0;
	unsigned char bus = (unsigned char)bus_number;
	unsigned char device = (unsigned char)device_number;
	int config = Ph_ReadConfig(-1, bus, device, 0);
	int command;

	if (((config & 0x00ffffff) == 0x00789004 ||
	     (config & 0x00ffffff) == 0x00759004) &&
	    config != 276336644 && (config & 0x08000000) == 0) {
		command = Ph_ReadConfig(-1, bus, device, 4);
		if ((command & 1) == 0)
			result = 0x80;
		++result;
		if ((command & 4) == 0)
			Ph_WriteConfig(-1, bus, device, 4, (unsigned int)(command | 4));
	}
	return result;
}

int PH_GetNumOfBuses(void)
{
	int override = PH_GetNumOfBusesOSM();
	unsigned short bus_count = 0;
	unsigned short highest_secondary = 0;
	unsigned short bus = 0;
	unsigned char first_device;
	unsigned char device;
	unsigned char secondary = 0;
	unsigned int class_code;

	if (override != 0x55555555)
		return (unsigned short)override;
	do {
		secondary = 0;
		first_device = 0;
		for (;;) {
			class_code = (unsigned int)Ph_ReadConfig(-1, (unsigned char)bus,
				first_device, 8) & 0xffffff00U;
			if (class_code == 0x06000000U || class_code == 0)
				break;
			if (++first_device > 0x1f)
				goto next_bus;
		}
		++bus_count;
		for (device = 0; device <= 0x1f; ++device) {
			if (device != first_device) {
				int class_and_subclass = Ph_ReadConfig(-1, (unsigned char)bus,
					device, 8) & 0xffffff00;
				if (class_and_subclass == 0x06040000) {
					secondary = (unsigned char)(Ph_ReadConfig(-1,
						(unsigned char)bus, device, 24) >> 16);
					if ((unsigned short)(secondary + 1) > bus_count) {
						bus_count = (unsigned short)(secondary + 1);
						highest_secondary = secondary;
					}
				}
			}
		}
next_bus:
		if (secondary != 0)
			bus = (unsigned short)(secondary + 1);
		else
			++bus;
	} while (bus <= 0xff);
	if (bus_count == 256)
		return (unsigned short)(highest_secondary + 1);
	return bus_count;
}

int Ph_AutoTermCable(int host_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned char status;
	unsigned char cable;
	unsigned char term_bits = 0;
	int result;

	if ((host[15] & 0x20) == 0)
		return Ph_NoAssistTerm(host_address);
	status = (unsigned char)Ph_ReadCableStatus(host_address);
	cable = A2940_CONFIG_INB(io_base + 31);
	if ((cable & 2) == 0) {
		if ((status & 4) != 0 && (status & 1) != 0)
			term_bits &= (unsigned char)~2;
		else
			term_bits |= 2;
	} else {
		if ((status & 7) == 6) {
			term_bits &= (unsigned char)~2;
		} else if ((status & 4) == 0 && (status & 1) != 0 &&
			   (status & 2) != 0) {
			term_bits &= (unsigned char)~2;
		} else if ((status & 4) != 0 && (status & 1) != 0 &&
			   (status & 2) == 0) {
			term_bits &= (unsigned char)~2;
		} else {
			term_bits |= 2;
		}
		if ((status & 7) == 6)
			term_bits &= (unsigned char)~1;
		else
			term_bits |= 1;
	}
	if (((term_bits & 1) != 0) != ((host[13] & 0x20) != 0) ||
	    ((term_bits & 2) != 0) != ((host[13] & 0x10) != 0)) {
		host[13] &= (unsigned char)~0x10;
		host[13] |= (unsigned char)((term_bits << 3) & 0x10);
		host[13] &= (unsigned char)~0x20;
		host[13] |= (unsigned char)((term_bits & 1) << 5);
		return Ph_UpdateEeprom((unsigned short *)host, (int)io_base, 17);
	}
	result = (host[13] & 0x10) != 0;
	return result;
}

unsigned char PH_GetConfig(int host_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned char bus = host[8];
	unsigned char device = host[9];
	unsigned int bar0;
	unsigned int io_base;
	unsigned char hcntrl;
	unsigned char wide;
	unsigned char value;
	unsigned char i;
	int result;

	bar0 = (unsigned int)Ph_ReadConfig(host_address, bus, device, 16);
	io_base = (bar0 & 0xffffff00U) | (bar0 & 0xfcU);
	*(unsigned int *)(host + 4) = io_base;
	host[1] = A2940_CONFIG_INB(io_base + 130);
	host[0] = A2940_CONFIG_INB(io_base + 131);
	host[2] = 0;
	host[3] = (unsigned char)Ph_ReadConfig(host_address, bus, device, 8);
	hcntrl = A2940_CONFIG_INB(io_base + 135);
	if ((hcntrl & 1) != 0)
		host[12] |= 0x80;
	else
		Ph_Pause((int)io_base);
	Ph_GetDrvrConfig(host_address);
	host[19] = (unsigned char)Ph_ReadConfig(host_address, bus, device, 60);
	host[21] = A2940_CONFIG_INB(io_base + 133) & 0xfc;
	host[22] = 3;
	host[30] = 7;
	host[12] |= 0x20;
	if (host[0] == 116)
		*(unsigned int *)(host + 12) |= 0x200;
	wide = A2940_CONFIG_INB(io_base + 31);
	if ((wide & 2) != 0) {
		host[31] = 16;
		value = 0x81;
		*(unsigned short *)(host + 48) = 0xffff;
	} else {
		host[31] = 8;
		value = 1;
		*(unsigned short *)(host + 48) = 0x00ff;
	}
	Ph_MemorySet(host + 32, (char)value, host[31]);
	host[13] |= 0x20;
	host[13] |= 0x10;
	if ((unsigned short)Ph_ReadEeprom((unsigned short *)host, (int)io_base) != 0 &&
	    (signed char)host[12] >= 0) {
		host[22] = A2940_CONFIG_INB(io_base + 134) >> 6;
		host[30] = A2940_CONFIG_INB(io_base + 5) & 0x0f;
		host[12] |= A2940_CONFIG_INB(io_base + 2) & 0x38;
		for (i = 0; i < host[31]; ++i) {
			value = A2940_CONFIG_INB(io_base + i + 32);
			if (value != 0x8f) {
				host[i + 32] = value & 0xf0;
				if ((value & 0x0f) != 0)
					host[i + 32] |= 1;
			}
		}
		host[48] = (unsigned char)~A2940_CONFIG_INB(io_base + 50);
		if (host[31] == 16)
			host[49] = (unsigned char)~A2940_CONFIG_INB(io_base + 51);
	}
	if ((host[15] & 0x10) == 0 && (host[15] & 0x20) != 0)
		Ph_AutoTermCable(host_address);
	result = ((Ph_ReadConfig(host_address, bus, device, 64) & 0x1000) != 0 &&
		  (host[14] & 2) != 0) ? 2 : 0;
	host[14] &= (unsigned char)~2;
	host[14] |= (unsigned char)result;
	if ((hcntrl & 1) == 0)
		Ph_WriteHcntrl((short)io_base, hcntrl);
	host[12] |= 0x80;
	return (unsigned char)result;
}

int PH_InitHA(int host_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned char value;
	unsigned char mode;
	unsigned short load_result;

	Ph_WriteHcntrl((short)io_base, 4);
	Ph_InitDrvrHA(host_address);
	if ((signed char)host[12] < 0) {
		load_result = (unsigned short)Ph_LoadSequencer(host);
		if (load_result != 0)
			return load_result;
	}
	if ((signed char)host[12] < 0) {
		A2940_CONFIG_OUTB(io_base + 5, host[30]);
		if ((host[12] & 0x40) != 0) {
			Ph_ResetSCSI((int)io_base);
			Ph_CheckSyncNego(host_address);
		} else {
			host[14] &= (unsigned char)~1;
		}
		Ph_ResetChannel(host_address);
		value = A2940_CONFIG_INB(io_base + 31);
		A2940_CONFIG_OUTB(io_base + 31, value & 0x3f);
	}
	A2940_CONFIG_OUTB(io_base + 96, 0x32);
	A2940_CONFIG_OUTB(io_base + 98, 0);
	A2940_CONFIG_OUTB(io_base + 99, 0);
	A2940_CONFIG_OUTB(io_base + 104, 0x80);
	A2940_CONFIG_OUTB(io_base + 134, (unsigned char)(host[22] << 6));
	A2940_CONFIG_OUTB(io_base + 1, 0x80);
	if (host[31] == 16) {
		A2940_CONFIG_OUTB(io_base + 30, 0x20);
		do {
			value = A2940_CONFIG_INB(io_base + 30);
		} while ((signed char)value < 0);
		A2940_CONFIG_OUTB(io_base + 30, 0x28);
		mode = (host[13] & 0x20) != 0 ? 0x58 : 0x18;
		A2940_CONFIG_OUTB(io_base + 29, mode);
		A2940_CONFIG_OUTB(io_base + 29, (unsigned char)(mode - 0x10));
		A2940_CONFIG_OUTB(io_base + 29, 0);
		A2940_CONFIG_OUTB(io_base + 30, 0);
	}
	if ((host[14] & 2) != 0) {
		A2940_CONFIG_OUTB(io_base + 48, 0);
		A2940_CONFIG_OUTB(io_base + 49, 0);
	}
	A2940_CONFIG_OUTB(io_base + 50, (unsigned char)~host[48]);
	A2940_CONFIG_OUTB(io_base + 51, (unsigned char)~host[49]);
	Ph_WriteHcntrl((short)io_base, 2);
	return 0;
}

int Ph_ReadConfig(int selector, unsigned char bus, unsigned char device,
		  unsigned char reg)
{
	int mode = PH_ReadConfigOSM(selector, bus, device, reg);
	unsigned int value;
	unsigned short port;

	if ((mode & 0xffffff00) != 0x55555500)
		return mode;
	mode &= 0xff;
	if (mode != 1 && mode != 2)
		mode = Ph_AccessConfig(bus);
	if (mode == 1) {
		unsigned int address = 0x80000000U | ((unsigned int)bus << 16) |
			((unsigned int)(device & 0x1f) << 11) | reg;
		A2940_CONFIG_OUTL(0xcf8, address);
		value = A2940_CONFIG_INL(0xcfc);
		A2940_CONFIG_OUTL(0xcf8, 0);
		return (int)value;
	}
	if (mode == 2) {
		if (device > 0x0f)
			return -1;
		port = (unsigned short)(0xc000U | ((unsigned int)device << 8) | reg);
		A2940_CONFIG_OUTB(0xcfa, bus);
		A2940_CONFIG_OUTB(0xcf8, 0x60);
		value = A2940_CONFIG_INL(port);
		A2940_CONFIG_OUTB(0xcfa, 0);
		A2940_CONFIG_OUTB(0xcf8, 0);
		return (int)value;
	}
	return mode;
}

int Ph_WriteConfig(int selector, unsigned char bus, unsigned char device,
		   unsigned char reg, unsigned int value)
{
	int mode = PH_WriteConfigOSM(selector, bus, device, reg, value);
	unsigned int present;
	unsigned short port;

	if ((mode & 0xffffff00) != 0x55555500)
		return 0;
	mode &= 0xff;
	if (mode != 1 && mode != 2)
		mode = Ph_AccessConfig(bus);
	if (mode == 1) {
		unsigned int address = 0x80000000U | ((unsigned int)bus << 16) |
			((unsigned int)(device & 0x1f) << 11) | reg;
		A2940_CONFIG_OUTL(0xcf8, address);
		present = A2940_CONFIG_INL(0xcfc);
		if (present == 0xffffffffU) {
			A2940_CONFIG_OUTL(0xcf8, 0);
			return -1;
		}
		A2940_CONFIG_OUTL(0xcfc, value);
		A2940_CONFIG_OUTL(0xcf8, 0);
		return 0;
	}
	if (mode == 2) {
		if (device > 0x0f)
			return -1;
		port = (unsigned short)(0xc000U | ((unsigned int)device << 8) | reg);
		A2940_CONFIG_OUTB(0xcfa, bus);
		A2940_CONFIG_OUTB(0xcf8, 0x60);
		A2940_CONFIG_OUTL(port, value);
		A2940_CONFIG_OUTB(0xcfa, 0);
		A2940_CONFIG_OUTB(0xcf8, 0);
	}
	return 0;
}
