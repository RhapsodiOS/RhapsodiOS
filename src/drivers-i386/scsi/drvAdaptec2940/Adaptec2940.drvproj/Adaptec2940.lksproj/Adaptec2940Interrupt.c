/* IDA-reconstructed HIM interrupt state machine. */
#ifdef A2940_INTERRUPT_STANDALONE
extern void a2940_test_outb(unsigned short, unsigned char);
extern unsigned char a2940_test_inb(unsigned short);
int Ph_ReadIntstat(short);
int Ph_WriteHcntrl(short, unsigned char, ...);
char Ph_IntSrst(int);
char Ph_CheckLength(int, short);
char Ph_CdbAbort(int, int);
unsigned char Ph_SendMsgo(unsigned char *, int);
char Ph_CheckCondition(int, short);
char Ph_BadSeq(int, int);
char Ph_ExtMsgi(int, int);
char Ph_HandleMsgi(int, int);
int Ph_TargetAbort(int, int, int);
char Ph_Negotiate(int, int);
char Ph_IntSelto(int, int);
char Ph_IntFree(int, int);
unsigned char Ph_ParityError(int, int);
int Ph_SendCommand(int **, int);
void *Ph_PostCommand(int);
int Ph_SendTrmMsg(unsigned int, unsigned int);
int Ph_TrmCmplt(void);
#define A2940_INTERRUPT_INB(port) a2940_test_inb((unsigned short)(port))
#define A2940_INTERRUPT_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#else
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_INTERRUPT_INB(port) inb(port)
#define A2940_INTERRUPT_OUTB(port, value) outb((port), (value))
#endif

#ifndef A2940_HA_IO_BASE_OFFSET
#define A2940_HA_IO_BASE_OFFSET 4
#endif
#define A2940_INTERRUPT_CHAIN_HEAD_OFFSET 52

static unsigned char *a2940_interrupt_host(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

int PH_IntHandler(int host_address)
{
	unsigned char *host = a2940_interrupt_host(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char *ha = *(unsigned char **)(host + A2940_INTERRUPT_CHAIN_HEAD_OFFSET);
	unsigned char control = A2940_INTERRUPT_INB(io_base + 135);
	unsigned char intstat = (unsigned char)Ph_ReadIntstat((short)io_base);
	unsigned char cause = intstat & 0x0f;
	unsigned char result = 0;
	unsigned char saved_hcntrl;
	unsigned short saved_mode;
	unsigned int pass = 0;

	if (cause == 0)
		return 0;
	saved_mode = *(unsigned short *)(ha + 284);
	if (saved_mode == 1 && (control & 0x10) != 0)
		return cause;
	*(unsigned short *)(ha + 284) = 1;
	if ((control & 2) != 0) {
		control |= 0x10;
		Ph_WriteHcntrl((short)io_base, control);
	}
	saved_hcntrl = control;

	do {
		unsigned int completion = (unsigned int)cause << 8;
		while ((intstat & 2) != 0) {
			int (*completion_handler)(int, unsigned char, unsigned int);
			completion_handler = *(int (**)(int, unsigned char, unsigned int))(ha + 444);
			completion = (unsigned int)completion_handler(host_address, control, completion);
			if ((completion >> 24) == 0)
				break;
			intstat = (unsigned char)Ph_ReadIntstat((short)io_base);
		}
		cause = (unsigned char)(completion >> 8);
		while ((intstat & 0x0d) != 0) {
			unsigned char scsi_status = A2940_INTERRUPT_INB(io_base + 12);
			unsigned char scb_index;
			int scb_address;

			if ((scsi_status & 0x20) != 0) {
				Ph_IntSrst(host_address);
				intstat = 4;
				scsi_status = 0;
				scb_index = 0xff;
			} else {
				scb_index = A2940_INTERRUPT_INB(io_base + ((scsi_status & 0x80) ? 59 : 60));
			}
			if (scb_index == 0xff) {
				scb_address = -1;
			} else {
				int *scb_map = *(int **)(ha + 272);
				scb_address = scb_map[scb_index];
				if (scb_address == -2) {
					cause |= 0x80;
					break;
				}
			}
			cause |= 0x20;
			if ((intstat & 1) != 0) {
				unsigned char reason = intstat & 0xf0;
				A2940_INTERRUPT_OUTB(io_base + 146, 1);
				if (scb_address == -1)
					intstat = (intstat & 0x0f) | 0x80;
				switch (reason) {
				case 0x30:
					Ph_CheckLength(scb_address, (short)io_base);
					break;
				case 0x10:
					Ph_CdbAbort(scb_address, io_base);
					break;
				case 0x20:
					Ph_SendMsgo((unsigned char *)(unsigned long)(unsigned int)scb_address, io_base);
					break;
				case 0x50:
					Ph_CheckCondition(scb_address, (short)io_base);
					break;
				case 0x60:
					Ph_BadSeq(host_address, io_base);
					break;
				case 0x70:
					Ph_ExtMsgi(scb_address, io_base);
					break;
				case 0x40:
					Ph_HandleMsgi(scb_address, io_base);
					break;
				case 0x80:
				case 0x90:
					Ph_TargetAbort(host_address, scb_address, io_base);
					break;
				case 0:
					Ph_Negotiate(scb_address, io_base);
					break;
				default:
					break;
				}
			} else if ((intstat & 4) != 0) {
				if ((signed char)scsi_status < 0)
					Ph_IntSelto(host_address, scb_address);
				else if ((scsi_status & 8) != 0)
					Ph_IntFree(host_address, scb_address);
				else if ((scsi_status & 4) != 0)
					Ph_ParityError(scb_address, io_base);
				A2940_INTERRUPT_OUTB(io_base + 146, 4);
				intstat = (unsigned char)Ph_ReadIntstat((short)io_base);
			} else if ((intstat & 8) != 0) {
				A2940_INTERRUPT_OUTB(io_base + 146, 8);
				A2940_INTERRUPT_OUTB(io_base + 104, 0x80);
				control = A2940_INTERRUPT_INB(io_base + 96);
				A2940_INTERRUPT_OUTB(io_base + 96, control & 0xf7);
				Ph_SendTrmMsg(0, 0);
				Ph_TrmCmplt();
			}
		control &= (unsigned char)~4;
		Ph_WriteHcntrl((short)io_base, control);
		intstat = (unsigned char)Ph_ReadIntstat((short)io_base);
		}
		Ph_SendCommand((int **)ha, io_base);
		Ph_PostCommand(host_address);
		if ((cause & 0x80) != 0 && ha[270] == 0)
			break;
		if (++pass == 0xff ||
		    (((intstat & 0x0f) == 0) && ha[270] == 0)) {
			Ph_WriteHcntrl((short)io_base, saved_hcntrl & 0xf9);
			break;
		}
		cause = (unsigned char)Ph_ReadIntstat((short)io_base);
		intstat = cause;
	} while (1);

	*(unsigned short *)(ha + 284) = saved_mode;
	Ph_SendCommand((int **)ha, io_base);
	return Ph_WriteHcntrl((short)io_base, saved_hcntrl & 0xeb);
}
