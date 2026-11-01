/* Recovered bus-device-reset SCB state machine. */
#ifndef A2940_BUS_RESET_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_BUS_RESET_INB(port) inb(port)
#else
extern unsigned char a2940_bus_reset_test_inb(unsigned short port);
#define A2940_BUS_RESET_INB(port) a2940_bus_reset_test_inb((unsigned short)(port))
unsigned char Ph_HaHardReset(int);
char Ph_ChainAppendEnd(int, unsigned int *);
int Ph_ScbPrepare(int, int *);
void Ph_TerminateCommand(int, char);
void *Ph_PostCommand(int);
char Ph_ScbAbort(int);
void *PH_ScbCompleted(int);
unsigned char Ph_WriteHcntrl(short, unsigned char);
#endif

unsigned char Ph_BusDeviceReset(int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	int io_base = *(int *)(host + 4);
	int *ha = *(int **)(host + 52);
	unsigned char target = (unsigned char)(scb[12] >> 4);
	unsigned char index;
	unsigned char status;
	unsigned char *queued;

	if (((unsigned char (__cdecl *)(int *, int))ha[110])(ha, scb_address) != 0) {
		if (host[30] == target) {
			Ph_HaHardReset(host_address);
			Ph_ChainAppendEnd(host_address, (unsigned int *)scb);
			Ph_ScbPrepare(host_address, (int *)scb);
			index = ((unsigned char (__cdecl *)(int *, int))ha[112])(ha, scb_address);
			--*(unsigned short *)((unsigned char *)ha + 266);
			scb[11] = 64;
			((int **)(void *)ha)[68][index] = (int)scb;
			scb[24] = 0;
			scb[43] = 0;
			Ph_TerminateCommand(scb_address, (char)index);
			return (unsigned char)(unsigned long)Ph_PostCommand(host_address);
		}
		for (queued = (unsigned char *)(unsigned long)(unsigned int)ha[0];
			queued != (unsigned char *)(unsigned long)0xffffffffU;
			queued = (unsigned char *)(unsigned long)*(unsigned int *)queued) {
			if (queued != scb && (unsigned char)(queued[12] >> 4) == target)
				Ph_ScbAbort((int)(unsigned long)queued);
		}
		Ph_ChainAppendEnd(host_address, (unsigned int *)scb);
		Ph_ScbPrepare(host_address, (int *)scb);
		scb[15] = 0;
		*(unsigned int *)(scb + 16) = 12;
		scb[13] |= 8;
		index = ((unsigned char (__cdecl *)(int *, int))ha[112])(ha, scb_address);
		--*(unsigned short *)((unsigned char *)ha + 266);
		scb[11] = 65;
		((int **)(void *)ha)[68][index] = (int)scb;
		status = A2940_BUS_RESET_INB(io_base + 135);
		Ph_WriteHcntrl((short)io_base, (unsigned char)(status | 4));
		do {
			status = A2940_BUS_RESET_INB(io_base + 135);
		} while ((status & 4) == 0);
		((void (__stdcall *)(unsigned char))ha[120])(index);
		status = A2940_BUS_RESET_INB(io_base + 135);
		return Ph_WriteHcntrl((short)io_base, (unsigned char)(status & 0xfb));
	}
	scb[43] = 48;
	scb[11] = 4;
	return (unsigned char)(unsigned long)PH_ScbCompleted(scb_address);
}
