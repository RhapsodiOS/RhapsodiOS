/* Recovered HIM routines. Each body is kept close to its IDA control flow. */
#ifndef A2940_HIM_STANDALONE
#include "Adaptec2940HIM.h"
#include <driverkit/i386/ioPorts.h>
#else
extern void a2940_test_outb(unsigned short port, unsigned char value);
extern unsigned char a2940_test_inb(unsigned short port);
extern void a2940_test_outl(unsigned short port, unsigned int value);
extern unsigned int a2940_test_inl(unsigned short port);
unsigned char Ph_InBuffer(short, int, int);
unsigned char Ph_OutBuffer(short, int, int);
int Ph_RebuildEEControl(int, short);
char Ph_CheckLength(int, short);
unsigned char Ph_ParityError(int, int);
char Ph_IntSelto(int, int);
char Ph_IntFree(int, int);
void *PH_ScbCompleted(int);
void *Ph_PostCommand(int);
char Ph_Negotiate(int, int);
int Ph_Wt4Req(int, short);
unsigned char Ph_SyncNego(int, int);
#endif

#if defined(A2940_TEST) || defined(A2940_HIM_STANDALONE)
#define A2940_HIM_OUTB(port, value) a2940_test_outb((unsigned short)(port), (unsigned char)(value))
#define A2940_HIM_INB(port) a2940_test_inb((unsigned short)(port))
#define A2940_HIM_OUTL(port, value) a2940_test_outl((unsigned short)(port), (unsigned int)(value))
#define A2940_HIM_INL(port) a2940_test_inl((unsigned short)(port))
#if defined(A2940_TEST)
extern unsigned char a2940_test_eeprom_inb(unsigned short port);
#define A2940_HIM_EEPROM_INB(port) a2940_test_eeprom_inb((unsigned short)(port))
#else
#define A2940_HIM_EEPROM_INB(port) A2940_HIM_INB(port)
#endif

#if defined(A2940_TEST)
extern int a2940_test_config_osm_override;
#endif
#else
#define A2940_HIM_OUTB(port, value) outb((port), (value))
#define A2940_HIM_INB(port) inb((port))
#define A2940_HIM_OUTL(port, value) outl((port), (value))
#define A2940_HIM_INL(port) inl((port))
#define A2940_HIM_EEPROM_INB(port) A2940_HIM_INB(port)
#endif

int Ph_UnPause(int io_base);

#define A2940_CHAIN_HEAD_OFFSET 52
#define A2940_CHAIN_EMPTY_FLAG_OFFSET 13
#define A2940_CHAIN_EMPTY_FLAG 0x80
#define A2940_CHAIN_TARGET_OFFSET 62
#define A2940_CHAIN_LUN_OFFSET 64
#define A2940_CHAIN_TARGET_IN_SCB_OFFSET 268
#define A2940_CHAIN_LUN_IN_SCB_OFFSET 269
#define A2940_CHAIN_END 0xffffffffU
#ifndef A2940_HA_IO_BASE_OFFSET
#define A2940_HA_IO_BASE_OFFSET 4
#endif

static unsigned char *a2940_host_from_address(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

static unsigned int *a2940_chain_from_host(unsigned char *host)
{
	return *(unsigned int **)(host + A2940_CHAIN_HEAD_OFFSET);
}

char Ph_ChainAppendEnd(int host_address, unsigned int *scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	unsigned int *tail;
	unsigned int result = 0;

	*scb = A2940_CHAIN_END;
	if (chain[0] == A2940_CHAIN_END) {
		chain[0] = (unsigned int)scb;
		host[A2940_CHAIN_EMPTY_FLAG_OFFSET] &= (unsigned char)~A2940_CHAIN_EMPTY_FLAG;
		((unsigned char *)chain)[268] = host[A2940_CHAIN_TARGET_OFFSET];
		((unsigned char *)chain)[269] = host[A2940_CHAIN_LUN_OFFSET];
		result = host[A2940_CHAIN_LUN_OFFSET];
	} else {
		tail = (unsigned int *)chain[1];
		*tail = (unsigned int)scb;
		result = (unsigned int)tail;
	}
	tail = scb;
	while (*tail != A2940_CHAIN_END)
		tail = (unsigned int *)*tail;
	chain[1] = (unsigned int)tail;
	return (char)result;
}

int Ph_ChainPrevious(int *chain, int scb_address)
{
	unsigned int *node;
	unsigned int *head = (unsigned int *)chain[0];
	unsigned int target = (unsigned int)scb_address;

	if ((unsigned int)chain[0] == A2940_CHAIN_END)
		return -1;
	node = head;
	while (*node != target) {
		if ((unsigned int *)chain[1] == node || *node == A2940_CHAIN_END) {
			if (*node != target && (unsigned int)chain[0] != target)
				return -1;
			return (int)node;
		}
		node = (unsigned int *)*node;
	}
	return (int)node;
}

int Ph_ChainRemove(int host_address, unsigned int *scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	int previous = -1;

	if ((unsigned int *)chain[0] == scb)
		chain[0] = *scb;
	else {
		previous = Ph_ChainPrevious((int *)chain, (int)scb);
		*(unsigned int *)previous = *scb;
	}
	if (*scb == A2940_CHAIN_END)
		chain[1] = (unsigned int)previous;
	if (chain[0] == A2940_CHAIN_END)
		host[A2940_CHAIN_EMPTY_FLAG_OFFSET] |= A2940_CHAIN_EMPTY_FLAG;
	return previous;
}

void Ph_ChainInsertFront(void)
{
	/* IDA body is a seven-byte prologue/epilogue with no state changes. */
}

char Ph_MemorySet(unsigned char *destination, char value, int length)
{
	short index;
	char result = value;

	for (index = 0; index < length; result = (char)index) {
		*destination++ = (unsigned char)value;
		++index;
	}
	return result;
}

unsigned char Ph_WriteHcntrl(short io_base, unsigned char value, ...)
{
	unsigned char control = value;
	unsigned char observed;

	if ((value & 0x04) == 0) {
		observed = A2940_HIM_INB(io_base + 0x87);
		if ((observed & 0x04) == 0) {
			A2940_HIM_OUTB(io_base + 0x87, observed | 0x04);
			do {
				observed = A2940_HIM_INB(io_base + 0x87);
			} while ((observed & 0x04) == 0);
		}
		observed = A2940_HIM_INB(io_base + 0x91);
		if ((observed & 0x0d) != 0)
			control = value | 0x04;
	}
	A2940_HIM_OUTB(io_base + 0x87, control);
	return control;
}

int Ph_ReadIntstat(short io_base)
{
	unsigned char original = A2940_HIM_INB(io_base + 0x87);
	unsigned char status;
	unsigned char restore;

	if ((original & 0x04) != 0)
		return A2940_HIM_INB(io_base + 0x91);
	A2940_HIM_OUTB(io_base + 0x87, original | 0x04);
	do {
		status = A2940_HIM_INB(io_base + 0x87);
	} while ((status & 0x04) == 0);
	status = A2940_HIM_INB(io_base + 0x91);
	restore = original;
	if ((status & 0x0d) != 0)
		restore |= 0x04;
	A2940_HIM_OUTB(io_base + 0x87, restore);
	return status;
}

int PH_PollInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char original = A2940_HIM_INB(io_base + 135);
	unsigned char control;
	unsigned char status;
	A2940_HIM_OUTB(io_base + 135, original | 0x04);
	do {
		control = A2940_HIM_INB(io_base + 135);
	} while ((control & 0x04) == 0);
	status = Ph_ReadIntstat((short)io_base) & 0x0f;
	Ph_WriteHcntrl((short)io_base, original);
	return status;
}

unsigned char Ph_Delay(int io_base, int count)
{
	unsigned char timer_low;
	unsigned char timer_high;
	unsigned char control;
	unsigned char result;
	int iteration;
	if (count != 0) {
		timer_low = A2940_HIM_INB(io_base + 176);
		timer_high = A2940_HIM_INB(io_base + 177);
		for (iteration = 0; iteration != count; ++iteration) {
			A2940_HIM_OUTB(io_base + 176, 0x54);
			A2940_HIM_OUTB(io_base + 177, 0x0b);
			A2940_HIM_OUTB(io_base + 98, 4);
			A2940_HIM_OUTB(io_base + 99, 0);
			Ph_UnPause(io_base);
			do {
				control = A2940_HIM_INB(io_base + 135);
			} while ((control & 0x04) == 0);
			A2940_HIM_OUTB(io_base + 146, 1);
		}
		A2940_HIM_OUTB(io_base + 176, timer_low);
		result = timer_high;
		A2940_HIM_OUTB(io_base + 177, timer_high);
	}
	return result;
}

unsigned char Ph_Wait2usec(unsigned char value, short io_base)
{
	int iteration;
	for (iteration = 0; iteration != 3; ++iteration) {
		while ((A2940_HIM_INB(io_base + 30) & 0x10) == 0)
			;
		A2940_HIM_OUTB(io_base + 30, value);
	}
	return value;
}

int Ph_SendStartBitEE(short io_base)
{
	A2940_HIM_OUTB(io_base + 30, 0x2a);
	Ph_Wait2usec(0x2a, io_base);
	A2940_HIM_OUTB(io_base + 30, 0x2e);
	Ph_Wait2usec(0x2e, io_base);
	A2940_HIM_OUTB(io_base + 30, 0x2a);
	return Ph_Wait2usec(0x2a, io_base);
}

short Ph_SendAddressEE(short io_base, int bit_count, short command)
{
	unsigned short address_bit = 0;
	unsigned short shifted_command = (unsigned short)command;
	unsigned short data_port = (unsigned short)(io_base + 30);
	short result = command;
	int bit;
	if (bit_count == 8)
		address_bit = 0x80;
	else if (bit_count == 10)
		address_bit = 0x200;
	else if (bit_count == 16)
		address_bit = 0x8000;
	for (bit = 0; bit < bit_count; ++bit) {
		unsigned char value = (address_bit & shifted_command) != 0 ? 0x2a : 0x28;
		A2940_HIM_OUTB(data_port, value);
	result = Ph_Wait2usec(value, io_base);
		value |= 4;
		A2940_HIM_OUTB(data_port, value);
		result = Ph_Wait2usec(value, io_base);
		shifted_command = (unsigned short)(shifted_command * 2);
	}
	return result;
}

int Ph_EnableEraseWriteEE(int io_base, int extended)
{
	int address = extended ? 10 : 8;
	short command = extended ? 0xc0 : 0x30;
	Ph_SendStartBitEE((short)io_base);
	Ph_SendAddressEE((short)io_base, address, command);
	A2940_HIM_OUTB(io_base + 30, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	A2940_HIM_OUTB(io_base + 30, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	return 0;
}

int Ph_DisableEraseWriteEE(int io_base, int extended)
{
	int address = extended ? 10 : 8;
	Ph_SendStartBitEE((short)io_base);
	Ph_SendAddressEE((short)io_base, address, 0);
	A2940_HIM_OUTB(io_base + 30, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	A2940_HIM_OUTB(io_base + 30, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	return 0;
}

int Ph_ReadE2Register(short address, int io_base, int extended)
{
	unsigned short command = (unsigned short)address;
	unsigned short value = 0;
	unsigned short data_port = (unsigned short)(io_base + 30);
	int bit_count;
	int bit;
	if (extended) {
		command = (unsigned short)((command & 0x00ff) |
					   (((command >> 8) | 2) << 8));
		bit_count = 10;
	} else {
		command = (unsigned short)((command | 0x80) & 0x00ff);
		bit_count = 8;
	}
	Ph_SendStartBitEE((short)io_base);
	Ph_SendAddressEE((short)io_base, bit_count, (short)command);
	A2940_HIM_OUTB(data_port, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	for (bit = 0; bit != 16; ++bit) {
		value = (unsigned short)(value * 2);
		A2940_HIM_OUTB(data_port, 0x2c);
		Ph_Wait2usec(0x2c, (short)io_base);
		A2940_HIM_OUTB(data_port, 0x28);
		if ((A2940_HIM_EEPROM_INB(data_port) & 1) != 0)
			value |= 1;
		Ph_Wait2usec(0x28, (short)io_base);
	}
	A2940_HIM_OUTB(data_port, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	return value;
}

int Ph_WriteE2Register(short address, int io_base, int extended, short value)
{
	unsigned short command;
	unsigned short data_port = (unsigned short)(io_base + 30);
	int bit_count;
	if (extended) {
		command = (unsigned short)address | 0x300;
		bit_count = 10;
	} else {
		command = (unsigned short)address | 0xc0;
		bit_count = 8;
	}
	Ph_SendStartBitEE((short)io_base);
	Ph_SendAddressEE((short)io_base, bit_count, (short)command);
	A2940_HIM_OUTB(data_port, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	A2940_HIM_OUTB(data_port, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	A2940_HIM_OUTB(data_port, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	while ((A2940_HIM_INB(data_port) & 1) == 0)
		;
	A2940_HIM_OUTB(data_port, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	Ph_SendStartBitEE((short)io_base);
	Ph_SendAddressEE((short)io_base, bit_count,
			 (short)((unsigned short)address | (extended ? 0x100 : 0x40)));
	Ph_SendAddressEE((short)io_base, 16, value);
	A2940_HIM_OUTB(data_port, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	A2940_HIM_OUTB(data_port, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	A2940_HIM_OUTB(data_port, 0x28);
	Ph_Wait2usec(0x28, (short)io_base);
	while ((A2940_HIM_INB(data_port) & 1) == 0)
		;
	A2940_HIM_OUTB(data_port, 0x20);
	Ph_Wait2usec(0x20, (short)io_base);
	return 0;
}

int Ph_ReadEeprom(unsigned short *host_words, int io_base)
{
	unsigned char *host = (unsigned char *)host_words;
	unsigned short checksum = 0;
	unsigned short mapped_bits = 0;
	unsigned short base_address = 0;
	int extended = 0;
	unsigned int i;
	unsigned int j;
	A2940_HIM_OUTB(io_base + 30, 8);
	if ((A2940_HIM_INB(io_base + 30) & 8) == 0)
		return 1;
	A2940_HIM_OUTB(io_base + 30, 0x20);
	while ((A2940_HIM_INB(io_base + 30) & 0x10) == 0)
		;
	if (*(unsigned short *)host == 0x7872) {
		if (host[9] != 4)
			base_address = 32;
	} else if (*(unsigned short *)host == 0x7873) {
		extended = 1;
		if (host[9] == 2 || host[9] == 8)
			base_address = 32;
		else if (host[9] == 3 || host[9] == 12)
			base_address = 64;
	}
	for (i = 0; i <= 30; ++i) {
		unsigned short word = (unsigned short)Ph_ReadE2Register(
			(short)(i + base_address), io_base, extended);
		checksum = (unsigned short)(checksum + word);
		if (i == 19 && host[31] != (unsigned char)word)
			break;
	}
	if (i == 31 && checksum == (unsigned short)Ph_ReadE2Register(
			(short)(base_address + 31), io_base, extended)) {
		for (j = 0; j <= 30; ++j) {
			unsigned short word = (unsigned short)Ph_ReadE2Register(
				(short)(j + base_address), io_base, extended);
			if (host[31] <= (unsigned char)j) {
				if (j > 15) {
					if (j == 17) {
						host[12] = (host[12] & (unsigned char)~0x20) |
							((word & 0x10) != 0 ? 0x20 : 0);
						host[14] = (host[14] & (unsigned char)~2) |
							((word & 2) != 0 ? 2 : 0);
						host[13] = (host[13] & (unsigned char)~0x30) |
							((word & 4) != 0 ? 0x10 : 0) |
							((word & 8) != 0 ? 0x20 : 0);
						host[15] = (host[15] & (unsigned char)~0x20) |
							((word & 1) != 0 ? 0x20 : 0);
					} else if (j == 18) {
						host[30] = (unsigned char)(word & 0x0f);
						host[21] = (unsigned char)(word >> 8);
					}
				} else {
					host[j + 32] = 0;
				}
			} else {
				host[j + 32] = (unsigned char)(((word & 8) != 0) |
					(16 * (word & 7)) | (4 * (word & 0x20)));
				if ((word & 0x10) != 0)
					mapped_bits |= (unsigned short)(1U << j);
			}
		}
		host_words[24] = mapped_bits;
		A2940_HIM_OUTB(io_base + 30, 0);
		return 0;
	}
	A2940_HIM_OUTB(io_base + 30, 0);
	return 1;
}

int Ph_UpdateEeprom(unsigned short *host_words, int io_base, unsigned short index)
{
	unsigned char *host = (unsigned char *)host_words;
	unsigned short words[32];
	unsigned short base_address = 0;
	unsigned short checksum = 0;
	int extended = 0;
	unsigned int i;
	A2940_HIM_OUTB(io_base + 30, 8);
	if ((A2940_HIM_INB(io_base + 30) & 8) == 0)
		return 1;
	if (*(unsigned short *)host == 0x7872) {
		if (host[9] != 4)
			base_address = 32;
	} else if (*(unsigned short *)host == 0x7873) {
		extended = 1;
		if (host[9] == 2 || host[9] == 8)
			base_address = 32;
		else if (host[9] == 3 || host[9] == 12)
			base_address = 64;
	}
	A2940_HIM_OUTB(io_base + 30, 0x20);
	while ((A2940_HIM_INB(io_base + 30) & 0x10) == 0)
		;
	for (i = 0; i != 32; ++i)
		words[i] = (unsigned short)Ph_ReadE2Register(
			(short)(i + base_address), io_base, extended);
	words[index] = (unsigned short)Ph_RebuildEEControl((int)(unsigned long)host,
							   (short)words[index]);
	for (i = 0; i <= 30; ++i)
		checksum = (unsigned short)(checksum + words[i]);
	Ph_EnableEraseWriteEE(io_base, extended);
	Ph_WriteE2Register((short)(base_address + index), io_base, extended,
			   (short)words[index]);
	Ph_WriteE2Register((short)(base_address + 31), io_base, extended,
			   (short)checksum);
	Ph_DisableEraseWriteEE(io_base, extended);
	A2940_HIM_OUTB(io_base + 30, 0);
	return 0;
}

unsigned char Ph_ReadBiosInfo(int host_address, unsigned short offset,
			      int destination_address, unsigned short length)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + 4);
	unsigned char control = A2940_HIM_INB(io_base + 135);
	unsigned char saved_control = A2940_HIM_INB(io_base + 144);
	Ph_WriteHcntrl((short)io_base, control | 4);
	while ((A2940_HIM_INB(io_base + 135) & 4) == 0)
		;
	A2940_HIM_OUTB(io_base + 144, 2);
	Ph_InBuffer((short)(io_base + offset + 160), destination_address, length);
	A2940_HIM_OUTB(io_base + 144, saved_control);
	return Ph_WriteHcntrl((short)io_base, control);
}

unsigned char Ph_WriteBiosInfo(int host_address, unsigned short offset,
			       int source_address, unsigned short length)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + 4);
	unsigned char control = A2940_HIM_INB(io_base + 135);
	unsigned char saved_control = A2940_HIM_INB(io_base + 144);
	Ph_WriteHcntrl((short)io_base, control | 4);
	while ((A2940_HIM_INB(io_base + 135) & 4) == 0)
		;
	A2940_HIM_OUTB(io_base + 144, 2);
	Ph_OutBuffer((short)(io_base + offset + 160), source_address, length);
	A2940_HIM_OUTB(io_base + 144, saved_control);
	return Ph_WriteHcntrl((short)io_base, control);
}

int Ph_CheckBiosPresence(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int signature;
	Ph_ReadBiosInfo(host_address, 0x10, host_address + 32, 4);
	signature = *(unsigned int *)(host + 32);
	return signature != 0 && signature != 0xffffffffU;
}

int Ph_GetDrvrConfig(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + 4);
	host[13] |= 0x80;
	if ((A2940_HIM_INB(io_base + 135) & 1) == 0 &&
	    Ph_CheckBiosPresence(host_address) != 0)
		host[12] |= 2;
	*(unsigned short *)(host + 62) = 2;
	*(unsigned short *)(host + 64) = 32;
	*(unsigned short *)(host + 16) = 2;
	return Ph_GetOptimaConfig(host_address);
}

unsigned char Ph_Pause(int io_base)
{
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	A2940_HIM_OUTB(io_base + 0x87, control | 0x04);
	do {
		control = A2940_HIM_INB(io_base + 0x87);
	} while ((control & 0x04) == 0);
	return control;
}

int Ph_UnPause(int io_base)
{
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control & 0xfb);
}

int PH_EnableInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control | 0x02, io_base);
}

int PH_DisableInt(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char control = A2940_HIM_INB(io_base + 0x87);
	return Ph_WriteHcntrl((short)io_base, control & 0xfd, io_base);
}



unsigned char Ph_InBuffer(short port, int destination_address, int length)
{
	unsigned char *destination = (unsigned char *)(unsigned long)(unsigned int)destination_address;
	unsigned char result;
	int index;
	for (index = 0; index < length; ++index) {
		result = A2940_HIM_INB(port + index);
		destination[index] = result;
	}
	return result;
}

unsigned char Ph_OutBuffer(short port, int source_address, int length)
{
	unsigned char *source = (unsigned char *)(unsigned long)(unsigned int)source_address;
	unsigned char result;
	int index;
	for (index = 0; index < length; ++index) {
		result = source[index];
		A2940_HIM_OUTB(port + index, result);
	}
	return result;
}

char Ph_SetNeedNego(unsigned char target, short io_base)
{
	A2940_HIM_OUTB(io_base + target + 32, 0x8f);
	return (char)-113;
}

char Ph_CheckSyncNego(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	short io_base = *(short *)(host + 4);
	unsigned char target;
	char result = 0;
	for (target = 0; target < host[31]; ++target) {
		if ((host[14] & 1) == 0 && (host[target + 32] & 0x81) != 0)
			result = Ph_SetNeedNego(target, io_base);
		else
			A2940_HIM_OUTB(io_base + target + 32, 0);
	}
	return result;
}

int Ph_SetHaData(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	*(unsigned int *)block = 0xffffffffU;
	*(unsigned int *)(block + 4) = 0xffffffffU;
	Ph_MemorySet(block + 8, 0, 256);
	*(unsigned short *)(block + 266) = 0;
	block[268] = host[62];
	block[269] = host[64];
	block[270] = 0;
	Ph_SetScbMark(host_address);
	return Ph_SetOptimaHaData(host_address);
}

int Ph_SyncSet(int scb_address)
{
	unsigned char period = *(unsigned char *)((unsigned long)(unsigned int)scb_address + 67);
	if (period == 0x12 || (period >= 0x14 && period <= 0x19))
		return 0;
	if (period <= 0x10 || (period >= 0x1a && period <= 0x1f))
		return 16;
	if (period <= 0x25)
		return 32;
	if (period <= 0x2b)
		return 48;
	if (period <= 0x32)
		return 64;
	if (period <= 0x38)
		return 80;
	if (period <= 0x3e)
		return 96;
	return 112;
}

char Ph_ScbRenego(int host_address, unsigned char target_channel_lun)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
	unsigned char target = target_channel_lun >> 4;
	unsigned char *need_nego = host + target + 32;
	unsigned char value;
	if ((*need_nego & 0x81) != 0)
		return Ph_SetNeedNego(target, (short)io_base);
	value = A2940_HIM_INB(io_base + target + 32);
	if ((value & 0x8f) != 0) {
		if ((value & 0x0f) != 0)
			*need_nego |= 1;
		if ((signed char)value < 0)
			*need_nego |= 0x80;
		return Ph_SetNeedNego(target, (short)io_base);
	}
	A2940_HIM_OUTB(io_base + target + 32, 0);
	return 0;
}

unsigned char Ph_ClearFast20Reg(int host_address, int scb_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char target;
	unsigned char mask;
	unsigned short register_port;
	unsigned char value;
	unsigned char result;
	if (scb[66] == 1) {
		int io_base = *(int *)(host + A2940_HA_IO_BASE_OFFSET);
		target = scb[12] >> 4;
		if (target > 7) {
			mask = (unsigned char)(1 << (target - 8));
			register_port = (unsigned short)(io_base + 49);
		} else {
			mask = (unsigned char)(1 << target);
			register_port = (unsigned short)(io_base + 48);
		}
		value = A2940_HIM_INB(register_port);
		A2940_HIM_OUTB(register_port, value & (unsigned char)~mask);
		result = A2940_HIM_INB(io_base + 1) & 0xdf;
		A2940_HIM_OUTB(io_base + 1, result);
	}
	return result;
}

void Ph_LogFast20Map(int host_address, unsigned char *scb)
{
	unsigned char target;
	unsigned char mask;
	unsigned short register_port;
	unsigned char map;
	unsigned char control;
	int io_base;
	if (scb[66] != 1)
		return;
	io_base = *(int *)(a2940_host_from_address(host_address) + A2940_HA_IO_BASE_OFFSET);
	target = scb[12] >> 4;
	if (target > 7) {
		mask = (unsigned char)(1 << (target - 8));
		register_port = (unsigned short)(io_base + 49);
	} else {
		mask = (unsigned char)(1 << target);
		register_port = (unsigned short)(io_base + 48);
	}
	map = A2940_HIM_INB(register_port);
	control = A2940_HIM_INB(io_base + 1);
	if (scb[67] > 0x18) {
		map &= (unsigned char)~mask;
		control &= 0xdf;
	} else {
		map |= mask;
		control |= 0x20;
	}
	A2940_HIM_OUTB(register_port, map);
	A2940_HIM_OUTB(io_base + 1, control);
}

void Ph_Abort(void)
{
}

int Ph_SendTrmMsg(unsigned int unused_host, unsigned int unused_scb)
{
	(void)unused_host;
	(void)unused_scb;
	return 0;
}

int Ph_TrmCmplt(void)
{
	return 0;
}

void Ph_BusReset(void)
{
}

void Ph_HaSoftReset(void)
{
}

void Ph_SoftReset(void)
{
}

char Ph_CheckLength(int scb_address, short io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char phase = A2940_HIM_INB(io_base + 3);
	unsigned char control;
	unsigned int residual;
	unsigned char i;

	if ((phase & 0xe0) != 0xc0) {
		if ((signed char)phase >= 0) {
			A2940_HIM_OUTB(io_base + 3, phase & 0xe0);
			control = A2940_HIM_INB(io_base + 2);
			A2940_HIM_OUTB(io_base + 2, control | 0x80);
			while ((A2940_HIM_INB(io_base + 12) & 0x10) == 0)
				;
			*(unsigned int *)(scb + 28) = 0;
			A2940_HIM_OUTB(io_base + 2, control);
		}
		scb[43] = 18;
		return (char)phase;
	}
	if ((scb[10] & 0x40) == 0 && scb[24] != 2) {
		residual = 0;
		for (i = 0; i <= 3; ++i)
			residual |= (unsigned int)A2940_HIM_INB(io_base + 176 + i) << (8 * i);
		*(unsigned int *)(scb + 28) = residual;
		scb[43] = 18;
	}
	return (char)phase;
}

int Ph_GetScbStatus(int chain_address, int scb_address)
{
	unsigned char *chain = (unsigned char *)(unsigned long)(unsigned int)chain_address;
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char limit;
	if ((scb[13] & 0x20) != 0)
		limit = chain[269];
	else
		limit = chain[268];
	return chain[(unsigned int)scb[12] + 8] > limit ? 32 : 16;
}

unsigned char Ph_SetMgrStat(unsigned char *scb)
{
	unsigned char status;
	scb[11] = 1;
	if (scb[43] != 0)
		scb[11] = 4;
	status = scb[24];
	if (status != 4) {
		if (status <= 4) {
			if (status == 0)
				return status;
			scb[11] = 4;
		} else if (status != 16 && status != 20) {
			scb[11] = 4;
		}
	}
	return status;
}

void Ph_TerminateCommand(int scb_address, char abort_marker)
{
	unsigned char *scb;
	unsigned char *host;
	unsigned char *block;
	unsigned char *current;
	unsigned char target;
	unsigned char status;
	unsigned char *abort_queue;
	unsigned int next_address;

	if (scb_address == -1)
		return;
	scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	block = (unsigned char *)(unsigned long)*(unsigned int *)(host + 52);
	if (scb == block + 352)
		return;
	if ((unsigned char)abort_marker != 0xff) {
		abort_queue = (unsigned char *)(unsigned long)*(unsigned int *)(block + 280);
		abort_queue[block[270]++] = (unsigned char)abort_marker;
	}
	Ph_SetMgrStat(scb);
	target = scb[12];
	if ((unsigned char)Ph_GetScbStatus((int)(unsigned long)block,
					  (int)(unsigned long)scb) == 32) {
		current = scb;
		for (;;) {
			next_address = *(unsigned int *)current;
			if (next_address == 0xffffffffU ||
			    *((unsigned char *)(unsigned long)next_address + 8) == 0xff)
				current = (unsigned char *)(unsigned long)*(unsigned int *)block;
			else
				current = (unsigned char *)(unsigned long)next_address;
			if (current[11] == 32 && current[12] == target)
				break;
			if (current == scb)
				goto finish;
		}
		current[11] = 16;
		++*(unsigned short *)(block + 266);
	}
finish:
	status = block[(unsigned int)target + 8];
	if (status != 0)
		--block[(unsigned int)target + 8];
}

int Ph_SetScbMark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	*(unsigned int *)(chain + 372) = *(unsigned int *)(host + 56) + 404;
	*(unsigned int *)(chain + 356) = (unsigned int)host;
	return (int)chain;
}

unsigned char Ph_SendMsgo(unsigned char *scb, int io_base)
{
	unsigned char target = scb[12] >> 4;
	unsigned char result;

	A2940_HIM_OUTB(io_base + 3, 0xa0);
	if ((A2940_HIM_INB(io_base + 3) & 0x10) == 0) {
		A2940_HIM_OUTB(io_base + 6, 8);
		do {
			result = A2940_HIM_INB(io_base + 3);
		} while ((result & 1) != 0);
		return result;
	}
	if ((scb[10] & 2) == 0) {
		result = A2940_HIM_INB(io_base + 2);
		A2940_HIM_OUTB(io_base + 2, result & 0xdf);
		A2940_HIM_OUTB(io_base + 2, result | 0x20);
		A2940_HIM_OUTB(io_base + 12, 0x44);
		A2940_HIM_OUTB(io_base + 146, 4);
		A2940_HIM_OUTB(io_base + 6, 5);
		do {
			result = A2940_HIM_INB(io_base + 3);
		} while ((result & 1) != 0);
		return result;
	}
	if (scb[64] == 0xff) {
		scb[64] = 1;
		result = (unsigned char)Ph_ExtMsgo((int)(unsigned long)scb, io_base);
		if (result == 0xe0 && A2940_HIM_INB(io_base + 18) == 7) {
			unsigned char sync = 0;
			if (scb[66] == 1)
				sync = A2940_HIM_INB(io_base + target + 32) & 0x80;
			A2940_HIM_OUTB(io_base + target + 32, sync);
			A2940_HIM_OUTB(io_base + 4, sync);
			return A2940_HIM_INB(io_base + 6);
		}
		return result;
	}
	scb[10] &= (unsigned char)~2;
	if (scb[64] == 1)
		return Ph_SyncNego((int)(unsigned long)scb, io_base);
	result = A2940_HIM_INB(io_base + target + 32);
	if (result == 0x8f)
		return (unsigned char)Ph_Negotiate((int)(unsigned long)scb, io_base);
	return result;
}

char Ph_Negotiate(int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char *host = a2940_host_from_address(*(int *)(scb + 4));
	unsigned char target = scb[12] >> 4;
	unsigned char negotiation;
	unsigned char result;

	A2940_HIM_OUTB(io_base + 98, 2);
	A2940_HIM_OUTB(io_base + 99, 0);
	if ((A2940_HIM_INB(io_base + 3) & 0xe0) != 0xa0) {
		A2940_HIM_OUTB(io_base + target + 32, 0);
		A2940_HIM_OUTB(io_base + 4, 0);
		return (char)Ph_ClearFast20Reg(*(int *)(host + 4), scb_address);
	}
	negotiation = A2940_HIM_INB(io_base + target + 32);
	if (negotiation != 0x8f)
		return (char)Ph_SendMsgo(scb, io_base);
	A2940_HIM_OUTB(io_base + target + 32, 0);
	A2940_HIM_OUTB(io_base + 4, 0);
	Ph_ClearFast20Reg(*(int *)(host + 4), scb_address);
	scb[64] = 1;
	negotiation = host[target + 32] & 0x81;
	if (negotiation == 1)
		goto sync_request;
	if (negotiation == 0x80) {
		scb[65] = 2;
		scb[66] = 3;
		scb[67] = 1;
		result = (unsigned char)Ph_ExtMsgo(scb_address, io_base);
		if (result != 0xe0)
			return (char)result;
		result = A2940_HIM_INB(io_base + 18);
		if (result == 1) {
			scb[10] |= 2;
			return (char)result;
		}
		if (result != 7)
			return (char)result;
		if ((host[target + 32] & 1) == 0) {
			A2940_HIM_OUTB(io_base + 3, 0xe0);
			return (char)A2940_HIM_INB(io_base + 6);
		}
		A2940_HIM_OUTB(io_base + 3, 0xf0);
		A2940_HIM_INB(io_base + 6);
		result = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
		if (result != 0xa0)
			return (char)result;
		A2940_HIM_OUTB(io_base + 3, 0xb0);
	}

sync_request:
	scb[65] = 3;
	scb[66] = 1;
	if ((host[14] & 2) != 0) {
		switch ((host[target + 32] >> 4) & 7) {
		case 0: scb[67] = 12; break;
		case 1: scb[67] = 16; break;
		case 2: scb[67] = 19; break;
		case 4: scb[67] = 25; break;
		}
	} else {
		scb[67] = (unsigned char)(25 + 6 * ((host[target + 32] >> 4) & 7) +
			((host[target + 32] & 0x40) != 0));
	}
	scb[68] = 15;
	return Ph_SyncNego(scb_address, io_base);
}

int Ph_TargetAbort(int host_address, int scb_address, int io_base)
{
	unsigned char status = 6;
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char scb_index;

	if ((Ph_ReadIntstat((short)io_base) & 0xf0) == 0x90) {
		A2940_HIM_OUTB(io_base + 3, 0xf0);
		A2940_HIM_INB(io_base + 6);
	}
	if ((unsigned char)Ph_Wt4Req(scb_address, (short)io_base) == 0xa0) {
		scb_index = A2940_HIM_INB(io_base + 60);
		if (scb_index != 0xff) {
			if (scb[11] == 68) {
				scb[11] = 2;
				return 0;
			}
			if (scb[11] == 65)
				return 0;
			if ((A2940_HIM_INB(io_base + 161) & 0x20) != 0)
				status = 13;
		}
		if ((Ph_SendTrmMsg((unsigned int)host_address, status) & 8) != 0) {
			unsigned char *host = a2940_host_from_address(host_address);
			unsigned char *ha = *(unsigned char **)(host + A2940_CHAIN_HEAD_OFFSET);
			A2940_HIM_OUTB(io_base + 12, 8);
			A2940_HIM_OUTB(io_base + 146, 4);
			scb_index = A2940_HIM_INB(io_base + 144);
			if (*(int *)(*(unsigned int **)(ha + 272) + scb_index) != -1) {
				A2940_HIM_OUTB(io_base + 161, 0);
				scb[43] = 5;
				scb[11] = 2;
				Ph_TerminateCommand(scb_address, (char)scb_index);
				Ph_PostCommand(host_address);
				A2940_HIM_OUTB(io_base + 98, 0);
				A2940_HIM_OUTB(io_base + 99, 0);
			}
		return 0;
	}
		return 0;
	}
	Ph_BadSeq(host_address, io_base);
	return 1;
}

int Ph_ScbPrepare(int host_address, int *first_scb)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	unsigned char *scb = (unsigned char *)first_scb;
	int result;
	do {
		scb[9] = 0;
		++chain[(unsigned int)scb[12] + 8];
		result = Ph_GetScbStatus((int)chain, (int)scb);
		scb[11] = (unsigned char)result;
		if ((unsigned char)result == 16)
			++*(unsigned short *)(chain + 266);
		if (*(unsigned int *)scb == A2940_CHAIN_END)
			break;
		scb = (unsigned char *)(unsigned long)*(unsigned int *)scb;
	} while (1);
	return result;
}

char Ph_InsertBookmark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	*(unsigned char *)(chain + 360) = 0xff;
	return Ph_ChainAppendEnd(host_address, (unsigned int *)(chain + 352));
}

int Ph_RemoveBookmark(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	return Ph_ChainRemove(host_address, (unsigned int *)(chain + 352));
}

int Ph_AsynchEvent(int event, int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned int callback_address = *(unsigned int *)(scb + 104);
	void (__attribute__((stdcall)) *callback)(int, int, int);
	if ((scb[13] & 0x40) == 0 || callback_address == 0xffffffffU)
		return 255;
	callback = (void (__attribute__((stdcall)) *)(int, int, int))(unsigned long)callback_address;
	callback(event, scb_address, io_base);
	return 0;
}

int Ph_RebuildEEControl(int host_address, short control)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned short result = (unsigned short)control;
	unsigned char flags = host[13];
	unsigned char low = (unsigned char)result;
	if ((flags & 0x10) != 0)
		low |= 0x04;
	else
		low &= (unsigned char)~0x04;
	if ((flags & 0x20) != 0)
		low |= 0x08;
	else
		low &= (unsigned char)~0x08;
	return (int)((result & 0xff00U) | low);
}

int Ph_Wt4Req(int scb_address, short io_base)
{
	unsigned int timeout = 0x800000;
	unsigned short request_port = (unsigned short)(io_base + 3);
	unsigned short status_port = (unsigned short)(io_base + 12);
	unsigned char request;
	unsigned char status;
	unsigned char result;
	(void)scb_address;
	for (;;) {
		do {
			request = A2940_HIM_INB(request_port);
		} while ((request & 1) != 0);
		for (;;) {
			status = A2940_HIM_INB(status_port);
			if ((status & 1) != 0)
				break;
			if ((--timeout == 0) || (status & 0x28) != 0)
				return 0xff;
		}
		A2940_HIM_OUTB(status_port, 4);
		request = A2940_HIM_INB(request_port);
		result = request & 0xe0;
		if ((request & 0x40) == 0 || result == 0x40)
			return result;
		status = A2940_HIM_INB(status_port);
		if ((status & 4) == 0)
			return result;
		A2940_HIM_OUTB(request_port, result);
		(void)A2940_HIM_INB((unsigned short)(io_base + 6));
	}
}

unsigned char Ph_ParityError(int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char result;
	(void)Ph_Wt4Req(scb_address, (short)io_base);
	result = A2940_HIM_INB(io_base + 2) & (unsigned char)~0x20;
	A2940_HIM_OUTB(io_base + 2, result);
	scb[43] = 72;
	return result;
}

char Ph_IntSelto(int host_address, int scb_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	unsigned char *block = (unsigned char *)(unsigned long)(unsigned int)chain;
	int io_base = *(int *)(host + 4);
	unsigned char selection_id = A2940_HIM_INB(io_base + 59);
	unsigned char control = A2940_HIM_INB(io_base);
	void (*selection_timeout)(int, unsigned int) =
		(void (*)(int, unsigned int))(unsigned long)chain[117];
	A2940_HIM_OUTB(io_base, control & 0x33);
	selection_timeout(host_address, selection_id);
	A2940_HIM_OUTB(io_base + 12, 0x88);
	if (scb_address != -1) {
		unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
		if (scb != block + 352) {
			void (__attribute__((stdcall)) *abort_callback)(int, int, int) =
				(void (__attribute__((stdcall)) *)(int, int, int))
				(unsigned long)chain[121];
			abort_callback(scb_address, 0, 0);
			scb[43] = 17;
			Ph_TerminateCommand(scb_address, (char)selection_id);
			return 0;
		}
	}
	return (char)0x88;
}

char Ph_IntFree(int host_address, int scb_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned int *chain = a2940_chain_from_host(host);
	unsigned short io_base = *(unsigned short *)(host + 4);
	unsigned char selection_id = A2940_HIM_INB(io_base + 60);
	unsigned char value;
	A2940_HIM_OUTB(io_base + 147, 1);
	value = A2940_HIM_INB(io_base + 1);
	A2940_HIM_OUTB(io_base + 1, value | 0x1a);
	value = A2940_HIM_INB(io_base + 17);
	A2940_HIM_OUTB(io_base + 17, value & 0xf7);
	A2940_HIM_OUTB(io_base + 4, 0);
	A2940_HIM_OUTB(io_base + 12, 8);
	A2940_HIM_OUTB(io_base + 98, 0);
	A2940_HIM_OUTB(io_base + 99, 0);
	if (scb_address != -1) {
		unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
		void (__attribute__((stdcall)) *abort_callback)(int, int, int) =
			(void (__attribute__((stdcall)) *)(int, int, int))
			(unsigned long)chain[121];
		void (*selection_timeout)(int, unsigned int) =
			(void (*)(int, unsigned int))(unsigned long)chain[117];
		abort_callback(scb_address, 0, 0);
		selection_timeout(host_address, selection_id);
		scb[43] = 19;
		Ph_TerminateCommand(scb_address, (char)selection_id);
		return 0;
	}
	return 0;
}

void *Ph_RemoveAndPostScb(int chain_address, int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	Ph_ChainRemove(chain_address, (unsigned int *)scb);
	scb[9] = scb[11];
	return PH_ScbCompleted(scb_address);
}

void *Ph_PostNonActiveScb(int host_address, int scb_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char *chain = *(unsigned char **)(host + 52);
	unsigned int target = scb[12];
	if (chain[target + 8] != 0)
		--chain[target + 8];
	return Ph_RemoveAndPostScb(host_address, scb_address);
}

void *Ph_TermPostNonActiveScb(int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	Ph_TerminateCommand(scb_address, (char)0xff);
	return Ph_RemoveAndPostScb(host_address, scb_address);
}

int Ph_NonInit(int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *chain = *(unsigned char **)(host + 52);
	unsigned char event = scb[8];
	if (event == 0)
		return 0;
	if (event == 4)
		Ph_BusDeviceReset(scb_address);
	else {
		Ph_ChainAppendEnd(host_address, (unsigned int *)scb);
		scb[11] = 0x80;
		++chain[270];
	}
	return 0;
}

void *Ph_PostCommand(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	unsigned int *scb_array;
	unsigned char *qin_order;
	void (*mark_complete)(int, unsigned int);
	void *result = 0;
	if (*(unsigned int *)block == 0xffffffffU || block[270] == 0)
		return result;
	scb_array = (unsigned int *)(unsigned long)*(unsigned int *)(block + 272);
	qin_order = (unsigned char *)(unsigned long)*(unsigned int *)(block + 280);
	mark_complete = (void (*)(int, unsigned int))
		(unsigned long)*(unsigned int *)(block + 452);
	do {
		unsigned char queue_index = --block[270];
		unsigned char scb_index = qin_order[queue_index];
		unsigned char *scb = (unsigned char *)(unsigned long)scb_array[scb_index];
		mark_complete(host_address, scb_index);
		Ph_ChainRemove(host_address, (unsigned int *)scb);
		scb[9] = scb[11];
		result = PH_ScbCompleted((int)(unsigned long)scb);
	} while (block[270] != 0);
	return result;
}

char Ph_ScbAbort(int scb_address)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	int host_address = *(int *)(scb + 4);
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	int previous = Ph_ChainPrevious((int *)block, scb_address);
	unsigned char status;
	if (previous == -1)
		return (char)-1;
	status = scb[11];
	if (status == 32) {
		scb[43] = 4;
		scb[11] = 2;
		return (char)(unsigned long)Ph_PostNonActiveScb(host_address, scb_address);
	}
	if (status == 16) {
		--*(unsigned short *)(block + 266);
		scb[43] = 4;
		scb[11] = 2;
		return (char)(unsigned long)Ph_TermPostNonActiveScb(scb_address);
	}
	if (status == 8 || status == 64) {
		int (*abort_callback)(int) = (int (*)(int))
			(unsigned long)*(unsigned int *)(block + 456);
		int result;
		scb[11] = 2;
		scb[43] = 4;
		result = abort_callback(scb_address);
		if (result == 0)
			return (char)(unsigned long)Ph_TermPostNonActiveScb(scb_address);
		return (char)result;
	}
	return (char)status;
}

unsigned char Ph_NoAssistTerm(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + 4);
	unsigned char control = A2940_HIM_INB(io_base + 2);
	unsigned char result;
	if ((host[13] & 0x10) == 0)
		result = control & 0xfe;
	else
		result = control | 1;
	A2940_HIM_OUTB(io_base + 2, result);
	if (host[31] != 16)
		return result;
	A2940_HIM_OUTB(io_base + 30, 0x20);
	while ((signed char)A2940_HIM_INB(io_base + 30) < 0)
		;
	A2940_HIM_OUTB(io_base + 30, 0x28);
	if ((host[13] & 0x20) != 0) {
		A2940_HIM_OUTB(io_base + 29, 0x58);
		A2940_HIM_OUTB(io_base + 29, 72);
	} else {
		A2940_HIM_OUTB(io_base + 29, 0x18);
		A2940_HIM_OUTB(io_base + 29, 8);
	}
	A2940_HIM_OUTB(io_base + 29, 0);
	A2940_HIM_OUTB(io_base + 30, 0);
	return 0;
}

int Ph_ExtMsgo(int scb_address, int io_base)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
	unsigned char saved8 = A2940_HIM_INB(io_base + 8);
	unsigned char saved9 = A2940_HIM_INB(io_base + 9);
	unsigned char saved10 = A2940_HIM_INB(io_base + 10);
	unsigned char index = 0;
	unsigned char remaining = (unsigned char)(scb[65] + 1);
	unsigned char sync_value = 0;
	unsigned char response;
	unsigned char result;
	if (scb[65] != 0xff) {
		while (remaining != 0) {
			A2940_HIM_OUTB(io_base + 6, scb[64 + index++]);
			if ((unsigned char)Ph_Wt4Req(scb_address, (short)io_base) != 0xa0) {
				A2940_HIM_OUTB(io_base + 12, 0x40);
				break;
			}
			--remaining;
		}
	}
	if (scb[65] == 0xff || remaining == 0) {
		if ((scb[10] & 2) != 0) {
			unsigned char target = scb[12] >> 4;
			if (scb[66] == 3) {
				if (scb[67] != 0)
					sync_value = 0x80;
			} else {
				response = A2940_HIM_INB(io_base + target + 32);
				sync_value = (unsigned char)(scb[68] + Ph_SyncSet(scb_address) + response);
				(void)Ph_LogFast20Map(*(int *)(scb + 4), scb);
			}
			A2940_HIM_OUTB(io_base + target + 32, sync_value);
			A2940_HIM_OUTB(io_base + 4, sync_value);
			scb[10] &= (unsigned char)~2;
		}
		A2940_HIM_OUTB(io_base + 12, 0x40);
		A2940_HIM_OUTB(io_base + 6, scb[64 + index]);
	}
	A2940_HIM_OUTB(io_base + 8, saved8);
	A2940_HIM_OUTB(io_base + 9, saved9);
	A2940_HIM_OUTB(io_base + 10, saved10);
	result = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
	return result;
}

unsigned char Ph_SyncNego(int scb_address, int io_base)
{
	unsigned char result = (unsigned char)Ph_ExtMsgo(scb_address, io_base);
	if (result == 0xe0) {
		result = A2940_HIM_INB(io_base + 18);
		if (result == 1) {
			unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scb_address;
			scb[10] |= 2;
		} else if (result == 7) {
			do {
				A2940_HIM_OUTB(io_base + 3, 0xe0);
				(void)A2940_HIM_INB(io_base + 6);
				result = (unsigned char)Ph_Wt4Req(scb_address, (short)io_base);
				if (result != 0xe0)
					break;
				result = A2940_HIM_INB(io_base + 18);
			} while (result == 7);
		}
	}
	return result;
}

int Ph_ReadCableStatus(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	int io_base = *(int *)(host + 4);
	unsigned char cable = 0;
	unsigned short device = *(unsigned short *)host & 0xfff0;
	unsigned char value;
	volatile unsigned char index;
	A2940_HIM_OUTB(io_base + 30, 0x20);
	while ((signed char)A2940_HIM_INB(io_base + 30) < 0)
		;
	if (device == 0x7850 || device == 0x7550) {
		value = A2940_HIM_INB(io_base + 27);
		A2940_HIM_OUTB(io_base + 27, (value & 0xcf) | 0x10);
		value = A2940_HIM_INB(io_base + 29);
		for (index = 0; index <= 15; ++index)
			;
		A2940_HIM_OUTB(io_base + 29, value | 0x0c);
		value = A2940_HIM_INB(io_base + 30);
		A2940_HIM_OUTB(io_base + 30, value | 0x20);
		for (index = 0; index <= 15; ++index)
			;
		A2940_HIM_OUTB(io_base + 30, value & 0xdf);
		value = A2940_HIM_INB(io_base + 29);
		if ((value & 0x20) == 0)
			cable = 1;
		if ((value & 0x40) == 0)
			cable |= 4;
		return cable;
	}
	if (device != 0x7870 && device != 0x7880)
		return cable;
	A2940_HIM_OUTB(io_base + 30, 0x28);
	A2940_HIM_OUTB(io_base + 29, 0x18);
	A2940_HIM_OUTB(io_base + 29, 8);
	A2940_HIM_OUTB(io_base + 29, 0);
	A2940_HIM_OUTB(io_base + 29, 0x0c);
	{
		unsigned char cable_pins = A2940_HIM_INB(io_base + 29);
		unsigned char termination_pins;
		A2940_HIM_OUTB(io_base + 29, 0);
		A2940_HIM_OUTB(io_base + 29, 0x38);
		A2940_HIM_OUTB(io_base + 29, 0x28);
		A2940_HIM_OUTB(io_base + 29, 0x20);
		A2940_HIM_OUTB(io_base + 29, 0x0c);
		termination_pins = A2940_HIM_INB(io_base + 29);
		A2940_HIM_OUTB(io_base + 29, 0);
		A2940_HIM_OUTB(io_base + 30, 0);
		value = A2940_HIM_INB(io_base + 31);
		if ((value & 2) != 0) {
			if ((signed char)cable_pins >= 0)
				cable = 2;
			if ((cable_pins & 0x40) == 0)
				cable |= 1;
			if ((termination_pins & 0x40) == 0)
				cable |= 4;
		} else {
			if ((signed char)cable_pins >= 0)
				cable = 4;
			if ((cable_pins & 0x40) == 0)
				cable |= 1;
		}
	}
	return cable;
}

char Ph_ResetChannel(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	int io_base = *(int *)(host + 4);
	unsigned char control = A2940_HIM_INB(io_base);
	unsigned char reset_value;
	unsigned int target;
	unsigned int target_count;
	A2940_HIM_OUTB(io_base, control & 0x33);
	A2940_HIM_OUTB(io_base + 11, 0xff);
	A2940_HIM_OUTB(io_base + 12, 0xff);
	A2940_HIM_OUTB(io_base + 1, 0x12);
	reset_value = host[12] & 0x38;
	if ((host[13] & 0x10) != 0)
		reset_value |= 7;
	else
		reset_value |= 6;
	A2940_HIM_OUTB(io_base + 2, reset_value);
	A2940_HIM_OUTB(io_base + 147, 1);
	A2940_HIM_OUTB(io_base + 17, 0xa4);
	target_count = (host[13] & 1) != 0 ? 0x80 : 16;
	for (target = 0; target < target_count; ++target) {
		void (*reset_target)(int, unsigned int) = (void (*)(int, unsigned int))
			(unsigned long)*(unsigned int *)(block + 464);
		reset_target(host_address, target);
	}
	A2940_HIM_OUTB(io_base + 144, 0);
	return 0;
}

int SWAPCurrScratchRam(int host_address, char save_registers)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	unsigned short offset;
	for (offset = 32; offset <= 0x5f; ++offset) {
		unsigned char value = A2940_HIM_INB(*(int *)(host + 4) + offset);
		if (save_registers != 0 && offset >= 0x3b)
			A2940_HIM_OUTB(*(int *)(host + 4) + offset, block[256 + offset]);
		if (offset == 65)
			value = 0;
		else if ((unsigned short)(offset - 70) <= 15)
			value = 0x7f;
		block[256 + offset] = value;
	}
	A2940_HIM_OUTB(*(int *)(host + 4) + 98, 0);
	A2940_HIM_OUTB(*(int *)(host + 4) + 99, 0);
	return 0;
}

int Ph_InitDrvrHA(int host_address)
{
	unsigned char *host = a2940_host_from_address(host_address);
	unsigned char *block = *(unsigned char **)(host + 52);
	unsigned int io_base = *(unsigned int *)(host + 4);
	unsigned char scratch_value;
	block[432] = 0;
	block[433] = 0;
	block[434] = 0;
	block[435] = 0;
	block[284] = 0;
	block[285] = 0;
	(void)SWAPCurrScratchRam(host_address, 0);
	block[287] = 3;
	(void)Ph_SetHaData(host_address);
	A2940_HIM_OUTB(io_base + 96, 0x80);
	A2940_HIM_OUTB(io_base + 96, 0x81);
	A2940_HIM_OUTB(io_base + 98, 1);
	A2940_HIM_OUTB(io_base + 99, 0);
	(void)A2940_HIM_INB(io_base + 97);
	(void)A2940_HIM_INB(io_base + 97);
	scratch_value = A2940_HIM_INB(io_base + 97);
	(void)A2940_HIM_INB(io_base + 97);
	*(unsigned short *)(block + 264) = (unsigned short)(scratch_value + 1);
	A2940_HIM_OUTB(io_base + 96, 0x80);
	return (int)(unsigned long)Ph_OptimaLoadFuncPtrs(host_address);
}
