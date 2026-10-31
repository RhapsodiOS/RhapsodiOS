/* Recovered SCB submission entry points. */
#ifndef A2940_SCB_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_SCB_INB(port) inb(port)
#else
extern unsigned char a2940_scb_test_inb(unsigned short port);
#define A2940_SCB_INB(port) a2940_scb_test_inb((unsigned short)(port))
#endif

#ifdef A2940_SCB_STANDALONE
int PH_Special(char, int, int);
char Ph_ChainAppendEnd(int, unsigned int *);
int Ph_ScbPrepare(int, int *);
int Ph_SendCommand(int **, int);
int Ph_WriteHcntrl(short, unsigned char);
int Ph_NonInit(int);
#endif

char PH_ScbSend(int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char *host = (unsigned char *)(unsigned long)(unsigned int)host_address;
	unsigned char *ha = *(unsigned char **)(host + 52);
	int io_base = *(int *)(host + 4);
	unsigned char hcntrl = A2940_SCB_INB(io_base + 135);
	unsigned short saved_mode = *(unsigned short *)(ha + 284);
	char result;

	*(unsigned short *)(ha + 284) = 1;
	if (scb[8] == 2 || scb[8] == 0) {
		scb[13] &= (unsigned char)~8;
		if (ha[287] == 2)
			PH_Special(16, host_address, scb_address);
		Ph_ChainAppendEnd(host_address, (unsigned int *)scb);
		Ph_ScbPrepare(host_address, (int *)scb);
		if (saved_mode == 0 && (unsigned char)Ph_SendCommand((int **)ha, io_base) != 0)
			hcntrl |= 0x10;
		result = (char)Ph_WriteHcntrl((short)io_base, hcntrl);
	} else {
		result = (char)Ph_NonInit(scb_address);
	}
	*(unsigned short *)(ha + 284) = saved_mode;
	return result;
}
