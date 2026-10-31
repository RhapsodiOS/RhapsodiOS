/* Recovered special-command dispatcher. */
#ifndef A2940_SPECIAL_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_SPECIAL_INB(port) inb(port)
#else
extern unsigned char a2940_special_test_inb(unsigned short port);
#define A2940_SPECIAL_INB(port) a2940_special_test_inb((unsigned short)(port))
int Ph_ScbAbort(int);
unsigned char Ph_HaHardReset(int);
char Ph_ScbRenego(int, unsigned char);
int SWAPCurrScratchRam(int, char);
int Ph_SendCommand(int **, int);
int Ph_WriteHcntrl(short, unsigned char);
#endif

int PH_Special(char command, int host_address, int scb_address)
{
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	int io_base = *(int *)(host + 4);
	unsigned char *ha = *(unsigned char **)(host + 52);
	unsigned char saved_hcntrl;
	unsigned char status;
	unsigned short saved_mode = *(unsigned short *)(ha + 284);
	int result = 0;

	*(unsigned short *)(ha + 284) = 1;
	switch (command) {
	case 0:
		Ph_ScbAbort(scb_address);
		break;
	case 2:
		Ph_HaHardReset(host_address);
		break;
	case 3:
		status = A2940_SPECIAL_INB(io_base + 135);
		Ph_WriteHcntrl((short)io_base, (unsigned char)(status | 4));
		do {
			status = A2940_SPECIAL_INB(io_base + 135);
		} while ((status & 4) == 0);
		Ph_ScbRenego(host_address, *((unsigned char *)(unsigned long)(unsigned int)scb_address + 12));
		status = A2940_SPECIAL_INB(io_base + 135);
		Ph_WriteHcntrl((short)io_base, (unsigned char)(status & 0xfb));
		break;
	case 5:
		if (ha[287] != 2) {
			if (*(unsigned int *)ha == 0xffffffffU) {
				saved_hcntrl = A2940_SPECIAL_INB(io_base + 135);
				Ph_WriteHcntrl((short)io_base, (unsigned char)(saved_hcntrl | 4));
				do {
					status = A2940_SPECIAL_INB(io_base + 135);
				} while ((status & 4) == 0);
				result = SWAPCurrScratchRam(host_address, 1);
				ha[287] = 2;
				Ph_WriteHcntrl((short)io_base, saved_hcntrl);
			} else {
				result = -1;
			}
		}
		break;
	case 16:
		saved_hcntrl = A2940_SPECIAL_INB(io_base + 135);
		Ph_WriteHcntrl((short)io_base, (unsigned char)(saved_hcntrl | 4));
		do {
			status = A2940_SPECIAL_INB(io_base + 135);
		} while ((status & 4) == 0);
		result = SWAPCurrScratchRam(host_address, 1);
		ha[287] = 3;
		Ph_WriteHcntrl((short)io_base, saved_hcntrl);
		break;
	default:
		break;
	}
	if ((command == 2 || command == 0) && saved_mode == 0 &&
		(unsigned char)Ph_SendCommand((int **)ha, io_base) != 0) {
		status = A2940_SPECIAL_INB(io_base + 135);
		Ph_WriteHcntrl((short)io_base, (unsigned char)(status | 0x10));
	}
	*(unsigned short *)(ha + 284) = saved_mode;
	return result;
}
