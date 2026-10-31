/* Extended-message negotiation receiver reconstructed from IDA 9.4. */
#ifdef A2940_EXTMSG_TESTING
char Ph_BadSeq(int, int);
char Ph_SetNeedNego(unsigned char, short);
int Ph_SyncSet(int);
unsigned char Ph_ClearFast20Reg(int, int);
void Ph_LogFast20Map(int, unsigned char *);
#define A2940_EXTMSG_INB(port) a2940_extmsg_inb((unsigned short)(port))
#define A2940_EXTMSG_OUTB(port, value) a2940_extmsg_outb((unsigned short)(port), (unsigned char)(value))
extern unsigned char a2940_extmsg_inb(unsigned short);
extern void a2940_extmsg_outb(unsigned short, unsigned char);
#else
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#define A2940_EXTMSG_INB(port) inb(port)
#define A2940_EXTMSG_OUTB(port, value) outb((port), (value))
#endif

char Ph_ExtMsgi(int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	int host_address = *(int *)(scb + 4);
	unsigned char target = scb[12] >> 4;
	unsigned char remaining;
	unsigned char message_count;
	unsigned char message_status;
	unsigned char message_phase;
	unsigned char message_index = 3;
	unsigned char max_offset = 15;
	unsigned char max_period = 0;
	unsigned char wide = 0;
	unsigned char fast20 = 0;
	unsigned char sync_register;
	unsigned char current_value;
	unsigned char value;
	unsigned char result;
	unsigned char changed = 0;

	message_count = A2940_EXTMSG_INB(io_base + 58);
	scb[64] = 1;
	scb[65] = message_count;
	remaining = (unsigned char)(message_count - 1);
	message_status = A2940_EXTMSG_INB(io_base + 18);
	scb[66] = message_status;
	if (remaining != 0) {
		while (remaining != 0) {
			(void)A2940_EXTMSG_INB(io_base + 6);
			result = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
			if (result != 0xe0)
				break;
			if (message_index <= 4)
				scb[64 + message_index++] = A2940_EXTMSG_INB(io_base + 18);
			if (--remaining == 0)
				goto negotiation;
		}
		message_phase = A2940_EXTMSG_INB(io_base + 3) & 0xf0;
		if (message_phase == 0xb0) {
			if ((scb[10] & 2) != 0) {
				A2940_EXTMSG_OUTB(io_base + 3, 0xb0);
				(void)Ph_SetNeedNego(target, (short)io_base);
			} else {
				A2940_EXTMSG_OUTB(io_base + 12, 0x40);
				A2940_EXTMSG_OUTB(io_base + 3, 0xa0);
			}
			current_value = A2940_EXTMSG_INB(io_base + 1);
			value = A2940_EXTMSG_INB(io_base + 2);
			A2940_EXTMSG_OUTB(io_base + 2, value & 0xdf);
			A2940_EXTMSG_OUTB(io_base + 2, value | 0x20);
			A2940_EXTMSG_OUTB(io_base + 146, 4);
			A2940_EXTMSG_OUTB(io_base + 1, current_value & 0xf7);
			A2940_EXTMSG_OUTB(io_base + 6, 9);
			A2940_EXTMSG_OUTB(io_base + 1, current_value | 8);
			return (char)(current_value | 8);
		}
		if (result == 0xff)
			return (char)message_phase;
		return Ph_BadSeq(host_address, io_base);
	}

negotiation:
	if ((host[14] & 2) != 0) {
		switch ((host[target + 32] >> 4) & 7) {
		case 0: max_period = 12; break;
		case 1: max_period = 16; break;
		case 2: max_period = 19; break;
		case 4: max_period = 25; break;
		default: break;
		}
	} else {
		max_period = (unsigned char)(6 * ((host[target + 32] >> 4) & 7) + 25);
		if ((host[target + 32] & 0x40) != 0)
			++max_period;
	}
	if ((host[14] & 1) == 0 || (scb[10] & 2) != 0) {
		if ((A2940_EXTMSG_INB(io_base + 31) & 2) != 0)
			fast20 = 1;
	} else {
		fast20 = 0;
		max_offset = 0;
		max_period = 0;
	}

	message_status = scb[66];
	if (message_status == 1) {
		if (scb[65] == 3) {
			current_value = A2940_EXTMSG_INB(io_base + target + 32);
			wide = current_value == 0x8f ? 0 : (current_value & 0x80);
			A2940_EXTMSG_OUTB(io_base + target + 32, wide);
			A2940_EXTMSG_OUTB(io_base + 4, wide);
			if (scb[68] != 0) {
				if (wide != 0)
					max_offset = 8;
				if (scb[68] > max_offset) {
					scb[68] = max_offset;
					changed = 1;
				}
				if (scb[67] < max_period) {
					scb[67] = max_period;
					changed = 1;
				} else if (scb[67] > 0x44) {
					scb[68] = 0;
					goto initiate_extended_message;
				}
			}
			if ((scb[10] & 2) == 0) {
				scb[64] = 0xff;
				goto initiate_extended_message;
			}
			scb[10] &= (unsigned char)~2;
			if (changed == 0) {
				sync_register = (unsigned char)(scb[68] + Ph_SyncSet(scb_address) + wide);
				A2940_EXTMSG_OUTB(io_base + target + 32, sync_register);
				A2940_EXTMSG_OUTB(io_base + 4, sync_register);
				Ph_LogFast20Map(host_address, scb);
				return (char)sync_register;
			}
		}
	} else if (message_status == 3) {
		if (scb[65] == 2) {
			A2940_EXTMSG_OUTB(io_base + target + 32, 0);
			A2940_EXTMSG_OUTB(io_base + 4, 0);
			(void)Ph_ClearFast20Reg(host_address, scb_address);
			if (scb[67] > fast20) {
				scb[67] = fast20;
				changed = 1;
			}
			if ((scb[10] & 2) == 0) {
				host[target + 32] |= 0x80;
				scb[64] = 0xff;
				goto initiate_extended_message;
			}
			scb[10] &= (unsigned char)~2;
			if (changed == 0) {
				if (scb[67] != 0) {
					A2940_EXTMSG_OUTB(io_base + target + 32, 0x80);
					A2940_EXTMSG_OUTB(io_base + 4, 0x80);
					max_offset = 8;
				}
				if ((host[target + 32] & 1) != 0) {
					scb[65] = 3;
					scb[66] = 1;
					scb[67] = max_period;
					scb[68] = max_offset;
					A2940_EXTMSG_OUTB(io_base + 3, 0xf0);
					scb[10] |= 2;
					return (char)-16;
				}
				return (char)host_address;
			}
		}
		scb[65] = 2;
	}

	A2940_EXTMSG_OUTB(io_base + 3, 0xf0);
	(void)A2940_EXTMSG_INB(io_base + 6);
	result = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
	if (result == 0xa0) {
		A2940_EXTMSG_OUTB(io_base + 3, 0xa0);
		A2940_EXTMSG_OUTB(io_base + 12, 0x40);
		current_value = A2940_EXTMSG_INB(io_base + 1);
		A2940_EXTMSG_OUTB(io_base + 1, current_value & 0xf7);
		A2940_EXTMSG_OUTB(io_base + 6, 7);
		current_value = A2940_EXTMSG_INB(io_base + 1) | 8;
		A2940_EXTMSG_OUTB(io_base + 1, current_value);
		return (char)current_value;
	}
	if (result != 0xff)
		return Ph_BadSeq(host_address, io_base);
	return (char)result;

initiate_extended_message:
	A2940_EXTMSG_OUTB(io_base + 3, 0xf0);
	scb[10] |= 2;
	return (char)-16;

}
