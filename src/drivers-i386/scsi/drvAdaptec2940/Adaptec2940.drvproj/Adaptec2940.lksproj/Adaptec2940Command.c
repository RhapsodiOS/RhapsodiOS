/* Recovered host-adapter command queue drain. */
#ifndef A2940_COMMAND_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_COMMAND_INB(port) inb(port)
#else
extern unsigned char a2940_command_test_inb(unsigned short port);
#define A2940_COMMAND_INB(port) a2940_command_test_inb((unsigned short)(port))
#endif

int Ph_SendCommand(int **ha, int io_base)
{
	int *scb = ha[0];
	unsigned char index;
	unsigned char hcntrl;
	unsigned char status;
	if (scb != (int *)-1 && *((unsigned short *)ha + 133) != 0) {
		do {
			if (((unsigned char (__cdecl *)(int **, int *))ha[110])(ha, scb) == 0)
				break;
			if (*((unsigned char *)scb + 11) == 16) {
				index = ((unsigned char (__cdecl *)(int **, int *))ha[112])(ha, scb);
				--*((unsigned short *)ha + 133);
				*((unsigned char *)scb + 11) = 64;
				ha[68][index] = (int)scb;
				hcntrl = A2940_COMMAND_INB(io_base + 135);
				Ph_WriteHcntrl((short)io_base, (unsigned char)(hcntrl | 4));
				do {
					status = A2940_COMMAND_INB(io_base + 135);
				} while ((status & 4) == 0);
				((void (__cdecl *)(int, int *, int))ha[119])(index, scb, io_base);
				Ph_WriteHcntrl((short)io_base, hcntrl);
			}
			scb = (int *)*scb;
			if (scb == (int *)-1)
				break;
		} while (*((unsigned short *)ha + 133) != 0);
	}
	return 0;
}
