/* Recovered BIOS ROM and SCSI-ID discovery for an adapter. */
#ifndef A2940_BIOS_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_BIOS_INB(port) inb(port)
#define A2940_BIOS_OUTB(port, value) outb((port), (value))
#else
extern unsigned char a2940_bios_test_inb(unsigned short port);
extern void a2940_bios_test_outb(unsigned short port, unsigned char value);
int Ph_ReadConfig(int, unsigned char, unsigned char, unsigned char);
unsigned char Ph_Pause(int);
unsigned char Ph_WriteHcntrl(short, unsigned char, ...);
#define A2940_BIOS_INB(port) a2940_bios_test_inb((unsigned short)(port))
#define A2940_BIOS_OUTB(port, value) a2940_bios_test_outb((unsigned short)(port), (unsigned char)(value))
#endif

int PH_GetBiosInfo(int host_address, char bus, char device, unsigned char *info)
{
	unsigned int io_base;
	unsigned int scsi_bios;
	unsigned int option_bios;
	unsigned char saved_hcntrl;
	unsigned char saved_page;
	unsigned char restore_page;
	unsigned char value;
	unsigned char first_id;
	unsigned char last_id;
	unsigned char id;
	unsigned char id_count;
	unsigned int index;
	(void)host_address;
	io_base = (unsigned int)Ph_ReadConfig(-1, (unsigned char)bus,
		(unsigned char)device, 16) & 0xfffffffcu;
	info[0] = 0;
	info[1] = 0xff;
	info[2] = 0xff;
	for (index = 0; index <= 7; ++index)
		info[index + 3] = 0xff;
	saved_hcntrl = A2940_BIOS_INB(io_base + 135);
	Ph_Pause((int)io_base);
	saved_page = A2940_BIOS_INB(io_base + 144);
	restore_page = saved_page;
	A2940_BIOS_OUTB(io_base + 144, 2);
	scsi_bios = (unsigned int)A2940_BIOS_INB(io_base + 160);
	scsi_bios |= (unsigned int)A2940_BIOS_INB(io_base + 161) << 8;
	scsi_bios |= (unsigned int)A2940_BIOS_INB(io_base + 162) << 16;
	scsi_bios |= (unsigned int)A2940_BIOS_INB(io_base + 163) << 24;
	option_bios = (unsigned int)A2940_BIOS_INB(io_base + 176);
	option_bios |= (unsigned int)A2940_BIOS_INB(io_base + 177) << 8;
	option_bios |= (unsigned int)A2940_BIOS_INB(io_base + 178) << 16;
	option_bios |= (unsigned int)A2940_BIOS_INB(io_base + 179) << 24;
	value = A2940_BIOS_INB(io_base + 135);
	if ((value & 1) == 0 && scsi_bios != 0 && option_bios != 0 &&
		scsi_bios != 0xffffffffU && option_bios != 0xffffffffU) {
		restore_page = 0;
		info[0] = 1;
		if ((A2940_BIOS_INB(io_base + 172) & 0x40) != 0)
			info[0] = 5;
		if ((A2940_BIOS_INB(io_base + 173) & 1) != 0)
			info[0] |= 2;
		value = A2940_BIOS_INB(io_base + 174);
		first_id = value & 0x0f;
		last_id = value >> 4;
		info[1] = first_id;
		info[2] = last_id;
		id_count = (unsigned char)(last_id - first_id + 1);
		if (id_count != 0) {
			for (id = 0; id < id_count; ++id)
				info[id + 3] = A2940_BIOS_INB(io_base + 164 + id) & 0x0f;
		}
		restore_page = id_count;
		info[12] = A2940_BIOS_INB(io_base + 178);
		info[13] = A2940_BIOS_INB(io_base + 179);
	}
	A2940_BIOS_OUTB(io_base + 144, restore_page);
	Ph_WriteHcntrl((short)io_base, saved_hcntrl);
	return info[0] == 0 ? 0xff : 0;
}
