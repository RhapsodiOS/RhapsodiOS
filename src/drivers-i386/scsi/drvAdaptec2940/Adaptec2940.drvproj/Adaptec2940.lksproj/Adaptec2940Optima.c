/* Recovered Optima sizing and host-map helpers. */
#include "Adaptec2940HIM.h"

static unsigned char *a2940_optima_host(int address)
{
	return (unsigned char *)(unsigned long)(unsigned int)address;
}

static unsigned char *a2940_optima_block(unsigned char *host)
{
	return (unsigned char *)(unsigned long)*(unsigned int *)(host + 52);
}

int PH_CalcDataSize(int host_address, short count)
{
	(void)host_address;
	return (unsigned short)Ph_CalcOptimaSize((unsigned short)count);
}

int Ph_CalcOptimaSize(unsigned short count)
{
	if (count > 254)
		count = 254;
	return (unsigned short)(10 * (count + 1) + 1532);
}

int Ph_GetOptimaConfig(int host_address)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned short count = *(unsigned short *)(host + 66);
	int size;

	if (count == 0 || count > 254)
		count = 254;
	*(unsigned short *)(host + 66) = count;
	host[13] |= 1;
	size = Ph_CalcOptimaSize(count);
	*(unsigned short *)(host + 60) = (unsigned short)size;
	return size;
}

int Ph_OptimaIndexClearBusy(int host_address, unsigned char index)
{
	unsigned char *busy_map = a2940_optima_block(
		a2940_optima_host(host_address)) + 504;

	busy_map[index] = 0xff;
	return (int)(unsigned long)busy_map;
}

int Ph_OptimaClearTargetBusy(int host_address, unsigned char target)
{
	unsigned char *host = a2940_optima_host(host_address);
	unsigned char *block = a2940_optima_block(host);
	unsigned int scb_address = ((unsigned int *)(block + 272))[target];
	unsigned char busy_index = *(unsigned char *)(
		(unsigned long)scb_address + 12);

	return Ph_OptimaIndexClearBusy(host_address, busy_index);
}

void Ph_OptimaClearDevQue(void)
{
	/* IDA body is an empty seven-byte prologue/epilogue. */
}

int Ph_OptimaClearQinFifo(int host_address)
{
	unsigned char *qin_map = a2940_optima_block(
		a2940_optima_host(host_address)) + 496;
	int index;

	for (index = 0; index <= 255; ++index)
		qin_map[index] = 0xff;
	return (int)(unsigned long)qin_map;
}

void Ph_OptimaClearChannelBusy(void)
{
	/* IDA body is an empty seven-byte prologue/epilogue. */
}
